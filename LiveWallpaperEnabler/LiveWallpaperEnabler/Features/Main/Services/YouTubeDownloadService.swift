import Foundation
import Observation
import AVFoundation

@Observable
class YouTubeDownloadService {
    static let shared = YouTubeDownloadService()
    
    var downloadStates: [UUID: DownloadState] = [:]
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]
    
    @ObservationIgnored
    private let store = IngredientStore.shared
    
    private init() {}
    
    /// Main entry point for starting a YouTube download.
    func downloadVideo(ingredient: MediaIngredient, resolution: Int) {
        let id = ingredient.id
        guard let metadata = ingredient.source.youtubeMetadata else { return }
        
        // Define format string (No Audio)
        let formatString = "bestvideo[height<=\(resolution)]"
        
        // Setup download path
        let downloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LiveWallpaperDownloads", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        
        // Cancel existing task if any
        downloadTasks[id]?.cancel()
        
        // Initialize State
        downloadStates[id] = DownloadState(progress: 0.0, status: "Starting...", isDownloading: true)
        
        let task = Task {
            do {
                guard let webpageURL = URL(string: metadata.webpage_url) else { 
                    throw YTDLPError.parsingFailed 
                }
                
                await updateState(id, status: "Fetching Stream Info...", progress: 0.05)
                
                let (_, streams) = try await YouTubeDownloader.shared.fetchMetadata(url: webpageURL)
                
                // Find best stream matching resolution
                guard let stream = streams.first(where: { $0.resolution <= resolution }) ?? streams.first else {
                    throw YouTubeDownloadError.noStreamsFound
                }
                
                await updateState(id, status: "Downloading...", progress: 0.1)
                
                let fileURL = downloadFolder.appendingPathComponent("\(UUID().uuidString).\(stream.fileExtension)")
                try await downloadFileWithProgress(url: stream.url, destination: fileURL, id: id)
                
                let downloadedFile = fileURL
                try Task.checkCancellation()
                
                // 2a. Analyze ORIGINAL file metadata BEFORE preview conversion
                //     This preserves the true source specs (e.g., 4K) even if preview is FHD.
                await updateState(id, status: "Analyzing source...", progress: 0.55)
                let originalMeta = try? await VideoMetadataAnalyzer.analyze(url: downloadedFile)
                
                // 2b. Pre-process (Convert to MOV always)
                var finalPreviewURL = downloadedFile
                let ext = downloadedFile.pathExtension.lowercased()
                
                // YouTube DASH MP4s often have malformed timescales/sidx boxes causing AVFoundation
                // to report exactly double their actual duration. Passing them through the native
                // AVAssetReader/Writer or FFmpeg pipeline normalizes the metadata and duration.
                if true {
                    await updateState(id, status: "Creating Preview...", progress: 0.6)
                    
                    let previewFilename = downloadedFile.deletingPathExtension().lastPathComponent + "_preview.mov"
                    let previewURL = downloadedFile.deletingLastPathComponent().appendingPathComponent(previewFilename)
                    
                    try await VideoConverterService.shared.convertToNativelyPlayable(
                        inputURL: downloadedFile,
                        outputURL: previewURL,
                        forceFFmpeg: true
                    ) { progress in
                        Task { @MainActor in
                            self.downloadStates[id]?.progress = 0.6 + (progress * 0.3)
                        }
                    }
                    finalPreviewURL = previewURL
                }
                
                try Task.checkCancellation()
                
                // 3. Success - Update Ingredient & Store
                _ = await MainActor.run {
                    if var currentIngredient = self.store.ingredients.first(where: { $0.id == id }) {
                        // Preserve existing streams
                        let existingStreams: [YouTubeStreamOption]
                        if case .youtube(_, _, let streams) = currentIngredient.source {
                            existingStreams = streams
                        } else {
                            existingStreams = []
                        }
                        currentIngredient.source = .youtube(metadata: metadata, localURL: finalPreviewURL, streams: existingStreams)
                        currentIngredient.originalMetadata = originalMeta
                        self.store.update(currentIngredient)
                    }
                    
                    self.downloadStates[id]?.status = "Finished"
                    self.downloadStates[id]?.progress = 1.0
                    self.downloadStates[id]?.isDownloading = false
                    
                    // Trigger initial metadata load and thumbnail in ViewModel context if possible
                    // However, service should be self-contained for data.
                    // ViewModel will observe the update via store.
                }
                
                // Cleanup state after delay
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                _ = await MainActor.run {
                    self.downloadStates.removeValue(forKey: id)
                }
                
            } catch is CancellationError {
                _ = await MainActor.run { self.downloadStates.removeValue(forKey: id) }
            } catch {
                let userMessage = Self.friendlyErrorMessage(for: error)
                await MainActor.run {
                    self.downloadStates[id] = DownloadState(
                        progress: 0,
                        status: userMessage,
                        isDownloading: false,
                        error: error.localizedDescription
                    )
                }
                
                // Auto-cleanup failed state after 5 seconds
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                _ = await MainActor.run {
                    self.downloadStates.removeValue(forKey: id)
                }
            }
        }
        
        downloadTasks[id] = task
    }
    
    private static func friendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "Download timed out. Please try again."
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection."
        case NSURLErrorNetworkConnectionLost:
            return "Connection lost during download."
        case NSURLErrorCancelled:
            return "Download cancelled."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Server unreachable. Try again later."
        case NSURLErrorSecureConnectionFailed:
            return "Secure connection failed."
        default:
            if nsError.domain == NSURLErrorDomain {
                return "Network error. Please try again."
            }
            return "Download failed: \(error.localizedDescription)"
        }
    }
    
    func cancelDownload(for id: UUID) {
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
        downloadStates.removeValue(forKey: id)
    }
    
    private func updateState(_ id: UUID, status: String, progress: Double? = nil, error: String? = nil) async {
        _ = await MainActor.run {
            if var state = self.downloadStates[id] {
                state.status = status
                if let p = progress { state.progress = p }
                if let e = error { 
                    state.error = e
                    state.isDownloading = false
                }
                self.downloadStates[id] = state
            }
        }
    }
    
    private func downloadFileWithProgress(url: URL, destination: URL, id: UUID) async throws {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let expectedLength = response.expectedContentLength
        
        guard let outputStream = OutputStream(url: destination, append: false) else {
            throw NSLocalizedString("Unable to create output stream.", comment: "") as! Error
        }
        outputStream.open()
        
        defer {
            outputStream.close()
        }
        
        var downloadedBytes: Int64 = 0
        var buffer = [UInt8]()
        buffer.reserveCapacity(65536)
        
        var nextProgressUpdate: Int64 = 1024 * 512 // Every 512KB to prevent too many re-renders
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                let written = outputStream.write(buffer, maxLength: buffer.count)
                if written < 0 { throw outputStream.streamError ?? YTDLPError.executionFailed(code: -1, message: "Stream write failed") }
                downloadedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                
                try Task.checkCancellation()
                
                if downloadedBytes >= nextProgressUpdate {
                    let progress = Double(downloadedBytes) / Double(expectedLength)
                    await updateState(id, status: "Downloading (\(Int(progress * 100))%)", progress: 0.1 + (progress * 0.5))
                    nextProgressUpdate += 1024 * 512
                }
            }
        }
        
        if !buffer.isEmpty {
            let written = outputStream.write(buffer, maxLength: buffer.count)
            if written < 0 { throw outputStream.streamError ?? YTDLPError.executionFailed(code: -1, message: "Stream write failed") }
        }
    }
}
