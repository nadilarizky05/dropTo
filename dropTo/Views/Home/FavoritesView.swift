import SwiftUI
import Photos

struct FavoritesView: View {
    @EnvironmentObject private var dataService: DataService
    @StateObject private var libraryService = PhotoLibraryService.shared
    @State private var favoriteAssets: [PHAsset] = []
    @State private var selectedAsset: PHAsset?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        Group {
            if favoriteAssets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(favoriteAssets, id: \.localIdentifier) { asset in
                            AssetThumbnailView(asset: asset, cornerRadius: 0)
                                .aspectRatio(1, contentMode: .fill)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAsset = asset
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedAsset) { asset in
            PhotoDetailView(
                assets: favoriteAssets,
                startingAt: asset,
                mode: .favorites
            )
        }
        .task {
            loadFavorites()
        }
        .onChange(of: libraryService.libraryVersion) { _, _ in
            loadFavorites()
        }
        .onReceive(dataService.$lastUpdate) { _ in
            loadFavorites()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Favorites Yet")
                    .font(.title2.weight(.semibold))

                Text("Tap the heart icon on any photo to add it to your favorites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadFavorites() {
        guard libraryService.isAuthorized else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "isFavorite == YES")

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        favoriteAssets = assets
    }
}

#Preview {
    NavigationStack {
        FavoritesView()
            .environmentObject(DataService())
    }
}
