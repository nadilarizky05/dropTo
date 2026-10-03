import SwiftUI
import Photos

struct RecentlyDeletedView: View {
    @EnvironmentObject private var dataService: DataService
    @State private var isSelecting = false
    @State private var selectedIdentifiers: Set<String> = []
    @State private var selectedAsset: PHAsset?
    @State private var assets: [PHAsset] = []
    @State private var deletedItems: [DeletedItem] = []

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private func loadAssets() {
        deletedItems = dataService.fetchDeletedItems()
        assets = PhotoLibraryService.shared.fetchAssets(
            withIdentifiers: deletedItems.map(\.assetIdentifier)
        )
    }

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Recently Deleted Items")
                        .font(.headline)
                }
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetThumbnailView(asset: asset)
                            .selectionOverlay(isSelecting: isSelecting, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
                            .dragToSelect(
                                isSelecting: .constant(isSelecting),
                                selectedIdentifiers: $selectedIdentifiers,
                                identifier: asset.localIdentifier
                            )
                            .onTapGesture {
                                if !isSelecting { selectedAsset = asset }
                            }
                    }
                }
                .gridDragSelection(isSelecting: isSelecting, selected: $selectedIdentifiers)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSelecting && !assets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedIdentifiers = allSelected ? [] : Set(assets.map(\.localIdentifier))
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if isSelecting {
                SelectionActionBar(
                    selectedCount: selectedIdentifiers.count,
                    onMove: recoverSelected,
                    leadingSystemImage: "arrow.uturn.backward",
                    leadingLabel: "Recover",
                    deleteSuffix: " Forever",
                    deleteMessage: "These items will be permanently deleted from your device. This can't be undone.",
                    totalCount: assets.count,
                    actsOnAllWhenEmpty: true,
                    onDelete: deleteSelectedForever
                )
            }
        }
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .swipeBackDisabled(isSelecting)
        .navigationDestination(item: $selectedAsset) { asset in
            PhotoDetailView(assets: assets, startingAt: asset, mode: .recentlyDeleted)
        }
        .onAppear {
            loadAssets()
        }
        .onReceive(dataService.$lastUpdate) { _ in
            loadAssets()
        }
    }

    private var allSelected: Bool {
        !assets.isEmpty && selectedIdentifiers.count == assets.count
    }

    private var targetIdentifiers: [String] {
        selectedIdentifiers.isEmpty ? assets.map(\.localIdentifier) : Array(selectedIdentifiers)
    }

    private func recoverSelected() {
        dataService.restoreFromDeleted(targetIdentifiers)
        selectedIdentifiers.removeAll()
        isSelecting = false
        loadAssets()
    }

    private func deleteSelectedForever() {
        Task {
            let ids = targetIdentifiers
            let success = await PhotoLibraryService.shared.permanentlyDelete(identifiers: ids)
            if success {
                for id in ids { dataService.removeFromDeletedList(id) }
            }
            selectedIdentifiers.removeAll()
            isSelecting = false
            loadAssets()
        }
    }
}

#Preview {
    NavigationStack { RecentlyDeletedView() }
        .environmentObject(DataService())
}
