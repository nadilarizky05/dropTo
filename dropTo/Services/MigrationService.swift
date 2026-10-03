import Foundation
import SwiftData

@MainActor
final class MigrationService {
    static func migrateFromUserDefaults(to dataService: DataService) {
        guard needsMigration() else { return }

        print("🔄 Starting migration...")

        migrateAlbums(to: dataService)
        migrateDeletedItems(to: dataService)

        markMigrationComplete()

        print("✅ Migration complete!")
    }

    private static func needsMigration() -> Bool {
        let key = "dropTo.migrated_to_swiftdata"
        return !UserDefaults.standard.bool(forKey: key)
    }

    private static func markMigrationComplete() {
        let key = "dropTo.migrated_to_swiftdata"
        UserDefaults.standard.set(true, forKey: key)
    }

    private static func migrateAlbums(to dataService: DataService) {
        struct OldAlbum: Codable {
            var id: UUID
            var title: String
            var tag: String?
            var createdAt: Date
            var assetIdentifiers: [String]
        }

        let key = "dropTo.albums"
        guard let data = UserDefaults.standard.data(forKey: key),
              let oldAlbums = try? JSONDecoder().decode([OldAlbum].self, from: data) else {
            return
        }

        for oldAlbum in oldAlbums {
            let album = Album(
                id: oldAlbum.id,
                title: oldAlbum.title,
                createdAt: oldAlbum.createdAt,
                assetIdentifiers: oldAlbum.assetIdentifiers,
                isPinned: false
            )
            dataService.modelContext.insert(album)
        }

        try? dataService.modelContext.save()

        print("✅ Migrated \(oldAlbums.count) albums")
    }

    private static func migrateDeletedItems(to dataService: DataService) {
        struct OldDeletedItem: Codable {
            let assetIdentifier: String
            let deletedAt: Date
            let sourceAlbumID: UUID?
        }

        let key = "dropTo.deletedItems"
        guard let data = UserDefaults.standard.data(forKey: key),
              let oldItems = try? JSONDecoder().decode([OldDeletedItem].self, from: data) else {
            return
        }

        for oldItem in oldItems {
            let item = DeletedItem(
                assetIdentifier: oldItem.assetIdentifier,
                deletedAt: oldItem.deletedAt,
                sourceAlbumID: oldItem.sourceAlbumID
            )
            dataService.modelContext.insert(item)
        }

        try? dataService.modelContext.save()

        print("✅ Migrated \(oldItems.count) deleted items")
    }
}
