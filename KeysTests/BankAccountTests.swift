import XCTest
@testable import Keys

@MainActor
final class BankAccountTests: XCTestCase {
    
    var viewModel: PasswordVaultViewModel!
    var keychainService: KeychainService!
    
    override func setUp() {
        super.setUp()
        // Her test için sıfır bağımsız servis
        keychainService = KeychainService()
        try? keychainService.clearAllData()
        
        viewModel = PasswordVaultViewModel(keychainService: keychainService)
        viewModel.isUnlocked = true
    }
    
    override func tearDown() {
        try? keychainService.clearAllData()
        super.tearDown()
    }
    
    // MARK: - 1. Banka Adı Zorunlu
    func testBankNameIsRequired() {
        XCTAssertThrowsError(
            try viewModel.createBankEntry(bankName: "   ", password: "valid_password")
        ) { error in
            XCTAssertEqual(error as? VaultValidationError, VaultValidationError.emptyTitle)
        }
    }
    
    // MARK: - 2. Banka Şifresi Zorunlu
    func testBankPasswordIsRequired() {
        XCTAssertThrowsError(
            try viewModel.createBankEntry(bankName: "Garanti BBVA", password: "")
        ) { error in
            XCTAssertEqual(error as? VaultValidationError, VaultValidationError.emptyTitle)
        }
    }
    
    // MARK: - 3. Banka Kaydı Oluşturma
    func testCreateBankEntrySuccess() throws {
        let entry = try viewModel.createBankEntry(bankName: "İş Bankası", password: "BankPass!987")
        
        XCTAssertEqual(entry.recordType, .bank)
        XCTAssertEqual(entry.title, "İş Bankası")
        XCTAssertEqual(entry.username, "", "Banka kaydında kullanıcı adı boş olmalıdır.")
        XCTAssertEqual(entry.website, "", "Banka kaydında website boş olmalıdır.")
        XCTAssertEqual(entry.notes, "", "Banka kaydında notlar boş olmalıdır.")
        XCTAssertNil(entry.cachedPassword, "Şifre RAM'deki modelde tutulmamalıdır.")
        
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries.first?.title, "İş Bankası")
        XCTAssertEqual(viewModel.entries.first?.recordType, .bank)
    }
    
    // MARK: - 4. Banka Kaydı Okuma
    func testReadBankEntryPassword() throws {
        let entry = try viewModel.createBankEntry(bankName: "Yapı Kredi", password: "YKBSecret#456")
        
        let retrievedSecret = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(retrievedSecret, "YKBSecret#456")
    }
    
    // MARK: - 5. Banka Kaydı Güncelleme
    func testUpdateBankEntryNameAndSecret() throws {
        let entry = try viewModel.createBankEntry(bankName: "Akbank", password: "OldBankPassword")
        
        try viewModel.updateBankEntry(entry, bankName: "Akbank Güncel", newPassword: "NewBankPassword789")
        
        XCTAssertEqual(viewModel.entries.first?.title, "Akbank Güncel")
        
        let updatedSecret = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(updatedSecret, "NewBankPassword789")
    }
    
    func testUpdateBankEntryNameOnlyPreservesSecret() throws {
        let entry = try viewModel.createBankEntry(bankName: "QNB Finansbank", password: "UnchangedBankSecret")
        
        try viewModel.updateBankEntry(entry, bankName: "QNB", newPassword: nil)
        
        XCTAssertEqual(viewModel.entries.first?.title, "QNB")
        
        let secret = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(secret, "UnchangedBankSecret")
    }
    
    // MARK: - 6. Banka Kaydı Silme
    func testDeleteBankEntryRemovesSecretAndMetadata() throws {
        let entry = try viewModel.createBankEntry(bankName: "Ziraat Bankası", password: "ZiraatSecret123")
        XCTAssertEqual(viewModel.entries.count, 1)
        
        try viewModel.deleteEntry(entry)
        
        XCTAssertEqual(viewModel.entries.count, 0)
        XCTAssertThrowsError(try keychainService.readSecret(forAccount: entry.keychainPasswordKey)) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }
    
    // MARK: - 7. Banka Şifresinin Metadata JSON'a Girmediği
    func testBankPasswordDoesNotLeakIntoMetadataJSON() throws {
        _ = try viewModel.createBankEntry(bankName: "Halkbank", password: "SuperSecretBankPassword999")
        
        let rawData = try keychainService.readData(forAccount: SecurityConstants.vaultMetadataAccountKey)
        let jsonString = String(data: rawData, encoding: .utf8)!
        
        XCTAssertFalse(jsonString.contains("SuperSecretBankPassword999"), "HATA: Banka şifresi metadata JSON içerisine sızdı!")
    }
    
    // MARK: - 8. Banka Şifresinin Keychain'de Tutulduğu
    func testBankPasswordStoredInKeychain() throws {
        let entry = try viewModel.createBankEntry(bankName: "Vakıfbank", password: "VakifPassword#321")
        
        let secretData = try keychainService.readSecret(forAccount: entry.keychainPasswordKey)
        XCTAssertEqual(secretData, "VakifPassword#321")
    }
    
    // MARK: - 9. LockVault Sonrası RAM Temizliği
    func testLockVaultWipesBankStateFromRAM() throws {
        _ = try viewModel.createBankEntry(bankName: "Denizbank", password: "DenizSecret")
        XCTAssertFalse(viewModel.entries.isEmpty)
        
        viewModel.lockVault()
        
        XCTAssertFalse(viewModel.isUnlocked)
        XCTAssertTrue(viewModel.entries.isEmpty, "Kasa kilitlendiğinde banka kayıtları da RAM'den silinmelidir.")
        XCTAssertEqual(viewModel.selectedFilter, .logins)
    }
}
