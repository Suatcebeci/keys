import SwiftUI
import UIKit

/// iOS / iPadOS yerel paylaşım sayfası (Share Sheet).
/// Geçici dosya paylaşıldıktan veya kullanıcı vazgeçtikten sonra dosyayı diskten otomatik olarak temizler.
public struct ShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    var onComplete: (() -> Void)?
    
    public init(fileURL: URL, onComplete: (() -> Void)? = nil) {
        self.fileURL = fileURL
        self.onComplete = onComplete
    }
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Paylaşım bittiğinde veya iptal edildiğinde geçici dosyayı derhal temizle
            try? FileManager.default.removeItem(at: fileURL)
            onComplete?()
        }
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
