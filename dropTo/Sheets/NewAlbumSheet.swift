import SwiftUI
import UIKit

struct NewAlbumSheet: View {
    let dataService: DataService
    var onCreate: ((Album) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var albumTitle = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.primary)

                Spacer()

                Text("New Album")
                    .font(.headline)

                Spacer()

                Button("Create") { createAlbum() }
                    .fontWeight(.semibold)
            }
            .padding(.top, 20)

            AutoFocusTextField(text: $albumTitle, placeholder: "Album Title", onSubmit: createAlbum)
                .frame(height: 44)
                .padding(.horizontal, 14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(190)])
        .presentationDragIndicator(.visible)
    }

    private func createAlbum() {
        let title = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAlbum = dataService.createAlbum(title: title.isEmpty ? "Untitled Album" : title)
        onCreate?(newAlbum)
        dismiss()
    }
}

private struct AutoFocusTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> FocusTextField {
        let field = FocusTextField()
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.returnKeyType = .done
        field.autocapitalizationType = .words
        field.clearButtonMode = .whileEditing
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: FocusTextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AutoFocusTextField
        init(_ parent: AutoFocusTextField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }

    final class FocusTextField: UITextField {
        private var didFocus = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !didFocus else { return }
            didFocus = true
            becomeFirstResponder()
        }
    }
}
