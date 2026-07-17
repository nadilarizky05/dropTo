//
//  PhotoLibraryManager.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//

import Photos
import SwiftUI
import Combine

class PhotoLibraryManager: ObservableObject {
    @Published var mediaItems: [PHAsset] = []
    @Published var mediaByDay: [(date: Date, assets: [PHAsset])] = []
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    var allAssets: [PHAsset] { mediaItems }

    func requestPermissionAndLoad() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            if status == .authorized || status == .limited {
                self.fetchAllMedia()
            }
        }
    }   

    func fetchAllMedia() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: fetchOptions)

        var result: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in result.append(asset) }

        let calendar = Calendar.current
        var grouped: [Date: [PHAsset]] = [:]
        for asset in result {
            let day = calendar.startOfDay(for: asset.creationDate ?? Date())
            grouped[day, default: []].append(asset)
        }

        let sorted = grouped.map { (date: $0.key, assets: $0.value) }
            .sorted { $0.date > $1.date }

        DispatchQueue.main.async {
            self.mediaItems = result
            self.mediaByDay = sorted
        }
    }

    var assetsForSelectedDay: [PHAsset] {
        let calendar = Calendar.current
        return mediaItems.filter {
            calendar.isDate($0.creationDate ?? Date(), inSameDayAs: selectedDate)
        }
    }

    func unorganizedAssets(albums: [AlbumProp]) -> [PHAsset] {
        let allAssigned = Set(albums.flatMap { $0.assetIdentifiers })
        return mediaItems.filter { !allAssigned.contains($0.localIdentifier) }
    }

    func deleteAsset(_ asset: PHAsset, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { success, _ in
            if success {
                DispatchQueue.main.async {
                    self.fetchAllMedia()
                    completion(true)
                }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func saveImageToLibrary(_ image: UIImage, completion: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, _ in
            if success {
                DispatchQueue.main.async { self.fetchAllMedia(); completion() }
            }
        }
    }

    func saveVideoToLibrary(url: URL, completion: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, _ in
            if success {
                DispatchQueue.main.async { self.fetchAllMedia(); completion() }
            }
        }
    }

    func loadImage(for asset: PHAsset, size: CGSize = CGSize(width: 300, height: 300), completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }
}
