import Foundation
import Security
import LocalAuthentication

/// Keychain işlemleri sırasında oluşabilecek olası hata durumları.
public enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidData
    case accessControlCreationFailed
    case unhandledError(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "İstenen anahtar Keychain içerisinde bulunamadı."
        case .duplicateItem:
            return "Bu anahtar Keychain içerisinde zaten mevcut."
        case .invalidData:
            return "Keychain'den dönen veri beklenen biçimde değil."
        case .accessControlCreationFailed:
            return "Biyometrik erişim denetimi (SecAccessControl) nesnesi oluşturulamadı."
        case .unhandledError(let status):
            return "Keychain işleminde hata oluştu. OSStatus: \(status)"
        }
    }
}

/// Apple'ın yerel Security framework'ünü ve donanım destekli SecAccessControl altyapısını
/// kullanan yüksek güvenlikli Keychain servisi.
///
/// GERÇEK PLATFORM YEDEKLEME DAVRANIŞI (BACKUP VERIFICATION):
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
/// 1. iCloud Backup & iCloud Keychain: Bu özniteliğe sahip veriler KESİNLİKLE iCloud'a yedeklenmez ve senkronize edilmez.
/// 2. Şifresiz Finder/iTunes Yedekleri: Keychain verileri şifresiz yerel yedeklemelere KESİNLİKLE dahil edilmez.
/// 3. Şifreli Yerel Yedekler (Encrypted Local Backups): Veriler yedeğe alınsa bile cihazın benzersiz donanım
///    UID'sine (Secure Enclave) bağlıdır. Başka bir cihaza ("ThisDeviceOnly") ASLA aktarılamaz ve çözülemez.
///    Yalnızca aynı fiziksel cihaza geri yüklendiğinde erişilebilir.
public final class KeychainService {
    
    public static let shared = KeychainService()
    
    private let service: String
    private let accessibility: CFString
    
    public init(
        service: String = SecurityConstants.keychainService,
        accessibility: CFString = SecurityConstants.defaultAccessibility
    ) {
        self.service = service
        self.accessibility = accessibility
    }
    
    // MARK: - SecAccessControl Oluşturma
    
    /// Biyometrik veya cihaz parolası doğrulamasını donanım düzeyinde zorunlu kılan SecAccessControl nesnesi
    private func createBiometricAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            accessibility,
            .userPresence, // Face ID / Touch ID veya Cihaz Parolası
            &error
        ) else {
            let cfError = error?.takeRetainedValue()
            SecureLogger.error("SecAccessControl oluşturulamadı", errorCode: cfError != nil ? CFErrorGetCode(cfError) : -1)
            throw KeychainError.accessControlCreationFailed
        }
        return accessControl
    }
    
    // MARK: - Ham Veri (Data) İşlemleri - Sıfır Fazladan String Dönüşümü
    
    /// Belirtilen hesaba ait ham veriyi (Data) Keychain'e kaydeder.
    /// `requireAccessControl` true ise öğe işletim sistemi düzeyinde SecAccessControl ile kilitlenir.
    public func saveData(_ data: Data, forAccount account: String, requireAccessControl: Bool = false) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        // Önce var olup olmadığını kontrol et
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            // Güncelleme: Mevcut veriyi güncelle
            var attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            if requireAccessControl {
                let accessControl = try createBiometricAccessControl()
                attributesToUpdate[kSecAttrAccessControl as String] = accessControl
            } else {
                attributesToUpdate[kSecAttrAccessible as String] = accessibility
            }
            
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                SecureLogger.error("Keychain güncelleme hatası", errorCode: Int(updateStatus))
                throw KeychainError.unhandledError(status: updateStatus)
            }
        } else if status == errSecItemNotFound {
            // Yeni ekleme
            var newQuery = baseQuery
            newQuery[kSecValueData as String] = data
            
            if requireAccessControl {
                let accessControl = try createBiometricAccessControl()
                newQuery[kSecAttrAccessControl as String] = accessControl
            } else {
                newQuery[kSecAttrAccessible as String] = accessibility
            }
            
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                SecureLogger.error("Keychain ekleme hatası", errorCode: Int(addStatus))
                throw KeychainError.unhandledError(status: addStatus)
            }
        } else {
            SecureLogger.error("Keychain sorgu hatası", errorCode: Int(status))
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Belirtilen hesaba ait ham veriyi (Data) okur.
    /// Biyometrik doğrulamadan geçmiş LAContext iletilirse kullanıcıya tekrar sormadan donanım anahtarını çözer.
    public func readData(forAccount account: String, context: LAContext? = nil) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        // Eğer kimlik doğrulanmış LAContext varsa ekle (Çift Face ID sormasını engeller)
        if let authContext = context {
            query[kSecUseAuthenticationContext as String] = authContext
        }
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        
        guard status == errSecSuccess else {
            SecureLogger.error("Keychain okuma hatası", errorCode: Int(status))
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
    
    /// Belirtilen hesabı Keychain'den siler
    public func deleteData(forAccount account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            SecureLogger.error("Keychain silme hatası", errorCode: Int(status))
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Şifre (Secret) Kolaylık Metotları (SecAccessControl Korumalı)
    
    /// Şifreyi donanımsal SecAccessControl korumasıyla kaydeder
    public func saveSecret(_ secret: String, forAccount account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try saveData(data, forAccount: account, requireAccessControl: true)
    }
    
    /// Şifreyi doğrulanmış LAContext ile donanım kilidini açarak okur
    public func readSecret(forAccount account: String, context: LAContext? = nil) throws -> String {
        let data = try readData(forAccount: account, context: context)
        guard let secret = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return secret
    }
    
    public func deleteSecret(forAccount account: String) throws {
        try deleteData(forAccount: account)
    }
    
    // MARK: - Kasa Metadata Koleksiyonu (Doğrudan Data olarak Keychain'e Yazılır)
    
    /// Metadata listesini doğrudan Data olarak Keychain'e kaydeder.
    /// Güncelleme öncesinde mevcut geçerli metadata'yı yedek anahtara kopyalar (Güvenli Güncelleme / Safe Migration).
    public func saveVaultMetadata(_ entries: [PasswordEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        
        // 1. Önce mevcut veriyi yedek anahtara kopyala (varsa)
        if let currentData = try? readData(forAccount: SecurityConstants.vaultMetadataAccountKey), !currentData.isEmpty {
            try? saveData(currentData, forAccount: SecurityConstants.vaultMetadataBackupAccountKey, requireAccessControl: false)
        }
        
        // 2. Yeni metadata'yı kaydet
        try saveData(data, forAccount: SecurityConstants.vaultMetadataAccountKey, requireAccessControl: false)
    }
    
    /// Keychain içerisindeki metadata Data'sını güvenli ve hata toleranslı şekilde decode eder.
    /// Ana metadata bozulmuş veya bulunamamışsa otomatik olarak yedek anahtardan kurtarma yapar.
    public func loadVaultMetadata() throws -> [PasswordEntry] {
        // 1. Ana anahtardan oku
        do {
            let data = try readData(forAccount: SecurityConstants.vaultMetadataAccountKey)
            if let entries = decodeEntries(from: data), !entries.isEmpty {
                return entries
            }
            // Ana anahtar boş veya bozuk çıktıysa yedeğe bak
            if let backupData = try? readData(forAccount: SecurityConstants.vaultMetadataBackupAccountKey),
               let backupEntries = decodeEntries(from: backupData), !backupEntries.isEmpty {
                SecureLogger.info("Ana metadata okunamadı, yedek metadatadan başarıyla kurtarıldı")
                return backupEntries
            }
            return []
        } catch KeychainError.itemNotFound {
            // Ana anahtar bulunamadıysa yedek anahtara bak
            if let backupData = try? readData(forAccount: SecurityConstants.vaultMetadataBackupAccountKey),
               let backupEntries = decodeEntries(from: backupData), !backupEntries.isEmpty {
                SecureLogger.info("Ana metadata bulunamadı, yedek metadatadan kurtarıldı")
                return backupEntries
            }
            return []
        }
    }
    
    /// Hata toleranslı JSON decode (Dizi içindeki tekil bozuk kayıtlar diğerlerinin kaybına yol açmaz)
    private func decodeEntries(from data: Data) -> [PasswordEntry]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // A. Doğrudan dizi decode etmeyi dene
        if let directList = try? decoder.decode([PasswordEntry].self, from: data) {
            return directList
        }
        
        // B. Bozuk eleman toleranslı failable container ile kurtarmayı dene
        struct FailableEntry: Decodable {
            let entry: PasswordEntry?
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.entry = try? container.decode(PasswordEntry.self)
            }
        }
        
        if let failableList = try? decoder.decode([FailableEntry].self, from: data) {
            let recovered = failableList.compactMap { $0.entry }
            if !recovered.isEmpty {
                SecureLogger.info("Failable decode ile kayıtlar kurtarıldı")
                return recovered
            }
        }
        
        return nil
    }
    
    // MARK: - Test ve Sıfırlama Yardımcıları
    
    /// Test ve kurtarma amaçlı hata toleranslı ayrıştırma metodu.
    func safeDecodeEntries(from data: Data) -> [PasswordEntry] {
        return decodeEntries(from: data) ?? []
    }
    
    /// Belirtilen service adına ait tüm Keychain generic password kayıtlarını siler.
    public func clearAllData() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            SecureLogger.error("Keychain tüm verileri silme hatası", errorCode: Int(status))
            throw KeychainError.unhandledError(status: status)
        }
    }
}
