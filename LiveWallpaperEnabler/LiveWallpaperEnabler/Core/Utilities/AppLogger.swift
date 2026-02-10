import Foundation
import os

extension Logger {
    /// The subsystem identifier. Using a constant string to avoid MainActor isolation issues in Swift 6.
    private static let subsystem: String = "com.antigravity.LiveWallpaperEnabler"

    /// General application logs
    static let general = Logger(subsystem: subsystem, category: "general")
    
    /// Video processing, transcoding, and ffmpeg operations
    static let video = Logger(subsystem: subsystem, category: "video")
    
    /// Network operations, downloads, and API calls
    static let network = Logger(subsystem: subsystem, category: "network")
    
    /// User interface and view model interactions
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// System and wallpaper service operations
    static let system = Logger(subsystem: subsystem, category: "system")
}
