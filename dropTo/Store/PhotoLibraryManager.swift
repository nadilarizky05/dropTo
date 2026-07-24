//
//  PhotoLibraryManager.swift
//  dropTo
//
//  This file talks to Apple's "Photos" framework (called PhotoKit).
//  Think of PhotoKit as the real librarian who actually owns every photo
//  on the iPhone. dropTo never keeps its own private copy of images —
//  instead it politely ASKS this librarian: "may I see this photo?",
//  "please save this new photo", "please delete that one".
//
//  Beginner note: `PHAsset` is Apple's word for "one photo or video
//  in the library". `localIdentifier` is that photo's unique ID card.
//

import Foundation
import Combine
import Photos
import UIKit
import SwiftUI

@MainActor
final class PhotoLibraryManager: ObservableObject {

    static let shared = PhotoLibraryManager()

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Ask the user for permission to read & write photos.
    /// Call this once, e.g. when the Home screen first appears.
    func requestAccessIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
            }
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    // MARK: - Fetching

    /// Returns every photo AND video asset in the library, newest first.
    /// This powers the "All Photos" tile.
    func fetchAllAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options) // no `.image` filter = photos + videos
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Looks up real PHAssets for a list of stored localIdentifiers,
    /// keeping them sorted newest first. Used to display a custom album.
    func fetchAssets(withIdentifiers identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        assets.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        return assets
    }

    // MARK: - Saving a brand new photo (taken with the camera button)

    /// Saves a UIImage into the system Photos library and returns the
    /// new asset's localIdentifier, so we can immediately drop it into
    /// whichever album the user was looking at.
    func saveNewPhoto(_ image: UIImage) async -> String? {
        var newIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                newIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            return newIdentifier
        } catch {
            print("Could not save photo: \(error)")
            return nil
        }
    }

    /// Same idea as `saveNewPhoto`, but for a video the camera just
    /// recorded (delivered to us as a temporary file URL).
    func saveNewVideo(fileURL: URL) async -> String? {
        var newIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL) else { return }
                newIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            return newIdentifier
        } catch {
            print("Could not save video: \(error)")
            return nil
        }
    }

    // MARK: - Permanently deleting (used from "Recently Deleted")

    func permanentlyDelete(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            print("Could not delete photos: \(error)")
        }
    }

    // MARK: - Loading actual pixels for a PHAsset

    /// Loads a thumbnail-sized image. Cheap & fast — use this for grids.
    func loadThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Loads the full-resolution image. Use this for the single-photo
    /// detail screen where the user swipes to delete/keep.
    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    func toggleFavorite(for asset: PHAsset) async {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest(for: asset)
                    request.isFavorite = !asset.isFavorite
                }
            } catch {
                print("Could not toggle favorite: \(error)")
            }
        }
}
