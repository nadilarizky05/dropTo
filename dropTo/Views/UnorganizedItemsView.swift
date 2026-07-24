//
//  UnorganizedItemsView.swift
//  dropTo
//
//  Created by Nadila Rizky Amelia on 20/07/26.
//

//
//  UnorganizedItemsView.swift
//  dropTo
//
//  "Unorganized Items" = everything on the device that ISN'T yet sitting
//  inside one of your custom albums (and isn't in Recently Deleted
//  either). This is where new photos/videos land until you file them
//  away — "Select" lets you multi-pick a batch and move them into an
//  album in one go.
//

import SwiftUI
import Photos

struct UnorganizedItemsView: View {
    @EnvironmentObject private var albumStore: AlbumStore
    @State private var selectedAsset: PHAsset?
    @State private var isSelecting = false
    @State private var selectedIdentifiers: Set<String> = []
    @State private var showMoveSheet = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    /// Everything already filed into a custom album — anything in this
    /// set is considered "organized" and shouldn't show up here.
    private var organizedIdentifiers: Set<String> {
        Set(albumStore.albums.flatMap(\.assetIdentifiers))
    }

    private var deletedIdentifiers: Set<String> {
        Set(albumStore.deletedItems.map(\.assetIdentifier))
    }

    private var assets: [PHAsset] {
        PhotoLibraryManager.shared
            .fetchAllAssets()
            .filter { !organizedIdentifiers.contains($0.localIdentifier) && !deletedIdentifiers.contains($0.localIdentifier) }
    }

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                ContentUnavailableView(
                    "All Organized!",
                    systemImage: "checkmark.circle",
                    description: Text("Every photo and video is filed into an album.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetThumbnailView(asset: asset)
                            .selectionOverlay(isSelecting: isSelecting, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
                            .onTapGesture {
                                if isSelecting {
                                    toggle(asset.localIdentifier)
                                } else {
                                    selectedAsset = asset
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Unorganized Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
                .disabled(assets.isEmpty && !isSelecting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selectedIdentifiers.isEmpty {
                selectionActionBar
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            // No source album — these items aren't in one yet.
            MoveToAlbumSheet(sourceAlbum: nil, identifiersToMove: Array(selectedIdentifiers)) {
                selectedIdentifiers.removeAll()
                isSelecting = false
            }
        }
        .navigationDestination(item: $selectedAsset) { asset in
            // Deleting from here still works like a normal album (soft
            // delete into Recently Deleted) — it just isn't tied to a
            // specific album, so Recover simply leaves it "unorganized".
            PhotoDetailView(assets: assets, startingAt: asset, mode: .album(AlbumModel(title: "Unorganized Items")))
        }
    }

    private var selectionActionBar: some View {
        HStack {
            Text("\(selectedIdentifiers.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showMoveSheet = true
            } label: {
                Label("Move to Album", systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(selectedIdentifiers.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func toggle(_ identifier: String) {
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }
}

#Preview {
    NavigationStack { UnorganizedItemsView() }
        .environmentObject(AlbumStore())
}
