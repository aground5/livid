import Foundation

public struct YTDLPFormat: Codable, Identifiable, Sendable {
    public let format_id: String
    public let ext: String
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    public let vcodec: String?
    public let acodec: String?
    public let filesize: Int64?
    public let filesize_approx: Int64?
    public let tbr: Double? // Total bitrate
    public let vbr: Double? // Video bitrate
    public let abr: Double? // Audio bitrate
    public let format_note: String?
    public let dynamic_range: String? // e.g., "SDR", "HDR10"
    public let url: String?
    
    public var id: String { format_id }
    
    public var resolution: Int { height ?? 0 }
    public var hasVideo: Bool { vcodec != "none" && vcodec != nil }
    public var hasAudio: Bool { acodec != "none" && acodec != nil }
    
    public var isNativelyPlayable: Bool {
        // Simple heuristic for macOS native support
        let v = vcodec?.lowercased() ?? ""
        let isH264 = v.contains("avc") || v.contains("h264")
        let isHEVC = v.contains("hev") || v.contains("h265")
        
        // MP4 container + (H264 or HEVC) is safe. 
        if ext == "mp4" || ext == "mov" {
            return isH264 || isHEVC
        }
        return false
    }
    
    public var isVP9: Bool {
        vcodec?.lowercased().contains("vp9") ?? false
    }
    
    public var isHDR: Bool {
        let dr = dynamic_range?.lowercased() ?? ""
        return dr.contains("hdr") || dr.contains("pqi")
    }
    
    public var estimatedSize: Int64 {
        filesize ?? filesize_approx ?? 0
    }
    
    public var bitrate: Double {
        tbr ?? (vbr ?? 0) + (abr ?? 0)
    }
}

public struct YTDLPMetadata: Codable, Sendable {
    public let id: String
    public let title: String
    public let uploader: String?
    public let duration: Double?
    public let formats: [YTDLPFormat]
    public let webpage_url: String
    public let thumbnail: String?
    public let description: String?
}
