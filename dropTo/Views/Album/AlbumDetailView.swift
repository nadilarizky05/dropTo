//============================================================================
// VIEW: DETAIL ALBUM
//============================================================================
// HALAMAN DETAIL ALBUM - TAMPIL FOTO/VIDEO DIKELOMPOKKAN PER HARI, ADA SELECT MODE DAN CAMERA BUTTON

import SwiftUI
import Photos
import SwiftData

struct AlbumDetailView: View {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    
    let album: Album                                        // ALBUM YANG DITAMPILKAN
    @EnvironmentObject private var dataService: DataService // AKSES DATABASE

    
    @State private var showCamera = false                   // FLAG BUKA/TUTUP KAMERA
    @State private var selectedAsset: PHAsset?              // FOTO YANG DIPILIH (BUAT NAVIGATION)
    @State private var isSelecting = false                  // MODE SELECT ON/OFF
    @State private var selectedIdentifiers: Set<String> = [] // LIST FOTO TERCENTANG
    @State private var showMoveSheet = false                 // FLAG SHEET MOVE
    @State private var showDeleteConfirm = false             // FLAG KONFIRMASI DELETE
    @State private var groupedAssets: [(day: Date, assets: [PHAsset])] = [] // FOTO PER HARI
    
    //============================================================================
    // COMPUTED PROPERTY: CURRENT ALBUM
    //============================================================================
    // FETCH ALBUM TERBARU DARI DATABASE BIAR SELALU SYNC
    
    private var currentAlbum: Album {
        dataService.fetchAlbums().first(where: { $0.id == album.id }) ?? album
    }
    
    //============================================================================
    // FUNCTION: LOAD ASSETS DAN GROUP PER HARI
    //============================================================================
    // AMBIL SEMUA FOTO/VIDEO DI ALBUM → KELOMPOKKAN PER TANGGAL (HARI)
    
    private func loadAssets() {
        let assets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: currentAlbum.assetIdentifiers)
        let groups = Dictionary(grouping: assets) { asset in
            Calendar.current.startOfDay(for: asset.creationDate ?? Date())
        }
        groupedAssets = groups
            .map { (day: $0.key, assets: $0.value) }
            .sorted { $0.day > $1.day }
    }
    
    //============================================================================
    // GRID LAYOUT
    //============================================================================
    // 4 KOLOM FOTO
    
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        ScrollView {
            if currentAlbum.assetIdentifiers.isEmpty {
                EmptyAlbumView()
                    .padding(.top, 100)
            } else {
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
                                        if isSelecting {
                                            toggle(asset.localIdentifier)
                                        } else {
                                            selectedAsset = asset
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.vertical)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionActionBar }
            else {
                HStack { Spacer(); CameraFloatingButton { showCamera = true }; Spacer() }  // ← center
            }
        }
        .navigationTitle(currentAlbum.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting) // DISABLE SWIPE BACK SAAT SELECT MODE
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { media in
                Task {
                    await dataService.saveCapturedMedia(media, toAlbumWithID: album.id)
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Delete \(selectedIdentifiers.count) item\(selectedIdentifiers.count > 1 ? "s" : "")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These items will be moved to Recently Deleted.")
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToAlbumSheet(sourceAlbum: currentAlbum, identifiersToMove: Array(selectedIdentifiers), dataService: dataService) {
                selectedIdentifiers.removeAll()
                isSelecting = false
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
    
    private var selectionActionBar: some View {
        HStack(spacing: 16) {
            Text("\(selectedIdentifiers.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            // DELETE BUTTON (ICON HITAM, GLASSY BACKGROUND)
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .disabled(selectedIdentifiers.isEmpty)

            // MOVE BUTTON (ICON HITAM, GLASSY BACKGROUND)
            Button {
                showMoveSheet = true
            } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .disabled(selectedIdentifiers.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    
    //============================================================================
    // FUNCTION: TOGGLE SELECTION
    //============================================================================
    // CENTANG/UNCENTANG FOTO SAAT MODE SELECT AKTIF
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
    
    //============================================================================
    // FUNCTION: DELETE SELECTED ASSETS
    //============================================================================
    // SOFT DELETE - PINDAH KE TRASH (RECENTLY DELETED), BUKAN HAPUS PERMANEN
    
    private func deleteSelected() {
        let identifiersToDelete = Array(selectedIdentifiers)
        
        // SOFT DELETE → PINDAH KE TRASH
        for identifier in identifiersToDelete {
            dataService.softDelete(identifier, sourceAlbumID: currentAlbum.id)
        }
        
        // FEEDBACK & CLEANUP
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        selectedIdentifiers.removeAll()
        isSelecting = false
        loadAssets()
    }
    
    //============================================================================
    // FUNCTION: FORMAT TANGGAL SECTION HEADER
    //============================================================================
    // FORMAT TANGGAL JADI "Wed, 01 Sep"
    private func sectionTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM"
        return formatter.string(from: date)
    }
}

private struct EmptyAlbumView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No items yet")
                .font(.headline)
            Text("Take a photo or video, or drag items here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CameraFloatingButton: View {
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
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

#Preview {
    NavigationStack {
        AlbumDetailView(album: Album(title: "Coding"))
            .environmentObject(DataService())
    }
}
