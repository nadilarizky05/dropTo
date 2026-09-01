import SwiftUI

//============================================================================
// VIEW: ROOT TAB VIEW
//============================================================================
// TAB BAR UTAMA APP - 2 TAB: ALL ALBUMS DAN ALL ITEMS

struct RootTabView: View {
    
    //============================================================================
    // BODY
    //============================================================================
    
    var body: some View {
        TabView {
            // TAB 1: ALL ALBUMS (GRID ALBUM)
            HomeView()
                .tabItem {
                    Label("All Albums", systemImage: "square.grid.2x2.fill")
                }
            
            // TAB 2: ALL ITEMS (SEMUA FOTO/VIDEO)
            AllItemsView()
                .tabItem {
                    Label("All Items", systemImage: "photo.on.rectangle.angled")
                }
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(DataService())
}
