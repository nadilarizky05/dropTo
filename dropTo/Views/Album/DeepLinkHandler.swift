import Foundation
import SwiftUI

enum DeepLink: Equatable {
    case albumCamera(albumID: UUID)
    case album(albumID: UUID)
    case home
    case unknown

    static func parse(url: URL) -> DeepLink {
        guard url.scheme?.lowercased() == "dropto" else { return .unknown }

        let parts = ([url.host ?? ""] + url.pathComponents)
            .filter { !$0.isEmpty && $0 != "/" }

        if parts.count == 3,
           parts[0] == "album",
           let albumID = UUID(uuidString: parts[1]),
           parts[2] == "camera" {
            return .albumCamera(albumID: albumID)
        }

        if parts.count == 2,
           parts[0] == "album",
           let albumID = UUID(uuidString: parts[1]) {
            return .album(albumID: albumID)
        }

        if parts.isEmpty || parts.first == "home" {
            return .home
        }

        return .unknown
    }
}

enum RootTab: Hashable {
    case albums
    case unorganized
}

struct CameraTarget: Identifiable, Equatable {
    let albumID: UUID
    var id: UUID { albumID }
}

@MainActor
@Observable
class DeepLinkCoordinator {
    var selectedTab: RootTab = .albums

    var albumToOpen: UUID?

    var cameraTarget: CameraTarget?

    var albumAfterCamera: UUID?

    func handle(url: URL) {
        let deepLink = DeepLink.parse(url: url)
        print("📱 Deep link: \(url) → \(deepLink)")

        switch deepLink {
        case .albumCamera(let albumID):
            selectedTab = .albums
            albumAfterCamera = albumID

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cameraTarget = CameraTarget(albumID: albumID)
            }

        case .album(let albumID):
            selectedTab = .albums
            albumToOpen = albumID

        case .home:
            selectedTab = .albums

        case .unknown:
            print("⚠️ Unknown deep link: \(url)")
        }
    }

    func cameraDidClose() {
        if let albumID = albumAfterCamera {
            albumToOpen = albumID
        }
        albumAfterCamera = nil
    }
}
