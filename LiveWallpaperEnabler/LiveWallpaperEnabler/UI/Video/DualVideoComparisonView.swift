import SwiftUI
import AVFoundation

struct DualVideoComparisonView: View {
    let url: URL
    @Binding var startTime: Double
    @Binding var endTime: Double
    let videoSize: CGSize
    let fps: Double
    let timeScale: CMTimeScale
    
    @State private var startPlayer = AVPlayer()
    @State private var endPlayer = AVPlayer()
    
    var body: some View {
        GeometryReader { proxy in
            let halfWidth = proxy.size.width / 2
            let size = proxy.size
            
            HStack(spacing: 0) {
                // Left: Start Frame
                ManualFitVideoPlayer(
                    player: startPlayer,
                    label: "START",
                    time: startTime,
                    containerSize: CGSize(width: halfWidth, height: size.height),
                    videoSize: videoSize,
                    fps: fps
                )
                .onChange(of: startTime) { _, newTime in
                    seek(player: startPlayer, to: newTime)
                }
                
                // Right: End Frame
                ManualFitVideoPlayer(
                    player: endPlayer,
                    label: "END",
                    time: endTime,
                    containerSize: CGSize(width: halfWidth, height: size.height),
                    videoSize: videoSize,
                    fps: fps
                )
                .onChange(of: endTime) { _, newTime in
                    seek(player: endPlayer, to: newTime)
                }
            }
        }
        .background(Color.black)
        .onAppear {
            setupPlayers()
        }
        .onDisappear {
            startPlayer.pause()
            endPlayer.pause()
            startPlayer.replaceCurrentItem(with: nil)
            endPlayer.replaceCurrentItem(with: nil)
        }
    }
    
    private func setupPlayers() {
        let startItem = AVPlayerItem(url: url)
        let endItem = AVPlayerItem(url: url)
        startPlayer.replaceCurrentItem(with: startItem)
        endPlayer.replaceCurrentItem(with: endItem)
        seek(player: startPlayer, to: startTime)
        seek(player: endPlayer, to: endTime)
    }
    
    private func seek(player: AVPlayer, to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: timeScale)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

struct ManualFitVideoPlayer: View {
    let player: AVPlayer
    let label: String
    let time: Double
    let containerSize: CGSize
    let videoSize: CGSize
    let fps: Double
    
    @State private var observedTime: Double = 0
    @State private var timeObserver: Any?
    
    private var fittedRect: CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        
        let screenAspect = containerSize.width / containerSize.height
        let videoAspect = videoSize.width / videoSize.height
        
        var drawSize = containerSize
        if videoAspect > screenAspect {
            drawSize.height = containerSize.width / videoAspect
        } else {
            drawSize.width = containerSize.height * videoAspect
        }
        
        return CGRect(
            x: (containerSize.width - drawSize.width) / 2,
            y: (containerSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
    
    var body: some View {
        ZStack {
            Color.clear // Transparent container
            
            // The Video Frame
            ZStack(alignment: .top) {
                NativeVideoPlayer(player: player)
                
                // Pure White Label with Time
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 32, weight: .black))
                    
                    Text(TimeFormatter.format(seconds: observedTime, fps: fps))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .opacity(0.8)
                }
                .foregroundColor(.white)
                .tracking(2)
                .opacity(0.7)
                .padding(.top, 30)
            }
            .frame(width: fittedRect.width, height: fittedRect.height)
            .position(x: containerSize.width / 2, y: containerSize.height / 2)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .onAppear {
            setupObserver()
        }
        .onDisappear {
            removeObserver()
        }
        .onChange(of: time) { _, _ in
            // Fallback: If player hasn't sought yet, improve responsiveness by pre-setting (optional, but good UX)
            // But user explicitly wanted PLAYER time. So let's stick to observer,
            // OR we can optimistic update? -> User said "Get player.currentTime()".
            // So we rely on observer.
        }
    }
    
    private func setupObserver() {
        observedTime = player.currentTime().seconds
        // Update frequently enough (e.g., 30fps checks) to catch seek completions
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { cmTime in
            observedTime = cmTime.seconds
        }
    }
    
    private func removeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
}

