import Foundation
import Hummingbird
import Logging
import HTTPTypes
import NIOCore
import NIOFoundationCompat

// Minimal representation of the Main App's Item for JSON decoding
struct StoredWallpaperItem: Codable {
    let id: UUID
    let filename: String
    let catalogAssetID: String?
}

class LocalAssetServer {
    static let shared = LocalAssetServer()
    let port = 50505
    
    // Cache or live lookup? Live lookup is safer for consistency.
    private let mainAppBundleID = "com.mitocondria.LiveWallpaperEnabler"
    
    func start() {
        Task {
            do {
                try await run()
            } catch {
                print("❌ LocalAssetServer failed: \(error)")
            }
        }
    }
    
    func run() async throws {
        let router = Router()
        
        // Routes
        router.get("video/:filename", use: handleVideo)
        router.get("thumbnail/:filename", use: handleThumbnail)
        
        // Middleware (Logger)
        // router.middlewares.add(LogRequestsMiddleware(.info))

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        
        print("✅ LocalAssetServer (Hummingbird) listening on port \(port)")
        try await app.runService()
    }
    
    // MARK: - Handlers
    
    @Sendable func handleVideo(request: Request, context: some RequestContext) async throws -> Response {
        guard let filename = context.parameters.get("filename") else {
            return Response(status: .badRequest)
        }
        
        guard let finalURL = resolveFile(filename: filename, type: "video") else {
             return Response(status: .notFound, body: .init(byteBuffer: ByteBuffer(string: "File not found")))
        }
        
        print("📥 Request for Video: \(filename)")
        
        // Patch Logic
        do {
            let patcher = try AtomPatcher(fileURL: finalURL)
            try WallpaperInjector.patch(patcher: patcher)
            let patchedData = try patcher.getPatchedData()
            
            var headers = HTTPFields()
            headers[.contentType] = "video/quicktime"
            headers[.contentLength] = String(patchedData.count)
            headers[.connection] = "close"
            
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: patchedData)))
        } catch {
            print("❌ Error patching video: \(error)")
            return Response(status: .internalServerError)
        }
    }
    
    @Sendable func handleThumbnail(request: Request, context: some RequestContext) async throws -> Response {
        guard let filename = context.parameters.get("filename") else {
            return Response(status: .badRequest)
        }
        
        guard let finalURL = resolveFile(filename: filename, type: "thumbnail") else {
             return Response(status: .notFound)
        }
        
        print("📥 Request for Thumbnail: \(filename)")
        
        do {
            let data = try Data(contentsOf: finalURL)
             var headers = HTTPFields()
            headers[.contentType] = "image/png"
            headers[.contentLength] = String(data.count)
            headers[.connection] = "close"
            
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
        } catch {
             print("❌ Error reading thumbnail: \(error)")
            return Response(status: .internalServerError)
        }
    }
    
    // MARK: - Helpers
    
    private func resolveFile(filename: String, type: String) -> URL? {
        // Security: Input Sanitization
        if filename.contains("..") || filename.contains("/") || filename.contains("\\") {
            print("⚠️ Security Alert: Path traversal blocked: \(filename)")
            return nil
        }
        
        let assetID = filename.replacingOccurrences(of: ".mov", with: "")
                              .replacingOccurrences(of: ".png", with: "")
        
        if let storedPath = findPathInStore(for: assetID, type: type) {
            if FileManager.default.fileExists(atPath: storedPath.path) {
                return storedPath
            }
        }
        
        // Fallback / Standard Resolution via App Group
        let baseDir: URL
        
        if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mitocondria.LiveWallpaperEnabler") {
             let appSupport = sharedContainer.appendingPathComponent("Library/Application Support/LiveWallpaperEnabler")
             
             switch type {
             case "video":
                 baseDir = appSupport.appendingPathComponent("Wallpapers")
             case "thumbnail":
                 baseDir = appSupport.appendingPathComponent("Thumbnails")
             default:
                 return nil
             }
        } else {
            // Very old fallback
             let home = FileManager.default.homeDirectoryForCurrentUser
             let appSupport = home.appendingPathComponent("Library/Application Support/LiveWallpaperEnabler")
             
             switch type {
             case "video":
                 baseDir = appSupport.appendingPathComponent("Wallpapers")
             case "thumbnail":
                 baseDir = appSupport.appendingPathComponent("Thumbnails")
             default:
                 return nil
             }
        }
        
        let legacyURL = baseDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        
        return nil
    }
    
    private func findPathInStore(for assetID: String, type: String) -> URL? {
        // Use App Group Defaults
        guard let defaults = UserDefaults(suiteName: "group.com.mitocondria.LiveWallpaperEnabler") else {
             return nil
        }
        
        guard let data = defaults.data(forKey: "wallpaper_library_v2"),
              let items = try? JSONDecoder().decode([StoredWallpaperItem].self, from: data) else {
            return nil
        }
        
        // Find item linked to this assetID
        guard let item = items.first(where: { $0.catalogAssetID == assetID }) else {
            return nil
        }
        
        // Construct path relative to App Group Container
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mitocondria.LiveWallpaperEnabler") else {
            return nil
        }
        
        let appSupport = sharedContainer.appendingPathComponent("Library/Application Support/LiveWallpaperEnabler")
        
        if type == "video" {
            return appSupport.appendingPathComponent("Wallpapers").appendingPathComponent(item.filename)
        } else {
            // Reconstruct thumbnail path: UUID.png
            return appSupport.appendingPathComponent("Thumbnails").appendingPathComponent("\(item.id.uuidString).png")
        }
    }
}
