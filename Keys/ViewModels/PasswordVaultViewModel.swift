import Foundation
import SwiftUI
import Combine
import Security

/// Form doğrulama hataları
public enum VaultValidationError: LocalizedError {
    case emptyTitle
    
    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Başlık alanı boş bırakılamaz."
        }
    }
}

/// Kayıt filtreleme seçenekleri (Yalnızca Hesaplar ve Bankalar).
/// "Tümü" kategorisi tamamen kaldırılmıştır.
public enum RecordFilter: String, CaseIterable, Identifiable, Hashable {
    case logins = "Hesaplar"
    case banks = "Bankalar"
    
    public var id: String { rawValue }
}

/// Aynı başlığa (servis/platform) sahip hesapların UI düzeyinde gruplanmış hali.
/// Fiziksel veri modelinde her hesap bağımsız bir PasswordEntry olarak Keychain'de saklanır.
public struct AccountGroup: Identifiable, Hashable {
    /// Gruplama için normalleştirilmiş anahtar (küçük harfe çevrilmiş başlık)
    public var id: String { normalizedTitle }
    
    public let normalizedTitle: String
    public let displayTitle: String
    public var entries: [PasswordEntry]
    
    public var count: Int {
        entries.count
    }
    
    public init(normalizedTitle: String, displayTitle: String, entries: [PasswordEntry]) {
        self.normalizedTitle = normalizedTitle
        self.displayTitle = displayTitle
        self.entries = entries
    }
}

/// Kasa durumunu, kimlik doğrulamasını ve kayıt yönetimini koordine eden ana ViewModel.
/// Kasa kilitlendiğinde RAM'de hiçbir metadata, arama metni veya şifre tutulmaz.
@MainActor
public final class PasswordVaultViewModel: ObservableObject {
    
    // MARK: - Yayınlanan Durumlar (Published State)
    @Published public var isUnlocked: Bool = false
    @Published public var isAuthenticating: Bool = false
    @Published public var authErrorMessage: String? = nil
    @Published public var userErrorMessage: String? = nil
    public private(set) var isInBackground: Bool = false
    public private(set) var isManualLock: Bool = false
    
    /// Uygulama versiyon numarası (CFBundleShortVersionString üzerinden dinamik okunur)
    public var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(version)"
    }
    
    /// Kasa kilitliyken bu dizi kesinlikle boş ([]) tutulur.
    @Published public var entries: [PasswordEntry] = []
    @Published public var searchText: String = ""
    @Published public var selectedFilter: RecordFilter = .logins
    
    // MARK: - Bağımlılıklar (Dependencies)
    private let keychainService: KeychainService
    private let biometricService: BiometricAuthService
    
    public init(
        keychainService: KeychainService = .shared,
        biometricService: BiometricAuthService = .shared
    ) {
        self.keychainService = keychainService
        self.biometricService = biometricService
        biometricService.warmUpBiometricType()
    }
    
    // MARK: - Kimlik Doğrulama ve Kilit İşlemleri
    
    /// Biyometrik veya cihaz parolası ile kasayı açma isteği başlatır
    public func unlockVault() async {
        guard !isUnlocked else { return }
        guard !isInBackground else { return }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        isManualLock = false
        authErrorMessage = nil
        
        let result = await biometricService.authenticate()
        
        switch result {
        case .success(let authenticated):
            if authenticated {
                // PERFORMANS: Kasa açıldığında metadata'yı hemen yükle ve
                // isUnlocked ile birlikte güncelle. Bu sayede ara boş render önlenir.
                do {
                    self.entries = try keychainService.loadVaultMetadata()
                } catch {
                    SecureLogger.error("Metadata yüklenirken hata oluştu")
                    self.entries = []
                }
                self.isManualLock = false
                self.isUnlocked = true
            } else {
                isUnlocked = false
            }
        case .failure(let error):
            isUnlocked = false
            authErrorMessage = error.localizedDescription
        }
        
        isAuthenticating = false
    }
    
    /// Kasayı anında kilitler ve tüm hassas verileri RAM'den temizler.
    /// Title, username, website, notes ve şifreler kilitliyken heap bellekte KALMAZ.
    public func lockVault(isManual: Bool = true) {
        isUnlocked = false
        isAuthenticating = false
        self.isManualLock = isManual
        
        // 1. RAM'deki tüm metadata listesini ve notları tamamen temizle
        entries.removeAll()
        
        // 2. Geçici UI durumlarını sıfırla
        searchText = ""
        selectedFilter = .logins
        authErrorMessage = nil
        userErrorMessage = nil
        
        // 3. Aktif biyometrik oturumu işletim sistemi düzeyinde geçersiz kıl
        biometricService.invalidateAuthenticationContext()
        
        // 4. Varsa geçici dışa aktarma (XLSX) ve yedekleme (.keysbackup) dosyalarını diskten temizle
        cleanExportFiles()
        cleanBackupFiles()
        
        SecureLogger.info("Kasa kilitlendi: Bellek ve oturum tamamen temizlendi")
    }
    
    // MARK: - Veri Yükleme ve Filtreleme
    
    /// Keychain üzerinden kasanın metadata listesini yükler
    public func loadVaultEntries() {
        guard isUnlocked else { return }
        do {
            self.entries = try keychainService.loadVaultMetadata()
        } catch {
            SecureLogger.error("Metadata yüklenirken hata oluştu")
        }
    }
    
    // MARK: - Dashboard Özet Metrikleri (Dinamik Hesaplama)
    
    /// Toplam kayıtlı şifre sayısı
    public var totalCount: Int {
        entries.count
    }
    
    /// Toplam giriş kaydı sayısı
    public var loginCount: Int {
        entries.filter { $0.recordType == .login }.count
    }
    
    /// Toplam banka kaydı sayısı
    public var bankCount: Int {
        entries.filter { $0.recordType == .bank }.count
    }
    
    /// Belirli bir kategori türündeki tüm kayıtları alfabetik sırayla döndürür
    public func entries(for filter: RecordFilter) -> [PasswordEntry] {
        guard isUnlocked else { return [] }
        let list: [PasswordEntry]
        switch filter {
        case .logins:
            list = entries.filter { $0.recordType == .login }
        case .banks:
            list = entries.filter { $0.recordType == .bank }
        }
        return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    
    // MARK: - Hesap Gruplama (Account Grouping)
    
    /// Tüm hesap kayıtlarını başlıklarına göre gruplar (büyük/küçük harf duyarsız).
    /// Gruplar başlığa göre alfabetik sıralanır.
    public var accountGroups: [AccountGroup] {
        guard isUnlocked else { return [] }
        return groupEntries(entries.filter { $0.recordType == .login })
    }
    
    /// Verilen kayıtları başlıklarına göre gruplayan fonksiyon.
    public func groupEntries(_ loginEntries: [PasswordEntry]) -> [AccountGroup] {
        var groupsDict: [String: (displayTitle: String, entries: [PasswordEntry])] = [:]
        
        for entry in loginEntries {
            let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.localizedLowercase
            
            if var existing = groupsDict[key] {
                existing.entries.append(entry)
                groupsDict[key] = existing
            } else {
                groupsDict[key] = (displayTitle: trimmed, entries: [entry])
            }
        }
        
        return groupsDict.map { (key, value) in
            let sortedEntries = value.entries.sorted {
                if !$0.username.isEmpty && !$1.username.isEmpty {
                    return $0.username.localizedStandardCompare($1.username) == .orderedAscending
                }
                return $0.createdAt < $1.createdAt
            }
            return AccountGroup(
                normalizedTitle: key,
                displayTitle: value.displayTitle,
                entries: sortedEntries
            )
        }.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }
    
    /// Belirli bir grubun güncel kayıtlarını döndürür (silme/güncelleme sonrası anlık güncellenir)
    public func entries(forGroup group: AccountGroup) -> [PasswordEntry] {
        guard isUnlocked else { return [] }
        return entries
            .filter { $0.recordType == .login && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == group.normalizedTitle }
            .sorted {
                if !$0.username.isEmpty && !$1.username.isEmpty {
                    return $0.username.localizedStandardCompare($1.username) == .orderedAscending
                }
                return $0.createdAt < $1.createdAt
            }
    }
    
    /// Arama sorgusuna göre filtrelenmiş hesap grupları.
    /// Başlık veya herhangi bir hesabın kullanıcı adı/web sitesi eşleşirse grup listelenir.
    public func filteredAccountGroups(query: String) -> [AccountGroup] {
        guard isUnlocked else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return accountGroups }
        let matchingLogins = entries.filter { $0.recordType == .login && $0.matches(query: trimmedQuery) }
        return groupEntries(matchingLogins)
    }
    
    /// Arama sorgusuna göre filtrelenmiş banka kayıtları
    public func filteredBankEntries(query: String) -> [PasswordEntry] {
        guard isUnlocked else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let banks = entries.filter { $0.recordType == .bank }
        guard !trimmedQuery.isEmpty else { return banks }
        return banks.filter { $0.matches(query: trimmedQuery) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    
    /// Ana ekran aramasında tüm kayıtlar (hem Girişler hem Bankalar) arasında filtreleme
    public var searchResults: [PasswordEntry] {
        guard isUnlocked else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return entries
            .filter { $0.matches(query: query) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    
    /// Filtreye (Girişler veya Bankalar) ve arama sorgusuna göre filtrelenmiş ve Title'a göre alfabetik sıralanmış kayıtlar
    public var filteredEntries: [PasswordEntry] {
        guard isUnlocked else { return [] }
        var list = entries
        switch selectedFilter {
        case .logins:
            list = list.filter { $0.recordType == .login }
        case .banks:
            list = list.filter { $0.recordType == .bank }
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list = list.filter { $0.matches(query: searchText) }
        }
        return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    
    // MARK: - CRUD İşlemleri (Transaction & Rollback Güvenceli)
    
    /// Bir kayda ait şifreyi doğrulanmış LAContext kullanarak Keychain'den çeker
    public func getPassword(for entry: PasswordEntry) throws -> String {
        guard isUnlocked else {
            throw KeychainError.unhandledError(status: errSecAuthFailed)
        }
        let authContext = biometricService.currentAuthenticatedContext
        return try keychainService.readSecret(forAccount: entry.keychainPasswordKey, context: authContext)
    }
    
    /// Yeni bir standart giriş (Login) kaydı ekler
    @discardableResult
    public func createEntry(
        title: String,
        username: String,
        password: String,
        website: String = "",
        notes: String = ""
    ) throws -> PasswordEntry {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw VaultValidationError.emptyTitle
        }
        guard !password.isEmpty else {
            throw VaultValidationError.emptyTitle
        }
        
        let newEntry = PasswordEntry(
            id: UUID(),
            recordType: .login,
            title: trimmedTitle,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: nil, // Bellekte tutma
            website: website.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // 1. Şifreyi donanımsal SecAccessControl ile Keychain'e yaz
        try keychainService.saveSecret(password, forAccount: newEntry.keychainPasswordKey)
        
        // 2. Metadata listesine ekle ve kaydet (Başarısız olursa rollback yap)
        var updatedEntries = entries
        updatedEntries.insert(newEntry, at: 0)
        
        do {
            try keychainService.saveVaultMetadata(updatedEntries)
            self.entries = updatedEntries
            SecureLogger.info("Yeni giriş kaydı başarıyla eklendi")
            return newEntry
        } catch {
            try? keychainService.deleteSecret(forAccount: newEntry.keychainPasswordKey)
            SecureLogger.error("Metadata kaydı başarısız, şifre rollback edildi")
            throw error
        }
    }
    
    /// Yeni bir banka (Bank) kaydı ekler. Yalnızca Banka Adı ve Şifre içerir.
    @discardableResult
    public func createBankEntry(
        bankName: String,
        password: String
    ) throws -> PasswordEntry {
        let trimmedName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VaultValidationError.emptyTitle
        }
        guard !password.isEmpty else {
            throw VaultValidationError.emptyTitle
        }
        
        let newEntry = PasswordEntry(
            id: UUID(),
            recordType: .bank,
            title: trimmedName,
            username: "",
            password: nil,
            website: "",
            notes: "",
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // 1. Şifreyi Keychain'e güvenle yaz
        try keychainService.saveSecret(password, forAccount: newEntry.keychainPasswordKey)
        
        // 2. Metadata listesine ekle ve kaydet (Rollback güvencesi)
        var updatedEntries = entries
        updatedEntries.insert(newEntry, at: 0)
        
        do {
            try keychainService.saveVaultMetadata(updatedEntries)
            self.entries = updatedEntries
            SecureLogger.info("Yeni banka kaydı başarıyla eklendi")
            return newEntry
        } catch {
            try? keychainService.deleteSecret(forAccount: newEntry.keychainPasswordKey)
            SecureLogger.error("Metadata kaydı başarısız, banka şifresi rollback edildi")
            throw error
        }
    }
    
    /// Mevcut bir giriş kaydını günceller
    public func updateEntry(_ entry: PasswordEntry, newPassword: String?) throws {
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw VaultValidationError.emptyTitle
        }
        
        // 1. Şifre değiştirildiyse Keychain'deki secret'ı güncelle
        if let newPassword = newPassword, !newPassword.isEmpty {
            try keychainService.saveSecret(newPassword, forAccount: entry.keychainPasswordKey)
        }
        
        // 2. Metadata listesinde güncelle
        var updatedEntries = entries
        guard let index = updatedEntries.firstIndex(where: { $0.id == entry.id }) else {
            throw KeychainError.itemNotFound
        }
        
        var updatedEntry = entry
        updatedEntry.title = trimmedTitle
        updatedEntry.username = entry.username.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedEntry.website = entry.website.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedEntry.notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedEntry.updatedAt = Date()
        
        updatedEntries[index] = updatedEntry
        
        try keychainService.saveVaultMetadata(updatedEntries)
        self.entries = updatedEntries
        SecureLogger.info("Kayıt başarıyla güncellendi")
    }
    
    /// Mevcut bir banka kaydını günceller
    public func updateBankEntry(_ entry: PasswordEntry, bankName: String, newPassword: String?) throws {
        let trimmedName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VaultValidationError.emptyTitle
        }
        
        if let newPassword = newPassword, !newPassword.isEmpty {
            try keychainService.saveSecret(newPassword, forAccount: entry.keychainPasswordKey)
        }
        
        var updatedEntries = entries
        guard let index = updatedEntries.firstIndex(where: { $0.id == entry.id }) else {
            throw KeychainError.itemNotFound
        }
        
        var updatedEntry = entry
        updatedEntry.title = trimmedName
        updatedEntry.updatedAt = Date()
        
        updatedEntries[index] = updatedEntry
        
        try keychainService.saveVaultMetadata(updatedEntries)
        self.entries = updatedEntries
        SecureLogger.info("Banka kaydı başarıyla güncellendi")
    }
    
    /// Bir kaydı ve ona ait Keychain şifresini tamamen siler
    public func deleteEntry(_ entry: PasswordEntry) throws {
        // 1. Şifreyi Keychain'den sil
        try keychainService.deleteSecret(forAccount: entry.keychainPasswordKey)
        
        // 2. Metadata listesinden çıkar
        var updatedEntries = entries
        updatedEntries.removeAll { $0.id == entry.id }
        
        // 3. Güncel listeyi Keychain'e kaydet
        try keychainService.saveVaultMetadata(updatedEntries)
        self.entries = updatedEntries
        SecureLogger.info("Kayıt ve ilişkili şifre güvenle silindi")
    }
    
    // MARK: - Güvenli XLSX Dışa Aktarma
    
    /// Kasa açıkken ve açık biyometrik doğrulamadan sonra tüm kayıtları
    /// iki ayrı çalışma sayfası (Giriş Bilgileri & Banka Bilgileri) içeren
    /// gerçek .xlsx formatında geçici bir dosyaya yazar.
    /// Herhangi bir hata veya iptal durumunda geçici dosya derhal temizlenir.
    public func exportAllEntriesToXLSX() async throws -> URL {
        guard isUnlocked else {
            throw KeychainError.unhandledError(status: errSecAuthFailed)
        }
        
        // Önceki olası artık dosyaları temizle
        cleanExportFiles()
        
        // 1. Açık Biyometrik Kimlik Doğrulama:
        let authResult = await biometricService.authenticate(reason: "Şifreleri dışa aktarmak için kimliğinizi doğrulayın")
        switch authResult {
        case .success(let authenticated):
            guard authenticated else {
                throw KeychainError.unhandledError(status: errSecAuthFailed)
            }
        case .failure:
            throw KeychainError.unhandledError(status: errSecAuthFailed)
        }
        
        do {
            // 2. Doğrulanmış bağlam ile şifreleri oku:
            var exportItems: [ExportItem] = []
            for entry in entries {
                let secret = (try? getPassword(for: entry)) ?? ""
                let item = ExportItem(
                    title: entry.title,
                    username: entry.username,
                    website: entry.website,
                    password: secret,
                    notes: entry.notes,
                    recordType: entry.recordType
                )
                exportItems.append(item)
            }
            
            // 3. Gerçek Open XML (.xlsx) oluştur:
            let xlsxData = ExcelExportService.shared.createXLSXData(items: exportItems)
            
            // 4. Geçici dosya yaz (Sadece paylaşım için kısa ömürlü):
            let tempDir = FileManager.default.temporaryDirectory
            let exportURL = tempDir.appendingPathComponent("Keys-Export.xlsx")
            
            try? FileManager.default.removeItem(at: exportURL)
            try xlsxData.write(to: exportURL, options: .atomic)
            
            SecureLogger.info("XLSX dışa aktarma dosyası geçici olarak üretildi")
            return exportURL
        } catch {
            cleanExportFiles()
            SecureLogger.error("XLSX dışa aktarma sırasında hata oluştu, geçici dosyalar temizlendi")
            throw error
        }
    }
    
    /// temporaryDirectory içerisindeki Keys dışa aktarma geçici dosyalarını temizler.
    public func cleanExportFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("Keys-Export") && file.pathExtension == "xlsx" {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let exportURL = tempDir.appendingPathComponent("Keys-Export.xlsx")
        try? FileManager.default.removeItem(at: exportURL)
    }

    // MARK: - Şifreli Keys Yedekleme & Geri Yükleme (.keysbackup)
    
    /// Kasadaki tüm kayıtları ve şifrelerini şifreli .keysbackup dosyası olarak dışa aktarır.
    public func createBackup(password: String) async throws -> URL {
        guard isUnlocked else {
            throw BackupError.authenticationFailed
        }
        guard password.count >= 12 else {
            throw BackupError.passwordTooShort
        }
        
        // Aktif doğrulanmış LAContext'i kullan. Yoksa tek bir doğrulama oturumu aç.
        var authContext = biometricService.currentAuthenticatedContext
        if authContext == nil {
            let authResult = await biometricService.authenticate(reason: "Yedek oluşturmak için kimliğinizi doğrulayın.")
            switch authResult {
            case .success(let authenticated):
                guard authenticated else {
                    throw BackupError.authenticationFailed
                }
                authContext = biometricService.currentAuthenticatedContext
            case .failure:
                throw BackupError.authenticationFailed
            }
        }
        
        var backupEntries: [BackupEntry] = []
        
        for entry in entries {
            let secret = (try? keychainService.readSecret(forAccount: entry.keychainPasswordKey, context: authContext)) ?? ""
            let item = BackupEntry(
                id: entry.id,
                recordType: entry.recordType,
                title: entry.title,
                username: entry.username,
                website: entry.website,
                notes: entry.notes,
                password: secret,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )
            backupEntries.append(item)
        }
        
        let payload = BackupPayload(
            version: 1,
            createdAt: Date(),
            appVersion: appVersion,
            entries: backupEntries
        )
        
        let encryptedData = try BackupService.shared.createEncryptedBackupData(payload: payload, password: password)
        
        let tempDir = FileManager.default.temporaryDirectory
        let backupFileName = "Keys-Backup-\(Int(Date().timeIntervalSince1970)).keysbackup"
        let backupURL = tempDir.appendingPathComponent(backupFileName)
        
        try? FileManager.default.removeItem(at: backupURL)
        try encryptedData.write(to: backupURL, options: .atomic)
        
        SecureLogger.info("Şifreli Keys yedeği geçici olarak üretildi")
        return backupURL
    }
    
    /// Seçilen yedek dosyasını açıp doğrular ve içeriğindeki kayıt özetini döndürür.
    public func inspectBackup(from url: URL, password: String) throws -> BackupPayload {
        let fileData = try Data(contentsOf: url)
        return try BackupService.shared.decryptBackupData(fileData, password: password)
    }
    
    /// Doğrulanmış yedek verilerini mevcut kasaya güvenli / transactional olarak geri yükler.
    /// Mevcut kayıtlar silinmez. Aynı UUID varsa güncellenir, yeni UUID varsa eklenir.
    public func restoreBackup(payload: BackupPayload) throws -> (restoredCount: Int, updatedCount: Int) {
        guard isUnlocked else {
            throw BackupError.authenticationFailed
        }
        
        // 1. Mevcut kasanın anlık kopyasını al (Rollback için)
        let currentEntries = try keychainService.loadVaultMetadata()
        var updatedMap: [UUID: PasswordEntry] = Dictionary(uniqueKeysWithValues: currentEntries.map { ($0.id, $0) })
        
        var addedCount = 0
        var updatedCount = 0
        
        do {
            for item in payload.entries {
                // A. Metadata modelini oluştur
                let newEntry = PasswordEntry(
                    id: item.id,
                    recordType: item.recordType,
                    title: item.title,
                    username: item.username,
                    website: item.website,
                    notes: item.notes,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
                
                // B. Şifreyi Keychain'e yaz
                try keychainService.saveSecret(item.password, forAccount: newEntry.keychainPasswordKey)
                
                if updatedMap[item.id] != nil {
                    updatedCount += 1
                } else {
                    addedCount += 1
                }
                updatedMap[item.id] = newEntry
            }
            
            // C. Birleştirilmiş yeni metadata listesini Keychain'e yaz
            let mergedList = Array(updatedMap.values).sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
            try keychainService.saveVaultMetadata(mergedList)
            
            // D. RAM durumunu güncelle
            self.entries = mergedList
            cleanBackupFiles()
            SecureLogger.info("Yedek geri yüklendi")
            return (restoredCount: addedCount, updatedCount: updatedCount)
        } catch {
            // Rollback: Metadata'yı eski haline geri getir
            SecureLogger.error("Yedek geri yükleme başarısız oldu, rollback başlatılıyor")
            try? keychainService.saveVaultMetadata(currentEntries)
            self.entries = (try? keychainService.loadVaultMetadata()) ?? currentEntries
            cleanBackupFiles()
            throw error
        }
    }
    
    /// temporaryDirectory içerisindeki Keys yedek geçici dosyalarını temizler.
    public func cleanBackupFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "keysbackup" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Güvenli Rastgele Şifre Üretici Delegasyonu
    
    /// Hızlı şifre üretimi için donanım tabanlı CSPRNG kullanan PasswordGenerator servisine delege eder.
    /// Eski modulo-bias ve UUID fallback tamamen kaldırılmıştır.
    public func generateSecurePassword(length: Int = 18) -> String {
        let config = PasswordGeneratorConfig(length: length)
        do {
            return try PasswordGenerator.shared.generatePassword(config: config)
        } catch {
            SecureLogger.error("Şifre üretimi başarısız oldu")
            return ""
        }
    }
    
    // MARK: - Yaşam Döngüsü (ScenePhase) ve Güvenlik Dengesi
    
    public func handleScenePhase(_ phase: ScenePhase) {
        handleScenePhase(from: .active, to: phase)
    }
    
    public func handleScenePhase(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            isInBackground = true
            lockVault(isManual: false)
        case .inactive:
            break
        case .active:
            let wasInBackground = (oldPhase == .background) || isInBackground
            isInBackground = false
            if wasInBackground {
                handleForegroundReturn()
            }
        @unknown default:
            isInBackground = true
            lockVault(isManual: false)
        }
    }
    
    /// Ön plana dönüşte panoyu senkronize eder ve kasa kilitliyse Face ID'yi anında tetikler
    public func handleForegroundReturn() {
        ClipboardService.shared.syncStateOnForeground()
        if !isUnlocked && !isAuthenticating {
            Task(priority: .userInitiated) {
                await unlockVault()
            }
        }
    }
}
