//
//  RootTabView.swift
//  dropTo
//
//  Created by Nadila Rizky Amelia on 20/07/26.
//

//
//  RootTabView.swift
//  dropTo
//
//  The very outer shell of the app: a tab bar with two tabs.
//  - "All Albums" is the album grid you already know (HomeView).
//  - "All Items" is every photo/video on the device, newest first,
//    for quickly browsing without worrying about albums at all.
//

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("All Albums", systemImage: "square.grid.2x2.fill")
                }

            AllItemsView()
                .tabItem {
                    Label("All Items", systemImage: "photo.on.rectangle.angled")
                }
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AlbumStore())
}
