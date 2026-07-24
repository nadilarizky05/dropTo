//
//  AssetThumbnailView.swift
//  dropTo
//
//  A small reusable piece: "given a PHAsset, show me a neat square
//  thumbnail for it". Used everywhere in grids (Home covers, album
//  grids, Recently Deleted grid) so every tile looks consistent —
//  just like the real Photos app.
//

import SwiftUI
import Photos

struct AssetThumbnailView: View {
    let asset: PHAsset
    var cornerRadius: CGFloat = 0

    // The modern, non-deprecated way to get the screen's pixel density
    // (replaces the old `UIScreen.main.scale`).
    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width // width decides the square size

            ZStack {
                // Placeholder shimmer while the real photo loads.
                Rectangle()
                    .fill(Color(.systemGray5))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }

                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(durationString(asset.duration))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                                .padding(5)
                        }
                    }
                }
            }
            .frame(width: side, height: side) // always 1:1, regardless of the original photo's shape
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: asset.localIdentifier) {
                let pixelSize = CGSize(width: side * displayScale, height: side * displayScale)
                image = await PhotoLibraryManager.shared.loadThumbnail(for: asset, targetSize: pixelSize)
            }
        }
        .aspectRatio(1, contentMode: .fit) // reserves a perfect square cell in the grid
    }

    /// Formats seconds as "m:ss", e.g. 163 seconds -> "2:43".
    private func durationString(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
