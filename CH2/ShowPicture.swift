//
//  ShowPicture.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//

import SwiftUI
import Photos
import AVKit

struct ShowPicture: View {
    let assets: [PHAsset]
    @State var currentIndex: Int

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var albumStore: AlbumStore
    @EnvironmentObject var photoManager: PhotoLibraryManager
    @State private var showDeleteAlert = false

    var currentAsset: PHAsset { assets[currentIndex] }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(assets.indices, id: \.self) { index in
                    MediaView(asset: assets[index])
                        .tag(index)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Top bar
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(assets.count)")
                        .foregroundStyle(.white)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())

                    Spacer()

                    Button { showDeleteAlert = true } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                            .shadow(radius: 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()
            }
        }
        .alert("Delete this photo?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                let asset = currentAsset
                for i in albumStore.albums.indices {
                    albumStore.albums[i].assetIdentifiers.removeAll { $0 == asset.localIdentifier }
                    if albumStore.albums[i].coverAssetIdentifier == asset.localIdentifier {
                        albumStore.albums[i].coverAssetIdentifier = albumStore.albums[i].assetIdentifiers.isEmpty
                            ? nil
                            : albumStore.albums[i].assetIdentifiers.last
                    }
                }
                photoManager.deleteAsset(asset) { _ in }
                if assets.count <= 1 {
                    dismiss()
                } else {
                    currentIndex = max(0, currentIndex - 1)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the photo from your Photos library.")
        }
    }
}

// MARK: - MediaView

struct MediaView: View {
    let asset: PHAsset
    @State private var image: UIImage? = nil
    @State private var player: AVPlayer? = nil

    // Zoom state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    var isZoomedIn: Bool { scale > 1.01 }

    var body: some View {
        ZStack {
            Color.black

            if asset.mediaType == .video {
                if let player = player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView().tint(.white)
                }
            } else {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(panOffset)
                        // Pinch to zoom
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, lastScale * value)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation(.spring()) {
                                            scale = 1.0
                                            lastScale = 1.0
                                            panOffset = .zero
                                            lastPanOffset = .zero
                                        }
                                    }
                                }
                        )
                        // Pan hanya aktif saat zoom in — saat scale == 1,
                        // gesture ini TIDAK dikonsumsi sehingga TabView bisa swipe
                        .gesture(
                            isZoomedIn
                            ? DragGesture()
                                .onChanged { value in
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastPanOffset = panOffset
                                }
                            : nil
                        )
                        // Double tap to zoom
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if isZoomedIn {
                                    scale = 1.0
                                    lastScale = 1.0
                                    panOffset = .zero
                                    lastPanOffset = .zero
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .onAppear { loadMedia() }
        .onDisappear { player?.pause() }
    }

    func loadMedia() {
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let avAsset = avAsset {
                    DispatchQueue.main.async {
                        player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                        player?.play()
                    }
                }
            }
        } else {
            let size = CGSize(
                width: UIScreen.main.bounds.width * 2,
                height: UIScreen.main.bounds.height * 2
            )
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: nil
            ) { img, _ in
                DispatchQueue.main.async { image = img }
            }
        }
    }
}
