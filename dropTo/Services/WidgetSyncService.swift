//
//  WidgetSyncService.swift
//  dropTo (MAIN APP ONLY)
//
//  KIRIM DATA ALBUM YANG DI-PIN KE WIDGET:
//  1. TULIS pinnedAlbum.json (ID, NAMA ALBUM, JUMLAH FOTO) KE APP GROUP
//  2. SURUH WIDGET RELOAD
//
//  DESAIN WIDGET-NYA TETAP (BIRU + KAMERA), YANG BERUBAH CUMA NAMA ALBUM.
//

import Foundation
import WidgetKit

@MainActor
enum WidgetSyncService {

    // SNAPSHOT TERAKHIR YANG UDAH DIKIRIM (BIAR NGGAK RELOAD WIDGET KALAU NGGAK ADA PERUBAHAN)
    private static var lastSnapshot: PinnedAlbumSnapshot?
    private static var didSyncOnce = false

    //============================================================================
    // SYNC
    //============================================================================
    // PANGGIL SETIAP DATA BERUBAH. KIRIM NIL KALAU NGGAK ADA ALBUM YANG DI-PIN

    static func sync(pinnedAlbum album: Album?) {
        guard let folderURL = WidgetShared.folderURL,
              let snapshotURL = WidgetShared.snapshotURL else {
            print("⚠️ WidgetSync: App Group container not found. Cek App Groups di Signing & Capabilities")
            return
        }

        let snapshot = album.map {
            PinnedAlbumSnapshot(id: $0.id, title: $0.title, photoCount: $0.assetIdentifiers.count)
        }

        // NGGAK ADA YANG BERUBAH → SKIP
        guard !didSyncOnce || snapshot != lastSnapshot else { return }
        didSyncOnce = true
        lastSnapshot = snapshot

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
            try? fileManager.removeItem(at: snapshotURL) // NGGAK ADA YANG DI-PIN
        }

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
    }
}
