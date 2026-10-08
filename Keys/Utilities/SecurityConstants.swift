import Foundation
import Security

/// Uygulama genelinde kullanılan güvenlik ve anahtar sabitleri.
/// Bu sabitler cihaz dışına çıkmaz ve yalnızca yerel kasanın bütünlüğü için kullanılır.
public enum SecurityConstants {
    
    /// Keychain hizmet tanımlayıcısı (Service Identifier)
    public static let keychainService = "com.offlinevault.keys.service"
    
    /// Kasa içerisindeki şifrelenmiş metadata dizini için anahtar
    public static let vaultMetadataAccountKey = "com.offlinevault.entries.metadata"
    
    /// Güncelleme ve çökme kurtarması için metadata yedek anahtarı
    public static let vaultMetadataBackupAccountKey = "com.offlinevault.entries.metadata.backup"
    
    /// Bireysel şifre kayıtlarının Keychain üzerindeki öneki
    public static let passwordKeyPrefix = "com.offlinevault.password."
    
    /// Pano (Clipboard) otomatik temizleme süresi (saniye cinsinden)
    public static let clipboardClearTimeoutSeconds: TimeInterval = 45.0
    
    /// Uygulama arka plana geçtiğinde otomatik kilitlenme için bekleme süresi (0 = anında kilit)
    public static let autoLockGracePeriodSeconds: TimeInterval = 0.0
    
    /// Keychain öğelerinin erişilebilirlik seviyesi:
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
    /// 1. Verilere yalnızca cihazın ekran kilidi açıkken erişilebilir.
    /// 2. Veriler cihaz yedeğine (iCloud/Finder) aktarılamaz veya başka bir cihaza taşınamaz ("ThisDeviceOnly").
    /// 3. Cihaz kilitlendiği anda şifreleme anahtarları donanımsal Secure Enclave / işletim sistemi tarafından bellekten silinir.
    public static let defaultAccessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
}
