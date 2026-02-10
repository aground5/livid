import Foundation

/// XPC Service implementation that orchestrates services and runners
/// XPC Service implementation that orchestrates services and runners
class LiveWallpaperHelperService: NSObject, LiveWallpaperHelperProtocol {
    
    func fetchMetadata(url: URL, withReply reply: @escaping (String?, Error?) -> Void) {
        Task {
            do {
                let binary = try await BinaryManager.shared.ensureBinaryExists(.ytdlp)
                _ = try? await BinaryManager.shared.ensureBinaryExists(.deno) // Pre-pull JS runtime
                
                let task = YTDLPTask(
                    arguments: ["--dump-json", "--no-playlist", url.absoluteString],
                    binaryURL: binary
                )
                let json = try task.run()
                reply(json, nil)
            } catch {
                reply(nil, error)
            }
        }
    }
    
    func downloadVideo(url: URL, formatID: String?, outputDirectoryURL: URL, withReply reply: @escaping (URL?, Error?) -> Void) {
        Task {
            do {
                let binary = try await BinaryManager.shared.ensureBinaryExists(.ytdlp)
                _ = try? await BinaryManager.shared.ensureBinaryExists(.deno)
                
                let filenameTemplate = "%(title)s [%(id)s].%(ext)s"
                // Using absolute path for output template
                let outputPath = outputDirectoryURL.appendingPathComponent(filenameTemplate).path
                
                
                var args = [
                    "--no-playlist",
                    "-o", outputPath,
                    url.absoluteString
                ]
                
                // If formatID is provided, use it as the format selector string (e.g., "bestvideo[height<=1080]")
                // If nil, yt-dlp defaults to "best"
                if let formatSelector = formatID {
                    args.insert(contentsOf: ["-f", formatSelector], at: 0)
                }
                
                let task = YTDLPTask(arguments: args, binaryURL: binary)
                let _ = try task.run()
                
                // Find the downloaded file
                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(at: outputDirectoryURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                
                // Sort by creation date descending to find the just-created file
                let validExtensions = ["mov", "mp4", "webm", "mkv"]
                let newestFile = files
                    .filter { validExtensions.contains($0.pathExtension.lowercased()) }
                    .sorted {
                        let date1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                        let date2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                        return date1 > date2
                    }
                    .first
                
                reply(newestFile, nil)
            } catch {
                reply(nil, error)
            }
        }
    }
    
    func checkHealth(withReply reply: @escaping (String) -> Void) {
        let stats = [
            "status": "Healthy",
            "yt-dlp": BinaryManager.shared.getBinaryStatus(.ytdlp),
            "deno": BinaryManager.shared.getBinaryStatus(.deno),
            "helper": [
                "pid": "\(ProcessInfo.processInfo.processIdentifier)",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                "sandbox": "Disabled" // As verified in entitlements
            ],
            "secure_storage": "Available"
        ] as [String : Any]
        
        if let data = try? JSONSerialization.data(withJSONObject: stats, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            reply(jsonString)
        } else {
            reply("{\"status\": \"Error building health report\"}")
        }
    }
}

