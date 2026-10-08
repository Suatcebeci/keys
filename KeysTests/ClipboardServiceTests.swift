import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import Keys

@MainActor
final class ClipboardServiceTests: XCTestCase {
    
    var clipboardService: ClipboardService!
    
    override func setUp() {
        super.setUp()
        clipboardService = ClipboardService.shared
        UIPasteboard.general.items = []
    }
    
    override func tearDown() {
        UIPasteboard.general.items = []
        super.tearDown()
    }
    
    func testCopySensitiveTextSetsState() {
        let secret = "super_secure_random_pass_999"
        clipboardService.copySensitiveText(secret, timeout: 45)
        
        XCTAssertTrue(clipboardService.isCopied)
        XCTAssertEqual(clipboardService.secondsRemaining, 45)
        XCTAssertEqual(UIPasteboard.general.string, secret)
    }
    
    func testCopyEmptyStringDoesNothing() {
        clipboardService.clearClipboardIfMatching()
        clipboardService.copySensitiveText("")
        XCTAssertFalse(clipboardService.isCopied)
        XCTAssertEqual(clipboardService.secondsRemaining, 0)
    }
    
    func testDefaultTimeoutUsesSecurityConstant() {
        let secret = "test_timeout_pass"
        clipboardService.copySensitiveText(secret)
        XCTAssertEqual(Double(clipboardService.secondsRemaining), SecurityConstants.clipboardClearTimeoutSeconds)
    }
    
    func testClearClipboardDoesNotOverwriteOtherContent() {
        let secret = "original_secret"
        clipboardService.copySensitiveText(secret, timeout: 45)
        
        // Kullanıcı başka bir uygulamadan yeni bir şey kopyaladı
        UIPasteboard.general.string = "kullanicinin_baska_metni"
        
        // Temizleme çağrıldığında kullanıcının yeni metni silinmemeli
        clipboardService.clearClipboardIfMatching()
        
        XCTAssertEqual(UIPasteboard.general.string, "kullanicinin_baska_metni", "Kullanıcının harici kopyalaması korunmalıdır.")
    }
    
    func testSyncStateOnForegroundWhenNotExpired() {
        clipboardService.copySensitiveText("active_secret", timeout: 45)
        clipboardService.syncStateOnForeground()
        XCTAssertTrue(clipboardService.secondsRemaining > 0)
        XCTAssertEqual(UIPasteboard.general.string, "active_secret")
    }
}
