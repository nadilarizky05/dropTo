import SwiftUI
import AVFoundation
import UIKit

struct CameraPicker: View {
    let dataService: DataService
    var onAlbumChanged: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var albumID: UUID
    @State private var albumTitle: String
    @State private var albums: [Album] = []
    @State private var showAlbumList = false
    @State private var controller = CameraController()

    @State private var isVideoMode = false
    @State private var isRecording = false
    @State private var flashOn = false
    @State private var lastThumbnail: UIImage?
    @State private var permissionDenied = false
    @State private var zoom = ZoomModel()

    init(dataService: DataService, initialAlbumID: UUID, onAlbumChanged: @escaping (UUID) -> Void = { _ in }) {
        self.dataService = dataService
        self.onAlbumChanged = onAlbumChanged
        _albumID = State(initialValue: initialAlbumID)
        _albumTitle = State(initialValue: dataService.fetchAlbums().first(where: { $0.id == initialAlbumID })?.title ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if permissionDenied {
                permissionDeniedView
            } else {
                VStack(spacing: 0) {
                    topBar

                    Spacer(minLength: 12)

                    CameraPreviewView(session: controller.session)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            if !zoom.options.isEmpty {
                                CameraZoomOverlay(model: zoom, controller: controller)
                            }
                        }
                        .clipped()

                    Spacer(minLength: 12)

                    bottomBar
                }
                .overlay(alignment: .top) {
                    if showAlbumList { albumListOverlay }
                }
            }
        }
        .onAppear {
            controller.onCapture = { media in
                Task { await dataService.saveCapturedMedia(media, toAlbumWithID: albumID) }
                Task { lastThumbnail = await thumbnail(for: media) }
            }
            controller.onZoomChange = { [zoom] value in zoom.value = value }
            controller.requestAccessAndStart { granted in
                permissionDenied = !granted
                refreshZoom()
            }
        }
        .onDisappear { controller.stop() }
    }

    private func refreshZoom() {
        zoom.options = controller.zoomLabels
        zoom.value = 1
    }

    private var topBar: some View {
        HStack {
            RoundIconButton(systemImage: "xmark") { dismiss() }

            Spacer()

            if !albumTitle.isEmpty {
                Button {
                    albums = dataService.fetchAlbums()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showAlbumList.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(albumTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(showAlbumList ? 180 : 0))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            RoundIconButton(systemImage: flashOn ? "bolt.fill" : "bolt.slash.fill") {
                flashOn.toggle()
                controller.setTorch(on: flashOn)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var albumListOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { showAlbumList = false } }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(albums) { album in
                        Button { switchAlbum(to: album) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.white.opacity(0.9))
                                Text(album.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if album.id == albumID {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.yellow)
                                } else {
                                    Text("\(album.assetIdentifiers.count)")
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if album.id != albums.last?.id {
                            Divider().overlay(.white.opacity(0.25)).padding(.leading, 44)
                        }
                    }
                }
            }
            .frame(width: 280)
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular.tint(.black.opacity(0.55)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.top, 58)
            .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        }
    }

    private func switchAlbum(to album: Album) {
        if album.id != albumID {
            albumID = album.id
            albumTitle = album.title
            lastThumbnail = nil
            onAlbumChanged(album.id)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showAlbumList = false }
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack(spacing: 4) {
                modeButton("VIDEO", isActive: isVideoMode) { setMode(video: true) }
                modeButton("PHOTO", isActive: !isVideoMode) { setMode(video: false) }
            }
            .padding(4)
            .background(.white.opacity(0.12), in: Capsule())

            HStack {
                Button { dismiss() } label: {
                    Group {
                        if let lastThumbnail {
                            Image(uiImage: lastThumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.white.opacity(0.12)
                                .overlay(Image(systemName: "photo.on.rectangle").foregroundStyle(.white.opacity(0.6)))
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.4), lineWidth: 1))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShutterButton(isVideoMode: isVideoMode, isRecording: isRecording) {
                    if isVideoMode {
                        if isRecording {
                            controller.stopRecording()
                        } else {
                            controller.startRecording()
                        }
                        isRecording.toggle()
                    } else {
                        controller.capturePhoto(flashOn: flashOn)
                    }
                }

                RoundIconButton(systemImage: "arrow.triangle.2.circlepath", size: 50) {
                    controller.flipCamera()
                    refreshZoom()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 28)
        }
        .padding(.bottom, 12)
    }

    private func modeButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? .yellow : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(isActive ? Color.white.opacity(0.2) : .clear, in: Capsule())
        }
        .disabled(isRecording)
    }

    private func setMode(video: Bool) {
        guard !isRecording, isVideoMode != video else { return }
        isVideoMode = video
        controller.configureMode(video: video)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera Access Needed")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Enable camera access for dropTo in Settings to take photos.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
    }

    private func thumbnail(for media: CapturedMedia) async -> UIImage? {
        switch media {
        case .photo(let image):
            return image
        case .video(let url):
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            return await withCheckedContinuation { continuation in
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, cgImage, _, _, _ in
                    if let cgImage {
                        continuation.resume(returning: UIImage(cgImage: cgImage))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

private struct RoundIconButton: View {
    let systemImage: String
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.white.opacity(0.15), in: Circle())
        }
    }
}

private struct ShutterButton: View {
    let isVideoMode: Bool
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                if isVideoMode {
                    RoundedRectangle(cornerRadius: isRecording ? 6 : 30, style: .continuous)
                        .fill(.red)
                        .frame(width: isRecording ? 28 : 60, height: isRecording ? 28 : 60)
                        .animation(.easeInOut(duration: 0.2), value: isRecording)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                }
            }
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

@MainActor
final class CameraController: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var currentInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private var position: AVCaptureDevice.Position = .back
    private var isConfigured = false
    private var zoomTarget: CGFloat = 1
    private var zoomCurrent: CGFloat = 1
    private var slideBase: CGFloat = 1
    var onZoomChange: ((Double) -> Void)?
    private var zoomSmoothing: Double = 18
    private var displayLink: CADisplayLink?
    private let zoomWriter = ZoomWriter()
    private var lastTick: CFTimeInterval = 0

    var onCapture: ((CapturedMedia) -> Void)?

    func requestAccessAndStart(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
            start()
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        self.configureSessionIfNeeded()
                        self.start()
                    }
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .photo
        setInput(for: position)
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }
    }

    func stop() {
        stopZoomLink()
        guard session.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session] in
            session.stopRunning()
        }
    }

    private func setInput(for position: AVCaptureDevice.Position) {
        if let currentInput { session.removeInput(currentInput) }
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        currentInput = input
        currentDevice = device
        applyZoomFactor(wideZoomFactor)

        if session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }) == nil,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
    }

    private var hasUltraWide: Bool {
        currentDevice?.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera } == true
    }

    private var wideZoomFactor: CGFloat {
        guard hasUltraWide, let first = currentDevice?.virtualDeviceSwitchOverVideoZoomFactors.first else { return 1 }
        return CGFloat(truncating: first)
    }

    var zoomLabels: [Double] {
        guard position == .back, let device = currentDevice else { return [] }
        var labels: [Double] = hasUltraWide ? [0.5, 1] : [1]
        if device.maxAvailableVideoZoomFactor >= wideZoomFactor * 2 { labels.append(2) }
        return labels
    }

    func beginSlide() {
        slideBase = zoomTarget
    }

    func slide(by distance: CGFloat) {
        guard let device = currentDevice else { return }
        let maxFactor = min(device.maxAvailableVideoZoomFactor, wideZoomFactor * 10)
        let factor = slideBase * CGFloat(pow(2, Double(distance) / 130))
        zoomTarget = min(max(factor, device.minAvailableVideoZoomFactor), maxFactor)
        zoomSmoothing = 30
        startZoomLink()
    }

    func glideZoom(toLabel label: Double) {
        guard let device = currentDevice else { return }
        zoomTarget = min(max(wideZoomFactor * CGFloat(label), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        zoomSmoothing = 7
        startZoomLink()
    }

    private func startZoomLink() {
        guard displayLink == nil, let device = currentDevice else { return }
        zoomCurrent = device.videoZoomFactor
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(zoomTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func zoomTick(_ link: CADisplayLink) {
        guard let device = currentDevice else {
            stopZoomLink()
            return
        }
        let dt = min(link.timestamp - lastTick, 0.05)
        lastTick = link.timestamp

        let logCurrent = log(Double(zoomCurrent))
        let logTarget = log(Double(zoomTarget))
        let delta = logTarget - logCurrent

        if abs(delta) < 0.0015 {
            zoomCurrent = zoomTarget
            zoomWriter.write(zoomCurrent, to: device)
            onZoomChange?(Double(zoomCurrent / wideZoomFactor))
            stopZoomLink()
            return
        }

        let alpha = 1 - exp(-dt * zoomSmoothing)
        zoomCurrent = CGFloat(exp(logCurrent + delta * alpha))
        zoomCurrent = min(max(zoomCurrent, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        zoomWriter.write(zoomCurrent, to: device)
        onZoomChange?(Double(zoomCurrent / wideZoomFactor))
    }

    private func stopZoomLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func applyZoomFactor(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        let clamped = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        try? device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
        zoomTarget = clamped
        zoomCurrent = clamped
    }

    func flipCamera() {
        stopZoomLink()
        position = position == .back ? .front : .back
        session.beginConfiguration()
        setInput(for: position)
        session.commitConfiguration()
    }

    func configureMode(video: Bool) {
        session.beginConfiguration()
        session.sessionPreset = video ? .high : .photo
        session.commitConfiguration()
    }

    func setTorch(on: Bool) {
        guard let device = currentDevice, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func capturePhoto(flashOn: Bool) {
        let settings = AVCapturePhotoSettings()
        if currentDevice?.hasFlash == true {
            settings.flashMode = flashOn ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() {
        movieOutput.stopRecording()
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.onCapture?(.photo(image))
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.onCapture?(.video(outputFileURL))
        }
    }
}

nonisolated final class ZoomWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dropTo.camera.zoom", qos: .userInteractive)
    private let lock = NSLock()
    private var latest: CGFloat = 1
    private var scheduled = false

    func write(_ factor: CGFloat, to device: AVCaptureDevice) {
        lock.lock()
        latest = factor
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needsSchedule else { return }

        queue.async { [self] in
            lock.lock()
            let value = latest
            scheduled = false
            lock.unlock()

            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = value
            device.unlockForConfiguration()
        }
    }
}
