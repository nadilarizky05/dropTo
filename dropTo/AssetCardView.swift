//
//  AssetCardView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//

import SwiftUI
import Photos

struct AssetCardView: View {
    let asset: PHAsset
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                ProgressView()
            }
            if asset.mediaType == .video {
                Image(systemName: "play.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
        }
        .onAppear {
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 440, height: 600),
                contentMode: .aspectFill,
                options: nil
            ) { img, _ in image = img }
        }
    }
}
