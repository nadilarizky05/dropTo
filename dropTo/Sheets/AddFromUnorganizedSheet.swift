import SwiftUI
import Photos

struct AddFromUnorganizedSheet: View {
    let album: Album
    let dataService: DataService
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var selectedIdentifiers: Set<String> = []

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    ContentUnavailableView(
                        "Nothing Unorganized",
                        systemImage: "checkmark.circle",
                        description: Text("All your photos and videos are already in an album.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                AssetThumbnailView(asset: asset)
                                    .selectionOverlay(isSelecting: true, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
                                    .dragToSelect(
                                        isSelecting: .constant(true),
                                        selectedIdentifiers: $selectedIdentifiers,
                                        identifier: asset.localIdentifier
                                    )
                            }
                        }
                        .gridDragSelection(isSelecting: true, selected: $selectedIdentifiers)
                    }
                }
            }
            .navigationTitle("Add from Unorganized")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedIdentifiers.count))") {
                        addSelected()
                    }
                    .disabled(selectedIdentifiers.isEmpty)
                }
            }
            .onAppear { loadAssets() }
        }
    }

    private func loadAssets() {
        let albums = dataService.fetchAlbums()
        let deletedIdentifiers = Set(dataService.fetchDeletedItems().map(\.assetIdentifier))
        let organizedIdentifiers = Set(albums.flatMap(\.assetIdentifiers))
        assets = PhotoLibraryService.shared
            .fetchAllAssets()
            .filter { !organizedIdentifiers.contains($0.localIdentifier) && !deletedIdentifiers.contains($0.localIdentifier) }
    }

    private func addSelected() {
        dataService.addAssets(Array(selectedIdentifiers), to: album)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAdded()
        dismiss()
    }
}
