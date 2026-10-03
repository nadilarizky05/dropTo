import SwiftUI
import Observation

@Observable
final class ZoomModel {
    var value: Double = 1
    var options: [Double] = []
    var isSliding = false
}

enum ZoomFormat {
    static func text(option: Double, value: Double, active: Bool) -> String {
        guard active else { return option == 0.5 ? "0,5" : String(Int(option)) }
        return valueText(abs(value - option) < 0.05 ? option : value) + "×"
    }

    static func valueText(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

struct CameraZoomOverlay: View {
    let model: ZoomModel
    let controller: CameraController

    private var activeOption: Double? {
        model.options.last(where: { $0 <= model.value + 0.05 }) ?? model.options.first
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.options, id: \.self) { option in
                let isActive = option == activeOption
                Button {
                    controller.glideZoom(toLabel: option)
                } label: {
                    Text(ZoomFormat.text(option: option, value: model.value, active: isActive))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? .yellow : .white)
                        .frame(minWidth: 34, minHeight: 34)
                        .padding(.horizontal, isActive ? 4 : 0)
                        .background(isActive ? Color.black.opacity(0.5) : .clear, in: Capsule())
                }
            }
        }
        .padding(4)
        .background(.black.opacity(0.25), in: Capsule())
        .overlay(alignment: .top) {
            if model.isSliding {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text(ZoomFormat.valueText(model.value) + "×")
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(.yellow)
                        .frame(minWidth: 52)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
                .offset(y: -44)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .simultaneousGesture(slideGesture)
        .padding(.bottom, -2)
    }

    private let deadZone: CGFloat = 4

    private var slideGesture: some Gesture {
        DragGesture(minimumDistance: deadZone)
            .onChanged { value in
                if !model.isSliding {
                    controller.beginSlide()
                    withAnimation(.easeOut(duration: 0.12)) { model.isSliding = true }
                }
                let dx = value.translation.width
                controller.slide(by: dx - (dx > 0 ? deadZone : -deadZone))
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.2)) { model.isSliding = false }
            }
    }
}
