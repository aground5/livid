import Foundation
import os
import YouTubeKit

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
    
    func fetchMetadata(url: URL) async throws -> (YTDLPMetadata, [YouTubeStreamOption]) {
        let video = YouTube(url: url)
        
        // Fetch metadata and streams
        let metaOptional = try await video.metadata
        let streamsResult = try await video.streams
        
        let title = metaOptional?.title ?? "Unknown"
        let description = metaOptional?.description ?? ""
        let thumbnail = metaOptional?.thumbnail?.url
        
        let dto = YTDLPMetadata(
            id: url.absoluteString,
            title: title,
            description: description, 
            webpage_url: url.absoluteString,
            thumbnail: thumbnail?.absoluteString
        )
        
        // Map streams to options
        let streamOptions = streamsResult.compactMap { stream -> YouTubeStreamOption? in
            guard let resolution = stream.videoResolution else { return nil } // Exclude audio-only for wallpaper
            guard stream.includesVideoTrack else { return nil }
            
            let codec = stream.videoCodec.map { String(describing: $0) } ?? "unknown"
            
            return YouTubeStreamOption(
                id: UUID().uuidString,
                resolution: resolution,
                fileExtension: stream.fileExtension.rawValue,
                url: stream.url,
                hasAudio: stream.includesAudioTrack,
                isNativelyPlayable: stream.isNativelyPlayable,
                codec: codec,
                bitrate: Double(stream.averageBitrate ?? stream.bitrate ?? 0),
                isHDR: codec.lowercased().contains("hdr"), // naive fallback
                isVP9: codec.lowercased().contains("vp9"),
                estimatedSpeed: nil
            )
        }.sorted { 
            if $0.resolution != $1.resolution {
                return $0.resolution > $1.resolution
            }
            return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
        }
            
        return (dto, streamOptions)
    }
    
    func benchmarkStreams(_ streams: [YouTubeStreamOption]) async -> [YouTubeStreamOption] {
        return streams // No-op
    }
}
