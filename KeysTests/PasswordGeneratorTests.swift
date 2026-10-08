import XCTest
@testable import Keys

final class PasswordGeneratorTests: XCTestCase {
    
    let generator = PasswordGenerator.shared
    
    func testDefaultPasswordGeneration() throws {
        let config = PasswordGeneratorConfig()
        let password = try generator.generatePassword(config: config)
        
        XCTAssertEqual(password.count, 20, "Varsayılan şifre uzunluğu 20 karakter olmalıdır.")
        
        // Karakter grubu garantisi doğrulaması
        let hasUpper = password.contains { $0.isUppercase }
        let hasLower = password.contains { $0.isLowercase }
        let hasDigit = password.contains { $0.isNumber }
        let hasSymbol = password.contains { PasswordGenerator.symbolCharacters.contains($0) }
        
        XCTAssertTrue(hasUpper, "Büyük harf seçiliyse şifrede en az 1 büyük harf bulunmalıdır.")
        XCTAssertTrue(hasLower, "Küçük harf seçiliyse şifrede en az 1 küçük harf bulunmalıdır.")
        XCTAssertTrue(hasDigit, "Rakam seçiliyse şifrede en az 1 rakam bulunmalıdır.")
        XCTAssertTrue(hasSymbol, "Özel karakter seçiliyse şifrede en az 1 özel karakter bulunmalıdır.")
    }
    
    func testMinimumLength() throws {
        let config = PasswordGeneratorConfig(length: 8)
        let password = try generator.generatePassword(config: config)
        XCTAssertEqual(password.count, 8)
    }
    
    func testMaximumLength() throws {
        let config = PasswordGeneratorConfig(length: 64)
        let password = try generator.generatePassword(config: config)
        XCTAssertEqual(password.count, 64)
    }
    
    func testOnlyUppercase() throws {
        let config = PasswordGeneratorConfig(
            length: 15,
            includeUppercase: true,
            includeLowercase: false,
            includeDigits: false,
            includeSymbols: false
        )
        let password = try generator.generatePassword(config: config)
        
        XCTAssertEqual(password.count, 15)
        XCTAssertTrue(password.allSatisfy { $0.isUppercase })
    }
    
    func testOnlyLowercase() throws {
        let config = PasswordGeneratorConfig(
            length: 12,
            includeUppercase: false,
            includeLowercase: true,
            includeDigits: false,
            includeSymbols: false
        )
        let password = try generator.generatePassword(config: config)
        
        XCTAssertEqual(password.count, 12)
        XCTAssertTrue(password.allSatisfy { $0.isLowercase })
    }
    
    func testOnlyDigits() throws {
        let config = PasswordGeneratorConfig(
            length: 10,
            includeUppercase: false,
            includeLowercase: false,
            includeDigits: true,
            includeSymbols: false
        )
        let password = try generator.generatePassword(config: config)
        
        XCTAssertEqual(password.count, 10)
        XCTAssertTrue(password.allSatisfy { $0.isNumber })
    }
    
    func testOnlySymbols() throws {
        let config = PasswordGeneratorConfig(
            length: 14,
            includeUppercase: false,
            includeLowercase: false,
            includeDigits: false,
            includeSymbols: true
        )
        let password = try generator.generatePassword(config: config)
        
        XCTAssertEqual(password.count, 14)
        XCTAssertTrue(password.allSatisfy { PasswordGenerator.symbolCharacters.contains($0) })
    }
    
    func testNoCharacterGroupThrowsError() {
        let config = PasswordGeneratorConfig(
            length: 16,
            includeUppercase: false,
            includeLowercase: false,
            includeDigits: false,
            includeSymbols: false
        )
        
        XCTAssertThrowsError(try generator.generatePassword(config: config)) { error in
            XCTAssertEqual(error as? PasswordGeneratorError, PasswordGeneratorError.noCharacterGroupSelected)
        }
    }
    
    func testConsecutivePasswordsAreNotEqual() throws {
        let config = PasswordGeneratorConfig(length: 24)
        var generatedSet = Set<String>()
        
        // 50 adet şifre üret; hepsi birbirinden farklı olmalıdır
        for _ in 0..<50 {
            let password = try generator.generatePassword(config: config)
            XCTAssertFalse(generatedSet.contains(password), "Kriptografik rastgelelikte aynı şifrenin tekrar üretilmemesi gerekir.")
            generatedSet.insert(password)
        }
        
        XCTAssertEqual(generatedSet.count, 50)
    }
}
