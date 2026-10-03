import Foundation
import SwiftData

@Model
final class Album {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var assetIdentifiers: [String]
    var isPinned: Bool

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), assetIdentifiers: [String] = [], isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.assetIdentifiers = assetIdentifiers
        self.isPinned = isPinned
    }
}
