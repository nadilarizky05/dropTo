import Foundation
import SwiftData

//============================================================================
// SCHEMA V2: ALBUM DENGAN isPinned
//============================================================================
// SCHEMA BARU DENGAN FITUR PIN ALBUM

enum AlbumSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Album.self, DeletedItem.self]
    }
    
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
}
