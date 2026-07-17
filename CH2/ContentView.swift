//
//  ContentView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 24/04/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var albumStore: AlbumStore
    @State var showAddAlbum = false
    @State var newAlbumName = ""

    var body: some View {
        NavigationStack {
            AlbumView()
                .navigationTitle("dropTo")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            if !albumStore.undoStack.isEmpty {
                                Button { albumStore.undo() } label: {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                }
                            }
                            Button {
                                newAlbumName = ""
                                showAddAlbum = true
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
                .toolbarTitleDisplayMode(.inlineLarge)
                .alert("New Album", isPresented: $showAddAlbum) {
                    TextField("Album Name", text: $newAlbumName)
                    Button("Create") {
                        if !newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty {
                            albumStore.addAlbum(name: newAlbumName)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Enter a name for this album")
                }
        }
        
        }
}

#Preview {
    ContentView()
        .environmentObject(AlbumStore())
        .environmentObject(PhotoLibraryManager())
}
