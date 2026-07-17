//
//  AlbumDetailView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//

import SwiftUI
import Photos

// MARK: - AlbumDetailView

struct AlbumDetailView: View {
    let album: AlbumProp
    let photoManager: PhotoLibraryManager

    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    @State private var assets: [PHAsset] = []
    @State private var selectedIndex: Int? = nil
    @State private var showCamera = false

    @State private var isSelecting = false
    @State private var selectedIdentifiers: Set<String> = []

    @State private var showDeleteSelectedAlert = false
    @State private var showMoveSheet = false
    @State private var showCompare = false

    @EnvironmentObject var albumStore: AlbumStore

    var canCompare: Bool { selectedIdentifiers.count == 2 }

    var selectedAssets: [PHAsset] {
        assets.filter { selectedIdentifiers.contains($0.localIdentifier) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                if assets.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 100)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundStyle(.gray.opacity(0.4))
                        Text("No photos yet")
                            .foregroundStyle(.secondary)
                        Text("Drag photos into this album from the main screen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets.indices, id: \.self) { index in
                            let asset = assets[index]
                            let id = asset.localIdentifier
                            let isSelected = selectedIdentifiers.contains(id)
                            let isFav = albumStore.isFavorite(assetIdentifier: id, in: album.id)

                            ZStack(alignment: .topTrailing) {
                                Button {
                                    if isSelecting {
                                        toggleSelect(asset)
                                    } else {
                                        selectedIndex = index
                                    }
                                } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        AssetThumbnailView(asset: asset)
                                            .frame(width: UIScreen.main.bounds.width / 3,
                                                   height: UIScreen.main.bounds.width / 3)
                                            .clipped()
                                            .opacity(isSelecting && !isSelected ? 0.55 : 1.0)

                                        // favorite
                                        if isFav {
                                            Image(systemName: "heart.fill")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                                .padding(5)
                                                .background(Color.black.opacity(0.45))
                                                .clipShape(Circle())
                                                .padding(4)
                                        }
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 0)
                                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                                )

                                // checkmark
                                if isSelecting {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? .blue : .white)
                                        .shadow(radius: 2)
                                        .padding(5)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .padding(.bottom, isSelecting ? 90 : 0)
                }
            }

            // bottom bar
            VStack(spacing: 0) {
                if isSelecting && !selectedIdentifiers.isEmpty {
                    selectActionBar
                } else if !isSelecting {
                    cameraButton
                }
            }
        }
        .navigationTitle(album.albumName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIdentifiers.removeAll() }
                }
            }
        }
        .onAppear { loadAssets() }
        .onChange(of: albumStore.albums) { loadAssets() }

        .fullScreenCover(item: Binding(
            get: { selectedIndex.map { SelectedIndex(value: $0) } },
            set: { selectedIndex = $0?.value }
        )) { selected in
            ShowPicture(assets: assets, currentIndex: selected.value)
                .environmentObject(albumStore)
                .environmentObject(photoManager)
        }
        // camera
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(isPresented: $showCamera) { image in
                photoManager.saveImageToLibrary(image) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let idx = albumStore.albums.firstIndex(where: { $0.id == album.id }),
                           let newest = photoManager.mediaItems.first {
                            albumStore.assignPhoto(assetIdentifier: newest.localIdentifier, to: idx)
                        }
                    }
                }
            } onCaptureVideo: { url in
                photoManager.saveVideoToLibrary(url: url) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let idx = albumStore.albums.firstIndex(where: { $0.id == album.id }),
                           let newest = photoManager.mediaItems.first {
                            albumStore.assignPhoto(assetIdentifier: newest.localIdentifier, to: idx)
                        }
                    }
                }
            }
        }
        // compare
        .fullScreenCover(isPresented: $showCompare) {
            CompareView(assets: selectedAssets, albumID: album.id)
                .environmentObject(albumStore)
                .environmentObject(photoManager)
        }
        // move sheet
        .sheet(isPresented: $showMoveSheet) {
            MoveToAlbumSheet(
                sourceAlbumID: album.id,
                identifiersToMove: selectedIdentifiers
            ) {
                selectedIdentifiers.removeAll()
                isSelecting = false
                loadAssets()
            }
            .environmentObject(albumStore)
        }
        // delete alert
        .alert("Delete \(selectedIdentifiers.count) photo(s)?", isPresented: $showDeleteSelectedAlert) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected photos will be permanently deleted from your Photos library.")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    var selectActionBar: some View {
        HStack(spacing: 12) {
            // move
            ActionBarButton(icon: "folder.fill", label: "Move", color: .blue) {
                showMoveSheet = true
            }

            // compare (only if 2 selected)
            ActionBarButton(
                icon: "rectangle.split.2x1.fill",
                label: "Compare",
                color: canCompare ? .orange : .gray
            ) {
                if canCompare { showCompare = true }
            }
            .disabled(!canCompare)
            .opacity(canCompare ? 1 : 0.5)

            // delete
            ActionBarButton(icon: "trash.fill", label: "Delete", color: .red) {
                showDeleteSelectedAlert = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    var cameraButton: some View {
        HStack {
            Spacer()
            Button { showCamera = true } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.red)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(24)
        }
    }

    // MARK: - Helpers

    func toggleSelect(_ asset: PHAsset) {
        if selectedIdentifiers.contains(asset.localIdentifier) {
            selectedIdentifiers.remove(asset.localIdentifier)
        } else {
            selectedIdentifiers.insert(asset.localIdentifier)
        }
    }

    func deleteSelected() {
        let toDelete = assets.filter { selectedIdentifiers.contains($0.localIdentifier) }
        for identifier in selectedIdentifiers {
            albumStore.removePhoto(assetIdentifier: identifier, from: album.id)
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        }) { success, _ in
            if success {
                DispatchQueue.main.async {
                    photoManager.fetchAllMedia()
                    selectedIdentifiers.removeAll()
                    isSelecting = false
                    loadAssets()
                }
            }
        }
    }

    func loadAssets() {
        let current = albumStore.albums.first(where: { $0.id == album.id }) ?? album
        let result = PHAsset.fetchAssets(withLocalIdentifiers: current.assetIdentifiers, options: nil)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched.reversed()
    }
}

// MARK: - ActionBarButton

struct ActionBarButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - MoveToAlbumSheet

struct MoveToAlbumSheet: View {
    let sourceAlbumID: UUID
    let identifiersToMove: Set<String>
    let onDone: () -> Void

    @EnvironmentObject var albumStore: AlbumStore
    @Environment(\.dismiss) var dismiss

    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""

    // go to album except the source album
    var targetAlbums: [AlbumProp] {
        albumStore.albums.filter { $0.id != sourceAlbumID }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    newAlbumName = ""
                    showNewAlbumAlert = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("New Album")
                                .bold()
                                .foregroundStyle(.primary)
                            Text("Create and move here")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(targetAlbums) { album in
                    Button {
                        if let idx = albumStore.albums.firstIndex(where: { $0.id == album.id }) {
                            albumStore.movePhotos(
                                identifiers: identifiersToMove,
                                from: sourceAlbumID,
                                to: idx
                            )
                        }
                        dismiss()
                        onDone()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.albumName)
                                    .bold()
                                    .foregroundStyle(.primary)
                                Text("\(album.numberOfPhotos) photos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Move \(identifiersToMove.count) photo\(identifiersToMove.count > 1 ? "s" : "") to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }

            .alert("New Album", isPresented: $showNewAlbumAlert) {
                TextField("Album Name", text: $newAlbumName)
                Button("Create & Move") {
                    let name = newAlbumName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    albumStore.addAlbum(name: name)
                    albumStore.movePhotos(
                        identifiers: identifiersToMove,
                        from: sourceAlbumID,
                        to: 0
                    )
                    dismiss()
                    onDone()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Photos will be moved to the new album.")
            }
        }
    }
}

// MARK: - SelectedIndex (shared helper)

struct SelectedIndex: Identifiable {
    let id = UUID()
    let value: Int
}
