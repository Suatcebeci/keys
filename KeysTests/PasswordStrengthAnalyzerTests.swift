import XCTest
@testable import Keys

final class PasswordStrengthAnalyzerTests: XCTestCase {
    
    let analyzer = PasswordStrengthAnalyzer.shared
    
    func testCommonWeakPasswords() {
        let weak1 = analyzer.analyze("12345678")
        XCTAssertEqual(weak1.level, .veryWeak, "'12345678' çok zayıf olarak sınıflandırılmalıdır.")
        
        let weak2 = analyzer.analyze("password")
        XCTAssertEqual(weak2.level, .veryWeak, "'password' çok zayıf olarak sınıflandırılmalıdır.")
        
        let weak3 = analyzer.analyze("qwerty123")
        XCTAssertTrue(weak3.level == .veryWeak || weak3.level == .weak, "'qwerty123' zayıf veya çok zayıf olmalıdır.")
    }
    
    func testShortPasswordPenalty() {
        let short = analyzer.analyze("Ab1!")
        XCTAssertEqual(short.level, .veryWeak, "8 karakterden kısa şifreler çok zayıf olmalıdır.")
    }
    
    func testRepetitiveCharactersPenalty() {
        let repeating = analyzer.analyze("aaaaaaa1111111")
        XCTAssertTrue(repeating.level <= .weak, "Aşırı karakter tekrarı içeren şifreler düşük puan almalıdır.")
    }
    
    func testStrongPassword() {
        let strong = analyzer.analyze("Tr7!kP9@xL2#")
        XCTAssertTrue(strong.level >= .strong, "'Tr7!kP9@xL2#' güçlü veya çok güçlü olmalıdır.")
    }
    
    func testVeryStrongComplexPassword() {
        let veryStrong = analyzer.analyze("K9#vP2$mL8*qZ4!wY6@tR3^bX1&mN5")
        XCTAssertEqual(veryStrong.level, .veryStrong, "30 karakterlik yüksek entropili şifre çok güçlü olmalıdır.")
    }
    
    func testEmptyPassword() {
        let empty = analyzer.analyze("")
        XCTAssertEqual(empty.level, .veryWeak, "Boş string çok zayıf olmalıdır.")
        XCTAssertEqual(empty.entropyBits, 0, "Boş string entropisi 0 olmalıdır.")
    }
    
    func testSingleCharacter() {
        let single = analyzer.analyze("a")
        XCTAssertEqual(single.level, .veryWeak, "Tek karakterli şifre çok zayıf olmalıdır.")
        XCTAssertEqual(single.entropyBits, 0, "Tek karakter cezalardan ötürü 0 bit olmalıdır.")
    }
    
    func testDiversityPenaltiesForLongRepetitivePasswords() {
        // "aaaaaaaa" (8 karakter, tek harf)
        let a8 = analyzer.analyze("aaaaaaaa")
        XCTAssertEqual(a8.level, .veryWeak, "'aaaaaaaa' çok zayıf olmalıdır.")
        
        // "aaaaaaaaaaaaaaaa" (16 karakter, tek harf)
        let a16 = analyzer.analyze("aaaaaaaaaaaaaaaa")
        XCTAssertEqual(a16.level, .veryWeak, "'aaaaaaaaaaaaaaaa' uzun olmasına rağmen çok zayıf olmalıdır.")
        XCTAssertTrue(a16.entropyBits < 28, "Düşük çeşitlilik nedeniyle entropi 28 bitin altında kalmalıdır.")
        
        // "1111111111111111" (16 karakter, tek rakam)
        let ones16 = analyzer.analyze("1111111111111111")
        XCTAssertEqual(ones16.level, .veryWeak, "'1111111111111111' uzun olmasına rağmen çok zayıf olmalıdır.")
        XCTAssertTrue(ones16.entropyBits < 28, "Entropi çok zayıf (< 28 bit) sınırında kalmalıdır.")
        
        // "abababababababab" (16 karakter, 2 benzersiz harf)
        let ab16 = analyzer.analyze("abababababababab")
        XCTAssertEqual(ab16.level, .veryWeak, "'abababababababab' periyodik kalıp ve düşük çeşitlilik nedeniyle çok zayıf olmalıdır.")
    }
    
    func testRepeatedBlocksAndEdgeCases() {
        // "passwordpassword" (Tekrarlanan sözlük kelimesi)
        let passPass = analyzer.analyze("passwordpassword")
        XCTAssertEqual(passPass.level, .veryWeak, "'passwordpassword' blok tekrarı ve yaygın kalıp nedeniyle çok zayıf olmalıdır.")
        
        // "1234567812345678" (Tekrarlanan ardışık dizi)
        let seqRepeat = analyzer.analyze("1234567812345678")
        XCTAssertEqual(seqRepeat.level, .veryWeak, "'1234567812345678' çok zayıf olmalıdır.")
    }
}
