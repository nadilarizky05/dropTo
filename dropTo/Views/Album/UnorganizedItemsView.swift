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
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionActionBar
            }
        }
        .navigationTitle("Unorganized Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
                .disabled(assets.isEmpty && !isSelecting)
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
        .onAppear {
            loadAssets()
        }
        .onReceive(dataService.$lastUpdate) { _ in
            loadAssets()
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
        loadAssets()
    }
}

#Preview {
    NavigationStack { UnorganizedItemsView() }
        .environmentObject(DataService())
}
