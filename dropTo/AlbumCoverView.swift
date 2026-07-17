//
//  AlbumCoverView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//

import SwiftUI
import Photos

struct AlbumCoverView: View {
    let album: AlbumProp
    let photoManager: PhotoLibraryManager
    @State private var coverImage: UIImage? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipped()
                    .cornerRadius(8)
            }
            else {
                Image("empty-photo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipped()
                    .cornerRadius(8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(album.albumName)
                    .font(.caption2).bold()
                    .foregroundStyle(.white)
                Text("\(album.numberOfPhotos) photos")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(4)
            .background(Color.black.opacity(0.4))
            .cornerRadius(4)
            .padding(4)
        }
        .onAppear { loadCover() }
        .onChange(of: album.coverAssetIdentifier) { loadCover() }
        .onChange(of: album.numberOfPhotos) { loadCover() }
    }

    func loadCover() {
        guard let id = album.coverAssetIdentifier else {
            coverImage = nil
            return
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else {
            coverImage = nil
            return
        }
        photoManager.loadImage(for: asset) { img in coverImage = img }
    }
}
