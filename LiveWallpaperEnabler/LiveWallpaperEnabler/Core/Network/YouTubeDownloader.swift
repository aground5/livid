import Foundation
import os

enum YouTubeDownloadError: Error {
    case invalidURL
    case noStreamsFound
    case missingStreamURL
    case downloadFailed(String)
}

struct YouTubeStreamOption: Identifiable, Hashable, Codable {
    let id: String
    let formatID: String?
    let resolution: Int
    let fileExtension: String
    let url: URL?
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
    
    func fetchMetadata(url: URL) async throws -> (YTDLPMetadata, [YouTubeStreamOption]) {
        let metadata = try await HelperServiceConnection.shared.fetchMetadata(url: url)
        let streamOptions = mapStreams(from: metadata)
        
        logger.info("Fetched yt-dlp metadata for \(url.absoluteString, privacy: .public) with \(streamOptions.count) playable streams")
        
        return (metadata, streamOptions)
    }
    
    func benchmarkStreams(_ streams: [YouTubeStreamOption]) async -> [YouTubeStreamOption] {
        return streams // No-op
    }
    
    private func mapStreams(from metadata: YTDLPMetadata) -> [YouTubeStreamOption] {
        let streamOptions = (metadata.formats ?? []).compactMap { format -> YouTubeStreamOption? in
            guard format.hasVideo else { return nil }
            guard format.resolution > 0 else { return nil }
            guard let urlString = format.url, let url = URL(string: urlString) else { return nil }
            
            let formatID = format.format_id.isEmpty ? nil : format.format_id
            let codec = normalizedCodec(from: format.vcodec)
            
            return YouTubeStreamOption(
                id: formatID ?? url.absoluteString,
                formatID: formatID,
                resolution: format.resolution,
                fileExtension: format.ext,
                url: url,
                hasAudio: format.hasAudio,
                isNativelyPlayable: format.isNativelyPlayable,
                codec: codec,
                bitrate: format.bitrate,
                isHDR: format.isHDR,
                isVP9: format.isVP9,
                estimatedSpeed: nil
            )
        }.sorted {
            if $0.resolution != $1.resolution {
                return $0.resolution > $1.resolution
            }
            return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
        }
        
        return streamOptions
    }
    
    private func normalizedCodec(from value: String?) -> String {
        guard let value, !value.isEmpty else { return "unknown" }
        return value.split(separator: ".").first.map(String.init) ?? value
    }
}
