import Foundation
import Observation
import Combine
import CoreGraphics

// Private CGS APIs (SkyLight)
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

@_silgen_name("CGSSpaceCopyName")
func CGSSpaceCopyName(_ cid: Int32, _ sid: Int32) -> CFString?


@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(_ cid: Int32, _ displayUUID: CFString, _ sid: Int32) -> Int32

struct CGSTransitionSpec {
    var unknown1: UInt32 = 0
    var type: Int32
    var option: Int32
    var wid: Int32 = 0
    var backColour: UnsafeMutablePointer<Float>? = nil
}

@_silgen_name("CGSNewTransition")
func CGSNewTransition(_ cid: Int32, _ spec: UnsafePointer<CGSTransitionSpec>, _ handle: UnsafeMutablePointer<Int>) -> Int

@_silgen_name("CGSInvokeTransition")
func CGSInvokeTransition(_ cid: Int32, _ handle: Int, _ duration: Float) -> Int

@_silgen_name("CGSReleaseTransition")
func CGSReleaseTransition(_ cid: Int32, _ handle: Int) -> Int

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

    private var loctablePath: URL {
        stringsBundlePath.appendingPathComponent("Contents/Resources/Localizable.nocache.loctable")
    }
    
    func loadManifest() {
        refreshSpaceStatus()
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
        // 1. Try to load from loctable first (macOS Sonoma and later)
        if let data = try? Data(contentsOf: loctablePath),
           let loctable = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: Any] {
            
            let preferredLanguages = Locale.preferredLanguages
            var targetLang: String = "en"
            let availableLangs = Array(loctable.keys)
            
            for lang in preferredLanguages {
                let standardized = lang.replacingOccurrences(of: "-", with: "_")
                if availableLangs.contains(standardized) {
                    targetLang = standardized
                    break
                }
                let langCode = String(standardized.split(separator: "_").first ?? "")
                if availableLangs.contains(langCode) {
                    targetLang = langCode
                    break
                }
            }
            
            if let dict = loctable[targetLang] as? [String: String] {
                self.localizedStrings = dict
                print("Loaded \(dict.count) localized strings from Loctable for language: \(targetLang)")
                return // Success!
            }
        }
        
        // 2. Fallback to old .strings way (Older macOS or if loctable fails)
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: stringsBundlePath.path) else { return }
        let availableLprojs = items.filter { $0.hasSuffix(".lproj") }.map { $0.replacingOccurrences(of: ".lproj", with: "") }
        
        let preferredLanguages = Locale.preferredLanguages
        var targetLang: String = "en"
        
        for lang in preferredLanguages {
            let standardized = lang.replacingOccurrences(of: "-", with: "_")
            if availableLprojs.contains(standardized) {
                targetLang = standardized
                break
            }
            let langCode = String(standardized.split(separator: "_").first ?? "")
            if availableLprojs.contains(langCode) {
                targetLang = langCode
                break
            }
        }
        
        let stringsPath = stringsBundlePath.appendingPathComponent("\(targetLang).lproj/Localizable.nocache.strings")
        if let data = try? Data(contentsOf: stringsPath),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: String] {
            self.localizedStrings = dict
            print("Loaded \(dict.count) localized strings from .strings for language: \(targetLang)")
        }
    }
    
    /// Updates strings files for en and ko languages
    private func updateStrings(key: String, value: String) {
        // 1. Update .strings files if they exist or lproj directories exist
        let languages = ["en", "ko"]
        for lang in languages {
            let folderUrl = stringsBundlePath.appendingPathComponent("\(lang).lproj")
            let fileUrl = folderUrl.appendingPathComponent("Localizable.nocache.strings")
            
            // Ensure folder exists for old way
            if !FileManager.default.fileExists(atPath: folderUrl.path) {
                try? FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true)
            }
            
            var dict: [String: String] = [:]
            if let data = try? Data(contentsOf: fileUrl),
               let existing = (try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil)) as? [String: String] {
                dict = existing
            }
            dict[key] = value
            if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
                try? data.write(to: fileUrl)
            }
        }
        
        // 2. Update .loctable if it exists (macOS Sonoma+)
        if let data = try? Data(contentsOf: loctablePath),
           var loctable = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(Int(PropertyListSerialization.MutabilityOptions.mutableContainers.rawValue)), format: nil) as? [String: Any] {
            
            // Update all available language sections in loctable to be safe
            for lang in loctable.keys where lang != "LocProvenance" {
                if var langDict = loctable[lang] as? [String: String] {
                    langDict[key] = value
                    loctable[lang] = langDict
                }
            }
            
            if let updatedData = try? PropertyListSerialization.data(fromPropertyList: loctable, format: .binary, options: 0) {
                try? updatedData.write(to: loctablePath)
            }
        }
        
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
    
    func getThumbnailURL(for assetID: String) -> URL? {
        // 1. Check local system path first (macOS Sonoma and later use assetID.png)
        let localURL = systemThumbDir.appendingPathComponent("\(assetID).png")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        // 2. Fallback to remote if asset is known
        if let asset = manifest?.assets.first(where: { $0.id == assetID }) {
            // Check original remote URL
            if let url = URL(string: asset.previewImage) {
                return url
            }
        }
        
        return nil
    }
    
    // MARK: - Wallpaper Management
    
    struct WallpaperTarget: Identifiable {
        let id: String
        let name: String
        let path: [String] // ["Spaces", "UUID", "Displays", "UUID"] or ["AllSpacesAndDisplays"]
    }
    
    struct WallpaperSpaceStatus: Identifiable {
        let id: String // UUID or DisplayID
        let spaceNumber: Int?
        let internalID: Int? // CGS ManagedSpaceID
        let name: String
        let currentAssetID: String?
        let currentAssetName: String?
        let displayID: String?
        let monitorName: String?
        let windowCount: Int?
    }
    
    var availableTargets: [WallpaperTarget] = []
    var spaceStatuses: [WallpaperSpaceStatus] = []
    private var spaceUUIDMap: [Int: String] = [:]
    
    var isGlobalMode: Bool = true
    
    func getSpaceUUID(for internalID: Int) -> String? {
        return spaceUUIDMap[internalID]
    }
    
    func refreshSpaceStatus() {
        let indexPath = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: indexPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: Any] else {
            return
        }
        
        DispatchQueue.main.async {
            self.isGlobalMode = (plist["AllSpacesAndDisplays"] as? [String: Any] != nil)
        }
        
        var statuses: [WallpaperSpaceStatus] = []
        let cid = CGSMainConnectionID()
        let displaySpaces = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] ?? []
        
        func getAssetInfo(from node: [String: Any]) -> (id: String?, name: String?) {
            var content: [String: Any]?
            if let desktop = node["Desktop"] as? [String: Any] {
                content = desktop["Content"] as? [String: Any]
            } else if let linked = node["Linked"] as? [String: Any] {
                content = linked["Content"] as? [String: Any]
            }
            
            guard let choices = content?["Choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let configData = firstChoice["Configuration"] as? Data,
                  let config = try? PropertyListSerialization.propertyList(from: configData, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: Any],
                  let assetID = config["assetID"] as? String else {
                return (nil, nil)
            }
            
            let name = self.localizedStrings[assetID] ?? self.localizedStrings["\(assetID)_NAME"] ?? assetID
            return (assetID, name)
        }
        
        // 1. Process display spaces from CGS (Real-time order)
        for display in displaySpaces {
            let did = display["Display Identifier"] as? String ?? "Unknown"
            let monitorName = "Monitor \(did.suffix(4))"
            
            if let spaces = display["Spaces"] as? [[String: Any]] {
                for (j, space) in spaces.enumerated() {
                    let sid = space["ManagedSpaceID"] as? Int ?? 0
                    let uuid = CGSSpaceCopyName(cid, Int32(sid)) as String? ?? ""
                    
                    if !uuid.isEmpty {
                        spaceUUIDMap[sid] = uuid
                    }
                        
                    
                    var info: (id: String?, name: String?) = (nil, nil)
                    
                    // Match with Index.plist - NO FALLBACKS
                    if self.isGlobalMode {
                        // Global Mode: Look ONLY at AllSpacesAndDisplays (if dictionary) or SystemDefault
                        if let allConfig = plist["AllSpacesAndDisplays"] as? [String: Any] {
                            info = getAssetInfo(from: allConfig)
                        } else if let systemDefault = plist["SystemDefault"] as? [String: Any] {
                            info = getAssetInfo(from: systemDefault)
                        }
                    } else {
                        // Individual Mode: Check display-specific settings first, then fall back to the space's Default.
                        if let plistSpaces = plist["Spaces"] as? [String: Any],
                           let sdata = plistSpaces[uuid] as? [String: Any] {
                            
                            let monitorNode = (sdata["Displays"] as? [String: Any])?[did] as? [String: Any] ?? sdata["Default"] as? [String: Any]
                            if let dnode = monitorNode {
                                info = getAssetInfo(from: dnode)
                            }
                        }
                    }
                    
                    let winCount: Int? = nil
                    
                    statuses.append(WallpaperSpaceStatus(
                        id: "\(sid)_\(did)",
                        spaceNumber: j + 1,
                        internalID: sid,
                        name: "Desktop \(j + 1)",
                        currentAssetID: info.id,
                        currentAssetName: info.name,
                        displayID: did,
                        monitorName: monitorName,
                        windowCount: winCount
                    ))
                }
            }
        }
        
        // 2. Add "All Spaces" default reference
        if let allNode = plist["AllSpacesAndDisplays"] as? [String: Any] {
            let info = getAssetInfo(from: allNode)
            statuses.append(WallpaperSpaceStatus(
                id: "All",
                spaceNumber: 0,
                internalID: nil,
                name: "All Spaces & Displays",
                currentAssetID: info.id,
                currentAssetName: info.name,
                displayID: nil,
                monitorName: "Global Settings",
                windowCount: nil
            ))
            self.currentAssetID = info.id
        }
        
        DispatchQueue.main.async {
            self.spaceStatuses = statuses
        }
    }
    
    func switchToSpace(did: String, sid: Int) {
        let cid = CGSMainConnectionID()
        var handle: Int = 0
        
        // 7 = CGSCube, 2 = CGSRight
        var spec = CGSTransitionSpec(type: 7, option: 2)
        
        // 1. Snapshot
        _ = CGSNewTransition(cid, &spec, &handle)
        
        // 2. Set (Verified Signature: cid, did, sid)
        _ = CGSManagedDisplaySetCurrentSpace(cid, did as CFString, Int32(sid))
        
        // 3. Invoke
        _ = CGSInvokeTransition(cid, handle, 0.75)
        
        // 4. Cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            _ = CGSReleaseTransition(cid, handle)
        }
    }
    
    func fetchCurrentWallpaperID() {
        refreshSpaceStatus()
    }
    
    func loadAvailableTargets() {
        guard let data = try? Data(contentsOf: indexPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: Any] else {
            return
        }
        
        var targets: [WallpaperTarget] = []
        
        // 1. All Spaces (Default)
        targets.append(WallpaperTarget(id: "All", name: "All Spaces & Displays", path: ["AllSpacesAndDisplays"]))
        
        // 2. Individual Spaces
        if let spaces = plist["Spaces"] as? [String: Any] {
            let sortedSpaceIDs = spaces.keys.sorted()
            for (index, spaceID) in sortedSpaceIDs.enumerated() {
                if let spaceData = spaces[spaceID] as? [String: Any] {
                    // Try to find display specific desktop under this space
                    if let displays = spaceData["Displays"] as? [String: Any] {
                        for displayID in displays.keys {
                            targets.append(WallpaperTarget(
                                id: "\(spaceID)_\(displayID)",
                                name: "Desktop \(index + 1) - Display \(displayID.suffix(4))",
                                path: ["Spaces", spaceID, "Displays", displayID]
                            ))
                        }
                    } else if spaceData["Default"] != nil {
                        targets.append(WallpaperTarget(
                            id: spaceID,
                            name: "Desktop \(index + 1) (Default)",
                            path: ["Spaces", spaceID, "Default"]
                        ))
                    }
                }
            }
        }
        
        self.availableTargets = targets
    }
    
    func setWallpaper(assetID: String, target: WallpaperTarget? = nil) {
        NSLog("🖼️ [Wallpaper] Target: \(target?.name ?? "All Displays & Spaces"), Asset: \(assetID)")
        
        guard let data = try? Data(contentsOf: indexPath),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(Int(PropertyListSerialization.MutabilityOptions.mutableContainers.rawValue)), format: nil) as? [String: Any] else {
            NSLog("❌ [Wallpaper] Failed to read Index.plist at \(indexPath.path)")
            return
        }
        
        // Prepare configuration
        let configDict: [String: Any] = ["assetID": assetID]
        guard let nestedConfigData = try? PropertyListSerialization.data(fromPropertyList: configDict, format: .binary, options: 0) else { 
            NSLog("❌ [Wallpaper] Failed to serialize config data")
            return 
        }
        
        let targetPath = target?.path ?? ["AllSpacesAndDisplays"]
        NSLog("🔍 [Wallpaper] Navigating path: \(targetPath)")
        
        // Path following update (Recursive)
        func updatePath(_ path: [String], in root: inout [String: Any]) {
            guard !path.isEmpty else { return }
            
            let key = path[0]
            
            // If the node doesn't exist, create it (Crucial for fresh spaces/displays)
            if root[key] == nil {
                root[key] = [String: Any]()
                NSLog("🛠️ [Wallpaper] Created missing node for path component: \(key)")
            }
            
            if path.count == 1 {
                // We are at the monitor/display level (e.g., Displays/ID or Spaces/UUID/Displays/ID)
                if var node = root[key] as? [String: Any] {
                    NSLog("📍 [Wallpaper] Found target node: \(key). Updating all relevant containers (Desktop/Idle/Linked).")
                    
                    // For specific monitor targets, ensure Type is "individual"
                    if key != "AllSpacesAndDisplays" && key != "SystemDefault" {
                        node["Type"] = "individual"
                    }
                    
                    // Aerials/Live Wallpapers often require BOTH 'Desktop' and 'Idle' to be in sync.
                    let containers = ["Desktop", "Idle", "Linked"]
                    var updatedAny = false
                    
                    for containerKey in containers {
                        if var containerNode = node[containerKey] as? [String: Any] {
                            inject(into: &containerNode)
                            containerNode["LastSet"] = Date()
                            node[containerKey] = containerNode
                            updatedAny = true
                            NSLog("📍 [Wallpaper] Updated \(containerKey) container.")
                        }
                    }
                    
                    if !updatedAny {
                        // Create Desktop & Idle if nothing was found
                        var configNode = [String: Any]()
                        inject(into: &configNode)
                        configNode["LastSet"] = Date()
                        
                        node["Desktop"] = configNode
                        node["Idle"] = configNode
                        NSLog("🛠️ [Wallpaper] Created new Desktop and Idle nodes for \(key)")
                    }
                    
                    root[key] = node
                }
            } else {
                var nextPath = path
                nextPath.removeFirst()
                if var nextNode = root[key] as? [String: Any] {
                    updatePath(nextPath, in: &nextNode)
                    root[key] = nextNode
                }
            }
        }
        
        func inject(into node: inout [String: Any]) {
            // Force Type to "individual" so this container's content is used
            node["Type"] = "individual"
            
            // macOS wallpaper structure: [Target] -> Desktop/Linked -> Content -> Choices
            // We MUST ensure 'Content' exists for the setting to be recognized.
            if node["Content"] == nil {
                node["Content"] = [String: Any]()
                NSLog("🛠️ [Wallpaper] Initializing missing 'Content' sub-node.")
            }
            
            if var content = node["Content"] as? [String: Any] {
                updateContentNode(&content)
                node["Content"] = content
                NSLog("✅ [Wallpaper] Successfully updated nested 'Content' structure.")
            }
        }
        
        func updateContentNode(_ content: inout [String: Any]) {
            var choices = content["Choices"] as? [[String: Any]] ?? [[String: Any]()]
            if choices.isEmpty { choices = [[String: Any]()] }
            
            choices[0]["Provider"] = "com.apple.wallpaper.choice.aerials"
            choices[0]["Configuration"] = nestedConfigData
            choices[0]["Files"] = []
            
            content["Choices"] = choices
            content["Shuffle"] = "$null"
            
            // Explicitly remove EncodedOptionValues if present so it doesn't conflict with Choices
            content.removeValue(forKey: "EncodedOptionValues")
        }
        
        // Update specific target
        updatePath(targetPath, in: &plist)
        
        if target == nil || target?.id == "All" {
            updatePath(["AllSpacesAndDisplays"], in: &plist)
            updatePath(["SystemDefault"], in: &plist)
        }
        
        do {
            let updatedData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try updatedData.write(to: indexPath)
            NSLog("💾 [Wallpaper] Successfully saved Index.plist.")
            
            // Force reload
            self.restartWallpaperAgent()
            
            DispatchQueue.main.async {
                self.currentAssetID = assetID
            }
        } catch {
            NSLog("❌ [Wallpaper] Write failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Toggle Global Mode (Native Tree Construction)
    
    func toggleGlobalMode(isOn: Bool) {
        let indexPath = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: indexPath),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(0), format: nil) as? [String: Any] else {
            return
        }
        
        let isCurrentlyGlobal = (plist["AllSpacesAndDisplays"] as? [String: Any] != nil)
        
        guard isOn != isCurrentlyGlobal else {
            NSLog("🔄 [Wallpaper] Global mode is already \(isOn). No action needed.")
            return
        }
        
        var baseConfig: [String: Any]? = nil
        
        if isCurrentlyGlobal {
            if let config = plist["AllSpacesAndDisplays"] as? [String: Any] {
                baseConfig = config
            } else if let config = plist["SystemDefault"] as? [String: Any] {
                baseConfig = config
            }
        } else {
            if let spaces = plist["Spaces"] as? [String: Any] {
                for (_, spaceData) in spaces {
                    if let spaceDict = spaceData as? [String: Any],
                       let displays = spaceDict["Displays"] as? [String: Any],
                       let firstDisplayVal = displays.values.first as? [String: Any] {
                        baseConfig = firstDisplayVal
                        break
                    }
                }
            }
            if baseConfig == nil {
                if let displays = plist["Displays"] as? [String: Any],
                   let firstDisplayVal = displays.values.first as? [String: Any] {
                    baseConfig = firstDisplayVal
                }
            }
            if baseConfig == nil {
                if let config = plist["AllSpacesAndDisplays"] as? [String: Any] {
                    baseConfig = config
                } else if let config = plist["SystemDefault"] as? [String: Any] {
                    baseConfig = config
                }
            }
        }
        
        if isOn {
            NSLog("🧹 [Wallpaper] Enabling Global Mode.")
            // Explicitly set as dictionary to override all spaces
            if var systemConfig = baseConfig {
                systemConfig["Type"] = "linked"
                plist["AllSpacesAndDisplays"] = systemConfig
            } else {
                plist["AllSpacesAndDisplays"] = [String: Any]()
            }
            
            plist.removeValue(forKey: "Spaces")
            plist.removeValue(forKey: "Displays")
        } else {
            NSLog("🔄 [Wallpaper] Disabling Global Mode. Constructing Spaces tree from current global config.")
            let globalConfig = baseConfig ?? [String: Any]()
            var newSpaces = [String: Any]()
            var rootDisplays = [String: Any]()
            
            let cid = CGSMainConnectionID()
            if let displaySpaces = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] {
                for display in displaySpaces {
                    let did = display["Display Identifier"] as? String ?? ""
                    
                    // Root display entry (similar to Apple's native behavior)
                    var rootDisplayConfig = globalConfig
                    if rootDisplayConfig["Type"] == nil { rootDisplayConfig["Type"] = "linked" }
                    if !did.isEmpty {
                        rootDisplays[did] = rootDisplayConfig
                    }
                    
                    if let spaces = display["Spaces"] as? [[String: Any]] {
                        for space in spaces {
                            let sid = space["ManagedSpaceID"] as? Int ?? 0
                            let uuid = CGSSpaceCopyName(cid, Int32(sid)) as String? ?? ""
                            // DO NOT skip empty UUIDs, as "" is how macOS stores Desktop 1.
                            
                            var spaceDict = newSpaces[uuid] as? [String: Any] ?? [String: Any]()
                            var displaysDict = spaceDict["Displays"] as? [String: Any] ?? [String: Any]()
                            
                            var monitorConfig = globalConfig
                            if monitorConfig["Type"] == nil { monitorConfig["Type"] = "linked" }
                            displaysDict[did] = monitorConfig
                            
                            var defaultSpaceConfig = globalConfig
                            if defaultSpaceConfig["Type"] == nil { defaultSpaceConfig["Type"] = "linked" }
                            
                            spaceDict["Displays"] = displaysDict
                            spaceDict["Default"] = defaultSpaceConfig
                            newSpaces[uuid] = spaceDict
                        }
                    }
                }
            }
            plist["Spaces"] = newSpaces
            plist["Displays"] = rootDisplays
            plist["AllSpacesAndDisplays"] = "$null"
        }
        
        do {
            let updatedData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try updatedData.write(to: indexPath)
            NSLog("💾 [Wallpaper] Successfully saved Index.plist for mode switch.")
            
            DispatchQueue.main.async {
                self.isGlobalMode = isOn
            }
            
            self.restartWallpaperAgent()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.refreshSpaceStatus()
            }
            
        } catch {
            NSLog("❌ [Wallpaper] Write failed: \(error.localizedDescription)")
        }
    }
    
    /// Restarts the macOS wallpaper agent and associated processes to force a refresh of both Index.plist and entries.json.
    func restartWallpaperAgent() {
        print("Restarting Wallpaper Agent to apply changes...")
        
        // 1. Stop agent first
        let stopTask = Process()
        stopTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        stopTask.arguments = ["stop", "com.apple.wallpaper.agent"]
        try? stopTask.run()
        stopTask.waitUntilExit()
        
        // 2. Kill associated processes
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "WallpaperAgent|WallpaperAerialsExtension|NeptuneOneWallpaper"]
        try? killTask.run()
        killTask.waitUntilExit()
        
        // 3. Start agent back up
        let startTask = Process()
        startTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        startTask.arguments = ["start", "com.apple.wallpaper.agent"]
        try? startTask.run()
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
    
    func systemThumbnailURL(for assetID: String) -> URL? {
        // 1. Local path (macOS Sonoma default)
        let localURL = systemThumbDir.appendingPathComponent("\(assetID).png")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        // 2. Fallback to manifest remote URL if local is missing
        if let asset = manifest?.assets.first(where: { $0.id == assetID }),
           let url = URL(string: asset.previewImage) {
            return url
        }
        
        return nil
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
            
            // Force macOS to reload the Updated entries.json
            self.restartWallpaperAgent()
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
        // 1. Update .strings files
        let languages = ["en", "ko"]
        for lang in languages {
            let url = stringsBundlePath.appendingPathComponent("\(lang).lproj/Localizable.nocache.strings")
            if var dict = try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: PropertyListSerialization.ReadOptions(Int(PropertyListSerialization.MutabilityOptions.mutableContainers.rawValue)), format: nil) as? [String: String] {
                dict.removeValue(forKey: key)
                if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
                    try? data.write(to: url)
                }
            }
        }
        
        // 2. Update .loctable
        if let data = try? Data(contentsOf: loctablePath),
           var loctable = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(Int(PropertyListSerialization.MutabilityOptions.mutableContainers.rawValue)), format: nil) as? [String: Any] {
            
            for lang in loctable.keys where lang != "LocProvenance" {
                if var langDict = loctable[lang] as? [String: String] {
                    langDict.removeValue(forKey: key)
                    loctable[lang] = langDict
                }
            }
            
            if let updatedData = try? PropertyListSerialization.data(fromPropertyList: loctable, format: .binary, options: 0) {
                try? updatedData.write(to: loctablePath)
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
