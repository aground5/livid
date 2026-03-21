import Foundation

/// Pure locator for already-present runtime binaries.
class BinaryManager: NSObject {
    static let shared = BinaryManager()
    
    private let fileManager = FileManager.default
    private let packagedPythonDistributionName = "cpython-3.13.9-macos-aarch64-none"
    
    private override init() {
        super.init()
    }
    
    enum BinaryAsset: String {
        case ytdlp = "yt-dlp"
    }
    
    func getBinaryURL(_ asset: BinaryAsset) -> URL? {
        existingExecutableURL(from: candidateURLs(for: asset))
    }
    
    func ensureBinaryExists(_ asset: BinaryAsset) async throws -> URL {
        guard let binaryURL = getBinaryURL(asset) else {
            throw NSError(
                domain: "BinaryManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Required binary not found: \(asset.rawValue)"]
            )
        }
        return binaryURL
    }
    
    func getBinaryStatus(_ asset: BinaryAsset) -> [String: String] {
        let url = getBinaryURL(asset)
        return [
            "path": url?.path ?? "none",
            "version": url != nil ? "packaged" : "missing",
            "exists": url != nil ? "true" : "false",
        ]
    }
    
    func pythonRuntimeURL(forYTDLPBinary binaryURL: URL) -> URL? {
        let pythonURL = binaryURL.deletingLastPathComponent().appendingPathComponent("python3")
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            return nil
        }
        return pythonURL
    }
    
    private func candidateURLs(for asset: BinaryAsset) -> [URL] {
        switch asset {
        case .ytdlp:
            return packagedYTDLPCandidates()
        }
    }
    
    private func packagedYTDLPCandidates() -> [URL] {
        var candidates: [URL] = []
        
        for root in packagedToolRootCandidates() {
            candidates.append(root.appendingPathComponent("bin/yt-dlp"))
        }
        
        candidates.append(contentsOf: workspacePackageCandidates(startingAtPath: Bundle.main.bundleURL.path))
        candidates.append(contentsOf: workspacePackageCandidates(startingAtPath: fileManager.currentDirectoryPath))
        
        return uniqueURLs(candidates)
    }
    
    private func packagedToolRootCandidates() -> [URL] {
        var roots: [URL] = []
        
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL.appendingPathComponent(packagedPythonDistributionName, isDirectory: true))
            roots.append(resourceURL.appendingPathComponent("python-runtime/\(packagedPythonDistributionName)", isDirectory: true))
            roots.append(resourceURL.appendingPathComponent("py-standalone/\(packagedPythonDistributionName)", isDirectory: true))
        }
        
        if let appBundle = containingAppBundle(startingAt: Bundle.main.bundleURL) {
            let appResources = appBundle.appendingPathComponent("Contents/Resources", isDirectory: true)
            roots.append(appResources.appendingPathComponent(packagedPythonDistributionName, isDirectory: true))
            roots.append(appResources.appendingPathComponent("python-runtime/\(packagedPythonDistributionName)", isDirectory: true))
            roots.append(appResources.appendingPathComponent("py-standalone/\(packagedPythonDistributionName)", isDirectory: true))
        }
        
        return uniqueURLs(roots)
    }
    
    private func containingAppBundle(startingAt url: URL) -> URL? {
        var currentURL: URL? = url
        while let candidate = currentURL {
            if candidate.pathExtension == "app" {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            currentURL = parent.path == candidate.path ? nil : parent
        }
        return nil
    }
    
    private func existingExecutableURL(from candidates: [URL]) -> URL? {
        candidates.first { candidate in
            fileManager.isExecutableFile(atPath: candidate.path)
        }
    }
    
    private func workspacePackageCandidates(startingAtPath path: String) -> [URL] {
        guard !path.isEmpty else {
            return []
        }
        
        var candidates: [URL] = []
        var currentPath = (path as NSString).standardizingPath
        
        while !currentPath.isEmpty {
            let currentURL = URL(fileURLWithPath: currentPath, isDirectory: true)
            candidates.append(
                currentURL.appendingPathComponent("Packages/\(packagedPythonDistributionName)/bin/yt-dlp")
            )
            
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath == currentPath || parentPath.isEmpty {
                break
            }
            currentPath = parentPath
        }
        
        return candidates
    }
    
    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}
