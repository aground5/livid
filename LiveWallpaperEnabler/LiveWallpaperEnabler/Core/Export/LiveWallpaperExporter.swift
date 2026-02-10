import Foundation
@preconcurrency import CoreMedia
import Observation
import os

/// Encapsulates the configuration and execution logic for exporting a live wallpaper.
/// This separates business rules (e.g., smart trimming) from UI state management.
// LiveWallpaperExportConfiguration is now defined in Core/Models/RenderModels.swift


actor LiveWallpaperExporter {
    
    enum ExportError: LocalizedError {
        case invalidDuration
        case conversionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidDuration:
                return "The selected duration is invalid."
            case .conversionFailed(let reason):
                return "Video conversion failed: \(reason)"
            }
        }
    }
    
    /// Executes the export process using the provided configuration.
    /// Handles trimming calculation and delegates to VideoConverterService.
    func export(config: LiveWallpaperExportConfiguration, progressHandler: ((Double) -> Void)? = nil) async throws {
        
        // 1. Calculate Trimming Range
        let range = calculateTrimRange(config: config)
        
        // 2. Log Operation
        Logger.video.info("Starting Export: \(config.sourceURL.lastPathComponent)")
        if let r = range {
            Logger.video.debug("Trimming: \(r.start.seconds)s to \(r.end.seconds)s")
        } else {
            Logger.video.debug("Exporting Full Duration")
        }
        
        // 3. Perform Conversion
        try await VideoConverterService.shared.convertToLiveWallpaper(
            inputURL: config.sourceURL,
            outputURL: config.outputURL,
            timeRange: range,
            strategy: config.strategy,
            progressHandler: progressHandler
        )
    }
    
    /// Determines the CMTimeRange based on user selection and total duration.
    /// Returns nil if the full video is selected (optimization).
    private func calculateTrimRange(config: LiveWallpaperExportConfiguration) -> CMTimeRange? {
        let isAtStart = config.startTime <= 0.01
        let isAtEnd = (config.endTime - config.totalDuration).magnitude < 0.01
        
        if isAtStart && isAtEnd {
            return nil // Full video, no trim
        }
        
        let finalStartTime = isAtStart ? 0.0 : config.startTime
        let finalEndTime = isAtEnd ? config.totalDuration : config.endTime
        
        let start = CMTime(seconds: finalStartTime, preferredTimescale: config.timeScale)
        let duration = CMTime(seconds: finalEndTime - finalStartTime, preferredTimescale: config.timeScale)
        
        return CMTimeRange(start: start, duration: duration)
    }
}
