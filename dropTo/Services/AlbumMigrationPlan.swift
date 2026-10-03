import Foundation
import SwiftData

enum AlbumMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AlbumSchemaV1.self, AlbumSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: AlbumSchemaV1.self,
        toVersion: AlbumSchemaV2.self,
        willMigrate: { context in
            let albums = try context.fetch(FetchDescriptor<AlbumSchemaV1.Album>())

            print("🔄 Migrating \(albums.count) albums from V1 to V2...")
        },
        didMigrate: { context in
            let albums = try context.fetch(FetchDescriptor<AlbumSchemaV2.Album>())
            print("✅ Migration complete! \(albums.count) albums migrated with isPinned property")
        }
    )
}
