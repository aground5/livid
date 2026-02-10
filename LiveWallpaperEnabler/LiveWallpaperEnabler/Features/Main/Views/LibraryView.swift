import SwiftUI
import AppKit
import AVFoundation

struct LibraryView: View {
    @Bindable var viewModel: MainViewModel
    @AppStorage("LibraryViewMode") private var viewMode: MediaBrowserViewMode = .gallery
    @State private var selection: UUID?
    
    // Connect to WallpaperStore
    @State private var store = WallpaperStore.shared
    
    // Category Selection State
    @State private var itemToRegister: LiveWallpaperItem?
    
    // Rename State
    @State private var itemToRename: LiveWallpaperItem?
    @State private var renameText: String = ""
    @State private var isShowingRenameAlert = false
    
    var body: some View {
        MediaBrowser(
            title: "Your Wallpapers",
            items: store.wallpapers,
            selection: $selection,
            viewMode: $viewMode,
            rowContent: { item in
                LibraryRow(
                    item: item, 
                    onRegister: { itemToRegister = item },
                    onRename: {
                        itemToRename = item
                        renameText = item.displayName
                        isShowingRenameAlert = true
                    }
                )
            },
            gridContent: { item in
                LibraryGridItem(
                    item: item, 
                    onRegister: { itemToRegister = item },
                    onRename: {
                        itemToRename = item
                        renameText = item.displayName
                        isShowingRenameAlert = true
                    }
                )
            },
            onAdd: {
                // ... same as before
                viewModel.selectedTab = .prepare
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.selectFile()
                }
            }
        )
        .sheet(item: $itemToRegister) { item in
            CategorySelectionSheet(item: item)
        }
        .alert("Rename Wallpaper", isPresented: $isShowingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let item = itemToRename {
                    store.updateName(id: item.id, newName: renameText)
                }
            }
        } message: {
            Text("Enter a new name for this wallpaper.")
        }
        .onAppear {
            AerialService.shared.loadManifest()
        }
        .overlay {
            if store.wallpapers.isEmpty {
                ContentUnavailableView(
                    "No Wallpapers Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Import a video to create your first Live Wallpaper.")
                )
            }
        }
    }
}

private struct LibraryRow: View {
    let item: LiveWallpaperItem
    let onRegister: () -> Void
    let onRename: () -> Void
    
    var body: some View {
        HStack {
            LiveThumbnailView(item: item)
                .frame(width: 80)
                .cornerRadius(4)
                .clipped()
            
            VStack(alignment: .leading) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.creationDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Duration Badge
            Text(String(format: "%.1fs", item.duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onRegister()
            } label: {
                Label("Register to Catalog", systemImage: "plus.square.on.square")
            }
            
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                WallpaperStore.shared.remove(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }
}

private struct LibraryGridItem: View {
    let item: LiveWallpaperItem
    let onRegister: () -> Void
    let onRename: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    LiveThumbnailView(item: item)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .overlay(durationOverlay)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.creationDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onRegister()
            } label: {
                Label("Register to Catalog", systemImage: "plus.square.on.square")
            }
            
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                WallpaperStore.shared.remove(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }
    
    private var durationOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(String(format: "%.1fs", item.duration))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(6)
            }
        }
    }
}

/// On-Demand Thumbnail Generator Component
private struct LiveThumbnailView: View {
    let item: LiveWallpaperItem
    @State private var image: NSImage?
    @State private var isGenerating = false
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
            
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isGenerating {
                ProgressView()
                // .controlSize(.small) // Might cause issues on some SDKs, remove if needed
            } else {
                Image(systemName: "photo")
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadOrGenerateThumbnail()
        }
    }
    
    private func loadOrGenerateThumbnail() {
        if image != nil { return }
        
        let thumbURL = item.thumbnailURL
        
        if let existingImage = NSImage(contentsOf: thumbURL) {
            self.image = existingImage
            return
        }
        
        // 3. Generate On-Demand
        generateThumbnail(outputURL: thumbURL)
    }
    
    private func generateThumbnail(outputURL: URL) {
        guard !isGenerating else { return }
        isGenerating = true
        
        Task.detached(priority: .background) {
            let asset = AVURLAsset(url: item.fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360) 
            
            do {
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                let cgImage = try await generator.image(at: time).image
                let nsImage = NSImage(cgImage: cgImage, size: .zero)
                
                // Cache to disk
                if let tiff = nsImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                    if let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: outputURL)
                    }
                }
                
                await MainActor.run {
                    self.image = nsImage
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                }
            }
        }
    }
}
