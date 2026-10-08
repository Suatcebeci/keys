import Foundation
import UIKit
import UniformTypeIdentifiers

/// Güvenli Pano (Clipboard) Yönetim Servisi.
///
/// GÜVENLİK ÖZELLİKLERİ:
/// 1. `UIPasteboard.OptionsKey.localOnly: true`:
///    Şifrenin Apple Universal Clipboard (Handoff) üzerinden Bluetooth/Wi-Fi ile diğer Apple
///    cihazlarına (Mac, iPad vb.) aktarılmasını donanımsal/sistem seviyesinde KESİNLİKLE ENGELLER.
/// 2. `UIPasteboard.OptionsKey.expirationDate`:
///    Uygulama arka plana geçtiğinde veya kapandığında iOS Timer'ları askıya alsa dahi,
///    işletim sistemi panoyu belirtilen sürede (45 sn) kendiliğinden siler.
/// 3. Başka Uygulama İçeriğini Koruması:
///    Temizleme anında yalnızca bizim kopyaladığımız şifre hala duruyorsa silinir; kullanıcının
///    bu esnada başka bir uygulamadan kopyaladığı veriler silinmez.
@MainActor
public final class ClipboardService: ObservableObject {
    public static let shared = ClipboardService()
    
    @Published public var secondsRemaining: Int = 0
    @Published public var isCopied: Bool = false
    
    private var expirationTimer: Timer?
    private var lastCopiedHash: Int?
    private var activeExpirationDate: Date?
    
    private init() {}
    
    /// Hassas metni panoya yalnızca yerel cihazda kalacak şekilde ve son kullanma tarihiyle kopyalar.
    public func copySensitiveText(_ text: String, timeout: TimeInterval = SecurityConstants.clipboardClearTimeoutSeconds) {
        guard !text.isEmpty else { return }
        
        let expirationDate = Date().addingTimeInterval(timeout)
        self.activeExpirationDate = expirationDate
        self.lastCopiedHash = text.hashValue
        self.isCopied = true
        self.secondsRemaining = Int(timeout)
        
        // 1. iOS Sistem Seviyesinde Yerel ve Süreli Pano Ayarı (Primary Security Mechanism)
        let item: [String: Any] = [
            UTType.utf8PlainText.identifier: text
        ]
        let options: [UIPasteboard.OptionsKey: Any] = [
            .localOnly: true,              // Universal Clipboard / Handoff aktarımını engelle
            .expirationDate: expirationDate // İşletim sistemi arka plandayken bile panoyu bu tarihte siler
        ]
        
        UIPasteboard.general.setItems([item], options: options)
        SecureLogger.info("Şifre panoya yerel ve süreli olarak kopyalandı")
        
        // 2. Uygulama İçi UI Geri Sayımı İçin Yardımcı Timer (Secondary / UI Helper)
        expirationTimer?.invalidate()
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] currentTimer in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let expiration = self.activeExpirationDate {
                    let remaining = Int(expiration.timeIntervalSinceNow)
                    if remaining > 0 {
                        self.secondsRemaining = remaining
                    } else {
                        self.clearClipboardIfMatching()
                        currentTimer.invalidate()
                    }
                } else {
                    currentTimer.invalidate()
                }
            }
        }
    }
    
    /// Uygulama ön plana geldiğinde panonun süresini senkronize eder
    public func syncStateOnForeground() {
        guard let expiration = activeExpirationDate else { return }
        if Date() >= expiration {
            clearClipboardIfMatching()
        } else {
            secondsRemaining = Int(expiration.timeIntervalSinceNow)
        }
    }
    
    /// Panoyu yalnızca bizim kopyaladığımız şifre duruyorsa temizler
    public func clearClipboardIfMatching() {
        expirationTimer?.invalidate()
        expirationTimer = nil
        secondsRemaining = 0
        isCopied = false
        activeExpirationDate = nil
        
        // Güvenlik: Yalnızca mevcut panodaki metin bizim kopyaladığımız metinse sil
        if let currentText = UIPasteboard.general.string,
           let lastHash = lastCopiedHash,
           currentText.hashValue == lastHash {
            UIPasteboard.general.items = []
            SecureLogger.info("Pano süresi dolduğu için güvenle temizlendi")
        }
        
        lastCopiedHash = nil
    }
}
