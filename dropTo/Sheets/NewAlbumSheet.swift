import SwiftUI

//============================================================================
// SHEET: BUAT ALBUM BARU
//============================================================================
// SHEET POPUP FORM INPUT NAMA ALBUM, TAP "CREATE" → BIKIN ALBUM DI DATABASE

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
                        // KALAU USER GAK ISI NAMA, DEFAULT "UNTITLED ALBUM"
                        let newAlbum = dataService.createAlbum(title: albumTitle.isEmpty ? "Untitled Album" : albumTitle)
                        onCreate?(newAlbum)
                        dismiss()
                    }
                }
            }
            .onAppear {
                // AUTO FOCUS KE TEXTFIELD BIAR USER LANGSUNG BISA NGETIK
                isFocused = true
            }
        }
    }
}

#Preview {
    NewAlbumSheet(dataService: DataService())
}
