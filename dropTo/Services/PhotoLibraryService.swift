import Foundation
import Combine
import Photos
import UIKit
import SwiftUI

@MainActor
final class PhotoLibraryService: ObservableObject {
    static let shared = PhotoLibraryService()

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    @Published private(set) var libraryVersion = 0

    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        startObservingLibraryIfNeeded()
    }

    private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
        var onChange: (() -> Void)?
        func photoLibraryDidChange(_ changeInstance: PHChange) {
            DispatchQueue.main.async { [onChange] in onChange?() }
        }
    }

    private var changeObserver: ChangeObserver?

    private func startObservingLibraryIfNeeded() {
        guard changeObserver == nil, isAuthorized else { return }
        let observer = ChangeObserver()
        observer.onChange = { [weak self] in
            Task { @MainActor in self?.libraryVersion += 1 }
        }
        PHPhotoLibrary.shared().register(observer)
        changeObserver = observer
    }

    func requestAccessIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                self?.startObservingLibraryIfNeeded()
            }
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func fetchAllAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func fetchAssets(withIdentifiers identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        assets.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        return assets
    }

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

    func permanentlyDelete(identifiers: [String]) async -> Bool {
        guard !identifiers.isEmpty else { return false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            print("Could not delete photos: \(error)")
            return false
        }
    }

    func loadThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let bucketed = Self.bucket(targetSize)
        let key = "\(asset.localIdentifier)|\(Int(bucketed.width))" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        let image: UIImage? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: bucketed,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image { thumbnailCache.setObject(image, forKey: key) }
        return image
    }

    func prefetchThumbnails(identifiers: [String], limit: Int = 80) {
        let assets = Array(fetchAssets(withIdentifiers: identifiers).prefix(limit))
        let side = (UIScreen.main.bounds.width - 16) / 4 * UIScreen.main.scale
        let size = CGSize(width: side, height: side)
        Task(priority: .userInitiated) { [weak self] in
            for asset in assets {
                _ = await self?.loadThumbnail(for: asset, targetSize: size)
            }
        }
    }

    private static func bucket(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(50, (size.width / 50).rounded(.up) * 50),
            height: max(50, (size.height / 50).rounded(.up) * 50)
        )
    }

    func loadDisplayImage(for asset: PHAsset, maxDimension: CGFloat = 3200) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: maxDimension, height: maxDimension),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

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

    func setFavorite(_ value: Bool, for asset: PHAsset) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = value
            }
            libraryVersion += 1
        } catch {
            print("Could not set favorite: \(error)")
        }
    }
}

typealias DayGroup = (day: Date, assets: [PHAsset])

extension Array where Element == PHAsset {
    func groupedByDay() -> [DayGroup] {
        let calendar = Calendar.current
        return Dictionary(grouping: self) { calendar.startOfDay(for: $0.creationDate ?? Date()) }
            .map { (day: $0.key, assets: $0.value) }
            .sorted { $0.day > $1.day }
    }
}

enum DayTitleFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM"
        return formatter
    }()

    static func string(for date: Date) -> String { formatter.string(from: date) }
}
