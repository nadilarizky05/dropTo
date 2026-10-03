import Foundation
import SwiftData

@Model
final class DeletedItem {
    @Attribute(.unique) var assetIdentifier: String
    var deletedAt: Date
    var sourceAlbumID: UUID?

    init(assetIdentifier: String, deletedAt: Date = Date(), sourceAlbumID: UUID? = nil) {
        self.assetIdentifier = assetIdentifier
        self.deletedAt = deletedAt
        self.sourceAlbumID = sourceAlbumID
    }
}
