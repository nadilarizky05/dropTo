//
//  dropToApp.swift
//  dropTo
//
//  This is the starting point of the whole app.
//  Think of it like the "main()" function you'd see in other languages —
//  iOS looks here first to know what screen to show.
//

import SwiftUI
import AVFoundation

@main
struct dropToApp: App {

    // AlbumStore is the "brain" of the app. It remembers every album,
    // every photo inside those albums, and everything sitting in
    // "Recently Deleted". We create ONE instance here and hand it down
    // to every screen, so all screens always see the same up-to-date data.
    @StateObject private var albumStore = AlbumStore()

    init() {
        // Without this, videos with sound can end up silent, or muted
        // by the phone's physical silent switch. `.playback` tells iOS
        // "this app intentionally plays audio, please actually play it".
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(albumStore)
        }
    }
}
