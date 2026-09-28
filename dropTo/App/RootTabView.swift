import SwiftUI

struct RootTabView: View {
    
    @EnvironmentObject private var dataService: DataService
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator
    
    var body: some View {
        @Bindable var coordinator = deepLinkCoordinator
        
        TabView(selection: $coordinator.selectedTab) {
            HomeView()
                .tabItem {
                    Label("All Albums", systemImage: "square.grid.2x2.fill")
                }
                .tag(RootTab.albums)
            
            AllItemsView()
                .tabItem {
                    Label("Similiar Photos", systemImage: "photo.on.rectangle.angled")
                }
                .tag(RootTab.similarPhotos)
        }
        // KAMERA DARI WIDGET: MUNCUL LANGSUNG.
        // SETELAH DITUTUP (onDismiss) → BARU MASUK KE ALBUM-NYA
        .fullScreenCover(
            item: $coordinator.cameraTarget,
            onDismiss: { deepLinkCoordinator.cameraDidClose() }
        ) { target in
            CameraPicker { media in
                Task {
                    await dataService.saveCapturedMedia(media, toAlbumWithID: target.albumID)
                }
            }
            .ignoresSafeArea()
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(DataService())
        .environment(DeepLinkCoordinator())
}
