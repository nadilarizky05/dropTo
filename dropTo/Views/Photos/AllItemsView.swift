//
//  AllItemsView.swift
//  dropTo
//
//  Created by Nadila Rizky Amelia on 20/07/26.
//
//============================================================================
// VIEW: ALL ITEMS
//============================================================================
// HALAMAN SEMUA FOTO/VIDEO DI DEVICE (EXCLUDE YANG UDAH DIHAPUS)
// DIKELOMPOKKAN BERDASARKAN KEMIRIPAN VISUAL

import SwiftUI
import Photos

struct AllItemsView: View {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    
    @EnvironmentObject private var dataService: DataService
    @StateObject private var libraryManager = PhotoLibraryService.shared
    @StateObject private var similarityService = ImageSimilarityService.shared
    
    @State private var assets: [PHAsset] = []          // LIST SEMUA FOTO/VIDEO
    @State private var imageGroups: [ImageGroup] = []  // GRUP FOTO BERDASARKAN KEMIRIPAN
    @State private var selectedAsset: PHAsset?         // FOTO YANG DIPILIH (NAVIGATION)
    @State private var deletedItems: [DeletedItem] = [] // LIST FOTO DI TRASH
    @State private var expandedGroups: Set<UUID> = []  // GRUP YANG DI-EXPAND
    
    // SELECT MODE
    @State private var isSelecting = false             // MODE SELECT ON/OFF
    @State private var selectedIdentifiers: Set<String> = [] // FOTO YANG TERCENTANG

    var body: some View {
        NavigationStack {
            ScrollView {
                if assets.isEmpty {
                    ContentUnavailableView(
                        "No Items Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Photos and videos you take will show up here.")
                    )
                    .padding(.top, 80)
                } else if similarityService.isAnalyzing || imageGroups.isEmpty {
                    // LOADING STATE SAAT ANALISIS ATAU GROUPS BELUM READY
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
                    // TAMPILKAN FOTO BERDASARKAN GRUP KEMIRIPAN
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                        ForEach(imageGroups) { group in
                            GroupSectionView(
                                group: group,
                                isExpanded: expandedGroups.contains(group.id),
                                isSelecting: isSelecting,
                                selectedIdentifiers: $selectedIdentifiers,
                                onTapHeader: {
                                    // EXPLICIT ANIMATION UNTUK SMOOTH EXPAND/COLLAPSE
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        if expandedGroups.contains(group.id) {
                                            expandedGroups.remove(group.id)
                                        } else {
                                            expandedGroups.insert(group.id)
                                        }
                                    }
                                },
                                onTapAsset: { asset in
                                    if isSelecting {
                                        toggleSelection(asset.localIdentifier)
                                    } else {
                                        selectedAsset = asset
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Similar Photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // BUTTON RE-ANALYZE (KIRI)
                ToolbarItem(placement: .topBarLeading) {
                    if !assets.isEmpty && !similarityService.isAnalyzing {
                        Button {
                            Task {
                                await analyzeAndGroup()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                
                // BUTTON SELECT (KANAN)
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
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selectedIdentifiers.isEmpty {
                    selectionActionBar
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

    //============================================================================
    // FUNCTION: RELOAD
    //============================================================================
    // AMBIL SEMUA FOTO/VIDEO DI DEVICE, FILTER YANG SUDAH DIHAPUS
    
    private func reload() {
        guard libraryManager.isAuthorized else { return }
        deletedItems = dataService.fetchDeletedItems()
        let deletedIdentifiers = Set(deletedItems.map(\.assetIdentifier))
        
        let fetchedAssets = PhotoLibraryService.shared
            .fetchAllAssets()
            .filter { !deletedIdentifiers.contains($0.localIdentifier) }
        
        // HANYA RELOAD JIKA ADA PERUBAHAN
        if assets.map({ $0.localIdentifier }).sorted() != fetchedAssets.map({ $0.localIdentifier }).sorted() {
            assets = fetchedAssets
            
            // ANALISIS DAN GROUP OTOMATIS
            Task {
                await analyzeAndGroup()
            }
        } else if imageGroups.isEmpty && !assets.isEmpty {
            // JIKA BELUM ADA GROUPS TAPI ADA ASSETS, ANALISIS
            Task {
                await analyzeAndGroup()
            }
        }
    }
    
    //============================================================================
    // FUNCTION: ANALYZE AND GROUP
    //============================================================================
    // ANALISIS KEMIRIPAN DAN KELOMPOKKAN FOTO
    
    private func analyzeAndGroup() async {
        // SKIP JIKA SEDANG ANALISIS ATAU TIDAK ADA ASSETS
        guard !similarityService.isAnalyzing && !assets.isEmpty else { return }
        
        let groups = await similarityService.analyzeAndGroupAssets(assets)
        
        await MainActor.run {
            imageGroups = groups
            
            // AUTO-EXPAND GRUP PERTAMA (YANG PALING BARU)
            // TAPI SKIP "OTHER PHOTOS" - BIAR DEFAULT COLLAPSED
            if let firstGroup = groups.first, firstGroup.category != .normal {
                expandedGroups.insert(firstGroup.id)
            }
        }
    }
    
    //============================================================================
    // FUNCTION: TOGGLE SELECTION
    //============================================================================
    
    private func toggleSelection(_ identifier: String) {
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }
    
    //============================================================================
    // VIEW: SELECTION ACTION BAR
    //============================================================================
    
    private var selectionActionBar: some View {
        HStack(spacing: 20) {
            Spacer()
            
            // COUNT
            Text("\(selectedIdentifiers.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // DELETE BUTTON
            Button(role: .destructive) {
                deleteSelectedAssets()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedIdentifiers.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    //============================================================================
    // FUNCTION: DELETE SELECTED ASSETS
    //============================================================================
    
    private func deleteSelectedAssets() {
        let selectedAssets = assets.filter { selectedIdentifiers.contains($0.localIdentifier) }
        
        for asset in selectedAssets {
            dataService.softDelete(asset.localIdentifier)
        }
        
        // RESET STATE
        selectedIdentifiers.removeAll()
        isSelecting = false
        
        // RELOAD
        reload()
    }
}

//============================================================================
// VIEW: GROUP SECTION
//============================================================================
// SECTION UNTUK SATU GRUP FOTO YANG MIRIP

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
    
    // THRESHOLD: GRUP DENGAN LEBIH DARI 5 FOTO BARU PAKAI DROPDOWN
    private var shouldShowDropdown: Bool {
        return group.assets.count > 5
    }
    
    // WRAPPER UNTUK DRAG TO SELECT (BUTUH CONSTANT BINDING)
    private var isSelectingBinding: Binding<Bool> {
        .constant(isSelecting)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // HEADER - HANYA TAMPIL JIKA ADA DROPDOWN
            if shouldShowDropdown {
                Button(action: onTapHeader) {
                    HStack(spacing: 12) {
                        // ICON KATEGORI
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
                        
                        // CHEVRON INDICATOR - SMOOTH ROTATION
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(0)) // PREVENT IMPLICIT ANIMATION
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // HEADER TANPA DROPDOWN (NON-INTERACTIVE)
                HStack(spacing: 12) {
                    // ICON KATEGORI
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
            
            // CONTENT
            if shouldShowDropdown {
                // GRUP BESAR: PAKAI DROPDOWN
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
                                    onTapAsset(asset)
                                }
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    // COLLAPSED: TAMPILKAN 4 FOTO PREVIEW (BISA TAP INDIVIDUAL)
                    HStack(spacing: 2) {
                        ForEach(Array(group.assets.prefix(4)), id: \.localIdentifier) { asset in
                            AssetThumbnailView(asset: asset)
                                .aspectRatio(1, contentMode: .fit)
                                .selectionOverlay(
                                    isSelecting: isSelecting,
                                    isSelected: selectedIdentifiers.contains(asset.localIdentifier)
                                )
                                .onTapGesture {
                                    if isSelecting {
                                        // KALAU SELECT MODE, TOGGLE SELECTION
                                        if selectedIdentifiers.contains(asset.localIdentifier) {
                                            selectedIdentifiers.remove(asset.localIdentifier)
                                        } else {
                                            selectedIdentifiers.insert(asset.localIdentifier)
                                        }
                                    } else {
                                        // KALAU NORMAL MODE, BUKA FOTO
                                        onTapAsset(asset)
                                    }
                                }
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                // GRUP KECIL (<= 5): LANGSUNG TAMPILKAN SEMUA (NO DROPDOWN)
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
                                onTapAsset(asset)
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
    AllItemsView()
        .environmentObject(DataService())
}

