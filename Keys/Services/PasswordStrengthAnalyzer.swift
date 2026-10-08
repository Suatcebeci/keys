import Foundation
import SwiftUI

/// Şifre gücü seviyeleri
public enum PasswordStrengthLevel: Int, CaseIterable, Comparable {
    case veryWeak = 1
    case weak = 2
    case moderate = 3
    case strong = 4
    case veryStrong = 5
    
    public static func < (lhs: PasswordStrengthLevel, rhs: PasswordStrengthLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    public var displayName: String {
        switch self {
        case .veryWeak: return "Çok Zayıf"
        case .weak: return "Zayıf"
        case .moderate: return "Orta"
        case .strong: return "Güçlü"
        case .veryStrong: return "Çok Güçlü"
        }
    }
    
    public var color: Color {
        switch self {
        case .veryWeak: return .red
        case .weak: return .orange
        case .moderate: return .yellow
        case .strong: return .green
        case .veryStrong: return .mint
        }
    }
    
    /// Çoklu çubuk (segment) göstergesi için aktif segment adedi (1-5)
    public var segmentCount: Int {
        return rawValue
    }
}

/// Şifre gücü analiz sonucu
public struct PasswordStrengthResult {
    public let level: PasswordStrengthLevel
    public let entropyBits: Double
    public let feedback: String
    
    public init(level: PasswordStrengthLevel, entropyBits: Double, feedback: String) {
        self.level = level
        self.entropyBits = entropyBits
        self.feedback = feedback
    }
}

/// Tamamen lokal, çevrimdışı çalışan ve entropi tabanlı sezgisel (heuristic) şifre gücü analizörü.
/// Kesinlikle harici API veya internet bağlantısı KULLANMAZ.
public final class PasswordStrengthAnalyzer {
    
    public static let shared = PasswordStrengthAnalyzer()
    
    // Yaygın ve kolay tahmin edilebilir zayıf şifre kalıpları (Offline mini sözlük)
    private static let commonPatterns: Set<String> = [
        "password", "pass", "123456", "12345678", "123456789", "qwerty",
        "admin", "welcome", "letmein", "login", "master", "iloveyou",
        "abc123", "default", "guest", "secret"
    ]
    
    public init() {}
    
    /// Şifrenin entropisini ve sezgisel zayıflıklarını hesaplar
    public func analyze(_ password: String) -> PasswordStrengthResult {
        guard !password.isEmpty else {
            return PasswordStrengthResult(
                level: .veryWeak,
                entropyBits: 0,
                feedback: "Lütfen bir şifre girin."
            )
        }
        
        let length = password.count
        
        // 1. Karakter Havuzu Boyutunu (Pool Size) Belirle:
        var poolSize = 0
        var hasLower = false
        var hasUpper = false
        var hasDigit = false
        var hasSymbol = false
        
        for char in password {
            if char.isLowercase { hasLower = true }
            else if char.isUppercase { hasUpper = true }
            else if char.isNumber { hasDigit = true }
            else { hasSymbol = true }
        }
        
        if hasLower { poolSize += 26 }
        if hasUpper { poolSize += 26 }
        if hasDigit { poolSize += 10 }
        if hasSymbol { poolSize += 33 }
        
        guard poolSize > 0 else {
            return PasswordStrengthResult(level: .veryWeak, entropyBits: 0, feedback: "Geçersiz karakter.")
        }
        
        // 2. Hartley Bilgi Tahmini / Brute-Force Entropisi: E = L * log2(R)
        var entropy = Double(length) * log2(Double(poolSize))
        
        // Karakter Çeşitliliği Analizi (Diversity Factor)
        // Sıfıra bölme hatasını (division by zero) önlemek için guard !password.isEmpty yukarıda garanti edilmiştir.
        let uniqueCharacterCount = Set(password).count
        let uniqueCharacterRatio = Double(uniqueCharacterCount) / Double(length)
        
        if uniqueCharacterRatio < 0.3 {
            // Düşük çeşitlilik cezası: "aaaaaaaaaaaaaaaa" gibi şifrelerin uzunluktan dolayı
            // yüksek puan almasını engelleyen oransal ve kuadratik ağır ceza
            let diversityFactor = pow(uniqueCharacterRatio / 0.3, 2.0)
            entropy *= diversityFactor
        }
        
        // 3. Sezgisel (Heuristic) Cezalar ve Zayıflık İndirimleri:
        let lowerPassword = password.lowercased()
        
        // Ceza 1: Yaygın kalıp içeriyor mu?
        for pattern in Self.commonPatterns {
            if lowerPassword.contains(pattern) {
                entropy -= 30.0
                break
            }
        }
        
        // Ceza 2: Ardışık 3 veya daha fazla aynı karakter tekrarı ("aaa", "111")
        if containsRepeatingCharacters(password, threshold: 3) {
            entropy -= 18.0
        }
        
        // Ceza 3: Ardışık sayı veya harf dizilimleri ("1234", "abcd")
        if containsSequentialCharacters(password, threshold: 3) {
            entropy -= 15.0
        }
        
        // Ceza 4: 8 karakterden kısa şifreler için ağır ceza
        if length < 8 {
            entropy -= 25.0
        }
        
        // Ceza 5: Tekrarlanan blok / periyodik kalıp tespiti ("passwordpassword", "1234567812345678", "abababab")
        if containsRepeatedPattern(password) {
            entropy *= 0.5
            entropy -= 15.0
        }
        
        // Entropiyi negatif olmayacak şekilde sınırla
        entropy = max(0, entropy)
        
        // 4. Seviye Sınıflandırması:
        let level: PasswordStrengthLevel
        let feedback: String
        
        if entropy < 28 {
            level = .veryWeak
            if length < 8 {
                feedback = "Şifreniz çok kısa (en az 8 karakter önerilir)."
            } else if uniqueCharacterRatio < 0.3 {
                feedback = "Karakter çeşitliliği çok düşük; farklı karakterler ekleyin."
            } else {
                feedback = "Kolay tahmin edilebilir kalıplar içeriyor."
            }
        } else if entropy < 45 {
            level = .weak
            feedback = "Şifrenizi uzatın veya büyük harf/özel karakter ekleyin."
        } else if entropy < 65 {
            level = .moderate
            feedback = "Kabul edilebilir ancak daha uzun olması önerilir."
        } else if entropy < 85 {
            level = .strong
            feedback = "Güçlü ve güvenli bir şifre."
        } else {
            level = .veryStrong
            feedback = "Mükemmel güçte ve kırılması son derece zor bir şifre."
        }
        
        return PasswordStrengthResult(level: level, entropyBits: entropy, feedback: feedback)
    }
    
    // MARK: - Sezgisel Yardımcılar
    
    private func containsRepeatingCharacters(_ text: String, threshold: Int) -> Bool {
        guard text.count >= threshold else { return false }
        var count = 1
        var previousChar: Character? = nil
        
        for char in text {
            if let prev = previousChar, prev == char {
                count += 1
                if count >= threshold { return true }
            } else {
                count = 1
                previousChar = char
            }
        }
        return false
    }
    
    private func containsSequentialCharacters(_ text: String, threshold: Int) -> Bool {
        guard text.count >= threshold else { return false }
        let scalars = text.unicodeScalars.map { Int($0.value) }
        
        var forwardSeq = 1
        var backwardSeq = 1
        
        for i in 1..<scalars.count {
            let diff = scalars[i] - scalars[i - 1]
            if diff == 1 {
                forwardSeq += 1
                backwardSeq = 1
                if forwardSeq >= threshold { return true }
            } else if diff == -1 {
                backwardSeq += 1
                forwardSeq = 1
                if backwardSeq >= threshold { return true }
            } else {
                forwardSeq = 1
                backwardSeq = 1
            }
        }
        return false
    }
    
    /// Bütün şifrenin kendini tekrar eden periyodik alt bloklardan oluşup oluşmadığını tespit eder ("passwordpassword", "ababab" vb.)
    private func containsRepeatedPattern(_ text: String) -> Bool {
        let count = text.count
        guard count >= 4 else { return false }
        
        for patternLen in 1...(count / 2) {
            if count % patternLen == 0 {
                let firstChunk = text.prefix(patternLen)
                var allMatch = true
                var index = text.startIndex
                while index < text.endIndex {
                    let nextIndex = text.index(index, offsetBy: patternLen)
                    if text[index..<nextIndex] != firstChunk {
                        allMatch = false
                        break
                    }
                    index = nextIndex
                }
                if allMatch {
                    return true
                }
            }
        }
        return false
    }
}
