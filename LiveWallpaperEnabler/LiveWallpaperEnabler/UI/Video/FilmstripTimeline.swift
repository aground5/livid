import SwiftUI
import AppKit

// MARK: - Main Container
struct FilmstripTimeline: View {
    let thumbnails: [NSImage]
    @Binding var startTime: Double
    @Binding var endTime: Double
    @Binding var currentTime: Double
    let duration: Double
    let fps: Double
    
    var onSeek: ((Double) -> Void)?
    
    // Hoisted State for Tooltip Visibility
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingRange = false
    @State private var isScrubbing = false
    
    // Layout Constants
    private let height: CGFloat = 80
    private let cornerRadius: CGFloat = 12
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            ZStack(alignment: .leading) {
                // 0. Scrub Interaction Layer (Bottom - catches clicks)
                Color.black.opacity(0.001)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isScrubbing = true
                                let rawTime = Double(value.location.x / totalWidth) * duration
                                
                                // Snap to frame
                                let validFps = fps > 0 ? fps : 30
                                let snappedTime = round(rawTime * validFps) / validFps
                                
                                let clamped = max(0, min(duration, snappedTime))
                                currentTime = clamped
                                onSeek?(clamped)
                            }
                            .onEnded { _ in isScrubbing = false }
                    )
                
                // 1. Background & Thumbnails (Visual Only)
                TimelineTrackView(thumbnails: thumbnails, cornerRadius: cornerRadius)
                    .frame(height: height)
                    .allowsHitTesting(false)
                
                // 2. Range Selection & Handles
                VideoRangeSlider(
                    startTime: $startTime,
                    endTime: $endTime,
                    isDraggingStart: $isDraggingStart,
                    isDraggingEnd: $isDraggingEnd,
                    isDraggingRange: $isDraggingRange,
                    duration: duration,
                    fps: fps,
                    totalWidth: totalWidth,
                    height: height,
                    cornerRadius: cornerRadius,
                    onSeek: onSeek
                )
                
                // 3. Premium Playhead (Current Time Indicator)
                VStack(spacing: 0) {
                    // Head Cap
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    
                    // Main Line
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2, height: height)
                        .shadow(color: .white.opacity(0.5), radius: 3)
                }
                .offset(x: position(for: currentTime, width: totalWidth) - 4, y: -4)
                .allowsHitTesting(false)
            }
            .overlay(
                // Floating Tooltips Layer (Outside layout flow)
                ZStack {
                    if isDraggingStart || isDraggingRange {
                        TimeTooltip(time: startTime, fps: fps)
                            .position(x: position(for: startTime, width: totalWidth), y: -25)
                    }
                    
                    if isDraggingEnd || isDraggingRange {
                        TimeTooltip(time: endTime, fps: fps)
                            .position(x: position(for: endTime, width: totalWidth), y: -25)
                    }
                    
                    if isScrubbing {
                        TimeTooltip(time: currentTime, fps: fps)
                            .position(x: position(for: currentTime, width: totalWidth), y: -25)
                    }
                }
                .allowsHitTesting(false),
                alignment: .topLeading
            )
        }
        .frame(height: height)
        .padding(.horizontal)
    }
    
    private func position(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }
}

// MARK: - Component: Timeline Track (Visuals)
struct TimelineTrackView: View {
    let thumbnails: [NSImage]
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack {
            // Glass Base: Ensure material and color are both clipped to the rounded shape
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            
            if !thumbnails.isEmpty {
                HStack(spacing: 0) {
                    ForEach(thumbnails, id: \.self) { image in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 80)
                            .opacity(0.85) // Increase bleed-through
                            .clipped()
                    }
                }
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .clipped()
            }
        }
    }
}

// MARK: - Component: Video Range Slider (Selection Logic)
struct VideoRangeSlider: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    @Binding var isDraggingStart: Bool
    @Binding var isDraggingEnd: Bool
    @Binding var isDraggingRange: Bool
    
    let duration: Double
    let fps: Double
    let totalWidth: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    var onSeek: ((Double) -> Void)?
    
    // Stable references for drag operations
    @State private var initialStartTime: Double = 0
    @State private var initialEndTime: Double = 0
        
    var body: some View {
        let startPos = position(for: startTime)
        let endPos = position(for: endTime)
        let selectionWidth = max(0, endPos - startPos)
        
        ZStack(alignment: .leading) {
            // 1. Unified Selection Frame (Handles + Borders)
            ZStack(alignment: .leading) {
                // Top & Bottom Horizontal Borders
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.Colors.liquidStart, Theme.Colors.liquidEnd], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 3)
                    Spacer()
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.Colors.liquidEnd, Theme.Colors.liquidStart], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 3)
                }
                .frame(width: selectionWidth, height: height)
                .offset(x: startPos)
                
                // Start Handle ([)
                TrimHandle(isLeading: true, height: height, isDragging: isDraggingStart)
                    .offset(x: startPos - 30)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDraggingStart {
                                    isDraggingStart = true
                                    initialStartTime = startTime
                                }
                                let deltaSeconds = Double(value.translation.width / totalWidth) * duration
                                let newStart = snap(max(0, min(initialStartTime + deltaSeconds, endTime - 0.5))) // Snap
                                startTime = newStart
                                onSeek?(newStart)
                            }
                            .onEnded { _ in isDraggingStart = false }
                    )
                
                // End Handle (])
                TrimHandle(isLeading: false, height: height, isDragging: isDraggingEnd)
                    .offset(x: endPos)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDraggingEnd {
                                    isDraggingEnd = true
                                    initialEndTime = endTime
                                }
                                let deltaSeconds = Double(value.translation.width / totalWidth) * duration
                                let newEnd = snap(min(duration, max(initialEndTime + deltaSeconds, startTime + 0.5))) // Snap
                                endTime = newEnd
                                onSeek?(newEnd)
                            }
                            .onEnded { _ in isDraggingEnd = false }
                    )
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingRange {
                            isDraggingRange = true
                            initialStartTime = startTime
                            initialEndTime = endTime
                        }
                        
                        let deltaSeconds = Double(value.translation.width / totalWidth) * duration
                        let currentDuration = initialEndTime - initialStartTime
                        
                        // Snap logic for range drag
                        let rawNewStart = initialStartTime + deltaSeconds
                        var newStart = snap(rawNewStart)
                        var newEnd = snap(newStart + currentDuration)
                        
                        // Bound checks
                        if newStart < 0 {
                            newStart = 0
                            newEnd = snap(currentDuration)
                        } else if newEnd > duration {
                            newEnd = snap(duration)
                            newStart = snap(duration - currentDuration)
                        }
                        
                        startTime = newStart
                        endTime = newEnd
                        onSeek?(newStart)
                    }
                    .onEnded { _ in isDraggingRange = false }
            )
        }
        .allowsHitTesting(true)
    }
    
    private func position(for time: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * totalWidth
    }
    
    private func snap(_ time: Double) -> Double {
        let validFps = fps > 0 ? fps : 30.0
        return round(time * validFps) / validFps
    }
}

// MARK: - Component: Time Tooltip
struct TimeTooltip: View {
    let time: Double
    let fps: Double
    
    var body: some View {
        Text(TimeFormatter.format(seconds: time, fps: fps))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.bottom, 6) // Space for the arrow tail
            .background(
                TooltipBubble()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        TooltipBubble()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .fixedSize()
    }
}

// Custom Speech Bubble Shape
struct TooltipBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arrowWidth: CGFloat = 10
        let arrowHeight: CGFloat = 6
        let bodyHeight = rect.height - arrowHeight
        let cornerRadius: CGFloat = 8
        
        // Rounded Rectangle Body
        let bodyRect = CGRect(x: 0, y: 0, width: rect.width, height: bodyHeight)
        path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        
        // Triangle Tail at bottom center
        path.move(to: CGPoint(x: rect.midX - arrowWidth / 2, y: bodyHeight))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        path.addLine(to: CGPoint(x: rect.midX + arrowWidth / 2, y: bodyHeight))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Utility: Time Formatter
struct TimeFormatter {
    static func format(seconds: Double, fps: Double) -> String {
        guard seconds.isFinite else { return "00:00.00" }
        
        let validFps = fps > 0 ? fps : 30.0
        let roundedFps = Int(round(validFps)) // Fix: 29.97 -> 30, not 29
        let divisor = roundedFps > 0 ? roundedFps : 30
        
        let totalFrames = Int(round(seconds * validFps))
        
        let minutes = totalFrames / (divisor * 60)
        let secs = (totalFrames / divisor) % 60
        let frames = totalFrames % divisor
        
        return String(format: "%02d:%02d.%02d", minutes, secs, frames)
    }
}

// MARK: - Component: Trim Handle (Visual)
struct TrimHandle: View {
    let isLeading: Bool
    let height: CGFloat
    let isDragging: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: isLeading ? .trailing : .leading) {
            // Hit Target (Wider for better UX)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 30, height: height)
            
            // Visual Bar (Bracket Style)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: isLeading ? [Theme.Colors.liquidStart, Theme.Colors.liquidEnd] : [Theme.Colors.liquidEnd, Theme.Colors.liquidStart],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 20, height: height)
                .clipShape(
                    .rect(
                        topLeadingRadius: isLeading ? 10 : 0,
                        bottomLeadingRadius: isLeading ? 10 : 0,
                        bottomTrailingRadius: isLeading ? 0 : 10,
                        topTrailingRadius: isLeading ? 0 : 10
                    )
                )
                .overlay(
                    VStack(spacing: 3) {
                        Capsule().fill(Color.white.opacity(0.8)).frame(width: 2, height: 16)
                        Capsule().fill(Color.white.opacity(0.8)).frame(width: 2, height: 16)
                    }
                )
                .shadow(color: .black.opacity(0.3), radius: 3)
        }
        .onHover { hover in
            isHovering = hover
            if hover { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
    }
}
