import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox
import AudioToolbox

struct VideoMetadataAnalyzer {
    
    enum AnalysisError: LocalizedError {
        case trackNotFound
        case assetNotReadable
    }
    
    static func analyze(url: URL) async throws -> MediaMetadata {
        let asset = AVURLAsset(url: url)
        
        let isReadable = try await asset.load(.isReadable)
        guard isReadable else {
            throw AnalysisError.assetNotReadable
        }
        
        let tracks = try await asset.load(.tracks)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        
        guard let videoTrack = videoTracks.first else {
            throw AnalysisError.trackNotFound
        }
        
        // 1. Core Properties
        let duration = try await asset.load(.duration).seconds
        let size = try await videoTrack.load(.naturalSize).applying(videoTrack.load(.preferredTransform))
        let width = Int(abs(size.width))
        let height = Int(abs(size.height))
        var fps = Double(try await videoTrack.load(.nominalFrameRate))
        if fps <= 0 {
            let minDuration = try await videoTrack.load(.minFrameDuration)
            if minDuration.seconds > 0 {
                fps = 1.0 / minDuration.seconds
            }
        }
        
        // Final fallback to 30 if still 0
        if fps <= 0 { fps = 30.0 }
        
        // 2. Codec & Profile & Color Space
        var codec = "Unknown"
        var profile: String? = nil
        var colorSpace = "SDR"
        var bitDepth = 8
        var chromaSubsampling = "4:2:0"
        
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        if let formatDesc = formatDescriptions.first {
            let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
            codec = mapCodec(subType)
            
            // Extract properties from extensions
            let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] ?? [:]
            colorSpace = extractColorSpace(extensions: extensions)
            
            // Extract Bit Depth
            if let bits = extensions["BitsPerComponent"] as? Int {
                bitDepth = bits
            } else if colorSpace.contains("HDR") || colorSpace.contains("HLG") {
                bitDepth = 10 // HDR is typically at least 10-bit
            }
            
            // Extract Chroma Subsampling
            if let subsampling = extensions[kCVImageBufferChromaSubsamplingKey as String] as? String {
                chromaSubsampling = subsampling.replacingOccurrences(of: "YCbCr", with: "") // Clean up if needed
                // Map common internal strings to user-friendly format
                if chromaSubsampling.contains("420") { chromaSubsampling = "4:2:0" }
                else if chromaSubsampling.contains("422") { chromaSubsampling = "4:2:2" }
                else if chromaSubsampling.contains("444") { chromaSubsampling = "4:4:4" }
            }
        }
        
        // 3. Audio Info
        let hasAudio = !audioTracks.isEmpty
        var audioFormat: String? = nil
        if let audioTrack = audioTracks.first, let desc = try await audioTrack.load(.formatDescriptions).first {
            let subType = CMFormatDescriptionGetMediaSubType(desc)
            audioFormat = mapAudioCodec(subType)
        }
        
        // 4. Bitrate
        // Use estimatedDataRate for async API
        var bitrateMbps = Double(try await videoTrack.load(.estimatedDataRate)) / 1_000_000.0
        if bitrateMbps <= 0 {
            // Fallback to file size calculation
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            bitrateMbps = duration > 0 ? (Double(fileSize) * 8.0 / 1_000_000.0) / duration : 0
        }
        
        return MediaMetadata(
            codec: codec,
            profile: profile,
            width: width,
            height: height,
            fps: fps,
            bitrateMbps: bitrateMbps,
            colorSpace: colorSpace,
            bitDepth: bitDepth,
            chromaSubsampling: chromaSubsampling,
            hasAudio: hasAudio,
            audioFormat: audioFormat,
            duration: duration
        )
    }
    
    // MARK: - Helpers
    
    private static func mapCodec(_ subType: FourCharCode) -> String {
        switch subType {
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_VP9: return "VP9"
        case kCMVideoCodecType_AppleProRes422, 
             kCMVideoCodecType_AppleProRes4444: return "ProRes"
        default: return subType.toString()
        }
    }
    
    private static func mapAudioCodec(_ subType: FourCharCode) -> String {
        // Use kAudioFormat constants from AudioToolbox
        switch subType {
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatAC3: return "AC3"
        case kAudioFormatEnhancedAC3: return "E-AC3"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatOpus: return "Opus"
        default: return subType.toString()
        }
    }
    
    private static func extractColorSpace(extensions: [String: Any]) -> String {
        let primaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
        let transfer = extensions[kCVImageBufferTransferFunctionKey as String] as? String
        
        // Detect HDR
        let isHDR = transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) ||
                    transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
        
        if isHDR {
            let type = transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) ? "HLG" : "HDR10"
            return "\(type) (Rec.2020)"
        }
        
        // Detect Wide Color (P3)
        if primaries == (kCVImageBufferColorPrimaries_P3_D65 as String) {
            return "Display P3"
        }
        
        return "Rec.709"
    }
}
