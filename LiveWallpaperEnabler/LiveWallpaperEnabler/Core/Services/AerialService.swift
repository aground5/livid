import Foundation
import Observation

@Observable
class AerialService {
    static let shared = AerialService()
    
    var manifest: AerialManifest?
    var isLoading = false
    var error: Error?
    
    var currentAssetID: String?
    
    var localizedStrings: [String: String] = [:]
    
    private var aerialsBaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper")
    }
    
    private var manifestPath: URL {
        aerialsBaseURL.appendingPathComponent("aerials/manifest/entries.json")
    }
    
    private var stringsBundlePath: URL {
        aerialsBaseURL.appendingPathComponent("aerials/manifest/TVIdleScreenStrings.bundle")
    }
    
    private var indexPath: URL {
        aerialsBaseURL.appendingPathComponent("Store/Index.plist")
    }
    
    private var systemVideoDir: URL {
        aerialsBaseURL.appendingPathComponent("aerials/videos")
    }
    
    private var systemThumbDir: URL {
        aerialsBaseURL.appendingPathComponent("aerials/thumbnails")
    }
    
    func loadManifest() {
        fetchCurrentWallpaperID()
        loadLocalizedStrings()
        
        guard manifest == nil else { return }
        
        isLoading = true
        
        Task(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: manifestPath)
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(AerialManifest.self, from: data)
                
                await MainActor.run {
                    self.manifest = decoded
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadLocalizedStrings() {
        let fileManager = FileManager.default
        
        // 1. Get available languages in the bundle
        guard let items = try? fileManager.contentsOfDirectory(atPath: stringsBundlePath.path) else { return }
        let availableLprojs = items.filter { $0.hasSuffix(".lproj") }.map { $0.replacingOccurrences(of: ".lproj", with: "") }
        
        // 2. Find best match for system preferences
        let preferredLanguages = Locale.preferredLanguages // e.g., ["ko-KR", "en-US"]
        var targetLang: String = "en"
        
        for lang in preferredLanguages {
            let standardized = lang.replacingOccurrences(of: "-", with: "_")
            
            // Exact match (e.g., en_GB)
            if availableLprojs.contains(standardized) {
                targetLang = standardized
                break
            }
            
            // Language code match (e.g., ko for ko-KR)
            let langCode = String(standardized.split(separator: "_").first ?? "")
            if availableLprojs.contains(langCode) {
                targetLang = langCode
                break
            }
        }
        
        // 3. Load the file
        let stringsPath = stringsBundlePath.appendingPathComponent("\(targetLang).lproj/Localizable.nocache.strings")
        
        if let data = try? Data(contentsOf: stringsPath),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: String] {
            self.localizedStrings = dict
            print("Loaded \(dict.count) localized strings for language: \(targetLang)")
        }
    }
    
    /// Updates strings files for en and ko languages
    private func updateStrings(key: String, value: String) {
        let languages = ["en", "ko"]
        for lang in languages {
            let url = stringsBundlePath.appendingPathComponent("\(lang).lproj/Localizable.nocache.strings")
            
            var dict: [String: String] = [:]
            
            // 1. Load existing
            if let data = try? Data(contentsOf: url),
               let existing = (try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil)) as? [String: String] {
                dict = existing
            }
            
            // 2. Update
            dict[key] = value
            
            // 3. Save
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: url)
                print("Updated localization key '\(key)' in \(lang).lproj")
            } catch {
                print("Failed to save strings for \(lang): \(error)")
            }
        }
        
        // Refresh current cache
        loadLocalizedStrings()
    }
    
    func getCategories() -> [AerialCategory] {
        guard let categories = manifest?.categories else { return [] }
        return categories.sorted(by: { $0.preferredOrder < $1.preferredOrder })
    }
    
    func getAssets(for categoryID: String) -> [AerialAsset] {
        guard let assets = manifest?.assets else { return [] }
        return assets
            .filter({ $0.categories.contains(categoryID) })
            .sorted(by: { ($0.preferredOrder ?? 999) < ($1.preferredOrder ?? 999) })
    }
    
    func getAssetName(for asset: AerialAsset) -> String {
        // 1. Try shotID + "_NAME" (e.g., A001_C001_120530_NAME)
        if let shotID = asset.shotID {
            let nameKey = "\(shotID)_NAME"
            if let localized = localizedStrings[nameKey] {
                return localized
            }
        }
        
        // 2. Try localizedNameKey (though often not in the strings file)
        if let localized = localizedStrings[asset.localizedNameKey] {
            return localized
        }
        
        // 3. Fallback to accessibilityLabel or localizedNameKey itself
        return asset.accessibilityLabel ?? asset.localizedNameKey
    }
    
    func localize(_ key: String) -> String {
        return localizedStrings[key] ?? key
    }
    
    // MARK: - Wallpaper Management
    
    func fetchCurrentWallpaperID() {
        guard let data = try? Data(contentsOf: indexPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: Any],
              let allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any],
              let linked = allSpaces["Linked"] as? [String: Any],
              let content = linked["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let configData = firstChoice["Configuration"] as? Data else {
            return
        }
        
        // Decode nested Configuration plist
        if let config = try? PropertyListSerialization.propertyList(from: configData, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: Any],
           let assetID = config["assetID"] as? String {
            self.currentAssetID = assetID
        }
    }
    
    func setWallpaper(assetID: String) {
        guard let data = try? Data(contentsOf: indexPath),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(Int(PropertyListSerialization.MutabilityOptions.mutableContainers.rawValue)), format: nil) as? [String: Any] else {
            return
        }
        
        // 1. Prepare nested Configuration data
        let configDict: [String: Any] = ["assetID": assetID]
        guard let nestedConfigData = try? PropertyListSerialization.data(fromPropertyList: configDict, format: .binary, options: 0) else { return }
        
        // 2. Prepare default options data
        let optionsDict: [String: Any] = ["values": [:]]
        guard let nestedOptionsData = try? PropertyListSerialization.data(fromPropertyList: optionsDict, format: .binary, options: 0) else { return }
        
        // 3. Update Plist Structure
        func updateNode(_ key: String) {
            if var node = plist[key] as? [String: Any],
               var linked = node["Linked"] as? [String: Any],
               var content = linked["Content"] as? [String: Any],
               var choices = content["Choices"] as? [[String: Any]],
               !choices.isEmpty {
                
                choices[0]["Provider"] = "com.apple.wallpaper.choice.aerials"
                choices[0]["Configuration"] = nestedConfigData
                choices[0]["Files"] = []
                
                content["Choices"] = choices
                content["EncodedOptionValues"] = nestedOptionsData
                content["Shuffle"] = "$null"
                
                linked["Content"] = content
                node["Linked"] = linked
                plist[key] = node
            }
        }
        
        updateNode("AllSpacesAndDisplays")
        updateNode("SystemDefault")
        
        // 4. Save and Restart
        do {
            let updatedData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            
            // Stop agent first
            let stopTask = Process()
            stopTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            stopTask.arguments = ["stop", "com.apple.wallpaper.agent"]
            try? stopTask.run()
            stopTask.waitUntilExit()
            
            try updatedData.write(to: indexPath)
            
            // Kill processes
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killTask.arguments = ["-f", "WallpaperAgent|WallpaperAerialsExtension|NeptuneOneWallpaper"]
            try? killTask.run()
            killTask.waitUntilExit()
            
            // Start agent
            let startTask = Process()
            startTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            startTask.arguments = ["start", "com.apple.wallpaper.agent"]
            try? startTask.run()
            
            self.currentAssetID = assetID
            print("Successfully switched to wallpaper: \(assetID)")
        } catch {
            print("Failed to set wallpaper: \(error)")
        }
    }
    
    // MARK: - File Management
    
    func checkAvailability(for assetID: String) -> (hasVideo: Bool, hasThumbnail: Bool) {
        let fileManager = FileManager.default
        let videoURL = systemVideoDir.appendingPathComponent("\(assetID).mov")
        let thumbURL = systemThumbDir.appendingPathComponent("\(assetID).png")
        
        return (
            fileManager.fileExists(atPath: videoURL.path),
            fileManager.fileExists(atPath: thumbURL.path)
        )
    }
    
    func systemVideoURL(for assetID: String) -> URL {
        systemVideoDir.appendingPathComponent("\(assetID).mov")
    }
    
    func systemThumbnailURL(for assetID: String) -> URL {
        systemThumbDir.appendingPathComponent("\(assetID).png")
    }
    
    // MARK: - Direct Manifest Modification
    
    func backupManifest() {
        let backupURL = manifestPath.appendingPathExtension("bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            do {
                try FileManager.default.copyItem(at: manifestPath, to: backupURL)
                print("Created manifest backup at: \(backupURL.path)")
            } catch {
                print("Failed to create backup: \(error)")
            }
        }
    }
    
    func saveManifest() {
        guard let manifest = manifest else { return }
        backupManifest() // Ensure we have a backup before overwriting
        
        do {
            let encoder = JSONEncoder()
            // Try to match Apple's formatting as much as possible
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestPath)
            print("Successfully saved manifest to system path.")
        } catch {
            print("Failed to save manifest: \(error)")
        }
    }
    
    /// Registers a custom library item into the system's Aerial catalog.
    func registerAssetIntoSystemCatalog(
        item: LiveWallpaperItem,
        categoryID: String,
        subcategoryID: String? = nil,
        localizedName: String? = nil
    ) -> String? {
        guard manifest != nil else { return nil }
        
        // Generate a unique UUID for the system asset ID
        let assetID = UUID().uuidString
        let cleanAssetID = assetID.replacingOccurrences(of: "-", with: "")
        let displayName = localizedName ?? item.displayName
        
        // 1. Prepare the Asset ID/Path in system folder
        let targetVideoURL = systemVideoDir.appendingPathComponent("\(assetID).mov")
        let targetThumbURL = systemThumbDir.appendingPathComponent("\(assetID).png")
        
        // Ensure directories exist
        do {
            try FileManager.default.createDirectory(at: systemVideoDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: systemThumbDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create system directories: \(error)")
        }
        
        // PATCH AND SAVE instead of simple linking
        print("Registering and Patching: \(item.fileURL.lastPathComponent)")
        do {
            if FileManager.default.fileExists(atPath: targetVideoURL.path) {
                try FileManager.default.removeItem(at: targetVideoURL)
            }
            let patcher = try AtomPatcher(fileURL: item.fileURL)
            try WallpaperInjector.patch(patcher: patcher)
            try patcher.save(outputURL: targetVideoURL)
            print("Successfully patched and stored to \(targetVideoURL.path)")
        } catch {
            print("Failed to patch during registration: \(error). Falling back to symlink.")
            try? FileManager.default.linkItem(at: item.fileURL, to: targetVideoURL)
        }
        
        let thumbURL = item.thumbnailURL
        do {
            if FileManager.default.fileExists(atPath: targetThumbURL.path) {
                try FileManager.default.removeItem(at: targetThumbURL)
            }
            try FileManager.default.copyItem(at: thumbURL, to: targetThumbURL)
            print("Successfully copied thumbnail to \(targetThumbURL.path)")
        } catch {
            print("Failed to copy thumbnail from \(thumbURL.path) to \(targetThumbURL.path): \(error)")
        }
        
        // 2. Create AerialAsset model
        // Use LocalAssetServer URLs for on-the-fly patching
        let videoFileURL = "http://localhost:50505/video/\(assetID).mov"
        let thumbFileURL = "http://localhost:50505/thumbnail/\(assetID).png"
        
        let newAsset = AerialAsset(
            id: assetID,
            localizedNameKey: "AerialAsset_\(cleanAssetID)_NAME",
            accessibilityLabel: displayName,
            previewImage: thumbFileURL,
            previewImage900x580: thumbFileURL,
            url4KSDR240FPS: videoFileURL,
            preferredOrder: (manifest?.assets.filter({ $0.categories.contains(categoryID) }).count ?? 0) + 1,
            categories: [categoryID],
            subcategories: subcategoryID.map { [$0] },
            shotID: assetID,
            includeInShuffle: true,
            showInTopLevel: true,
            pointsOfInterest: [:]
        )
        
        // 3. Update manifest
        if let index = manifest?.assets.firstIndex(where: { $0.id == assetID }) {
            manifest?.assets[index] = newAsset
        } else {
            manifest?.assets.append(newAsset)
        }
        
        // 3.1 Update Representative Asset for Category/Subcategory if missing
        if let catIndex = manifest?.categories.firstIndex(where: { $0.id == categoryID }) {
            if manifest?.categories[catIndex].representativeAssetID == nil || manifest?.categories[catIndex].representativeAssetID == "" {
                manifest?.categories[catIndex].representativeAssetID = assetID
                manifest?.categories[catIndex].previewImage = thumbFileURL
            }
            
            if let subID = subcategoryID,
               var subcategories = manifest?.categories[catIndex].subcategories,
               let subIndex = subcategories.firstIndex(where: { $0.id == subID }) {
                
                if subcategories[subIndex].representativeAssetID == nil || subcategories[subIndex].representativeAssetID == "" {
                    subcategories[subIndex].representativeAssetID = assetID
                    subcategories[subIndex].previewImage = thumbFileURL
                    manifest?.categories[catIndex].subcategories = subcategories
                }
            }
        }
        
        // 4. Update Localization
        let nameKey = "AerialAsset_\(cleanAssetID)_NAME"
        updateStrings(key: nameKey, value: displayName)
        
        saveManifest()
        return assetID
    }
    
    func createCategory(id: String, name: String, subcategoryID: String) {
        guard manifest != nil else { return }
        
        let cleanCatID = id.replacingOccurrences(of: "-", with: "")
        let cleanSubID = subcategoryID.replacingOccurrences(of: "-", with: "")
        
        let catKey = "AerialCategory_\(cleanCatID)"
        let subKey = "AerialSubcategory_\(cleanSubID)"
        
        // 1. Create Subcategory
        let newSubcategory = AerialSubcategory(
            id: subcategoryID,
            localizedNameKey: subKey,
            localizedDescriptionKey: nil,
            representativeAssetID: nil,
            previewImage: nil,
            preferredOrder: 1
        )
        
        // 2. Create Category with the subcategory
        let newCategory = AerialCategory(
            id: id,
            localizedNameKey: catKey,
            localizedDescriptionKey: nil,
            representativeAssetID: nil,
            previewImage: nil,
            preferredOrder: (manifest?.categories.count ?? 0) + 1,
            subcategories: [newSubcategory]
        )
        
        if !manifest!.categories.contains(where: { $0.id == id }) {
            manifest?.categories.append(newCategory)
            
            // 3. Update Localization
            updateStrings(key: catKey, value: name)
            updateStrings(key: subKey, value: name)
            
            saveManifest()
        }
    }
    
    /// Removes a custom asset from the manifest and deletes associated files.
    func deleteCustomAsset(assetID: String) -> Bool {
        guard manifest != nil else { return false }
        
        // 1. Find and remove the asset from manifest
        guard let index = manifest?.assets.firstIndex(where: { $0.id == assetID }) else {
            print("Asset not found: \(assetID)")
            return false
        }
        
        let asset = manifest!.assets.remove(at: index)
        
        // 2. Delete the video file (symlink)
        let videoURL = systemVideoDir.appendingPathComponent("\(assetID).mov")
        try? FileManager.default.removeItem(at: videoURL)
        
        // 3. Delete the thumbnail file
        let thumbURL = systemThumbDir.appendingPathComponent("\(assetID).png")
        try? FileManager.default.removeItem(at: thumbURL)
        
        // 4. Remove from localization
        let cleanAssetID = assetID.replacingOccurrences(of: "-", with: "")
        let nameKey = "AerialAsset_\(cleanAssetID)_NAME"
        removeFromStrings(key: nameKey)
        
        // 5. Clean up category references
        let affectedCategoryIDs = asset.categories
        for catID in affectedCategoryIDs {
            if let catIndex = manifest!.categories.firstIndex(where: { $0.id == catID }) {
                let remaining = manifest!.assets.filter { $0.categories.contains(catID) }
                
                if remaining.isEmpty {
                    // Category is empty, safely delete if it's custom
                    if isCustomCategory(catID) {
                        _ = deleteCustomCategory(categoryID: catID)
                    }
                } else {
                    // Still has assets, check if we need to update the representative asset
                    if manifest!.categories[catIndex].representativeAssetID == assetID {
                        if let newRep = remaining.first {
                            manifest!.categories[catIndex].representativeAssetID = newRep.id
                            manifest!.categories[catIndex].previewImage = newRep.previewImage
                            
                            // Also update subcategory if needed
                            if let subID = newRep.subcategories?.first,
                               var subcategories = manifest!.categories[catIndex].subcategories,
                               let subIndex = subcategories.firstIndex(where: { $0.id == subID }) {
                                subcategories[subIndex].representativeAssetID = newRep.id
                                subcategories[subIndex].previewImage = newRep.previewImage
                                manifest!.categories[catIndex].subcategories = subcategories
                            }
                        }
                    }
                }
            }
        }
        
        // 6. Save manifest
        saveManifest()
        
        print("Successfully deleted custom asset: \(assetID)")
        return true
    }
    
    /// Removes a key from localization strings files
    private func removeFromStrings(key: String) {
        let languages = ["en", "ko"]
        for lang in languages {
            let url = stringsBundlePath.appendingPathComponent("\(lang).lproj/Localizable.nocache.strings")
            
            var dict: [String: String] = [:]
            
            if let data = try? Data(contentsOf: url),
               let existing = (try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil)) as? [String: String] {
                dict = existing
            }
            
            dict.removeValue(forKey: key)
            
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: url)
            } catch {
                print("Failed to update strings for \(lang): \(error)")
            }
        }
        
        loadLocalizedStrings()
    }
    
    /// Checks if an asset is a user-added custom asset
    func isCustomAsset(_ assetID: String) -> Bool {
        guard let asset = manifest?.assets.first(where: { $0.id == assetID }) else { return false }
        // Custom assets use local patch server URLs (modern)
        return asset.url4KSDR240FPS?.hasPrefix("http://localhost") ?? false
    }
    
    /// Checks if a category is user-created (contains only custom assets)
    func isCustomCategory(_ categoryID: String) -> Bool {
        guard let category = manifest?.categories.first(where: { $0.id == categoryID }) else { return false }
        // Custom categories use AerialCategory_ prefix in their localized name key
        return category.localizedNameKey.hasPrefix("AerialCategory_")
    }
    
    /// Deletes a custom category and all its assets
    func deleteCustomCategory(categoryID: String) -> Bool {
        guard manifest != nil else { return false }
        guard isCustomCategory(categoryID) else {
            print("Cannot delete non-custom category: \(categoryID)")
            return false
        }
        
        // 1. Find all assets in this category
        let assetsToDelete = manifest?.assets.filter { $0.categories.contains(categoryID) } ?? []
        
        // 2. Delete each asset
        for asset in assetsToDelete {
            _ = deleteCustomAsset(assetID: asset.id)
        }
        
        // 3. Find and remove the category
        guard let catIndex = manifest?.categories.firstIndex(where: { $0.id == categoryID }) else {
            return false
        }
        
        let category = manifest!.categories.remove(at: catIndex)
        
        // 4. Remove category localization
        removeFromStrings(key: category.localizedNameKey)
        
        // 5. Remove subcategory localizations
        if let subcategories = category.subcategories {
            for sub in subcategories {
                removeFromStrings(key: sub.localizedNameKey)
            }
        }
        
        // 6. Save manifest
        saveManifest()
        
        print("Successfully deleted custom category: \(categoryID)")
        return true
    }
}


extension String {
    func deletingPathExtension() -> String {
        return (self as NSString).deletingPathExtension
    }
}
