import AVFoundation
import AppKit
import os

class FilmstripGenerator {
    static let shared = FilmstripGenerator()
    
    private init() {}
    
    func generateThumbnails(for url: URL, count: Int = 10) async throws -> [NSImage] {
        let asset = AVURLAsset(url: url)
        
        // Load duration and tracks (for timeScale)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        let videoTrack = tracks.first(where: { $0.mediaType == .video })
        
        let durationSeconds = CMTimeGetSeconds(duration)
        let timeScale = try await videoTrack?.load(.naturalTimeScale) ?? 600
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400) // Optimization
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        var times: [CMTime] = []
        let increment = durationSeconds / Double(count)
        
        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * increment, preferredTimescale: timeScale)
            times.append(time)
        }
        
        var images: [NSImage] = []
        
        for await result in generator.images(for: times) {
            switch result {
            case .success(_, let image, _):
                images.append(NSImage(cgImage: image, size: .zero))
            case .failure(_, let error):
                Logger.video.error("Error generating thumbnail: \(error.localizedDescription)")
            }
        }
        
        return images
    }
    
    func generateThumbnail(for url: URL, at time: CMTime = .zero) async throws -> NSImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        
        let cgImage = try await generator.image(at: time).image
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
