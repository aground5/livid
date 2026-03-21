import Foundation

/// XPC Service implementation that orchestrates bundled yt-dlp runtime operations.
class LiveWallpaperHelperService: NSObject, LiveWallpaperHelperProtocol {
    func fetchMetadata(url: URL, withReply reply: @escaping (String?, Error?) -> Void) {
        Task {
            do {
                HelperLogger.log("[Metadata] Request url=\(url.absoluteString)")
                let pythonURL = try await pythonRuntimeURL()
                let task = PythonTask(
                    scriptName: "yt_dlp_bridge",
                    arguments: ["metadata", "--url", url.absoluteString],
                    binaryURL: pythonURL
                )
                
                let metadataBox = MetadataResultBox()
                _ = try await task.run(onOutputLine: { line in
                    guard let event = Self.parseEvent(from: line) else { return }
                    guard (event["type"] as? String) == "metadata" else { return }
                    guard let payload = event["payload"],
                          JSONSerialization.isValidJSONObject(payload),
                          let data = try? JSONSerialization.data(withJSONObject: payload),
                          let jsonString = String(data: data, encoding: .utf8) else {
                        return
                    }
                    metadataBox.jsonString = jsonString
                })
                
                guard let jsonString = metadataBox.jsonString else {
                    throw NSError(
                        domain: "LiveWallpaperHelperService",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "yt-dlp bridge returned no metadata payload"]
                    )
                }
                
                HelperLogger.log("[Metadata] Success url=\(url.absoluteString) payloadBytes=\(jsonString.utf8.count)")
                reply(jsonString, nil)
            } catch {
                HelperLogger.error("[Metadata] Failed url=\(url.absoluteString): \(error.localizedDescription)")
                reply(nil, error)
            }
        }
    }
    
    func downloadVideo(
        taskID: String,
        url: URL,
        formatID: String?,
        outputDirectoryURL: URL,
        observer: LiveWallpaperDownloadObserverProtocol,
        withReply reply: @escaping (URL?, Error?) -> Void
    ) {
        Task {
            do {
                let pythonURL = try await pythonRuntimeURL()
                let outputPath = outputDirectoryURL.appendingPathComponent("%(id)s_%(height)sp.%(ext)s").path
                let resultBox = DownloadResultBox()
                await DownloadTraceRegistry.shared.begin(
                    taskID: taskID,
                    url: url.absoluteString,
                    formatID: formatID,
                    outputPath: outputPath,
                    pythonPath: pythonURL.path
                )
                
                var arguments = [
                    "download",
                    "--url", url.absoluteString,
                    "--output", outputPath,
                ]
                
                if let formatID, !formatID.isEmpty {
                    arguments.append(contentsOf: ["--format", formatID])
                }
                
                let task = PythonTask(
                    scriptName: "yt_dlp_bridge",
                    arguments: arguments,
                    binaryURL: pythonURL
                )
                
                defer {
                    Task {
                        await DownloadProcessRegistry.shared.unregister(taskID: taskID)
                        await DownloadTraceRegistry.shared.finish(taskID: taskID)
                    }
                }
                
                _ = try await task.run(
                    onOutputLine: { line in
                        guard let event = Self.parseEvent(from: line) else {
                            if !line.isEmpty {
                                Task {
                                    await DownloadTraceRegistry.shared.logRawOutput(taskID: taskID, line: line)
                                }
                            }
                            return
                        }
                        Self.handleDownloadEvent(event, taskID: taskID, observer: observer, resultBox: resultBox)
                    },
                    onErrorLine: { line in
                        if !line.isEmpty {
                            Task {
                                await DownloadTraceRegistry.shared.logStandardError(taskID: taskID, line: line)
                            }
                            observer.downloadDidUpdate(
                                taskID: taskID,
                                phase: "logging",
                                progress: 0,
                                downloadedBytes: 0,
                                totalBytes: 0,
                                speedBytesPerSecond: 0,
                                etaSeconds: -1,
                                detail: line
                            )
                        }
                    },
                    onProcessStarted: { process in
                        Task {
                            await DownloadProcessRegistry.shared.register(process, for: taskID)
                            await DownloadTraceRegistry.shared.logProcessStarted(
                                taskID: taskID,
                                pid: process.processIdentifier
                            )
                        }
                    }
                )
                
                let downloadedFile: URL
                if let fileURL = resultBox.fileURL {
                    downloadedFile = fileURL
                    HelperLogger.log("[Download \(taskID)] Confirmed output path from bridge: \(downloadedFile.path)")
                } else {
                    HelperLogger.error("[Download \(taskID)] Bridge did NOT report an output path. Using fallback heuristic.")
                    downloadedFile = try newestDownloadedFile(in: outputDirectoryURL)
                }
                
                await DownloadTraceRegistry.shared.logCompletion(taskID: taskID, filePath: downloadedFile.path)
                observer.downloadDidUpdate(
                    taskID: taskID,
                    phase: "finished",
                    progress: 1.0,
                    downloadedBytes: 0,
                    totalBytes: 0,
                    speedBytesPerSecond: 0,
                    etaSeconds: 0,
                    detail: "Download complete"
                )
                reply(downloadedFile, nil)
            } catch {
                await DownloadTraceRegistry.shared.logFailure(taskID: taskID, error: error.localizedDescription)
                reply(nil, error)
            }
        }
    }
    
    func cancelDownload(taskID: String, withReply reply: @escaping (Bool) -> Void) {
        Task {
            await DownloadTraceRegistry.shared.logCancellationRequested(taskID: taskID)
            let cancelled = await DownloadProcessRegistry.shared.cancel(taskID: taskID)
            await DownloadTraceRegistry.shared.logCancellationResult(taskID: taskID, cancelled: cancelled)
            reply(cancelled)
        }
    }
    
    func checkHealth(withReply reply: @escaping (String) -> Void) {
        let stats = [
            "status": "Healthy",
            "yt-dlp": BinaryManager.shared.getBinaryStatus(.ytdlp),
            "helper": [
                "pid": "\(ProcessInfo.processInfo.processIdentifier)",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                "sandbox": "Disabled",
            ],
            "secure_storage": "Available",
        ] as [String: Any]
        
        if let data = try? JSONSerialization.data(withJSONObject: stats, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            reply(jsonString)
        } else {
            reply("{\"status\": \"Error building health report\"}")
        }
    }
    
    private func pythonRuntimeURL() async throws -> URL {
        let ytdlpURL = try await BinaryManager.shared.ensureBinaryExists(.ytdlp)
        guard let pythonURL = BinaryManager.shared.pythonRuntimeURL(forYTDLPBinary: ytdlpURL) else {
            throw NSError(
                domain: "LiveWallpaperHelperService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Bundled python runtime not found next to yt-dlp"]
            )
        }
        return pythonURL
    }
    
    private func newestDownloadedFile(in directory: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )
        
        let validExtensions = ["mov", "mp4", "webm", "mkv"]
        let newestFile = files
            .filter { validExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let date1 = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2
            }
            .first
        
        guard let newestFile else {
            throw NSError(
                domain: "LiveWallpaperHelperService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded file was not found in output directory"]
            )
        }
        
        return newestFile
    }
    
    private static func parseEvent(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
    
    private static func handleDownloadEvent(
        _ event: [String: Any],
        taskID: String,
        observer: LiveWallpaperDownloadObserverProtocol,
        resultBox: DownloadResultBox
    ) {
        switch event["type"] as? String {
        case "progress":
            let phase = event["phase"] as? String ?? "download"
            let progress = asDouble(event["progress"])
            let downloadedBytes = asInt64(event["downloaded_bytes"])
            let totalBytes = asInt64(event["total_bytes"])
            let speed = asDouble(event["speed_bytes_per_second"])
            let eta = asDouble(event["eta_seconds"], defaultValue: -1)
            let detail = event["detail"] as? String ?? ""

            Task {
                await DownloadTraceRegistry.shared.logProgress(
                    taskID: taskID,
                    phase: phase,
                    progress: progress,
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                    speedBytesPerSecond: speed,
                    etaSeconds: eta,
                    detail: detail
                )
            }
            observer.downloadDidUpdate(
                taskID: taskID,
                phase: phase,
                progress: progress,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                speedBytesPerSecond: speed,
                etaSeconds: eta,
                detail: detail
            )
        case "result":
            if let filepath = event["filepath"] as? String, !filepath.isEmpty {
                resultBox.fileURL = URL(fileURLWithPath: filepath)
                Task {
                    await DownloadTraceRegistry.shared.logResult(taskID: taskID, filePath: filepath)
                }
            }
        default:
            break
        }
    }
    
    private static func asDouble(_ value: Any?, defaultValue: Double = 0) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? String, let doubleValue = Double(value) {
            return doubleValue
        }
        return defaultValue
    }
    
    private static func asInt64(_ value: Any?, defaultValue: Int64 = 0) -> Int64 {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? String, let intValue = Int64(value) {
            return intValue
        }
        return defaultValue
    }
}

private final class MetadataResultBox: @unchecked Sendable {
    var jsonString: String?
}

private final class DownloadResultBox: @unchecked Sendable {
    var fileURL: URL?
}

private actor DownloadTraceRegistry {
    static let shared = DownloadTraceRegistry()

    private struct State {
        var lastPhase: String?
        var lastProgressBucket: Int = -1
    }

    private var states: [String: State] = [:]

    func begin(taskID: String, url: String, formatID: String?, outputPath: String, pythonPath: String) {
        states[taskID] = State()
        HelperLogger.log(
            "[Download \(taskID)] Started url=\(url) format=\(formatID ?? "best") output=\(outputPath) python=\(pythonPath)"
        )
    }

    func finish(taskID: String) {
        states.removeValue(forKey: taskID)
    }

    func logProcessStarted(taskID: String, pid: Int32) {
        HelperLogger.log("[Download \(taskID)] Python process started pid=\(pid)")
    }

    func logProgress(
        taskID: String,
        phase: String,
        progress: Double,
        downloadedBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSecond: Double,
        etaSeconds: Double,
        detail: String
    ) {
        var state = states[taskID] ?? State()
        let bucket = progressBucket(for: progress)
        let shouldLog = state.lastPhase != phase || bucket > state.lastProgressBucket || phase != "download"

        guard shouldLog else {
            return
        }

        state.lastPhase = phase
        state.lastProgressBucket = max(state.lastProgressBucket, bucket)
        states[taskID] = state

        let downloaded = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        let total = totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) : "unknown"
        let speed = speedBytesPerSecond > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSecond), countStyle: .file) + "/s"
            : "unknown"
        let eta = etaSeconds >= 0 ? "\(Int(etaSeconds.rounded()))s" : "unknown"
        let percent = Int((progress * 100).rounded())

        HelperLogger.log(
            "[Download \(taskID)] phase=\(phase) progress=\(percent)% bytes=\(downloaded)/\(total) speed=\(speed) eta=\(eta) detail=\(detail)"
        )
    }

    func logResult(taskID: String, filePath: String) {
        HelperLogger.log("[Download \(taskID)] yt-dlp reported output path=\(filePath)")
    }

    func logCompletion(taskID: String, filePath: String) {
        HelperLogger.log("[Download \(taskID)] Completed file=\(filePath)")
    }

    func logFailure(taskID: String, error: String) {
        HelperLogger.error("[Download \(taskID)] Failed: \(error)")
    }

    func logCancellationRequested(taskID: String) {
        HelperLogger.log("[Download \(taskID)] Cancellation requested")
    }

    func logCancellationResult(taskID: String, cancelled: Bool) {
        HelperLogger.log("[Download \(taskID)] Cancellation result cancelled=\(cancelled)")
    }

    func logStandardError(taskID: String, line: String) {
        HelperLogger.log("[Download \(taskID)][stderr] \(line)")
    }

    func logRawOutput(taskID: String, line: String) {
        HelperLogger.log("[Download \(taskID)][stdout] \(line)")
    }

    private func progressBucket(for progress: Double) -> Int {
        let clampedProgress = min(max(progress, 0), 1)
        return Int((clampedProgress * 100).rounded(.down) / 10) * 10
    }
}

private actor DownloadProcessRegistry {
    static let shared = DownloadProcessRegistry()
    
    private var processes: [String: Process] = [:]
    
    func register(_ process: Process, for taskID: String) {
        processes[taskID] = process
    }
    
    func unregister(taskID: String) {
        processes.removeValue(forKey: taskID)
    }
    
    func cancel(taskID: String) -> Bool {
        guard let process = processes.removeValue(forKey: taskID) else {
            return false
        }
        
        if process.isRunning {
            process.terminate()
        }
        
        return true
    }
}
