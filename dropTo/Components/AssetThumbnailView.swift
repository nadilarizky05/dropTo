import SwiftUI
import Photos

struct AssetThumbnailView: View {
    let asset: PHAsset
    var cornerRadius: CGFloat = 0

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var imageIdentifier: String?

    @State private var side: CGFloat = 0

    private struct LoadKey: Hashable {
        let identifier: String
        let bucket: Int
    }

    private var loadKey: LoadKey {
        LoadKey(identifier: asset.localIdentifier, bucket: Int((side * displayScale / 50).rounded(.up)))
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle()
                        .fill(Color(.systemGray5))

                    if let image, imageIdentifier == asset.localIdentifier {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay {
                if asset.mediaType == .video {
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                                .padding(6)

                            Spacer()
                        }

                        Spacer()

                        HStack {
                            Spacer()

                            Text(durationString(asset.duration))
                                .font(.system(size: 13, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                                .padding(.trailing, 7)
                        }
                        .padding(.bottom, 5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = $0 }
            .task(id: loadKey) {
                guard side > 0 else { return }
                let pixelSize = CGSize(width: side * displayScale, height: side * displayScale)
                if let loaded = await PhotoLibraryService.shared.loadThumbnail(for: asset, targetSize: pixelSize) {
                    image = loaded
                    imageIdentifier = asset.localIdentifier
                }
            }
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
