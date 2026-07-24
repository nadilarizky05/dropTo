////
////  AllPhotosView.swift
////  dropTo
////
////  This is the special album that always mirrors EVERY photo already
////  on the iPhone (via PhotoKit), sorted by newest first — exactly like
////  the "All Photos" collection in Apple's own Photos app.
////
//
//import SwiftUI
//import Photos
//
//struct AllPhotosView: View {
//    @EnvironmentObject private var albumStore: AlbumStore
//    @State private var assets: [PHAsset] = []
//    @State private var selectedAsset: PHAsset?
//
//    private let columns = [
//        GridItem(.flexible(), spacing: 2),
//        GridItem(.flexible(), spacing: 2),
//        GridItem(.flexible(), spacing: 2),
//        GridItem(.flexible(), spacing: 2)
//    ]
//
//    var body: some View {
//        ScrollView {
//            LazyVGrid(columns: columns, spacing: 2) {
//                ForEach(assets, id: \.localIdentifier) { asset in
//                    AssetThumbnailView(asset: asset)
//                        .onTapGesture { selectedAsset = asset }
//                }
//            }
//        }
//        .navigationTitle("All Photos")
//        .navigationBarTitleDisplayMode(.inline)
//        .onAppear { reload() }
//        .onChange(of: albumStore.deletedItems) { _, _ in reload() }
//        .navigationDestination(item: $selectedAsset) { asset in
//            // "All Photos" isn't tied to one custom album, so we hand
//            // in a lightweight placeholder album — Undo simply won't
//            // have anywhere specific to restore to from here.
//            PhotoDetailView(assets: assets, startingAt: asset, mode: .album(AlbumModel(title: "All Photos")))
//        }
//    }
//
//    private func reload() {
//        // A photo that's sitting in "Recently Deleted" shouldn't still
//        // show up here — otherwise it looks like deleting did nothing.
//        let deletedIdentifiers = Set(albumStore.deletedItems.map(\.assetIdentifier))
//        assets = PhotoLibraryManager.shared.fetchAllAssets()
//            .filter { !deletedIdentifiers.contains($0.localIdentifier) }
//    }
//}
//
//#Preview {
//    NavigationStack { AllPhotosView() }
//}
