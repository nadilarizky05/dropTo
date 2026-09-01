import SwiftUI
import Photos

//============================================================================
// COMPONENT: ASSET THUMBNAIL VIEW
//============================================================================
// REUSABLE COMPONENT BUAT TAMPILKAN THUMBNAIL FOTO/VIDEO DI GRID

struct AssetThumbnailView: View {
    
    //============================================================================
    // PHASE 1: PROPERTIES
    //============================================================================
    //PHAsset (Foto/Video yg mau ditampilkan), image (untuk thumbnail)
    
    let asset: PHAsset
    var cornerRadius: CGFloat = 0
    
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width

            ZStack {
                // BACKGROUND + IMAGE
                ZStack {
                    Rectangle()
                        .fill(Color(.systemGray5))

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: side, height: side)
                .clipped()

                // VIDEO OVERLAY (PLAY ICON + DURATION)
                if asset.mediaType == .video {
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                                .padding(5)
                            
                            Spacer()
                        }
                        
                        Spacer()
                        
                        HStack {
                            Spacer()
                            
                            Text(durationString(asset.duration))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(.black.opacity(0.75))
                                )
                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                                .padding(.trailing, 7)
                        }
                        .padding(.bottom, 4)
                    }
                    .frame(width: side, height: side)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: asset.localIdentifier) {
                // LOAD THUMBNAIL DENGAN UKURAN SESUAI DISPLAY SCALE
                let pixelSize = CGSize(width: side * displayScale, height: side * displayScale)
                image = await PhotoLibraryService.shared.loadThumbnail(for: asset, targetSize: pixelSize)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    //============================================================================
    // PHASE 2: BUAT FUNCTION DURATION STRING
    //============================================================================
    // FORMAT DURASI VIDEO JADI "M:SS" (CONTOH: "3:45")
    
    private func durationString(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
