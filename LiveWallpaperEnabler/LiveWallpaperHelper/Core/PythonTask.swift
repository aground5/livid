import Foundation

final class PythonTask {
    private let scriptName: String
    private let arguments: [String]
    private let binaryURL: URL
    
    init(scriptName: String, arguments: [String], binaryURL: URL) {
        self.scriptName = scriptName
        self.arguments = arguments
        self.binaryURL = binaryURL
    }
    
    private func getScriptPath() throws -> String {
        if let bundlePath = Bundle.main.path(forResource: scriptName, ofType: "py") {
            return bundlePath
        }
        
        if let bundlePath = Bundle.main.path(forResource: scriptName, ofType: "py", inDirectory: "Scripts") {
            return bundlePath
        }
        
        let currentDirectory = FileManager.default.currentDirectoryPath
        let relativePaths = [
            "LiveWallpaperEnabler/LiveWallpaperHelper/Resources/Scripts/\(scriptName).py",
            "LiveWallpaperHelper/Resources/Scripts/\(scriptName).py",
            "Resources/Scripts/\(scriptName).py",
        ]
        
        for relativePath in relativePaths {
            let fullPath = (currentDirectory as NSString).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }
        
        throw NSError(
            domain: "PythonTask",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Script '\(scriptName).py' not found in bundle or relative path"]
        )
    }
    
    func run(
        onOutputLine: (@Sendable (String) -> Void)? = nil,
        onErrorLine: (@Sendable (String) -> Void)? = nil,
        onProcessStarted: (@Sendable (Process) -> Void)? = nil
    ) async throws -> String {
        let scriptPath = try getScriptPath()
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [scriptPath] + arguments
        
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "en_US.UTF-8"
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let privateBinPath = appSupport.appendingPathComponent("LiveWallpaperEnabler/bin").path
        let currentPath = env["PATH"] ?? ""
        let extraPaths = "\(privateBinPath):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(extraPaths):\(currentPath)"
        process.environment = env
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        // Output task using readabilityHandler
        let stdoutTask = Task<Data, Never> {
            var accumulated = Data()
            var buffer = Data()
            
            let stream = AsyncStream<Data> { continuation in
                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.finish()
                    } else {
                        continuation.yield(data)
                    }
                }
            }
            
            for await data in stream {
                accumulated.append(data)
                buffer.append(data)
                
                // Process lines in buffer
                while true {
                    let newlineRange = buffer.range(of: Data([10])) ?? buffer.range(of: Data([13]))
                    guard let range = newlineRange else { break }
                    
                    let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                        onOutputLine?(line)
                    }
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                }
            }
            
            // Final leftovers
            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                onOutputLine?(line)
            }
            
            return accumulated
        }
        
        // Error task using readabilityHandler
        let stderrTask = Task<Data, Never> {
            var accumulated = Data()
            var buffer = Data()
            
            let stream = AsyncStream<Data> { continuation in
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.finish()
                    } else {
                        continuation.yield(data)
                    }
                }
            }
            
            for await data in stream {
                accumulated.append(data)
                buffer.append(data)
                
                while true {
                    let newlineRange = buffer.range(of: Data([10])) ?? buffer.range(of: Data([13]))
                    guard let range = newlineRange else { break }
                    
                    let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                        onErrorLine?(line)
                    }
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                }
            }
            
            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                onErrorLine?(line)
            }
            
            return accumulated
        }
        
        HelperLogger.log("[Python] Executing: \(binaryURL.path) \(process.arguments?.joined(separator: " ") ?? "")")
        
        let terminationStatus = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            
            do {
                try process.run()
                HelperLogger.log("[Python] Started PID \(process.processIdentifier) script=\(self.scriptName)")
                onProcessStarted?(process)
            } catch {
                process.terminationHandler = nil
                HelperLogger.error("[Python] Failed to start script=\(self.scriptName): \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
        
        // Wait for output tasks to complete
        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        
        if terminationStatus != 0 {
            let errorMessage = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            HelperLogger.error("[Python] script=\(scriptName) exited with status \(terminationStatus): \(errorMessage)")
            throw NSError(
                domain: "PythonTask",
                code: Int(terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
        }

        HelperLogger.log("[Python] script=\(scriptName) exited successfully with status \(terminationStatus)")
        
        guard let output = String(data: stdoutData, encoding: .utf8) else {
            throw NSError(
                domain: "PythonTask",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode Python task output"]
            )
        }
        
        return output
    }
}
