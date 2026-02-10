import Foundation

enum DistributionChannel {
    case appStore
    case direct
}

struct AppConfig {
    static let shared = AppConfig()
    
    let channel: DistributionChannel = {
        #if DIRECT_DISTRIBUTION
        return .direct
        #else
        return .appStore
        #endif
    }()
    
    var isSandboxed: Bool {
        #if DIRECT_DISTRIBUTION
        return false
        #else
        return true
        #endif
    }
    
    /// Returns the directory where app-specific data should be stored.
    /// In Sandbox, this is standard. Outside Sandbox, we might want a specific directory.
    var appSupportDirectory: URL {
        if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mitocondria.LiveWallpaperEnabler") {
            let base = sharedContainer.appendingPathComponent("Library/Application Support/LiveWallpaperEnabler", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        }
        
        // Fallback for non-App Group environments (debugging?)
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = paths[0].appendingPathComponent("LiveWallpaperEnabler", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    
    var thumbnailsDirectory: URL {
        let url = appSupportDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    var wallpapersDirectory: URL {
        let url = appSupportDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
