import Foundation
import Observation

@Observable
class IngredientStore {
    static let shared = IngredientStore()
    
    private let ingredientsKey = "media_ingredients_v3"
    
    var ingredients: [MediaIngredient] = [] {
        didSet {
            saveIngredients()
            updateFileWatchers()
        }
    }
    
    init() {
        loadIngredients()
        initializeFileWatchdog()
    }
    
    @ObservationIgnored
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored
    private var previousExistenceStatus: [UUID: Bool] = [:]
    
    private func initializeFileWatchdog() {
        for ingredient in ingredients {
            let exists = !ingredient.isOffline && !ingredient.isRemoteYouTube
            previousExistenceStatus[ingredient.id] = exists
        }
        updateFileWatchers()
    }
    
    private func updateFileWatchers() {
        var directoriesToWatch = Set<String>()
        for ingredient in ingredients {
            if let url = ingredient.source.localURL {
                let parentPath = url.deletingLastPathComponent().path
                directoriesToWatch.insert(parentPath)
            }
        }
        
        // Remove old watchers
        for path in fileWatchers.keys {
            if !directoriesToWatch.contains(path) {
                fileWatchers[path]?.cancel()
                fileWatchers.removeValue(forKey: path)
            }
        }
        
        // Add new watchers
        for path in directoriesToWatch {
            if fileWatchers[path] == nil {
                let fd = open(path, O_EVTONLY)
                if fd != -1 {
                    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: DispatchQueue.main)
                    source.setEventHandler { [weak self] in
                        self?.verifyFiles()
                    }
                    source.setCancelHandler {
                        close(fd)
                    }
                    source.resume()
                    fileWatchers[path] = source
                }
            }
        }
    }
    
    private func verifyFiles() {
        var changed = false
        for (index, ingredient) in ingredients.enumerated() {
            let exists = !ingredient.isOffline && !ingredient.isRemoteYouTube
            if previousExistenceStatus[ingredient.id] != exists {
                changed = true
                previousExistenceStatus[ingredient.id] = exists
                // Mutate the array so SwiftUI detects the update
                ingredients[index] = ingredient
            }
        }
    }
    
    // MARK: - CRUD Operations
    
    func add(_ ingredient: MediaIngredient) {
        // Avoid duplicates if needed, though UUID should handle it
        if !ingredients.contains(where: { $0.id == ingredient.id }) {
            ingredients.append(ingredient)
        }
    }
    
    func remove(id: UUID) {
        ingredients.removeAll { $0.id == id }
    }
    
    func update(_ ingredient: MediaIngredient) {
        if let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
            ingredients[index] = ingredient
        }
    }
    
    // MARK: - Availability
    
    func checkAvailability(for ingredient: MediaIngredient) -> Bool {
        // If it's offline, it's not available for immediate editing/playback
        return !ingredient.isOffline
    }
    
    // MARK: - Persistence
    
    private func saveIngredients() {
        do {
            let data = try JSONEncoder().encode(ingredients)
            UserDefaults.standard.set(data, forKey: ingredientsKey)
        } catch {
            print("Failed to save ingredients: \(error)")
        }
    }
    
    private func loadIngredients() {
        guard let data = UserDefaults.standard.data(forKey: ingredientsKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([MediaIngredient].self, from: data)
            self.ingredients = decoded
        } catch {
            print("Failed to load ingredients: \(error)")
        }
    }
}
