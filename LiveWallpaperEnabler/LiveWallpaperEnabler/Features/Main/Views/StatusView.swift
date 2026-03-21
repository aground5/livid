import SwiftUI

struct StatusView: View {
    @Bindable var viewModel: MainViewModel
    @State private var aerialService = AerialService.shared
    @State private var selectedStatus: AerialService.WallpaperSpaceStatus? = nil
    @State private var isShowingSelection = false
    
    private var groupedStatuses: [(name: String, statuses: [AerialService.WallpaperSpaceStatus])] {
        let dictionary = Dictionary(grouping: aerialService.spaceStatuses) { $0.monitorName ?? "Unknown Monitor" }
        return dictionary.map { key, value in
            (name: key, statuses: value.sorted(by: { ($0.spaceNumber ?? 0) < ($1.spaceNumber ?? 0) }))
        }
        .sorted { $0.name < $1.name }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Management")
                            .font(.system(size: 28, weight: .bold))
                        Text("Manage wallpapers across monitors and spaces")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring()) {
                            aerialService.refreshSpaceStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Status")
                }
                .padding(.horizontal, 10)
                
                if aerialService.spaceStatuses.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("No active displays detected.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Button("Reload Status") {
                            aerialService.refreshSpaceStatus()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    // Global / All Spaces target
                    GlobalStatusSection(aerialService: aerialService) {
                        selectedStatus = nil // Represents "All"
                        isShowingSelection = true
                    }
                    
                    // Displays
                    ForEach(groupedStatuses, id: \.name) { group in
                        MonitorSection(name: group.name, statuses: group.statuses, aerialService: aerialService) { status in
                            selectedStatus = status
                            isShowingSelection = true
                        }
                    }
                }
            }
            .padding(30)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        .sheet(isPresented: $isShowingSelection) {
            WallpaperSelectionSheet(targetStatus: selectedStatus, aerialService: aerialService)
        }
        .onAppear {
            aerialService.refreshSpaceStatus()
        }
    }
}

struct GlobalStatusSection: View {
    let aerialService: AerialService
    let onSelect: () -> Void
    
    var body: some View {
        let globalStatus = aerialService.spaceStatuses.first(where: { $0.id == "All" })
        
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Global Configuration", systemImage: "globe")
                    .font(.headline)
                Spacer()
                Text("Applied to new spaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            
            HStack(spacing: 20) {
                if let assetID = globalStatus?.currentAssetID,
                   let thumbURL = aerialService.systemThumbnailURL(for: assetID) {
                    AsyncImage(url: thumbURL) { image in
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    }
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .shadow(radius: 5, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 160, height: 90)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(globalStatus?.currentAssetName ?? "System Default")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text("This setting applies to all displays and spaces unless overridden specifically.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 16) {
                        Button(action: onSelect) {
                            Text("Apply Settings")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Toggle("Show on all Spaces", isOn: Binding(
                            get: { aerialService.isGlobalMode },
                            set: { newValue in
                                aerialService.toggleGlobalMode(isOn: newValue)
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
    }
}

struct MonitorSection: View {
    let name: String
    let statuses: [AerialService.WallpaperSpaceStatus]
    let aerialService: AerialService
    let onSelect: (AerialService.WallpaperSpaceStatus) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "display")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text(name)
                    .font(.title3.bold())
                
                if let first = statuses.first, let did = first.displayID {
                    Text(did.suffix(8))
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Text("\(statuses.count) Desktops")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20)], spacing: 20) {
                ForEach(statuses) { status in
                    SpaceCard(status: status, aerialService: aerialService)
                        .onTapGesture {
                            onSelect(status)
                        }
                }
            }
        }
    }
}

struct SpaceCard: View {
    let status: AerialService.WallpaperSpaceStatus
    let aerialService: AerialService
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview
            ZStack {
                if let assetID = status.currentAssetID,
                   let thumbURL = aerialService.systemThumbnailURL(for: assetID) {
                    AsyncImage(url: thumbURL) { image in
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    }
                    .frame(height: 120)
                } else {
                    Color.gray.opacity(0.1)
                        .frame(height: 120)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.quaternary)
                        )
                }
                
                // Overlay for Space Action
                if isHovered {
                    Color.black.opacity(0.3)
                        .transition(.opacity)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "cursorarrow.click.2")
                            .font(.title2)
                        Text("Change Wallpaper")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            // Info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.name)
                        .font(.system(size: 13, weight: .bold))
                    Text(status.currentAssetName ?? "System Default")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if let sid = status.internalID, let did = status.displayID {
                    Button {
                        aerialService.switchToSpace(did: did, sid: sid)
                    } label: {
                        Image(systemName: "macwindow.badge.plus")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to this Desktop")
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .cornerRadius(16)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct WallpaperSelectionSheet: View {
    let targetStatus: AerialService.WallpaperSpaceStatus?
    let aerialService: AerialService
    @Environment(\.dismiss) var dismiss
    @State private var selectedAssetID: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Wallpaper")
                        .font(.headline)
                    if let target = targetStatus {
                        Text("Target: \(target.monitorName ?? "Display") - \(target.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Target: All Displays & Spaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Grid of assets
            ScrollView {
                if let manifest = aerialService.manifest {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(manifest.assets) { asset in
                            AssetPickItem(asset: asset, aerialService: aerialService, isSelected: selectedAssetID == asset.id)
                                .onTapGesture {
                                    selectedAssetID = asset.id
                                }
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView("No Assets Loaded", systemImage: "photo.on.rectangle")
                }
            }
            
            Divider()
            
            // Footer Actions
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .controlSize(.large)
                
                Button("Set Wallpaper") {
                    if let assetID = selectedAssetID {
                        applyWallpaper(assetID: assetID)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedAssetID == nil)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 800, height: 600)
    }
    
    private func applyWallpaper(assetID: String) {
        // Construct target
        var target: AerialService.WallpaperTarget? = nil
        
        if let ts = targetStatus {
            // Desk 1 often has an empty string for UUID.
            // We MUST use the Spaces hierarchy as it takes precedence over the roof Displays key.
            let spaceID = aerialService.getSpaceUUID(for: ts.internalID ?? 0) ?? ""
            let displayID = ts.displayID ?? ""
            
            target = AerialService.WallpaperTarget(
                id: ts.id,
                name: "\(ts.monitorName ?? "M") - \(ts.name)",
                path: ["Spaces", spaceID, "Displays", displayID]
            )
        }
        
        aerialService.setWallpaper(assetID: assetID, target: target)
        
        // Refresh after a delay to allow the agent to restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            aerialService.refreshSpaceStatus()
            dismiss()
        }
    }
}

struct AssetPickItem: View {
    let asset: AerialAsset
    let aerialService: AerialService
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let thumbURL = aerialService.systemThumbnailURL(for: asset.id) {
                    AsyncImage(url: thumbURL) { image in
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    }
                    .frame(width: 160, height: 90)
                } else {
                    Color.gray.opacity(0.1)
                        .frame(width: 160, height: 90)
                }
                
                if isSelected {
                    Color.blue.opacity(0.1)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            
            Text(aerialService.getAssetName(for: asset))
                .font(.caption2)
                .lineLimit(1)
        }
    }
}
