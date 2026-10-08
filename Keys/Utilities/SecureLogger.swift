import Foundation
import os

/// Güvenli günlükleme (logging) yardımcı sınıfı.
/// Şifre, kullanıcı adı veya anahtar gibi hiçbir hassas verinin loglara yazdırılmasına izin vermez.
/// Yalnızca genel teknik olayları ve durum kodlarını kaydeder.
public enum SecureLogger {
    private static let subsystem = "com.offlinevault.keys"
    private static let logger = Logger(subsystem: subsystem, category: "Security")

    /// Genel teknik olay bildirimi (DEBUG modunda çalışır, hassas veri almaz)
    public static func info(_ message: StaticString) {
        #if DEBUG
        logger.info("\(message, privacy: .public)")
        #endif
    }
    
    /// Hata durumları bildirimi (Yalnızca hata kodu veya teknik açıklama)
    public static func error(_ message: StaticString, errorCode: Int? = nil) {
        #if DEBUG
        if let code = errorCode {
            logger.error("\(message, privacy: .public) [Code: \(code)]")
        } else {
            logger.error("\(message, privacy: .public)")
        }
        #endif
    }
}
