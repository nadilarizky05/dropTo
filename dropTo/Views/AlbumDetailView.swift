//
//  AlbumDetailView.swift
//  dropTo
//
//  Shows everything inside one album, newest first, grouped by the day
//  they were taken ("Tue, 01 March" style headers). The camera button
//  opens the real camera and files the new photo/video straight into
//  this album. "Select" lets you multi-select items and move them into
//  a different album.
//

import SwiftUI
import Photos

struct AlbumDetailView: View {
    let album: AlbumModel
    @EnvironmentObject private var albumStore: AlbumStore

    @State private var showCamera = false
    @State private var selectedAsset: PHAsset?
    @State private var isSelecting = false
    @State private var selectedIdentifiers: Set<String> = []
    @State private var showMoveSheet = false

    private var currentAlbum: AlbumModel {
        albumStore.albums.first(where: { $0.id == album.id }) ?? album
    }

    private var groupedAssets: [(day: Date, assets: [PHAsset])] {
        let assets = PhotoLibraryManager.shared.fetchAssets(withIdentifiers: currentAlbum.assetIdentifiers)
        let groups = Dictionary(grouping: assets) { asset in
            Calendar.current.startOfDay(for: asset.creationDate ?? Date())
        }
        return groups
            .map { (day: $0.key, assets: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        ScrollView {
            if currentAlbum.assetIdentifiers.isEmpty {
                EmptyAlbumView()
                    .padding(.top, 100)
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedAssets, id: \.day) { group in
                        Text(sectionTitle(for: group.day))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(group.assets, id: \.localIdentifier) { asset in
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
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.vertical)
            }
        }
        // Pinning via safeAreaInset keeps the button reliably in place,
        // regardless of scroll content height.
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionActionBar }
            else {
                HStack { Spacer(); CameraFloatingButton { showCamera = true }; Spacer() }  // ← center
            }
        }
        .navigationTitle(currentAlbum.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
                .disabled(currentAlbum.assetIdentifiers.isEmpty && !isSelecting)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { media in
                Task {
                    let identifier: String?
                    switch media {
                    case .photo(let image):
                        identifier = await PhotoLibraryManager.shared.saveNewPhoto(image)
                    case .video(let url):
                        identifier = await PhotoLibraryManager.shared.saveNewVideo(fileURL: url)
                    }
                    if let identifier {
                        albumStore.addAsset(identifier, to: currentAlbum)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToAlbumSheet(sourceAlbum: currentAlbum, identifiersToMove: Array(selectedIdentifiers)) {
                selectedIdentifiers.removeAll()
                isSelecting = false
            }
        }
        .navigationDestination(item: $selectedAsset) { asset in
            PhotoDetailView(assets: groupedAssets.flatMap(\.assets), startingAt: asset, mode: .album(currentAlbum))
        }
    }

    // MARK: - Select mode action bar

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

    private func sectionTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM"
        return formatter.string(from: date)
    }
}

private struct EmptyAlbumView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No items yet")
                .font(.headline)
            Text("Take a photo or video, or drag items here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Glassy floating capture button, centered like a native camera shutter
/// affordance — translucent material with a soft specular ring, in the
/// spirit of Apple's newer "Liquid Glass" look.
private struct CameraFloatingButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(Color.black.opacity(0.25))
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.85), .white.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
    }
}

// Lets `.navigationDestination(item:)` work with PHAsset by identifying
// it via its unique localIdentifier. (PHAsset already conforms to
// Hashable on its own — we only need to add Identifiable here.)
extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

#Preview {
    NavigationStack {
        AlbumDetailView(album: AlbumModel(title: "Coding"))
            .environmentObject(AlbumStore())
    }
}
