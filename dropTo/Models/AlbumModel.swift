//
//  AlbumModel.swift
//  dropTo
//
//  A very simple "blueprint" describing what an Album looks like.
//  It does NOT store actual images — it only stores the ID (a text string
//  called `localIdentifier`) that points to a photo living in the
//  iPhone's real Photos library. That's how dropTo stays connected
//  to the Photos app instead of copying everything.
//

import Foundation

struct AlbumModel: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var tag: String?
    var createdAt: Date = Date()

    // The "receipts" for photos that belong to this album.
    // Each string is a PHAsset.localIdentifier — a unique ID that
    // Apple's Photos framework gives every photo on the device.
    var assetIdentifiers: [String] = []
}

// A tiny helper enum so our Home screen can show 3 kinds of tiles:
// the special "All Photos" tile, the special "Recently Deleted" tile,
// and normal user-made albums — all in one list, one grid.
enum HomeTile: Identifiable {
    case allPhotos
    case recentlyDeleted
    case album(AlbumModel)

    var id: String {
        switch self {
        case .allPhotos: return "allPhotos"
        case .recentlyDeleted: return "recentlyDeleted"
        case .album(let album): return album.id.uuidString
        }
    }
}
