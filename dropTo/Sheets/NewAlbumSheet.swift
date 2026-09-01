import SwiftUI

//============================================================================
// SHEET: BUAT ALBUM BARU
//============================================================================
// SHEET COMPACT DARI BAWAH BUAT INPUT NAMA ALBUM

struct NewAlbumSheet: View {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    
    let dataService: DataService          // AKSES DATABASE
    var onCreate: ((Album) -> Void)?      // CALLBACK SAAT ALBUM DIBUAT
    
    @Environment(\.dismiss) private var dismiss // TUTUP SHEET
    @State private var albumTitle = ""          // NAMA ALBUM INPUT USER
    @FocusState private var isFocused: Bool     // AUTO FOCUS TEXTFIELD
    
    //============================================================================
    // BODY: MAIN UI
    //============================================================================
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Album Title", text: $albumTitle)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            createAlbum()
                        }
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createAlbum()
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
        .presentationDetents([.height(200)])  // FIXED HEIGHT 200PT (COMPACT!)
        .presentationDragIndicator(.visible)
    }
    
    //============================================================================
    // FUNCTION: CREATE ALBUM
    //============================================================================
    // HELPER FUNCTION BUAT BIKIN ALBUM (DIPANGGIL SAAT TAP CREATE ATAU SUBMIT)
    
    private func createAlbum() {
        let newAlbum = dataService.createAlbum(title: albumTitle.isEmpty ? "Untitled Album" : albumTitle)
        onCreate?(newAlbum)
        dismiss()
    }
}

