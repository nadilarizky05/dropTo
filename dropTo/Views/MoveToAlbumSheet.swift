//
//  MoveToAlbumSheet.swift
//  dropTo
//
//  A simple picker: "which album should these selected photos move to?"
//  Shown from an album's Select mode.
//

import SwiftUI

struct MoveToAlbumSheet: View {
    /// nil when moving items that aren't in any album yet (e.g. from
    /// "Unorganized Items") — there's nothing to remove them FROM.
    let sourceAlbum: AlbumModel?
    let identifiersToMove: [String]
    var onMoved: () -> Void

    @EnvironmentObject private var albumStore: AlbumStore
    @Environment(\.dismiss) private var dismiss

    /// Every album except the one we're currently moving photos out of
    /// (if any).
    private var destinationAlbums: [AlbumModel] {
        albumStore.albums.filter { $0.id != sourceAlbum?.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if destinationAlbums.isEmpty {
                    ContentUnavailableView(
                        "No Other Albums",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Create another album first, then you'll be able to move photos into it.")
                    )
                } else {
                    List(destinationAlbums) { album in
                        Button {
                            albumStore.moveAssets(identifiersToMove, from: sourceAlbum, to: album)
                            onMoved()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(album.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(album.assetIdentifiers.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    MoveToAlbumSheet(sourceAlbum: AlbumModel(title: "Coding"), identifiersToMove: [], onMoved: {})
        .environmentObject(AlbumStore())
}
