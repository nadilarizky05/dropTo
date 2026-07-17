//
//  ItemModel.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 24/04/26.
//

import Foundation

struct AlbumProp: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let albumName: String
    var timeCreated: Date
    var projectType: String
    var numberOfPhotos: Int
    var assetIdentifiers: [String] = []
    var coverAssetIdentifier: String? = nil
    var favoriteIdentifiers: [String] = []
    
}

struct ImageProp: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let fileName: String
    var location: String
    var timeCreated: Date
    var width: Int
    var height: Int
}
