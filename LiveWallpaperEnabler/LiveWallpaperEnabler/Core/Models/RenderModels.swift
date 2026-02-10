import Foundation
import AppKit
import SwiftUI
import CoreMedia

/// Represents the status of a specific render job
enum RenderStatus: Equatable, Sendable {
    case pending
    case rendering
    case completed
    case failed(String)
    case cancelled
}

/// A unifying model representing a single item in the export queue.
/// This model drives the UI for the Render Queue List.
struct RenderJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let config: LiveWallpaperExportConfiguration
    let createdAt: Date
    var originalFilename: String
    var thumbnail: NSImage?
    
    // Mutable State
    var status: RenderStatus = .pending
    var progress: Double = 0.0
    
    // Performance Metrics
    var fps: Double = 0.0
    var speed: Double = 0.0
    var currentFrame: Int = 0
    var timeRemaining: TimeInterval?
    
    static func == (lhs: RenderJob, rhs: RenderJob) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.progress == rhs.progress
    }
}

/// Moved from LiveWallpaperExporter.swift to be shared
struct LiveWallpaperExportConfiguration: Sendable {
    let sourceURL: URL
    let outputURL: URL
    let startTime: Double
    let endTime: Double
    let totalDuration: Double
    let timeScale: CMTimeScale
    let strategy: TranscodeStrategy
}
