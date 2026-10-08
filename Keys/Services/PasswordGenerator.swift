import Foundation
import Security

/// Şifre üretici hata durumları
public enum PasswordGeneratorError: LocalizedError {
    case noCharacterGroupSelected
    case invalidLength
    case randomGenerationFailed
    
    public var errorDescription: String? {
        switch self {
        case .noCharacterGroupSelected:
            return "Güvenli şifre oluşturmak için en az bir karakter grubu seçilmelidir."
        case .invalidLength:
            return "Şifre uzunluğu en az 8, en fazla 64 karakter olmalıdır."
        case .randomGenerationFailed:
            return "Kriptografik rastgele bayt üretimi başarısız oldu."
        }
    }
}

/// Şifre üretici konfigürasyonu
public struct PasswordGeneratorConfig {
    public var length: Int
    public var includeUppercase: Bool
    public var includeLowercase: Bool
    public var includeDigits: Bool
    public var includeSymbols: Bool
    
    public init(
        length: Int = 20,
        includeUppercase: Bool = true,
        includeLowercase: Bool = true,
        includeDigits: Bool = true,
        includeSymbols: Bool = true
    ) {
        self.length = max(8, min(64, length))
        self.includeUppercase = includeUppercase
        self.includeLowercase = includeLowercase
        self.includeDigits = includeDigits
        self.includeSymbols = includeSymbols
    }
    
    public var activeGroupCount: Int {
        var count = 0
        if includeUppercase { count += 1 }
        if includeLowercase { count += 1 }
        if includeDigits { count += 1 }
        if includeSymbols { count += 1 }
        return count
    }
}

/// Kriptografik olarak güvenli (CSPRNG) ve önyargısız (unbiased rejection sampling) şifre üretici servisi.
/// Sorumluluk Ayrımı: Yalnızca şifre üretir; Keychain veya depolama servislerine doğrudan bağlanmaz.
public final class PasswordGenerator {
    
    public static let shared = PasswordGenerator()
    
    // MARK: - Standart ve Güvenli Karakter Kümeleri
    public static let uppercaseCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    public static let lowercaseCharacters = Array("abcdefghijklmnopqrstuvwxyz")
    public static let digitCharacters     = Array("0123456789")
    // Web siteleri ve formlarda sorun çıkarmayacak güvenli özel karakter seti:
    public static let symbolCharacters    = Array("!@#$%^&*()-_=+[]{};:,.?")
    
    public init() {}
    
    /// Belirtilen konfigürasyona uygun rastgele ve güçlü bir şifre üretir.
    public func generatePassword(config: PasswordGeneratorConfig) throws -> String {
        guard config.length >= 8 && config.length <= 64 else {
            throw PasswordGeneratorError.invalidLength
        }
        
        var selectedGroups: [[Character]] = []
        if config.includeUppercase { selectedGroups.append(Self.uppercaseCharacters) }
        if config.includeLowercase { selectedGroups.append(Self.lowercaseCharacters) }
        if config.includeDigits    { selectedGroups.append(Self.digitCharacters) }
        if config.includeSymbols   { selectedGroups.append(Self.symbolCharacters) }
        
        guard !selectedGroups.isEmpty else {
            throw PasswordGeneratorError.noCharacterGroupSelected
        }
        
        var passwordCharacters: [Character] = []
        
        // 1. Karakter Grubu Garantisi:
        // Seçilen her gruptan en az 1 karakterin şifrede bulunmasını sağla
        for group in selectedGroups {
            let guaranteedChar = try secureRandomElement(from: group)
            passwordCharacters.append(guaranteedChar)
        }
        
        // 2. Kalan Karakterleri Birleşik Havuzdan Doldur:
        let combinedPool = selectedGroups.flatMap { $0 }
        let remainingCount = config.length - passwordCharacters.count
        
        for _ in 0..<remainingCount {
            let char = try secureRandomElement(from: combinedPool)
            passwordCharacters.append(char)
        }
        
        // 3. Güvenli Karıştırma (Fisher-Yates Shuffle with CSPRNG):
        try secureShuffle(&passwordCharacters)
        
        return String(passwordCharacters)
    }
    
    // MARK: - Unbiased Rejection Sampling (Önyargısız Seçim)
    
    /// `byte % count` işlemindeki modulo bias sorununu engellemek için
    /// rejection sampling tekniğiyle tamamen uniform rastgele karakter seçer.
    private func secureRandomElement(from array: [Character]) throws -> Character {
        guard !array.isEmpty else {
            throw PasswordGeneratorError.randomGenerationFailed
        }
        
        let count = UInt32(array.count)
        // 256'nın (veya UInt32.max'ın) count'a tam bölünmeyen fazlalık bölgesini reddet
        let limit = UInt32.max - (UInt32.max % count)
        var randomValue: UInt32 = 0
        
        while true {
            let status = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &randomValue)
            guard status == errSecSuccess else {
                throw PasswordGeneratorError.randomGenerationFailed
            }
            
            if randomValue < limit {
                let index = Int(randomValue % count)
                return array[index]
            }
            // randomValue >= limit ise reddedilir ve eşit olasılık için tekrar çekilir
        }
    }
    
    /// Diziyi SecRandomCopyBytes kullanarak önyargısız şekilde yerinde karıştırır
    private func secureShuffle(_ array: inout [Character]) throws {
        guard array.count > 1 else { return }
        
        for i in stride(from: array.count - 1, through: 1, by: -1) {
            let count = UInt32(i + 1)
            let limit = UInt32.max - (UInt32.max % count)
            var randomValue: UInt32 = 0
            
            while true {
                let status = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &randomValue)
                guard status == errSecSuccess else {
                    throw PasswordGeneratorError.randomGenerationFailed
                }
                
                if randomValue < limit {
                    let j = Int(randomValue % count)
                    array.swapAt(i, j)
                    break
                }
            }
        }
    }
}
