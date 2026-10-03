import SwiftUI
import Photos
import Vision
import Combine

enum ImageCategory: String, Codable {
    case blurry = "Blurry Photos"
    case handwriting = "Handwriting"
    case screenshot = "Screenshots"
    case document = "Documents"
    case lowQuality = "Low Quality"
    case duplicate = "Similar Photos"
    case normal = "Other Photos"

    var priority: Int {
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

struct ImageMetadata: Codable {
    let assetIdentifier: String
    let featurePrintData: Data?
    let category: ImageCategory
    let blurScore: Float
    let analyzedAt: Date

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

struct ImageGroup: Identifiable {
    let id = UUID()
    let category: ImageCategory
    let assets: [PHAsset]
    let representativeAsset: PHAsset
    let averageFeature: VNFeaturePrintObservation?

    var title: String {
        let count = assets.count

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
        return "Tap to review"
    }

    var icon: String {
        return category.icon
    }

    var mostRecentDate: Date {
        return assets.compactMap { $0.creationDate }.max() ?? Date.distantPast
    }
}

@MainActor
class ImageSimilarityService: ObservableObject {
    static let shared = ImageSimilarityService()

    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    private var metadataCache: [String: ImageMetadata] = [:]

    private(set) var cachedGroups: [ImageGroup] = []
    var hasResult: Bool { cachedSignature != nil }
    private var cachedSignature: Int?

    private func signature(of assets: [PHAsset]) -> Int {
        var hasher = Hasher()
        for asset in assets.sorted(by: { $0.localIdentifier < $1.localIdentifier }) {
            hasher.combine(asset.localIdentifier)
            hasher.combine(asset.modificationDate)
        }
        return hasher.finalize()
    }

    private let similarityThreshold: Float = 0.35

    private let blurThreshold: Float = 0.3

    private var cacheFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("image_analysis_cache.json")
    }

    init() {
        loadCacheFromDisk()
    }

    func analyzeAndGroupAssets(_ assets: [PHAsset]) async -> [ImageGroup] {
        guard !assets.isEmpty else { return [] }

        let newAssets = assets.filter { asset in
            if let metadata = metadataCache[asset.localIdentifier] {
                return asset.modificationDate ?? Date.distantPast > metadata.analyzedAt
            }
            return true
        }

        let currentSignature = signature(of: assets)
        if newAssets.isEmpty, currentSignature == cachedSignature {
            return cachedGroups
        }

        isAnalyzing = true
        progress = 0
        statusMessage = "Checking for new photos..."

        if newAssets.isEmpty {
            statusMessage = "Loading from cache..."
            progress = 0.5

            let groups = await buildGroupsFromCache(assets)
            cachedGroups = groups
            cachedSignature = currentSignature

            isAnalyzing = false
            progress = 1.0
            statusMessage = "Done!"

            return groups
        }

        statusMessage = "Analyzing \(newAssets.count) new photos..."
        await analyzeNewAssets(newAssets)

        statusMessage = "Grouping photos..."
        let groups = await buildGroupsFromCache(assets)

        saveCacheToDisk()
        cachedGroups = groups
        cachedSignature = currentSignature

        isAnalyzing = false
        progress = 1.0
        statusMessage = "Done!"

        return groups
    }

    private func analyzeNewAssets(_ assets: [PHAsset]) async {
        for (index, asset) in assets.enumerated() {
            let feature = await extractFeaturePrint(from: asset)

            let (category, blurScore) = await detectCategoryAndQuality(for: asset)

            let metadata = ImageMetadata.from(
                asset: asset,
                feature: feature,
                category: category,
                blurScore: blurScore
            )
            metadataCache[asset.localIdentifier] = metadata

            await MainActor.run {
                progress = Double(index + 1) / Double(assets.count) * 0.8
                statusMessage = "Analyzing \(index + 1)/\(assets.count)..."
            }
        }
    }

    private func buildGroupsFromCache(_ assets: [PHAsset]) async -> [ImageGroup] {
        var duplicateCandidates: [(asset: PHAsset, feature: VNFeaturePrintObservation, category: ImageCategory, blurScore: Float)] = []

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

        let duplicateGroupsWithCategories = await findDuplicateGroupsWithCategories(duplicateCandidates)

        var result: [ImageGroup] = []
        var usedAssets: Set<String> = []

        for (category, groupAssets) in duplicateGroupsWithCategories {
            let sortedAssets = groupAssets.sorted { a, b in
                let dateA = a.creationDate ?? Date.distantPast
                let dateB = b.creationDate ?? Date.distantPast
                return dateA > dateB
            }

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

            for asset in sortedAssets {
                usedAssets.insert(asset.localIdentifier)
            }
        }

        return result.sorted { lhs, rhs in
            return lhs.mostRecentDate > rhs.mostRecentDate
        }
    }

    private func similarityLimit(gap: TimeInterval, a: ImageCategory, b: ImageCategory) -> Float {
        var limit: Float
        switch gap {
        case ..<900:    limit = 0.80
        case ..<10_800: limit = 0.65
        case ..<86_400: limit = 0.55
        default:        limit = 0.45
        }
        let looseCategories: Set<ImageCategory> = [.screenshot, .document]
        if looseCategories.contains(a) && looseCategories.contains(b) { limit += 0.15 }
        return limit
    }

    private func findDuplicateGroupsWithCategories(
        _ candidates: [(asset: PHAsset, feature: VNFeaturePrintObservation, category: ImageCategory, blurScore: Float)]
    ) async -> [(category: ImageCategory, assets: [PHAsset])] {
        guard candidates.count > 1 else { return [] }

        let items = candidates.sorted {
            ($0.asset.creationDate ?? .distantPast) < ($1.asset.creationDate ?? .distantPast)
        }

        var parent = Array(items.indices)
        var size = Array(repeating: 1, count: items.count)

        func find(_ x: Int) -> Int {
            var node = x
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }

        let maxGroupSize = 40
        let window = 300

        for i in items.indices {
            let upper = min(items.count, i + window + 1)
            guard i + 1 < upper else { continue }
            let dateI = items[i].asset.creationDate ?? .distantPast

            for j in (i + 1)..<upper {
                let rootI = find(i)
                let rootJ = find(j)
                if rootI == rootJ { continue }
                if size[rootI] + size[rootJ] > maxGroupSize { continue }

                let gap = abs((items[j].asset.creationDate ?? .distantPast).timeIntervalSince(dateI))
                let limit = similarityLimit(gap: gap, a: items[i].category, b: items[j].category)

                var distance: Float = 0
                guard (try? items[i].feature.computeDistance(&distance, to: items[j].feature)) != nil,
                      distance < limit else { continue }

                parent[rootJ] = rootI
                size[rootI] += size[rootJ]
            }
        }

        var members: [Int: [Int]] = [:]
        for index in items.indices {
            members[find(index), default: []].append(index)
        }

        return members.values.compactMap { indices in
            guard indices.count > 1 else { return nil }
            let dominant = indices.map { items[$0].category }.min(by: { $0.priority < $1.priority }) ?? .duplicate
            return (category: dominant, assets: indices.map { items[$0].asset })
        }
    }

    private func detectCategoryAndQuality(for asset: PHAsset) async -> (ImageCategory, Float) {
        guard let image = await requestImage(for: asset) else {
            return (.normal, 0)
        }

        let blurScore = await detectBlur(cgImage: image)

        let category = await detectCategory(cgImage: image, blurScore: blurScore)

        return (category, blurScore)
    }

    private func detectBlur(cgImage: CGImage) async -> Float {
        let ciImage = CIImage(cgImage: cgImage)

        guard let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono") else {
            return 0
        }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)

        guard let grayscaleImage = grayscaleFilter.outputImage else {
            return 0
        }

        guard let laplacianFilter = CIFilter(name: "CIEdges") else {
            return 0
        }
        laplacianFilter.setValue(grayscaleImage, forKey: kCIInputImageKey)
        laplacianFilter.setValue(1.0, forKey: kCIInputIntensityKey)

        guard let edgesImage = laplacianFilter.outputImage else {
            return 0
        }

        let context = CIContext()
        let extent = edgesImage.extent

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

        let variance = Float(bitmap2[0]) / 255.0

        return 1.0 - variance
    }

    private func detectCategory(cgImage: CGImage, blurScore: Float) async -> ImageCategory {
        if blurScore > blurThreshold {
            return .blurry
        }

        let request = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast

        do {
            try request.perform([textRequest])

            if let observations = textRequest.results, !observations.isEmpty {
                let totalConfidence = observations.reduce(0.0) { $0 + $1.confidence }
                let avgConfidence = totalConfidence / Float(observations.count)

                if avgConfidence > 0.5 {
                    let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined()

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

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let aspectRatio = width / height

        let commonRatios: [CGFloat] = [
            9.0/16.0,
            9.0/19.5,
            16.0/9.0,
            3.0/4.0,
            4.0/3.0
        ]

        for ratio in commonRatios {
            if abs(aspectRatio - ratio) < 0.05 {
                if !textRequest.results!.isEmpty {
                    return .screenshot
                }
            }
        }

        return .normal
    }

    private func isLikelyHandwriting(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        let shortWords = words.filter { $0.count < 4 }
        let lowercaseRatio = Float(text.filter { $0.isLowercase }.count) / Float(max(text.count, 1))

        return shortWords.count > words.count / 2 || lowercaseRatio > 0.8
    }

    private func extractFeaturePrint(from asset: PHAsset) async -> VNFeaturePrintObservation? {
        let image = await requestImage(for: asset)
        guard let cgImage = image else { return nil }

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

    private func requestImage(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast

            let targetSize = CGSize(width: 299, height: 299)

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

    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            print("📦 No cache file found")
            return
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            let cached = try decoder.decode([ImageMetadata].self, from: data)

            metadataCache = Dictionary(uniqueKeysWithValues: cached.map { ($0.assetIdentifier, $0) })

            print("✅ Loaded \(metadataCache.count) items from cache")
        } catch {
            print("❌ Error loading cache: \(error)")
        }
    }

    private func saveCacheToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted

            let array = Array(metadataCache.values)
            let data = try encoder.encode(array)

            try data.write(to: cacheFileURL, options: .atomic)

            print("✅ Saved \(array.count) items to cache")
        } catch {
            print("❌ Error saving cache: \(error)")
        }
    }

    func invalidateGroups() {
        cachedGroups = []
        cachedSignature = nil
    }

    func clearCache() {
        cachedGroups = []
        cachedSignature = nil
        metadataCache.removeAll()
        try? FileManager.default.removeItem(at: cacheFileURL)
        print("🗑️ Cache cleared")
    }
}
