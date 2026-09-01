//
//  UnorganizedItemsView.swift
//  dropTo
//
//  Created by Nadila Rizky Amelia on 20/07/26.
//
//============================================================================
// VIEW: UNORGANIZED ITEMS
//============================================================================
// HALAMAN FOTO/VIDEO YANG BELUM MASUK ALBUM MANAPUN DAN BELUM DIHAPUS

import SwiftUI
import Photos

struct UnorganizedItemsView: View {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    
    @EnvironmentObject private var dataService: DataService // AKSES DATABASE
    
    @State private var selectedAsset: PHAsset?               // FOTO DIPILIH (NAVIGATION)
    @State private var isSelecting = false                   // MODE SELECT ON/OFF
    @State private var selectedIdentifiers: Set<String> = [] // LIST FOTO TERCENTANG
    @State private var showMoveSheet = false                 // FLAG SHEET MOVE
    @State private var showDeleteConfirmation = false        // FLAG ALERT DELETE
    @State private var assets: [PHAsset] = []                // LIST FOTO/VIDEO UNORGANIZED
    @State private var albums: [Album] = []                  // LIST ALBUM (BUAT CEK)
    @State private var deletedItems: [DeletedItem] = []      // LIST FOTO DI TRASH (BUAT CEK)

    //============================================================================
    // GRID LAYOUT
    //============================================================================
    // 4 KOLOM FOTO
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    //============================================================================
    // COMPUTED PROPERTY: ORGANIZED IDENTIFIERS
    //============================================================================
    // SET SEMUA IDENTIFIER FOTO YANG SUDAH ADA DI ALBUM
    
    private var organizedIdentifiers: Set<String> {
        Set(albums.flatMap(\.assetIdentifiers))
    }
    
    //============================================================================
    // COMPUTED PROPERTY: DELETED IDENTIFIERS
    //============================================================================
    // SET SEMUA IDENTIFIER FOTO YANG ADA DI TRASH
    
    private var deletedIdentifiers: Set<String> {
        Set(deletedItems.map(\.assetIdentifier))
    }
    
    //============================================================================
    // FUNCTION: LOAD ASSETS
    //============================================================================
    // AMBIL SEMUA FOTO DI DEVICE → FILTER YANG BELUM DI ALBUM & BELUM DI TRASH
    
    private func loadAssets() {
        albums = dataService.fetchAlbums()
        deletedItems = dataService.fetchDeletedItems()
        assets = PhotoLibraryService.shared
            .fetchAllAssets()
            .filter { !organizedIdentifiers.contains($0.localIdentifier) && !deletedIdentifiers.contains($0.localIdentifier) }
    }

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                ContentUnavailableView(
                    "All Organized!",
                    systemImage: "checkmark.circle",
                    description: Text("Every photo and video is filed into an album.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetThumbnailView(asset: asset)
                            .selectionOverlay(isSelecting: isSelecting, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
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
        .navigationTitle(isSelecting ? "\(selectedIdentifiers.count) Selected" : "Unorganized Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    withAnimation {
                        isSelecting.toggle()
                        selectedIdentifiers.removeAll()
                    }
                }
                .disabled(assets.isEmpty && !isSelecting)
            }
            
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .disabled(selectedIdentifiers.isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedIdentifiers.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToAlbumSheet(sourceAlbum: nil, identifiersToMove: Array(selectedIdentifiers), dataService: dataService) {
                selectedIdentifiers.removeAll()
                isSelecting = false
                loadAssets()
            }
        }
        .navigationDestination(item: $selectedAsset) { asset in
            PhotoDetailView(assets: assets, startingAt: asset, mode: .browseOnly)
        }
        .alert("Delete \(selectedIdentifiers.count) item\(selectedIdentifiers.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedItems()
            }
        } message: {
            Text("These items will be moved to Recently Deleted.")
        }
        .onAppear {
            loadAssets()
        }
        .onReceive(dataService.$lastUpdate) { _ in
            loadAssets()
        }
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        selectedIdentifiers.removeAll()
        isSelecting = false
        loadAssets()
    }
}

#Preview {
    NavigationStack { UnorganizedItemsView() }
        .environmentObject(DataService())
}
