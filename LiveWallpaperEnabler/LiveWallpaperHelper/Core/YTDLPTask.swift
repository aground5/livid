import Foundation

/// Core domain logic for executing yt-dlp commands
struct YTDLPTask {
    let arguments: [String]
    let binaryURL: URL
    
    func run() throws -> String {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "en_US.UTF-8"
        
        // Add our private bin directory and system paths for node, deno, ffmpeg, etc.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let privateBinPath = appSupport.appendingPathComponent("LiveWallpaperEnabler/bin").path
        
        let currentPath = env["PATH"] ?? ""
        let extraPaths = "\(privateBinPath):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(extraPaths):\(currentPath)"
        process.environment = env
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        print("   [Process] Executing: \(binaryURL.path) \(arguments.joined(separator: " "))")
        try process.run()
        print("   [Process] Started (PID: \(process.processIdentifier))")
        
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            print("   [Process] Failed with status \(process.terminationStatus): \(errorMsg)")
            throw NSError(domain: "YTDLPTask", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        guard let output = String(data: outData, encoding: .utf8) else {
            throw NSError(domain: "YTDLPTask", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to read task output"])
        }
        
        return output
    }
}
