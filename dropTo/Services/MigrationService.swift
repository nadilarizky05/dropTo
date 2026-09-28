import Foundation
import SwiftData

@MainActor
final class MigrationService {
    
    //============================================================================
    // FUNCTION 1: MAIN MIGRATION ORCHESTRATOR
    //============================================================================
    // PINDAHIN DATA LAMA DARI USERDEFAULTS KE SWIFTDATA (JALAN SEKALI AJA)
    static func migrateFromUserDefaults(to dataService: DataService) {
        guard needsMigration() else { return }
        
        print("🔄 Starting migration...")
        
        migrateAlbums(to: dataService)
        migrateDeletedItems(to: dataService)
        
        markMigrationComplete()
        
        print("✅ Migration complete!")
    }
    
    //============================================================================
    // FUNCTION 2: CEK APAKAH PERLU MIGRASI
    //============================================================================
    // RETURN TRUE KALAU BELUM PERNAH MIGRASI (FLAG DI USERDEFAULTS BELUM ADA)
    private static func needsMigration() -> Bool {
        let key = "dropTo.migrated_to_swiftdata"
        return !UserDefaults.standard.bool(forKey: key)
    }
    
    //============================================================================
    // FUNCTION 3: TANDAI MIGRASI SUDAH SELESAI
    //============================================================================
    // SIMPAN FLAG DI USERDEFAULTS SUPAYA TIDAK MIGRASI LAGI DI NEXT LAUNCH
    private static func markMigrationComplete() {
        let key = "dropTo.migrated_to_swiftdata"
        UserDefaults.standard.set(true, forKey: key)
    }
    
    //============================================================================
    // FUNCTION 4: MIGRASI DATA ALBUM
    //============================================================================
    // BACA ALBUM DARI USERDEFAULTS → PINDAHKAN KE SWIFTDATA
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
    
    //============================================================================
    // FUNCTION 5: MIGRASI DATA TRASH/DELETED ITEMS
    //============================================================================
    // BACA DELETED ITEMS DARI USERDEFAULTS → PINDAHKAN KE SWIFTDATA
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
