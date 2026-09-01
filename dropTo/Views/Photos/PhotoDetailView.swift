//
//  PhotoDetailView.swift
//  dropTo
//

import SwiftUI
import Photos
import AVKit
import UIKit

struct PhotoDetailView: View {
    let mode: PhotoDetailMode
    @EnvironmentObject private var dataService: DataService
    @Environment(\.dismiss) private var dismiss
    
    @State private var assets: [PHAsset]
    @State private var currentIndex: Int
    @State private var showUndoToast = false
    @State private var lastDeletedAsset: PHAsset?
    @State private var lastDeletedIndex: Int?
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var showMoveSheet = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isLoadingShare = false

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
    
    private var isBrowseMode: Bool {
        if case .browseOnly = mode { return true }
        return false
    }
    
    private var showsActionBar: Bool {
        isAlbumMode || isBrowseMode
    }

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
                    TabView(selection: $currentIndex) {
                        ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                            MediaPageView(asset: asset, isActive: index == currentIndex)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    if showsActionBar {
                        Text("Swipe to browse  •  use \"•••\" to delete")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 10)
                    }
                }
            }

            if showsActionBar, currentAsset != nil {
                albumActionBar
            }

            if showUndoToast {
                undoToast
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if showsRecentlyDeletedActions, currentAsset != nil {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        performRecover()
                    } label: {
                        Label("Recover", systemImage: "arrow.uturn.backward")
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        performDeleteForever()
                    } label: {
                        Label("Delete Forever", systemImage: "trash.fill")
                    }
                }
            }
        }
        .toolbarBackground(showsRecentlyDeletedActions ? .visible : .hidden, for: .bottomBar)
        .sheet(isPresented: $showMoveSheet) {
            if let asset = currentAsset {
                MoveToAlbumSheet(
                    sourceAlbum: {
                        if case .album(let album) = mode { return album }
                        return nil
                    }(),
                    identifiersToMove: [asset.localIdentifier],
                    dataService: dataService,
                    onMoved: { advanceOrDismiss() }
                )
            }
        }
        .sheet(isPresented: $showShareSheet) {
            shareItems = []
        } content: {
            if !shareItems.isEmpty {
                ActivityViewController(items: shareItems)
            }
        }
    }

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

            if asset != nil {
                Button {
                    performShare()
                } label: {
                    if isLoadingShare {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }
                .disabled(isLoadingShare)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
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

    private func performShare() {
        guard let asset = currentAsset else { return }
        isLoadingShare = true
        
        Task {
            do {
                if asset.mediaType == .video {
                    print("📹 Starting video share for asset: \(asset.localIdentifier)")
                    let options = PHVideoRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.version = .original
                    
                    let avAsset = await withCheckedContinuation { (continuation: CheckedContinuation<AVAsset?, Never>) in
                        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                            print("📹 Got AVAsset: \(avAsset != nil)")
                            continuation.resume(returning: avAsset)
                        }
                    }
                    
                    if let urlAsset = avAsset as? AVURLAsset {
                        print("📹 Video URL: \(urlAsset.url)")
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension("mov")
                        
                        try? FileManager.default.copyItem(at: urlAsset.url, to: tempURL)
                        
                        await MainActor.run {
                            print("📹 Setting shareItems with tempURL")
                            self.shareItems = [tempURL]
                            self.showShareSheet = true
                            self.isLoadingShare = false
                        }
                    } else {
                        print("❌ Failed to get URL asset")
                        await MainActor.run {
                            self.isLoadingShare = false
                        }
                    }
                } else {
                    print("📷 Starting photo share for asset: \(asset.localIdentifier)")
                    let options = PHImageRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.isSynchronous = false
                    options.version = .current
                    
                    let imageData = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                            print("📷 Got image data: \(data?.count ?? 0) bytes")
                            continuation.resume(returning: data)
                        }
                    }
                    
                    if let imageData = imageData, let image = UIImage(data: imageData) {
                        print("📷 Created UIImage: \(image.size)")
                        await MainActor.run {
                            print("📷 Setting shareItems with image")
                            self.shareItems = [image]
                            self.showShareSheet = true
                            self.isLoadingShare = false
                        }
                    } else {
                        print("❌ Failed to create image from data")
                        await MainActor.run {
                            self.isLoadingShare = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingShare = false
                }
                print("❌ Share error: \(error)")
            }
        }
    }

    private func performDelete(_ asset: PHAsset) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        let sourceAlbumID: UUID? = {
            if case .album(let album) = mode { return album.id }
            return nil
        }()
        dataService.softDelete(asset.localIdentifier, sourceAlbumID: sourceAlbumID)

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
                guard let asset = lastDeletedAsset else { return }
                
                if case .album(let album) = mode {
                    dataService.undoDelete(asset.localIdentifier, restoringTo: album)
                } else {
                    dataService.undoDelete(asset.localIdentifier, restoringTo: nil)
                }
                
                let insertIndex = min(lastDeletedIndex ?? assets.count, assets.count)
                assets.insert(asset, at: insertIndex)
                currentIndex = insertIndex
                
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
            Task { await PhotoLibraryService.shared.toggleFavorite(for: asset) }
        }
    
    private func performRecover() {
        guard let asset = currentAsset else { return }
        dataService.restoreFromDeleted(asset.localIdentifier)
        advanceOrDismiss()
    }

    private func performDeleteForever() {
        guard let asset = currentAsset else { return }
        Task {
            await PhotoLibraryService.shared.permanentlyDelete(identifiers: [asset.localIdentifier])
            dataService.removeFromDeletedList(asset.localIdentifier)
            advanceOrDismiss()
        }
    }

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

private struct MediaPageView: View {
    let asset: PHAsset
    var isActive: Bool = true
    var enableHoldToDelete: Bool = false
    var onConfirmDelete: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoomScale: CGFloat = 1
    @State private var baselineZoomScale: CGFloat = 1
    @State private var zoomAnchor: UnitPoint = .center
    @State private var panOffset: CGSize = .zero
    @State private var baselinePanOffset: CGSize = .zero

    @State private var isHolding = false
    @State private var holdDragOffset: CGSize = .zero
    @State private var isHoveringDeleteZone = false
    private let deleteZoneThreshold: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if asset.mediaType == .video {
                    mediaContent(in: geo)
                } else {
                    mediaContent(in: geo)
                        .offset(x: holdDragOffset.width + panOffset.width, 
                               y: holdDragOffset.height + panOffset.height)
                        .scaleEffect(isHolding ? 0.92 : zoomScale, anchor: isHolding ? .center : zoomAnchor)
                        .simultaneousGesture(magnificationGesture)
                        .gesture(zoomScale > 1 ? panGesture : nil, including: zoomScale > 1 ? .all : .none)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                zoomScale = 1
                                baselineZoomScale = 1
                                zoomAnchor = .center
                                panOffset = .zero
                                baselinePanOffset = .zero
                            }
                        }
                        .gesture(enableHoldToDelete ? holdToDeleteGesture : nil)
                }

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
            baselineZoomScale = 1
            zoomAnchor = .center
            panOffset = .zero
            baselinePanOffset = .zero
            if asset.mediaType == .video {
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                let item = await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
                    PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                        continuation.resume(returning: item)
                    }
                }
                if let item {
                    let newPlayer = AVPlayer(playerItem: item)
                    player = newPlayer
                    if isActive { newPlayer.play() }
                }
            } else {
                image = await PhotoLibraryService.shared.loadFullImage(for: asset)
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                player?.play()
            } else {
                player?.pause()
            }
        }
    }

    @ViewBuilder
    private func mediaContent(in geo: GeometryProxy) -> some View {
        if asset.mediaType == .video {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { if isActive { player.play() } }
                    .onDisappear { player.pause() }
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
        MagnifyGesture()
            .onChanged { value in
                guard !isHolding, asset.mediaType != .video else { return }
                zoomAnchor = value.startAnchor
                zoomScale = min(max(baselineZoomScale * value.magnification, 1), 4)
            }
            .onEnded { _ in
                baselineZoomScale = zoomScale
                if zoomScale < 1.05 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        zoomScale = 1
                        baselineZoomScale = 1
                        zoomAnchor = .center
                        panOffset = .zero
                        baselinePanOffset = .zero
                    }
                }
            }
    }
    
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let newOffsetWidth = baselinePanOffset.width + value.translation.width
                let newOffsetHeight = baselinePanOffset.height + value.translation.height
                
                let maxOffset = 200 * zoomScale
                let clampedWidth = min(max(newOffsetWidth, -maxOffset), maxOffset)
                let clampedHeight = min(max(newOffsetHeight, -maxOffset), maxOffset)
                
                panOffset = CGSize(width: clampedWidth, height: clampedHeight)
            }
            .onEnded { _ in
                baselinePanOffset = panOffset
            }
    }
}

