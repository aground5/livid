import Foundation
import os

enum YouTubeDownloadError: Error {
    case invalidURL
    case noStreamsFound
    case downloadFailed(String)
}

struct YouTubeStreamOption: Identifiable, Hashable, Codable {
    let id: String
    let resolution: Int
    let fileExtension: String
    let url: URL
    let hasAudio: Bool
    let isNativelyPlayable: Bool
    let codec: String
    let bitrate: Double?
    let isHDR: Bool
    let isVP9: Bool
    var estimatedSpeed: Double?
    
    var title: String {
        var parts: [String] = ["\(resolution)p"]
        if isHDR { parts.append("HDR") }
        if isVP9 { parts.append("VP9") }
        
        let playableBadge = isNativelyPlayable ? "" : " (Converted)"
        return "\(parts.joined(separator: " ")) (\(fileExtension))\(playableBadge)"
    }
}

struct DownloadProgress {
    let progress: Double
    let completedBytes: Int64
    let totalBytes: Int64
    let speedBytesPerSecond: Double
}

class YouTubeDownloader {
    static let shared = YouTubeDownloader()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiveWallpaperEnabler", category: "YouTubeDownloader")
    
    func fetchMetadata(url: URL) async throws -> (YouTubeMetadataDTO, [YouTubeStreamOption]) {
        let meta = try await HelperServiceConnection.shared.fetchMetadata(url: url)
        
        let dto = YouTubeMetadataDTO(
            title: meta.title,
            description: meta.description ?? "", 
            thumbnailURL: URL(string: meta.thumbnail ?? "")
        )
        
        // Filter and Map
        // We group by resolution and extension, but keep the one with the highest bitrate if multiple exist
        let uniqueFormats = Dictionary(grouping: meta.formats, by: { "\($0.height ?? 0)-\($0.ext)-\($0.vcodec ?? "")" })
            .compactMap { $0.value.max(by: { ($0.bitrate) < ($1.bitrate) }) }
        
        let streams = uniqueFormats
            .filter { ($0.height ?? 0) >= 360 } // Filter low quality
            .map { f in
                YouTubeStreamOption(
                    id: f.format_id,
                    resolution: f.height ?? 0,
                    fileExtension: f.ext,
                    url: url,
                    hasAudio: f.hasAudio,
                    isNativelyPlayable: f.isNativelyPlayable,
                    codec: f.vcodec ?? "unknown",
                    bitrate: f.bitrate,
                    isHDR: f.isHDR,
                    isVP9: f.isVP9,
                    estimatedSpeed: nil
                )
            }
            .sorted { 
                if $0.resolution != $1.resolution {
                    return $0.resolution > $1.resolution
                }
                return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
            }
            
        return (dto, streams)
    }
    
    func download(streamOption: YouTubeStreamOption, progressHandler: @escaping (DownloadProgress) -> Void) async throws -> URL {
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveWallpaperDownloads")
        
        return try await HelperServiceConnection.shared.download(
            url: streamOption.url,
            formatID: streamOption.id,
            outputDirectory: outputDir
        ) { progress, statusLine in
            
            let speed = self.parseSpeed(from: statusLine)
            
            let info = DownloadProgress(
                progress: progress,
                completedBytes: 0,
                totalBytes: 0, 
                speedBytesPerSecond: speed
            )
            progressHandler(info)
        }
    }
    
    private func parseSpeed(from line: String) -> Double {
        // Example: "[download]  45.0% of 10.00MiB at 2.00MiB/s ETA 00:05"
        if let range = line.range(of: "at ") {
            let suffix = line[range.upperBound...]
            let components = suffix.split(separator: " ")
            if let speedStr = components.first {
                return self.parseSizeString(String(speedStr))
            }
        }
        return 0
    }
    
    private func parseSizeString(_ str: String) -> Double {
        let raw = str.replacingOccurrences(of: "/s", with: "")
        let unitMultipliers: [String: Double] = ["KiB": 1024, "MiB": 1024*1024, "GiB": 1024*1024*1024, "kB": 1000, "MB": 1000000]
        
        for (unit, mult) in unitMultipliers {
            if raw.contains(unit) {
                let valStr = raw.replacingOccurrences(of: unit, with: "")
                if let val = Double(valStr) {
                    return val * mult
                }
            }
        }
        return 0
    }
    
    func benchmarkStreams(_ streams: [YouTubeStreamOption]) async -> [YouTubeStreamOption] {
        return streams // No-op, yt-dlp handles optimization
    }
}
