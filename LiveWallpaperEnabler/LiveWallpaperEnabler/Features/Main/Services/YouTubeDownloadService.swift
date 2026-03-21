import Foundation
import Observation

@Observable @MainActor
class YouTubeDownloadService {
    static let shared = YouTubeDownloadService()
    
    var downloadStates: [UUID: DownloadState] = [:]
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]
    
    @ObservationIgnored
    private var helperTaskIDs: [UUID: String] = [:]
    
    @ObservationIgnored
    private let store = IngredientStore.shared
    
    private init() {}
    
    func downloadVideo(ingredient: MediaIngredient, resolution: Int) {
        let id = ingredient.id
        _ = ingredient.source.youtubeMetadata
        
        let downloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LiveWallpaperDownloads", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        
        downloadTasks[id]?.cancel()
        downloadStates[id] = DownloadState(
            progress: 0.0,
            status: "Starting...",
            phase: "preparing",
            isDownloading: true
        )
        
        let task = Task {
            await performDownload(
                ingredient: ingredient,
                resolution: resolution,
                downloadFolder: downloadFolder
            )
        }
        downloadTasks[id] = task
    }
    
    private final class DownloadThrottler: @unchecked Sendable {
        var lastProgress: Double = -1.0
        var lastPhase: String = ""
    }
    
    private func performDownload(
        ingredient: MediaIngredient,
        resolution: Int,
        downloadFolder: URL
    ) async {
        let id = ingredient.id
        let metadata = ingredient.source.youtubeMetadata!
        var videoID = metadata.id
        // Sanitize videoID if it's a URL (to avoid pending_https:/... issues)
        if videoID.contains("://"), let url = URL(string: videoID) {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
                videoID = v
            } else {
                videoID = url.lastPathComponent
            }
        }
        
        // Remove any other invalid characters for filename but keep dashes and underscores
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        videoID = videoID.components(separatedBy: allowed.inverted).joined(separator: "_")
        
        let helperTaskID = UUID().uuidString
        let taskFolder = downloadFolder.appendingPathComponent("pending_\(videoID)_\(resolution)")
        try? FileManager.default.createDirectory(at: taskFolder, withIntermediateDirectories: true)
        
        await MainActor.run {
            self.helperTaskIDs[id] = helperTaskID
        }
        
        do {
            guard let webpageURL = URL(string: metadata.webpage_url) else {
                throw YTDLPError.parsingFailed
            }
            
            await updateState(id, status: "Resolving format...", phase: "preparing", progress: 0.05)
            let streams = try await availableStreams(for: ingredient, url: webpageURL)
            
            guard let stream = selectStream(from: streams, resolution: resolution) else {
                throw YouTubeDownloadError.noStreamsFound
            }
            
            let formatSelector = stream.formatID ?? "bestvideo[height<=\(resolution)]"
            let throttler = DownloadThrottler()
            
            await updateState(id, status: "Starting download...", phase: "downloading", progress: 0.1)
            
            let downloadedFile = try await HelperServiceConnection.shared.download(
                taskID: helperTaskID,
                url: webpageURL,
                formatID: formatSelector,
                outputDirectory: taskFolder,
                progressHandler: { [id, self, throttler] observation in
                    self.handleDownloadProgress(id: id, throttler: throttler, observation: observation)
                }
            )
            
            try Task.checkCancellation()
            
            await updateState(
                id,
                status: "Analyzing source...",
                phase: "analyzing",
                progress: 0.6,
                downloadedBytes: 0,
                totalBytes: 0,
                speedBytesPerSecond: 0,
                etaSeconds: nil
            )
            let originalMeta = try? await VideoMetadataAnalyzer.analyze(url: downloadedFile)
            
            await updateState(id, status: "Creating Preview...", phase: "preview", progress: 0.65)
            let previewFilename = downloadedFile.deletingPathExtension().lastPathComponent + "_preview.mp4"
            let previewURL = downloadedFile.deletingLastPathComponent().appendingPathComponent(previewFilename)
            
            // Decide whether to use FFmpeg or native AVFoundation
            let needsFFmpeg = originalMeta?.codec != "H.264" && originalMeta?.codec != "HEVC"
            
            try await VideoConverterService.shared.convertToNativelyPlayable(
                inputURL: downloadedFile,
                outputURL: previewURL,
                forceFFmpeg: needsFFmpeg
            ) { progress in
                Task { @MainActor in
                    guard var state = self.downloadStates[id] else { return }
                    state.phase = "preview"
                    state.status = "Creating Preview..."
                    state.progress = 0.65 + (progress * 0.25)
                    self.downloadStates[id] = state
                }
            }
            
            // Cleanup: Delete the original high-res download once the preview is ready
            // and move the preview out of the task folder
            let finalDestination = downloadFolder.appendingPathComponent(previewFilename)
            if FileManager.default.fileExists(atPath: finalDestination.path) {
                try? FileManager.default.removeItem(at: finalDestination)
            }
            try FileManager.default.moveItem(at: previewURL, to: finalDestination)
            let finalPreviewURL = finalDestination
            
            // Remove the source file and the temporary task folder
            try? FileManager.default.removeItem(at: downloadedFile)
            try? FileManager.default.removeItem(at: taskFolder)
            
            try Task.checkCancellation()
            
            await MainActor.run { [metadata, streams, originalMeta] in
                if var currentIngredient = self.store.ingredients.first(where: { $0.id == id }) {
                    currentIngredient.source = .youtube(metadata: metadata, localURL: finalPreviewURL, streams: streams)
                    currentIngredient.originalMetadata = originalMeta
                    self.store.update(currentIngredient)
                }
                
                self.downloadStates[id]?.phase = "finished"
                self.downloadStates[id]?.status = "Finished"
                self.downloadStates[id]?.progress = 1.0
                self.downloadStates[id]?.isDownloading = false
                self.downloadStates[id]?.downloadedBytes = 0
                self.downloadStates[id]?.totalBytes = 0
                self.downloadStates[id]?.speedBytesPerSecond = 0
                self.downloadStates[id]?.etaSeconds = nil
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            _ = await MainActor.run {
                self.downloadStates.removeValue(forKey: id)
            }
        } catch {
            if Task.isCancelled {
                _ = await MainActor.run {
                    self.downloadStates.removeValue(forKey: id)
                }
            } else {
                    let userMessage = Self.friendlyErrorMessage(for: error)
                    await MainActor.run {
                        self.downloadStates[id] = DownloadState(
                            progress: 0,
                            status: userMessage,
                            phase: "failed",
                            isDownloading: false,
                            error: error.localizedDescription
                        )
                    }
                    
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    _ = await MainActor.run {
                        self.downloadStates.removeValue(forKey: id)
                    }
                }
            }
            
            await MainActor.run {
                self.helperTaskIDs.removeValue(forKey: id)
                self.downloadTasks.removeValue(forKey: id)
            }
        }
    
    private func availableStreams(for ingredient: MediaIngredient, url: URL) async throws -> [YouTubeStreamOption] {
        if case .youtube(_, _, let streams) = ingredient.source, !streams.isEmpty {
            return streams
        }
        
        let (_, streams) = try await YouTubeDownloader.shared.fetchMetadata(url: url)
        return streams
    }
    
    private func selectStream(from streams: [YouTubeStreamOption], resolution: Int) -> YouTubeStreamOption? {
        let sortedStreams = streams.sorted {
            if $0.resolution != $1.resolution {
                return $0.resolution > $1.resolution
            }
            return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
        }
        
        return sortedStreams.first(where: { $0.resolution == resolution })
            ?? sortedStreams.first(where: { $0.resolution <= resolution })
            ?? sortedStreams.first
    }
    
    private static func downloadProgress(for observation: YTDLPDownloadObservation) -> Double {
        let clamped = min(max(observation.progress, 0), 1)
        
        switch observation.phase {
        case "download":
            return 0.1 + (clamped * 0.45)
        case "postprocess":
            return 0.55
        case "finished":
            return 0.6
        default:
            return max(0.05, clamped * 0.1)
        }
    }
    
    private static func statusText(for observation: YTDLPDownloadObservation) -> String {
        switch observation.phase {
        case "download":
            return "Downloading (\(Int(min(max(observation.progress, 0), 1) * 100))%)"
        case "postprocess":
            return "Post-processing \(observation.detail)"
        case "logging":
            return observation.detail
        case "finished":
            return "Download complete"
        default:
            return observation.detail.isEmpty ? "Preparing..." : observation.detail
        }
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
        if let taskID = helperTaskIDs[id] {
            Task {
                _ = try? await HelperServiceConnection.shared.cancelDownload(taskID: taskID)
            }
        }
        
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
        helperTaskIDs.removeValue(forKey: id)
        downloadStates.removeValue(forKey: id)
    }
    
    private func updateState(
        _ id: UUID,
        status: String,
        phase: String? = nil,
        progress: Double? = nil,
        error: String? = nil,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        speedBytesPerSecond: Double? = nil,
        etaSeconds: Double? = nil
    ) async {
        _ = await MainActor.run {
            if var state = self.downloadStates[id] {
                state.status = status
                if let phase { state.phase = phase }
                if let progress { state.progress = progress }
                if let downloadedBytes { state.downloadedBytes = downloadedBytes }
                if let totalBytes { state.totalBytes = totalBytes }
                if let speedBytesPerSecond { state.speedBytesPerSecond = speedBytesPerSecond }
                state.etaSeconds = etaSeconds
                if let error {
                    state.error = error
                    state.isDownloading = false
                }
                self.downloadStates[id] = state
            }
        }
    }
    
    private func handleDownloadProgress(id: UUID, throttler: DownloadThrottler, observation: YTDLPDownloadObservation) {
        let current: Double = YouTubeDownloadService.downloadProgress(for: observation)
        let last: Double = throttler.lastProgress
        
        let isPhaseChange = observation.phase != throttler.lastPhase
        let isSignificantProgress = (current - last) >= 0.001 || (current - last) <= -0.001
        let isFirstUpdate = last < 0.0
        
        if isPhaseChange || isSignificantProgress || isFirstUpdate {
            throttler.lastProgress = current
            throttler.lastPhase = observation.phase
            
            // This method is @MainActor, so we might need a Task if handleDownloadProgress 
            // is called from a non-main context, but HelperServiceConnection relay does it on MainActor.
            self.updateDownloadState(id: id, observation: observation, progress: current)
        }
    }
    
    @MainActor
    private func updateDownloadState(id: UUID, observation: YTDLPDownloadObservation, progress: Double) {
        if var state = self.downloadStates[id] {
            state.phase = observation.phase
            state.status = YouTubeDownloadService.statusText(for: observation)
            state.progress = progress
            state.downloadedBytes = observation.downloadedBytes
            state.totalBytes = observation.totalBytes
            state.speedBytesPerSecond = observation.speedBytesPerSecond
            state.etaSeconds = observation.etaSeconds
            self.downloadStates[id] = state
        }
    }
}
