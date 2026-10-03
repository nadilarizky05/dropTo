import SwiftUI

struct RootTabView: View {
    let showNewAlbumOnAppear: Bool

    @EnvironmentObject private var dataService: DataService
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator

    init(showNewAlbumOnAppear: Bool = false) {
        self.showNewAlbumOnAppear = showNewAlbumOnAppear
    }

    var body: some View {
        @Bindable var coordinator = deepLinkCoordinator

        TabView(selection: $coordinator.selectedTab) {
            HomeView(showNewAlbumOnAppear: showNewAlbumOnAppear)
                .tabItem {
                    Label("All Albums", systemImage: "square.grid.2x2.fill")
                }
                .tag(RootTab.albums)

            UnorganizedItemsView()
                .tabItem {
                    Label("Unorganized", systemImage: "photo.on.rectangle.angled")
                }
                .tag(RootTab.unorganized)
        }
        .onChange(of: coordinator.cameraTarget) { _, target in
            guard let target,
                  let album = dataService.fetchAlbums().first(where: { $0.id == target.albumID }) else { return }
            PhotoLibraryService.shared.prefetchThumbnails(identifiers: album.assetIdentifiers)
        }
        .fullScreenCover(
            item: $coordinator.cameraTarget,
            onDismiss: { deepLinkCoordinator.cameraDidClose() }
        ) { target in
            CameraPicker(dataService: dataService, initialAlbumID: target.albumID) { newAlbumID in
                deepLinkCoordinator.albumAfterCamera = newAlbumID
            }
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(DataService())
        .environment(DeepLinkCoordinator())
}
