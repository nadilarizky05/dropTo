//
//  PhotoDetailView.swift
//  dropTo
//

import SwiftUI
import Photos
import AVKit
import UIKit
import Vision
import EventKit

//============================================================================
// STRUCT: DETECTED EVENT
//============================================================================
// REPRESENTASI EVENT YANG TERDETEKSI DARI FOTO

struct DetectedEvent {
    let title: String
    let date: Date
    let location: String?
    let notes: String?
}

struct PhotoDetailView: View {
    let mode: PhotoDetailMode
    @EnvironmentObject private var dataService: DataService
    @Environment(\.dismiss) private var dismiss
    
    @State private var assets: [PHAsset]
    @State private var currentIndex: Int
    @State private var showUndoToast = false
    @State private var lastDeletedAsset: PHAsset?
    @State private var lastDeletedIndex: Int?
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var showMoveSheet = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isLoadingShare = false
    
    // CALENDAR EVENT DETECTION
    @State private var detectedEvent: DetectedEvent? = nil
    @State private var isDetectingEvent = false
    @State private var showCalendarSheet = false
    @State private var isScanning = false
    
    // INITIAL IDENTIFIERS (BUAT REFRESH SAAT DATA BERUBAH)
    private let initialIdentifiers: [String]

    init(assets: [PHAsset], startingAt startAsset: PHAsset, mode: PhotoDetailMode) {
        _assets = State(initialValue: assets)
        self.mode = mode
        _currentIndex = State(initialValue: assets.firstIndex(where: { $0.localIdentifier == startAsset.localIdentifier }) ?? 0)
        self.initialIdentifiers = assets.map { $0.localIdentifier }
    }

    private var currentAsset: PHAsset? {
        guard assets.indices.contains(currentIndex) else { return nil }
        return assets[currentIndex]
    }

    private var isAlbumMode: Bool {
        if case .album = mode { return true }
        return false
    }
    
    private var isBrowseMode: Bool {
        if case .browseOnly = mode { return true }
        return false
    }
    
    private var isFavoritesMode: Bool {
        if case .favorites = mode { return true }
        return false
    }
    
    private var showsActionBar: Bool {
        isAlbumMode || isBrowseMode || isFavoritesMode
    }

    private var showsRecentlyDeletedActions: Bool {
        if case .recentlyDeleted = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header(for: currentAsset)

                if currentAsset == nil {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                            MediaPageView(asset: asset, isActive: index == currentIndex)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    if showsActionBar {
                        Text("Swipe to browse  •  use \"•••\" to delete")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 10)
                    }
                }
            }

            if showsActionBar, currentAsset != nil {
                albumActionBar
            }

            if showUndoToast {
                undoToast
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if showsRecentlyDeletedActions, currentAsset != nil {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        performRecover()
                    } label: {
                        Label("Recover", systemImage: "arrow.uturn.backward")
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        performDeleteForever()
                    } label: {
                        Label("Delete Forever", systemImage: "trash.fill")
                    }
                }
            }
        }
        .toolbarBackground(showsRecentlyDeletedActions ? .visible : .hidden, for: .bottomBar)
        .sheet(isPresented: $showMoveSheet) {
            if let asset = currentAsset {
                MoveToAlbumSheet(
                    sourceAlbum: {
                        if case .album(let album) = mode { return album }
                        return nil
                    }(),
                    identifiersToMove: [asset.localIdentifier],
                    dataService: dataService,
                    onMoved: { advanceOrDismiss() }
                )
            }
        }
        .sheet(isPresented: $showCalendarSheet) {
            if let asset = currentAsset {
                AddToCalendarSheet(
                    asset: asset,
                    detectedEvent: detectedEvent,
                    isPresented: $showCalendarSheet
                )
            }
        }
        .sheet(isPresented: $showShareSheet) {
            shareItems = []
        } content: {
            if !shareItems.isEmpty {
                ActivityViewController(items: shareItems)
            }
        }
        .onChange(of: assets.isEmpty) { _, isEmpty in
            // AUTO DISMISS KALAU SEMUA FOTO UDAH DIHAPUS/DIMOVE
            if isEmpty {
                dismiss()
            }
        }
        .onReceive(dataService.$lastUpdate) { _ in
            // REFRESH ASSETS SAAT ADA PERUBAHAN DATA
            refreshAssets()
        }
    }
    
    //============================================================================
    // FUNCTION: REFRESH ASSETS
    //============================================================================
    // RELOAD ASSETS DARI ALBUM/SOURCE SAAT ADA PERUBAHAN (DELETE/MOVE)
    
    private func refreshAssets() {
        // SAVE CURRENT ASSET IDENTIFIER SEBELUM REFRESH
        let currentIdentifier = currentAsset?.localIdentifier
        
        let updatedAssets: [PHAsset]
        
        switch mode {
        case .album(let album):
            // RELOAD DARI ALBUM
            let currentAlbum = dataService.fetchAlbums().first(where: { $0.id == album.id })
            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: currentAlbum?.assetIdentifiers ?? [])
            
        case .browseOnly:
            // RELOAD DARI UNORGANIZED (FILTER YANG BELUM DI ALBUM & TRASH)
            let albums = dataService.fetchAlbums()
            let deletedItems = dataService.fetchDeletedItems()
            let organizedIdentifiers = Set(albums.flatMap(\.assetIdentifiers))
            let deletedIdentifiers = Set(deletedItems.map(\.assetIdentifier))
            
            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: initialIdentifiers)
                .filter { !organizedIdentifiers.contains($0.localIdentifier) && !deletedIdentifiers.contains($0.localIdentifier) }
            
        case .favorites:
            // RELOAD DARI FAVORITES (FILTER YANG MASIH DI-FAVORITE)
            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: initialIdentifiers)
                .filter { $0.isFavorite }
            
        case .recentlyDeleted:
            // RELOAD DARI RECENTLY DELETED
            let deletedItems = dataService.fetchDeletedItems()
            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: deletedItems.map { $0.assetIdentifier })
        }
        
        // UPDATE ASSETS ARRAY
        assets = updatedAssets
        
        // SMART INDEX ADJUSTMENT:
        // 1. KALAU FOTO YANG SEDANG DILIHAT MASIH ADA → TETAP DI FOTO ITU
        // 2. KALAU FOTO UDAH DIHAPUS → PINDAH KE FOTO DENGAN INDEX YANG SAMA (ATAU SEBELUMNYA KALAU INDEX OUT OF BOUNDS)
        if let currentIdentifier = currentIdentifier,
           let newIndex = assets.firstIndex(where: { $0.localIdentifier == currentIdentifier }) {
            // FOTO MASIH ADA, UPDATE INDEX KE POSISI BARUNYA
            currentIndex = newIndex
        } else {
            // FOTO UDAH DIHAPUS, ADJUST INDEX KALAU PERLU
            if !assets.isEmpty && currentIndex >= assets.count {
                currentIndex = assets.count - 1
            }
        }
    }

    private func header(for asset: PHAsset?) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
            }

            Spacer()

            if let asset {
                VStack(spacing: 2) {
                    Text(fileName(for: asset))
                        .font(.subheadline.weight(.semibold))
                    Text(dateString(for: asset))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
            }

            Spacer()

            if asset != nil {
                Button {
                    performShare()
                } label: {
                    if isLoadingShare {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }
                .disabled(isLoadingShare)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("All caught up")
                .foregroundStyle(.white)
        }
    }

    private func performShare() {
        guard let asset = currentAsset else { return }
        isLoadingShare = true
        
        Task {
            do {
                if asset.mediaType == .video {
                    print("📹 Starting video share for asset: \(asset.localIdentifier)")
                    let options = PHVideoRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.version = .original
                    
                    let avAsset = await withCheckedContinuation { (continuation: CheckedContinuation<AVAsset?, Never>) in
                        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                            print("📹 Got AVAsset: \(avAsset != nil)")
                            continuation.resume(returning: avAsset)
                        }
                    }
                    
                    if let urlAsset = avAsset as? AVURLAsset {
                        print("📹 Video URL: \(urlAsset.url)")
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension("mov")
                        
                        try? FileManager.default.copyItem(at: urlAsset.url, to: tempURL)
                        
                        await MainActor.run {
                            print("📹 Setting shareItems with tempURL")
                            self.shareItems = [tempURL]
                            self.showShareSheet = true
                            self.isLoadingShare = false
                        }
                    } else {
                        print("❌ Failed to get URL asset")
                        await MainActor.run {
                            self.isLoadingShare = false
                        }
                    }
                } else {
                    print("📷 Starting photo share for asset: \(asset.localIdentifier)")
                    let options = PHImageRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.isSynchronous = false
                    options.version = .current
                    
                    let imageData = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                            print("📷 Got image data: \(data?.count ?? 0) bytes")
                            continuation.resume(returning: data)
                        }
                    }
                    
                    if let imageData = imageData, let image = UIImage(data: imageData) {
                        print("📷 Created UIImage: \(image.size)")
                        await MainActor.run {
                            print("📷 Setting shareItems with image")
                            self.shareItems = [image]
                            self.showShareSheet = true
                            self.isLoadingShare = false
                        }
                    } else {
                        print("❌ Failed to create image from data")
                        await MainActor.run {
                            self.isLoadingShare = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingShare = false
                }
                print("❌ Share error: \(error)")
            }
        }
    }

    private func performDelete(_ asset: PHAsset) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        let sourceAlbumID: UUID? = {
            if case .album(let album) = mode { return album.id }
            return nil
        }()
        
        // SAVE INFO BUAT UNDO
        lastDeletedAsset = asset
        lastDeletedIndex = currentIndex
        
        // SOFT DELETE KE DATA SERVICE
        // refreshAssets() AKAN OTOMATIS DIPANGGIL LEWAT onReceive(dataService.$lastUpdate)
        dataService.softDelete(asset.localIdentifier, sourceAlbumID: sourceAlbumID)

        withAnimation { showUndoToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showUndoToast = false }
        }
    }

    private func advanceOrDismiss() {
        // GA PERLU MANUAL REMOVE ASSET!
        // refreshAssets() AKAN OTOMATIS DIPANGGIL LEWAT onReceive(dataService.$lastUpdate)
        // DAN DIA AKAN HANDLE SEMUA LOGIC REFRESH + INDEX ADJUSTMENT
        
        // FUNGSI INI SEKARANG CUMA PLACEHOLDER
        // BISA DIHAPUS TAPI BIAR BACKWARD COMPATIBLE TETAP DIBIKIN
    }

    private var undoToast: some View {
        VStack {
            Spacer()
            Button {
                guard let asset = lastDeletedAsset else { return }
                
                if case .album(let album) = mode {
                    dataService.undoDelete(asset.localIdentifier, restoringTo: album)
                } else {
                    dataService.undoDelete(asset.localIdentifier, restoringTo: nil)
                }
                
                let insertIndex = min(lastDeletedIndex ?? assets.count, assets.count)
                assets.insert(asset, at: insertIndex)
                currentIndex = insertIndex
                
                withAnimation { showUndoToast = false }
            } label: {
                Label("Undo Delete", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var albumActionBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                actionButton(
                    systemImage: isFavorite(currentAsset!) ? "heart.fill" : "heart",
                    label: "Favorite",
                    tint: isFavorite(currentAsset!) ? .red : .white
                ) {
                    toggleFavorite(currentAsset!)
                }
                
                Spacer()
                
                // CALENDAR BUTTON WITH LOADING STATE
                Button {
                    if !isScanning {
                        performScanForCalendar()
                    }
                } label: {
                    VStack(spacing: 4) {
                        if isScanning {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .font(.system(size: 20))
                        } else {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 20))
                        }
                        Text("Calendar")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
                .disabled(isScanning)
                
                Spacer()
                
                actionButton(systemImage: "folder", label: "Move", tint: .white) {
                    showMoveSheet = true
                }
                
                Spacer()
                
                actionButton(systemImage: "trash", label: "Delete", tint: .red) {
                    performDelete(currentAsset!)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }

        private func actionButton(systemImage: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage).font(.system(size: 20))
                    Text(label).font(.caption2)
                }
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
            }
        }

        private func isFavorite(_ asset: PHAsset) -> Bool {
            favoriteOverrides[asset.localIdentifier] ?? asset.isFavorite
        }

        private func toggleFavorite(_ asset: PHAsset) {
            let newValue = !isFavorite(asset)
            favoriteOverrides[asset.localIdentifier] = newValue
            Task { await PhotoLibraryService.shared.toggleFavorite(for: asset) }
        }
    
    private func performScanForCalendar() {
        guard let asset = currentAsset, asset.mediaType == .image else { return }
        
        isScanning = true
        
        Task {
            await detectEventFromImage(asset)
            
            await MainActor.run {
                isScanning = false
                showCalendarSheet = true
            }
        }
    }
    
    private func performRecover() {
        guard let asset = currentAsset else { return }
        dataService.restoreFromDeleted(asset.localIdentifier)
        advanceOrDismiss()
    }

    private func performDeleteForever() {
        guard let asset = currentAsset else { return }
        Task {
            let success = await PhotoLibraryService.shared.permanentlyDelete(identifiers: [asset.localIdentifier])
            // HANYA REMOVE DARI UI KALAU DELETE BENER-BENER BERHASIL
            if success {
                dataService.removeFromDeletedList(asset.localIdentifier)
                advanceOrDismiss()
            }
        }
    }

    private func fileName(for asset: PHAsset) -> String {
        PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "Item"
    }

    private func dateString(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy"
        return formatter.string(from: date)
    }
    
    //============================================================================
    // FUNCTION: DETECT EVENT FROM IMAGE
    //============================================================================
    
    private func detectEventFromImage(_ asset: PHAsset) async {
        guard !isDetectingEvent else { return }
        isDetectingEvent = true
        
        print("🔎 Starting event detection for asset: \(asset.localIdentifier)")
        
        // RESET STATE
        await MainActor.run {
            detectedEvent = nil
        }
        
        // GET IMAGE
        guard let cgImage = await PhotoLibraryService.shared.loadFullImage(for: asset)?.cgImage else {
            print("❌ Failed to load image")
            isDetectingEvent = false
            return
        }
        
        // VISION TEXT RECOGNITION
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results, !observations.isEmpty else {
                print("❌ No text detected in image")
                isDetectingEvent = false
                return
            }
            
            print("✅ Found \(observations.count) text observations")
            
            // EXTRACT ALL TEXT
            let recognizedText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            
            print("📝 Recognized text:\n\(recognizedText)")
            
            // PARSE EVENT INFO
            if let event = parseEventFromText(recognizedText) {
                print("🎉 Event detected: \(event.title) on \(event.date)")
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        detectedEvent = event
                    }
                }
            } else {
                print("❌ No event info parsed from text")
            }
        } catch {
            print("❌ Error detecting text: \(error)")
        }
        
        isDetectingEvent = false
    }
    
    //============================================================================
    // FUNCTION: PARSE EVENT FROM TEXT
    //============================================================================
    
    private func parseEventFromText(_ text: String) -> DetectedEvent? {
        print("🔍 Parsing text for event: \(text)")
        
        // COMPREHENSIVE DATE PATTERNS - SUPPORTS ALL POSSIBLE FORMATS!
        let datePatterns = [
            // ========== INDONESIAN FORMATS (HIGH PRIORITY) ==========
            // With year: "31 Oktober 2026", "7 September 2026"
            "\\d{1,2}\\s+(Januari|Februari|Maret|April|Mei|Juni|Juli|Agustus|September|Oktober|November|Desember)\\s+\\d{4}",
            
            // Without year: "31 Oktober", "7 September"
            "\\d{1,2}\\s+(Januari|Februari|Maret|April|Mei|Juni|Juli|Agustus|September|Oktober|November|Desember)(?!\\s*\\d)",
            
            // With day name: "Senin, 31 Oktober 2026", "Jumat 15 Desember 2026"
            "(Senin|Selasa|Rabu|Kamis|Jumat|Sabtu|Minggu),?\\s+\\d{1,2}\\s+(Januari|Februari|Maret|April|Mei|Juni|Juli|Agustus|September|Oktober|November|Desember)\\s+\\d{4}",
            
            // ========== ENGLISH FORMATS ==========
            // With day + full month + year: "Monday, 7 September 2024"
            "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\\s+\\d{1,2}(st|nd|rd|th)?\\s+[A-Z][a-z]+\\s+\\d{2,4}",
            
            // With day + abbr month + year: "Monday, Sep 7th 2024"
            "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2}(st|nd|rd|th)?\\s+\\d{2,4}",
            
            // With day without year: "Monday, Aug 24th", "Friday, September 7th"
            "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2}(st|nd|rd|th)?(?!\\s*\\d)",
            
            // With day without year (number first): "Monday, 24 Aug", "Friday, 7 September"
            "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\\s+\\d{1,2}(st|nd|rd|th)?\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*(?!\\s*\\d)",
            
            // Month + day + year: "Sep 7th 2024", "September 7 2024"
            "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2}(st|nd|rd|th)?\\s+\\d{2,4}",
            
            // Month + day (no year): "Sep 28th", "September 28", "Aug 24th"
            "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2}(st|nd|rd|th)?(?!\\s*\\d)",
            
            // Day + month + year: "7 Sep 2024", "7th September 2024"
            "\\d{1,2}(st|nd|rd|th)?\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{2,4}",
            
            // Day + month (no year): "28 Sep", "24th August"
            "\\d{1,2}(st|nd|rd|th)?\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*(?!\\s*\\d)",
            
            // ========== NUMERIC FORMATS ==========
            // ISO format: "2024-09-07", "2024/09/07"
            "\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}",
            
            // DD-MM-YYYY: "07-09-2024", "07/09/2024", "07.09.2024"
            "\\d{1,2}[-/.]\\d{1,2}[-/.]\\d{4}",
            
            // Two-digit year: "07-09-24", "07/09/24"
            "\\d{1,2}[-/.]\\d{1,2}[-/.]\\d{2}",
            
            // ========== SPECIAL FORMATS ==========
            // "on Monday, 7 September", "on 31 Oktober"
            "on\\s+(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Senin|Selasa|Rabu|Kamis|Jumat|Sabtu|Minggu),?\\s+\\d{1,2}(st|nd|rd|th)?\\s+[A-Z][a-z]+",
            
            // "tanggal 31 Oktober 2026"
            "(tanggal|date)[:\\s]+\\d{1,2}\\s+[A-Z][a-z]+\\s*\\d{0,4}"
        ]
        
        for pattern in datePatterns {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                var dateString = String(text[range])
                print("📅 Found date pattern: \(dateString)")
                
                // CLEAN UP: REMOVE PREFIXES
                dateString = dateString.replacingOccurrences(of: "^(on|tanggal|date)[:\\s]+", with: "", options: [.regularExpression, .caseInsensitive])
                
                // CLEAN UP: REMOVE DAY OF WEEK
                dateString = dateString.replacingOccurrences(of: "^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Senin|Selasa|Rabu|Kamis|Jumat|Sabtu|Minggu),?\\s*", with: "", options: [.regularExpression, .caseInsensitive])
                
                // CLEAN UP: REMOVE ORDINAL SUFFIXES (st, nd, rd, th)
                dateString = dateString.replacingOccurrences(of: "(\\d+)(st|nd|rd|th)", with: "$1", options: .regularExpression)
                print("🧹 Cleaned date: \(dateString)")
                
                // EXTRACT TITLE (FIRST LINE OR BIGGEST TEXT)
                let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                let title = lines.first ?? "Event from Photo"
                
                // PARSE DATE
                if let date = parseDateString(dateString) {
                    print("✅ Successfully parsed date: \(date)")
                    return DetectedEvent(
                        title: title,
                        date: date,
                        location: extractLocation(from: text),
                        notes: text
                    )
                } else {
                    print("❌ Failed to parse date string: \(dateString)")
                }
            }
        }
        
        print("❌ No date pattern matched")
        return nil
    }
    
    //============================================================================
    // FUNCTION: PARSE DATE STRING
    //============================================================================
    
    private func parseDateString(_ dateString: String) -> Date? {
        print("🔍 Trying to parse: \(dateString)")
        
        // ========== INDONESIAN MONTH DICTIONARY ==========
        let indonesianMonths = [
            "januari": 1, "februari": 2, "maret": 3, "april": 4,
            "mei": 5, "juni": 6, "juli": 7, "agustus": 8,
            "september": 9, "oktober": 10, "november": 11, "desember": 12,
            // Abbreviated forms
            "jan": 1, "feb": 2, "mar": 3, "apr": 4,
            "jun": 6, "jul": 7, "agu": 8, "ags": 8,
            "sep": 9, "okt": 10, "nov": 11, "des": 12
        ]
        
        // ========== TRY INDONESIAN WITH YEAR: "31 Oktober 2026" ==========
        let indoWithYear = "(\\d{1,2})\\s+([A-Za-z]+)\\s+(\\d{4})"
        if let range = dateString.range(of: indoWithYear, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(dateString[range])
            let parts = matched.components(separatedBy: " ")
            
            if parts.count == 3,
               let day = Int(parts[0]),
               let month = indonesianMonths[parts[1].lowercased()],
               let year = Int(parts[2]) {
                
                let calendar = Calendar.current
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                components.hour = 8
                components.minute = 0
                components.second = 0
                
                if let date = calendar.date(from: components) {
                    print("✅ Matched Indonesian WITH year: \(matched) → \(date)")
                    return date
                }
            }
        }
        
        // ========== TRY INDONESIAN WITHOUT YEAR: "31 Oktober" ==========
        let indoWithoutYear = "^(\\d{1,2})\\s+([A-Za-z]+)$"
        if let range = dateString.range(of: indoWithoutYear, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(dateString[range])
            let parts = matched.components(separatedBy: " ")
            
            if parts.count == 2,
               let day = Int(parts[0]),
               let month = indonesianMonths[parts[1].lowercased()] {
                
                let calendar = Calendar.current
                let currentYear = calendar.component(.year, from: Date())
                
                var components = DateComponents()
                components.year = currentYear
                components.month = month
                components.day = day
                components.hour = 8
                components.minute = 0
                components.second = 0
                
                if let date = calendar.date(from: components) {
                    print("✅ Matched Indonesian WITHOUT year: \(matched) → \(date)")
                    return date
                }
            }
        }
        
        // ========== ENGLISH FORMATS WITH YEAR ==========
        let formatsWithYear = [
            // Full month names
            "MMMM d yyyy", "MMMM dd yyyy",
            "d MMMM yyyy", "dd MMMM yyyy",
            
            // Abbreviated months
            "MMM d yyyy", "MMM dd yyyy",
            "d MMM yyyy", "dd MMM yyyy",
            
            // With separators
            "dd-MM-yyyy", "dd/MM/yyyy", "dd.MM.yyyy",
            "MM-dd-yyyy", "MM/dd/yyyy", "MM.dd.yyyy",
            
            // ISO format
            "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd",
            
            // Two-digit year
            "MMM d yy", "MMM dd yy",
            "dd-MM-yy", "MM-dd-yy",
            "dd/MM/yy", "MM/dd/yy"
        ]
        
        for format in formatsWithYear {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let date = formatter.date(from: dateString) {
                // SET TIME TO 8:00 AM
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = 8
                components.minute = 0
                components.second = 0
                
                let finalDate = calendar.date(from: components) ?? date
                print("✅ Matched English format: \(format) → \(finalDate)")
                return finalDate
            }
        }
        
        // ========== ENGLISH FORMATS WITHOUT YEAR ==========
        let formatsWithoutYear = [
            "MMM d", "MMM dd",           // Sep 28
            "d MMM", "dd MMM",           // 28 Sep
            "MMMM d", "MMMM dd",         // September 28
            "d MMMM", "dd MMMM"          // 28 September
        ]
        
        for format in formatsWithoutYear {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let dateWithoutYear = formatter.date(from: dateString) {
                // GET CURRENT YEAR
                let calendar = Calendar.current
                let currentYear = calendar.component(.year, from: Date())
                
                // ADD CURRENT YEAR + SET TIME TO 8:00 AM
                var components = calendar.dateComponents([.month, .day], from: dateWithoutYear)
                components.year = currentYear
                components.hour = 8
                components.minute = 0
                components.second = 0
                
                guard let dateThisYear = calendar.date(from: components) else { continue }
                
                print("✅ Matched English WITHOUT year: \(format) → \(dateThisYear)")
                return dateThisYear
            }
        }
        
        print("❌ No format matched for: \(dateString)")
        return nil
    }
    
    //============================================================================
    // FUNCTION: EXTRACT LOCATION
    //============================================================================
    
    private func extractLocation(from text: String) -> String? {
        // SIMPLE LOCATION DETECTION (BISA DIPERLUAS)
        let locationKeywords = ["at ", "@ ", "location:", "venue:", "place:", "lokasi:", "tempat:"]
        
        for keyword in locationKeywords {
            if let range = text.range(of: keyword, options: .caseInsensitive) {
                let afterKeyword = text[range.upperBound...]
                let location = afterKeyword.components(separatedBy: .newlines).first?
                    .trimmingCharacters(in: .whitespaces)
                
                if let location = location, !location.isEmpty {
                    return location
                }
            }
        }
        
        return nil
    }
}

//============================================================================
// SHEET: ADD TO CALENDAR
//============================================================================

struct AddToCalendarSheet: View {
    let asset: PHAsset
    let detectedEvent: DetectedEvent?
    @Binding var isPresented: Bool
    
    @State private var eventTitle: String
    @State private var eventDate: Date
    @State private var eventLocation: String
    @State private var eventNotes: String
    @State private var isSaving = false
    @State private var scanError: String?
    
    init(asset: PHAsset, detectedEvent: DetectedEvent?, isPresented: Binding<Bool>) {
        self.asset = asset
        self.detectedEvent = detectedEvent
        self._isPresented = isPresented
        
        // INITIALIZE WITH DETECTED VALUES OR DEFAULTS
        if let event = detectedEvent {
            _eventTitle = State(initialValue: event.title)
            _eventDate = State(initialValue: event.date)
            _eventLocation = State(initialValue: event.location ?? "")
            _eventNotes = State(initialValue: event.notes ?? "")
        } else {
            _eventTitle = State(initialValue: "")
            
            // DEFAULT TO TODAY AT 8 AM
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = 8
            components.minute = 0
            _eventDate = State(initialValue: calendar.date(from: components) ?? Date())
            
            _eventLocation = State(initialValue: "")
            _eventNotes = State(initialValue: "")
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // PREVIEW IMAGE
                    imagePreview
                    
                    // SCAN STATUS
                    if detectedEvent != nil {
                        scanSuccessMessage
                    } else if let error = scanError {
                        scanErrorMessage(error)
                    } else {
                        noDetectionMessage
                    }
                    
                    // EDITABLE FIELDS
                    VStack(spacing: 16) {
                        // TITLE
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Event Title")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g., Exhibition Opening", text: $eventTitle)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // DATE
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Date & Time")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                        
                        // LOCATION
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location (Optional)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g., MoMA Gallery", text: $eventLocation)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // NOTES
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes (Optional)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $eventNotes)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Add to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveToCalendar()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Add")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(eventTitle.isEmpty || isSaving)
                }
            }
        }
    }
    
    @ViewBuilder
    private var imagePreview: some View {
        if let image = loadThumbnail() {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var scanSuccessMessage: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Event Detected!")
                    .font(.subheadline.weight(.semibold))
                Text("Review and edit the details below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var noDetectionMessage: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.blue)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No Event Detected")
                    .font(.subheadline.weight(.semibold))
                Text("Fill in the event details manually")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func scanErrorMessage(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan Error")
                    .font(.subheadline.weight(.semibold))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func loadThumbnail() -> UIImage? {
        var thumbnail: UIImage?
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 400, height: 400),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            thumbnail = image
        }
        
        return thumbnail
    }
    
    private func saveToCalendar() {
        isSaving = true
        
        let eventStore = EKEventStore()
        
        eventStore.requestFullAccessToEvents { granted, error in
            guard granted, error == nil else {
                print("❌ Calendar access denied")
                DispatchQueue.main.async {
                    isSaving = false
                    scanError = "Calendar access denied"
                }
                return
            }
            
            // CREATE EVENT
            let calendarEvent = EKEvent(eventStore: eventStore)
            calendarEvent.title = eventTitle
            calendarEvent.startDate = eventDate
            calendarEvent.endDate = eventDate.addingTimeInterval(3600) // 1 HOUR
            calendarEvent.calendar = eventStore.defaultCalendarForNewEvents
            
            if !eventLocation.isEmpty {
                calendarEvent.location = eventLocation
            }
            
            if !eventNotes.isEmpty {
                calendarEvent.notes = eventNotes
            }
            
            // SAVE EVENT
            do {
                try eventStore.save(calendarEvent, span: .thisEvent)
                
                DispatchQueue.main.async {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isSaving = false
                    isPresented = false
                }
                
                print("✅ Event added to calendar: \(eventTitle)")
            } catch {
                print("❌ Error saving event: \(error)")
                DispatchQueue.main.async {
                    isSaving = false
                    scanError = "Failed to save event"
                }
            }
        }
    }
}

private struct MediaPageView: View {
    let asset: PHAsset
    var isActive: Bool = true
    var enableHoldToDelete: Bool = false
    var onConfirmDelete: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoomScale: CGFloat = 1
    @State private var baselineZoomScale: CGFloat = 1
    @State private var zoomAnchor: UnitPoint = .center
    @State private var panOffset: CGSize = .zero
    @State private var baselinePanOffset: CGSize = .zero

    @State private var isHolding = false
    @State private var holdDragOffset: CGSize = .zero
    @State private var isHoveringDeleteZone = false
    private let deleteZoneThreshold: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if asset.mediaType == .video {
                    mediaContent(in: geo)
                } else {
                    mediaContent(in: geo)
                        .offset(x: holdDragOffset.width + panOffset.width, 
                               y: holdDragOffset.height + panOffset.height)
                        .scaleEffect(isHolding ? 0.92 : zoomScale, anchor: isHolding ? .center : zoomAnchor)
                        .simultaneousGesture(magnificationGesture)
                        .gesture(zoomScale > 1 ? panGesture : nil, including: zoomScale > 1 ? .all : .none)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                zoomScale = 1
                                baselineZoomScale = 1
                                zoomAnchor = .center
                                panOffset = .zero
                                baselinePanOffset = .zero
                            }
                        }
                        .gesture(enableHoldToDelete ? holdToDeleteGesture : nil)
                }

                if enableHoldToDelete {
                    VStack {
                        Spacer()
                        deleteButton
                            .padding(.bottom, 40)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: asset.localIdentifier) {
            zoomScale = 1
            baselineZoomScale = 1
            zoomAnchor = .center
            panOffset = .zero
            baselinePanOffset = .zero
            if asset.mediaType == .video {
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                let item = await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
                    PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                        continuation.resume(returning: item)
                    }
                }
                if let item {
                    let newPlayer = AVPlayer(playerItem: item)
                    player = newPlayer
                    if isActive { newPlayer.play() }
                }
            } else {
                image = await PhotoLibraryService.shared.loadFullImage(for: asset)
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                player?.play()
            } else {
                player?.pause()
            }
        }
    }

    @ViewBuilder
    private func mediaContent(in geo: GeometryProxy) -> some View {
        if asset.mediaType == .video {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { if isActive { player.play() } }
                    .onDisappear { player.pause() }
            } else {
                ProgressView().tint(.white)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
        } else {
            ProgressView().tint(.white)
        }
    }

    private var deleteButton: some View {
        Label("Delete", systemImage: "trash.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                isHoveringDeleteZone ? Color.red : Color.red.opacity(0.25),
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white.opacity(isHoveringDeleteZone ? 0.7 : 0.35), lineWidth: 1.5))
            .foregroundStyle(.white)
            .scaleEffect(isHoveringDeleteZone ? 1.15 : 1)
            .opacity(isHolding ? 1 : 0)
            .offset(y: isHolding ? 0 : 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHolding)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHoveringDeleteZone)
    }

    private var holdToDeleteGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    withAnimation(.spring()) { isHolding = true }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                case .second(true, let drag):
                    guard let drag else { return }
                    holdDragOffset = drag.translation
                    let hovering = drag.translation.height > deleteZoneThreshold
                    if hovering != isHoveringDeleteZone {
                        isHoveringDeleteZone = hovering
                        if hovering {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    }

                default:
                    break
                }
            }
            .onEnded { value in
                let shouldDelete: Bool
                if case .second(true, let drag) = value, let drag {
                    shouldDelete = drag.translation.height > deleteZoneThreshold
                } else {
                    shouldDelete = false
                }

                withAnimation(.spring()) {
                    isHolding = false
                    holdDragOffset = .zero
                    isHoveringDeleteZone = false
                }

                if shouldDelete {
                    onConfirmDelete?()
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !isHolding, asset.mediaType != .video else { return }
                zoomAnchor = value.startAnchor
                zoomScale = min(max(baselineZoomScale * value.magnification, 1), 4)
            }
            .onEnded { _ in
                baselineZoomScale = zoomScale
                if zoomScale < 1.05 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        zoomScale = 1
                        baselineZoomScale = 1
                        zoomAnchor = .center
                        panOffset = .zero
                        baselinePanOffset = .zero
                    }
                }
            }
    }
    
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let newOffsetWidth = baselinePanOffset.width + value.translation.width
                let newOffsetHeight = baselinePanOffset.height + value.translation.height
                
                let maxOffset = 200 * zoomScale
                let clampedWidth = min(max(newOffsetWidth, -maxOffset), maxOffset)
                let clampedHeight = min(max(newOffsetHeight, -maxOffset), maxOffset)
                
                panOffset = CGSize(width: clampedWidth, height: clampedHeight)
            }
            .onEnded { _ in
                baselinePanOffset = panOffset
            }
    }
}

