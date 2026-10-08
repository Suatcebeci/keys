import Foundation

/// Bir şifre kaydının temel veri modeli: Giriş (Login) veya Banka (Bank).
/// Güvenlik mimarisi gereği metadata (başlık, kullanıcı adı, web sitesi, notlar) ile
/// gizli kimlik bilgisi (şifre) birbirinden izole edilir.
public struct PasswordEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    public var recordType: RecordType
    public var title: String // Login için Başlık, Banka için Banka Adı
    public var username: String // Yalnızca Login
    public var website: String // Yalnızca Login
    public var notes: String // Yalnızca Login
    public let createdAt: Date
    public var updatedAt: Date
    
    /// Şifre değeri bellekte yalnızca kullanıcı talep ettiğinde Keychain'den yüklenir.
    /// Kalıcı metadata JSON serileştirmesine dahil edilmez.
    public var cachedPassword: String?
    
    public init(
        id: UUID = UUID(),
        recordType: RecordType = .login,
        title: String,
        username: String = "",
        password: String? = nil,
        website: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.recordType = recordType
        self.title = title
        self.username = username
        self.cachedPassword = password
        self.website = website
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Codable: cachedPassword alanını serileştirme dışında tutuyoruz.
    enum CodingKeys: String, CodingKey {
        case id
        case recordType
        case title
        case username
        case website
        case notes
        case createdAt
        case updatedAt
    }
    
    // Güvenli Geriye Dönük Uyumluluk (Backward Compatibility):
    // Güncelleme sonrasında farklı tarih biçimleri (ISO8601, ISO8601 fractional, timestamp),
    // string ID'ler veya eksik alanlar olması durumunda hata fırlatmayarak veriyi kurtarır.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 1. ID: UUID veya String olarak çöz, başarısızsa yeni UUID oluştur
        if let decodedID = try? container.decode(UUID.self, forKey: .id) {
            self.id = decodedID
        } else if let idString = try? container.decode(String.self, forKey: .id),
                  let parsedUUID = UUID(uuidString: idString) {
            self.id = parsedUUID
        } else {
            self.id = UUID()
        }
        
        // 2. RecordType: Eksikse veya bilinmiyorsa varsayılan .login
        self.recordType = (try? container.decodeIfPresent(RecordType.self, forKey: .recordType)) ?? .login
        
        // 3. Title: Boşsa "Başlıksız Kayıt"
        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Başlıksız Kayıt"
        
        // 4. String alanları
        self.username = (try? container.decodeIfPresent(String.self, forKey: .username)) ?? ""
        self.website = (try? container.decodeIfPresent(String.self, forKey: .website)) ?? ""
        self.notes = (try? container.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        
        // 5. Tarihler: Date, String (ISO8601/fractional) veya Double (timestamp) destekle
        self.createdAt = Self.decodeDate(from: container, forKey: .createdAt) ?? Date()
        self.updatedAt = Self.decodeDate(from: container, forKey: .updatedAt) ?? Date()
        self.cachedPassword = nil
    }
    
    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }
        if let timeInterval = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: timeInterval)
        }
        if let dateString = try? container.decode(String.self, forKey: key) {
            let formatter = ISO8601DateFormatter()
            if let d = formatter.date(from: dateString) {
                return d
            }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: dateString) {
                return d
            }
        }
        return nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recordType, forKey: .recordType)
        try container.encode(title, forKey: .title)
        try container.encode(username, forKey: .username)
        try container.encode(website, forKey: .website)
        try container.encode(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    /// Keychain üzerinde bu kayda ait şifrenin saklanacağı benzersiz anahtar
    public var keychainPasswordKey: String {
        return SecurityConstants.passwordKeyPrefix + id.uuidString
    }
    
    /// Arama işlemi için güvenli ve yerelleştirilmiş eşleşme kontrolü
    /// KURAL:
    /// - LOGIN kayıtlarında: Başlık, Kullanıcı Adı ve Web Sitesi taranabilir.
    /// - BANK kayıtlarında: Yalnızca Banka Adı (title) taranabilir.
    /// - Şifre veya gizli notlar aramada KESİNLİKLE taranmaz.
    /// - Türkçe karakter duyarlılığı localizedCaseInsensitiveContains ile sağlanır.
    public func matches(query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }
        switch recordType {
        case .login:
            return title.localizedCaseInsensitiveContains(trimmedQuery) ||
                   username.localizedCaseInsensitiveContains(trimmedQuery) ||
                   website.localizedCaseInsensitiveContains(trimmedQuery)
        case .bank:
            return title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}
