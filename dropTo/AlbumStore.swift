//
//  AlbumStore.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//


import Foundation
import Combine
import SwiftUI

class AlbumStore: ObservableObject {
    @Published var albums: [AlbumProp] = []
    @Published var undoStack: [(albumIndex: Int, assetIdentifier: String)] = []

    private let saveKey = "saved_albums"

    init() {
        load()
        if albums.isEmpty {
            albums = [
                AlbumProp(albumName: "Asian Food", timeCreated: .now, projectType: "Food Vloger", numberOfPhotos: 0),
                AlbumProp(albumName: "Western Food", timeCreated: .now, projectType: "Travelling Content", numberOfPhotos: 0),
                AlbumProp(albumName: "Like Jennie MV", timeCreated: .now, projectType: "Music", numberOfPhotos: 0),
                AlbumProp(albumName: "Travel Moments", timeCreated: .now, projectType: "Personal", numberOfPhotos: 0)
            ]
            save()
        }
    }

    func assignPhoto(assetIdentifier: String, to albumIndex: Int) {
        guard albumIndex < albums.count else { return }
        guard !albums[albumIndex].assetIdentifiers.contains(assetIdentifier) else { return }
        undoStack.append((albumIndex: albumIndex, assetIdentifier: assetIdentifier))
        albums[albumIndex].assetIdentifiers.append(assetIdentifier)
        albums[albumIndex].coverAssetIdentifier = assetIdentifier
        albums[albumIndex].numberOfPhotos += 1
        save()
    }

    func undo() {
        guard let last = undoStack.last else { return }
        undoStack.removeLast()
        let idx = last.albumIndex
        albums[idx].assetIdentifiers.removeAll { $0 == last.assetIdentifier }
        albums[idx].numberOfPhotos = max(0, albums[idx].numberOfPhotos - 1)
        albums[idx].coverAssetIdentifier = albums[idx].assetIdentifiers.isEmpty
            ? nil
            : albums[idx].assetIdentifiers.last
        save()
    }

    func addAlbum(name: String, projectType: String = "") {
        let newAlbum = AlbumProp(albumName: name, timeCreated: .now, projectType: projectType, numberOfPhotos: 0)
        albums.insert(newAlbum, at: 0)
        save()
    }

    func deleteAlbum(id: UUID) {
        albums.removeAll { $0.id == id }
        save()
    }

    func moveAlbum(from source: IndexSet, to destination: Int) {
        albums.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func removePhoto(assetIdentifier: String, from albumID: UUID) {
        guard let idx = albums.firstIndex(where: { $0.id == albumID }) else { return }
        albums[idx].assetIdentifiers.removeAll { $0 == assetIdentifier }
        albums[idx].favoriteIdentifiers.removeAll { $0 == assetIdentifier }
        albums[idx].numberOfPhotos = max(0, albums[idx].numberOfPhotos - 1)
        if albums[idx].coverAssetIdentifier == assetIdentifier {
            albums[idx].coverAssetIdentifier = albums[idx].assetIdentifiers.last
        }
        save()
    }

    /// Pindah foto dari satu album ke album lain (tanpa hapus dari Photos library)
    func movePhotos(identifiers: Set<String>, from sourceAlbumID: UUID, to targetAlbumIndex: Int) {
        guard targetAlbumIndex < albums.count else { return }
        guard let sourceIdx = albums.firstIndex(where: { $0.id == sourceAlbumID }) else { return }

        for identifier in identifiers {
            // Hapus dari source
            albums[sourceIdx].assetIdentifiers.removeAll { $0 == identifier }
            albums[sourceIdx].favoriteIdentifiers.removeAll { $0 == identifier }
            albums[sourceIdx].numberOfPhotos = max(0, albums[sourceIdx].numberOfPhotos - 1)
            if albums[sourceIdx].coverAssetIdentifier == identifier {
                albums[sourceIdx].coverAssetIdentifier = albums[sourceIdx].assetIdentifiers.last
            }
            // Tambah ke target (kalau belum ada)
            if !albums[targetAlbumIndex].assetIdentifiers.contains(identifier) {
                albums[targetAlbumIndex].assetIdentifiers.append(identifier)
                albums[targetAlbumIndex].numberOfPhotos += 1
                albums[targetAlbumIndex].coverAssetIdentifier = identifier
            }
        }
        save()
    }

    // MARK: - Favorite

    func toggleFavorite(assetIdentifier: String, in albumID: UUID) {
        guard let idx = albums.firstIndex(where: { $0.id == albumID }) else { return }
        if albums[idx].favoriteIdentifiers.contains(assetIdentifier) {
            albums[idx].favoriteIdentifiers.removeAll { $0 == assetIdentifier }
        } else {
            albums[idx].favoriteIdentifiers.append(assetIdentifier)
        }
        save()
    }

    func isFavorite(assetIdentifier: String, in albumID: UUID) -> Bool {
        guard let idx = albums.firstIndex(where: { $0.id == albumID }) else { return false }
        return albums[idx].favoriteIdentifiers.contains(assetIdentifier)
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(albums) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([AlbumProp].self, from: data) {
            albums = decoded
        }
    }
}
