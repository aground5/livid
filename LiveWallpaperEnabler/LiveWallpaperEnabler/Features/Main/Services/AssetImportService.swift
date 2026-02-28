import Foundation
import Observation
import AVFoundation
import AppKit

@Observable
class AssetImportService {
    static let shared = AssetImportService()
    
    var state = ImportState()
    
    @ObservationIgnored
    private let store = IngredientStore.shared
    @ObservationIgnored
    private let thumbnailManager = ThumbnailManager.shared
    
    /// Main entry point for importing a file. Handles validation, conversion, and metadata.
    func importFile(at url: URL) async {
        await MainActor.run {
            self.state.isImporting = true
            self.state.progress = 0.0
            self.state.status = "Starting import..."
            self.state.error = nil
        }
        
        do {
            // 1. Analyze ORIGINAL file metadata BEFORE any conversion
            let originalMeta = try? await VideoMetadataAnalyzer.analyze(url: url)
            
            // 2. Determine if conversion is needed
            let processedURL = try await ensureNativelyPlayable(url)
            
            // 3. Extract Metadata & Create Ingredient
            let id = UUID()
            let name = url.lastPathComponent
            var ingredient = MediaIngredient(
                id: id,
                name: name,
                source: .local(url: processedURL),
                addedDate: Date(),
                originalMetadata: originalMeta
            )
            
            // 4. Generate Initial Thumbnail
            await MainActor.run { self.state.status = "Generating preview..." }
            try await generateAndSaveThumbnail(for: id, url: processedURL, ingredient: &ingredient)
            
            // 5. Finalize in Store
            await MainActor.run {
                self.store.add(ingredient)
                self.state.isImporting = false
                self.state.status = "Finished"
            }
            
        } catch {
            await MainActor.run {
                self.state.error = error.localizedDescription
                self.state.isImporting = false
            }
        }
    }
    
    /// Decides if the file needs conversion and executes it if necessary.
    private func ensureNativelyPlayable(_ url: URL) async throws -> URL {
        if url.pathExtension.lowercased() == "webm" {
            await MainActor.run { 
                self.state.status = "Converting WebM for preview..."
            }
            
            let folder = url.deletingLastPathComponent()
            let convertedURL = folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)_preview.mov")
            
            // Fast preview conversion
            try await VideoConverterService.shared.convertToNativelyPlayable(
                inputURL: url, 
                outputURL: convertedURL,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.state.progress = progress
                    }
                }
            )
            return convertedURL
        }
        
        // As-is if natively supported
        return url
    }
    
    private func generateAndSaveThumbnail(for id: UUID, url: URL, ingredient: inout MediaIngredient) async throws {
        let image = try await FilmstripGenerator.shared.generateThumbnail(for: url)
        let filename = "\(id.uuidString).png"
        let fileURL = AppConfig.shared.thumbnailsDirectory.appendingPathComponent(filename)
        
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            let pngData = bitmap.representation(using: .png, properties: [:])
            try pngData?.write(to: fileURL)
        }
        
        ingredient.thumbnailName = filename
        // Also cache it in the manager immediately
        await MainActor.run {
            self.thumbnailManager.ingredientThumbnails[id] = image
        }
    }
}
