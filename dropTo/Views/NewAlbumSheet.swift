//
//  NewAlbumSheet.swift
//  dropTo
//
//  Matches the mockup's "New Album" popup: a title field, an optional
//  tag, and Cancel/Create buttons.
//

import SwiftUI

struct NewAlbumSheet: View {
    @EnvironmentObject private var albumStore: AlbumStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Album Title", text: $title)
                        .focused($titleFocused)
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        albumStore.createAlbum(title: title.isEmpty ? "Untitled Album" : title, tag: nil)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.height(200)])
    }
}

#Preview {
    NewAlbumSheet()
        .environmentObject(AlbumStore())
}
