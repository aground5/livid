import Foundation

@main
class LiveWallpaperHelper {
    static func main() {
        // Debug Logging Helper
        func log(_ message: String) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let logDir = home.appendingPathComponent("Library/Logs")
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
            
            let logPath = logDir.appendingPathComponent("LiveWallpaperHelper.log").path
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date())
            
            let msg = "\(timestamp): [PID \(ProcessInfo.processInfo.processIdentifier)] \(message)\n"
            if let data = msg.data(using: .utf8) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: URL(fileURLWithPath: logPath))
                }
            }
        }
        
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
        log("Process Launched. Args: \(args)")
        
        // 1. --test Test Mode
        if args.contains("--test") {
            log("Running in TEST mode.")
            Task {
                await runCoreTests()
                log("Tests completed. Exiting.")
                exit(0)
            }
            RunLoop.main.run()
        } else {
            // 2. Service Mode
            // 1. Restart Wallpaper Subsystem
            log("🔄 [Startup] Restarting Wallpaper Subsystem (Agent & Extension)...")
            restartWallpaperSubsystem()
            
            log("Starting NSXPCListener (Mach Service)...")
            NSLog("🚀 Starting NSXPCListener for Mach Service: com.mitocondria.LiveWallpaperHelper")
            let delegate = XPCListenerDelegate()
             // LaunchAgent Mode: Listen on Mach Service Name
            let listener = NSXPCListener(machServiceName: "com.mitocondria.LiveWallpaperHelper")
            listener.delegate = delegate
            listener.resume()
            
            log("Starting Local Asset Server...")
            NSLog("🚀 Starting Local Asset Server...")
            LocalAssetServer.shared.start()
            
            log("Entering Main RunLoop...")
            NSLog("🚀 Entering Main RunLoop...")
            RunLoop.main.run()
        }
    }
    
    static func runCoreTests() async {
        print("\n🚀 Starting Helper Core Lifecycle Test...")
        
        do {
            let assets: [BinaryManager.BinaryAsset] = [.ytdlp, .deno]
            
            for asset in assets {
                print("\n--- Testing Lifecycle for: \(asset.rawValue) ---")
                
                // 1. Check current status
                let initialStatus = BinaryManager.shared.getBinaryStatus(asset)
                print("📍 Initial status: Exists=\(initialStatus["exists"] ?? "false"), Version=\(initialStatus["version"] ?? "none")")
                
                // 2. Ensure exists (this handles download/update)
                print("⏳ Ensuring binary is ready (Downloading if needed)...")
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
            
            // 4. Test functionality with a real URL
            // 4. Test Deno Script Execution
            print("\n--- Testing Deno Script Integration ---")
            let testURL = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
            let tempDownloadPath = FileManager.default.temporaryDirectory.appendingPathComponent("deno_test_output.txt").path
            
            let denoURL = try await BinaryManager.shared.ensureBinaryExists(.deno)
            
            // Note: We are using a mock script first to verify the pipeline
            let task = DenoTask(
                scriptName: "sabr-downloader",
                arguments: [testURL, "--output", tempDownloadPath],
                binaryURL: denoURL
            )
            
            print("⏳ Running Deno task...")
            let output = try task.run()
            print("✅ Deno Output:\n\(output)")
            
            if FileManager.default.fileExists(atPath: tempDownloadPath) {
                let content = try String(contentsOfFile: tempDownloadPath, encoding: .utf8)
                print("✅ Script file created successfully. Content: [\(content.trimmingCharacters(in: .whitespacesAndNewlines))]")
            } else {
                print("⚠️ Script output file not found")
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
