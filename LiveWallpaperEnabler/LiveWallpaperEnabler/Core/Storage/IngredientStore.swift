import Foundation
import Observation

@Observable
class IngredientStore {
    static let shared = IngredientStore()
    
    private let ingredientsKey = "media_ingredients_v3"
    
    var ingredients: [MediaIngredient] = [] {
        didSet {
            saveIngredients()
        }
    }
    
    init() {
        loadIngredients()
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
