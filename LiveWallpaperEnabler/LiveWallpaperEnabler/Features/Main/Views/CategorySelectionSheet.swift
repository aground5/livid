import SwiftUI

struct CategorySelectionSheet: View {
    let item: LiveWallpaperItem
    @Environment(\.dismiss) var dismiss
    
    @State private var aerialService = AerialService.shared
    @State private var selectedCategoryID: String = ""
    @State private var newCategoryName: String = ""
    @State private var isCreatingNew = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Form {
                if aerialService.isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading Categories...")
                        Spacer()
                    }
                    .padding()
                } else {
                    Section {
                        Picker("Target Category", selection: $selectedCategoryID) {
                            Text("Choose...").tag("")
                            ForEach(aerialService.getCategories()) { category in
                                Text(aerialService.localize(category.localizedNameKey))
                                    .tag(category.id)
                            }
                        }
                        .disabled(isCreatingNew)
                    } header: {
                        Text("Select Existing")
                    }
                }
                
                Section {
                    Toggle("Create New Category", isOn: $isCreatingNew)
                    
                    if isCreatingNew {
                        TextField("Name", text: $newCategoryName)
                            .textFieldStyle(.roundedBorder)
                    }
                } header: {
                    Text("Custom Category")
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            actions
        }
        .frame(width: 400, height: 350)
        .onAppear {
            if selectedCategoryID.isEmpty, let first = aerialService.getCategories().first {
                selectedCategoryID = first.id
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to System Catalog")
                    .font(.headline)
                Text("Register '\(item.displayName)' to appear in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.square.on.square")
                .font(.title)
                .foregroundStyle(.blue)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var actions: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            Button("Register") {
                performRegistration()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreatingNew ? newCategoryName.isEmpty : selectedCategoryID.isEmpty)
        }
        .padding()
    }
    
    private func performRegistration() {
        let categoryID: String
        var subcategoryID: String? = nil
        
        if isCreatingNew {
            let newID = UUID().uuidString
            let newSubID = UUID().uuidString
            aerialService.createCategory(id: newID, name: newCategoryName, subcategoryID: newSubID)
            categoryID = newID
            subcategoryID = newSubID
        } else {
            categoryID = selectedCategoryID
            // Try to find the first subcategory of the existing category
            if let cat = aerialService.getCategories().first(where: { $0.id == categoryID }),
               let firstSub = cat.subcategories?.first {
                subcategoryID = firstSub.id
            }
        }
        
        let newAssetID = aerialService.registerAssetIntoSystemCatalog(
            item: item,
            categoryID: categoryID,
            subcategoryID: subcategoryID
        )
        
        if let assetID = newAssetID {
            WallpaperStore.shared.updateCatalogLink(id: item.id, catalogID: assetID)
        }
        dismiss()
    }
}
