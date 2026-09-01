import SwiftUI

//============================================================================
// SHEET: MOVE FOTO/VIDEO KE ALBUM LAIN
//============================================================================
// SHEET POPUP LIST ALBUM TUJUAN, PILIH ALBUM → FOTO DIPINDAH → SHEET TUTUP

struct MoveToAlbumSheet: View {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    
    let sourceAlbum: Album?              // ALBUM ASAL (NIL KALAU DARI UNORGANIZED)
    let identifiersToMove: [String]      // LIST FOTO/VIDEO YANG MAU DIPINDAH
    let dataService: DataService         // AKSES DATABASE
    var onMoved: () -> Void              // CALLBACK SAAT BERHASIL MOVE
    
    @Environment(\.dismiss) private var dismiss       // TUTUP SHEET
    @State private var showNewAlbumSheet = false      // FLAG SHEET BUAT ALBUM BARU
    
    //============================================================================
    // COMPUTED PROPERTY: DESTINATION ALBUMS
    //============================================================================
    // LIST ALBUM TUJUAN (EXCLUDE ALBUM ASAL)
    
    private var destinationAlbums: [Album] {
        dataService.fetchAlbums().filter { $0.id != sourceAlbum?.id }
    }
    
    //============================================================================
    // BODY: MAIN UI
    //============================================================================

    var body: some View {
        NavigationStack {
            Group {
                // KALAU GAK ADA ALBUM LAIN → TAMPILKAN EMPTY STATE
                if destinationAlbums.isEmpty {
                    ContentUnavailableView(
                        "No Other Albums",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Create an album to move photos into.")
                    )
                } else {
                    // TAMPILKAN LIST ALBUM YANG BISA DIPILIH
                    List(destinationAlbums) { album in
                        Button {
                            // MOVE FOTO KE ALBUM YANG DIPILIH
                            dataService.moveAssets(identifiersToMove, from: sourceAlbum, to: album)
                            onMoved()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(album.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(album.assetIdentifiers.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                createAlbumButton
            }
            .sheet(isPresented: $showNewAlbumSheet) {
                // SHEET BUAT ALBUM BARU, SETELAH DIBUAT LANGSUNG MOVE KE SANA
                NewAlbumSheet(dataService: dataService) { newAlbum in
                    dataService.moveAssets(identifiersToMove, from: sourceAlbum, to: newAlbum)
                    onMoved()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    //============================================================================
    // SUBVIEW: CREATE ALBUM BUTTON
    //============================================================================
    // TOMBOL BIRU DI BAWAH SHEET BUAT BIKIN ALBUM BARU
    
    private var createAlbumButton: some View {
        Button {
            showNewAlbumSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Create New Album")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
