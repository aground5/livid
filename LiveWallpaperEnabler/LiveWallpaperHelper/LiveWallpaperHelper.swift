import Foundation

@main
class LiveWallpaperHelper {
    static func main() {
        // Helper to restart Wallpaper Subsystem (Agent & Extension)
        func restartWallpaperSubsystem() {
            let processes = ["WallpaperAgent", "WallpaperAerialsExtension"]
            
            for procName in processes {
                let task = Process()
                task.launchPath = "/usr/bin/killall"
                task.arguments = [procName]
                try? task.run()
            }
        }
        
        let args = ProcessInfo.processInfo.arguments
        HelperLogger.log("Process Launched. Args: \(args)")
        
        // 1. --test Test Mode
        if args.contains("--test") {
            HelperLogger.log("Running in TEST mode.")
            Task {
                await runCoreTests()
                HelperLogger.log("Tests completed. Exiting.")
                exit(0)
            }
            RunLoop.main.run()
        } else {
            // 2. Service Mode
            // 1. Restart Wallpaper Subsystem
            HelperLogger.log("🔄 [Startup] Restarting Wallpaper Subsystem (Agent & Extension)...")
            restartWallpaperSubsystem()
            
            HelperLogger.log("Starting NSXPCListener for bundled XPC service...")
            NSLog("🚀 Starting NSXPCListener for bundled XPC service")
            let delegate = XPCListenerDelegate()
            let listener = NSXPCListener.service()
            listener.delegate = delegate
            listener.resume()
            
            HelperLogger.log("Starting Local Asset Server...")
            NSLog("🚀 Starting Local Asset Server...")
            LocalAssetServer.shared.start()
            
            HelperLogger.log("Entering Main RunLoop...")
            NSLog("🚀 Entering Main RunLoop...")
            RunLoop.main.run()
        }
    }
    
    static func runCoreTests() async {
        print("\n🚀 Starting Helper Core Lifecycle Test...")
        
        do {
            let assets: [BinaryManager.BinaryAsset] = [.ytdlp]
            
            for asset in assets {
                print("\n--- Testing Lifecycle for: \(asset.rawValue) ---")
                
                // 1. Check current status
                let initialStatus = BinaryManager.shared.getBinaryStatus(asset)
                print("📍 Initial status: Exists=\(initialStatus["exists"] ?? "false"), Version=\(initialStatus["version"] ?? "none")")
                
                // 2. Ensure exists from the packaged runtime
                print("⏳ Ensuring packaged runtime is ready...")
                let startTime = Date()
                let binaryURL = try await BinaryManager.shared.ensureBinaryExists(asset)
                let duration = String(format: "%.2fs", Date().timeIntervalSince(startTime))
                print("✅ Ready at: \(binaryURL.path) (Took \(duration))")
                
                // 3. Verify caching (second call should be near-instant)
                print("⏳ Verifying cache performance...")
                let cacheStartTime = Date()
                _ = try await BinaryManager.shared.ensureBinaryExists(asset)
                let cacheDuration = String(format: "%.2fms", Date().timeIntervalSince(cacheStartTime) * 1000)
                
                let finalStatus = BinaryManager.shared.getBinaryStatus(asset)
                print("✅ Cache verified: \(cacheDuration) (Version: \(finalStatus["version"] ?? "n/a"))")
            }
        } catch {
            print("\n❌ TEST FAILED: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                print("💡 Decoding details: \(decodingError)")
            }
        }
        
        print("\n✨ Lifecycle test finished.")
    }
}
