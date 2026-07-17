//
//  CompareView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 27/04/26.
//

import SwiftUI
import Photos

struct CompareView: View {
    let assets: [PHAsset]
    let albumID: UUID

    @EnvironmentObject var albumStore: AlbumStore
    @EnvironmentObject var photoManager: PhotoLibraryManager
    @Environment(\.dismiss) var dismiss


    @State private var scales: [String: CGFloat] = [:]
    @State private var lastScales: [String: CGFloat] = [:]
    @State private var offsets: [String: CGSize] = [:]
    @State private var lastOffsets: [String: CGSize] = [:]


    @State private var focusedIdentifier: String? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 2) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    let id = asset.localIdentifier
                    let isFav = albumStore.isFavorite(assetIdentifier: id, in: albumID)
                    let isFocused = focusedIdentifier == id

                    ZStack(alignment: .topTrailing) {
                        ComparePhotoPane(
                            asset: asset,
                            scale: Binding(
                                get: { scales[id] ?? 1.0 },
                                set: { scales[id] = $0 }
                            ),
                            lastScale: Binding(
                                get: { lastScales[id] ?? 1.0 },
                                set: { lastScales[id] = $0 }
                            ),
                            offset: Binding(
                                get: { offsets[id] ?? .zero },
                                set: { offsets[id] = $0 }
                            ),
                            lastOffset: Binding(
                                get: { lastOffsets[id] ?? .zero },
                                set: { lastOffsets[id] = $0 }
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(isFocused ? Color.blue : Color.clear, lineWidth: 4)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.2)) {
                                focusedIdentifier = (focusedIdentifier == id) ? nil : id
                            }
                        }

                        // favorite
                        Button {
                            albumStore.toggleFavorite(assetIdentifier: id, in: albumID)
                        } label: {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundStyle(isFav ? .red : .white)
                                .shadow(color: .black.opacity(0.6), radius: 3)
                                .padding(10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isFocused {
                        Button {
                            showDeleteAlert = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text("Delete Photo")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                        }
                        .padding(.vertical, 6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    Spacer()
                    Text("Compare")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    // Spacer visual balance
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .opacity(0)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                Spacer()
            }
        }
        .animation(.spring(duration: 0.25), value: focusedIdentifier)
        .alert("Delete this photo?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                guard let id = focusedIdentifier,
                      let asset = assets.first(where: { $0.localIdentifier == id }) else { return }
                albumStore.removePhoto(assetIdentifier: id, from: albumID)
                photoManager.deleteAsset(asset) { _ in }
                focusedIdentifier = nil
                // close compare view if all photos deleted
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the photo from your Photos library.")
        }
    }
}

// MARK: - ComparePhotoPane

struct ComparePhotoPane: View {
    let asset: PHAsset
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    @State private var image: UIImage? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .clipped()
                        .gesture(
                            SimultaneousGesture(
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
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1.01 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        guard scale > 1.01 else { return }
                                        lastOffset = offset
                                    }
                            )
                        )
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .onAppear { loadImage() }
    }

    func loadImage() {
        let size = CGSize(width: UIScreen.main.bounds.width * 2,
                          height: UIScreen.main.bounds.height)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: nil
        ) { img, _ in
            DispatchQueue.main.async { image = img }
        }
    }
}
