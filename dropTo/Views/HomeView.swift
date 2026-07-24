//
//  HomeView.swift
//  dropTo
//
//  The "All Albums" tab: a grid of albums.
//  - "Unorganized Items" (things not filed into any album yet) sits
//    near the top; "Recently Deleted" at the very end — both pinned,
//    like Apple's own Photos app.
//  - Every other tile is a user-created album, showing its most recent
//    item as the cover.
//  - "Select" (top right) lets you multi-select your own albums and
//    delete them, with a confirmation first since deleting an album
//    also sends everything inside it to Recently Deleted.
//  - Long-press an album for Rename / Delete, or drag it to reorder.
//

import SwiftUI
import Photos
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var albumStore: AlbumStore
    @StateObject private var libraryManager = PhotoLibraryManager.shared

    @State private var showNewAlbumSheet = false
    @State private var selectedAlbum: AlbumModel?
    @State private var showUnorganizedItems = false
    @State private var showRecentlyDeleted = false

    @State private var isSelecting = false
    @State private var selectedAlbumIDs: Set<UUID> = []
    @State private var showDeleteConfirmation = false

    @State private var draggingAlbumID: UUID?
    @State private var albumToRename: AlbumModel?
    @State private var renameText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// Newest item in "Recently Deleted", used as that tile's cover
    /// instead of a plain trash icon.
    private var mostRecentlyDeletedAsset: PHAsset? {
        guard let identifier = albumStore.deletedItems.first?.assetIdentifier else { return nil }
        return PhotoLibraryManager.shared.fetchAssets(withIdentifiers: [identifier]).first
    }

    /// Every real photo/video on the device that ISN'T yet filed into an
    /// album, and isn't sitting in Recently Deleted either.
    private var unorganizedAssets: [PHAsset] {
        guard libraryManager.isAuthorized else { return [] }
        let deletedIdentifiers = Set(albumStore.deletedItems.map(\.assetIdentifier))
        let organizedIdentifiers = Set(albumStore.albums.flatMap(\.assetIdentifiers))
        return PhotoLibraryManager.shared
            .fetchAllAssets()
            .filter { !deletedIdentifiers.contains($0.localIdentifier) && !organizedIdentifiers.contains($0.localIdentifier) }
    }

    private var unorganizedCoverAsset: PHAsset? { unorganizedAssets.first }
    private var unorganizedCount: Int { unorganizedAssets.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    // "New Album" sits inside the grid, same size as every
                    // other tile. Tapping it while selecting exits
                    // selection instead of opening the sheet.
                    NewAlbumTile()
                        .onTapGesture {
                            if isSelecting {
                                isSelecting = false
                                selectedAlbumIDs.removeAll()
                            } else {
                                showNewAlbumSheet = true
                            }
                        }

                    // Pinned system tile — never selectable/deletable.
                    SystemTileView(
                        title: "Unorganized Items",
                        subtitle: "\(unorganizedCount) items",
                        systemImage: "tray.full.fill",
                        tint: .blue,
                        coverAsset: unorganizedCoverAsset
                    )
                    .onTapGesture { if !isSelecting { showUnorganizedItems = true } }

                    // User-created albums — these are the ones Select mode
                    // lets you pick and delete. Long-press for Rename /
                    // Delete, or drag to reorder.
                    ForEach(albumStore.albums) { album in
                        AlbumGridCell(
                            album: album,
                            isSelecting: isSelecting,
                            isSelected: selectedAlbumIDs.contains(album.id)
                        )
                        .onTapGesture {
                            if isSelecting {
                                toggle(album.id)
                            } else {
                                selectedAlbum = album
                            }
                        }
                        .contextMenu {
                            Button {
                                albumToRename = album
                                renameText = album.title
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                albumStore.deleteAlbum(album)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onDrag {
                            draggingAlbumID = album.id
                            return NSItemProvider(object: album.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: AlbumDropDelegate(
                                targetAlbum: album,
                                albumStore: albumStore,
                                draggingAlbumID: $draggingAlbumID
                            )
                        )
                    }

                    // "Recently Deleted" — always last, never selectable.
                    SystemTileView(
                        title: "Recently Deleted",
                        subtitle: "\(albumStore.deletedItems.count) items",
                        systemImage: "trash",
                        tint: .gray,
                        coverAsset: mostRecentlyDeletedAsset
                    )
                    .onTapGesture { if !isSelecting { showRecentlyDeleted = true } }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("dropTo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Cancel" : "Select") {
                        isSelecting.toggle()
                        selectedAlbumIDs.removeAll()
                    }
                    .disabled(albumStore.albums.isEmpty && !isSelecting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selectedAlbumIDs.isEmpty {
                    deleteAlbumsBar
                }
            }
            .alert(
                "Delete \(selectedAlbumIDs.count) Album\(selectedAlbumIDs.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    for album in albumStore.albums where selectedAlbumIDs.contains(album.id) {
                        albumStore.deleteAlbum(album)
                    }
                    selectedAlbumIDs.removeAll()
                    isSelecting = false
                }
            } message: {
                Text("Everything inside will move to Recently Deleted. This won't remove the photos from your device.")
            }
            .alert(
                "Rename Album",
                isPresented: Binding(
                    get: { albumToRename != nil },
                    set: { if !$0 { albumToRename = nil } }
                )
            ) {
                TextField("Album Title", text: $renameText)
                Button("Cancel", role: .cancel) { albumToRename = nil }
                Button("Save") {
                    if let album = albumToRename {
                        albumStore.renameAlbum(album, to: renameText)
                    }
                    albumToRename = nil
                }
            }
            .sheet(isPresented: $showNewAlbumSheet) {
                NewAlbumSheet()
            }
            .navigationDestination(item: $selectedAlbum) { album in
                AlbumDetailView(album: album)
            }
            .navigationDestination(isPresented: $showUnorganizedItems) {
                UnorganizedItemsView()
            }
            .navigationDestination(isPresented: $showRecentlyDeleted) {
                RecentlyDeletedView()
            }
            .task {
                libraryManager.requestAccessIfNeeded()
            }
        }
    }

    private var deleteAlbumsBar: some View {
        HStack {
            Text("\(selectedAlbumIDs.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func toggle(_ id: UUID) {
        if selectedAlbumIDs.contains(id) {
            selectedAlbumIDs.remove(id)
        } else {
            selectedAlbumIDs.insert(id)
        }
    }
}

// MARK: - Subviews

/// The "create album" tile — same square size as every other tile in
/// the grid, so everything lines up neatly in rows.
private struct NewAlbumTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray5))
                    .aspectRatio(1, contentMode: .fit)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.4), lineWidth: 0.5))

            Text("New Album")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            // Invisible placeholder — every other tile has a second line
            // ("12 items"), so this keeps all tiles the same height and
            // stops the grid rows from looking uneven.
            Text(" ")
                .font(.caption2)
        }
    }
}

/// A pinned tile like "Unorganized Items" or "Recently Deleted".
private struct SystemTileView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let coverAsset: PHAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let coverAsset {
                    AssetThumbnailView(asset: coverAsset, cornerRadius: 16)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .aspectRatio(1, contentMode: .fit)
                    Image(systemName: systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(tint)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.4), lineWidth: 0.5))

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A normal user album cell — cover photo = most recent item added.
/// The selection badge/ring is applied directly to the image square
/// (not the whole card), so it sits right on the photo's corner —
/// matching the native Photos app look.
private struct AlbumGridCell: View {
    let album: AlbumModel
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var coverAsset: PHAsset? {
        PhotoLibraryManager.shared
            .fetchAssets(withIdentifiers: album.assetIdentifiers)
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let coverAsset {
                    AssetThumbnailView(asset: coverAsset, cornerRadius: 16)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemGray5))
                            .aspectRatio(1, contentMode: .fit)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.4), lineWidth: 0.5))
            .selectionOverlay(isSelecting: isSelecting, isSelected: isSelected)

            Text(album.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(album.assetIdentifiers.count) items")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Drop handler that reorders `albumStore.albums` while a tile is being
/// dragged over another tile.
private struct AlbumDropDelegate: DropDelegate {
    let targetAlbum: AlbumModel
    let albumStore: AlbumStore
    @Binding var draggingAlbumID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggingAlbumID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingAlbumID,
              draggingID != targetAlbum.id,
              let fromIndex = albumStore.albums.firstIndex(where: { $0.id == draggingID }),
              let toIndex = albumStore.albums.firstIndex(where: { $0.id == targetAlbum.id })
        else { return }

        withAnimation {
            albumStore.moveAlbum(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AlbumStore())
}
