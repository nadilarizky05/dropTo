import Foundation
import SwiftData
import Combine

@MainActor
final class DataService: ObservableObject {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    @Published private(set) var lastUpdate = Date()

    static let appGroupIdentifier = "group.com.dila.dropTo"

    init() {
        do {
            modelContainer = try Self.createSharedContainer()
            modelContext = ModelContext(modelContainer)
        } catch {
            print("⚠️ ModelContainer initialization failed, attempting to reset database...")
            Self.resetDatabase()

            do {
                modelContainer = try Self.createSharedContainer()
                modelContext = ModelContext(modelContainer)
                print("✅ Database reset successful")
            } catch {
                fatalError("Failed to initialize ModelContainer after reset: \(error)")
            }
        }

        syncWidget()
    }

    static func createSharedContainer() throws -> ModelContainer {
        let schema = Schema([Album.self, DeletedItem.self])

        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            let storeURL = containerURL.appendingPathComponent("default.store")
            let config = ModelConfiguration(url: storeURL)

            print("✅ Using shared container: \(storeURL.path)")
            return try ModelContainer(for: schema, configurations: [config])
        } else {
            print("⚠️ App Group not found, using default container")
            return try ModelContainer(for: schema)
        }
    }

    private static func resetDatabase() {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            let url = containerURL.appendingPathComponent("default.store")
            let shmURL = url.appendingPathExtension("shm")
            let walURL = url.appendingPathExtension("wal")

            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: shmURL)
            try? FileManager.default.removeItem(at: walURL)

            print("🗑️ Shared database files removed")
        }

        let url = URL.applicationSupportDirectory.appending(path: "default.store")
        let shmURL = url.appendingPathExtension("shm")
        let walURL = url.appendingPathExtension("wal")

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: shmURL)
        try? FileManager.default.removeItem(at: walURL)

        print("🗑️ Database files removed")
    }

    func fetchAlbums() -> [Album] {
        let descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let albums = (try? modelContext.fetch(descriptor)) ?? []

        return albums.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func fetchDeletedItems() -> [DeletedItem] {
        let descriptor = FetchDescriptor<DeletedItem>(sortBy: [SortDescriptor(\.deletedAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func createAlbum(title: String) -> Album {
        let album = Album(title: title)
        modelContext.insert(album)
        save()
        return album
    }

    func addAsset(_ identifier: String, to album: Album) {
        if !album.assetIdentifiers.contains(identifier) {
            album.assetIdentifiers.insert(identifier, at: 0)
            save()
        }
    }

    func addAssets(_ identifiers: [String], to album: Album) {
        let existing = Set(album.assetIdentifiers)
        let newOnes = identifiers.filter { !existing.contains($0) }
        guard !newOnes.isEmpty else { return }
        album.assetIdentifiers.insert(contentsOf: newOnes, at: 0)
        save()
    }

    func moveAssets(_ identifiers: [String], from source: Album?, to destination: Album) {
        if let source {
            source.assetIdentifiers.removeAll { identifiers.contains($0) }
        }
        for identifier in identifiers where !destination.assetIdentifiers.contains(identifier) {
            destination.assetIdentifiers.insert(identifier, at: 0)
        }
        save()
    }

    func renameAlbum(_ album: Album, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        album.title = trimmed.isEmpty ? album.title : trimmed
        save()
    }

    func togglePinAlbum(_ album: Album) {
        if album.isPinned {
            album.isPinned = false
        } else {
            let allAlbums = fetchAlbums()
            for other in allAlbums where other.id != album.id {
                other.isPinned = false
            }
            album.isPinned = true
        }
        save()
    }

    func saveCapturedMedia(_ media: CapturedMedia, toAlbumWithID albumID: UUID) async {
        let identifier: String?
        switch media {
        case .photo(let image):
            identifier = await PhotoLibraryService.shared.saveNewPhoto(image)
        case .video(let url):
            identifier = await PhotoLibraryService.shared.saveNewVideo(fileURL: url)
        }

        guard let identifier else { return }
        guard let album = fetchAlbums().first(where: { $0.id == albumID }) else {
            print("⚠️ Album \(albumID) nggak ketemu, foto tetap tersimpan di Photos")
            return
        }
        addAsset(identifier, to: album)
        PhotoLibraryService.shared.prefetchThumbnails(identifiers: [identifier], limit: 1)
    }

    func deleteAlbum(_ album: Album) {
        let identifiers = album.assetIdentifiers
        let albumID = album.id
        softDelete(identifiers, sourceAlbumID: albumID, saveChanges: false)
        modelContext.delete(album)
        save()
    }

    func softDelete(_ identifiers: [String], sourceAlbumID: UUID? = nil, saveChanges: Bool = true) {
        guard !identifiers.isEmpty else { return }
        let idSet = Set(identifiers)

        for album in fetchAlbums() {
            album.assetIdentifiers.removeAll { idSet.contains($0) }
        }

        var alreadyDeleted = Set(fetchDeletedItems().map(\.assetIdentifier))
        for identifier in identifiers where alreadyDeleted.insert(identifier).inserted {
            modelContext.insert(DeletedItem(assetIdentifier: identifier, sourceAlbumID: sourceAlbumID))
        }

        if saveChanges { save() }
    }

    func softDelete(_ identifier: String, sourceAlbumID: UUID? = nil) {
        softDelete([identifier], sourceAlbumID: sourceAlbumID)
    }

    func undoDelete(_ identifier: String, restoringTo album: Album?) {
        if let item = fetchDeletedItems().first(where: { $0.assetIdentifier == identifier }) {
            modelContext.delete(item)
        }
        if let album = album {
            addAsset(identifier, to: album)
        }
        save()
    }

    func restoreFromDeleted(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        let idSet = Set(identifiers)
        let items = fetchDeletedItems().filter { idSet.contains($0.assetIdentifier) }
        guard !items.isEmpty else { return }

        let albums = Dictionary(uniqueKeysWithValues: fetchAlbums().map { ($0.id, $0) })

        for item in items {
            if let sourceAlbumID = item.sourceAlbumID,
               let album = albums[sourceAlbumID],
               !album.assetIdentifiers.contains(item.assetIdentifier) {
                album.assetIdentifiers.insert(item.assetIdentifier, at: 0)
            }
            modelContext.delete(item)
        }
        save()
    }

    func restoreFromDeleted(_ identifier: String) {
        restoreFromDeleted([identifier])
    }

    func removeFromDeletedList(_ identifier: String) {
        if let item = fetchDeletedItems().first(where: { $0.assetIdentifier == identifier }) {
            modelContext.delete(item)
            save()
        }
    }

    private static let lastPurgeKey = "dropTo.lastPurgeAttempt"
    private static let retentionDays = 30

    func purgeExpiredDeletedItems() async {
        guard PhotoLibraryService.shared.isAuthorized else { return }

        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Self.lastPurgeKey) as? Date,
           Date().timeIntervalSince(last) < 86_400 { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? Date()
        let expired = fetchDeletedItems().filter { $0.deletedAt < cutoff }
        guard !expired.isEmpty else { return }

        defaults.set(Date(), forKey: Self.lastPurgeKey)

        let deleted = await PhotoLibraryService.shared.permanentlyDelete(identifiers: expired.map(\.assetIdentifier))
        guard deleted else { return }

        for item in expired {
            modelContext.delete(item)
        }
        save()
    }

    private func save() {
        do {
            try modelContext.save()
            lastUpdate = Date()
        } catch {
            print("Error saving context: \(error)")
        }
        syncWidget()
    }

    func syncWidget() {
        let pinned = fetchAlbums().first(where: { $0.isPinned })
        Task { await WidgetSyncService.sync(pinnedAlbum: pinned) }
    }
}
