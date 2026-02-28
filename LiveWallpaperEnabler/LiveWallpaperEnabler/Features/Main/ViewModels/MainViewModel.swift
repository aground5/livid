import Foundation
import SwiftUI
import AppKit
import Observation
import os
import UniformTypeIdentifiers
import AVFoundation

enum AppTab: String, CaseIterable {
    case prepare = "Prepare"
    case edit = "Trim"
    case render = "Render"
    case library = "Library"
    case catalog = "Catalog"
    
    var icon: String {
        switch self {
        case .prepare: return "video.badge.plus"
        case .edit: return "scissors"
        case .render: return "cpu"
        case .library: return "square.grid.2x2.fill"
        case .catalog: return "square.grid.3x3.fill"
        }
    }
}

// Media types moved to Core/Models/MediaModels.swift

@Observable
class MainViewModel {
    @ObservationIgnored
    let wallpaperService: WallpaperServiceProtocol
    let playerService: VideoPlayerService
    
    // MARK: - Navigation State
    var selectedTab: AppTab = .prepare {
        didSet {
            if selectedTab == .edit {
                generateThumbnailsIfNeeded()
            }
        }
    }
    
    // MARK: - Ingredient State
    var selectedIngredientID: UUID?
    
    var ingredients: [MediaIngredient] { IngredientStore.shared.ingredients }
    
    var activeIngredient: MediaIngredient? {
        ingredients.first { $0.id == selectedIngredientID }
    }
    
    // MARK: - App State
    var isEnabled = false
    var windowOpacity: Double = 1.0
    // var exportState = ExportState() // Removed in favor of Queue
    var selectedAerialAsset: AerialAsset?
    
    // MARK: - Queue State Proxy
    var renderJobs: [RenderJob] { RenderQueueService.shared.jobs }
    
    // MARK: - Video Metadata
    var sourceMetadata: MediaMetadata?
    
    // MARK: - Import State Proxy
    var importState: ImportState { AssetImportService.shared.state }
    
    #if DIRECT_DISTRIBUTION
    var showYouTubeInput = false
    var youtubeURL: String = ""
    #endif
    
    // MARK: - Download State Proxy
    var downloadStates: [UUID: DownloadState] { YouTubeDownloadService.shared.downloadStates }
    
    // MARK: - Thumbnail State Proxy
    var thumbnails: [NSImage] { ThumbnailManager.shared.filmstripThumbnails }
    var ingredientThumbnails: [UUID: NSImage] { ThumbnailManager.shared.ingredientThumbnails }
    
    var timelineWidth: CGFloat {
        get { ThumbnailManager.shared.timelineWidth }
        set { ThumbnailManager.shared.timelineWidth = newValue }
    }
    
    func getThumbnail(for ingredient: MediaIngredient) -> NSImage? {
        ThumbnailManager.shared.getThumbnail(for: ingredient)
    }
    
    func triggerThumbnailGeneration(for id: UUID, url: URL) {
        ThumbnailManager.shared.triggerThumbnailGeneration(for: id, url: url)
    }
    
    func generateThumbnailsIfNeeded(force: Bool = false) {
        ThumbnailManager.shared.generateFilmstripIfNeeded(for: selectedVideoURL, force: force)
    }
    
    
    var isLooping: Bool = false {
        didSet { updateLoopRange() }
    }
    
    // MARK: - Trim Preview
    var isSideBySideActive: Bool = false
    
    var startTime: Double = 0.0 {
        didSet { 
            updateLoopRange()
        }
    }
    
    var endTime: Double = 10.0 {
        didSet { 
            updateLoopRange() 
        }
    }
    
    private func updateLoopRange() {
        if isLooping {
            playerService.loopRange = startTime..<endTime
        } else {
            playerService.loopRange = nil
        }
    }
    var videoDuration: Double = 10.0
    var animationSpeed: Double = 1.0
    var transitionDuration: Double = 2.0
    
    // MARK: - Export Configuration
    // Removed based on user feedback
    var isAdvancedInfoMode: Bool = false // Renamed from isAdvancedExportMode for clarity, used for Info View toggle
    
    // Legacy helper for compatibility
    var currentSource: MediaSource? {
        get { activeIngredient?.source }
        set {
            if let id = selectedIngredientID, let index = IngredientStore.shared.ingredients.firstIndex(where: { $0.id == id }), let newValue = newValue {
                var ingredient = IngredientStore.shared.ingredients[index]
                ingredient.source = newValue
                IngredientStore.shared.update(ingredient)
            }
        }
    }
    
    var selectedVideoURL: URL? {
        currentSource?.localURL
    }
    
    // MARK: - Initialization
    init(wallpaperService: WallpaperServiceProtocol = WallpaperService(), playerService: VideoPlayerService = VideoPlayerService()) {
        self.wallpaperService = wallpaperService
        self.playerService = playerService
    }
    
    // Persistence moved to IngredientStore
    
    // MARK: - File Actions
    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                Task {
                    await AssetImportService.shared.importFile(at: url)
                    
                    // After import, if successful, select the newly added ingredient
                    if let last = IngredientStore.shared.ingredients.last {
                        await MainActor.run {
                            self?.selectedIngredientID = last.id
                        }
                    }
                }
            }
        }
    }
    
    // addLocalIngredient has been moved to AssetImportService.shared.importFile(at:)
    
    func removeIngredient(_ ingredient: MediaIngredient) {
        if let localURL = ingredient.source.localURL, localURL.path.contains("LiveWallpaperDownloads") == true {
             try? FileManager.default.removeItem(at: localURL)
        }
        IngredientStore.shared.remove(id: ingredient.id)
        if selectedIngredientID == ingredient.id {
            selectedIngredientID = nil
        }
    }
    
    func selectIngredient(_ ingredient: MediaIngredient) {
        // If it's a local offline file, we don't allow it to be the "active" selection
        if ingredient.isOffline {
            Logger.video.warning("Ingredient '\(ingredient.name)' is offline. Deselecting.")
            selectedIngredientID = nil
            sourceMetadata = nil
            return
        }
        
        selectedIngredientID = ingredient.id
    }
    
    // MARK: - Video Metadata & Thumbnails
    func loadVideoMetadata(url: URL) {
        Task {
            // Policy: Clear playback state BEFORE loading new video to avoid range conflicts
            await MainActor.run {
                playerService.loopRange = nil
                playerService.playbackLimit = nil
                self.sourceMetadata = nil
                // self.exportState = ExportState() // Removed
            }
            
            do {
                let metadata = try await playerService.loadVideo(at: url)
                
                // Extract Technical Metadata via Helper
                let techMetadata = try await VideoMetadataAnalyzer.analyze(url: url)
                
                await MainActor.run {
                    self.videoDuration = metadata.duration
                    self.startTime = 0.0
                    self.endTime = metadata.duration
                    self.sourceMetadata = techMetadata
                    
                    // Reset thumbnails so they are regenerated for the new video when needed
                    ThumbnailManager.shared.clearFilmstrip()
                    
                    // Trigger thumbnail generation automatically
                    ThumbnailManager.shared.generateFilmstripIfNeeded(for: url)
                }
            } catch {
                Logger.video.error("Failed to load video metadata: \(error.localizedDescription)")
            }
        }
    }
    
    // generateThumbnailsIfNeeded moved to ThumbnailManager
    
    // MARK: - Rendering / Export
    func addToRenderQueue() {
        guard let url = selectedVideoURL else { return }
        
        // Prepare output path in App dedicated Library
        let filename = url.deletingPathExtension().lastPathComponent
        let uniqueID = UUID().uuidString.prefix(8)
        let outputURL = AppConfig.shared.wallpapersDirectory.appendingPathComponent("\(filename)_\(uniqueID).mov")
        
        // Create Configuration
        let config = LiveWallpaperExportConfiguration(
            sourceURL: url,
            outputURL: outputURL,
            startTime: self.startTime,
            endTime: self.endTime,
            totalDuration: self.playerService.duration,
            timeScale: self.playerService.timeScale,
            strategy: self.sourceMetadata?.transcodeStrategy ?? .standard10Bit
        )
        
        let currentThumbnail = self.thumbnails.first
        
        // Add to Queue Service
        RenderQueueService.shared.addToQueue(
            config: config,
            originalFilename: filename,
            thumbnail: currentThumbnail
        )
        
        // Provide user feedback (optional toast or navigation)
        // self.selectedTab = .render // Optional: Auto-switch to render tab
    }
    
    // MARK: - Enabler Logic
    func toggleEnabler() {
        isEnabled.toggle()
    }
}


// extension FourCharCode { has been moved to Core/Extensions/FourCharCode+String.swift

