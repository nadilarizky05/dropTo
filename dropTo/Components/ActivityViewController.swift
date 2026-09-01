import SwiftUI
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    
    //============================================================================
    // PHASE 1: BUAT FUNCTION UTK MENAMPILKAN SHARE SHEET
    //============================================================================
    // SWIFT UI BELUM PUNYA, JADI KITA BUAT MANUAL PAKAI UIKIT UNTUK SHARENYA
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.permittedArrowDirections = []
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
