import SwiftUI
import Photos
import AVKit
import UIKit
import Vision
import EventKit

private struct CalendarSaveResult {
    let count: Int
    let firstDate: Date
}

struct PhotoDetailView: View {
    let mode: PhotoDetailMode
    @EnvironmentObject private var dataService: DataService
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset]
    @State private var currentIndex: Int
    @State private var safeInsets = EdgeInsets()
    @State private var calendarResult: CalendarSaveResult?
    @State private var isZoomed = false
    @State private var showUndoToast = false
    @State private var lastDeletedAsset: PHAsset?
    @State private var lastDeletedIndex: Int?
    @State private var showControls = true
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var showMoveSheet = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isLoadingShare = false

    @State private var detectedEvents: [DetectedEvent] = []
    @State private var isDetectingEvent = false
    @State private var showCalendarSheet = false
    @State private var isScanning = false

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
                if currentAsset == nil {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            MediaPageView(asset: asset, isActive: index == currentIndex, onSingleTap: toggleControls, onZoomedChange: { isZoomed = $0 })
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .scrollDisabled(isZoomed)
                    .onChange(of: currentIndex) { _, _ in isZoomed = false }
                    .padding(.top, showControls ? safeInsets.top + 64 : 0)
                    .padding(.bottom, showControls ? safeInsets.bottom + (showsActionBar ? 88 : 0) : 0)
                }
            }
            .ignoresSafeArea()

            VStack {
                header(for: currentAsset)
                    .opacity(showControls ? 1 : 0)
                    .allowsHitTesting(showControls)
                Spacer()
            }

            if showsActionBar, currentAsset != nil {
                albumActionBar
                    .opacity(showControls ? 1 : 0)
                    .offset(y: showControls ? 0 : 24)
                    .allowsHitTesting(showControls)
            }

            if showUndoToast {
                undoToast
            }

        }
        .overlay {
            if let result = calendarResult {
                calendarSuccessModal(result)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { safeInsets = geo.safeAreaInsets }
                    .onChange(of: geo.safeAreaInsets) { _, newValue in safeInsets = newValue }
            }
            .ignoresSafeArea()
        )
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(!showControls)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(showControls ? .visible : .hidden, for: .bottomBar)
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
            calendarSheetContent
        }
        .sheet(isPresented: $showShareSheet) {
            shareItems = []
        } content: {
            if !shareItems.isEmpty {
                ActivityViewController(items: shareItems)
            }
        }
        .onChange(of: assets.isEmpty) { _, isEmpty in
            if isEmpty {
                dismiss()
            }
        }
        .onReceive(dataService.$lastUpdate) { _ in
            refreshAssets()
        }
    }

    private func refreshAssets() {
        let currentIdentifier = currentAsset?.localIdentifier

        let updatedAssets: [PHAsset]

        switch mode {
        case .album(let album):
            let currentAlbum = dataService.fetchAlbums().first(where: { $0.id == album.id })
            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: currentAlbum?.assetIdentifiers ?? [])

        case .browseOnly:
            let albums = dataService.fetchAlbums()
            let deletedItems = dataService.fetchDeletedItems()
            let organizedIdentifiers = Set(albums.flatMap(\.assetIdentifiers))
            let deletedIdentifiers = Set(deletedItems.map(\.assetIdentifier))

            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: initialIdentifiers)
                .filter { !organizedIdentifiers.contains($0.localIdentifier) && !deletedIdentifiers.contains($0.localIdentifier) }

        case .favorites:
            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: initialIdentifiers)
                .filter { $0.isFavorite }

        case .recentlyDeleted:
            let deletedItems = dataService.fetchDeletedItems()
            updatedAssets = PhotoLibraryService.shared.fetchAssets(withIdentifiers: deletedItems.map { $0.assetIdentifier })
        }

        assets = updatedAssets

        if let currentIdentifier = currentIdentifier,
           let newIndex = assets.firstIndex(where: { $0.localIdentifier == currentIdentifier }) {
            currentIndex = newIndex
        } else {
            if !assets.isEmpty && currentIndex >= assets.count {
                currentIndex = assets.count - 1
            }
        }
    }

    private func calendarSuccessModal(_ result: CalendarSaveResult) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismissCalendarModal() }

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)

                Text("Added to Calendar")
                    .font(.title3.weight(.bold))

                Text(result.count == 1 ? "Your event is now in your calendar" : "Your \(result.count) events are now in your calendar")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)

                Button {
                    openCalendar(at: result.firstDate)
                    dismissCalendarModal()
                } label: {
                    Text("Check Calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 300)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { dismissCalendarModal() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(.systemGray5), in: Circle())
                }
                .padding(10)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func dismissCalendarModal() {
        withAnimation(.easeOut(duration: 0.2)) { calendarResult = nil }
    }

    private func openCalendar(at date: Date) {
        guard let url = URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)") else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private var calendarSheetContent: some View {
        if let asset = currentAsset {
            AddToCalendarSheet(
                asset: asset,
                detectedEvents: detectedEvents,
                isPresented: $showCalendarSheet,
                onSaved: handleCalendarSaved
            )
        }
    }

    private func handleCalendarSaved(count: Int, firstDate: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                calendarResult = CalendarSaveResult(count: count, firstDate: firstDate)
            }
        }
    }

    private func toggleControls() {
        withAnimation(.smooth(duration: 0.35)) { showControls.toggle() }
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
        .padding(.top, 16)
        .padding(.bottom, 12)
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
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        let sourceAlbumID: UUID? = {
            if case .album(let album) = mode { return album.id }
            return nil
        }()

        lastDeletedAsset = asset
        lastDeletedIndex = currentIndex

        dataService.softDelete(asset.localIdentifier, sourceAlbumID: sourceAlbumID)

        withAnimation { showUndoToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showUndoToast = false }
        }
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

    private func advanceOrDismiss() {
    }

    private var albumActionBar: some View {
        VStack {
            Spacer()

            HStack(spacing: 0) {
                glassActionButton(
                    systemImage: isFavorite(currentAsset!) ? "heart.fill" : "heart",
                    label: "Favorite",
                    tint: isFavorite(currentAsset!) ? .red : .white
                ) {
                    toggleFavorite(currentAsset!)
                }

                Button {
                    if !isScanning {
                        performScanForCalendar()
                    }
                } label: {
                    Group {
                        if isScanning {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 22))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .disabled(isScanning)
                .accessibilityLabel("Add to Calendar")

                glassActionButton(systemImage: "folder", label: "Move", tint: .white) {
                    showMoveSheet = true
                }

                glassActionButton(systemImage: "trash", label: "Delete", tint: .red) {
                    performDelete(currentAsset!)
                }
            }
            .padding(.horizontal, 8)
            .glassEffect(.regular.tint(.black.opacity(0.35)), in: Capsule())
            .glassEffectTransition(.identity)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

        private func glassActionButton(systemImage: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(label)
        }

        private func isFavorite(_ asset: PHAsset) -> Bool {
            favoriteOverrides[asset.localIdentifier] ?? asset.isFavorite
        }

        private func toggleFavorite(_ asset: PHAsset) {
            let newValue = !isFavorite(asset)
            favoriteOverrides[asset.localIdentifier] = newValue
            Task { await PhotoLibraryService.shared.setFavorite(newValue, for: asset) }
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

    private func detectEventFromImage(_ asset: PHAsset) async {
        guard !isDetectingEvent else { return }
        isDetectingEvent = true
        defer { isDetectingEvent = false }

        print("🔎 Starting event detection for asset: \(asset.localIdentifier)")
        detectedEvents = []

        guard let cgImage = await PhotoLibraryService.shared.loadFullImage(for: asset)?.cgImage else {
            print("❌ Failed to load image")
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "id-ID"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("❌ Error detecting text: \(error)")
            return
        }

        let lines: [OCRLine] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return OCRLine(text: text, box: observation.boundingBox)
        }
        print("📝 Recognized \(lines.count) lines")

        let events = EventDetectionService.detect(lines: lines, referenceDate: asset.creationDate ?? Date())
        print("🎉 Detected \(events.count) event(s)")

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            detectedEvents = events
        }
    }
}

private struct EventDraft: Identifiable {
    let id = UUID()
    var include = true
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var isMultiDay: Bool
    var location: String
    var notes: String

    init(event: DetectedEvent) {
        title = event.title
        start = event.date
        isAllDay = event.isAllDay || event.endDate.map { !Calendar.current.isDate($0, inSameDayAs: event.date) } == true
        isMultiDay = event.endDate.map { !Calendar.current.isDate($0, inSameDayAs: event.date) } == true
        end = event.endDate ?? event.date.addingTimeInterval(3600)
        location = event.location ?? ""
        notes = event.notes ?? ""
    }

    init() {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8
        let date = cal.date(from: comps) ?? Date()
        title = ""
        start = date
        end = date.addingTimeInterval(3600)
        isAllDay = false
        isMultiDay = false
        location = ""
        notes = ""
    }
}

struct AddToCalendarSheet: View {
    let asset: PHAsset
    let detectedEvents: [DetectedEvent]
    @Binding var isPresented: Bool
    var onSaved: (_ count: Int, _ firstDate: Date) -> Void = { _, _ in }

    @State private var drafts: [EventDraft]
    @State private var isSaving = false
    @State private var scanError: String?

    init(asset: PHAsset, detectedEvents: [DetectedEvent], isPresented: Binding<Bool>, onSaved: @escaping (_ count: Int, _ firstDate: Date) -> Void = { _, _ in }) {
        self.asset = asset
        self.detectedEvents = detectedEvents
        self._isPresented = isPresented
        self.onSaved = onSaved
        _drafts = State(initialValue: detectedEvents.isEmpty ? [EventDraft()] : detectedEvents.map(EventDraft.init))
    }

    private var selectedCount: Int { drafts.filter { $0.include && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    imagePreview

                    if !detectedEvents.isEmpty {
                        scanSuccessMessage
                    } else if let error = scanError {
                        scanErrorMessage(error)
                    } else {
                        noDetectionMessage
                    }

                    ForEach($drafts) { $draft in
                        eventCard($draft)
                    }
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
                            Text(selectedCount > 1 ? "Add \(selectedCount)" : "Add")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(selectedCount == 0 || isSaving)
                }
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }

    private func eventCard(_ draft: Binding<EventDraft>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if drafts.count > 1 {
                    Button {
                        draft.wrappedValue.include.toggle()
                    } label: {
                        Image(systemName: draft.wrappedValue.include ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(draft.wrappedValue.include ? Color.blue : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                TextField("Event title", text: draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            DatePicker(
                "Starts",
                selection: draft.start,
                displayedComponents: draft.wrappedValue.isAllDay ? [.date] : [.date, .hourAndMinute]
            )
            .font(.subheadline)
            .onChange(of: draft.wrappedValue.start) { _, newValue in
                if draft.wrappedValue.isMultiDay && draft.wrappedValue.end < newValue {
                    draft.wrappedValue.end = newValue
                }
            }

            Toggle("All-day", isOn: draft.isAllDay.animation())
                .font(.subheadline)

            Toggle("Multiple Days", isOn: draft.isMultiDay.animation())
                .font(.subheadline)
                .onChange(of: draft.wrappedValue.isMultiDay) { _, isMulti in
                    if isMulti { draft.wrappedValue.isAllDay = true }
                }

            if draft.wrappedValue.isMultiDay {
                DatePicker("Ends", selection: draft.end, in: draft.wrappedValue.start..., displayedComponents: [.date])
                    .font(.subheadline)
            }

            TextField("Location (optional)", text: draft.location)
                .textFieldStyle(.roundedBorder)

            TextField("Notes (optional)", text: draft.notes, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(draft.wrappedValue.include ? 1 : 0.5)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = loadThumbnail() {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 160)
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
                Text(detectedEvents.count > 1 ? "\(detectedEvents.count) Dates Detected" : "Date Detected")
                    .font(.subheadline.weight(.semibold))
                Text("Review the details below, uncheck what you don't need")
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
                Text("No Date Detected")
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
        let toSave = drafts.filter { $0.include && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }

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

            let calendar = Calendar.current

            do {
                for draft in toSave {
                    let event = EKEvent(eventStore: eventStore)
                    event.title = draft.title
                    event.calendar = eventStore.defaultCalendarForNewEvents

                    if draft.isMultiDay {
                        let startDay = calendar.startOfDay(for: draft.start)
                        let endDay = calendar.startOfDay(for: max(draft.end, draft.start))
                        event.isAllDay = true
                        event.startDate = startDay
                        event.endDate = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
                    } else if draft.isAllDay {
                        let day = calendar.startOfDay(for: draft.start)
                        event.isAllDay = true
                        event.startDate = day
                        event.endDate = day
                    } else {
                        event.startDate = draft.start
                        event.endDate = draft.end > draft.start ? draft.end : draft.start.addingTimeInterval(3600)
                    }

                    if !draft.location.isEmpty { event.location = draft.location }
                    if !draft.notes.isEmpty { event.notes = draft.notes }

                    try eventStore.save(event, span: .thisEvent, commit: false)
                }
                try eventStore.commit()

                DispatchQueue.main.async {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isSaving = false
                    if let first = toSave.map(\.start).min() { onSaved(toSave.count, first) }
                    isPresented = false
                }
                print("✅ \(toSave.count) event(s) added to calendar")
            } catch {
                print("❌ Error saving event: \(error)")
                eventStore.reset()
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
    var onSingleTap: (() -> Void)? = nil
    var onZoomedChange: ((Bool) -> Void)? = nil

    @State private var image: UIImage?
    @State private var player: AVPlayer?

    private var isVideo: Bool { asset.mediaType == .video }

    var body: some View {
        ZStack {
            if isVideo {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { if isActive { player.play() } }
                        .onDisappear { player.pause() }
                        .simultaneousGesture(TapGesture().onEnded { onSingleTap?() })
                } else {
                    ProgressView().tint(.white)
                }
            } else if let image {
                ZoomableImageView(
                    image: image,
                    onSingleTap: { onSingleTap?() },
                    onZoomedChange: { zoomed in
                        if isActive { onZoomedChange?(zoomed) }
                    }
                )
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: asset.localIdentifier) {
            if isVideo {
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
                image = await PhotoLibraryService.shared.loadDisplayImage(for: asset)
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
}
