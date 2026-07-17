//
//  AlbumView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 24/04/26.
//

import SwiftUI
import Photos

struct AlbumView: View {
    var albumColumns = [GridItem(.flexible())]
    @State var dragOffset: CGSize = .zero
    @State var showDeleteAlert = false
    @State var highlightedAlbumID: UUID? = nil
    @State var isDragging = false
    @State var showDeleteAlbumAlert = false
    @State var albumToDelete: AlbumProp? = nil
    @State var isEditingAlbums = false
    @State var isHoveringTrash = false
    @State var trashFrame: CGRect = .zero
    @State private var showUnorganizedGrid = false

    @EnvironmentObject var photoManager: PhotoLibraryManager
    @EnvironmentObject var albumStore: AlbumStore

    var unorganized: [PHAsset] {
        photoManager.unorganizedAssets(albums: albumStore.albums)
    }

    var todayUnorganized: [PHAsset] {
        let calendar = Calendar.current
        return unorganized.filter {
            calendar.isDate($0.creationDate ?? Date(), inSameDayAs: photoManager.selectedDate)
        }
    }

    var topAsset: PHAsset? { todayUnorganized.last }

    @State var albumFrames: [UUID: CGRect] = [:]

    var body: some View {
        HStack {

// MARK: - LEFT STACK
            VStack(alignment: .center, spacing: 25) {
            
                HorizontalCalendarView()
                    .environmentObject(photoManager)
                    .environmentObject(albumStore)
                    .padding(.top, 20)
                
                Text("You've got \(todayUnorganized.count) \(todayUnorganized.count == 1 ? "unorganized photo" : "unorganized photos")")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.7))
                    )
               
                ZStack {
                    if todayUnorganized.isEmpty {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 210, height: 280)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.largeTitle).foregroundStyle(.green)
                                    Text("All organized!")
                                        .foregroundStyle(.secondary)
                                }
                            )
                    } else {
                        ForEach(todayUnorganized, id: \.localIdentifier) { asset in
                            let isTop = asset.localIdentifier == topAsset?.localIdentifier
                            AssetCardView(asset: asset)
                                .frame(width: 210, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                                .zIndex(isTop ? 10 : 1)
                                .offset(isTop ? dragOffset : .zero)
                                .rotationEffect(isTop ? .degrees(Double(dragOffset.width) / 20) : .zero)
                                .gesture(
                                    isTop ? DragGesture(coordinateSpace: .global)
                                        .onChanged { value in
                                            dragOffset = value.translation
                                            isDragging = true
                                            let loc = value.location
                                            highlightedAlbumID = albumFrames.first(where: {
                                                $0.value.contains(loc)
                                            })?.key
                                            isHoveringTrash = trashFrame.contains(loc)
                                        }
                                        .onEnded { value in
                                            isDragging = false
                                            let loc = value.location

                                            if trashFrame.contains(loc) {
                                                showDeleteAlert = true
                                                dragOffset = .zero
                                            } else if let targetID = highlightedAlbumID,
                                                      let idx = albumStore.albums.firstIndex(where: { $0.id == targetID }),
                                                      let asset = topAsset {
                                                withAnimation {
                                                    albumStore.assignPhoto(assetIdentifier: asset.localIdentifier, to: idx)
                                                }
                                                dragOffset = .zero
                                            } else {
                                                withAnimation { dragOffset = .zero }
                                            }

                                            highlightedAlbumID = nil
                                            isHoveringTrash = false
                                        }
                                    : nil
                                )
                                .onTapGesture {
                                    guard !isDragging else { return }
                                    showUnorganizedGrid = true
                                }
                        }
                    }
                }
                    .frame(height: 240)
                    .padding(.vertical, 25)

                
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill").font(.caption)
                        Text("Tap to view · Drag to album · Drop to trash")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 15)

                    
                RoundedRectangle(cornerRadius: 16)
                    .fill(isHoveringTrash ? Color.red.opacity(0.18) : (isDragging ? Color.red.opacity(0.08) : Color.gray.opacity(0.08)))
                    .frame(width: 160, height: 44)
                    .overlay(
                            HStack(spacing: 6) {
                                Image(systemName: isHoveringTrash ? "trash.fill" : "trash")
                                    .foregroundStyle(isDragging ? .red : .secondary)
                                Text("Drop to delete")
                                    .font(.caption)
                                    .foregroundStyle(isDragging ? .red : .secondary)
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    isDragging ? Color.red.opacity(0.4) : Color.clear,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5])
                                )
                        )
                        .animation(.easeInOut(duration: 0.2), value: isDragging)
                        .animation(.easeInOut(duration: 0.15), value: isHoveringTrash)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { trashFrame = geo.frame(in: .global) }
                                    .onChange(of: geo.frame(in: .global)) { trashFrame = geo.frame(in: .global) }
                            }
                        )
                }
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            

// MARK: - RIGHT STACK
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(albumStore.albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album, photoManager: photoManager)
                        } label: {
                            AlbumCoverView(album: album, photoManager: photoManager)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(highlightedAlbumID == album.id ? Color.blue : Color.clear, lineWidth: 3)
                                )
                                .scaleEffect(highlightedAlbumID == album.id ? 1.05 : 1.0)
                                .animation(.spring(duration: 0.2), value: highlightedAlbumID)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { albumFrames[album.id] = geo.frame(in: .global) }
                                    .onChange(of: geo.frame(in: .global)) { albumFrames[album.id] = geo.frame(in: .global) }
                            }
                        )
                        .disabled(isDragging)
                        .contextMenu {
                            Button(role: .destructive) {
                                albumToDelete = album
                                showDeleteAlbumAlert = true
                            } label: {
                                Label("Delete Album", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(width: 130)

        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { }
        }
        .onAppear {
            photoManager.requestPermissionAndLoad()
        }
        .navigationDestination(isPresented: $showUnorganizedGrid) {
            UnorganizedGridView(assets: todayUnorganized, date: photoManager.selectedDate)
                .environmentObject(albumStore)
                .environmentObject(photoManager)
        }
        .alert("Delete Photo?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let asset = topAsset {
                    photoManager.deleteAsset(asset) { _ in }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the photo from your Photos library.")
        }
        .alert("Delete Album?", isPresented: $showDeleteAlbumAlert, presenting: albumToDelete) { album in
            Button("Delete", role: .destructive) {
                albumStore.deleteAlbum(id: album.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { album in
            Text("\"\(album.albumName)\" will be deleted. Photos inside won't be deleted from your library.")
        }
    }
}

// MARK: - UnorganizedGridView

struct UnorganizedGridView: View {
    let assets: [PHAsset]
    let date: Date

    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    @State private var selectedIndex: Int? = nil

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 100)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green.opacity(0.6))
                    Text("All organized!")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(assets.indices, id: \.self) { index in
                        Button {
                            selectedIndex = index
                        } label: {
                            AssetThumbnailView(asset: assets[index])
                                .frame(
                                    width: UIScreen.main.bounds.width / 3,
                                    height: UIScreen.main.bounds.width / 3
                                )
                                .clipped()
                        }
                    }
                }
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(
            get: { selectedIndex.map { SelectedIndex(value: $0) } },
            set: { selectedIndex = $0?.value }
        )) { selected in
            ShowPicture(assets: assets, currentIndex: selected.value)
        }
    }
}

// MARK: - HORIZONTAL CALENDER

struct HorizontalCalendarView: View {
    @EnvironmentObject var photoManager: PhotoLibraryManager
    @EnvironmentObject var albumStore: AlbumStore

    let daysRange = -30...30

    var dates: [Date] {
        let calendar = Calendar.current
        let base = photoManager.selectedDate

        return daysRange.compactMap {
            calendar.date(byAdding: .day, value: $0, to: base)
        }
    }

    func status(for date: Date) -> DayStatus {
        let calendar = Calendar.current

        let allAssets = photoManager.mediaItems.filter {
            calendar.isDate($0.creationDate ?? Date(), inSameDayAs: date)
        }
        if allAssets.isEmpty { return .noPhotos }

        let unorganizedAssets = photoManager.unorganizedAssets(albums: albumStore.albums)
        let hasUnorganized = unorganizedAssets.contains {
            calendar.isDate($0.creationDate ?? Date(), inSameDayAs: date)
        }

        return hasUnorganized ? .needsAttention : .organized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            

            Text(photoManager.selectedDate.formatted(.dateTime.month(.wide).year()))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(dates), id: \.self) { date in
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: photoManager.selectedDate)
                        let isToday = Calendar.current.isDateInToday(date)
                        
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.day()))
                                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(isSelected ? Color.accentColor : Color.clear)
                                )
                            
                            Circle()
                                .fill(dotColor(for: status(for: date)))
                                .frame(width: 5, height: 5)
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut) {
                                photoManager.selectedDate = date
                            }
                        }
                    }
                }
//                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
        }
    }
    func dotColor(for status: DayStatus) -> Color {
        switch status {
        case .noPhotos: return .clear
        case .organized: return .green
        case .needsAttention: return Color.orange
        }
    }
}
enum DayStatus {
    case noPhotos
    case organized
    case needsAttention
}

#Preview {
    AlbumView()
}
