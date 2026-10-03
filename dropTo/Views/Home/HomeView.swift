import SwiftUI
import Photos
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var dataService: DataService
    @StateObject private var libraryManager = PhotoLibraryService.shared

    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator

    @State private var albums: [Album] = []
    @State private var deletedItems: [DeletedItem] = []
    @State private var showNewAlbumSheet = false
    @State private var selectedAlbum: Album?
    @State private var showFavorites = false
    @State private var showRecentlyDeleted = false

    @State private var isSelecting = false
    @State private var selectedAlbumIDs: Set<UUID> = []

    @State private var draggingAlbumID: UUID?
    @State private var albumToRename: Album?
    @State private var renameText = ""

    @AppStorage("dropTo.colorScheme") private var colorSchemePreference: String = "auto"
    @Environment(\.colorScheme) private var systemColorScheme

    init(showNewAlbumOnAppear: Bool = false) {
        _showNewAlbumSheet = State(initialValue: showNewAlbumOnAppear)
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var mostRecentlyDeletedAsset: PHAsset? {
        guard let identifier = deletedItems.first?.assetIdentifier else { return nil }
        return PhotoLibraryService.shared.fetchAssets(withIdentifiers: [identifier]).first
    }

    @State private var favoriteAssets: [PHAsset] = []

    private var favoriteCoverAsset: PHAsset? { favoriteAssets.first }
    private var favoriteCount: Int { favoriteAssets.count }

    var body: some View {
        NavigationStack {
            contentView
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("dropTo")
                .font(.largeTitle.bold())

            Spacer(minLength: 8)

            Button {
                toggleColorScheme()
            } label: {
                Image(systemName: colorSchemeIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)

            Button(isSelecting ? "Cancel" : "Select") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelecting.toggle()
                    selectedAlbumIDs.removeAll()
                }
            }
            .font(.headline)
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(albums.isEmpty && !isSelecting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 24) {
                    NewAlbumBanner()
                        .onTapGesture {
                            if isSelecting {
                                isSelecting = false
                                selectedAlbumIDs.removeAll()
                            } else {
                                showNewAlbumSheet = true
                            }
                        }

                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(albums) { album in
                            albumCell(for: album)
                        }

                        SystemTileView(
                            title: "Favorites",
                            subtitle: "\(favoriteCount) items",
                            systemImage: "heart.fill",
                            tint: .red,
                            coverAsset: favoriteCoverAsset,
                            badge: .heart
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isSelecting {
                                showRecentlyDeleted = false
                                showFavorites = true
                            }
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
                                showFavorites = false
                                showRecentlyDeleted = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaBar(edge: .bottom) {
                if isSelecting {
                    SelectionActionBar(
                        selectedCount: selectedAlbumIDs.count,
                        itemName: "Album",
                        deleteMessage: "Everything inside will move to Recently Deleted. This won't remove the photos from your device.",
                        onDelete: deleteSelectedAlbums
                    )
                }
            }
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
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
                NewAlbumSheet(dataService: dataService) { newAlbum in
                    loadData()
                    selectedAlbum = newAlbum
                }
            }
            .navigationDestination(item: $selectedAlbum) { album in
                AlbumDetailView(album: album)
                    .id(album.id)
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
            .onChange(of: libraryManager.libraryVersion) { _, _ in
                loadFavorites()
            }
            .onChange(of: libraryManager.authorizationStatus) { _, _ in
                loadFavorites()
            }
            .onChange(of: deepLinkCoordinator.albumToOpen) { _, _ in
                handleDeepLink()
            }
    }

    private func handleDeepLink() {
        guard let albumID = deepLinkCoordinator.albumToOpen else { return }
        loadData()

        if let album = albums.first(where: { $0.id == albumID }) {
            print("📱 Deep link: Opening album \(album.title)")
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showFavorites = false
                showRecentlyDeleted = false
                isSelecting = false
                selectedAlbum = album
            }
        } else {
            print("⚠️ Deep link: Album not found with ID \(albumID)")
        }

        deepLinkCoordinator.albumToOpen = nil
    }

    private func loadData() {
        albums = dataService.fetchAlbums()
        deletedItems = dataService.fetchDeletedItems()
        loadFavorites()
    }

    private func loadFavorites() {
        guard libraryManager.isAuthorized else {
            favoriteAssets = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "isFavorite == YES")
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        favoriteAssets = assets
    }

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

    private func deleteSelectedAlbums() {
        for album in albums where selectedAlbumIDs.contains(album.id) {
            dataService.deleteAlbum(album)
        }
        selectedAlbumIDs.removeAll()
        isSelecting = false
        loadData()
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
            isSelected: selectedAlbumIDs.contains(album.id),
            onTap: {
                if isSelecting {
                    toggle(album.id)
                } else {
                    selectedAlbum = album
                }
            },
            onTogglePin: {
                dataService.togglePinAlbum(album)
                loadData()
            },
            onRename: {
                albumToRename = album
                renameText = album.title
            },
            onDelete: {
                dataService.deleteAlbum(album)
            }
        )
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

private struct NewAlbumBanner: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .glassEffect(.regular.tint(.blue).interactive(), in: Circle())

            Text("New Album")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .glassEffect(.regular.tint(.blue.opacity(0.08)), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct SystemTileView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let coverAsset: PHAsset?
    var badge: Badge? = nil

    enum Badge { case heart }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let coverAsset {
                    AssetThumbnailView(asset: coverAsset, cornerRadius: 24)
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .aspectRatio(1, contentMode: .fit)
                    Image(systemName: systemImage)
                        .font(.system(size: 32))
                        .foregroundStyle(tint)
                }

                if badge == .heart {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular, in: Circle())
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AlbumGridCell: View {
    let album: Album
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var coverAsset: PHAsset?

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onTogglePin) {
            Label(album.isPinned ? "Unpin" : "Pin", systemImage: album.isPinned ? "pin.slash" : "pin")
        }
        Button(action: onRename) {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .contextMenu { menuItems }
                .task(id: album.assetIdentifiers) {
                    coverAsset = PhotoLibraryService.shared
                        .fetchAssets(withIdentifiers: album.assetIdentifiers)
                        .first
                }

            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(album.assetIdentifiers.count) items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

                Spacer(minLength: 4)

                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .disabled(isSelecting)
            }
        }
    }

    private var cover: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let coverAsset {
                    AssetThumbnailView(asset: coverAsset)
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .aspectRatio(1, contentMode: .fit)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .selectionOverlay(isSelecting: isSelecting, isSelected: isSelected)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if album.isPinned && !isSelecting {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.tint(.blue.opacity(0.7)), in: Circle())
                    .padding(10)
            }
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
