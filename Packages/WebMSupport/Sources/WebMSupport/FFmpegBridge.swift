import Foundation
import CoreVideo
import WebMSupportCpp

public class FFmpegBridge: @unchecked Sendable {
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
    
    public typealias ProgressBlock = @Sendable (Double) -> Void
    
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
        
        let handlerBox = progress.map { Box($0) }
        let userData = handlerBox.map { Unmanaged.passRetained($0).toOpaque() }
        
        let success = FFmpegWrapper_PrepareToMov(ref, outputUrl.path, startTime, endTime, { p, userData in
            guard let userData = userData else { return }
            let box = Unmanaged<Box<ProgressBlock>>.fromOpaque(userData).takeUnretainedValue()
            box.value(p)
        }, userData)
        
        if let userData = userData {
            Unmanaged<Box<ProgressBlock>>.fromOpaque(userData).release()
        }
        
        if !success {
            throw NSError(domain: "FFmpegBridge", code: 3, userInfo: [NSLocalizedDescriptionKey: "Preparation failed"])
        }
    }
    
    public func exportToMov(outputUrl: URL, settings: FFmpegTranscodeSettings, progress: ProgressBlock? = nil) throws {
        guard let ref = ref else { return }
        
        let handlerBox = progress.map { Box($0) }
        let userData = handlerBox.map { Unmanaged.passRetained($0).toOpaque() }
        
        let success = FFmpegWrapper_ExportToMovExt(
            ref,
            outputUrl.path,
            settings.startTime,
            settings.endTime,
            settings.tonemap,
            settings.tenBit,
            { p, userData in
                guard let userData = userData else { return }
                let box = Unmanaged<Box<ProgressBlock>>.fromOpaque(userData).takeUnretainedValue()
                box.value(p)
            },
            userData)
            
        if let userData = userData {
            Unmanaged<Box<ProgressBlock>>.fromOpaque(userData).release()
        }
        
        if !success {
            throw NSError(domain: "FFmpegBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }

    public func remuxToMov(outputUrl: URL, startTime: Double = 0.0, endTime: Double = 0.0, progress: ProgressBlock? = nil) throws {
        guard let ref = self.ref else { return }
        
        let handlerBox = progress.map { Box($0) }
        let userData = handlerBox.map { Unmanaged.passRetained($0).toOpaque() }
        
        let success = FFmpegWrapper_RemuxToMov(ref, outputUrl.path, startTime, endTime, { p, userData in
            guard let userData = userData else { return }
            let box = Unmanaged<Box<ProgressBlock>>.fromOpaque(userData).takeUnretainedValue()
            box.value(p)
        }, userData)
        
        if let userData = userData {
            Unmanaged<Box<ProgressBlock>>.fromOpaque(userData).release()
        }
        
        if !success {
            throw NSError(domain: "FFmpegBridge", code: 5, userInfo: [NSLocalizedDescriptionKey: "Remux failed"])
        }
    }

    public func stop() {
        guard let ref = self.ref else { return }
        FFmpegWrapper_Stop(ref)
    }
}

// Helper box to wrap non-bit-pattern closure for Unmanaged
private class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}
