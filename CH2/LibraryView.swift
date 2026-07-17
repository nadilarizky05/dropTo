//
//  LibraryView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//

import SwiftUI
import Photos

struct LibraryView: View {
    @EnvironmentObject var photoManager: PhotoLibraryManager
    @State private var showCamera = false
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photoManager.mediaItems, id: \.localIdentifier) { asset in
                            AssetThumbnailView(asset: asset)
                                .frame(width: UIScreen.main.bounds.width / 4,
                                       height: UIScreen.main.bounds.width / 4)
                                .clipped()
                        }
                    }
                }
                
                // Floating camera button
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding(24)
            }
            .navigationTitle("Library")
            .onAppear {
                photoManager.requestPermissionAndLoad()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(isPresented: $showCamera) { image in
                    photoManager.saveImageToLibrary(image) {}
                } onCaptureVideo: { url in
                    photoManager.saveVideoToLibrary(url: url) {}
                }
            }
        }
    }
}

// Komponen thumbnail per asset
struct AssetThumbnailView: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
            
            // Icon video
            if asset.mediaType == .video {
                Image(systemName: "play.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .onAppear {
            let size = CGSize(width: 200, height: 200)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: nil
            ) { image, _ in
                thumbnail = image
            }
        }
    }
}

#Preview {
    LibraryView()
}
