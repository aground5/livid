import Foundation
import CoreMedia

enum MediaSource: Codable, Sendable {
    case local(url: URL)
    case youtube(metadata: YTDLPMetadata, localURL: URL?, streams: [YouTubeStreamOption])
    
    var localURL: URL? {
        switch self {
        case .local(let url): return url
        case .youtube(_, let url, _): return url
        }
    }
}

struct MediaIngredient: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var source: MediaSource
    var addedDate: Date
    var thumbnailName: String?
    var originalMetadata: MediaMetadata?  // Original source specs before preview conversion
    
    static func == (lhs: MediaIngredient, rhs: MediaIngredient) -> Bool {
        lhs.id == rhs.id
    }
}

struct MediaMetadata: Codable, Equatable {
    let codec: String
    let profile: String?
    let width: Int
    let height: Int
    let fps: Double
    let bitrateMbps: Double
    let colorSpace: String
    let bitDepth: Int
    let chromaSubsampling: String
    let hasAudio: Bool
    let audioFormat: String?
    let duration: Double
    
    // Quality labeling
    var resolutionLabel: String {
        if width >= 3840 { return "4K" }
        if width >= 2560 { return "QHD" }
        if width >= 1920 { return "FHD" }
        return "\(height)p"
    }
    
    // Smart Strategy Detection - Holistic Analysis
    var transcodeStrategy: TranscodeStrategy {
        let isHDR = colorSpace.contains("HDR") || colorSpace.contains("HLG") || colorSpace.contains("Rec.2020")
        let isWideColorSDR = colorSpace.contains("P3")
        let isHighChroma = !chromaSubsampling.contains("4:2:0")
        let is8Bit = bitDepth < 10
        
        // Priority 1: High Dynamic Range or Wide Color
        if isHDR || isWideColorSDR {
            if isHighChroma {
                return .advancedColorAndChroma // HDR/P3 + 422/444 (The most complex)
            } else {
                return .hdrTonemap10Bit // HDR/P3 + 420
            }
        }
        
        // Priority 2: High Chroma SDR (e.g., ProRes 422 SDR)
        if isHighChroma {
            return .chromaDownsample10Bit
        }
        
        // Priority 3: Standard SDR with low bit depth
        if is8Bit {
            return .upconvert10Bit
        }
        
        // Baseline: Native 10-bit SDR 4:2:0
        return .standard10Bit
    }
}

enum TranscodeStrategy: String, Codable, Sendable {
    case advancedColorAndChroma = "Advanced (HDR/P3 + High Chroma)"
    case hdrTonemap10Bit = "HDR/WideColor to SDR 10-bit"
    case chromaDownsample10Bit = "Professional SDR 4:2:2/4:4:4"
    case upconvert10Bit = "SDR Precision Upgrade (8 to 10-bit)"
    case standard10Bit = "Standard 10-bit SDR"
    
    var description: String {
        switch self {
        case .advancedColorAndChroma:
            return "Extreme high-fidelity processing. Simultaneous HDR/Wide-Color mapping and 4:2:2/4:4:4 chroma downsampling using libplacebo to ensure the most professional 10-bit SDR result."
        case .hdrTonemap10Bit:
            return "Intelligent color mapping (Rec.2020/P3 to Rec.709) with 10-bit precision, preserving highlight detail that would otherwise be lost."
        case .chromaDownsample10Bit:
            return "Professional SDR source detected with high chroma detail. Precision downsampling to 4:2:0 while expanding to 10-bit to maintain color smoothness."
        case .upconvert10Bit:
            return "Expanding 8-bit source to a 10-bit pipeline to prevent compression artifacts and banding in consistent areas like the sky."
        case .standard10Bit:
            return "Native compatibility mode. Optimized encoding for sources already matching the 10-bit SDR 4:2:0 standard."
        }
    }
}

struct ImportState {
    var isImporting: Bool = false
    var progress: Double = 0.0
    var status: String = ""
    var error: String? = nil
}

struct ExportState {
    var isActive: Bool = false
    var progress: Double = 0.0
    var status: String = "Idle"
    var isFinished: Bool = false
    
    // New Metrics
    var currentFrame: Int = 0
    var speed: Double = 0.0
    var fps: Double = 0.0
    var timeRemaining: TimeInterval? = nil
}

// MARK: - FFmpeg Metrics Protocol
struct FFmpegMediaMetrics: Sendable {
    let progress: Double
    let currentFrame: Int
    let speed: Double     // e.g., 1.5 (means 1.5x real-time)
    let fps: Double       // current encoding FPS
    let bitrate: Double   // in kbps
    let totalFrames: Int
}

protocol FFmpegProgressDelegate: Sendable {
    func ffmpegDidUpdateMetrics(_ metrics: FFmpegMediaMetrics)
}

// MARK: - YouTube Download State
struct DownloadState: Sendable {
    var progress: Double = 0.0
    var status: String = ""
    var isDownloading: Bool = false
    var error: String? = nil
}

// MARK: - Extensions
extension MediaSource {
    var youtubeMetadata: YTDLPMetadata? {
        if case .youtube(let metadata, _, _) = self {
            return metadata
        }
        return nil
    }
    
    var isYouTube: Bool {
        if case .youtube = self { return true }
        return false
    }
}

extension MediaIngredient {
    var isRemoteYouTube: Bool {
        if case .youtube(_, let localURL, _) = source {
            guard let url = localURL else { return true }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        return false
    }
    
    /// Returns true if the associated local file is missing from disk.
    var isOffline: Bool {
        if source.isYouTube { return false }
        guard let url = source.localURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }
}
