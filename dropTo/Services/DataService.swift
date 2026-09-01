import Foundation
import SwiftData
import Combine

@MainActor
final class DataService: ObservableObject {
    
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    @Published private(set) var lastUpdate = Date()
    
    //============================================================================
    //PHASE 1: SETUP
    //============================================================================
    //INISIALISASI SWIFT DATA
    
    init() {
        do {
            modelContainer = try ModelContainer(for: Album.self, DeletedItem.self)
            modelContext = ModelContext(modelContainer)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }
    
    //============================================================================
    //PHASE 2: READ
    //============================================================================
    //AMBIL SEMUA ALBUM DARI DB (URUTKAN BERDASARKAN YG TERBARU)
    func fetchAlbums() -> [Album] {
        let descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
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
    }
}
