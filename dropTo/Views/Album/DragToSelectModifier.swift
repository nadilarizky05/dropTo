import SwiftUI
import UIKit

@MainActor
final class GridSelectionController {
    static let spaceName = "gridSelectionSpace"

    var frames: [String: CGRect] = [:]
    var isActive = false
    var selected: Binding<Set<String>>?

    weak var lockedScrollView: UIScrollView?

    private var shouldSelect = true
    private var touchDownID: String?
    private var touchDownWasSelected = false
    private var processed: Set<String> = []
    private var lastPoint: CGPoint?

    private func id(at point: CGPoint) -> String? {
        frames.first(where: { $0.value.contains(point) })?.key
    }

    private func apply(_ identifiers: [String]) {
        guard let selected, !identifiers.isEmpty else { return }
        var set = selected.wrappedValue
        for identifier in identifiers {
            if shouldSelect { set.insert(identifier) } else { set.remove(identifier) }
        }
        guard set != selected.wrappedValue else { return }
        withAnimation(.easeOut(duration: 0.12)) { selected.wrappedValue = set }
    }

    func unlockScroll() {
        lockedScrollView?.isScrollEnabled = true
        lockedScrollView = nil
    }

    func touchDown(at point: CGPoint) {
        unlockScroll()
        touchDownID = nil
        processed.removeAll()
        lastPoint = point
        guard isActive, let selected, let identifier = id(at: point) else { return }

        touchDownID = identifier
        touchDownWasSelected = selected.wrappedValue.contains(identifier)
        shouldSelect = !touchDownWasSelected
        processed.insert(identifier)
        apply([identifier])
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    func cancelTouchDown() {
        guard let identifier = touchDownID, let selected else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            if touchDownWasSelected {
                selected.wrappedValue.insert(identifier)
            } else {
                selected.wrappedValue.remove(identifier)
            }
        }
        touchDownID = nil
    }

    func dragMoved(to point: CGPoint) {
        let start = lastPoint ?? point
        let distance = hypot(point.x - start.x, point.y - start.y)
        let steps = max(1, Int(distance / 12))

        var newlyProcessed: [String] = []
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let sample = CGPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t)
            guard let identifier = id(at: sample), processed.insert(identifier).inserted else { continue }
            newlyProcessed.append(identifier)
        }
        if !newlyProcessed.isEmpty {
            apply(newlyProcessed)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
        }
        lastPoint = point
    }

    func end() {
        unlockScroll()
        touchDownID = nil
        processed.removeAll()
        lastPoint = nil
    }
}

private struct GridSelectionKey: EnvironmentKey {
    static let defaultValue: GridSelectionController? = nil
}

extension EnvironmentValues {
    var gridSelection: GridSelectionController? {
        get { self[GridSelectionKey.self] }
        set { self[GridSelectionKey.self] = newValue }
    }
}

struct GridDragSelectionModifier: ViewModifier {
    let isSelecting: Bool
    @Binding var selected: Set<String>

    @State private var controller = GridSelectionController()

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: GridSelectionController.spaceName)
            .environment(\.gridSelection, controller)
            .background(ScrollSelectionInstaller(controller: controller))
            .onAppear { sync() }
            .onChange(of: isSelecting) { _, _ in sync() }
    }

    private func sync() {
        controller.isActive = isSelecting
        controller.selected = $selected
        if !isSelecting { controller.unlockScroll() }
    }
}

extension View {
    func gridDragSelection(isSelecting: Bool, selected: Binding<Set<String>>) -> some View {
        modifier(GridDragSelectionModifier(isSelecting: isSelecting, selected: selected))
    }

    func dragToSelect(
        isSelecting: Binding<Bool>,
        selectedIdentifiers: Binding<Set<String>>,
        identifier: String
    ) -> some View {
        modifier(SelectableCellModifier(identifier: identifier))
    }
}

struct SelectableCellModifier: ViewModifier {
    let identifier: String
    @Environment(\.gridSelection) private var controller

    @State private var lastFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(GridSelectionController.spaceName))
            } action: { frame in
                lastFrame = frame
                controller?.frames[identifier] = frame
            }
            .onAppear {
                if lastFrame != .zero { controller?.frames[identifier] = lastFrame }
            }
            .onDisappear { controller?.frames[identifier] = nil }
    }
}

private final class SelectionTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var controller: GridSelectionController?
    weak var installer: UIView?

    private enum Mode { case undecided, selecting, scrolling }
    private var mode: Mode = .undecided
    private var startPoint: CGPoint = .zero
    private weak var activeScrollView: UIScrollView?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    private func scrollViewForTouch(_ touch: UITouch) -> UIScrollView? {
        guard let installer, installer.window != nil else { return nil }
        var current: UIView? = installer.superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                let local = touch.location(in: scrollView)
                guard scrollView.bounds.contains(local) else { return nil }
                let inset = scrollView.adjustedContentInset
                let visibleY = local.y - scrollView.bounds.origin.y
                guard visibleY >= inset.top, visibleY <= scrollView.bounds.height - inset.bottom else { return nil }
                var responder: UIResponder? = scrollView
                while let next = responder?.next {
                    if let controller = next as? UIViewController {
                        if controller.presentedViewController != nil { return nil }
                        break
                    }
                    responder = next
                }
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first,
           MainActor.assumeIsolated({ TouchExclusionZones.contains(touch.location(in: nil)) }) {
            state = .failed
            return
        }
        guard let touch = touches.first,
              event.allTouches?.count == 1,
              MainActor.assumeIsolated({ controller?.isActive == true }),
              let scrollView = scrollViewForTouch(touch) else {
            state = .failed
            return
        }
        activeScrollView = scrollView
        mode = .undecided
        startPoint = touch.location(in: scrollView)
        MainActor.assumeIsolated { controller?.touchDown(at: startPoint) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let scrollView = activeScrollView, let touch = touches.first else { return }
        let point = touch.location(in: scrollView)

        switch mode {
        case .undecided:
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            guard hypot(dx, dy) > 8 else { return }

            if abs(dx) >= abs(dy) {
                mode = .selecting
                scrollView.isScrollEnabled = false
                MainActor.assumeIsolated {
                    controller?.lockedScrollView = scrollView
                    controller?.dragMoved(to: point)
                }
            } else {
                mode = .scrolling
                MainActor.assumeIsolated { controller?.cancelTouchDown() }
                state = .failed
            }

        case .selecting:
            MainActor.assumeIsolated { controller?.dragMoved(to: point) }

        case .scrolling:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
    }

    override func reset() {
        unlock()
        mode = .undecided
        activeScrollView = nil
    }

    private func finish() {
        unlock()
        MainActor.assumeIsolated { controller?.end() }
        state = (state == .possible) ? .failed : .ended
    }

    private func unlock() {
        activeScrollView?.isScrollEnabled = true
        MainActor.assumeIsolated { controller?.unlockScroll() }
    }
}

private struct ScrollSelectionInstaller: UIViewRepresentable {
    let controller: GridSelectionController

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.controller = controller
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        uiView.controller = controller
    }

    final class InstallerView: UIView {
        weak var controller: GridSelectionController? {
            didSet { recognizer?.controller = controller }
        }
        private var recognizer: SelectionTouchRecognizer?
        private weak var attachedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let recognizer = SelectionTouchRecognizer(target: nil, action: nil)
            recognizer.controller = controller
            recognizer.installer = self
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            attachedWindow = window
        }

        private func detach() {
            MainActor.assumeIsolated { controller?.unlockScroll() }
            if let recognizer { attachedWindow?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            attachedWindow = nil
        }
    }
}

private struct SwipeBackDisabler: UIViewControllerRepresentable {
    let disabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.disabled = disabled
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.disabled = disabled
        controller.apply()
    }

    final class Controller: UIViewController {
        var disabled = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = true
        }

        func apply() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = !disabled
            navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = !disabled
        }
    }
}

extension View {
    func swipeBackDisabled(_ disabled: Bool = true) -> some View {
        background(SwipeBackDisabler(disabled: disabled))
    }
}

@MainActor
enum TouchExclusionZones {
    static var rects: [UUID: CGRect] = [:]

    static func contains(_ point: CGPoint) -> Bool {
        rects.values.contains { $0.contains(point) }
    }
}

struct TouchExclusionModifier: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                TouchExclusionZones.rects[id] = frame
            }
            .onDisappear { TouchExclusionZones.rects[id] = nil }
    }
}

extension View {
    func excludesSelectionTouches() -> some View {
        modifier(TouchExclusionModifier())
    }
}
