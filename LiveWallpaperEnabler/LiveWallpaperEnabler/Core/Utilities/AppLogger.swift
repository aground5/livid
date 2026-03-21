import Foundation
import os

extension Logger {
    /// The subsystem identifier. Using a constant string to avoid MainActor isolation issues in Swift 6.
    private static let subsystem: String = "com.antigravity.LiveWallpaperEnabler"

    /// General application logs
    nonisolated static let general = Logger(subsystem: subsystem, category: "general")
    
    /// Video processing, transcoding, and ffmpeg operations
    nonisolated static let video = Logger(subsystem: subsystem, category: "video")
    
    /// Network operations, downloads, and API calls
    nonisolated static let network = Logger(subsystem: subsystem, category: "network")
    
    /// User interface and view model interactions
    nonisolated static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// System and wallpaper service operations
    nonisolated static let system = Logger(subsystem: subsystem, category: "system")
}
