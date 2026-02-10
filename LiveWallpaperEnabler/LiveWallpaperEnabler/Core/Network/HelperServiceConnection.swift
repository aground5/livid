import Foundation
import os

enum YTDLPError: Error, LocalizedError {
    case binaryNotFound
    case executionFailed(code: Int, message: String)
    case parsingFailed
    case jsonDecodingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "yt-dlp binary not found in application bundle."
        case .executionFailed(let code, let msg): return "Helper failed (code \(code)): \(msg)"
        case .parsingFailed: return "Failed to parse helper output."
        case .jsonDecodingFailed(let err): return "Failed to decode metadata: \(err.localizedDescription)"
        }
    }
}

@MainActor
class HelperServiceConnection {
    static let shared = HelperServiceConnection()
    private let logger = Logger(subsystem: "com.livewallpaper.enabler", category: "HelperConnection")
    
    // Check Info.plist of Helper App for this exact ID
    private let serviceBundleID = "com.mitocondria.LiveWallpaperHelper"
    
    // In-memory connection cache
    private var connection: NSXPCConnection?
    
    private func getXPCConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }
        
        let newConnection = NSXPCConnection(machServiceName: serviceBundleID, options: [])
        newConnection.remoteObjectInterface = NSXPCInterface(with: LiveWallpaperHelperProtocol.self)
        
        newConnection.interruptionHandler = {
            print("XPC Connection Interrupted")
        }
        
        newConnection.invalidationHandler = {
            print("XPC Connection Invalidated")
            Task { @MainActor in
                self.connection = nil
            }
        }
        
        newConnection.resume()
        self.connection = newConnection
        return newConnection
    }
    
    // MARK: - YouTube Download Features

    func fetchMetadata(url: URL) async throws -> YTDLPMetadata {
        let connection = getXPCConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                print("XPC Remote Proxy Error: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
            
            guard let service = proxy as? LiveWallpaperHelperProtocol else {
                continuation.resume(throwing: YTDLPError.executionFailed(code: -1, message: "XPC Service not available"))
                return
            }
            
            service.fetchMetadata(url: url) { jsonString, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = jsonString?.data(using: .utf8) else {
                    continuation.resume(throwing: YTDLPError.parsingFailed)
                    return
                }
                
                do {
                    // Swift 6: JSONDecoder().decode is nonisolated, models are Sendable.
                    let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: data)
                    continuation.resume(returning: metadata)
                } catch {
                    continuation.resume(throwing: YTDLPError.jsonDecodingFailed(error))
                }
            }
        }
    }
    
    func download(url: URL, formatID: String? = nil, outputDirectory: URL, progressHandler: @escaping (Double, String) -> Void) async throws -> URL {
        let connection = getXPCConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                print("XPC Remote Proxy Error: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
            
            guard let service = proxy as? LiveWallpaperHelperProtocol else {
                continuation.resume(throwing: YTDLPError.executionFailed(code: -1, message: "XPC Service not available"))
                return
            }
            
            service.downloadVideo(url: url, formatID: formatID, outputDirectoryURL: outputDirectory) { fileURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let fileURL = fileURL {
                    continuation.resume(returning: fileURL)
                } else {
                    continuation.resume(throwing: YTDLPError.executionFailed(code: 0, message: "Download failed without error"))
                }
            }
        }
    }
    
}
