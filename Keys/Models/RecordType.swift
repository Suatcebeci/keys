import Foundation

/// Kayıt türü ayrımı (Kategori DEĞİLDİR).
/// Sistem yalnızca iki temel kayıt tipini destekler: Standart Giriş (Login) ve Banka (Bank).
public enum RecordType: String, Codable, CaseIterable, Identifiable {
    case login = "login"
    case bank = "bank"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .login: return "Giriş"
        case .bank: return "Banka"
        }
    }
}
