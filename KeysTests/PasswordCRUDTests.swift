import XCTest
import Security
@testable import Keys

@MainActor
final class PasswordCRUDTests: XCTestCase {
    
    var viewModel: PasswordVaultViewModel!
    var keychainService: KeychainService!
    
    override func setUp() {
        super.setUp()
        keychainService = KeychainService(
            service: "com.offlinevault.keys.test.crud",
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        viewModel = PasswordVaultViewModel(keychainService: keychainService)
        viewModel.isUnlocked = true
    }
    
    override func tearDown() {
        // Test sonrası tüm oluşturulan kayıtları ve secret'ları temizle
        for entry in viewModel.entries {
            try? keychainService.deleteSecret(forAccount: entry.keychainPasswordKey)
        }
        try? keychainService.deleteData(forAccount: SecurityConstants.vaultMetadataAccountKey)
        viewModel.lockVault()
        super.tearDown()
    }
    
    // MARK: - 1. Create Testi
    func testCreateEntrySuccess() throws {
        let entry = try viewModel.createEntry(
            title: "GitHub Test",
            username: "developer",
            password: "super_secure_password_987",
            website: "https://github.com",
            notes: "Test notu"
        )
        
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries.first?.title, "GitHub Test")
        
        // Secret Keychain'e yazılmış mı? (Without accessControl requirement for unit test service)
        let secret = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(secret, "super_secure_password_987")
    }
    
    // MARK: - 2. Read Testi
    func testReadEntryPassword() throws {
        let entry = try viewModel.createEntry(
            title: "Instagram",
            username: "insta_user",
            password: "insta_secret_password",
            website: "instagram.com",
            notes: ""
        )
        
        let retrievedSecret = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(retrievedSecret, "insta_secret_password")
    }
    
    // MARK: - 3. Update Testi (Metadata ve Şifre Güncelleme)
    func testUpdateEntryMetadataAndSecret() throws {
        let entry = try viewModel.createEntry(
            title: "Google Eski",
            username: "old@gmail.com",
            password: "old_password",
            website: "google.com",
            notes: "Eski"
        )
        
        var modified = entry
        modified.title = "Google Yeni"
        modified.username = "new@gmail.com"
        
        // Hem metadata hem şifreyi güncelle
        try viewModel.updateEntry(modified, newPassword: "new_password_123")
        
        XCTAssertEqual(viewModel.entries.first?.title, "Google Yeni")
        XCTAssertEqual(viewModel.entries.first?.username, "new@gmail.com")
        
        let updatedSecret = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(updatedSecret, "new_password_123")
    }
    
    func testUpdateEntryMetadataOnlyPreservesExistingSecret() throws {
        let entry = try viewModel.createEntry(
            title: "Apple ID",
            username: "apple@icloud.com",
            password: "unchanged_secret",
            website: "apple.com",
            notes: ""
        )
        
        var modified = entry
        modified.title = "Apple ID Güncel"
        
        // Şifre nil verilerek sadece metadata güncellensin
        try viewModel.updateEntry(modified, newPassword: nil)
        
        XCTAssertEqual(viewModel.entries.first?.title, "Apple ID Güncel")
        
        // Şifrenin bozulmadan durduğunu doğrula
        let secret = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(secret, "unchanged_secret")
    }
    
    // MARK: - 4. Delete Testi (Orphan Bırakmama)
    func testDeleteEntryRemovesBothSecretAndMetadata() throws {
        let entry = try viewModel.createEntry(
            title: "Silinecek Kayıt",
            username: "delete_me",
            password: "secret_to_delete",
            website: "",
            notes: ""
        )
        
        XCTAssertEqual(viewModel.entries.count, 1)
        
        // Kaydı sil
        try viewModel.deleteEntry(entry)
        
        // Metadata'dan silindi mi?
        XCTAssertEqual(viewModel.entries.count, 0)
        
        // Keychain secret'ı da silindi mi? (Orphan kalmamalı)
        XCTAssertThrowsError(try keychainService.readSecret(forAccount: entry.keychainPasswordKey)) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }
    
    // MARK: - 5. Validation Testi (Başlık Boş Olamaz)
    func testValidationEmptyTitleThrowsError() {
        XCTAssertThrowsError(
            try viewModel.createEntry(
                title: "   ",
                username: "user",
                password: "pass",
                website: "",
                notes: ""
            )
        ) { error in
            XCTAssertEqual(error as? VaultValidationError, VaultValidationError.emptyTitle)
        }
    }
    
    // MARK: - 6. Şifre İzolasyonu Testi
    func testPasswordDoesNotLeakIntoVaultMetadata() throws {
        _ = try viewModel.createEntry(
            title: "Gizli Kasa",
            username: "vault_user",
            password: "super_confidential_secret_999",
            website: "example.com",
            notes: "Kurtarma: 555"
        )
        
        // Keychain'deki ham metadata Data'sını oku
        let rawMetadataData = try keychainService.readData(forAccount: SecurityConstants.vaultMetadataAccountKey)
        let jsonString = String(data: rawMetadataData, encoding: .utf8)!
        
        // Metadata JSON içinde şifre ASLA yer almamalı
        XCTAssertFalse(jsonString.contains("super_confidential_secret_999"), "HATA: Şifre metadata JSON içine sızmış!")
    }
    
    // MARK: - 7. Kilitlendiğinde RAM Temizliği Testi
    func testLockVaultWipesAllState() throws {
        _ = try viewModel.createEntry(
            title: "Banka Hesabı",
            username: "musteri_no",
            password: "bank_password",
            website: "banka.com",
            notes: "Gizli PIN: 7788"
        )
        
        XCTAssertFalse(viewModel.entries.isEmpty)
        
        viewModel.lockVault()
        
        XCTAssertFalse(viewModel.isUnlocked)
        XCTAssertTrue(viewModel.entries.isEmpty, "Kasa kilitlendiğinde entries boşaltılmalıdır.")
        XCTAssertEqual(viewModel.searchText, "")
    }
    
    // MARK: - 8. Hesap Gruplama (Account Grouping) Testi
    func testAccountGroupingByTitle() throws {
        _ = try viewModel.createEntry(
            title: "Google",
            username: "suat@gmail.com",
            password: "pass1"
        )
        _ = try viewModel.createEntry(
            title: "Google",
            username: "suat2@gmail.com",
            password: "pass2"
        )
        _ = try viewModel.createEntry(
            title: "Apple",
            username: "suat@icloud.com",
            password: "pass3"
        )
        
        let groups = viewModel.accountGroups
        XCTAssertEqual(groups.count, 2, "2 farklı başlık için 2 grup oluşmalı (Apple ve Google).")
        
        // Alfabetik sıralama kontrolü: Apple önce, Google sonra
        XCTAssertEqual(groups[0].displayTitle, "Apple")
        XCTAssertEqual(groups[0].count, 1)
        
        XCTAssertEqual(groups[1].displayTitle, "Google")
        XCTAssertEqual(groups[1].count, 2)
        
        // Toplam loginCount 3 olmalı (grup sayısı değil, gerçek kayıt sayısı)
        XCTAssertEqual(viewModel.loginCount, 3)
        XCTAssertEqual(viewModel.totalCount, 3)
        
        // Google grubundaki hesapların bağımsızlığı kontrolü
        let googleGroup = groups[1]
        let entries = viewModel.entries(forGroup: googleGroup)
        XCTAssertEqual(entries.count, 2)
        let usernames = entries.map { $0.username }
        XCTAssertTrue(usernames.contains("suat@gmail.com"))
        XCTAssertTrue(usernames.contains("suat2@gmail.com"))
    }
    
    // MARK: - 9. Büyük / Küçük Harf Duyarsız Gruplama Testi
    func testCaseInsensitiveGrouping() throws {
        _ = try viewModel.createEntry(title: "Google", username: "user1", password: "p1")
        _ = try viewModel.createEntry(title: "google", username: "user2", password: "p2")
        _ = try viewModel.createEntry(title: "GOOGLE", username: "user3", password: "p3")
        
        let groups = viewModel.accountGroups
        XCTAssertEqual(groups.count, 1, "Farklı büyük/küçük harfli Google başlıkları tek grupta birleşmeli.")
        XCTAssertEqual(groups.first?.count, 3)
        XCTAssertEqual(viewModel.loginCount, 3)
    }
    
    // MARK: - 10. Hesap Grubu Arama Testi
    func testFilteredAccountGroupsSearch() throws {
        _ = try viewModel.createEntry(title: "Google", username: "suat@gmail.com", password: "p1")
        _ = try viewModel.createEntry(title: "GitHub", username: "octocat", password: "p2")
        
        // Başlığa göre arama
        let searchByTitle = viewModel.filteredAccountGroups(query: "goog")
        XCTAssertEqual(searchByTitle.count, 1)
        XCTAssertEqual(searchByTitle.first?.displayTitle, "Google")
        
        // Kullanıcı adına göre arama
        let searchByUser = viewModel.filteredAccountGroups(query: "octo")
        XCTAssertEqual(searchByUser.count, 1)
        XCTAssertEqual(searchByUser.first?.displayTitle, "GitHub")
    }
}
