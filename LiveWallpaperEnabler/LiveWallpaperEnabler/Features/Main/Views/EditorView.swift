import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: MainViewModel
    @State private var showControls = true
    
    var body: some View {
        Group {
            if viewModel.selectedVideoURL != nil {
                ZStack {
                    // 1. Full-screen Video Background or Side-by-Side Comparison
                    Group {
                        if viewModel.isSideBySideActive, let url = viewModel.selectedVideoURL {
                            DualVideoComparisonView(
                                url: url,
                                startTime: $viewModel.startTime,
                                endTime: $viewModel.endTime,
                                videoSize: viewModel.playerService.videoSize,
                                fps: viewModel.playerService.fps,
                                timeScale: viewModel.playerService.timeScale
                            )
                        } else {
                            Color.black
                            if let player = viewModel.playerService.player {
                                NativeVideoPlayer(player: player)
                                    .onAppear {
                                        viewModel.playerService.play()
                                    }
                            } else {
                                ProgressView()
                                    .controlSize(.large)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: [.top, .bottom])
                    
                    
                    // 3. Floating Controls Overlay (Respects All Safe Areas)
                    VStack {
                        Spacer()
                        
                        if showControls {
                            floatingControlPanel
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(24) // Distance from edges
                }
                .onHover { isHovering in
                    withAnimation(.spring(response: 0.3)) {
                        showControls = isHovering
                    }
                }
                .onKeyDown(.c) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.isSideBySideActive = true
                        if viewModel.playerService.isPlaying {
                            viewModel.playerService.pause()
                        }
                    }
                }
                .onKeyUp(.c) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.isSideBySideActive = false
                    }
                }
                .onKeyDown(.space) {
                    togglePlayback()
                }
                .onKeyDown(.l) {
                    viewModel.isLooping.toggle()
                }
            } else {
                PlaceholderView(
                    icon: "scissors",
                    title: "Editor Empty",
                    message: "Select a video from the Start tab to begin editing.",
                    actionTitle: "Go to Start",
                    action: { viewModel.selectedTab = .prepare }
                )
            }
        }
    }
    
    private var floatingControlPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Left: Play/Pause Button
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: viewModel.playerService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                
                // Center: Filmstrip Timeline (Flex width)
                GeometryReader { geometry in
                    FilmstripTimeline(
                        thumbnails: viewModel.thumbnails,
                        startTime: $viewModel.startTime,
                        endTime: $viewModel.endTime,
                        currentTime: Binding(
                            get: { viewModel.playerService.currentTime },
                            set: { time in viewModel.playerService.seek(to: time) }
                        ),
                        duration: viewModel.videoDuration,
                        fps: viewModel.playerService.fps,
                        onSeek: { time in
                            viewModel.playerService.seek(to: time)
                            if viewModel.playerService.isPlaying {
                                viewModel.playerService.pause()
                            }
                        }
                    )
                    .onAppear {
                        viewModel.timelineWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        viewModel.timelineWidth = newWidth
                    }
                }
                .frame(height: 80)
                
                // Right: Next Button
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.selectedTab = .render
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.liquidGradient)
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Subtle Control Extras
            HStack(spacing: 20) {
                // Loop Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isLooping ? Color.orange : Color.gray.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text("LOOP PREVIEW (L)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(viewModel.isLooping ? .orange : .white.opacity(0.4))
                }
                .onTapGesture {
                    viewModel.isLooping.toggle()
                }
                
                // Trim Preview Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        viewModel.isSideBySideActive.toggle()
                        if viewModel.isSideBySideActive && viewModel.playerService.isPlaying {
                            viewModel.playerService.pause()
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isSideBySideActive ? "viewfinder.circle.fill" : "viewfinder")
                            .font(.system(size: 11))
                        Text("SIDE-BY-SIDE (Hold C)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(viewModel.isSideBySideActive ? .blue : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                // Frosted Glass Effect
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                // Outer Border
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .frame(maxWidth: 900) // Slightly wider for better timeline scrubbing space
    }
    
    private func togglePlayback() {
        if viewModel.playerService.isPlaying {
            viewModel.playerService.pause()
        } else {
            // Apply Policy: Check boundaries before playing
            viewModel.playerService.playbackLimit = viewModel.endTime
            viewModel.playerService.play(at: viewModel.startTime, endTime: viewModel.endTime)
        }
    }
    
    private func timeString(from seconds: Double) -> String {
        let minute = Int(seconds) / 60
        let second = Int(seconds) % 60
        return String(format: "%02d:%02d", minute, second)
    }
}
