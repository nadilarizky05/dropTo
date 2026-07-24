//
//  PhotoDetailView.swift
//  dropTo
//
//  Shows one item at a time (photo OR video), full-size, keeping its
//  real portrait/landscape shape. Swiping left/right ALWAYS just
//  browses between items — identical feel everywhere (same as "All
//  Items"), no accidental deletes from a swipe.
//
//  Three top-level modes, differing only in what other actions are on
//  offer:
//   - .album: hold (long-press) a photo to reveal a "Delete" button,
//     then drag down onto it to confirm — like physically dragging the
//     item into a trash slot. Letting go anywhere else cancels safely.
//   - .recentlyDeleted: explicit Recover / Delete Forever buttons at
//     the bottom (these items are already on their way out).
//   - .browseOnly: just browsing, no destructive actions at all. Used
//     by "All Items".
//
//  Every photo can also be pinched to zoom in/out, and double-tapped to
//  reset back to fit-to-screen.
//

import SwiftUI
import Photos
import AVKit
import UIKit

/// What this screen is being shown for — changes which actions make sense.
enum PhotoDetailMode {
    case album(AlbumModel)   // hold-and-drag-to-delete is available
    case recentlyDeleted     // browsing the trash: recover or delete forever
    case browseOnly          // plain browsing, no destructive actions at all
}

struct PhotoDetailView: View {
    let mode: PhotoDetailMode
    @EnvironmentObject private var albumStore: AlbumStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var assets: [PHAsset]
    @State private var currentIndex: Int
    @State private var showUndoToast = false
    @State private var lastDeletedAsset: PHAsset?
    @State private var lastDeletedIndex: Int?
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var showMoveSheet = false

    init(assets: [PHAsset], startingAt startAsset: PHAsset, mode: PhotoDetailMode) {
        _assets = State(initialValue: assets)
        self.mode = mode
        _currentIndex = State(initialValue: assets.firstIndex(where: { $0.localIdentifier == startAsset.localIdentifier }) ?? 0)
    }

    private var currentAsset: PHAsset? {
        guard assets.indices.contains(currentIndex) else { return nil }
        return assets[currentIndex]
    }

    private var isAlbumMode: Bool {
        if case .album = mode { return true }
        return false
    }

    /// True only for Recently Deleted — controls the Recover / Delete
    /// Forever bar at the bottom.
    private var showsRecentlyDeletedActions: Bool {
        if case .recentlyDeleted = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header(for: currentAsset)

                if currentAsset == nil {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    // One consistent browsing mechanism everywhere — the
                    // exact same TabView used by "All Items", so paging
                    // feels identical no matter which screen you're in.
                    // (Hold-to-delete is paused for now while we make sure
                    // plain swiping is 100% smooth first.)
                    TabView(selection: $currentIndex) {
                        ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                            MediaPageView(asset: asset)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    if isAlbumMode {
                        Text("Swipe to browse  •  use \"•••\" to delete")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 10)
                    }
                }
            }

            if isAlbumMode, currentAsset != nil {
                albumActionBar
            }

            if showsRecentlyDeletedActions, currentAsset != nil {
                recentlyDeletedActionBar
            }

            if showUndoToast {
                undoToast
            }
        }
        .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .tabBar)
                .sheet(isPresented: $showMoveSheet) {
                    if let asset = currentAsset {
                        MoveToAlbumSheet(
                            sourceAlbum: {
                                if case .album(let album) = mode { return album }
                                return nil
                            }(),
                            identifiersToMove: [asset.localIdentifier],
                            onMoved: { advanceOrDismiss() }
                        )
                    }
                }
    }

    // MARK: - Header

    /// Shown at all times — including the "All caught up" empty state —
    /// so there's always a way back.
    private func header(for asset: PHAsset?) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
            }

            Spacer()

            if let asset {
                VStack(spacing: 2) {
                    Text(fileName(for: asset))
                        .font(.subheadline.weight(.semibold))
                    Text(dateString(for: asset))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
            }

            Spacer()

            
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("All caught up")
                .foregroundStyle(.white)
        }
    }

    // MARK: - Actions (album mode)

    private func performDelete(_ asset: PHAsset) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        let sourceAlbum: AlbumModel? = {
            if case .album(let album) = mode { return album }
            return nil
        }()
        albumStore.softDelete(asset.localIdentifier, sourceAlbum: sourceAlbum)

        lastDeletedAsset = asset
        lastDeletedIndex = currentIndex
        assets.remove(at: currentIndex)

        withAnimation { showUndoToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showUndoToast = false }
        }
    }

        private func advanceOrDismiss() {
            guard assets.indices.contains(currentIndex) else { return }
            assets.remove(at: currentIndex)
        }

    private var undoToast: some View {
        VStack {
            Spacer()
            Button {
                if let asset = lastDeletedAsset, case .album(let album) = mode {
                albumStore.undoDelete(asset.localIdentifier, restoringTo: album)
                let insertIndex = min(lastDeletedIndex ?? assets.count, assets.count)
                assets.insert(asset, at: insertIndex)
                currentIndex = insertIndex
            }
            withAnimation { showUndoToast = false }
            } label: {
                Label("Undo Delete", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var albumActionBar: some View {
            VStack {
                Spacer()
                HStack {
                    actionButton(
                        systemImage: isFavorite(currentAsset!) ? "heart.fill" : "heart",
                        label: "Favorite",
                        tint: isFavorite(currentAsset!) ? .red : .white
                    ) {
                        toggleFavorite(currentAsset!)
                    }
                    Spacer()
                    actionButton(systemImage: "folder", label: "Move", tint: .white) {
                        showMoveSheet = true
                    }
                    Spacer()
                    actionButton(systemImage: "trash", label: "Delete", tint: .red) {
                        performDelete(currentAsset!)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            }
            .ignoresSafeArea(edges: .bottom)
        }

        private func actionButton(systemImage: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage).font(.system(size: 20))
                    Text(label).font(.caption2)
                }
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
            }
        }

        private func isFavorite(_ asset: PHAsset) -> Bool {
            favoriteOverrides[asset.localIdentifier] ?? asset.isFavorite
        }

        private func toggleFavorite(_ asset: PHAsset) {
            let newValue = !isFavorite(asset)
            favoriteOverrides[asset.localIdentifier] = newValue
            Task { await PhotoLibraryManager.shared.toggleFavorite(for: asset) }
        }
    // MARK: - Actions (Recently Deleted mode)

    private var recentlyDeletedActionBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Button {
                    performRecover()
                } label: {
                    Label("Recover", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .tint(.blue)

                Button(role: .destructive) {
                    performDeleteForever()
                } label: {
                    Label("Delete Forever", systemImage: "trash.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .tint(.red)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private func performRecover() {
        guard let asset = currentAsset else { return }
        albumStore.restoreFromDeleted(asset.localIdentifier)
        advanceOrDismiss()
    }

    private func performDeleteForever() {
        guard let asset = currentAsset else { return }
        Task {
            await PhotoLibraryManager.shared.permanentlyDelete(identifiers: [asset.localIdentifier])
            albumStore.removeFromDeletedList(asset.localIdentifier)
            advanceOrDismiss()
        }
    }

    // MARK: - Helpers

    private func fileName(for asset: PHAsset) -> String {
        PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "Item"
    }

    private func dateString(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy"
        return formatter.string(from: date)
    }
}

/// One page inside the swipe pager — used by every mode. Loads its own
/// image/video, supports pinch-to-zoom (double-tap resets), and — only
/// when `enableHoldToDelete` is true — a "hold, then drag down onto the
/// Delete button" gesture:
///   1. Long-press the photo → a Delete button fades in at the bottom,
///      and the photo lifts slightly (scales down a touch) to show it's
///      "picked up".
///   2. Keep holding and drag down → the photo follows your finger. Once
///      you drag far enough that you'd be dropping it onto the button,
///      the button lights up red.
///   3. Let go while the button is lit → it's deleted. Let go anywhere
///      else → everything springs back, nothing happens.
private struct MediaPageView: View {
    let asset: PHAsset
    var enableHoldToDelete: Bool = false
    var onConfirmDelete: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoomScale: CGFloat = 1

    @State private var isHolding = false
    @State private var holdDragOffset: CGSize = .zero
    @State private var isHoveringDeleteZone = false

    /// How far down (in points) the photo needs to be dragged, once
    /// picked up, before it counts as "dropped on the Delete button".
    private let deleteZoneThreshold: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            ZStack {
                mediaContent(in: geo)
                    .offset(holdDragOffset)
                    .scaleEffect(isHolding ? 0.92 : zoomScale)
                    .simultaneousGesture(magnificationGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) { zoomScale = 1 }
                    }
                    .gesture(enableHoldToDelete ? holdToDeleteGesture : nil)

                if enableHoldToDelete {
                    VStack {
                        Spacer()
                        deleteButton
                            .padding(.bottom, 40)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: asset.localIdentifier) {
            zoomScale = 1
            if asset.mediaType == .video {
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                let item = await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
                    PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                        continuation.resume(returning: item)
                    }
                }
                if let item {
                    player = AVPlayer(playerItem: item)
                }
            } else {
                image = await PhotoLibraryManager.shared.loadFullImage(for: asset)
            }
        }
    }

    @ViewBuilder
    private func mediaContent(in geo: GeometryProxy) -> some View {
        if asset.mediaType == .video {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else {
                ProgressView().tint(.white)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
        } else {
            ProgressView().tint(.white)
        }
    }

    private var deleteButton: some View {
        Label("Delete", systemImage: "trash.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                isHoveringDeleteZone ? Color.red : Color.red.opacity(0.25),
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white.opacity(isHoveringDeleteZone ? 0.7 : 0.35), lineWidth: 1.5))
            .foregroundStyle(.white)
            .scaleEffect(isHoveringDeleteZone ? 1.15 : 1)
            .opacity(isHolding ? 1 : 0)
            .offset(y: isHolding ? 0 : 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHolding)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHoveringDeleteZone)
    }

    /// Long-press to "pick up" the photo, then drag down onto the
    /// Delete button to confirm.
    private var holdToDeleteGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    withAnimation(.spring()) { isHolding = true }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                case .second(true, let drag):
                    guard let drag else { return }
                    holdDragOffset = drag.translation
                    let hovering = drag.translation.height > deleteZoneThreshold
                    if hovering != isHoveringDeleteZone {
                        isHoveringDeleteZone = hovering
                        if hovering {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    }

                default:
                    break
                }
            }
            .onEnded { value in
                let shouldDelete: Bool
                if case .second(true, let drag) = value, let drag {
                    shouldDelete = drag.translation.height > deleteZoneThreshold
                } else {
                    shouldDelete = false
                }

                withAnimation(.spring()) {
                    isHolding = false
                    holdDragOffset = .zero
                    isHoveringDeleteZone = false
                }

                if shouldDelete {
                    onConfirmDelete?()
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !isHolding, asset.mediaType != .video else { return }
                zoomScale = min(max(value, 1), 4)
            }
            .onEnded { _ in
                if zoomScale < 1.05 {
                    withAnimation(.spring()) { zoomScale = 1 }
                }
            }
    }
}
