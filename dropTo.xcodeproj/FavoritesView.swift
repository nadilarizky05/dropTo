//
//  FavoritesView.swift
//  dropTo
//

import SwiftUI
import Photos

struct FavoritesView: View {
    @EnvironmentObject private var dataService: DataService
    @StateObject private var libraryService = PhotoLibraryService.shared
    @State private var favoriteAssets: [PHAsset] = []
    @State private var selectedAsset: PHAsset?
    @State private var refreshTimer: Timer?
    
    @State private var isSelecting = false                   // MODE SELECT ON/OFF
    @State private var selectedIdentifiers: Set<String> = [] // LIST FOTO TERCENTANG
    @State private var showMoveSheet = false                 // FLAG SHEET MOVE
    @State private var showDeleteConfirmation = false        // FLAG ALERT DELETE
    
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
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
                                .selectionOverlay(isSelecting: isSelecting, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
                                .dragToSelect(
                                    isSelecting: $isSelecting,
                                    selectedIdentifiers: $selectedIdentifiers,
                                    identifier: asset.localIdentifier
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelecting {
                                        toggle(asset.localIdentifier)
                                    } else {
                                        selectedAsset = asset
                                    }
                                }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionActionBar
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(isSelecting) // DISABLE SWIPE BACK SAAT SELECT MODE
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
                .disabled(favoriteAssets.isEmpty && !isSelecting)
            }
        }
        .navigationDestination(item: $selectedAsset) { asset in
            PhotoDetailView(
                assets: favoriteAssets,
                startingAt: asset,
                mode: .favorites
            )
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToAlbumSheet(sourceAlbum: nil, identifiersToMove: Array(selectedIdentifiers), dataService: dataService) {
                selectedIdentifiers.removeAll()
                isSelecting = false
                loadFavorites()
            }
        }
        .confirmationDialog(
            "Delete \(selectedIdentifiers.count) item\(selectedIdentifiers.count > 1 ? "s" : "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These items will be moved to Recently Deleted.")
        }
        .task {
            loadFavorites()
            // Setup periodic refresh untuk mendeteksi perubahan favorite status
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                loadFavorites()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onReceive(dataService.$lastUpdate) { _ in
            // Refresh saat ada perubahan (misal foto di-unfavorite)
            loadFavorites()
        }
    }
    
    //============================================================================
    // SUBVIEW: SELECTION ACTION BAR
    //============================================================================
    // BAR DI BAWAH DENGAN DELETE & MOVE BUTTONS (GLASSY STYLE)
    
    private var selectionActionBar: some View {
        HStack(spacing: 16) {
            Text("\(selectedIdentifiers.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            // DELETE BUTTON (ICON HITAM, GLASSY BACKGROUND)
            Button {
                showDeleteConfirmation = true
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
    // FUNCTION: DELETE SELECTED ITEMS
    //============================================================================
    // HAPUS FOTO/VIDEO YANG DIPILIH → PINDAH KE TRASH
    
    private func deleteSelectedItems() {
        for identifier in selectedIdentifiers {
            dataService.softDelete(identifier, sourceAlbumID: nil)
        }
        
        // HAPTIC FEEDBACK
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        // CLEANUP UI STATE
        selectedIdentifiers.removeAll()
        isSelecting = false
        
        // RELOAD DATA (PENTING! BIAR GRID UPDATE)
        loadFavorites()
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
    
    //============================================================================
    // FUNCTION: LOAD FAVORITES
    //============================================================================
    // AMBIL SEMUA FOTO YANG SUDAH DI-FAVORITE DARI PHOTOS LIBRARY
    
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
