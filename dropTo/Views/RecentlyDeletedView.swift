//
//  RecentlyDeletedView.swift
//  dropTo
//
//  Every photo swiped-to-delete lands here first — nothing is ever
//  destroyed immediately. The user can Restore it, or Delete it for
//  good. Items left untouched for 30 days quietly drop off this list
//  (handled in AlbumStore).
//

import SwiftUI
import Photos

struct RecentlyDeletedView: View {
    @EnvironmentObject private var albumStore: AlbumStore
    @State private var isSelecting = false
    @State private var selectedIdentifiers: Set<String> = []
    @State private var selectedAsset: PHAsset?

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private var assets: [PHAsset] {
        PhotoLibraryManager.shared.fetchAssets(
            withIdentifiers: albumStore.deletedItems.map(\.assetIdentifier)
        )
    }

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Recently Deleted Items")
                        .font(.headline)
                }
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetThumbnailView(asset: asset)
                            .selectionOverlay(isSelecting: isSelecting, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
                            .onTapGesture {
                                if isSelecting {
                                    toggle(asset.localIdentifier)
                                } else {
                                    // Tapping outside selection mode opens the
                                    // photo full-size, with Recover / Delete
                                    // Forever buttons instead of swipe gestures.
                                    selectedAsset = asset
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selectedIdentifiers.isEmpty {
                actionBar
            }
        }
        .navigationDestination(item: $selectedAsset) { asset in
            PhotoDetailView(assets: assets, startingAt: asset, mode: .recentlyDeleted)
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Recover") {
                for id in selectedIdentifiers {
                    albumStore.restoreFromDeleted(id)
                }
                selectedIdentifiers.removeAll()
            }
            .foregroundStyle(.blue)

            Spacer()

            Button("Delete") {
                Task {
                    let ids = Array(selectedIdentifiers)
                    await PhotoLibraryManager.shared.permanentlyDelete(identifiers: ids)
                    for id in ids { albumStore.removeFromDeletedList(id) }
                    selectedIdentifiers.removeAll()
                }
            }
            .foregroundStyle(.red)
        }
        .font(.subheadline.weight(.semibold))
        .padding()
        .background(.regularMaterial)
    }

    private func toggle(_ identifier: String) {
        guard isSelecting else { return }
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }
}

#Preview {
    NavigationStack { RecentlyDeletedView() }
        .environmentObject(AlbumStore())
}
