import Foundation
import WidgetKit
import UIKit
import Photos

@MainActor
enum WidgetSyncService {
    private static var lastSnapshot: PinnedAlbumSnapshot?
    private static var lastCoverIdentifier: String?
    private static var didSyncOnce = false

    static func sync(pinnedAlbum album: Album?) async {
        guard let folderURL = WidgetShared.folderURL,
              let snapshotURL = WidgetShared.snapshotURL else {
            print("⚠️ WidgetSync: App Group container not found. Cek App Groups di Signing & Capabilities")
            return
        }

        let coverAsset = album.flatMap { PhotoLibraryService.shared.fetchAssets(withIdentifiers: $0.assetIdentifiers).first }

        let snapshot = album.map {
            PinnedAlbumSnapshot(
                id: $0.id,
                title: $0.title,
                photoCount: $0.assetIdentifiers.count,
                lastPhotoDate: coverAsset?.creationDate
            )
        }

        guard !didSyncOnce || snapshot != lastSnapshot || coverAsset?.localIdentifier != lastCoverIdentifier else { return }
        didSyncOnce = true
        lastSnapshot = snapshot
        lastCoverIdentifier = coverAsset?.localIdentifier

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        if let snapshot {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: snapshotURL, options: .atomic)
                print("📌 WidgetSync: '\(snapshot.title)' dikirim ke widget")
            } catch {
                print("❌ WidgetSync: gagal nulis snapshot - \(error)")
            }
        } else {
            try? fileManager.removeItem(at: snapshotURL)
        }

        await writeCoverImage(coverAsset, to: WidgetShared.coverImageURL)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
    }

    private static func writeCoverImage(_ asset: PHAsset?, to url: URL?) async {
        guard let url else { return }
        guard let asset else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let image = await PhotoLibraryService.shared.loadThumbnail(for: asset, targetSize: CGSize(width: 360, height: 360)),
              let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
