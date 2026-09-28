//
//  HomeView.swift
//  dropTo
//

import SwiftUI
import Photos
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var dataService: DataService
    @StateObject private var libraryManager = PhotoLibraryService.shared
    
    // DEEP LINK COORDINATOR (DARI WIDGET)
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator

    @State private var albums: [Album] = []
    @State private var deletedItems: [DeletedItem] = []
    @State private var showNewAlbumSheet = false
    @State private var selectedAlbum: Album?
    @State private var showUnorganizedItems = false
    @State private var showFavorites = false
    @State private var showRecentlyDeleted = false

    @State private var isSelecting = false
    @State private var selectedAlbumIDs: Set<UUID> = []
    @State private var showDeleteConfirmation = false

    @State private var draggingAlbumID: UUID?
    @State private var albumToRename: Album?
    @State private var renameText = ""
    
    @AppStorage("dropTo.colorScheme") private var colorSchemePreference: String = "auto"
    @Environment(\.colorScheme) private var systemColorScheme

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    private var mostRecentlyDeletedAsset: PHAsset? {
        guard let identifier = deletedItems.first?.assetIdentifier else { return nil }
        return PhotoLibraryService.shared.fetchAssets(withIdentifiers: [identifier]).first
    }

    private var unorganizedAssets: [PHAsset] {
        guard libraryManager.isAuthorized else { return [] }
        let deletedIdentifiers = Set(deletedItems.map(\.assetIdentifier))
        let organizedIdentifiers = Set(albums.flatMap(\.assetIdentifiers))
        return PhotoLibraryService.shared
            .fetchAllAssets()
            .filter { !deletedIdentifiers.contains($0.localIdentifier) && !organizedIdentifiers.contains($0.localIdentifier) }
    }

    private var unorganizedCoverAsset: PHAsset? { unorganizedAssets.first }
    private var unorganizedCount: Int { unorganizedAssets.count }
    
    private var favoriteAssets: [PHAsset] {
        guard libraryManager.isAuthorized else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "isFavorite == YES")
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
    
    private var favoriteCoverAsset: PHAsset? { favoriteAssets.first }
    private var favoriteCount: Int { favoriteAssets.count }

    var body: some View {
        NavigationStack {
            contentView
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                NewAlbumTile()
                    .onTapGesture {
                        if isSelecting {
                            isSelecting = false
                            selectedAlbumIDs.removeAll()
                        } else {
                            showNewAlbumSheet = true
                        }
                    }
                
                SystemTileView(
                    title: "Unorganized Items",
                    subtitle: "\(unorganizedCount) items",
                    systemImage: "tray.full.fill",
                    tint: .blue,
                    coverAsset: unorganizedCoverAsset
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isSelecting {
                        print("🔵 Opening Unorganized Items")
                        showFavorites = false // Reset favorites state
                        showRecentlyDeleted = false // Reset deleted state
                        showUnorganizedItems = true
                    }
                }
                
                SystemTileView(
                    title: "Favorites",
                    subtitle: "\(favoriteCount) items",
                    systemImage: "heart.fill",
                    tint: .red,
                    coverAsset: favoriteCoverAsset
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isSelecting {
                        print("❤️ Opening Favorites")
                        showUnorganizedItems = false // Reset unorganized state
                        showRecentlyDeleted = false // Reset deleted state
                        showFavorites = true
                    }
                }

                ForEach(albums) { album in
                    albumCell(for: album)
                }

                SystemTileView(
                    title: "Recently Deleted",
                    subtitle: "\(deletedItems.count) items",
                    systemImage: "trash",
                    tint: .gray,
                    coverAsset: mostRecentlyDeletedAsset
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isSelecting {
                        print("🗑️ Opening Recently Deleted")
                        showUnorganizedItems = false // Reset unorganized state
                        showFavorites = false // Reset favorites state
                        showRecentlyDeleted = true
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
            .navigationTitle("dropTo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        toggleColorScheme()
                    } label: {
                        Image(systemName: colorSchemeIcon)
                            .font(.system(size: 18))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Cancel" : "Select") {
                        isSelecting.toggle()
                        selectedAlbumIDs.removeAll()
                    }
                    .disabled(albums.isEmpty && !isSelecting)
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
                    for album in albums where selectedAlbumIDs.contains(album.id) {
                        dataService.deleteAlbum(album)
                    }
                    selectedAlbumIDs.removeAll()
                    isSelecting = false
                    loadData()
                }
            } message: {
                Text("Everything inside will move to Recently Deleted. This won't remove the photos from your device.")
            }
            .alert(
                "Rename Album",
                isPresented: Binding<Bool>(
                    get: { albumToRename != nil },
                    set: { if !$0 { albumToRename = nil } }
                )
            ) {
                TextField("Album Title", text: $renameText)
                Button("Cancel", role: .cancel) { albumToRename = nil }
                Button("Save") {
                    if let album = albumToRename {
                        dataService.renameAlbum(album, to: renameText)
                    }
                    albumToRename = nil
                }
            }
            .sheet(isPresented: $showNewAlbumSheet) {
                NewAlbumSheet(dataService: dataService) { _ in
                    loadData()
                }
            }
            .navigationDestination(item: $selectedAlbum) { album in
                AlbumDetailView(album: album)
                    .id(album.id) // ALBUM BEDA = VIEW BARU (STATE NGGAK KEBAWA DARI ALBUM LAIN)
            }
            .navigationDestination(isPresented: $showUnorganizedItems) {
                UnorganizedItemsView()
            }
            .navigationDestination(isPresented: $showFavorites) {
                FavoritesView()
            }
            .navigationDestination(isPresented: $showRecentlyDeleted) {
                RecentlyDeletedView()
            }
            .task {
                libraryManager.requestAccessIfNeeded()
            }
            .onAppear {
                loadData()
                handleDeepLink()
            }
            .onReceive(dataService.$lastUpdate) { _ in
                loadData()
            }
            .onChange(of: deepLinkCoordinator.albumToOpen) { _, _ in
                handleDeepLink()
            }
    }
    
    //============================================================================
    // FUNCTION: HANDLE DEEP LINK
    //============================================================================
    // HANDLE NAVIGASI DARI WIDGET
    
    private func handleDeepLink() {
        guard let albumID = deepLinkCoordinator.albumToOpen else { return }
        loadData() // PASTIKAN LIST ALBUM TERBARU
        
        // CARI ALBUM BERDASARKAN ID
        if let album = albums.first(where: { $0.id == albumID }) {
            print("📱 Deep link: Opening album \(album.title)")
            // TUTUP HALAMAN LAIN, LALU PUSH ALBUM TANPA ANIMASI
            // (KAMERA UDAH NUTUP LAYAR, JADI USER NGGAK NGELIHAT PROSES INI)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showUnorganizedItems = false
                showFavorites = false
                showRecentlyDeleted = false
                isSelecting = false
                selectedAlbum = album
            }
        } else {
            print("⚠️ Deep link: Album not found with ID \(albumID)")
        }
        
        // SUDAH DI-HANDLE → CLEAR (KAMERA DI-HANDLE TERPISAH OLEH ROOTTABVIEW)
        deepLinkCoordinator.albumToOpen = nil
    }
    
    private func loadData() {
        albums = dataService.fetchAlbums()
        deletedItems = dataService.fetchDeletedItems()
    }
    
    //============================================================================
    // FUNCTION: TOGGLE COLOR SCHEME
    //============================================================================
    // TOGGLE ANTARA AUTO → DARK → LIGHT → DARK → LIGHT ...
    
    private func toggleColorScheme() {
        switch colorSchemePreference {
        case "auto":
            colorSchemePreference = "dark"
        case "dark":
            colorSchemePreference = "light"
        case "light":
            colorSchemePreference = "dark"
        default:
            colorSchemePreference = "dark"
        }
    }
    
    //============================================================================
    // COMPUTED PROPERTY: COLOR SCHEME ICON
    //============================================================================
    // ICON BUAT BUTTON (AUTO = CIRCLE, DARK = MOON, LIGHT = SUN)
    
    private var colorSchemeIcon: String {
        switch colorSchemePreference {
        case "auto":
            return "circle.lefthalf.filled"
        case "dark":
            return "moon.fill"
        case "light":
            return "sun.max.fill"
        default:
            return "circle.lefthalf.filled"
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
    
    @ViewBuilder
    private func albumCell(for album: Album) -> some View {
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
                dataService.togglePinAlbum(album)
                loadData()
            } label: {
                Label(
                    album.isPinned ? "Unpin" : "Pin",
                    systemImage: album.isPinned ? "pin.slash" : "pin"
                )
            }
            
            Divider()
            
            Button {
                albumToRename = album
                renameText = album.title
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                dataService.deleteAlbum(album)
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
                dataService: dataService,
                draggingAlbumID: $draggingAlbumID,
                albums: $albums
            )
        )
    }
}

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

            Text(" ")
                .font(.caption2)
        }
    }
}

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

private struct AlbumGridCell: View {
    let album: Album
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var coverAsset: PHAsset? {
        PhotoLibraryService.shared
            .fetchAssets(withIdentifiers: album.assetIdentifiers)
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
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
                
                // PIN INDICATOR
                if album.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.blue.gradient, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .padding(8)
                }
            }

            HStack(spacing: 4) {
                if album.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                }
                Text(album.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            
            Text("\(album.assetIdentifiers.count) items")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AlbumDropDelegate: DropDelegate {
    let targetAlbum: Album
    let dataService: DataService
    @Binding var draggingAlbumID: UUID?
    @Binding var albums: [Album]

    func performDrop(info: DropInfo) -> Bool {
        draggingAlbumID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingAlbumID,
              draggingID != targetAlbum.id,
              let fromIndex = albums.firstIndex(where: { $0.id == draggingID }),
              let toIndex = albums.firstIndex(where: { $0.id == targetAlbum.id })
        else { return }

        withAnimation {
            albums.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(DataService())
        .environment(DeepLinkCoordinator())
}

