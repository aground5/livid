import AVFoundation
import Combine
import Observation
import QuartzCore
import AppKit

@Observable
class VideoPlayerService: NSObject {
    var player: AVPlayer?
    var isPlaying = false
    var duration: Double = 0.0
    var currentTime: Double = 0.0
    var videoSize: CGSize = .zero
    var fps: Double = 30.0
    var timeScale: CMTimeScale = 600
    var currentFrame: Int {
        return Int(round(currentTime * fps))
    }
    var playbackLimit: Double?
    
    private var displayLink: CADisplayLink?
    
    override init() {
        super.init()
        setupDisplayLink()
    }
    
    func loadVideo(at url: URL) async throws -> (duration: Double, size: CGSize, fps: Double) {
        let asset = AVURLAsset(url: url)
        let duration: CMTime = try await asset.load(.duration)
        let allTracks = try await asset.load(.tracks)
        let videoTracks = allTracks.filter { $0.mediaType == .video }
        
        var size: CGSize = .zero
        var nominalFps: Double = 30.0
        var naturalTimeScale: CMTimeScale = 600
        
        if let track = videoTracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            size = CGSize(width: abs(rect.width), height: abs(rect.height))
            nominalFps = Double(try await track.load(.nominalFrameRate))
            naturalTimeScale = try await track.load(.naturalTimeScale)
        }
        
        let item = AVPlayerItem(asset: asset)
        
        await MainActor.run {
            self.duration = duration.seconds
            self.videoSize = size
            self.fps = nominalFps > 0 ? nominalFps : 30.0
            self.timeScale = naturalTimeScale
            self.currentTime = 0
            self.player = AVPlayer(playerItem: item)
            
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.isPlaying = false
            }
        }
        
        return (duration.seconds, size, nominalFps)
    }
    
    func play(at startTime: Double? = nil, endTime: Double? = nil) {
        if let current = player?.currentTime().seconds {
            let start = startTime ?? (loopRange?.lowerBound ?? 0)
            let end = endTime ?? (loopRange?.upperBound ?? duration)
            if current >= end - 0.01 || current < start - 0.01 {
                seek(to: start)
            }
        }
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func seek(to time: Double) {
        // Optimistic UI update: Update immediately so slider doesn't jump back
        self.currentTime = time
        
        // Use natural timescale for seeking
        let cmTime = CMTime(seconds: time, preferredTimescale: self.timeScale)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    var loopRange: Range<Double>?
    
    private func setupDisplayLink() {
        displayLink?.invalidate()
        
        // Correct way for macOS 14+: Create display link from NSScreen
        // This automatically tracks the display's refresh rate (incl. ProMotion)
        displayLink = NSScreen.main?.displayLink(target: self, selector: #selector(displayLinkDidTick))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func displayLinkDidTick() {
        guard let player = player else { return }
        
        let newTime = player.currentTime().seconds
        guard newTime.isFinite else { return }
        
        // Update observable state only if changed significantly (prevent unnecessary SwiftUI refreshes)
        if (self.currentTime - newTime).magnitude > 0.001 {
            self.currentTime = newTime
        }
        
        let isActuallyPlaying = player.rate != 0
        
        // Handling Logic
        if isActuallyPlaying {
            // Sync internal state just in case
            if !isPlaying { isPlaying = true }
            
            if let range = loopRange {
                if newTime >= range.upperBound - (1.0 / fps) {
                    seek(to: range.lowerBound)
                }
            }
            
            if let limit = playbackLimit, newTime >= limit {
                pause()
                seek(to: limit)
            }
        } else {
            // Sync internal state if paused externally
            if isPlaying { isPlaying = false }
        }
    }
    
    deinit {
        displayLink?.invalidate()
    }
}
