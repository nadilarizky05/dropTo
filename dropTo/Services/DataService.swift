import Foundation
import SwiftData
import Combine

@MainActor
final class DataService: ObservableObject {
    
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    @Published private(set) var lastUpdate = Date()
    
    // APP GROUP IDENTIFIER (GANTI SESUAI YANG KAMU BUAT)
    static let appGroupIdentifier = "group.com.dila.dropTo"
    
    //============================================================================
    //PHASE 1: SETUP
    //============================================================================
    //INISIALISASI SWIFT DATA DENGAN SHARED CONTAINER
    
    init() {
        do {
            modelContainer = try Self.createSharedContainer()
            modelContext = ModelContext(modelContainer)
        } catch {
            // JIKA ERROR KARENA SCHEMA MISMATCH, HAPUS DATABASE LAMA DAN COBA LAGI
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
        
        // KIRIM ALBUM YANG DI-PIN KE WIDGET SAAT APP DIBUKA
        syncWidget()
    }
    
    //============================================================================
    // HELPER: CREATE SHARED CONTAINER
    //============================================================================
    // BUAT CONTAINER YANG BISA DI-AKSES OLEH MAIN APP DAN WIDGET
    
    static func createSharedContainer() throws -> ModelContainer {
        let schema = Schema([Album.self, DeletedItem.self])
        
        // COBA PAKAI APP GROUP CONTAINER DULU
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            let storeURL = containerURL.appendingPathComponent("default.store")
            let config = ModelConfiguration(url: storeURL)
            
            print("✅ Using shared container: \(storeURL.path)")
            return try ModelContainer(for: schema, configurations: [config])
        } else {
            // FALLBACK: PAKAI DEFAULT CONTAINER (APP GROUP GA SETUP)
            print("⚠️ App Group not found, using default container")
            return try ModelContainer(for: schema)
        }
    }
    
    //============================================================================
    // HELPER: RESET DATABASE
    //============================================================================
    // HAPUS FILE DATABASE SWIFTDATA UNTUK FRESH START
    
    private static func resetDatabase() {
        // RESET APP GROUP CONTAINER
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
        
        // RESET DEFAULT CONTAINER (LEGACY)
        let url = URL.applicationSupportDirectory.appending(path: "default.store")
        let shmURL = url.appendingPathExtension("shm")
        let walURL = url.appendingPathExtension("wal")
        
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: shmURL)
        try? FileManager.default.removeItem(at: walURL)
        
        print("🗑️ Database files removed")
    }
    
    //============================================================================
    //PHASE 2: READ
    //============================================================================
    //AMBIL SEMUA ALBUM DARI DB (URUTKAN: PINNED PERTAMA, LALU BERDASARKAN YG TERBARU)
    func fetchAlbums() -> [Album] {
        let descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let albums = (try? modelContext.fetch(descriptor)) ?? []
        
        // SORT: ALBUM YG DI-PIN MUNCUL PERTAMA, SISANYA URUTKAN BY CREATION DATE
        return albums.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned // PINNED ALBUM DULUAN
            }
            return lhs.createdAt > rhs.createdAt // NEWER FIRST
        }
    }
    
    //AMBIL SEMUA ITEM YG UDAH DIHAPUS
    func fetchDeletedItems() -> [DeletedItem] {
        let descriptor = FetchDescriptor<DeletedItem>(sortBy: [SortDescriptor(\.deletedAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    //============================================================================
    //PHASE 3: CREATE
    //============================================================================
    //BUAT ALBUM DGN NAMA TERTENTU
    
    func createAlbum(title: String) -> Album {
        let album = Album(title: title)
        modelContext.insert(album)
        save()
        return album
    }
    
    //============================================================================
    //PHASE 4: UPDATE
    //============================================================================
    //MENAMBAHKAN FOTO/VIDEO KE DALAM ALBUM
    
    func addAsset(_ identifier: String, to album: Album) {
        if !album.assetIdentifiers.contains(identifier) {
            album.assetIdentifiers.insert(identifier, at: 0)
            save()
        }
    }
    
    //MEMINDAHKAN FOTO/VIDEO KE ALBUM YG LAIN
    func moveAssets(_ identifiers: [String], from source: Album?, to destination: Album) {
        if let source {
            source.assetIdentifiers.removeAll { identifiers.contains($0) }
        }
        for identifier in identifiers where !destination.assetIdentifiers.contains(identifier) {
            destination.assetIdentifiers.insert(identifier, at: 0)
        }
        save()
    }
    
    //UBAH NAMA ALBUM
    func renameAlbum(_ album: Album, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        album.title = trimmed.isEmpty ? album.title : trimmed
        save()
    }
    
    //TOGGLE PIN ALBUM (PIN/UNPIN)
    // HANYA 1 ALBUM YANG BISA DI-PIN (UNTUK WIDGET)
    func togglePinAlbum(_ album: Album) {
        if album.isPinned {
            // UNPIN
            album.isPinned = false
        } else {
            // PIN: UNPIN SEMUA ALBUM LAIN DULU
            let allAlbums = fetchAlbums()
            for other in allAlbums where other.id != album.id {
                other.isPinned = false
            }
            album.isPinned = true
        }
        save() // save() OTOMATIS SYNC KE WIDGET (COVER + JUDUL + RELOAD)
    }
    
    //SIMPAN HASIL KAMERA KE PHOTOS LIBRARY + MASUKKAN KE ALBUM
    // DIPAKAI OLEH TOMBOL KAMERA DI ALBUM DAN KAMERA DARI WIDGET
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
    }
    
    //============================================================================
    //PHASE 5: DELETE
    //============================================================================
    //HAPUS ALBUM
    
    func deleteAlbum(_ album: Album) {
        for identifier in album.assetIdentifiers {
            softDelete(identifier, sourceAlbumID: album.id)
        }
        modelContext.delete(album)
        save()
    }
    
    //HAPUS FOTO/VIDEO KE TRASH SEMENTARA
    func softDelete(_ identifier: String, sourceAlbumID: UUID? = nil) {
        let albums = fetchAlbums()
        for album in albums {
            album.assetIdentifiers.removeAll { $0 == identifier }
        }
        
        let existing = fetchDeletedItems().first { $0.assetIdentifier == identifier }
        if existing == nil {
            let deletedItem = DeletedItem(assetIdentifier: identifier, sourceAlbumID: sourceAlbumID)
            modelContext.insert(deletedItem)
        }
        save()
    }
    
    //============================================================================
    //PHASE 6: RESTORE
    //============================================================================
    //UNDO PENGHAPUSAN FOTO/VIDEO
    
    func undoDelete(_ identifier: String, restoringTo album: Album?) {
        if let item = fetchDeletedItems().first(where: { $0.assetIdentifier == identifier }) {
            modelContext.delete(item)
        }
        if let album = album {
            addAsset(identifier, to: album)
        }
        save()
    }
    
    //RESTORE FOTO/VIDEO KEMBALI KE ALBUM ASALNYA
    func restoreFromDeleted(_ identifier: String) {
        guard let item = fetchDeletedItems().first(where: { $0.assetIdentifier == identifier }) else { return }
        
        if let sourceAlbumID = item.sourceAlbumID,
           let album = fetchAlbums().first(where: { $0.id == sourceAlbumID }) {
            addAsset(identifier, to: album)
        }
        
        modelContext.delete(item)
        save()
    }
    
    //HAPUS FOTO/VIDEO DARI TRASH PERMANEN
    func removeFromDeletedList(_ identifier: String) {
        if let item = fetchDeletedItems().first(where: { $0.assetIdentifier == identifier }) {
            modelContext.delete(item)
            save()
        }
    }
    
    //HAPUS OTOMATIS ITEM DI TRASH YG SUDAH LEWAT 30 HARI
    func purgeExpiredDeletedItems() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let items = fetchDeletedItems().filter { $0.deletedAt < thirtyDaysAgo }
        for item in items {
            modelContext.delete(item)
        }
        save()
    }
    
    //============================================================================
    //PHASE 7: HELPER
    //============================================================================
    //SIMPAN PERUBAHAN KE DB SWIFTDATA
    
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
        WidgetSyncService.sync(pinnedAlbum: pinned)
    }
}
