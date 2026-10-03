import SwiftUI
import Photos

struct AllItemsView: View {
    @EnvironmentObject private var dataService: DataService
    @StateObject private var libraryManager = PhotoLibraryService.shared
    @StateObject private var similarityService = ImageSimilarityService.shared

    @State private var assets: [PHAsset] = []
    @State private var imageGroups: [ImageGroup] = []
    @State private var selectedAsset: PHAsset?
    @State private var deletedItems: [DeletedItem] = []
    @State private var expandedGroups: Set<UUID> = []
    @State private var didAnalyze = false

    @State private var isSelecting = false
    @State private var showMoveSheet = false
    @State private var selectedIdentifiers: Set<String> = []

    init() {
        let cached = ImageSimilarityService.shared.cachedGroups
        _imageGroups = State(initialValue: cached)
        _assets = State(initialValue: cached.flatMap(\.assets))
        _didAnalyze = State(initialValue: ImageSimilarityService.shared.hasResult)
        _expandedGroups = State(initialValue: Set(cached.map(\.id)))
    }

    var body: some View {
        Group {
            ScrollView {
                if assets.isEmpty {
                    ContentUnavailableView(
                        "No Items Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Photos and videos you take will show up here.")
                    )
                    .padding(.top, 80)
                } else if !similarityService.isAnalyzing && didAnalyze && imageGroups.isEmpty {
                    ContentUnavailableView(
                        "No Similar Photos",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Photos that look alike will be grouped here.")
                    )
                    .padding(.top, 80)
                } else if similarityService.isAnalyzing || imageGroups.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView(value: similarityService.isAnalyzing ? similarityService.progress : 0) {
                            Text(similarityService.isAnalyzing ? "Analyzing similarities..." : "Loading...")
                                .font(.headline)
                        }
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)

                        if similarityService.isAnalyzing {
                            Text(similarityService.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                        ForEach(imageGroups) { group in
                            GroupSectionView(
                                group: group,
                                isExpanded: expandedGroups.contains(group.id),
                                isSelecting: isSelecting,
                                selectedIdentifiers: $selectedIdentifiers,
                                onTapHeader: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        if expandedGroups.contains(group.id) {
                                            expandedGroups.remove(group.id)
                                        } else {
                                            expandedGroups.insert(group.id)
                                        }
                                    }
                                },
                                onTapAsset: { asset in selectedAsset = asset }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .gridDragSelection(isSelecting: isSelecting, selected: $selectedIdentifiers)
                }
            }
            .swipeBackDisabled(isSelecting)
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .navigationTitle("Similar Photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !assets.isEmpty && !similarityService.isAnalyzing {
                        Button {
                            Task {
                                similarityService.invalidateGroups()
                                await analyzeAndGroup()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !assets.isEmpty && !similarityService.isAnalyzing {
                        Button(isSelecting ? "Cancel" : "Select") {
                            withAnimation {
                                isSelecting.toggle()
                                if !isSelecting {
                                    selectedIdentifiers.removeAll()
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaBar(edge: .bottom) {
                if isSelecting {
                    SelectionActionBar(
                        selectedCount: selectedIdentifiers.count,
                        onMove: { showMoveSheet = true },
                        onDelete: { deleteSelectedAssets() }
                    )
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                MoveToAlbumSheet(sourceAlbum: nil, identifiersToMove: Array(selectedIdentifiers), dataService: dataService) {
                    selectedIdentifiers.removeAll()
                    isSelecting = false
                    reload()
                }
            }
            .onAppear { reload() }
            .onReceive(dataService.$lastUpdate) { _ in
                reload()
            }
            .task {
                libraryManager.requestAccessIfNeeded()
                reload()
            }
            .navigationDestination(item: $selectedAsset) { asset in
                PhotoDetailView(assets: assets, startingAt: asset, mode: .browseOnly)
            }
        }
    }

    private func reload() {
        guard libraryManager.isAuthorized else { return }
        deletedItems = dataService.fetchDeletedItems()
        let deletedIdentifiers = Set(deletedItems.map(\.assetIdentifier))

        let fetchedAssets = PhotoLibraryService.shared
            .fetchAllAssets()
            .filter { !deletedIdentifiers.contains($0.localIdentifier) }

        if assets.map({ $0.localIdentifier }).sorted() != fetchedAssets.map({ $0.localIdentifier }).sorted() {
            assets = fetchedAssets

            Task {
                await analyzeAndGroup()
            }
        } else if !didAnalyze && !assets.isEmpty {
            Task {
                await analyzeAndGroup()
            }
        }
    }

    private func analyzeAndGroup() async {
        guard !similarityService.isAnalyzing && !assets.isEmpty else { return }

        let groups = await similarityService.analyzeAndGroupAssets(assets)

        await MainActor.run {
            imageGroups = groups
            didAnalyze = true

            expandedGroups.formUnion(groups.map(\.id))
        }
    }

    private func deleteSelectedAssets() {
        dataService.softDelete(Array(selectedIdentifiers))

        selectedIdentifiers.removeAll()
        isSelecting = false

        reload()
    }
}

struct GroupSectionView: View {
    let group: ImageGroup
    let isExpanded: Bool
    let isSelecting: Bool
    @Binding var selectedIdentifiers: Set<String>
    let onTapHeader: () -> Void
    let onTapAsset: (PHAsset) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var shouldShowDropdown: Bool {
        return group.assets.count > 5
    }

    private var isSelectingBinding: Binding<Bool> {
        .constant(isSelecting)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowDropdown {
                Button(action: onTapHeader) {
                    HStack(spacing: 12) {
                        Image(systemName: group.icon)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(group.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(0))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: group.icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(group.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if shouldShowDropdown {
                if isExpanded {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(group.assets, id: \.localIdentifier) { asset in
                            AssetThumbnailView(asset: asset)
                                .selectionOverlay(
                                    isSelecting: isSelecting,
                                    isSelected: selectedIdentifiers.contains(asset.localIdentifier)
                                )
                                .dragToSelect(
                                    isSelecting: isSelectingBinding,
                                    selectedIdentifiers: $selectedIdentifiers,
                                    identifier: asset.localIdentifier
                                )
                                .onTapGesture {
                                    if !isSelecting { onTapAsset(asset) }
                                }
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack(spacing: 2) {
                        ForEach(Array(group.assets.prefix(4)), id: \.localIdentifier) { asset in
                            AssetThumbnailView(asset: asset)
                                .aspectRatio(1, contentMode: .fit)
                                .selectionOverlay(
                                    isSelecting: isSelecting,
                                    isSelected: selectedIdentifiers.contains(asset.localIdentifier)
                                )
                                .dragToSelect(
                                    isSelecting: isSelectingBinding,
                                    selectedIdentifiers: $selectedIdentifiers,
                                    identifier: asset.localIdentifier
                                )
                                .onTapGesture {
                                    if !isSelecting { onTapAsset(asset) }
                                }
                        }

                        Spacer()
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(group.assets, id: \.localIdentifier) { asset in
                        AssetThumbnailView(asset: asset)
                            .selectionOverlay(
                                isSelecting: isSelecting,
                                isSelected: selectedIdentifiers.contains(asset.localIdentifier)
                            )
                            .dragToSelect(
                                isSelecting: isSelectingBinding,
                                selectedIdentifiers: $selectedIdentifiers,
                                identifier: asset.localIdentifier
                            )
                            .onTapGesture {
                                if !isSelecting { onTapAsset(asset) }
                            }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AllItemsView()
    }
    .environmentObject(DataService())
}
