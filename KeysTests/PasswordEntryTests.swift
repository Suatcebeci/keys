import XCTest
@testable import Keys

final class PasswordEntryTests: XCTestCase {
    
    func testPasswordIsolationInCodable() throws {
        let entry = PasswordEntry(
            title: "Test Site",
            username: "user@test.com",
            password: "super_secret_password_123",
            website: "https://example.com",
            notes: "Kurtarma kodu: 998877"
        )
        
        // JSON encode et
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // JSON içinde şifre KESİNLİKLE bulunmamalı
        XCTAssertFalse(jsonString.contains("super_secret_password_123"), "Şifre metadata JSON içerisine sızdı!")
        
        // JSON'dan tekrar decode et
        let decoder = JSONDecoder()
        let decodedEntry = try decoder.decode(PasswordEntry.self, from: data)
        
        // Decode edilen kayıtta cachedPassword nil olmalı
        XCTAssertNil(decodedEntry.cachedPassword, "Decode edilen nesnede şifre nil olmalıdır.")
        XCTAssertEqual(decodedEntry.title, "Test Site")
        XCTAssertEqual(decodedEntry.username, "user@test.com")
        XCTAssertEqual(decodedEntry.website, "https://example.com")
        XCTAssertEqual(decodedEntry.notes, "Kurtarma kodu: 998877")
    }
    
    func testBackwardCompatibilityWithLegacyCategoryJSON() throws {
        // Eski sürümde category alanı içeren Keychain JSON verisi simülasyonu
        let legacyJSON = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "title": "Eski Kayıt",
            "username": "legacy_user",
            "website": "legacy.com",
            "notes": "Eski not",
            "category": "E-posta",
            "createdAt": 732000000.0,
            "updatedAt": 732000000.0
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        let entry = try decoder.decode(PasswordEntry.self, from: data)
        
        XCTAssertEqual(entry.title, "Eski Kayıt")
        XCTAssertEqual(entry.username, "legacy_user")
        XCTAssertEqual(entry.website, "legacy.com")
        XCTAssertEqual(entry.notes, "Eski not")
        XCTAssertNil(entry.cachedPassword)
    }
    
    func testSearchMatching() {
        let entry = PasswordEntry(
            title: "GitHub Kişisel",
            username: "developer_octocat",
            website: "github.com",
            notes: "SSH key backed up"
        )
        
        XCTAssertTrue(entry.matches(query: "github"))
        XCTAssertTrue(entry.matches(query: "octocat"))
        XCTAssertTrue(entry.matches(query: "GITHUB"))
        XCTAssertTrue(entry.matches(query: "Kişisel"))
        XCTAssertTrue(entry.matches(query: "kisisel") || entry.matches(query: "kişisel"))
        XCTAssertFalse(entry.matches(query: "SSH"), "Notes aramaya kesinlikle dahil edilmemelidir!")
        XCTAssertFalse(entry.matches(query: "instagram"))
        XCTAssertTrue(entry.matches(query: "")) // Boş arama her şeyi getirmeli
    }
}
