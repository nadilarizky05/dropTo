import Foundation
import Combine
import Photos
import UIKit
import SwiftUI

//============================================================================
// SERVICE: PHOTO LIBRARY
//============================================================================
// INI SINGLETON CLASS YANG NGATUR SEMUA AKSES KE PHOTOS LIBRARY DEVICE
// SEMUA OPERASI BACA/TULIS/HAPUS FOTO/VIDEO LEWAT SERVICE INI
// PAKE PHOTOKIT FRAMEWORK DARI APPLE

@MainActor
final class PhotoLibraryService: ObservableObject {
    
    //============================================================================
    // SINGLETON INSTANCE
    //============================================================================
    // SHARED = INSTANCE GLOBAL, DIPAKE DI SELURUH APP
    
    static let shared = PhotoLibraryService()
    
    //============================================================================
    // PUBLISHED PROPERTIES
    //============================================================================
    // STATUS IZIN AKSES PHOTOS (NOTDETERMINED, AUTHORIZED, DENIED, DLL)
    
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    //============================================================================
    // INITIALIZER (PRIVATE, KARENA SINGLETON)
    //============================================================================
    // CEK STATUS IZIN SAAT PERTAMA KALI DIINISIALISASI
    
    private init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    //============================================================================
    // FUNCTION 1: MINTA IZIN AKSES PHOTOS
    //============================================================================
    // TAMPILKAN POPUP IZIN KE USER KALAU BELUM PERNAH MINTA IZIN SEBELUMNYA
    
    func requestAccessIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
            }
        }
    }
    
    //============================================================================
    // COMPUTED PROPERTY: CEK APAKAH SUDAH PUNYA IZIN
    //============================================================================
    // RETURN TRUE KALAU USER SUDAH KASIH IZIN FULL ATAU LIMITED
    
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }
    
    //============================================================================
    // FUNCTION 2: AMBIL SEMUA FOTO/VIDEO DI DEVICE
    //============================================================================
    // RETURN ARRAY PHASSET (FOTO/VIDEO) DIURUTKAN DARI YANG TERBARU
    
    func fetchAllAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
    
    //============================================================================
    // FUNCTION 3: AMBIL FOTO/VIDEO BERDASARKAN LIST IDENTIFIER
    //============================================================================
    // TERIMA ARRAY STRING IDENTIFIER → RETURN ARRAY PHASSET DIURUTKAN DARI TERBARU
    
    func fetchAssets(withIdentifiers identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        assets.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        return assets
    }
    
    //============================================================================
    // FUNCTION 4: SIMPAN FOTO BARU KE PHOTOS LIBRARY
    //============================================================================
    // TERIMA UIIMAGE → SIMPAN KE LIBRARY → RETURN IDENTIFIER (ATAU NIL KALAU GAGAL)
    
    func saveNewPhoto(_ image: UIImage) async -> String? {
        var newIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                newIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            return newIdentifier
        } catch {
            print("Could not save photo: \(error)")
            return nil
        }
    }
    
    //============================================================================
    // FUNCTION 5: SIMPAN VIDEO BARU KE PHOTOS LIBRARY
    //============================================================================
    // TERIMA FILE URL VIDEO → SIMPAN KE LIBRARY → RETURN IDENTIFIER (ATAU NIL KALAU GAGAL)
    
    func saveNewVideo(fileURL: URL) async -> String? {
        var newIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL) else { return }
                newIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            return newIdentifier
        } catch {
            print("Could not save video: \(error)")
            return nil
        }
    }
    
    //============================================================================
    // FUNCTION 6: HAPUS FOTO/VIDEO PERMANEN DARI DEVICE
    //============================================================================
    // TERIMA LIST IDENTIFIER → HAPUS PERMANEN (BEDA DARI SOFT DELETE KE TRASH)
    // RETURN TRUE KALAU BERHASIL, FALSE KALAU GAGAL (MISAL USER TOLAK PERMISSION)
    
    func permanentlyDelete(identifiers: [String]) async -> Bool {
        guard !identifiers.isEmpty else { return false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            print("Could not delete photos: \(error)")
            return false
        }
    }
    
    //============================================================================
    // FUNCTION 7: LOAD THUMBNAIL FOTO/VIDEO
    //============================================================================
    // LOAD GAMBAR KECIL (THUMBNAIL) BUAT GRID, LEBIH CEPAT DAN HEMAT MEMORY
    
    func loadThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    //============================================================================
    // FUNCTION 8: LOAD FULL RESOLUTION IMAGE
    //============================================================================
    // LOAD GAMBAR FULL QUALITY BUAT DITAMPILKAN DETAIL VIEW, UKURAN MAKSIMAL, KUALITAS TINGGI
    
    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    //============================================================================
    // FUNCTION 9: TOGGLE FAVORITE (LOVE/UNLIKE)
    //============================================================================
    // KALAU FOTO SUDAH FAVORITE → UNFAVORITE, KALAU BELUM → FAVORITE
    
    func toggleFavorite(for asset: PHAsset) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = !asset.isFavorite
            }
        } catch {
            print("Could not toggle favorite: \(error)")
        }
    }
}
