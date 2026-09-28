import Foundation
import SwiftData

@Model
final class Album {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    // REPRESENTASI DATA ALBUM DI SWIFTDATA - PUNYA ID, NAMA, TANGGAL, DAN LIST FOTO/VIDEO
    
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var assetIdentifiers: [String]
    var isPinned: Bool
    
    //============================================================================
    // INITIALIZER
    //============================================================================
    // BUAT ALBUM BARU DENGAN PARAMETER DEFAULT
    
    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), assetIdentifiers: [String] = [], isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.assetIdentifiers = assetIdentifiers
        self.isPinned = isPinned
    }
}
