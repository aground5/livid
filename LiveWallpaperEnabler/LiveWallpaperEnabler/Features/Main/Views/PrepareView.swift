import SwiftUI
import Foundation

struct PrepareView: View {
    // MARK: - Bindable ViewModel
    @Bindable
    var viewModel: MainViewModel
    @AppStorage("PrepareViewMode") private var viewMode: MediaBrowserViewMode = .list
    @State private var showDownloadPopover = false
    
    var body: some View {
        ZStack {
            MediaBrowser(
                title: "Library",
                items: viewModel.ingredients,
                selection: $viewModel.selectedIngredientID,
                viewMode: $viewMode,
                rowContent: { (ingredient: MediaIngredient) in
                    IngredientRowView(
                        ingredient: ingredient,
                        viewModel: viewModel,
                        isDownloading: viewModel.downloadStates[ingredient.id] != nil
                    )
                },
                gridContent: { (ingredient: MediaIngredient) in
                    IngredientGridItem(
                        ingredient: ingredient,
                        viewModel: viewModel,
                        isDownloading: viewModel.downloadStates[ingredient.id] != nil
                    )
                },
                onAdd: nil,
                onDelete: { (ingredient: MediaIngredient) in
                    viewModel.removeIngredient(ingredient)
                }
            )
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    #if DIRECT_DISTRIBUTION
                    // Download Options for YouTube
                    if let active = viewModel.activeIngredient, 
                       case .youtube(let metadata, let localURL) = active.source {
                        Button {
                            showDownloadPopover = true
                        } label: {
                            Label("Download Options", systemImage: localURL == nil ? "arrow.down.circle" : "arrow.down.circle.fill")
                        }
                        .popover(isPresented: $showDownloadPopover) {
                            YouTubeInfoSection(
                                metadata: metadata,
                                isDownloaded: localURL != nil,
                                activeDownload: viewModel.downloadStates[active.id],
                                onSelectResolution: { resolution in
                                    viewModel.downloadVideo(resolution: resolution)
                                },
                                onCancelDownload: {
                                    viewModel.cancelDownload(for: active.id)
                                }
                            )
                            .padding()
                            .frame(width: 320)
                        }
                    }
                    #endif
                    
                    Menu {
                        Button(action: { viewModel.selectFile() }) {
                            Label("Local File", systemImage: "folder")
                        }
                        #if DIRECT_DISTRIBUTION
                        Button(action: { viewModel.showYouTubeInput = true }) {
                            Label("YouTube Link", systemImage: "video.badge.plus")
                        }
                        #endif
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            
            // Floating Action Bar for "Start Editing"
            if let active = viewModel.activeIngredient, active.source.localURL != nil, !active.isOffline {
                VStack {
                    Spacer()
                    StartEditingBar(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectedTab = .edit
                        }
                    })
                    .padding(.bottom, 32)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if DIRECT_DISTRIBUTION
        .sheet(isPresented: $viewModel.showYouTubeInput) {
            YouTubeURLInputSheet(viewModel: viewModel)
        }
        #endif
        .alert("Import Error", isPresented: Binding(
            get: { viewModel.importState.error != nil },
            set: { if !$0 { /* Error clearing handled by service state */ } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.importState.error ?? "Unknown error")
        }
        .overlay {
            if viewModel.importState.isImporting {
                LoadingOverlay(
                    message: !viewModel.importState.status.isEmpty ? viewModel.importState.status : (viewModel.activeIngredient?.source.localURL == nil ? "Fetching..." : "Processing..."),
                    progress: viewModel.importState.progress
                )
            }
        }
        .onChange(of: viewModel.selectedIngredientID) { oldID, newID in
            if let newID, let ingredient = viewModel.ingredients.first(where: { $0.id == newID }) {
                viewModel.selectIngredient(ingredient)
            }
        }
    }
}


// MARK: - Row & Grid Items
private struct IngredientRowView: View {
    let ingredient: MediaIngredient
    let viewModel: MainViewModel
    let isDownloading: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if ingredient.isOffline {
                    Rectangle()
                        .fill(Color.red.opacity(0.1))
                    Image(systemName: "video.slash.fill")
                        .foregroundStyle(.red.opacity(0.6))
                        .font(.caption)
                } else if case .youtube(let metadata, _) = ingredient.source {
                    AsyncImage(url: URL(string: metadata.thumbnail ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.secondary.opacity(0.1)
                    }
                } else if let image = viewModel.getThumbnail(for: ingredient) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.blue.opacity(0.1))
                    Image(systemName: "film")
                        .foregroundStyle(.blue.opacity(0.5))
                }
            }
            .frame(width: 48, height: 32)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .overlay {
                if isDownloading {
                    ZStack {
                        Color.black.opacity(0.4)
                        ProgressView()
                            .controlSize(.small)
                            .colorScheme(.dark)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.caption2)
                    Text(subtitle)
                        .font(.caption2)
                    
                    if ingredient.isOffline {
                        Text("•")
                        Text("Offline")
                            .font(.system(size: 9, weight: .bold)) // Smaller size for indicator
                    }
                }
                .foregroundStyle(ingredient.isOffline ? Color.red : .secondary)
            }
            
            Spacer()
            
            if ingredient.source.localURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
        .opacity(ingredient.isOffline ? 0.6 : 1.0)
        .grayscale(ingredient.isOffline ? 1.0 : 0.0)
    }
    
    var iconName: String {
        switch ingredient.source {
        case .local: return "folder"
        case .youtube: return "play.rectangle.fill"
        }
    }
    
    var subtitle: String {
        switch ingredient.source {
        case .local: return "Local"
        case .youtube: return "YouTube"
        }
    }
}

private struct IngredientGridItem: View {
    let ingredient: MediaIngredient
    let viewModel: MainViewModel
    let isDownloading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail Container with fixed aspect ratio
            Color.clear
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    ZStack {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                        
                        if ingredient.isOffline {
                            VStack(spacing: 8) {
                                Image(systemName: "video.slash.fill")
                                    .font(.title3)
                                Text("Offline")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(.red.opacity(0.6))
                        } else if case .youtube(let metadata, _) = ingredient.source {
                            AsyncImage(url: URL(string: metadata.thumbnail ?? "")) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView().controlSize(.small)
                            }
                        } else if let image = viewModel.getThumbnail(for: ingredient) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "film")
                                .font(.title)
                                .foregroundStyle(.blue.opacity(0.5))
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .overlay {
                    if isDownloading {
                        ZStack {
                            Color.black.opacity(0.4)
                            ProgressView()
                                .controlSize(.regular)
                                .colorScheme(.dark)
                        }
                    }
                }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
                    Image(systemName: iconName)
                    Text(subtitle)
                    
                    if ingredient.isOffline {
                        Text("•")
                        Text("Offline")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .font(.caption2)
                .foregroundStyle(ingredient.isOffline ? Color.red : .secondary)
            }
        }
        .opacity(ingredient.isOffline ? 0.7 : 1.0)
        .grayscale(ingredient.isOffline ? 1.0 : 0.0)
    }
    
    var iconName: String {
        switch ingredient.source {
        case .local: return "folder"
        case .youtube: return "play.rectangle.fill"
        }
    }
    
    var subtitle: String {
        switch ingredient.source {
        case .local: return "Local"
        case .youtube: return "YouTube"
        }
    }
}

private struct StartEditingBar: View {
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "scissors")
                    .font(.title2)
                Text("Start Editing")
                    .font(.title3.bold())
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Theme.Colors.liquidGradient)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: isHovering ? 20 : 10, y: isHovering ? 10 : 5)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct LoadingOverlay: View {
    let message: String
    var progress: Double = 0.0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            VStack(spacing: 16) {
                if progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text("\(message) \(Int(progress * 100))%")
                        .font(.headline)
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.regular)
                    Text(message)
                        .font(.headline)
                }
            }
            .padding(32)
            .background(.regularMaterial)
            .cornerRadius(16)
        }
    }
}

#if DIRECT_DISTRIBUTION
// MARK: - Simplified YouTube Info & Download
private struct YouTubeInfoSection: View {
    let metadata: YTDLPMetadata
    let isDownloaded: Bool
    let activeDownload: DownloadState?
    let onSelectResolution: (Int) -> Void
    let onCancelDownload: () -> Void
    
    var availableResolutions: [Int] {
        let allHeights = metadata.formats.compactMap { $0.height }
        let unique = Set(allHeights)
        // Filter out small sizes (<360) if desired, but keep for now
        return unique.filter { $0 >= 360 }.sorted(by: >)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(activeDownload != nil ? "Downloading..." : "Video Info")
                        .font(.headline)
                    
                    if let download = activeDownload {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: download.progress)
                                .progressViewStyle(.linear)
                            
                            HStack {
                                Text(download.status)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Cancel", action: onCancelDownload)
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Text(metadata.title)
                            .font(.body)
                            .lineLimit(2)
                        if let uploader = metadata.uploader {
                            Text(uploader)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Resolution List
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Quality")
                        .font(.headline)
                    
                    if availableResolutions.isEmpty {
                        Text("No suitable video streams found.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(availableResolutions, id: \.self) { res in
                                Button {
                                    onSelectResolution(res)
                                } label: {
                                    HStack {
                                        Text("\(res)p")
                                            .font(.title3)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Image(systemName: "arrow.down.circle")
                                            .font(.title3)
                                            .foregroundStyle(Theme.Colors.accent)
                                    }
                                    .padding(12)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(activeDownload != nil)
                                .opacity(activeDownload != nil ? 0.6 : 1.0)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct YouTubeURLInputSheet: View {
    @Bindable
    var viewModel: MainViewModel
    @State private var url: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.liquidGradient)
            
            VStack(spacing: 8) {
                Text("Paste YouTube Link")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("We'll add this to your ingredients as a soft link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            TextField("https://youtube.com/watch?v=...", text: $url)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            
            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button(action: {
                    viewModel.fetchYouTubeStreams(url: url)
                    dismiss()
                }) {
                    Text("Add")
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}
#endif
