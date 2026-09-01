//
//  RecentlyDeletedView.swift
//  dropTo
//

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
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selectedIdentifiers.removeAll()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selectedIdentifiers.isEmpty {
                actionBar
            }
        }
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

    private var actionBar: some View {
        VStack(spacing: 12) {
            Text("\(selectedIdentifiers.count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Button {
                    for id in selectedIdentifiers {
                        dataService.restoreFromDeleted(id)
                    }
                    selectedIdentifiers.removeAll()
                    isSelecting = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Recover")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                }
                
                Button(role: .destructive) {
                    Task {
                        let ids = Array(selectedIdentifiers)
                        await PhotoLibraryService.shared.permanentlyDelete(identifiers: ids)
                        for id in ids { dataService.removeFromDeletedList(id) }
                        selectedIdentifiers.removeAll()
                        isSelecting = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Delete Forever")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: .red.opacity(0.4), radius: 8, y: 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func toggle(_ identifier: String) {
        guard isSelecting else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedIdentifiers.contains(identifier) {
                selectedIdentifiers.remove(identifier)
            } else {
                selectedIdentifiers.insert(identifier)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

#Preview {
    NavigationStack { RecentlyDeletedView() }
        .environmentObject(DataService())
}
