//
//  WidgetShared.swift
//  dropTo + AlbumWidgetExtension (HARUS MASUK 2 TARGET)
//

import Foundation

nonisolated enum WidgetShared {
    // HARUS SAMA DENGAN .entitlements APP & WIDGET
    static let appGroupID = "group.com.dila.dropTo"
    static let widgetKind = "AlbumWidget"

    static var folderURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Widget", isDirectory: true)
    }

    static var snapshotURL: URL? { folderURL?.appendingPathComponent("pinnedAlbum.json") }

    static func cameraURL(for albumID: UUID) -> URL {
        URL(string: "dropto://album/\(albumID.uuidString)/camera")!
    }

    static let homeURL = URL(string: "dropto://home")!
}

nonisolated struct PinnedAlbumSnapshot: Codable, Equatable {
    let id: UUID
    let title: String
    let photoCount: Int

    static func load() -> PinnedAlbumSnapshot? {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PinnedAlbumSnapshot.self, from: data)
    }
}
