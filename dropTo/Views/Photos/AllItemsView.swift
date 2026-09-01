//
//  AllItemsView.swift
//  dropTo
//
//  Created by Nadila Rizky Amelia on 20/07/26.
//
//============================================================================
// VIEW: ALL ITEMS
//============================================================================
// HALAMAN SEMUA FOTO/VIDEO DI DEVICE (EXCLUDE YANG UDAH DIHAPUS)

import SwiftUI
import Photos

struct AllItemsView: View {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    
    @EnvironmentObject private var dataService: DataService
    @StateObject private var libraryManager = PhotoLibraryService.shared
    
    @State private var assets: [PHAsset] = []          // LIST SEMUA FOTO/VIDEO
    @State private var selectedAsset: PHAsset?         // FOTO YANG DIPILIH (NAVIGATION)
    @State private var deletedItems: [DeletedItem] = [] // LIST FOTO DI TRASH
    
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
            .onReceive(dataService.$lastUpdate) { _ in
                reload()
            }
            .task {
                libraryManager.requestAccessIfNeeded()
                reload()
            }
            .navigationDestination(item: $selectedAsset) { asset in
                PhotoDetailView(assets: assets, startingAt: asset, mode: .browseOnly)
            }
        }
    }

    //============================================================================
    // FUNCTION: RELOAD
    //============================================================================
    // AMBIL SEMUA FOTO/VIDEO DI DEVICE, FILTER YANG SUDAH DIHAPUS
    
    private func reload() {
        guard libraryManager.isAuthorized else { return }
        deletedItems = dataService.fetchDeletedItems()
        let deletedIdentifiers = Set(deletedItems.map(\.assetIdentifier))
        assets = PhotoLibraryService.shared
            .fetchAllAssets()
            .filter { !deletedIdentifiers.contains($0.localIdentifier) }
    }
}

#Preview {
    AllItemsView()
        .environmentObject(DataService())
}
