import Foundation
import SwiftData

//============================================================================
// MIGRATION PLAN: V1 → V2
//============================================================================
// DEFINISI CARA MIGRASI DATA DARI SCHEMA LAMA KE BARU

enum AlbumMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AlbumSchemaV1.self, AlbumSchemaV2.self]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    //============================================================================
    // STAGE: MIGRASI V1 → V2
    //============================================================================
    // TAMBAHKAN isPinned = false KE SEMUA ALBUM YANG SUDAH ADA
    
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: AlbumSchemaV1.self,
        toVersion: AlbumSchemaV2.self,
        willMigrate: { context in
            // AMBIL SEMUA ALBUM DARI V1
            let albums = try context.fetch(FetchDescriptor<AlbumSchemaV1.Album>())
            
            // LOG INFO
            print("🔄 Migrating \(albums.count) albums from V1 to V2...")
            
            // TIDAK PERLU LAKUKAN APA-APA DI SINI
            // SWIFTDATA OTOMATIS AKAN HANDLE PENAMBAHAN PROPERTY DENGAN DEFAULT VALUE
        },
        didMigrate: { context in
            // SETELAH MIGRASI, VERIFY SEMUA ALBUM PUNYA isPinned
            let albums = try context.fetch(FetchDescriptor<AlbumSchemaV2.Album>())
            print("✅ Migration complete! \(albums.count) albums migrated with isPinned property")
        }
    )
}
