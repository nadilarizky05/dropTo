//
//  AllItemsView.swift
//  dropTo
//
//  Created by Nadila Rizky Amelia on 20/07/26.
//

//
//  AllItemsView.swift
//  dropTo
//
//  The "All Items" tab: every photo and video on the device, sorted
//  newest first — organized into albums or not, it doesn't matter here.
//  Tapping an item opens it full-size, but you can only swipe left/right
//  to browse — no swipe-to-delete/keep here, since this isn't tied to
//  any particular album.
//

import SwiftUI
import Photos

struct AllItemsView: View {
    @EnvironmentObject private var albumStore: AlbumStore
    @StateObject private var libraryManager = PhotoLibraryManager.shared

    @State private var assets: [PHAsset] = []
    @State private var selectedAsset: PHAsset?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if assets.isEmpty {
                    ContentUnavailableView(
                        "No Items Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Photos and videos you take will show up here.")
                    )
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            AssetThumbnailView(asset: asset)
                                .onTapGesture { selectedAsset = asset }
                        }
                    }
                }
            }
            .navigationTitle("All Items")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { reload() }
            .onChange(of: albumStore.deletedItems) { _, _ in reload() }
            .task {
                libraryManager.requestAccessIfNeeded()
                reload()
            }
            .navigationDestination(item: $selectedAsset) { asset in
                PhotoDetailView(assets: assets, startingAt: asset, mode: .browseOnly)
            }
        }
    }

    private func reload() {
        guard libraryManager.isAuthorized else { return }
        let deletedIdentifiers = Set(albumStore.deletedItems.map(\.assetIdentifier))
        assets = PhotoLibraryManager.shared
            .fetchAllAssets()
            .filter { !deletedIdentifiers.contains($0.localIdentifier) }
    }
}

#Preview {
    AllItemsView()
        .environmentObject(AlbumStore())
}
