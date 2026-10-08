import XCTest
import Security
@testable import Keys

final class KeychainServiceTests: XCTestCase {
    
    var keychainService: KeychainService!
    let testAccount = "com.offlinevault.test.account"
    
    override func setUp() {
        super.setUp()
        keychainService = KeychainService(
            service: "com.offlinevault.keys.test.service",
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        // Test öncesi temizle
        try? keychainService.deleteData(forAccount: testAccount)
    }
    
    override func tearDown() {
        try? keychainService.deleteData(forAccount: testAccount)
        super.tearDown()
    }
    
    func testSaveAndReadDataDirectly() throws {
        let sampleData = "gizli_veri_12345".data(using: .utf8)!
        
        try keychainService.saveData(sampleData, forAccount: testAccount, requireAccessControl: false)
        let loadedData = try keychainService.readData(forAccount: testAccount)
        
        XCTAssertEqual(sampleData, loadedData, "Keychain'e yazılan Data okunan Data ile birebir aynı olmalıdır.")
    }
    
    func testSaveAndReadVaultMetadataDirectly() throws {
        let entries = [
            PasswordEntry(title: "Google", username: "test@gmail.com", notes: "Önemli hesap"),
            PasswordEntry(title: "Banka", username: "user123", notes: "İnternet bankacılığı")
        ]
        
        try keychainService.saveVaultMetadata(entries)
        let loadedEntries = try keychainService.loadVaultMetadata()
        
        XCTAssertEqual(loadedEntries.count, 2)
        XCTAssertEqual(loadedEntries[0].title, "Google")
        XCTAssertEqual(loadedEntries[1].title, "Banka")
        XCTAssertNil(loadedEntries[0].cachedPassword, "Metadata yüklenirken şifreler belleğe yüklenmemelidir.")
    }
    
    func testDeleteSecret() throws {
        let sampleData = "silinecek_veri".data(using: .utf8)!
        try keychainService.saveData(sampleData, forAccount: testAccount, requireAccessControl: false)
        
        try keychainService.deleteData(forAccount: testAccount)
        
        XCTAssertThrowsError(try keychainService.readData(forAccount: testAccount)) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }
}
