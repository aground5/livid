import Foundation

/// Internal DTO for persisting YouTube metadata.
struct YouTubeMetadataDTO: Codable, Sendable {
    let title: String
    let description: String
    let thumbnailURL: URL?
}
