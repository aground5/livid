import Foundation
import SwiftUI

// #if DIRECT_DISTRIBUTION
extension MainViewModel {
    
    // MARK: - YouTube Integration
    
    func fetchYouTubeStreams(url: String) {
        print("🚀 [MainViewModel+YouTube] fetchYouTubeStreams called for: \(url)")
        guard let urlObj = URL(string: url) else {
            AssetImportService.shared.state.error = "Invalid URL"
            return
        }
        
        Task { @MainActor in
            AssetImportService.shared.state.isImporting = true
            AssetImportService.shared.state.progress = 0.3
            AssetImportService.shared.state.error = nil 
            
            do {
                print("🚀 [MainViewModel+YouTube] Requesting metadata directly...")
                let (metadata, streams) = try await YouTubeDownloader.shared.fetchMetadata(url: urlObj)
                print("🚀 [MainViewModel+YouTube] Received metadata: \(metadata.title), \(streams.count) streams")
                
                AssetImportService.shared.state.isImporting = false
                AssetImportService.shared.state.progress = 1.0
                
                let ingredient = MediaIngredient(
                    id: UUID(),
                    name: metadata.title,
                    source: .youtube(metadata: metadata, localURL: nil, streams: streams),
                    addedDate: Date()
                )
                IngredientStore.shared.add(ingredient)
                self.selectedIngredientID = ingredient.id
                self.showYouTubeInput = false
                
            } catch {
                print("❌ [MainViewModel+YouTube] Fetch Error: \(error.localizedDescription)")
                AssetImportService.shared.state.isImporting = false
                AssetImportService.shared.state.progress = 0.0
                AssetImportService.shared.state.error = error.localizedDescription
            }
        }
    }
    
    func downloadVideo(resolution: Int) {
        guard let id = selectedIngredientID,
              let ingredient = IngredientStore.shared.ingredients.first(where: { $0.id == id }) else { return }
        
        // Delegate to service
        YouTubeDownloadService.shared.downloadVideo(ingredient: ingredient, resolution: resolution)
    }
    
    func cancelDownload(for id: UUID) {
        YouTubeDownloadService.shared.cancelDownload(for: id)
    }
}
// #endif
