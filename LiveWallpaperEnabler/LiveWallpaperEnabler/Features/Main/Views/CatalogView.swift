import SwiftUI

struct CatalogView: View {
    @Bindable var viewModel: MainViewModel
    @State private var aerialService = AerialService.shared
    @State private var itemToRegister: LiveWallpaperItem?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                headerSection
                
                if aerialService.isLoading {
                    ProgressView("Loading Wallpapers...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if aerialService.manifest != nil {
                    // Current Wallpaper Section
                    currentWallpaperSection
                    
                    // Categorized Sections (Sorted & Localized)
                    ForEach(aerialService.getCategories()) { category in
                        categorySection(category: category)
                    }
                }
            }
            .padding(30)
        }
        .sheet(item: $itemToRegister) { item in
            CategorySelectionSheet(item: item)
        }
        .onAppear {
            aerialService.loadManifest()
        }
    }
    
    private var headerSection: some View {
        HStack {
            Text("Wallpaper")
                .font(.system(size: 24, weight: .bold))
            Spacer()
        }
    }
    
    private var currentWallpaper: AerialAsset? {
        guard let id = aerialService.currentAssetID else { return nil }
        return aerialService.manifest?.assets.first { $0.id == id }
    }
    
    private var currentWallpaperSection: some View {
        let availability = currentWallpaper.map { aerialService.checkAvailability(for: $0.id) }
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Active System Wallpaper")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            
            HStack(spacing: 0) {
                // Large Preview
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let asset = currentWallpaper {
                            AsyncImage(url: URL(string: asset.previewImage)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.1)
                            }
                        } else {
                            Color.gray.opacity(0.2)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                    }
                    .frame(width: 280, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if let avail = availability {
                        HStack(spacing: 4) {
                            if !avail.hasVideo {
                                StatusBadge(text: "Offline", color: .red)
                            }
                            if !avail.hasThumbnail {
                                StatusBadge(text: "No Thumb", color: .orange)
                            }
                        }
                        .padding(8)
                    }
                }
                .padding(8)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentWallpaper.map { aerialService.getAssetName(for: $0) } ?? "Unknown or Non-Aerial")
                                .font(.system(size: 16, weight: .bold))
                            
                            Text(currentWallpaper != nil ? "Official Apple Aerial Wallpaper" : "System Dynamic/Static Wallpaper")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Action Button
                        if let selected = viewModel.selectedAerialAsset, selected.id != aerialService.currentAssetID {
                            let isAvailable = aerialService.checkAvailability(for: selected.id).hasVideo
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Button("Apply to Desktop") {
                                    aerialService.setWallpaper(assetID: selected.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .disabled(!isAvailable)
                                
                                if !isAvailable {
                                    Text("Download required in System Settings")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button("Refresh Status") {
                            aerialService.fetchCurrentWallpaperID()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 16)
                .padding(.trailing, 20)
                .padding(.leading, 10)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private func categorySection(category: AerialCategory) -> some View {
        CategorySectionView(category: category, viewModel: viewModel, aerialService: aerialService) { item in
            itemToRegister = item
        }
    }
}

struct CategorySectionView: View {
    let category: AerialCategory
    @Bindable var viewModel: MainViewModel
    let aerialService: AerialService
    let onRegister: (LiveWallpaperItem) -> Void
    @State private var showDeleteAlert = false
    
    var body: some View {
        let assets = aerialService.getAssets(for: category.id)
        let isCustom = aerialService.isCustomCategory(category.id)
        let sectionTitle = aerialService.localize(category.localizedNameKey)
        
        if assets.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text(sectionTitle)
                            .font(.system(size: 15, weight: .bold))
                        
                        if isCustom {
                            Text("Custom")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    if isCustom {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete this category and all its wallpapers")
                    }
                    
                    Button(action: {}) {
                        Text("See All (\(assets.count))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(assets) { asset in
                            AssetThumbnail(asset: asset, isSelected: viewModel.selectedAerialAsset?.id == asset.id, onRegister: onRegister)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        viewModel.selectedAerialAsset = asset
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .alert("Delete Category", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    _ = aerialService.deleteCustomCategory(categoryID: category.id)
                }
            } message: {
                Text("Are you sure you want to delete \"\(sectionTitle)\" and all \(assets.count) wallpaper(s) in it?")
            }
        }
    }
}


struct StatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.8))
            .clipShape(Capsule())
    }
}

struct AssetThumbnail: View {
    let asset: AerialAsset
    let isSelected: Bool
    let onRegister: (LiveWallpaperItem) -> Void
    private let aerialService = AerialService.shared
    @State private var showDeleteAlert = false
    
    var body: some View {
        let availability = aerialService.checkAvailability(for: asset.id)
        let isCustom = aerialService.isCustomAsset(asset.id)
        
        VStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if isCustom {
                    // Local Thumbnail
                    let thumbURL = aerialService.systemThumbnailURL(for: asset.id)
                    if let image = NSImage(contentsOf: thumbURL) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 170, height: 100)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.2))
                            .frame(width: 170, height: 100)
                    }
                } else {
                    AsyncImage(url: URL(string: asset.previewImage)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 170, height: 100)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.primary.opacity(0.05), lineWidth: isSelected ? 3 : 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .overlay(alignment: .bottomLeading) {
                // Play icon overlay if video is available
                if availability.hasVideo {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.system(size: 14))
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 2) {
                    if isCustom {
                        StatusBadge(text: "Custom", color: .blue)
                    }
                    if !availability.hasThumbnail {
                        StatusBadge(text: "No Thumb", color: .orange)
                    }
                    if !availability.hasVideo {
                        StatusBadge(text: "Offline", color: .red)
                    }
                }
                .padding(4)
            }
            
            // Use localized name (e.g., shotID_NAME)
            Text(aerialService.getAssetName(for: asset))
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(width: 170)
                .foregroundStyle(isSelected ? .blue : .primary)
        }
        .contextMenu {
            if isCustom {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Wallpaper", systemImage: "trash")
                }
            } else if availability.hasVideo {
                Button {
                    let videoURL = aerialService.systemVideoURL(for: asset.id)
                    let thumbURL = aerialService.systemThumbnailURL(for: asset.id)
                    
                    let item = LiveWallpaperItem(
                        id: UUID(),
                        filename: "\(asset.id).mov",
                        displayName: aerialService.getAssetName(for: asset),
                        creationDate: Date(),
                        duration: 0,
                        catalogAssetID: asset.id,
                        absolutePath: videoURL.path,
                        absoluteThumbnailPath: FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL.path : nil
                    )
                    onRegister(item)
                } label: {
                    Label("Register as Custom (Patch)", systemImage: "plus.square.on.square")
                }
            }
        }
        .alert("Delete Wallpaper", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _ = aerialService.deleteCustomAsset(assetID: asset.id)
            }
        } message: {
            Text("Are you sure you want to delete \"\(aerialService.getAssetName(for: asset))\"? This will remove it from the catalog.")
        }
    }
}


#Preview {
    CatalogView(viewModel: MainViewModel())
}
