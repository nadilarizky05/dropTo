//
//  CH2App.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 24/04/26.
//

import SwiftUI

@main
struct CH2App: App {
    @StateObject var photoManager = PhotoLibraryManager()
    @StateObject var albumStore = AlbumStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(photoManager)
                .environmentObject(albumStore)
        }
    }
}
