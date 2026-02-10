import Foundation
import AppKit
import Observation
import os
import AVFoundation

@Observable
class ThumbnailManager {
    static let shared = ThumbnailManager()
    
    // MARK: - Properties
    
    /// Multiple thumbnails for the filmstrip timeline in Editor View
    var filmstripThumbnails: [NSImage] = []
    
    /// Single thumbnails for ingredients (cached in memory)
    var ingredientThumbnails: [UUID: NSImage] = [:]
    
    /// Current timeline width used to calculate thumbnail count
    var timelineWidth: CGFloat = 0 {
        didSet {
            if abs(oldValue - timelineWidth) > 5 { // Sightly more sensitive
                regenerateFilmstripDebounced()
            }
        }
    }
    
    private var currentFilmstripURL: URL?
    
    private var thumbnailTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.antigravity.LiveWallpaperEnabler", category: "ThumbnailManager")
    
    // MARK: - Ingredient Thumbnails (Icons)
    
    func getThumbnail(for ingredient: MediaIngredient) -> NSImage? {
        if let cached = ingredientThumbnails[ingredient.id] {
            return cached
        }
        
        if let name = ingredient.thumbnailName {
            let fileURL = AppConfig.shared.thumbnailsDirectory.appendingPathComponent(name)
            if let image = NSImage(contentsOf: fileURL) {
                ingredientThumbnails[ingredient.id] = image
                return image
            }
        }
        
        // Note: For YouTube ingredients, the view uses AsyncImage with the metadata thumbnail URL.
        // For local files without thumbnails, we might trigger generation.
        if case .local(let url) = ingredient.source {
             triggerThumbnailGeneration(for: ingredient.id, url: url)
        }
        
        return nil
    }
    
    func triggerThumbnailGeneration(for id: UUID, url: URL) {
        Task {
            do {
                let image = try await FilmstripGenerator.shared.generateThumbnail(for: url)
                let filename = "\(id.uuidString).png"
                let fileURL = AppConfig.shared.thumbnailsDirectory.appendingPathComponent(filename)
                
                if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                    let pngData = bitmap.representation(using: .png, properties: [:])
                    try pngData?.write(to: fileURL)
                }
                
                await MainActor.run {
                    self.ingredientThumbnails[id] = image
                    // Notify Store to update metadata if needed
                    if let index = IngredientStore.shared.ingredients.firstIndex(where: { $0.id == id }) {
                        var ingredient = IngredientStore.shared.ingredients[index]
                        ingredient.thumbnailName = filename
                        IngredientStore.shared.update(ingredient)
                    }
                }
            } catch {
                logger.error("Failed to generate thumb for \(id): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Filmstrip Thumbnails (Timeline)
    
    private func regenerateFilmstripDebounced() {
        thumbnailTask?.cancel()
        thumbnailTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            if !Task.isCancelled {
                generateFilmstripIfNeeded(force: true)
            }
        }
    }
    
    func generateFilmstripIfNeeded(for url: URL? = nil, force: Bool = false) {
        if let newURL = url {
            self.currentFilmstripURL = newURL
        }
        
        guard let urlToUse = currentFilmstripURL, (filmstripThumbnails.isEmpty || force), timelineWidth > 0 else { return }
        
        Task {
            do {
                // Optimization: Get video size for aspect ratio calculation
                let asset = AVURLAsset(url: urlToUse)
                guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
                let size = try await track.load(.naturalSize).applying(track.load(.preferredTransform))
                let naturalSize = CGSize(width: abs(size.width), height: abs(size.height))
                
                let aspectRatio = (naturalSize.width > 0 && naturalSize.height > 0) ? (naturalSize.width / naturalSize.height) : (16/9)
                let thumbWidth: CGFloat = 80 * aspectRatio
                let count = Int(ceil(timelineWidth / thumbWidth)) + 1
                
                logger.debug("Regenerating \(count) thumbnails for width \(self.timelineWidth)")
                let images = try await FilmstripGenerator.shared.generateThumbnails(for: urlToUse, count: max(5, min(count, 50)))
                
                await MainActor.run {
                    self.filmstripThumbnails = images
                }
            } catch {
                logger.error("Failed to generate filmstrip: \(error.localizedDescription)")
            }
        }
    }
    
    func clearFilmstrip() {
        filmstripThumbnails = []
    }
}
