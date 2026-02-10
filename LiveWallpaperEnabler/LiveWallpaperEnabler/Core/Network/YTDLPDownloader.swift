import Foundation
import os

enum YTDLPDownloaderError: Error, LocalizedError {
    case invalidURL
    case downloadFailed(Int)
    case architectureDetectionFailed
    case homebrewFormulaParsingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL for yt-dlp download."
        case .downloadFailed(let code): return "Download failed with status code: \(code)."
        case .architectureDetectionFailed: return "Failed to detect system architecture."
        case .homebrewFormulaParsingFailed: return "Failed to parse Homebrew formula information."
        }
    }
}

actor YTDLPDownloader {
    static let shared = YTDLPDownloader()
    private let logger = Logger(subsystem: "com.mitocondria.LiveWallpaperEnabler", category: "YTDLPDownloader")
    
    private let formulaURL = URL(string: "https://formulae.brew.sh/api/formula/yt-dlp.json")!
    
    /// Architecture of the running machine
    enum Architecture: String {
        case arm64
        case x86_64
        
        static var current: Architecture? {
            #if arch(arm64)
            return .arm64
            #elseif arch(x86_64)
            return .x86_64
            #else
            return nil
            #endif
        }
    }
    
    /// Returns the expected Homebrew path for yt-dlp based on architecture
    var homebrewBinaryPath: URL? {
        guard let arch = Architecture.current else { return nil }
        let basePath = (arch == .arm64) ? "/opt/homebrew/bin" : "/usr/local/bin"
        return URL(fileURLWithPath: basePath).appendingPathComponent("yt-dlp")
    }
    
    /// Checks if yt-dlp is available in the system (Homebrew)
    func checkSystemInstallation() -> URL? {
        if let path = homebrewBinaryPath, FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        return nil
    }
    
    /// Fetches the latest version string from Homebrew Formula API
    func fetchLatestVersion() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: formulaURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let versions = json?["versions"] as? [String: Any],
              let stable = versions["stable"] as? String else {
            throw YTDLPDownloaderError.homebrewFormulaParsingFailed
        }
        return stable
    }
    
    /// Fetches the local version of yt-dlp by running --version
    func getLocalVersion(at binaryURL: URL) async -> String? {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    /// Checks if an update is available for the given local binary
    func checkForUpdate(localBinaryURL: URL) async throws -> (isUpdateAvailable: Bool, latestVersion: String) {
        let latestVersion = try await fetchLatestVersion()
        guard let localVersion = await getLocalVersion(at: localBinaryURL) else {
            return (true, latestVersion) // Assume update needed if we can't get local version
        }
        
        // Simple string comparison for yt-dlp versions (usually YYYY.MM.DD)
        return (localVersion < latestVersion, latestVersion)
    }

    /// Downloads yt-dlp to the specified destination
    func downloadLatest(to destination: URL, progressHandler: @escaping (Double) -> Void) async throws {
        let version = try await fetchLatestVersion()
        try await downloadVersion(version, to: destination, progressHandler: progressHandler)
    }
    
    private func downloadVersion(_ version: String, to destination: URL, progressHandler: @escaping (Double) -> Void) async throws {
        // yt-dlp_macos is a universal binary
        let downloadURLString = "https://github.com/yt-dlp/yt-dlp/releases/download/\(version)/yt-dlp_macos"
        guard let downloadURL = URL(string: downloadURLString) else {
            throw YTDLPDownloaderError.invalidURL
        }
        
        logger.info("Downloading yt-dlp version \(version) from \(downloadURLString)")
        
        let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw YTDLPDownloaderError.downloadFailed(code)
        }
        
        // Ensure destination directory exists
        let destDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        
        // Move to destination
        try FileManager.default.moveItem(at: tempURL, to: destination)
        
        // Set executable permissions (0755)
        var attributes = [FileAttributeKey : Any]()
        attributes[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attributes, ofItemAtPath: destination.path)
        
        logger.info("Successfully installed yt-dlp version \(version) to \(destination.path)")
    }
}
