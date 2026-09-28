//
//  DeepLinkHandler.swift
//  dropTo
//
//  Handle deep link dari widget dan shortcuts
//

import Foundation
import SwiftUI

//============================================================================
// DEEP LINK HANDLER
//============================================================================
// PARSE URL DARI WIDGET DAN NAVIGATE KE DESTINATION YANG BENAR

enum DeepLink: Equatable {
    case albumCamera(albumID: UUID)  // dropto://album/{id}/camera
    case album(albumID: UUID)         // dropto://album/{id}
    case home                         // dropto://home
    case unknown

    // PARSE URL STRING JADI DEEP LINK
    // CATATAN: DI "dropto://album/{id}/camera", "album" ITU HOST, BUKAN PATH.
    // JADI HOST + PATH DIGABUNG DULU BIAR PARSING-NYA KONSISTEN.
    static func parse(url: URL) -> DeepLink {
        guard url.scheme?.lowercased() == "dropto" else { return .unknown }

        let parts = ([url.host ?? ""] + url.pathComponents)
            .filter { !$0.isEmpty && $0 != "/" }

        // dropto://album/{id}/camera
        if parts.count == 3,
           parts[0] == "album",
           let albumID = UUID(uuidString: parts[1]),
           parts[2] == "camera" {
            return .albumCamera(albumID: albumID)
        }

        // dropto://album/{id}
        if parts.count == 2,
           parts[0] == "album",
           let albumID = UUID(uuidString: parts[1]) {
            return .album(albumID: albumID)
        }

        // dropto://home
        if parts.isEmpty || parts.first == "home" {
            return .home
        }

        return .unknown
    }
}

//============================================================================
// TAB & CAMERA TARGET
//============================================================================

enum RootTab: Hashable {
    case albums
    case similarPhotos
}

// ALBUM TUJUAN KAMERA (IDENTIFIABLE BIAR BISA DIPAKAI .fullScreenCover(item:))
struct CameraTarget: Identifiable, Equatable {
    let albumID: UUID
    var id: UUID { albumID }
}

//============================================================================
// DEEP LINK COORDINATOR
//============================================================================
// OBSERVABLE CLASS UNTUK COORDINATE NAVIGATION DARI DEEP LINK
//
// ALURNYA:
// 1. selectedTab   → ROOTTABVIEW PINDAH KE TAB ALBUMS
// 2. cameraTarget  → ROOTTABVIEW LANGSUNG BUKA KAMERA (NGGAK NUNGGU NAVIGASI)
// 3. albumToOpen   → HOMEVIEW PUSH ALBUM DI BELAKANG KAMERA,
//                     JADI PAS KAMERA DITUTUP, USER UDAH ADA DI ALBUM ITU

@MainActor
@Observable
class DeepLinkCoordinator {
    
    // TAB YANG AKTIF
    var selectedTab: RootTab = .albums
    
    // ALBUM YANG MAU DI-OPEN (HOMEVIEW YANG HANDLE, LALU DI-NIL-KAN)
    var albumToOpen: UUID?
    
    // KAMERA YANG MAU DIBUKA (ROOTTABVIEW YANG HANDLE)
    var cameraTarget: CameraTarget?
    
    // ALBUM YANG DIBUKA SETELAH KAMERA DITUTUP
    var albumAfterCamera: UUID?
    
    // HANDLE INCOMING URL
    func handle(url: URL) {
        let deepLink = DeepLink.parse(url: url)
        print("📱 Deep link: \(url) → \(deepLink)")
        
        switch deepLink {
        case .albumCamera(let albumID):
            // 1. KAMERA DULUAN, SENDIRIAN (JANGAN BARENG PUSH ALBUM)
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
    
    // 2. DIPANGGIL SAAT KAMERA DITUTUP → BARU BUKA ALBUM-NYA
    func cameraDidClose() {
        if let albumID = albumAfterCamera {
            albumToOpen = albumID
        }
        albumAfterCamera = nil
    }
}
