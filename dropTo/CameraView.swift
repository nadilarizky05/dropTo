//
//  CameraView.swift
//  CH2
//
//  Created by Nadila Rizky Amelia on 26/04/26.
//

import SwiftUI
import UIKit
import MobileCoreServices

struct CameraView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onCaptureImage: (UIImage) -> Void
    var onCaptureVideo: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            
            let mediaType = info[.mediaType] as? String
            
            if mediaType == "public.image",
               let image = info[.originalImage] as? UIImage {
                parent.onCaptureImage(image)
                
            } else if mediaType == "public.movie",
                      let videoURL = info[.mediaURL] as? URL {
                parent.onCaptureVideo(videoURL)
            }
            
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
