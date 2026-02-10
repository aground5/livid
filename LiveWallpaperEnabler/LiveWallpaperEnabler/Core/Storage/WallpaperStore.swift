import Foundation
import Observation
import AppKit
import AVFoundation

struct LiveWallpaperItem: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String        // The actual file on disk (UUID.mov)
    var displayName: String     // User visible name
    let creationDate: Date
    let duration: Double
    
    // Linkage to AerialService / System Catalog
    var catalogAssetID: String? 
    
    // Transient / System file support (for CatalogView)
    var absolutePath: String? = nil
    var absoluteThumbnailPath: String? = nil
    
    var fileURL: URL {
        if let path = absolutePath { return URL(fileURLWithPath: path) }
        return AppConfig.shared.wallpapersDirectory.appendingPathComponent(filename)
    }
    
    // Thumbnail is now rigidly tied to UUID for simplicity, unless overridden
    var thumbnailURL: URL {
        if let path = absoluteThumbnailPath { return URL(fileURLWithPath: path) }
        return AppConfig.shared.thumbnailsDirectory.appendingPathComponent("\(id.uuidString).png")
    }
}
    
@Observable
class WallpaperStore {
    static let shared = WallpaperStore()
    
    private let dbKey = "wallpaper_library_v2"
    
    var wallpapers: [LiveWallpaperItem] = [] {
        didSet {
            saveDB()
        }
    }
    
    init() {
        loadDB()
        Task {
            await performFileSystemReconciliation()
        }
    }
    
    // MARK: - API
    
    func add(fileURL: URL, originalName: String? = nil, duration: Double) {
        let id = UUID()
        let newFilename = "\(id.uuidString).mov"
        let destinationURL = AppConfig.shared.wallpapersDirectory.appendingPathComponent(newFilename)
        
        do {
            // 1. Move or Copy File to UUID Name
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // If it's already in the wallpapers directory (legacy or temp), move it.
                // Otherwise copy it.
                if fileURL.deletingLastPathComponent().path == AppConfig.shared.wallpapersDirectory.path {
                   // It's already in the folder, just rename it
                   try FileManager.default.moveItem(at: fileURL, to: destinationURL)
                } else {
                   // Import from outside
                   try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                }
            }
            
            // 2. Generate Thumbnail Sync (First frame)
            // Ideally this should be async or validated, but for now we try to ensure it exists.
            let thumbDest = AppConfig.shared.thumbnailsDirectory.appendingPathComponent("\(id.uuidString).png")
            generateThumbnail(source: destinationURL, dest: thumbDest)
            
            // 3. Update DB
            let rawName = fileURL.deletingPathExtension().lastPathComponent // Fallback
            let nameToUse = originalName ?? rawName
            
            let finalName = nameToUse
                .replacingOccurrences(of: "_live_wallpaper", with: "")
                .replacingOccurrences(of: "_", with: " ")
            
            let newItem = LiveWallpaperItem(
                id: id,
                filename: newFilename,
                displayName: finalName,
                creationDate: Date(),
                duration: duration,
                catalogAssetID: nil
            )
            
            runOnMain {
                self.wallpapers.insert(newItem, at: 0)
            }
            
        } catch {
            print("Failed to add wallpaper: \(error)")
        }
    }
    
    func updateName(id: UUID, newName: String) {
        if let index = wallpapers.firstIndex(where: { $0.id == id }) {
            wallpapers[index].displayName = newName
        }
    }
    
    func updateCatalogLink(id: UUID, catalogID: String?) {
        if let index = wallpapers.firstIndex(where: { $0.id == id }) {
            wallpapers[index].catalogAssetID = catalogID
        }
    }
    
    func remove(id: UUID) {
        guard let item = wallpapers.first(where: { $0.id == id }) else { return }
        
        // 1. Remove Files
        try? FileManager.default.removeItem(at: item.fileURL)
        try? FileManager.default.removeItem(at: item.thumbnailURL)
        
        // 2. Remove from DB
        wallpapers.removeAll { $0.id == id }
    }
    
    // MARK: - Persistence
    
    private func saveDB() {
        if let data = try? JSONEncoder().encode(wallpapers) {
            if let defaults = UserDefaults(suiteName: "group.com.mitocondria.LiveWallpaperEnabler") {
                defaults.set(data, forKey: dbKey)
            } else {
                UserDefaults.standard.set(data, forKey: dbKey)
            }
        }
    }
    
    private func loadDB() {
        let defaults = UserDefaults(suiteName: "group.com.mitocondria.LiveWallpaperEnabler") ?? UserDefaults.standard
        
        if let data = defaults.data(forKey: dbKey),
           let decoded = try? JSONDecoder().decode([LiveWallpaperItem].self, from: data) {
            self.wallpapers = decoded
        }
    }
    
    // MARK: - Reconciliation (Migration)
    
    private func performFileSystemReconciliation() async {
        let fm = FileManager.default
        let newDir = AppConfig.shared.wallpapersDirectory
        
        // --- MIGRATION: Check Old Application Support Directory ---
        // The user previously stored files in ~/Library/Application Support/LiveWallpaperEnabler/Wallpapers
        // We need to move them to the App Group container.
        let legacyPaths = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        if let appSupportBase = legacyPaths.first {
            let legacyBase = appSupportBase.appendingPathComponent("LiveWallpaperEnabler")
            let legacyWallpapers = legacyBase.appendingPathComponent("Wallpapers")
            
            if fm.fileExists(atPath: legacyWallpapers.path) {
                if let oldFiles = try? fm.contentsOfDirectory(at: legacyWallpapers, includingPropertiesForKeys: nil) {
                    for file in oldFiles where file.pathExtension.lowercased() == "mov" {
                        let filename = file.lastPathComponent
                        let destination = newDir.appendingPathComponent(filename)
                        
                        if !fm.fileExists(atPath: destination.path) {
                            do {
                                print("📦 Migrating: \(filename) to App Group...")
                                try fm.moveItem(at: file, to: destination)
                                // Also try to move thumbnail
                                let thumbName = file.deletingPathExtension().appendingPathExtension("png").lastPathComponent
                                let oldThumb = legacyBase.appendingPathComponent("Thumbnails").appendingPathComponent(thumbName)
                                let newThumb = AppConfig.shared.thumbnailsDirectory.appendingPathComponent(thumbName)
                                if fm.fileExists(atPath: oldThumb.path) && !fm.fileExists(atPath: newThumb.path) {
                                    try? fm.moveItem(at: oldThumb, to: newThumb)
                                }
                            } catch {
                                print("❌ Migration failed for \(filename): \(error)")
                            }
                        }
                    }
                }
            }
        }
        // -----------------------------------------------------------
        
        let dir = newDir
        
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        
        let movFiles = files.filter { $0.pathExtension.lowercased() == "mov" }
        var changed = false
        var newItems: [LiveWallpaperItem] = []
        
        for file in movFiles {
            let filename = file.lastPathComponent
            
            // If DB doesn't have this file
            if !wallpapers.contains(where: { $0.filename == filename }) {
                
                // Case A: It is already a UUID-named file (orphaned v2 file)
                if let _ = UUID(uuidString: file.deletingPathExtension().lastPathComponent) {
                    let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)!
                    let asset = AVURLAsset(url: file)
                    let duration = (try? await asset.load(.duration))?.seconds ?? 0
                    
                    let restoredItem = LiveWallpaperItem(
                        id: id,
                        filename: filename,
                        displayName: "Restored Wallpaper",
                        creationDate: (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(),
                        duration: duration.isNaN ? 0 : duration,
                        catalogAssetID: nil
                    )
                    newItems.append(restoredItem)
                    changed = true
                    
                } else {
                    // Case B: Legacy filename (e.g. "MyWallpaper.mov") -> Migrate to UUID
                    let newID = UUID()
                    let newFilename = "\(newID.uuidString).mov"
                    let destURL = dir.appendingPathComponent(newFilename)
                    
                    do {
                        try fm.moveItem(at: file, to: destURL)
                        
                        // Migrate Thumbnail if exists
                        let oldBaseName = file.deletingPathExtension().lastPathComponent
                        let possibleOldThumbs = [
                            "thumb_\(oldBaseName).png",
                            "\(oldBaseName).png"
                        ]
                        
                        let newThumbRaw = AppConfig.shared.thumbnailsDirectory.appendingPathComponent("\(newID.uuidString).png")
                        
                        for oldThumbName in possibleOldThumbs {
                            let oldThumbURL = AppConfig.shared.thumbnailsDirectory.appendingPathComponent(oldThumbName)
                            if fm.fileExists(atPath: oldThumbURL.path) {
                                try? fm.moveItem(at: oldThumbURL, to: newThumbRaw)
                                break
                            }
                        }
                        
                        // Even if no thumbnail moved, try to generate one
                        if !fm.fileExists(atPath: newThumbRaw.path) {
                            generateThumbnail(source: destURL, dest: newThumbRaw)
                        }
                        
                        let asset = AVURLAsset(url: destURL)
                        let duration = (try? await asset.load(.duration))?.seconds ?? 0
                        
                        let newItem = LiveWallpaperItem(
                            id: newID,
                            filename: newFilename,
                            displayName: oldBaseName.replacingOccurrences(of: "_", with: " "),
                            creationDate: Date(),
                            duration: duration.isNaN ? 0 : duration,
                            catalogAssetID: nil
                        )
                        newItems.append(newItem)
                        changed = true
                        
                        print("Migrated legacy wallpaper: \(filename) -> \(newFilename)")
                    } catch {
                        print("Failed to migrate legacy file: \(filename) - \(error)")
                    }
                }
            }
        }
        
        if changed {
            await MainActor.run {
                self.wallpapers.append(contentsOf: newItems)
                self.wallpapers.sort(by: { $0.creationDate > $1.creationDate })
                // Save triggered by didSet
            }
        }
    }
    
    private func generateThumbnail(source: URL, dest: URL) {
        let asset = AVURLAsset(url: source)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 360)
        
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        // Synchronous generation for simplicity in this helper, wrapped in do-catch
        try? {
            let cgImage = try gen.copyCGImage(at: time, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: .zero)
            if let tiff = nsImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: dest)
                }
            }
        }()
    }
    
    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
