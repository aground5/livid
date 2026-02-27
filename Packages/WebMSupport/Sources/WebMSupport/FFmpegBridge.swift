import Foundation
import CoreVideo
import WebMSupportCpp

public class FFmpegBridge {
    private var ref: FFmpegWrapperRef?
    
    public init(path: String) throws {
        guard let ref = FFmpegWrapper_Create(path) else {
            throw NSError(domain: "FFmpegBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create FFmpeg wrapper"])
        }
        self.ref = ref
        if !FFmpegWrapper_IsOpen(ref) {
            FFmpegWrapper_Destroy(ref)
            self.ref = nil
            throw NSError(domain: "FFmpegBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to open video file at \(path)"])
        }
    }
    
    deinit {
        if let ref = ref {
            FFmpegWrapper_Destroy(ref)
        }
    }
    
    public var duration: Double {
        return FFmpegWrapper_GetDuration(ref)
    }
    
    public var width: Int {
        return Int(FFmpegWrapper_GetWidth(ref))
    }
    
    public var height: Int {
        return Int(FFmpegWrapper_GetHeight(ref))
    }
    
    public var codecName: String {
        if let cName = FFmpegWrapper_GetCodecName(ref) {
            return String(cString: cName)
        }
        return "unknown"
    }
    
    public typealias ProgressBlock = (Double) -> Void
    
    public struct FFmpegTranscodeSettings {
        public var startTime: Double = 0.0
        public var endTime: Double = 0.0
        public var tonemap: Bool = false
        public var tenBit: Bool = true
        
        public init(startTime: Double = 0.0, endTime: Double = 0.0, tonemap: Bool = false, tenBit: Bool = true) {
            self.startTime = startTime
            self.endTime = endTime
            self.tonemap = tonemap
            self.tenBit = tenBit
        }
    }
    
    public func prepareToMov(outputUrl: URL, startTime: Double = 0.0, endTime: Double = 0.0, progress: ProgressBlock? = nil) throws {
        guard let ref = ref else { return }
        var progressHandler = progress
        let success = withUnsafeMutablePointer(to: &progressHandler) { handlerPtr in
             FFmpegWrapper_PrepareToMov(ref, outputUrl.path, startTime, endTime, { p, userData in
                guard let userData = userData else { return }
                let block = userData.assumingMemoryBound(to: ProgressBlock?.self).pointee
                block?(p)
            }, handlerPtr)
        }
        if !success {
            throw NSError(domain: "FFmpegBridge", code: 3, userInfo: [NSLocalizedDescriptionKey: "Preparation failed"])
        }
    }
    
    public func exportToMov(outputUrl: URL, settings: FFmpegTranscodeSettings, progress: ProgressBlock? = nil) throws {
        guard let ref = ref else { return }
        var progressHandler = progress
        let success = withUnsafeMutablePointer(to: &progressHandler) { handlerPtr in
             FFmpegWrapper_ExportToMovExt(
                ref,
                outputUrl.path,
                settings.startTime,
                settings.endTime,
                settings.tonemap,
                settings.tenBit,
                { p, userData in
                    guard let userData = userData else { return }
                    let block = userData.assumingMemoryBound(to: ProgressBlock?.self).pointee
                    block?(p)
                },
                handlerPtr)
        }
        if !success {
            throw NSError(domain: "FFmpegBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }
}
