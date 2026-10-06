import SwiftUI
import Photos

struct UnorganizedItemsView: View {
    @EnvironmentObject private var dataService: DataService

    @State private var selectedAsset: PHAsset?
    @State private var showSimilarPhotos = false
    @State private var isSelecting = false
    @State private var selectedIdentifiers: Set<String> = []
    @State private var showMoveSheet = false
    @State private var groupedAssets: [DayGroup] = []
    @State private var albums: [Album] = []
    @State private var deletedItems: [DeletedItem] = []

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var allAssets: [PHAsset] { groupedAssets.flatMap(\.assets) }

    private func loadAssets() {
        albums = dataService.fetchAlbums()
        deletedItems = dataService.fetchDeletedItems()

        let organized = Set(albums.flatMap(\.assetIdentifiers))
        let deleted = Set(deletedItems.map(\.assetIdentifier))

        groupedAssets = PhotoLibraryService.shared
            .fetchAllAssets()
            .filter { !organized.contains($0.localIdentifier) && !deleted.contains($0.localIdentifier) }
            .groupedByDay()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SimilarPhotosCard()
                        .padding(.horizontal)
                        .onTapGesture { showSimilarPhotos = true }

                    if allAssets.isEmpty {
                        ContentUnavailableView(
                            "All Organized!",
                            systemImage: "checkmark.circle",
                            description: Text("Every photo and video is filed into an album.")
                        )
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(groupedAssets, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sectionTitle(for: group.day))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(group.assets, id: \.localIdentifier) { asset in
                                        AssetThumbnailView(asset: asset)
                                            .selectionOverlay(isSelecting: isSelecting, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
                                            .dragToSelect(
                                                isSelecting: $isSelecting,
                                                selectedIdentifiers: $selectedIdentifiers,
                                                identifier: asset.localIdentifier
                                            )
                                            .onTapGesture {
                                                if !isSelecting { selectedAsset = asset }
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom)
                .gridDragSelection(isSelecting: isSelecting, selected: $selectedIdentifiers)
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
            .safeAreaBar(edge: .top) { header }
            .safeAreaBar(edge: .bottom) {
                if isSelecting {
                    SelectionActionBar(
                        selectedCount: selectedIdentifiers.count,
                        onMove: { showMoveSheet = true },
                        onDelete: deleteSelectedItems
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .sheet(isPresented: $showMoveSheet) {
                MoveToAlbumSheet(sourceAlbum: nil, identifiersToMove: Array(selectedIdentifiers), dataService: dataService) {
                    selectedIdentifiers.removeAll()
                    isSelecting = false
                    loadAssets()
                }
            }
            .navigationDestination(item: $selectedAsset) { asset in
                PhotoDetailView(assets: allAssets, startingAt: asset, mode: .browseOnly)
            }
            .navigationDestination(isPresented: $showSimilarPhotos) {
                AllItemsView()
            }
            .onAppear {
                loadAssets()
            }
            .onReceive(dataService.$lastUpdate) { _ in
                loadAssets()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(isSelecting ? selectionTitle : "Unorganized")
                .font(.largeTitle.bold())
                .contentTransition(.numericText())
                .animation(.snappy, value: selectedIdentifiers.count)

            Spacer(minLength: 8)

            Button(isSelecting ? "Cancel" : "Select") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
            }
            .font(.headline)
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(allAssets.isEmpty && !isSelecting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var selectionTitle: String {
        selectedIdentifiers.isEmpty
            ? "Select Items"
            : "\(selectedIdentifiers.count) Selected"
    }

    // MARK: - Helpers

    private func sectionTitle(for date: Date) -> String {
        DayTitleFormatter.string(for: date)
    }

    private func toggle(_ identifier: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedIdentifiers.contains(identifier) {
                selectedIdentifiers.remove(identifier)
            } else {
                selectedIdentifiers.insert(identifier)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func deleteSelectedItems() {
        dataService.softDelete(Array(selectedIdentifiers))

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        selectedIdentifiers.removeAll()
        isSelecting = false
        loadAssets()
    }
}

private struct SimilarPhotosCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGray5))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text("Similar Photos")
                    .font(.subheadline.weight(.semibold))
                Text("Tap to review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

#Preview {
    UnorganizedItemsView()
        .environmentObject(DataService())
}
