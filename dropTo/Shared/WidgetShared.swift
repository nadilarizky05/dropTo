import Foundation

nonisolated enum WidgetShared {
    static let appGroupID = "group.com.dila.dropTo"
    static let widgetKind = "AlbumWidget"

    static var folderURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Widget", isDirectory: true)
    }

    static var snapshotURL: URL? { folderURL?.appendingPathComponent("pinnedAlbum.json") }
    static var coverImageURL: URL? { folderURL?.appendingPathComponent("pinnedAlbumCover.jpg") }

    static func cameraURL(for albumID: UUID) -> URL {
        URL(string: "dropto://album/\(albumID.uuidString)/camera")!
    }

    static let homeURL = URL(string: "dropto://home")!
}

nonisolated struct PinnedAlbumSnapshot: Codable, Equatable {
    let id: UUID
    let title: String
    let photoCount: Int
    var lastPhotoDate: Date? = nil

    static func load() -> PinnedAlbumSnapshot? {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PinnedAlbumSnapshot.self, from: data)
    }
}
