import SwiftUI

struct RenderView: View {
    @Bindable var viewModel: MainViewModel
    
    // We observe the singleton directly to ensure fine-grained updates for the list
    private var queueService = RenderQueueService.shared
    
    init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Live Wallpaper")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                
                Picker("View Mode", selection: $viewModel.isAdvancedInfoMode) {
                    Text("Simple").tag(false)
                    Text("Advanced Info").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding([.horizontal, .top], 40)
            .padding(.bottom, 20)
            
            ScrollView {
                VStack(spacing: 32) {
                    // SECTION 1: Current Selection Details (Restored)
                    if viewModel.selectedVideoURL != nil {
                        currentSelectionView
                    } else {
                        PlaceholderView(
                            icon: "cpu",
                            title: "Ready to Render",
                            message: "Select a video from the Start tab to see export details.",
                            actionTitle: "Go to Start",
                            action: { viewModel.selectedTab = .prepare }
                        )
                    }
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    // SECTION 2: Render Queue List
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Queue Status")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                            if !queueService.jobs.isEmpty {
                                Button("Clear Completed") {
                                    queueService.clearCompleted()
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                        .padding(.horizontal, 40)
                        
                        if queueService.jobs.isEmpty {
                            EmptyQueueView()
                                .frame(height: 150) // Compact empty state
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(queueService.jobs.reversed()) { job in
                                    RenderJobRow(job: job)
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var currentSelectionView: some View {
        VStack(spacing: 24) {
            // Preview Card
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.clear)
                        .aspectRatio(16/9, contentMode: .fit)
                        
                    if !viewModel.thumbnails.isEmpty {
                        Image(nsImage: viewModel.thumbnails[0])
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(16)
                    }
                    
                    // Overlay loop icon if looping
                    if viewModel.isLooping {
                         Image(systemName: "repeat")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 180)
                .shadow(radius: 10)
                
                // Basic Info Summary & Action
                 VStack(alignment: .leading, spacing: 16) {
                     VStack(alignment: .leading, spacing: 8) {
                         let metadata = viewModel.sourceMetadata
                         InfoRow(icon: "clock", label: "Duration", value: String(format: "%.2f sec", viewModel.endTime - viewModel.startTime))
                         InfoRow(icon: "scissors", label: "Trimmed", value: viewModel.startTime > 0 || viewModel.endTime < viewModel.videoDuration ? "Yes" : "No")
                         InfoRow(icon: "aspectratio", label: "Resolution", value: metadata?.resolutionLabel ?? "\(Int(viewModel.playerService.videoSize.width))p")
                     }
                     
                     Spacer()
                     
                     // Add to Queue Button (Prominent)
                     Button(action: {
                         viewModel.addToRenderQueue()
                     }) {
                         HStack {
                             Image(systemName: "plus.circle.fill")
                             Text("Add to Render Queue")
                         }
                         .font(.headline)
                         .frame(maxWidth: .infinity)
                         .padding(.vertical, 12)
                         .background(Theme.Colors.accent)
                         .foregroundColor(.white)
                         .cornerRadius(12)
                     }
                     .buttonStyle(.plain)
                 }
                 .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Advanced Information Section
            if viewModel.isAdvancedInfoMode {
                advancedInfoView
            } else {
                simpleInfoView
            }
        }
        .padding(.horizontal, 40)
    }
    
    private var advancedInfoView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Technical Specifications")
                .font(.title3)
                .fontWeight(.semibold)
            
            // 1. Source Metadata (Real Data)
            if let metadata = viewModel.sourceMetadata {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Source File")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        InfoCard(title: "Codec", icon: "film", value: metadata.codec)
                        InfoCard(title: "Resolution", icon: "arrow.up.left.and.arrow.down.right", value: "\(metadata.width)×\(metadata.height)")
                        InfoCard(title: "Frame Rate", icon: "speedometer", value: String(format: "%.0f fps", metadata.fps))
                        InfoCard(title: "Bitrate", icon: "waveform", value: String(format: "%.1f Mbps", metadata.bitrateMbps))
                        InfoCard(title: "Color", icon: "paintpalette", value: metadata.colorSpace)
                        InfoCard(title: "Bit Depth", icon: "square.stack.3d.down.right", value: "\(metadata.bitDepth)-bit")
                        InfoCard(title: "Chroma", icon: "circle.grid.3x3.fill", value: metadata.chromaSubsampling)
                        InfoCard(title: "Audio", icon: "speaker.wave.2", value: metadata.audioFormat ?? (metadata.hasAudio ? "Present" : "Muted"))
                    }
                }
                
                // 2. Smart Strategy Logic
                VStack(alignment: .leading, spacing: 12) {
                    Text("Optimal Strategy")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundColor(Theme.Colors.accent)
                            .padding(12)
                            .background(Theme.Colors.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metadata.transcodeStrategy.rawValue)
                                .font(.headline)
                            Text(metadata.transcodeStrategy.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            
            simpleInfoView
        }
    }
    
    private var simpleInfoView: some View {
        HStack {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 30))
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 50)
                
            VStack(alignment: .leading, spacing: 4) {
                Text("Optimized for macOS")
                    .font(.headline)
                Text("We automatically select the best settings to ensure your wallpaper plays smoothly and efficiently on your Mac's Lock Screen.")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Shared Components (Job Row, Status Badge)

struct RenderJobRow: View {
    let job: RenderJob
    
    var body: some View {
        HStack(spacing: 16) {
            // 1. Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 120, height: 68)
                
                if let thumb = job.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 68)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.2))
                }
                
                if job.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            
            // 2. Info & Progress
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(job.originalFilename)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    RenderStatusBadge(status: job.status)
                }
                
                if case .rendering = job.status {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: job.progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: Theme.Colors.accent))
                        
                        HStack {
                            Text("\(Int(job.progress * 100))%")
                                .font(.caption).bold()
                            Spacer()
                            HStack(spacing: 12) {
                                Text(String(format: "%.1f FPS", job.fps))
                                Text(String(format: "%.1fx Speed", job.speed))
                                if let remaining = job.timeRemaining {
                                    Text(formatTime(remaining))
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        }
                    }
                } else if case .failed(let reason) = job.status {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                } else {
                    // Static Info
                    HStack {
                        Text(job.config.strategy.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                        
                        Spacer()
                        Text(job.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            
            // 3. Action
            Button(action: {
                RenderQueueService.shared.cancel(job.id)
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(job.status == .rendering || job.status == .pending ? 1.0 : 0.0)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(job.status == .rendering ? Theme.Colors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct RenderStatusBadge: View {
    let status: RenderStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    var color: Color {
        switch status {
        case .pending: return .orange
        case .rendering: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
    
    var label: String {
        switch status {
        case .pending: return "Pending"
        case .rendering: return "Running"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.dash.header.rectangle")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.3))
            Text("No Active Jobs")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
    }
}

// MARK: - Legacy Info Helper Views (Re-added)
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            // Make value selectable or truncated properly
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct InfoCard: View {
    let title: String
    let icon: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.Colors.accent)
                Text(title)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}
