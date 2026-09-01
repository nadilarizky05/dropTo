import SwiftUI
import UIKit

//============================================================================
// CAMERA PICKER (UIKIT WRAPPER)
//============================================================================
// WRAPPER UIVIEWCONTROLLERREPRESENTABLE BUAT UIIMAGEPICKERCONTROLLER, SUPPORT FOTO & VIDEO

struct CameraPicker: UIViewControllerRepresentable {
    
    //============================================================================
    // PROPERTIES
    //============================================================================
    
    var onMediaCaptured: (CapturedMedia) -> Void // CALLBACK SAAT FOTO/VIDEO DIAMBIL
    @Environment(\.dismiss) private var dismiss   // TUTUP KAMERA
    
    //============================================================================
    // FUNCTION: MAKE UIVIEWCONTROLLER
    //============================================================================
    // BIKIN INSTANCE UIIMAGEPICKERCONTROLLER → SET JADI MODE KAMERA
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? ["public.image"]
        picker.videoQuality = .typeHigh
        picker.cameraFlashMode = .off
        return picker
    }
    
    //============================================================================
    // FUNCTION: UPDATE UIVIEWCONTROLLER
    //============================================================================
    // GAK PERLU UPDATE APAPUN
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    //============================================================================
    // FUNCTION: MAKE COORDINATOR
    //============================================================================
    // BIKIN COORDINATOR BUAT HANDLE DELEGATE UIIMAGEPICKERCONTROLLER
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onMediaCaptured: onMediaCaptured, dismiss: dismiss)
    }
    
    //============================================================================
    // COORDINATOR CLASS
    //============================================================================
    // HANDLE CALLBACK SAAT USER SELESAI AMBIL FOTO/VIDEO ATAU CANCEL
    
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onMediaCaptured: (CapturedMedia) -> Void
        let dismiss: DismissAction
        
        init(onMediaCaptured: @escaping (CapturedMedia) -> Void, dismiss: DismissAction) {
            self.onMediaCaptured = onMediaCaptured
            self.dismiss = dismiss
        }
        
        // CALLBACK SAAT USER SELESAI AMBIL FOTO/VIDEO
        func imagePickerController(_ picker: UIImagePickerController,
                                    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let mediaType = info[.mediaType] as? String
            
            // KALAU VIDEO → AMBIL URL FILE
            if mediaType == "public.movie", let videoURL = info[.mediaURL] as? URL {
                onMediaCaptured(.video(videoURL))
            }
            // KALAU FOTO → AMBIL UIIMAGE
            else if let image = info[.originalImage] as? UIImage {
                onMediaCaptured(.photo(image))
            }
            dismiss()
        }
        
        // CALLBACK SAAT USER CANCEL
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
