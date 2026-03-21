import Foundation
import os

enum HelperLogger {
    private static let subsystem = "com.mitocondria.LiveWallpaperHelper"
    private static let logger = Logger(subsystem: subsystem, category: "Helper")
    private static let queue = DispatchQueue(label: "\(subsystem).file-log")
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append(message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR: \(message)")
    }

    private static func append(_ message: String) {
        queue.async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let logDir = home.appendingPathComponent("Library/Logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

            let logPath = logDir.appendingPathComponent("LiveWallpaperHelper.log")
            let timestamp = formatter.string(from: Date())
            let line = "\(timestamp): [PID \(ProcessInfo.processInfo.processIdentifier)] \(message)\n"

            guard let data = line.data(using: .utf8) else {
                return
            }

            if let handle = try? FileHandle(forWritingTo: logPath) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }
}
