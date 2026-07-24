//
//  CameraPicker.swift
//  dropTo
//
//  SwiftUI doesn't have a built-in camera view, so we borrow the
//  older UIKit one (`UIImagePickerController`) and wrap it so SwiftUI
//  can use it like any other View. This is a very common beginner
//  pattern called a "UIViewControllerRepresentable bridge".
//
//  This picker supports BOTH photo and video — same as the stock
//  Camera app, the user gets a Photo/Video switcher on screen.
//

import SwiftUI
import UIKit

/// What the camera handed back: either a still photo, or a video
/// saved temporarily at a file URL (we move it into the Photos
/// library right after).
enum CapturedMedia {
    case photo(UIImage)
    case video(URL)
}

struct CameraPicker: UIViewControllerRepresentable {
    var onMediaCaptured: (CapturedMedia) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        // Offer both photo AND video (this is what makes the on-screen
        // Photo/Video switcher appear, just like the built-in Camera app).
        picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? ["public.image"]

        // Match the real Camera app's quality — .typeHigh is the best
        // option UIImagePickerController exposes.
        picker.videoQuality = .typeHigh

        // Default to flash OFF, as requested (user can still tap the
        // on-screen flash icon to turn it on themselves).
        picker.cameraFlashMode = .off

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onMediaCaptured: onMediaCaptured, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onMediaCaptured: (CapturedMedia) -> Void
        let dismiss: DismissAction

        init(onMediaCaptured: @escaping (CapturedMedia) -> Void, dismiss: DismissAction) {
            self.onMediaCaptured = onMediaCaptured
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let mediaType = info[.mediaType] as? String

            if mediaType == "public.movie", let videoURL = info[.mediaURL] as? URL {
                onMediaCaptured(.video(videoURL))
            } else if let image = info[.originalImage] as? UIImage {
                onMediaCaptured(.photo(image))
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
