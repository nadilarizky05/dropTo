import SwiftUI
import Photos
import SwiftData

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject private var dataService: DataService
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator

    @State private var showCamera = false
    @State private var albumChosenInCamera: UUID?
    @State private var selectedAsset: PHAsset?
    @State private var isSelecting = false
    @State private var selectedIdentifiers: Set<String> = []
    @State private var showMoveSheet = false
    @State private var showAddFromUnorganized = false
    @State private var groupedAssets: [DayGroup] = []

    private var currentAlbum: Album { album }

    private func loadAssets() {
        groupedAssets = PhotoLibraryService.shared
            .fetchAssets(withIdentifiers: currentAlbum.assetIdentifiers)
            .groupedByDay()
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        Group {
            if currentAlbum.assetIdentifiers.isEmpty {
                EmptyAlbumView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedAssets, id: \.day) { group in
                            Text(sectionTitle(for: group.day))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 4) {
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
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom)
                    .gridDragSelection(isSelecting: isSelecting, selected: $selectedIdentifiers)
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if isSelecting {
                SelectionActionBar(
                    selectedCount: selectedIdentifiers.count,
                    onMove: { showMoveSheet = true },
                    onDelete: deleteSelected
                )
            } else {
                HStack {
                    AlbumActionButton(systemImage: "photo.stack", label: "Add from Unorganized") {
                        showAddFromUnorganized = true
                    }
                    Spacer()
                    AlbumActionButton(systemImage: "camera.fill", label: "Take Photo") {
                        showCamera = true
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(currentAlbum.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSelecting = false
                        selectedIdentifiers.removeAll()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
                .disabled(currentAlbum.assetIdentifiers.isEmpty && !isSelecting)
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: openAlbumChosenInCamera) {
            CameraPicker(dataService: dataService, initialAlbumID: album.id) { newAlbumID in
                albumChosenInCamera = newAlbumID
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToAlbumSheet(sourceAlbum: currentAlbum, identifiersToMove: Array(selectedIdentifiers), dataService: dataService) {
                selectedIdentifiers.removeAll()
                isSelecting = false
            }
        }
        .sheet(isPresented: $showAddFromUnorganized) {
            AddFromUnorganizedSheet(album: currentAlbum, dataService: dataService) {
                loadAssets()
            }
        }
        .navigationDestination(item: $selectedAsset) { asset in
            PhotoDetailView(assets: groupedAssets.flatMap(\.assets), startingAt: asset, mode: .album(currentAlbum))
        }
        .onAppear {
            loadAssets()
        }
        .onReceive(dataService.$lastUpdate) { _ in
            loadAssets()
        }
    }

    private func openAlbumChosenInCamera() {
        defer { albumChosenInCamera = nil }
        guard let chosen = albumChosenInCamera, chosen != album.id else { return }
        deepLinkCoordinator.albumToOpen = chosen
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

    private func deleteSelected() {
        let identifiersToDelete = Array(selectedIdentifiers)

        dataService.softDelete(identifiersToDelete, sourceAlbumID: currentAlbum.id)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        selectedIdentifiers.removeAll()
        isSelecting = false
        loadAssets()
    }

    private func sectionTitle(for date: Date) -> String {
        DayTitleFormatter.string(for: date)
    }
}

private struct EmptyAlbumView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No items yet")
                .font(.headline)
            Text("Already snapped something with the regular camera?\nAdd it here, or take a new one now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -60)
    }
}

private struct AlbumActionButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(Color.black.opacity(0.25))
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.85), .white.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .accessibilityLabel(label)
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

#Preview {
    NavigationStack {
        AlbumDetailView(album: Album(title: "Coding"))
            .environmentObject(DataService())
            .environment(DeepLinkCoordinator())
    }
}
