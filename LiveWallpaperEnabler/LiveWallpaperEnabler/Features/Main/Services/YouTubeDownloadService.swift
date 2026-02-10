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
                
                // 1. Download via YTDLP
                await updateState(id, status: "Downloading...", progress: 0.1)
                
                let downloadedFile = try await HelperServiceConnection.shared.download(
                    url: webpageURL,
                    formatID: formatString,
                    outputDirectory: downloadFolder
                ) { progress, status in
                    // Update progress if supported
                }
                
                try Task.checkCancellation()
                
                // 2. Pre-process (Convert to MOV if WebM/MKV)
                var finalPreviewURL = downloadedFile
                let ext = downloadedFile.pathExtension.lowercased()
                
                if ext == "webm" || ext == "mkv" {
                    await updateState(id, status: "Creating Preview...", progress: 0.6)
                    
                    let previewFilename = downloadedFile.deletingPathExtension().lastPathComponent + "_preview.mov"
                    let previewURL = downloadedFile.deletingLastPathComponent().appendingPathComponent(previewFilename)
                    
                    try await VideoConverterService.shared.convertToNativelyPlayable(
                        inputURL: downloadedFile,
                        outputURL: previewURL
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
                        currentIngredient.source = .youtube(metadata: metadata, localURL: finalPreviewURL)
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
                await updateState(id, status: "Failed", error: error.localizedDescription)
            }
        }
        
        downloadTasks[id] = task
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
}
