import XCTest
import SwiftUI
import CryptoKit
@testable import Keys

@MainActor
final class BackupAndPersistenceTests: XCTestCase {
    
    var viewModel: PasswordVaultViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = PasswordVaultViewModel()
    }
    
    override func tearDown() {
        viewModel.lockVault()
        viewModel.cleanBackupFiles()
        super.tearDown()
    }
    
    // MARK: - 1. Face ID & Lifecycle Tests
    
    func testAuthenticationDoesNotStartInBackground() async {
        viewModel.handleScenePhase(from: .active, to: .background)
        XCTAssertTrue(viewModel.isInBackground, "Arka plana geçildiğinde isInBackground true olmalıdır.")
        
        // Arka plandayken unlockVault çağrılsa bile kimlik doğrulama başlamamalı
        await viewModel.unlockVault()
        XCTAssertFalse(viewModel.isUnlocked, "Arka plandayken kilit açılamaz.")
        XCTAssertFalse(viewModel.isAuthenticating, "Arka plandayken authentication başlatılamaz.")
    }
    
    func testScenePhaseTransitionsDoNotDuplicateFaceIDOnInactiveToActive() {
        // Face ID penceresi açıldığında sistem .inactive'e geçer.
        viewModel.handleScenePhase(from: .active, to: .inactive)
        XCTAssertFalse(viewModel.isInBackground)
        
        // Face ID penceresi kapandığında sistem .inactive -> .active geçişi yapar.
        // Bu geçiş background'dan dönüş OLMADIĞI için foreground return tetiklememelidir.
        let wasInBackgroundBefore = viewModel.isInBackground
        viewModel.handleScenePhase(from: .inactive, to: .active)
        XCTAssertFalse(wasInBackgroundBefore)
        XCTAssertFalse(viewModel.isInBackground)
    }
    
    func testForegroundReturnFromBackgroundOnly() {
        // Uygulama arka plana geçti
        viewModel.handleScenePhase(from: .active, to: .background)
        XCTAssertTrue(viewModel.isInBackground)
        XCTAssertFalse(viewModel.isUnlocked)
        
        // Uygulama arka plandan ön plana döndü
        viewModel.handleScenePhase(from: .background, to: .active)
        XCTAssertFalse(viewModel.isInBackground)
    }
    
    // MARK: - 2. Version Display Test
    
    func testAppVersionFormatAndDynamicReading() {
        let version = viewModel.appVersion
        XCTAssertTrue(version.hasPrefix("v"), "Versiyon 'v' önekiyle başlamalıdır: \(version)")
        
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        XCTAssertEqual(version, "v\(bundleVersion)", "Versiyon numarası doğrudan Bundle'dan dinamik okunmalıdır.")
    }
    
    // MARK: - 3. Data Persistence & Migration Tests
    
    func testPasswordEntryFlexibleDateDecoding() throws {
        // Standart ISO8601 formatı
        let json1 = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "title": "Google",
            "username": "user@example.com",
            "website": "https://google.com",
            "notes": "Not",
            "createdAt": "2026-01-01T12:00:00Z",
            "updatedAt": "2026-01-01T12:00:00Z",
            "recordType": "login"
        }
        """.data(using: .utf8)!
        
        let entry1 = try JSONDecoder().decode(PasswordEntry.self, from: json1)
        XCTAssertEqual(entry1.title, "Google")
        XCTAssertEqual(entry1.recordType, .login)
        
        // Kesirli saniyeli ISO8601 formatı (iOS farklı versiyonlarda üretebilir)
        let json2 = """
        {
            "id": "22222222-3333-4444-5555-666666666666",
            "title": "Ziraat Bankası",
            "username": "",
            "website": "",
            "notes": "",
            "createdAt": "2026-02-15T08:30:45.123Z",
            "updatedAt": "2026-02-15T08:30:45.123Z",
            "recordType": "bank"
        }
        """.data(using: .utf8)!
        
        let entry2 = try JSONDecoder().decode(PasswordEntry.self, from: json2)
        XCTAssertEqual(entry2.title, "Ziraat Bankası")
        XCTAssertEqual(entry2.recordType, .bank)
        
        // Unix Timestamp (Double) formatı
        let json3 = """
        {
            "id": "33333333-4444-5555-6666-777777777777",
            "title": "Eski Kayıt",
            "username": "admin",
            "website": "",
            "notes": "",
            "createdAt": 1770000000.0,
            "updatedAt": 1770000000.0,
            "recordType": "login"
        }
        """.data(using: .utf8)!
        
        let entry3 = try JSONDecoder().decode(PasswordEntry.self, from: json3)
        XCTAssertEqual(entry3.title, "Eski Kayıt")
    }
    
    func testSafeMetadataMigrationAndRecovery() throws {
        // Bozuk JSON içeren bir kayıtta tek tek kurtarma ve liste bütünlüğü
        let rawJSON = """
        [
            {
                "id": "11111111-1111-1111-1111-111111111111",
                "title": "Kayıt 1",
                "username": "u1",
                "createdAt": "2026-01-01T00:00:00Z",
                "updatedAt": "2026-01-01T00:00:00Z",
                "recordType": "login"
            },
            {
                "id": "invalid-uuid-format-test",
                "title": "Bozuk Kayıt"
            },
            {
                "id": "22222222-2222-2222-2222-222222222222",
                "title": "Kayıt 2",
                "username": "u2",
                "createdAt": "2026-01-02T00:00:00Z",
                "updatedAt": "2026-01-02T00:00:00Z",
                "recordType": "bank"
            }
        ]
        """.data(using: .utf8)!
        
        let recovered = KeychainService.shared.safeDecodeEntries(from: rawJSON)
        XCTAssertEqual(recovered.count, 2, "Bozuk olan 1 kayıt yüzünden diğer 2 sağlam kayıt çöpe atılmamalıdır!")
        XCTAssertEqual(recovered[0].title, "Kayıt 1")
        XCTAssertEqual(recovered[1].title, "Kayıt 2")
    }
    
    // MARK: - 4. Keys Şifreli Backup & Restore Tests
    
    func testBackupCreationAndHeaderVerification() throws {
        let entries = [
            BackupEntry(
                id: UUID(),
                recordType: .login,
                title: "GitHub",
                username: "developer@apple.com",
                website: "https://github.com",
                notes: "2FA yedek kodları",
                password: "UltraSecretPassword123!",
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: entries
        )
        
        let backupData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: "MyStrongMasterPassword2026!")
        
        // 1. Magic Header ve versiyon doğrulaması
        XCTAssertTrue(backupData.count >= 71, "Yedek dosyası en az 71 byte olmalıdır.")
        let magicString = String(data: backupData.subdata(in: 0..<10), encoding: .utf8)
        XCTAssertEqual(magicString, "KEYSBACKUP", "Magic header 'KEYSBACKUP' olmalıdır.")
        XCTAssertEqual(backupData[10], 1, "Versiyon baytı 1 olmalıdır.")
        
        // 2. verifyBackupHeader yardımcı metod kontrolü
        XCTAssertTrue(BackupService.shared.verifyBackupHeader(backupData))
    }
    
    func testBackupPlaintextAbsence() throws {
        let sensitivePassword = "SuperConfidentialPassword999!"
        let sensitiveUsername = "secret_agent_007"
        let sensitiveTitle = "TopSecretBank"
        let sensitiveNotes = "Secret vault PIN 9876"
        
        let entries = [
            BackupEntry(
                id: UUID(),
                recordType: .bank,
                title: sensitiveTitle,
                username: sensitiveUsername,
                website: "https://secure.bank.com",
                notes: sensitiveNotes,
                password: sensitivePassword,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: entries
        )
        
        let backupData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: "CorrectBackupPassword123!")
        
        // Düz metin arama: dosya içinde hassas bilgiler açıkça geçmemeli
        let rawDataString = String(decoding: backupData, as: UTF8.self)
        XCTAssertFalse(rawDataString.contains(sensitivePassword), "Şifre asla düz metin olarak backup içinde yer alamaz!")
        XCTAssertFalse(rawDataString.contains(sensitiveUsername), "Kullanıcı adı düz metin olamaz!")
        XCTAssertFalse(rawDataString.contains(sensitiveTitle), "Başlık düz metin olamaz!")
        XCTAssertFalse(rawDataString.contains(sensitiveNotes), "Notlar düz metin olamaz!")
    }
    
    func testWrongPasswordRejection() throws {
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: [
                BackupEntry(
                    id: UUID(),
                    recordType: .login,
                    title: "Test",
                    username: "user",
                    website: "",
                    notes: "",
                    password: "pass",
                    createdAt: Date(),
                    updatedAt: Date()
                )
            ]
        )
        
        let backupData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: "CorrectPassword123!")
        
        // Yanlış parola ile açmaya çalışma
        XCTAssertThrowsError(try BackupService.shared.decryptBackupData(backupData, password: "WrongPassword123!")) { error in
            guard let backupError = error as? BackupError else {
                XCTFail("Beklenen BackupError türü alınamadı: \(error)")
                return
            }
            if case .decryptionFailed = backupError {
                // Başarılı
            } else {
                XCTFail("Yanlış parola için .decryptionFailed bekleniyordu, gelen: \(backupError)")
            }
        }
    }
    
    func testTamperedFileFailsIntegrityCheck() throws {
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: []
        )
        
        var backupData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: "StrongPassword2026!")
        
        // Dosyanın son byte'ını değiştir (bit-flip saldırısı simülasyonu)
        let lastIndex = backupData.count - 1
        backupData[lastIndex] ^= 0x01
        
        // AEAD kimlik doğrulaması bozulmayı yakalamalı ve reddetmeli
        XCTAssertThrowsError(try BackupService.shared.decryptBackupData(backupData, password: "StrongPassword2026!")) { error in
            guard let backupError = error as? BackupError else {
                XCTFail("Beklenen BackupError alınamadı: \(error)")
                return
            }
            if case .decryptionFailed = backupError {
                // AEAD tag uyuşmazlığı tespit edildi
            } else {
                XCTFail("Bozuk veri için .decryptionFailed bekleniyordu, gelen: \(backupError)")
            }
        }
    }
    
    func testTurkishCharactersAndUnicodePreservation() throws {
        let turkishTitle = "Garanti BBVA Şube Çıkışı"
        let turkishUser = "ömer_şükrü_çetinkaya"
        let turkishNotes = "İpek, Şemsiye, Çiçek, Ördek, Üzüm, Ağaç, ğüşıöçĞÜŞİÖÇ"
        let turkishPassword = "Şifre!Çözülmez_2026+ğüşıöç"
        
        let entry = BackupEntry(
            id: UUID(),
            recordType: .bank,
            title: turkishTitle,
            username: turkishUser,
            website: "https://garantibbva.com.tr",
            notes: turkishNotes,
            password: turkishPassword,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: [entry]
        )
        
        let password = "SuperSecretPassword123!"
        let backupData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: password)
        let decrypted = try BackupService.shared.decryptBackupData(backupData, password: password)
        
        XCTAssertEqual(decrypted.entries.count, 1)
        let restored = decrypted.entries[0]
        XCTAssertEqual(restored.title, turkishTitle)
        XCTAssertEqual(restored.username, turkishUser)
        XCTAssertEqual(restored.notes, turkishNotes)
        XCTAssertEqual(restored.password, turkishPassword)
    }
    
    func testUUIDConflictMergeBehavior() throws {
        viewModel.isUnlocked = true
        
        let sharedID = UUID()
        let existingEntry = PasswordEntry(
            id: sharedID,
            title: "Spotify (Eski)",
            username: "old_user",
            notes: "Eski not"
        )
        
        // Mevcut kasaya eski kaydı koy
        viewModel.entries = [existingEntry]
        try? KeychainService.shared.saveVaultMetadata([existingEntry])
        
        // Yedekte aynı UUID ile güncellenmiş kayıt ve yeni bir UUID ile ikinci kayıt var
        let newID = UUID()
        let backupPayload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: [
                BackupEntry(
                    id: sharedID,
                    recordType: .login,
                    title: "Spotify (Güncel)",
                    username: "new_user@spotify.com",
                    website: "https://spotify.com",
                    notes: "Yeni not",
                    password: "NewPassword123!",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                BackupEntry(
                    id: newID,
                    recordType: .login,
                    title: "Netflix",
                    username: "netflix@user.com",
                    website: "https://netflix.com",
                    notes: "4K Aile Paketi",
                    password: "NetflixPassword123!",
                    createdAt: Date(),
                    updatedAt: Date()
                )
            ]
        )
        
        let result = try viewModel.restoreBackup(payload: backupPayload)
        
        XCTAssertEqual(result.updatedCount, 1, "Mevcut UUID güncellenmeli.")
        XCTAssertEqual(result.restoredCount, 1, "Yeni UUID eklenmeli.")
        XCTAssertEqual(viewModel.entries.count, 2, "Kasa toplam 2 kayıt içermelidir.")
        
        let updatedSpotify = viewModel.entries.first { $0.id == sharedID }
        XCTAssertEqual(updatedSpotify?.title, "Spotify (Güncel)")
        XCTAssertEqual(updatedSpotify?.username, "new_user@spotify.com")
    }
    
    func testEmptyVaultBackupAndRestore() throws {
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: []
        )
        
        let password = "ValidPassword123!"
        let backupData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: password)
        let restored = try BackupService.shared.decryptBackupData(backupData, password: password)
        
        XCTAssertEqual(restored.entries.count, 0, "Boş kasa yedeği başarıyla alınıp geri yüklenebilmelidir.")
    }
    
    func testLargeScaleBackupAndRestorePerformance() throws {
        // 160 kayıt üret
        var entries: [BackupEntry] = []
        for i in 1...160 {
            let item = BackupEntry(
                id: UUID(),
                recordType: (i % 3 == 0) ? .bank : .login,
                title: "Kayıt Başlığı #\(i)",
                username: "user_\(i)@domain.com",
                website: "https://subdomain\(i).example.com",
                notes: "Güvenlik notu ve açıklama metni #\(i)",
                password: "SecureP@ssword_Generated_\(i)!",
                createdAt: Date(),
                updatedAt: Date()
            )
            entries.append(item)
        }
        
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0.0",
            entries: entries
        )
        
        let password = "LargeScaleTestPassword2026!"
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let backupData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: password)
        let encryptedTime = CFAbsoluteTimeGetCurrent() - startTime
        
        let decryptStartTime = CFAbsoluteTimeGetCurrent()
        let restored = try BackupService.shared.decryptBackupData(backupData, password: password)
        let decryptedTime = CFAbsoluteTimeGetCurrent() - decryptStartTime
        
        XCTAssertEqual(restored.entries.count, 160)
        XCTAssertLessThan(encryptedTime, 2.5, "160 kaydın şifrelenmesi makul sürede tamamlanmalıdır.")
        XCTAssertLessThan(decryptedTime, 2.5, "160 kaydın çözülmesi makul sürede tamamlanmalıdır.")
    }
    
    func testTemporaryBackupFileCleanup() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("Keys-Backup-999999.keysbackup")
        try "test data".write(to: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        
        viewModel.cleanBackupFiles()
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path), "cleanBackupFiles geçici .keysbackup dosyalarını silmelidir.")
    }
}
