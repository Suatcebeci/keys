import Foundation
import CryptoKit
import CommonCrypto

/// Şifreli yedekleme ve geri yükleme işlemlerinde oluşabilecek hatalar
public enum BackupError: LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case passwordTooShort
    case passwordsDoNotMatch
    case keyDerivationFailed
    case encryptionFailed
    case authenticationFailed
    case decryptionFailed
    case invalidPayload
    case noEntriesToExport
    case fileReadFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Geçersiz yedek dosyası: Keys yedek biçimi tanınamadı."
        case .unsupportedVersion:
            return "Desteklenmeyen yedek versiyonu."
        case .passwordTooShort:
            return "Yedek parolası en az 12 karakter olmalıdır."
        case .passwordsDoNotMatch:
            return "Girilen parolalar birbiriyle eşleşmiyor."
        case .keyDerivationFailed:
            return "Şifreleme anahtarı türetilemedi."
        case .encryptionFailed:
            return "Yedek dosyası şifrelenirken hata oluştu."
        case .authenticationFailed:
            return "Biyometrik doğrulama başarısız oldu."
        case .decryptionFailed:
            return "Parola yanlış veya yedek dosyası bozulmuş/değiştirilmiş."
        case .invalidPayload:
            return "Yedek içeriği geçerli bir kasa verisi içermiyor."
        case .noEntriesToExport:
            return "Dışa aktarılacak kayıt bulunmuyor."
        case .fileReadFailed:
            return "Yedek dosyası okunamadı."
        }
    }
}

/// Şifrelenmiş yedek paketi içerisindeki tekil kayıt modeli
public struct BackupEntry: Codable {
    public let id: UUID
    public let recordType: RecordType
    public let title: String
    public let username: String
    public let website: String
    public let notes: String
    public let password: String
    public let createdAt: Date
    public let updatedAt: Date
    
    public init(
        id: UUID,
        recordType: RecordType,
        title: String,
        username: String,
        website: String,
        notes: String,
        password: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.recordType = recordType
        self.title = title
        self.username = username
        self.website = website
        self.notes = notes
        self.password = password
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Şifreli yedeğin çözülmüş ana yükü
public struct BackupPayload: Codable {
    public let version: Int
    public let createdAt: Date
    public let appVersion: String
    public let entries: [BackupEntry]
    
    public init(version: Int = 1, createdAt: Date = Date(), appVersion: String, entries: [BackupEntry]) {
        self.version = version
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.entries = entries
    }
}

/// Keys uygulamasına özel şifreli, bütünlük doğrulamalı yedekleme servisi.
///
/// Dosya Formatı (.keysbackup):
/// [0..9]   : Magic Bytes "KEYSBACKUP" (10 bytes ASCII)
/// [10]     : Format Versiyonu (UInt8 = 1)
/// [11..42] : Salt (32 bytes cryptographically secure random)
/// [43..]   : AES-256-GCM Combined Data (12-byte Nonce + Ciphertext + 16-byte Tag)
///
/// Kriptografi:
/// - KDF: PBKDF2-HMAC-SHA256 (100,000 iterasyon, 32-byte anahtar)
/// - Şifreleme: AES-256-GCM AEAD
/// - Bütünlük (AAD): Magic + Version + Salt başlığına kriptografik olarak bağlıdır.
public final class BackupService {
    public static let shared = BackupService()
    
    /// 10-byte Magic Header: "KEYSBACKUP"
    public static let magicHeader = Data("KEYSBACKUP".utf8)
    public static let currentVersion: UInt8 = 1
    public static let saltByteCount = 32
    public static let pbkdf2Iterations: UInt32 = 100_000
    
    private init() {}
    
    // MARK: - Key Derivation (PBKDF2-HMAC-SHA256)
    public static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw BackupError.keyDerivationFailed
        }
        
        var derivedKeyData = Data(count: 32)
        let derivedKeyCount = derivedKeyData.count
        let result = derivedKeyData.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        derivedKeyCount
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            throw BackupError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedKeyData)
    }
    
    // MARK: - Export / Encrypt
    public func createEncryptedBackupData(payload: BackupPayload, password: String) throws -> Data {
        guard password.count >= 12 else {
            throw BackupError.passwordTooShort
        }
        
        // 1. JSON Payload Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)
        
        // 2. Kriptografik Rastgele Salt (32 bytes)
        var salt = Data(count: Self.saltByteCount)
        let saltResult = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Self.saltByteCount, $0.baseAddress!)
        }
        guard saltResult == errSecSuccess else {
            throw BackupError.encryptionFailed
        }
        
        // 3. Simetrik Anahtar Türet (PBKDF2-HMAC-SHA256, 100.000 döngü)
        let symmetricKey = try Self.deriveKey(password: password, salt: salt)
        
        // 4. Doğrulanmış İlişkili Veri (AAD): Magic + Version + Salt
        var aad = Data()
        aad.append(Self.magicHeader)
        aad.append(Self.currentVersion)
        aad.append(salt)
        
        // 5. AES-256-GCM AEAD Şifreleme
        let sealedBox = try AES.GCM.seal(payloadData, using: symmetricKey, authenticating: aad)
        guard let combined = sealedBox.combined else {
            throw BackupError.encryptionFailed
        }
        
        // 6. Dosya Paketini Oluştur:
        var finalData = Data()
        finalData.append(Self.magicHeader)
        finalData.append(Self.currentVersion)
        finalData.append(salt)
        finalData.append(combined)
        
        return finalData
    }
    
    // MARK: - Import / Decrypt
    public func decryptBackupData(_ fileData: Data, password: String) throws -> BackupPayload {
        // Minimum uzunluk kontrolü: 10(magic) + 1(ver) + 32(salt) + 12(nonce) + 16(tag) = 71 bytes
        guard fileData.count >= 71 else {
            throw BackupError.invalidFormat
        }
        
        // 1. Magic Header Kontrolü
        let magic = fileData.subdata(in: 0..<10)
        guard magic == Self.magicHeader else {
            throw BackupError.invalidFormat
        }
        
        // 2. Versiyon Kontrolü
        let version = fileData[10]
        guard version == Self.currentVersion else {
            throw BackupError.unsupportedVersion
        }
        
        // 3. Salt ve Şifreli Kutu Ayrıştırma
        let salt = fileData.subdata(in: 11..<43)
        let sealedBoxData = fileData.subdata(in: 43..<fileData.count)
        
        // 4. Anahtar Türet
        let key = try Self.deriveKey(password: password, salt: salt)
        
        // 5. AEAD Bütünlük ve Şifre Çözme
        var aad = Data()
        aad.append(Self.magicHeader)
        aad.append(version)
        aad.append(salt)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedBoxData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BackupPayload.self, from: decryptedData)
        } catch {
            // Parola yanlışsa veya dosya içeriği 1 bit dahi bozulmuşsa AEAD doğrulaması reddeder
            throw BackupError.decryptionFailed
        }
    }
    
    // MARK: - Başlık Doğrulama (Hızlı Format Kontrolü)
    public func verifyBackupHeader(_ fileData: Data) -> Bool {
        guard fileData.count >= 71 else { return false }
        let magic = fileData.subdata(in: 0..<10)
        return magic == Self.magicHeader && fileData[10] == Self.currentVersion
    }
}
