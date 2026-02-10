import Foundation

/// Infrastructure service that manages binary dependencies via Homebrew Formulae API
class BinaryManager: NSObject {
    static let shared = BinaryManager()
    private let fileManager = FileManager.default
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: SecureSessionDelegate(), delegateQueue: nil)
    }()
    
    private override init() {
        super.init()
    }
    
    enum BinaryAsset: String {
        case ytdlp = "yt-dlp"
        case deno = "deno"
        
        var formulaURL: URL {
            return URL(string: "https://formulae.brew.sh/api/formula/\(self.rawValue).json")!
        }
        
        var defaultPaths: [String] {
            switch self {
            case .ytdlp: return ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
            case .deno: return ["/opt/homebrew/bin/deno", "/usr/local/bin/deno"]
            }
        }
    }
    
    // MARK: - Homebrew API Models
    struct FormulaJSON: Codable {
        let name: String
        let versions: VersionInfo
        let bottle: BottleInfo
        
        struct VersionInfo: Codable {
            let stable: String
        }
        
        struct BottleInfo: Codable {
            let stable: StableInfo
        }
        
        struct StableInfo: Codable {
            let files: [String: BottleFile]
        }
        
        struct BottleFile: Codable {
            let url: URL
            let sha256: String
        }
    }
    
    func getBinaryURL(_ asset: BinaryAsset) -> URL? {
        for path in asset.defaultPaths {
            if fileManager.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        let appSupportBin = getAppSupportBinURL().appendingPathComponent(asset.rawValue)
        if fileManager.fileExists(atPath: appSupportBin.path) {
            return appSupportBin
        }
        
        return nil
    }
    
    func ensureBinaryExists(_ asset: BinaryAsset) async throws -> URL {
        print("      [BinaryManager] Checking \(asset.rawValue)...")
        
        let formula = try await fetchFormulaInfo(asset)
        let remoteVersion = formula.versions.stable
        let localVersion = getStoredVersion(for: asset)
        
        if let existing = getBinaryURL(asset), localVersion == remoteVersion { 
            print("      [BinaryManager] \(asset.rawValue) up to date (\(localVersion ?? "unknown"))")
            return existing 
        }
        
        if localVersion != remoteVersion {
            print("      [BinaryManager] Update available: \(localVersion ?? "none") -> \(remoteVersion)")
        } else {
            print("      [BinaryManager] \(asset.rawValue) not found locally.")
        }
        
        let downloadURL = try await resolveBottleURL(from: formula)
        let binFolder = getAppSupportBinURL()
        let targetURL = binFolder.appendingPathComponent(asset.rawValue)
        try fileManager.createDirectory(at: binFolder, withIntermediateDirectories: true)
        
        if asset == .ytdlp {
            // yt-dlp special case: Single file download from GitHub
            print("      [BinaryManager] Downloading standalone yt-dlp binary...")
            let (tempURL, _) = try await session.download(from: downloadURL)
            
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: tempURL, to: targetURL)
        } else {
            // Deno and others: Homebrew bottle (tar.gz)
            print("      [BinaryManager] Requesting GHCR token...")
            let token = try await fetchGHCRToken(for: asset)
            
            print("      [BinaryManager] Downloading updated bottle with auth...")
            var request = URLRequest(url: downloadURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (tempURL, _) = try await session.download(for: request)
            try extractBinaryFromBottle(at: tempURL, asset: asset, to: targetURL)
        }
        
        // Save version info
        storeVersion(remoteVersion, for: asset)
        
        // Add execution permission (+x)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["755", targetURL.path]
        try chmod.run()
        chmod.waitUntilExit()
        
        return targetURL
    }
    
    private func fetchFormulaInfo(_ asset: BinaryAsset) async throws -> FormulaJSON {
        let (data, _) = try await session.data(from: asset.formulaURL)
        return try JSONDecoder().decode(FormulaJSON.self, from: data)
    }
    
    private func fetchGHCRToken(for asset: BinaryAsset) async throws -> String {
        let url = URL(string: "https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/\(asset.rawValue):pull")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct TokenResponse: Codable {
            let token: String
        }
        
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        return response.token
    }
    
    private func resolveBottleURL(from formula: FormulaJSON) async throws -> URL {
        // Special case for yt-dlp: Homebrew bottles are just Python scripts.
        // We need the standalone universal binary from GitHub Releases.
        if formula.name == "yt-dlp" {
            // Fetch latest release tag or use version from formula
            return URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        }
        
        if formula.name == "deno" {
            let arch = ProcessInfo.processInfo.machineArchitecture == "arm64" ? "aarch64" : "x86_64"
            // Use a specific stable version known to be standalone compatible
            let version = "2.6.6" 
            return URL(string: "https://github.com/denoland/deno/releases/download/v\(version)/deno-\(arch)-apple-darwin.zip")!
        }
        
        let archPrefix = ProcessInfo.processInfo.machineArchitecture == "arm64" ? "arm64_" : ""
        let osVersion = getMacOSVersionName()
        
        let platformKey = "\(archPrefix)\(osVersion)"
        
        if let file = formula.bottle.stable.files[platformKey] {
            return file.url
        }
        
        // Fallback logic...
        
        // Fallback to most recent OS if exact match fails
        let fallbacks = ["sequoia", "sonoma", "ventura", "monterey", "big_sur"]
        for version in fallbacks {
            let key = "\(archPrefix)\(version)"
            if let file = formula.bottle.stable.files[key] {
                print("      [BinaryManager] exact match failed, using fallback: \(key)")
                return file.url
            }
        }
        
        throw NSError(domain: "BinaryManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No suitable bottle found for your macOS version"])
    }
    
    private func extractBinaryFromBottle(at source: URL, asset: BinaryAsset, to destination: URL) throws {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 1. Extract (Untar or Unzip)
        if source.pathExtension == "zip" {
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", source.path, "-d", tempDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
        } else {
            let tarProcess = Process()
            tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tarProcess.arguments = ["-xzf", source.path, "-C", tempDir.path]
            try tarProcess.run()
            tarProcess.waitUntilExit()
        }
        
        // 2. Locate the binary inside the bottle structure
        // Bottle structure: name/version/bin/binary
        let enumerator = fileManager.enumerator(at: tempDir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        var bestMatch: (url: URL, size: UInt64)?
        
        while let file = enumerator?.nextObject() as? URL {
            let resourceValues = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if resourceValues?.isRegularFile ?? false && file.lastPathComponent == asset.rawValue && !file.path.contains(".brew") {
                let fileSize = UInt64(resourceValues?.fileSize ?? 0)
                if bestMatch == nil || fileSize > bestMatch!.size {
                    bestMatch = (file, fileSize)
                }
            }
        }
        
        if let match = bestMatch {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: match.url, to: destination)
            return
        }
        
        throw NSError(domain: "BinaryManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Binary \(asset.rawValue) not found in extracted bottle"])
    }
    
    func getBinaryStatus(_ asset: BinaryAsset) -> [String: String] {
        let url = getBinaryURL(asset)
        let version = getStoredVersion(for: asset) ?? "unknown"
        return [
            "path": url?.path ?? "none",
            "version": version,
            "exists": url != nil ? "true" : "false"
        ]
    }
    
    private func getStoredVersion(for asset: BinaryAsset) -> String? {
        UserDefaults.standard.string(forKey: "binary_version_\(asset.rawValue)")
    }
    
    private func storeVersion(_ version: String, for asset: BinaryAsset) {
        UserDefaults.standard.set(version, forKey: "binary_version_\(asset.rawValue)")
    }
    
    private func getAppSupportBinURL() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LiveWallpaperEnabler/bin", isDirectory: true)
    }
    
    private func getMacOSVersionName() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        switch version.majorVersion {
        case 15: return "sequoia"
        case 14: return "sonoma"
        case 13: return "ventura"
        case 12: return "monterey"
        case 11: return "big_sur"
        default: return "sonoma" // Reasonable default
        }
    }
}

import os

// MARK: - SSL Pinning Delegate
class SecureSessionDelegate: NSObject, URLSessionDelegate {
    private let logger = Logger(subsystem: "com.k2zoo.LiveWallpaperEnabler.Helper", category: "Security")
    
    // Pins for formulae.brew.sh
    // 1. Current Certificate Data Hash (SHA256)
    private let pinnedCertHash = "k7W6Y8k8Yq5zFm1X6X9k8Yq5zFm1X6X9k8Yq5zFm1X6=" // Placeholder, will fix below
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        if challenge.protectionSpace.host == "formulae.brew.sh" {
            if validate(serverTrust: serverTrust) {
                logger.info("✅ SSL Pinning Successful for formulae.brew.sh")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                logger.error("❌ SSL Pinning FAILED for formulae.brew.sh")
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    private func validate(serverTrust: SecTrust) -> Bool {
        guard let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let certificate = certificates.first,
              let publicKey = SecCertificateCopyKey(certificate),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return false
        }
        
        let currentHash = CryptoHelper.sha256(data: publicKeyData).base64EncodedString()
        
        // Updated pinned hashes:
        // 1. SPKI Hash (from openssl)
        let spkiHash = "DQc7m3O0sO4W4/WA5SHHtseqIKSKdkp1jhsx3/UEPZA="
        // 2. Raw Public Key Data Hash (as reported by the user's system)
        let rawHash = "WMmyqmjmpUjM2CvoQrK/f75FZmiLXaH4sLwyCb7pB+o="
        
        return currentHash == rawHash || currentHash == spkiHash
    }
}

// MARK: - Crypto Helper
import CommonCrypto
struct CryptoHelper {
    static func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

extension ProcessInfo {
    var machineArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { buf in
            String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return machine == "arm64" ? "arm64" : "x86_64"
    }
}
