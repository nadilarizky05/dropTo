import SwiftUI

struct MoveToAlbumSheet: View {
    let sourceAlbum: Album?
    let identifiersToMove: [String]
    let dataService: DataService
    var onMoved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNewAlbumSheet = false

    private var destinationAlbums: [Album] {
        dataService.fetchAlbums().filter { $0.id != sourceAlbum?.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if destinationAlbums.isEmpty {
                    ContentUnavailableView(
                        "No Other Albums",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Create an album to move photos into.")
                    )
                } else {
                    List(destinationAlbums) { album in
                        Button {
                            dataService.moveAssets(identifiersToMove, from: sourceAlbum, to: album)
                            onMoved()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                createAlbumButton
            }
            .sheet(isPresented: $showNewAlbumSheet) {
                NewAlbumSheet(dataService: dataService) { newAlbum in
                    dataService.moveAssets(identifiersToMove, from: sourceAlbum, to: newAlbum)
                    onMoved()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private var createAlbumButton: some View {
        Button {
            showNewAlbumSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Create New Album")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}
