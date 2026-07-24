//
//  AlbumStore.swift
//  dropTo
//
//  This is the "brain" of the app. Every screen reads from and writes
//  to this one object, so the data always stays in sync everywhere.
//
//  Beginner note: `@Published` means "whenever this value changes,
//  automatically refresh every screen that's showing it". We save
//  everything to UserDefaults (a tiny built-in database perfect for
//  small amounts of data like this) so albums survive app restarts.
//

import Foundation
import Combine
import SwiftUI

/// One entry inside "Recently Deleted" — remembers WHICH photo, WHEN it
/// was deleted, and WHICH album it came from (so Recover can put it back
/// exactly where it belongs, instead of it only reappearing in All Photos).
struct DeletedItem: Codable, Identifiable, Equatable {
    var id: String { assetIdentifier }
    let assetIdentifier: String
    let deletedAt: Date
    let sourceAlbumID: UUID?
}

@MainActor
final class AlbumStore: ObservableObject {

    @Published private(set) var albums: [AlbumModel] = []
    @Published private(set) var deletedItems: [DeletedItem] = []

    private let albumsKey = "dropTo.albums"
    private let deletedKey = "dropTo.deletedItems"

    init() {
        load()
        purgeExpiredDeletedItems()
    }

    // MARK: - Albums

    func createAlbum(title: String, tag: String?) {
        let album = AlbumModel(title: title, tag: tag?.isEmpty == true ? nil : tag)
        albums.insert(album, at: 0)
        save()
    }

    /// Deletes the album itself. Everything that was inside it doesn't
    /// just vanish — it moves into "Recently Deleted", exactly like
    /// swiping an individual photo away.
    func deleteAlbum(_ album: AlbumModel) {
        for identifier in album.assetIdentifiers {
            softDelete(identifier)
        }
        albums.removeAll { $0.id == album.id }
        save()
    }

    /// Adds a freshly-saved photo (identified by its localIdentifier)
    /// into a specific album — used right after the camera captures a shot.
    func addAsset(_ identifier: String, to album: AlbumModel) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        if !albums[index].assetIdentifiers.contains(identifier) {
            albums[index].assetIdentifiers.insert(identifier, at: 0)
            save()
        }
    }

    /// Moves a batch of photos into an album. `source` is optional: pass
    /// an album when moving OUT of another album (Select mode inside an
    /// album), or `nil` when organizing photos that weren't in any album
    /// yet (Select mode inside "Unorganized Items").
    func moveAssets(_ identifiers: [String], from source: AlbumModel?, to destination: AlbumModel) {
        if let source, let sourceIndex = albums.firstIndex(where: { $0.id == source.id }) {
            albums[sourceIndex].assetIdentifiers.removeAll { identifiers.contains($0) }
        }
        guard let destinationIndex = albums.firstIndex(where: { $0.id == destination.id }) else { return }
        for identifier in identifiers where !albums[destinationIndex].assetIdentifiers.contains(identifier) {
            albums[destinationIndex].assetIdentifiers.insert(identifier, at: 0)
        }
        save()
    }

    // MARK: - Soft delete / keep / undo

    /// "Deleting" a photo never destroys it right away. It just moves
    /// the photo's ID into the "Recently Deleted" list (like the Photos
    /// app does), and removes it from whichever album it was in.
    /// `sourceAlbum` is remembered so Recover knows exactly where to put
    /// it back.
    func softDelete(_ identifier: String, sourceAlbum: AlbumModel? = nil) {
        for i in albums.indices {
            albums[i].assetIdentifiers.removeAll { $0 == identifier }
        }
        if !deletedItems.contains(where: { $0.assetIdentifier == identifier }) {
            deletedItems.insert(
                DeletedItem(assetIdentifier: identifier, deletedAt: Date(), sourceAlbumID: sourceAlbum?.id),
                at: 0
            )
        }
        save()
    }

    /// Undo: put the photo back into the album it came from. Used right
    /// after a swipe, while we still have the album in hand.
    func undoDelete(_ identifier: String, restoringTo album: AlbumModel) {
        deletedItems.removeAll { $0.assetIdentifier == identifier }
        addAsset(identifier, to: album)
        save()
    }

    /// Restore from the "Recently Deleted" screen. Looks up which album
    /// this photo originally belonged to (saved at delete-time) and puts
    /// it back there. If it didn't come from a specific album (e.g. it
    /// was deleted straight from "All Photos"), it simply leaves the
    /// deleted bucket and naturally reappears in "All Photos" again.
    func restoreFromDeleted(_ identifier: String) {
        if let sourceAlbumID = deletedItems.first(where: { $0.assetIdentifier == identifier })?.sourceAlbumID,
           let album = albums.first(where: { $0.id == sourceAlbumID }) {
            addAsset(identifier, to: album)
        }
        deletedItems.removeAll { $0.assetIdentifier == identifier }
        save()
    }

    func removeFromDeletedList(_ identifier: String) {
        deletedItems.removeAll { $0.assetIdentifier == identifier }
        save()
    }

    /// Photos older than 30 days in "Recently Deleted" quietly disappear
    /// from OUR list (mirrors how the real Photos app behaves).
    /// Note: this does not touch the system library — only permanent
    /// delete (triggered explicitly by the user) does that.
    private func purgeExpiredDeletedItems() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        deletedItems.removeAll { $0.deletedAt < thirtyDaysAgo }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(albums) {
            UserDefaults.standard.set(data, forKey: albumsKey)
        }
        if let data = try? JSONEncoder().encode(deletedItems) {
            UserDefaults.standard.set(data, forKey: deletedKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: albumsKey),
           let saved = try? JSONDecoder().decode([AlbumModel].self, from: data) {
            albums = saved
        }
        if let data = UserDefaults.standard.data(forKey: deletedKey),
           let saved = try? JSONDecoder().decode([DeletedItem].self, from: data) {
            deletedItems = saved
        }
    }
    /// Ganti judul album.
    func renameAlbum(_ album: AlbumModel, to newTitle: String) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        albums[index].title = trimmed.isEmpty ? albums[index].title : trimmed
        save()
    }

    /// Urutan ulang album — dipakai drag-and-drop di grid Home.
    func moveAlbum(fromOffsets source: IndexSet, toOffset destination: Int) {
        albums.move(fromOffsets: source, toOffset: destination)
        save()
    }
}
