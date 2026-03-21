import Foundation
import os

enum YTDLPError: Error, LocalizedError {
    case binaryNotFound
    case executionFailed(code: Int, message: String)
    case parsingFailed
    case jsonDecodingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "yt-dlp runtime not found in the packaged standalone bundle."
        case .executionFailed(let code, let msg):
            return "Helper failed (code \(code)): \(msg)"
        case .parsingFailed:
            return "Failed to parse helper output."
        case .jsonDecodingFailed(let err):
            return "Failed to decode metadata: \(err.localizedDescription)"
        }
    }
}

struct YTDLPDownloadObservation: Sendable {
    let taskID: String
    let phase: String
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64
    let speedBytesPerSecond: Double
    let etaSeconds: Double?
    let detail: String
}

private final class DownloadProgressRelay: NSObject, LiveWallpaperDownloadObserverProtocol {
    weak var owner: HelperServiceConnection?
    
    init(owner: HelperServiceConnection) {
        self.owner = owner
    }
    
    func downloadDidUpdate(
        taskID: String,
        phase: String,
        progress: Double,
        downloadedBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSecond: Double,
        etaSeconds: Double,
        detail: String
    ) {
        Task { @MainActor in
            owner?.handleProgress(
                taskID: taskID,
                phase: phase,
                progress: progress,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                speedBytesPerSecond: speedBytesPerSecond,
                etaSeconds: etaSeconds >= 0 ? etaSeconds : nil,
                detail: detail
            )
        }
    }
}

@MainActor
class HelperServiceConnection {
    static let shared = HelperServiceConnection()
    
    private let logger = Logger(subsystem: "com.livewallpaper.enabler", category: "HelperConnection")
    private let serviceBundleID = "com.mitocondria.LiveWallpaperHelper"
    private var hasLoggedBundleDiagnostics = false
    
    private lazy var progressRelay = DownloadProgressRelay(owner: self)
    private var progressHandlers: [String: (YTDLPDownloadObservation) -> Void] = [:]
    private var connection: NSXPCConnection?
    
    private func configuredRemoteInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: LiveWallpaperHelperProtocol.self)
        let observerInterface = NSXPCInterface(with: LiveWallpaperDownloadObserverProtocol.self)
        interface.setInterface(
            observerInterface,
            for: #selector(LiveWallpaperHelperProtocol.downloadVideo(taskID:url:formatID:outputDirectoryURL:observer:withReply:)),
            argumentIndex: 4,
            ofReply: false
        )
        return interface
    }

    private func logServiceBundleDiagnostics(reason: String, force: Bool = false) {
        guard force || !hasLoggedBundleDiagnostics else { return }
        hasLoggedBundleDiagnostics = true

        let appBundleURL = Bundle.main.bundleURL
        let serviceBundleURL = appBundleURL
            .appendingPathComponent("Contents/XPCServices", isDirectory: true)
            .appendingPathComponent("\(serviceBundleID).xpc", isDirectory: true)
        let infoPlistURL = serviceBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)

        let fileManager = FileManager.default
        let serviceBundleExists = fileManager.fileExists(atPath: serviceBundleURL.path)
        let executableExists = fileManager.fileExists(
            atPath: serviceBundleURL
                .appendingPathComponent("Contents/MacOS/\(serviceBundleID)", isDirectory: false)
                .path
        )

        let infoPlist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
        let packageType = infoPlist?["CFBundlePackageType"] as? String ?? "<missing>"
        let serviceType = (infoPlist?["XPCService"] as? [String: Any])?["ServiceType"] as? String ?? "<missing>"

        logger.info(
            """
            XPC diagnostics [\(reason, privacy: .public)] appBundle=\(appBundleURL.path, privacy: .public) \
            serviceBundle=\(serviceBundleURL.path, privacy: .public) exists=\(serviceBundleExists, privacy: .public) \
            executableExists=\(executableExists, privacy: .public) packageType=\(packageType, privacy: .public) \
            serviceType=\(serviceType, privacy: .public)
            """
        )
    }
    
    private func getXPCConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }
        
        logServiceBundleDiagnostics(reason: "before-connect")
        logger.info("Creating XPC connection to bundled helper \(self.serviceBundleID, privacy: .public)")
        let newConnection = NSXPCConnection(serviceName: serviceBundleID)
        newConnection.remoteObjectInterface = configuredRemoteInterface()
        newConnection.exportedInterface = NSXPCInterface(with: LiveWallpaperDownloadObserverProtocol.self)
        newConnection.exportedObject = progressRelay
        
        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.logger.error("XPC connection interrupted")
            }
        }
        
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.logServiceBundleDiagnostics(reason: "after-invalidation", force: true)
                self?.logger.error("XPC connection invalidated")
                self?.connection = nil
                self?.progressHandlers.removeAll()
            }
        }
        
        newConnection.resume()
        connection = newConnection
        return newConnection
    }
    
    func fetchMetadata(url: URL) async throws -> YTDLPMetadata {
        let connection = getXPCConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                self.logServiceBundleDiagnostics(reason: "fetch-metadata-error", force: true)
                self.logger.error("XPC fetchMetadata proxy error: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
            
            guard let service = proxy as? LiveWallpaperHelperProtocol else {
                continuation.resume(throwing: YTDLPError.executionFailed(code: -1, message: "XPC service not available"))
                return
            }
            
            service.fetchMetadata(url: url) { jsonString, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = jsonString?.data(using: .utf8) else {
                    continuation.resume(throwing: YTDLPError.parsingFailed)
                    return
                }
                
                do {
                    let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: data)
                    continuation.resume(returning: metadata)
                } catch {
                    continuation.resume(throwing: YTDLPError.jsonDecodingFailed(error))
                }
            }
        }
    }
    
    func download(
        taskID: String,
        url: URL,
        formatID: String? = nil,
        outputDirectory: URL,
        progressHandler: @escaping (YTDLPDownloadObservation) -> Void
    ) async throws -> URL {
        let connection = getXPCConnection()
        progressHandlers[taskID] = progressHandler
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                Task { @MainActor in
                    self?.logServiceBundleDiagnostics(reason: "download-error", force: true)
                    self?.logger.error("XPC download proxy error for task \(taskID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self?.progressHandlers.removeValue(forKey: taskID)
                }
                continuation.resume(throwing: error)
            }
            
            guard let service = proxy as? LiveWallpaperHelperProtocol else {
                progressHandlers.removeValue(forKey: taskID)
                continuation.resume(throwing: YTDLPError.executionFailed(code: -1, message: "XPC service not available"))
                return
            }
            
            service.downloadVideo(
                taskID: taskID,
                url: url,
                formatID: formatID,
                outputDirectoryURL: outputDirectory,
                observer: progressRelay
            ) { [weak self] fileURL, error in
                Task { @MainActor in
                    self?.progressHandlers.removeValue(forKey: taskID)
                }
                
                if let error {
                    continuation.resume(throwing: error)
                } else if let fileURL {
                    continuation.resume(returning: fileURL)
                } else {
                    continuation.resume(throwing: YTDLPError.executionFailed(code: 0, message: "Download failed without error"))
                }
            }
        }
    }
    
    func cancelDownload(taskID: String) async throws -> Bool {
        let connection = getXPCConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                self.logServiceBundleDiagnostics(reason: "cancel-error", force: true)
                self.logger.error("XPC cancel proxy error for task \(taskID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
            
            guard let service = proxy as? LiveWallpaperHelperProtocol else {
                continuation.resume(throwing: YTDLPError.executionFailed(code: -1, message: "XPC service not available"))
                return
            }
            
            service.cancelDownload(taskID: taskID) { cancelled in
                continuation.resume(returning: cancelled)
            }
        }
    }
    
    func checkHealth() async throws -> String {
        let connection = getXPCConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                self.logServiceBundleDiagnostics(reason: "health-check-error", force: true)
                self.logger.error("XPC health proxy error: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
            
            guard let service = proxy as? LiveWallpaperHelperProtocol else {
                continuation.resume(throwing: YTDLPError.executionFailed(code: -1, message: "XPC service not available"))
                return
            }
            
            service.checkHealth { payload in
                continuation.resume(returning: payload)
            }
        }
    }
    
    fileprivate func handleProgress(
        taskID: String,
        phase: String,
        progress: Double,
        downloadedBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSecond: Double,
        etaSeconds: Double?,
        detail: String
    ) {
        guard let handler = progressHandlers[taskID] else {
            return
        }
        
        handler(
            YTDLPDownloadObservation(
                taskID: taskID,
                phase: phase,
                progress: progress,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                speedBytesPerSecond: speedBytesPerSecond,
                etaSeconds: etaSeconds,
                detail: detail
            )
        )
    }
}
