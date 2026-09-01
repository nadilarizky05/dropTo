import Foundation
import SwiftData

@Model
final class DeletedItem {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    // REPRESENTASI DATA TRASH - PUNYA ID FOTO/VIDEO, TANGGAL DIHAPUS, DAN ASAL ALBUM (BUAT RESTORE)
    
    @Attribute(.unique) var assetIdentifier: String
    var deletedAt: Date
    var sourceAlbumID: UUID?
    
    //============================================================================
    // INITIALIZER
    //============================================================================
    // BUAT DELETED ITEM BARU SAAT USER HAPUS FOTO/VIDEO
    
    init(assetIdentifier: String, deletedAt: Date = Date(), sourceAlbumID: UUID? = nil) {
        self.assetIdentifier = assetIdentifier
        self.deletedAt = deletedAt
        self.sourceAlbumID = sourceAlbumID
    }
}
