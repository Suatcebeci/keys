import XCTest
import SwiftUI
@testable import Keys

@MainActor
final class PasswordVaultViewModelSecurityTests: XCTestCase {
    
    var viewModel: PasswordVaultViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = PasswordVaultViewModel()
    }
    
    func testInitialLockedState() {
        XCTAssertFalse(viewModel.isUnlocked, "Uygulama açılışında kasa kilitli olmalıdır.")
        XCTAssertTrue(viewModel.entries.isEmpty, "Kasa kilitliyken entries RAM'de boş olmalıdır.")
        XCTAssertTrue(viewModel.filteredEntries.isEmpty, "Kasa kilitliyken filteredEntries boş dönmelidir.")
    }
    
    func testLockVaultWipesAllRAMState() {
        // Mock veri ata (Açık kasayı simüle et)
        viewModel.isUnlocked = true
        viewModel.entries = [
            PasswordEntry(title: "Önemli Site", username: "admin", notes: "Gizli kurtarma PIN: 1234")
        ]
        viewModel.searchText = "Önemli"
        
        // Kasayı kilitle
        viewModel.lockVault()
        
        // RAM temizliği doğrulaması
        XCTAssertFalse(viewModel.isUnlocked, "Kasa kilitli duruma geçmelidir.")
        XCTAssertTrue(viewModel.entries.isEmpty, "Kasa kilitlendiğinde tüm metadata RAM'den tamamen silinmelidir!")
        XCTAssertEqual(viewModel.searchText, "", "Arama metni kilitlendiğinde sıfırlanmalıdır.")
        XCTAssertTrue(viewModel.filteredEntries.isEmpty, "Filtrelenmiş kayıtlar boş olmalıdır.")
    }
    
    func testScenePhaseTransitions() {
        // Kasa açıkken
        viewModel.isUnlocked = true
        viewModel.entries = [
            PasswordEntry(title: "Test", username: "test")
        ]
        
        // .inactive durumunda (App Switcher veya Face ID diyalogu) kilit bozulmamalı
        viewModel.handleScenePhase(.inactive)
        XCTAssertTrue(viewModel.isUnlocked, "Face ID diyaloğu anında kilit bozulmamalıdır.")
        
        // .background durumunda anında kilitlenmeli ve RAM temizlenmeli
        viewModel.handleScenePhase(.background)
        XCTAssertFalse(viewModel.isUnlocked, "Arka plana geçildiğinde kasa kilitlenmelidir.")
        XCTAssertTrue(viewModel.entries.isEmpty, "Arka plana geçildiğinde RAM'deki kayıtlar silinmelidir.")
    }
    
    // MARK: - Generator Regression Test
    
    func testViewModelGenerateSecurePasswordDelegatesToPasswordGenerator() {
        let defaultPassword = viewModel.generateSecurePassword()
        XCTAssertEqual(defaultPassword.count, 18, "Varsayılan şifre uzunluğu 18 karakter olmalıdır.")
        
        // Karakter grubu garantileri (PasswordGenerator davranışı)
        let hasUpper = defaultPassword.contains { $0.isUppercase }
        let hasLower = defaultPassword.contains { $0.isLowercase }
        let hasDigit = defaultPassword.contains { $0.isNumber }
        let hasSymbol = defaultPassword.contains { PasswordGenerator.symbolCharacters.contains($0) }
        
        XCTAssertTrue(hasUpper, "PasswordGenerator garantisi: Büyük harf bulunmalıdır.")
        XCTAssertTrue(hasLower, "PasswordGenerator garantisi: Küçük harf bulunmalıdır.")
        XCTAssertTrue(hasDigit, "PasswordGenerator garantisi: Rakam bulunmalıdır.")
        XCTAssertTrue(hasSymbol, "PasswordGenerator garantisi: Özel karakter bulunmalıdır.")
        
        // Eski UUID fallback'in (32 hex karakteri veya tireli UUID) dönmediğini doğrula
        let isUUIDString = UUID(uuidString: defaultPassword) != nil
        XCTAssertFalse(isUUIDString, "Şifre kesinlikle standart bir UUID dizesi olmamalıdır.")
        
        // Özel uzunluk testi
        let customLengthPassword = viewModel.generateSecurePassword(length: 28)
        XCTAssertEqual(customLengthPassword.count, 28, "Belirtilen uzunlukta üretilmelidir.")
        
        // Rastgelelik ve bağımsızlık: 10 ardışık çağrının tamamı birbirinden farklı olmalı
        var generatedSet = Set<String>()
        for _ in 0..<10 {
            let pass = viewModel.generateSecurePassword(length: 20)
            XCTAssertFalse(generatedSet.contains(pass), "Her üretim birbirinden bağımsız ve benzersiz olmalıdır.")
            generatedSet.insert(pass)
        }
        XCTAssertEqual(generatedSet.count, 10)
    }
    
    // MARK: - Privacy Service Overlay Tests
    
    func testPrivacyServiceOverlayBehavior() {
        let privacyService = PrivacyService.shared
        
        // Aktif durumdayken overlay kapalı
        privacyService.handleScenePhaseChange(.active)
        XCTAssertFalse(privacyService.shouldBlurScreen, "Aktif durumdayken ekran gizlenmemelidir.")
        
        // Inactive durumdayken (App Switcher) overlay anında aktif
        privacyService.handleScenePhaseChange(.inactive)
        XCTAssertTrue(privacyService.shouldBlurScreen, "App Switcher (.inactive) anında ekran gizlenmelidir.")
        
        // Background durumundayken overlay aktif
        privacyService.handleScenePhaseChange(.background)
        XCTAssertTrue(privacyService.shouldBlurScreen, "Arka plandayken (.background) ekran gizlenmelidir.")
        
        // Tekrar active olunca overlay kalkar
        privacyService.handleScenePhaseChange(.active)
        XCTAssertFalse(privacyService.shouldBlurScreen, "Tekrar öne gelindiğinde overlay kaldırılmalıdır.")
    }
    
    func testPrivacyServiceRespondsToWillResignActiveNotification() async {
        let privacyService = PrivacyService.shared
        
        // Başlangıçta false olduğunu doğrula
        privacyService.handleScenePhaseChange(.active)
        XCTAssertFalse(privacyService.shouldBlurScreen, "Başlangıçta overlay kapalı olmalıdır.")
        
        // UIApplication.willResignActiveNotification manuel olarak tetikle
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        
        // Combine dağıtımı için kısa bir await Task.yield() bekle
        await Task.yield()
        
        XCTAssertTrue(privacyService.shouldBlurScreen, "willResignActiveNotification sonrasında overlay aktif olmalıdır.")
        
        // UIApplication.didBecomeActiveNotification manuel olarak tetikle
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        
        await Task.yield()
        
        XCTAssertFalse(privacyService.shouldBlurScreen, "didBecomeActiveNotification sonrasında overlay kaldırılmalıdır.")
    }
}
