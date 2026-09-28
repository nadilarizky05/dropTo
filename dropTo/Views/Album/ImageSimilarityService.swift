//
//  ImageSimilarityService.swift
//  dropTo
//
//  Created on 22/09/26.
//
//============================================================================
// SERVICE: IMAGE SIMILARITY
//============================================================================
// SERVICE UNTUK MENGANALISIS DAN MENGELOMPOKKAN FOTO BERDASARKAN KEMIRIPAN VISUAL
// MENGGUNAKAN VISION FRAMEWORK (FEATURE PRINT)
//
// CARA KERJA:
// 1. ANALISIS SETIAP FOTO: blur, category (handwriting, screenshot, document, dll)
// 2. CARI FOTO-FOTO YANG SIMILAR (visual similarity)
// 3. KELOMPOKKAN FOTO SIMILAR BERDASARKAN KATEGORI (blurry, handwriting, dll)
// 4. URUTKAN GRUP: BERDASARKAN TANGGAL FOTO TERBARU (NEWEST FIRST)
// 5. URUTKAN FOTO DI DALAM GRUP: BERDASARKAN TANGGAL (NEWEST FIRST)
//
// CONTOH OUTPUT (URUTAN BERDASARKAN TANGGAL TERBARU):
// ┌─────────────────────────────────────────────┐
// │ 📸 125 Other Photos                        │ <- FOTO BARU HARI INI (NEWEST)
// │    Tap to review                            │
// ├─────────────────────────────────────────────┤
// │ 📱 8 Similar Screenshots                   │ <- FOTO KEMARIN
// │    Tap to review                            │
// ├─────────────────────────────────────────────┤
// │ 📷 5 Similar Blurry Photos                 │ <- FOTO 3 HARI LALU
// │    Tap to review                            │
// ├─────────────────────────────────────────────┤
// │ ✍️ 3 Similar Handwriting                   │ <- FOTO MINGGU LALU
// │    Tap to review                            │
// ├─────────────────────────────────────────────┤
// │ 📄 4 Similar Documents                     │ <- FOTO BULAN LALU (OLDEST)
// │    Tap to review                            │
// └─────────────────────────────────────────────┘

import SwiftUI
import Photos
import Vision
import Combine

//============================================================================
// ENUM: IMAGE CATEGORY
//============================================================================
// KATEGORI FOTO BERDASARKAN KARAKTERISTIK

enum ImageCategory: String, Codable {
    case blurry = "Blurry Photos"           // FOTO BLUR/TIDAK FOKUS
    case handwriting = "Handwriting"        // TULISAN TANGAN
    case screenshot = "Screenshots"         // SCREENSHOT
    case document = "Documents"             // DOKUMEN/TEXT
    case lowQuality = "Low Quality"         // KUALITAS RENDAH
    case duplicate = "Similar Photos"       // FOTO MIRIP
    case normal = "Other Photos"            // FOTO NORMAL
    
    var priority: Int {
        // URUTAN PRIORITAS UNTUK DITAMPILKAN (SMALLER = HIGHER PRIORITY)
        switch self {
        case .blurry: return 1
        case .lowQuality: return 2
        case .handwriting: return 3
        case .screenshot: return 4
        case .document: return 5
        case .duplicate: return 6
        case .normal: return 7
        }
    }
    
    var icon: String {
        switch self {
        case .blurry: return "camera.filters"
        case .handwriting: return "pencil.and.scribble"
        case .screenshot: return "square.on.square"
        case .document: return "doc.text"
        case .lowQuality: return "exclamationmark.triangle"
        case .duplicate: return "photo.stack"
        case .normal: return "photo"
        }
    }
}

//============================================================================
// STRUCT: IMAGE METADATA
//============================================================================
// METADATA UNTUK SETIAP FOTO YANG DIANALISIS

struct ImageMetadata: Codable {
    let assetIdentifier: String
    let featurePrintData: Data?
    let category: ImageCategory
    let blurScore: Float
    let analyzedAt: Date
    
    // KONVERSI KE/DARI VNFeaturePrintObservation
    var featurePrint: VNFeaturePrintObservation? {
        guard let data = featurePrintData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
    
    static func from(asset: PHAsset, feature: VNFeaturePrintObservation?, category: ImageCategory, blurScore: Float) -> ImageMetadata {
        let data = feature.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        return ImageMetadata(
            assetIdentifier: asset.localIdentifier,
            featurePrintData: data,
            category: category,
            blurScore: blurScore,
            analyzedAt: Date()
        )
    }
}

//============================================================================
// STRUCT: IMAGE GROUP
//============================================================================
// REPRESENTASI SATU GRUP FOTO YANG MIRIP

struct ImageGroup: Identifiable {
    let id = UUID()
    let category: ImageCategory
    let assets: [PHAsset]
    let representativeAsset: PHAsset  // FOTO YANG MEWAKILI GRUP
    let averageFeature: VNFeaturePrintObservation?
    
    var title: String {
        let count = assets.count
        
        // FORMAT: "5 Similar Blurry Photos" atau "3 Similar Handwriting"
        switch category {
        case .blurry:
            return count == 1 ? "1 Blurry Photo" : "\(count) Similar Photos"
        case .handwriting:
            return count == 1 ? "1 Handwriting" : "\(count) Similar Handwriting"
        case .screenshot:
            return count == 1 ? "1 Screenshot" : "\(count) Similar Screenshots"
        case .document:
            return count == 1 ? "1 Document" : "\(count) Similar Documents"
        case .lowQuality:
            return count == 1 ? "1 Low Quality Photo" : "\(count) Similar Low Quality Photos"
        case .duplicate:
            return count == 1 ? "1 Similar Photo" : "\(count) Similar Photos"
        case .normal:
            return count == 1 ? "1 Other Photo" : "\(count) Other Photos"
        }
    }
    
    var subtitle: String {
        // SUBTITLE: TAP TO REVIEW & DELETE
        return "Tap to review"
    }
    
    var icon: String {
        return category.icon
    }
    
    // TANGGAL FOTO TERBARU DI GRUP (UNTUK SORTING)
    var mostRecentDate: Date {
        return assets.compactMap { $0.creationDate }.max() ?? Date.distantPast
    }
}

//============================================================================
// CLASS: IMAGE SIMILARITY SERVICE
//============================================================================

@MainActor
class ImageSimilarityService: ObservableObject {
    
    static let shared = ImageSimilarityService()
    
    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    
    // CACHE UNTUK METADATA FOTO YANG SUDAH DIANALISIS
    private var metadataCache: [String: ImageMetadata] = [:]
    
    // THRESHOLD UNTUK MENENTUKAN KEMIRIPAN (0.0 - 1.0)
    private let similarityThreshold: Float = 0.35
    
    // THRESHOLD UNTUK BLUR DETECTION
    private let blurThreshold: Float = 0.3
    
    // FILE PATH UNTUK PERSISTENT STORAGE
    private var cacheFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("image_analysis_cache.json")
    }
    
    //============================================================================
    // INIT
    //============================================================================
    
    init() {
        loadCacheFromDisk()
    }
    
    //============================================================================
    // FUNCTION: ANALYZE AND GROUP ASSETS
    //============================================================================
    // ANALISIS SEMUA FOTO DAN KELOMPOKKAN BERDASARKAN KEMIRIPAN + KATEGORI
    
    func analyzeAndGroupAssets(_ assets: [PHAsset]) async -> [ImageGroup] {
        guard !assets.isEmpty else { return [] }
        
        isAnalyzing = true
        progress = 0
        statusMessage = "Checking for new photos..."
        
        // IDENTIFIKASI FOTO YANG BELUM DIANALISIS
        let newAssets = assets.filter { asset in
            // CEK APAKAH FOTO INI SUDAH PERNAH DIANALISIS
            if let metadata = metadataCache[asset.localIdentifier] {
                // CEK APAKAH FOTO MASIH SAMA (BERDASARKAN MODIFICATION DATE)
                return asset.modificationDate ?? Date.distantPast > metadata.analyzedAt
            }
            return true
        }
        
        if newAssets.isEmpty {
            // SEMUA FOTO SUDAH DIANALISIS, GUNAKAN DATA CACHE
            statusMessage = "Loading from cache..."
            progress = 0.5
            
            let groups = await buildGroupsFromCache(assets)
            
            isAnalyzing = false
            progress = 1.0
            statusMessage = "Done!"
            
            return groups
        }
        
        // ANALISIS FOTO BARU SAJA
        statusMessage = "Analyzing \(newAssets.count) new photos..."
        await analyzeNewAssets(newAssets)
        
        // KELOMPOKKAN SEMUA FOTO (TERMASUK YANG LAMA)
        statusMessage = "Grouping photos..."
        let groups = await buildGroupsFromCache(assets)
        
        // SIMPAN CACHE KE DISK
        saveCacheToDisk()
        
        isAnalyzing = false
        progress = 1.0
        statusMessage = "Done!"
        
        return groups
    }
    
    //============================================================================
    // FUNCTION: ANALYZE NEW ASSETS
    //============================================================================
    // ANALISIS FOTO BARU DAN SIMPAN KE CACHE
    
    private func analyzeNewAssets(_ assets: [PHAsset]) async {
        for (index, asset) in assets.enumerated() {
            // EKSTRAK FEATURE PRINT
            let feature = await extractFeaturePrint(from: asset)
            
            // DETEKSI KATEGORI DAN BLUR
            let (category, blurScore) = await detectCategoryAndQuality(for: asset)
            
            // SIMPAN METADATA
            let metadata = ImageMetadata.from(
                asset: asset,
                feature: feature,
                category: category,
                blurScore: blurScore
            )
            metadataCache[asset.localIdentifier] = metadata
            
            // UPDATE PROGRESS
            await MainActor.run {
                progress = Double(index + 1) / Double(assets.count) * 0.8
                statusMessage = "Analyzing \(index + 1)/\(assets.count)..."
            }
        }
    }
    
    //============================================================================
    // FUNCTION: BUILD GROUPS FROM CACHE
    //============================================================================
    // BUAT GRUP DARI DATA CACHE YANG SUDAH ADA
    
    private func buildGroupsFromCache(_ assets: [PHAsset]) async -> [ImageGroup] {
        var duplicateCandidates: [(asset: PHAsset, feature: VNFeaturePrintObservation, category: ImageCategory, blurScore: Float)] = []
        
        // KUMPULKAN SEMUA FOTO UNTUK DETEKSI DUPLIKAT
        for asset in assets {
            guard let metadata = metadataCache[asset.localIdentifier] else { continue }
            
            if let feature = metadata.featurePrint {
                duplicateCandidates.append((
                    asset: asset,
                    feature: feature,
                    category: metadata.category,
                    blurScore: metadata.blurScore
                ))
            }
        }
        
        // DETEKSI FOTO DUPLIKAT/MIRIP DENGAN KATEGORI
        let duplicateGroupsWithCategories = await findDuplicateGroupsWithCategories(duplicateCandidates)
        
        // KONVERSI KE IMAGE GROUPS
        var result: [ImageGroup] = []
        var usedAssets: Set<String> = []
        
        // TAMBAHKAN DUPLICATE GROUPS (YANG ADA SIMILAR)
        for (category, groupAssets) in duplicateGroupsWithCategories {
            // SORT ASSETS DI DALAM GRUP BERDASARKAN TANGGAL (NEWEST FIRST)
            let sortedAssets = groupAssets.sorted { a, b in
                let dateA = a.creationDate ?? Date.distantPast
                let dateB = b.creationDate ?? Date.distantPast
                return dateA > dateB
            }
            
            // PILIH REPRESENTATIVE: YANG KUALITAS PALING JELEK (BLUR TERTINGGI)
            let representative = sortedAssets.max(by: { a, b in
                let scoreA = metadataCache[a.localIdentifier]?.blurScore ?? 0
                let scoreB = metadataCache[b.localIdentifier]?.blurScore ?? 0
                return scoreA < scoreB
            }) ?? sortedAssets.first!
            
            let group = ImageGroup(
                category: category,
                assets: sortedAssets,
                representativeAsset: representative,
                averageFeature: metadataCache[representative.localIdentifier]?.featurePrint
            )
            result.append(group)
            
            // TANDAI FOTO SUDAH DIGUNAKAN
            for asset in sortedAssets {
                usedAssets.insert(asset.localIdentifier)
            }
        }
        
        // KUMPULKAN SISA FOTO (YANG TIDAK PUNYA SIMILAR) KE SATU GRUP "OTHER PHOTOS"
        var remainingAssets: [PHAsset] = []
        for asset in assets {
            if !usedAssets.contains(asset.localIdentifier) {
                remainingAssets.append(asset)
            }
        }
        
        // SORT REMAINING ASSETS BERDASARKAN TANGGAL (NEWEST FIRST)
        remainingAssets.sort { a, b in
            let dateA = a.creationDate ?? Date.distantPast
            let dateB = b.creationDate ?? Date.distantPast
            return dateA > dateB
        }
        
        // TAMBAHKAN GRUP "OTHER PHOTOS" JIKA ADA
        if !remainingAssets.isEmpty {
            let representative = remainingAssets.first!
            let group = ImageGroup(
                category: .normal,
                assets: remainingAssets,
                representativeAsset: representative,
                averageFeature: metadataCache[representative.localIdentifier]?.featurePrint
            )
            result.append(group)
        }
        
        // SORT: BERDASARKAN TANGGAL FOTO TERBARU DI GRUP (NEWEST FIRST)
        return result.sorted { lhs, rhs in
            // URUTKAN BERDASARKAN FOTO TERBARU DI GRUP
            return lhs.mostRecentDate > rhs.mostRecentDate
        }
    }
    
    //============================================================================
    // FUNCTION: FIND DUPLICATE GROUPS WITH CATEGORIES
    //============================================================================
    // CARI FOTO-FOTO YANG MIRIP/DUPLIKAT DAN KELOMPOKKAN BERDASARKAN KATEGORI
    
    private func findDuplicateGroupsWithCategories(
        _ candidates: [(asset: PHAsset, feature: VNFeaturePrintObservation, category: ImageCategory, blurScore: Float)]
    ) async -> [(category: ImageCategory, assets: [PHAsset])] {
        guard !candidates.isEmpty else { return [] }
        
        var groups: [(category: ImageCategory, assets: [PHAsset])] = []
        var processed: Set<String> = []
        
        for (index, item) in candidates.enumerated() {
            guard !processed.contains(item.asset.localIdentifier) else { continue }
            
            var groupAssets: [PHAsset] = []
            var groupCategories: [ImageCategory] = []
            
            // CARI FOTO LAIN YANG MIRIP
            for other in candidates[index...] {
                guard !processed.contains(other.asset.localIdentifier) else { continue }
                
                do {
                    var distance: Float = 0.0
                    try item.feature.computeDistance(&distance, to: other.feature)
                    
                    if distance < similarityThreshold {
                        groupAssets.append(other.asset)
                        groupCategories.append(other.category)
                        processed.insert(other.asset.localIdentifier)
                    }
                } catch {
                    continue
                }
            }
            
            // HANYA TAMBAHKAN JIKA ADA LEBIH DARI 1 FOTO (BERARTI ADA DUPLIKAT)
            if groupAssets.count > 1 {
                // TENTUKAN KATEGORI GRUP BERDASARKAN KATEGORI DOMINAN YANG PRIORITASNYA TINGGI
                let dominantCategory = groupCategories.min(by: { $0.priority < $1.priority }) ?? .duplicate
                groups.append((category: dominantCategory, assets: groupAssets))
            }
        }
        
        return groups
    }
    
    //============================================================================
    // FUNCTION: DETECT CATEGORY AND QUALITY
    //============================================================================
    // DETEKSI KATEGORI FOTO DAN KUALITASNYA
    
    private func detectCategoryAndQuality(for asset: PHAsset) async -> (ImageCategory, Float) {
        guard let image = await requestImage(for: asset) else {
            return (.normal, 0)
        }
        
        // DETEKSI BLUR
        let blurScore = await detectBlur(cgImage: image)
        
        // DETEKSI KATEGORI MENGGUNAKAN VISION
        let category = await detectCategory(cgImage: image, blurScore: blurScore)
        
        return (category, blurScore)
    }
    
    //============================================================================
    // FUNCTION: DETECT BLUR
    //============================================================================
    // DETEKSI TINGKAT BLUR MENGGUNAKAN LAPLACIAN VARIANCE
    
    private func detectBlur(cgImage: CGImage) async -> Float {
        // KONVERSI CGImage KE CIImage
        let ciImage = CIImage(cgImage: cgImage)
        
        // BUAT GRAYSCALE IMAGE
        guard let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono") else {
            return 0
        }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        
        guard let grayscaleImage = grayscaleFilter.outputImage else {
            return 0
        }
        
        // APPLY LAPLACIAN EDGE DETECTION
        guard let laplacianFilter = CIFilter(name: "CIEdges") else {
            return 0
        }
        laplacianFilter.setValue(grayscaleImage, forKey: kCIInputImageKey)
        laplacianFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        guard let edgesImage = laplacianFilter.outputImage else {
            return 0
        }
        
        // HITUNG VARIANCE DARI EDGE IMAGE
        let context = CIContext()
        let extent = edgesImage.extent
        
        // RESIZE UNTUK PERFORMANCE (TIDAK PERLU FULL RESOLUTION)
        let scale: CGFloat = 0.25
        let scaledExtent = CGRect(
            x: 0,
            y: 0,
            width: extent.width * scale,
            height: extent.height * scale
        )
        
        guard let bitmap = context.createCGImage(edgesImage, from: extent) else {
            return 0
        }
        
        // HITUNG VARIANCE MENGGUNAKAN CIAREAAVERAGES
        guard let areaAverage = CIFilter(name: "CIAreaAverage") else {
            return 0
        }
        areaAverage.setValue(edgesImage, forKey: kCIInputImageKey)
        areaAverage.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        
        guard let outputImage = areaAverage.outputImage else {
            return 0
        }
        
        var bitmap2 = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap2, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        // VARIANCE SEBAGAI INDIKATOR BLUR (SEMAKIN TINGGI = SEMAKIN SHARP)
        let variance = Float(bitmap2[0]) / 255.0
        
        // RETURN BLUR SCORE (SEMAKIN TINGGI = SEMAKIN BLUR)
        return 1.0 - variance
    }
    
    //============================================================================
    // FUNCTION: DETECT CATEGORY
    //============================================================================
    // DETEKSI KATEGORI FOTO MENGGUNAKAN VISION CLASSIFICATION
    
    private func detectCategory(cgImage: CGImage, blurScore: Float) async -> ImageCategory {
        // CEK BLUR TERLEBIH DAHULU
        if blurScore > blurThreshold {
            return .blurry
        }
        
        let request = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // DETEKSI TEXT
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        
        do {
            try request.perform([textRequest])
            
            if let observations = textRequest.results, !observations.isEmpty {
                let totalConfidence = observations.reduce(0.0) { $0 + $1.confidence }
                let avgConfidence = totalConfidence / Float(observations.count)
                
                // BANYAK TEXT DENGAN CONFIDENCE TINGGI
                if avgConfidence > 0.5 {
                    // ANALISIS APAKAH HANDWRITING ATAU PRINTED TEXT
                    let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
                    
                    // HEURISTIC: HANDWRITING BIASANYA PUNYA CONFIDENCE LEBIH RENDAH
                    if avgConfidence < 0.7 || isLikelyHandwriting(recognizedText) {
                        return .handwriting
                    } else {
                        return .document
                    }
                }
            }
        } catch {
            print("❌ Error detecting text: \(error)")
        }
        
        // DETEKSI SCREENSHOT (BIASANYA PUNYA ASPECT RATIO DEVICE)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let aspectRatio = width / height
        
        // COMMON DEVICE ASPECT RATIOS
        let commonRatios: [CGFloat] = [
            9.0/16.0,  // iPhone portrait
            9.0/19.5,  // Modern iPhone
            16.0/9.0,  // Landscape
            3.0/4.0,   // iPad
            4.0/3.0    // iPad landscape
        ]
        
        for ratio in commonRatios {
            if abs(aspectRatio - ratio) < 0.05 {
                // MUNGKIN SCREENSHOT, CEK LAGI DENGAN TEXT DETECTION
                if !textRequest.results!.isEmpty {
                    return .screenshot
                }
            }
        }
        
        return .normal
    }
    
    //============================================================================
    // FUNCTION: IS LIKELY HANDWRITING
    //============================================================================
    // HEURISTIC UNTUK MENDETEKSI HANDWRITING
    
    private func isLikelyHandwriting(_ text: String) -> Bool {
        // HANDWRITING SERING PUNYA:
        // - HURUF KECIL SEMUA
        // - TIDAK ADA STRUKTUR YANG RAPI
        // - KATA-KATA PENDEK
        
        let words = text.split(separator: " ")
        let shortWords = words.filter { $0.count < 4 }
        let lowercaseRatio = Float(text.filter { $0.isLowercase }.count) / Float(max(text.count, 1))
        
        return shortWords.count > words.count / 2 || lowercaseRatio > 0.8
    }
    
    //============================================================================
    // FUNCTION: EXTRACT FEATURE PRINT
    //============================================================================
    // EKSTRAK FEATURE VECTOR DARI FOTO MENGGUNAKAN VISION
    
    private func extractFeaturePrint(from asset: PHAsset) async -> VNFeaturePrintObservation? {
        // REQUEST IMAGE DARI PHOTO LIBRARY
        let image = await requestImage(for: asset)
        guard let cgImage = image else { return nil }
        
        // BUAT VISION REQUEST
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            print("❌ Error generating feature print: \(error.localizedDescription)")
            return nil
        }
    }
    
    //============================================================================
    // FUNCTION: REQUEST IMAGE
    //============================================================================
    // AMBIL CGImage DARI PHAsset
    
    private func requestImage(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            
            let targetSize = CGSize(width: 299, height: 299) // SIZE OPTIMAL UNTUK VISION
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image = image,
                   let cgImage = image.cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    //============================================================================
    // FUNCTION: LOAD CACHE FROM DISK
    //============================================================================
    // MUAT CACHE DARI FILE JSON
    
    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            print("📦 No cache file found")
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            let cached = try decoder.decode([ImageMetadata].self, from: data)
            
            // KONVERSI ARRAY KE DICTIONARY
            metadataCache = Dictionary(uniqueKeysWithValues: cached.map { ($0.assetIdentifier, $0) })
            
            print("✅ Loaded \(metadataCache.count) items from cache")
        } catch {
            print("❌ Error loading cache: \(error)")
        }
    }
    
    //============================================================================
    // FUNCTION: SAVE CACHE TO DISK
    //============================================================================
    // SIMPAN CACHE KE FILE JSON
    
    private func saveCacheToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            // KONVERSI DICTIONARY KE ARRAY
            let array = Array(metadataCache.values)
            let data = try encoder.encode(array)
            
            try data.write(to: cacheFileURL, options: .atomic)
            
            print("✅ Saved \(array.count) items to cache")
        } catch {
            print("❌ Error saving cache: \(error)")
        }
    }
    
    //============================================================================
    // FUNCTION: CLEAR CACHE
    //============================================================================
    
    func clearCache() {
        metadataCache.removeAll()
        try? FileManager.default.removeItem(at: cacheFileURL)
        print("🗑️ Cache cleared")
    }
    
    //============================================================================
    // FUNCTION: FORCE REANALYZE
    //============================================================================
    // PAKSA ANALISIS ULANG SEMUA FOTO (HAPUS CACHE)
    
    func forceReanalyze() {
        clearCache()
    }
}
