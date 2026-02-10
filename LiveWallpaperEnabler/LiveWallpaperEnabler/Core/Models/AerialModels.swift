import Foundation

struct AerialManifest: Codable {
    var version: Int
    var localizationVersion: String
    var initialAssetCount: Int
    var categories: [AerialCategory]
    var assets: [AerialAsset]
}

struct AerialCategory: Codable, Identifiable {
    var id: String
    var localizedNameKey: String
    var localizedDescriptionKey: String?
    var representativeAssetID: String?
    var previewImage: String?
    var preferredOrder: Int
    var subcategories: [AerialSubcategory]?
}

struct AerialSubcategory: Codable, Identifiable {
    var id: String
    var localizedNameKey: String
    var localizedDescriptionKey: String?
    var representativeAssetID: String?
    var previewImage: String?
    var preferredOrder: Int
}

struct AerialAsset: Codable, Identifiable {
    var id: String
    var localizedNameKey: String
    var accessibilityLabel: String?
    var previewImage: String
    var previewImage900x580: String?
    var url4KSDR240FPS: String?
    var preferredOrder: Int?
    var categories: [String]
    var subcategories: [String]?
    var shotID: String?
    var includeInShuffle: Bool?
    var showInTopLevel: Bool?
    var pointsOfInterest: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case localizedNameKey
        case accessibilityLabel
        case previewImage
        case previewImage900x580 = "previewImage-900x580"
        case url4KSDR240FPS = "url-4K-SDR-240FPS"
        case preferredOrder
        case categories
        case subcategories
        case shotID
        case includeInShuffle
        case showInTopLevel
        case pointsOfInterest
    }
}
