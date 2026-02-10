import Foundation
@preconcurrency import AVFoundation
import os
import VideoToolbox
@preconcurrency import CoreVideo
import WebMSupport

enum VideoConversionError: LocalizedError {
    case conversionFailed(String)
    case outputAlreadyExists
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .conversionFailed(let reason):
            return "Video conversion failed: \(reason)"
        case .outputAlreadyExists:
            return "The output file already exists."
        case .unsupportedFormat(let reason):
            return "The video format is not supported natively by macOS: \(reason)."
        }
    }
}

class VideoConverterService {
    static let shared = VideoConverterService()
    
    private init() {}
    
    /// Converts a video file to a macOS-compatible MOV (H.264) using native AVFoundation/VideoToolbox.
    /// Used for fast preparation/preview. Supports Trimming.
    func convertToNativelyPlayable(inputURL: URL, outputURL: URL, timeRange: CMTimeRange? = nil, progressHandler: ((Double) -> Void)? = nil) async throws {
        if inputURL.pathExtension.lowercased() == "webm" {
            // Convert WebM to native MOV, applying trimming if timeRange is provided.
            try await prepareNativelyPlayableWithFFmpeg(inputURL: inputURL, outputURL: outputURL, timeRange: timeRange, progressHandler: progressHandler)
            return
        }
        
        let asset = AVURLAsset(url: inputURL)
        
        // 1. Initial Validation
        let isReadable: Bool
        let videoTracks: [AVAssetTrack]
        let assetDuration: CMTime
        
        do {
            isReadable = try await asset.load(.isReadable)
            guard isReadable else {
                throw VideoConversionError.unsupportedFormat("File is not readable (isReadable=false)")
            }
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            assetDuration = try await asset.load(.duration)
        } catch {
            throw VideoConversionError.unsupportedFormat("Failed to load tracks: \(error.localizedDescription)")
        }
        
        guard let videoTrack = videoTracks.first else {
            throw VideoConversionError.conversionFailed("No video track found in source")
        }
        
        // 2. Setup Reader
        let reader = try AVAssetReader(asset: asset)
        // [Trimming] Configure the reader to only extract samples within the user-selected range.
        // Note: The extracted samples retain their original timestamps. 
        // The timestamp shift to 0 is handled later by writer.startSession(atSourceTime:).
        if let range = timeRange {
            reader.timeRange = range
        }
        
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        reader.add(readerOutput)
        
        // 3. Setup Writer
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(naturalSize.width),
            AVVideoHeightKey: Int(naturalSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 15_000_000 // 15 Mbps for high quality HEVC
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)
        
        // 4. Audio Processing
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioWriterInput: AVAssetWriterInput?
        
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio), let audioTrack = audioTracks.first {
            audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(audioReaderOutput!)
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128000
            ]
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            writer.add(audioWriterInput!)
        }
        
        // 5. Execution
        guard reader.startReading() else {
            throw VideoConversionError.conversionFailed("Reader failed to start: \(reader.error?.localizedDescription ?? "Unknown error")")
        }
        writer.startWriting()
        let sessionStartTime = timeRange?.start ?? .zero
        writer.startSession(atSourceTime: sessionStartTime)
        
        // Calculate expected duration for progress reporting
        let expectedDurationSeconds: Double
        if let range = timeRange {
             expectedDurationSeconds = range.duration.seconds
        } else {
             expectedDurationSeconds = assetDuration.seconds
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            
            group.enter()
            nonisolated(unsafe) let vInput = writerInput
            nonisolated(unsafe) let vOutput = readerOutput
            
            vInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video_transcode_queue")) {
                while vInput.isReadyForMoreMediaData {
                    if let sampleBuffer = vOutput.copyNextSampleBuffer() {
                        // AVAssetWriter handles CTS/PTS shifting automatically via startSession(atSourceTime:).
                        // We just need timingInfo for progress reporting.
                        var timingInfo = CMSampleTimingInfo()
                        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
                        
                        vInput.append(sampleBuffer)
                        
                        // Report Progress
                        if let progressHandler = progressHandler, expectedDurationSeconds > 0 {
                            // Calculate progress relative to the trim window
                            let currentPTS = timingInfo.presentationTimeStamp.seconds
                            let start = timeRange?.start.seconds ?? 0
                            let progress = min(max((currentPTS - start) / expectedDurationSeconds, 0.0), 1.0)
                            progressHandler(progress)
                        }
                    } else {
                        vInput.markAsFinished()
                        group.leave()
                        break
                    }
                }
            }
            
            if let aWriterInput = audioWriterInput, let aReaderOutput = audioReaderOutput {
                group.enter()
                nonisolated(unsafe) let aWriter = aWriterInput
                nonisolated(unsafe) let aOutput = aReaderOutput
                aWriter.requestMediaDataWhenReady(on: DispatchQueue(label: "audio_transcode_queue")) {
                    while aWriter.isReadyForMoreMediaData {
                        if let sampleBuffer = aOutput.copyNextSampleBuffer() {
                            aWriter.append(sampleBuffer)
                        } else {
                            aWriter.markAsFinished()
                            group.leave()
                            break
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                continuation.resume()
            }
        }
        
        await writer.finishWriting()
        progressHandler?(1.0)
    }

    /// Full Transcoding for Live Wallpaper Export (The Golden Formula).
    /// Always uses FFmpeg to ensure specific binary signaling (Temporal Layers, GOP) required by macOS.
    func convertToLiveWallpaper(inputURL: URL, outputURL: URL, timeRange: CMTimeRange? = nil, strategy: TranscodeStrategy, progressHandler: ((Double) -> Void)? = nil) async throws {
        Logger.video.info("Starting Golden Formula Export for: \(inputURL.lastPathComponent) with strategy: \(strategy.rawValue)")
        try await applyGoldenFormula(inputURL: inputURL, outputURL: outputURL, timeRange: timeRange, strategy: strategy, progressHandler: progressHandler)
    }

    /// Converts a video file to a lightweight MOV for fast preview using FFmpeg.
    private func prepareNativelyPlayableWithFFmpeg(inputURL: URL, outputURL: URL, timeRange: CMTimeRange? = nil, progressHandler: ((Double) -> Void)? = nil) async throws {
        let bridge = try FFmpegBridge(path: inputURL.path)
        let startTime = timeRange?.start.seconds ?? 0
        var endTime = timeRange.map { $0.start.seconds + $0.duration.seconds } ?? 0
        
        if endTime > 0 && endTime >= (bridge.duration - 0.1) {
             endTime = 0
        }
        
        // Execute on a dedicated background thread to prevent blocking Swift Concurrency pool
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try bridge.prepareToMov(outputUrl: outputURL, startTime: startTime, endTime: endTime) { progress in
                        DispatchQueue.main.async {
                            progressHandler?(progress)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        progressHandler?(1.0)
    }

    /// Full Transcoding with x265 and specific live wallpaper parameters.
    private func applyGoldenFormula(inputURL: URL, outputURL: URL, timeRange: CMTimeRange? = nil, strategy: TranscodeStrategy, progressHandler: ((Double) -> Void)? = nil) async throws {
        let bridge = try FFmpegBridge(path: inputURL.path)
        let startTime = timeRange?.start.seconds ?? 0
        var endTime = timeRange.map { $0.start.seconds + $0.duration.seconds } ?? 0
        
        if endTime > 0 && endTime >= (bridge.duration - 0.1) {
             endTime = 0
        }
        
        // Map Strategy to FFmpeg settings
        let tonemap = (strategy == .hdrTonemap10Bit || strategy == .advancedColorAndChroma)
        let tenBit = true // All custom paths target 10-bit for quality
        
        let settings = FFmpegBridge.FFmpegTranscodeSettings(
            startTime: startTime,
            endTime: endTime,
            tonemap: tonemap,
            tenBit: tenBit
        )
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try bridge.exportToMov(outputUrl: outputURL, settings: settings) { progress in
                        // Future: Bridge will provide FFmpegMediaMetrics here
                        DispatchQueue.main.async {
                            progressHandler?(progress)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        progressHandler?(1.0)
    }
}
