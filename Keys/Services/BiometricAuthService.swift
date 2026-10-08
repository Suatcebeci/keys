import Foundation
import LocalAuthentication

/// Cihazda desteklenen biyometrik kimlik doğrulama türleri
public enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID
    
    public var displayName: String {
        switch self {
        case .none: return "Cihaz Parolası"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
    
    public var iconName: String {
        switch self {
        case .none: return "lock.shield.fill"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

/// Biyometrik kimlik doğrulama ve cihaz parolası servisi.
/// LocalAuthentication framework'ünü kullanarak güvenli doğrulama sağlar
/// ve Keychain SecAccessControl doğrulaması için doğrulanmış LAContext'i yönetir.
public final class BiometricAuthService {
    
    public static let shared = BiometricAuthService()
    
    /// Aktif kilit açma oturumunda doğrulanmış LAContext nesnesi.
    /// Keychain SecAccessControl öğelerinin kullanıcının yüzünü/parolasını tekrar sormadan
    /// donanımsal olarak çözülebilmesini sağlar.
    private(set) public var currentAuthenticatedContext: LAContext?
    private var currentEvaluatingContext: LAContext?
    private var cachedBiometricType: BiometricType?
    
    public init() {
        warmUpBiometricType()
    }
    
    /// Biyometri tipini erken aşamada, render döngüsünden bağımsız olarak arka planda ısıtır (prefetch).
    /// Böylece LockView ilk render olduğunda ana thread'de senkron canEvaluatePolicy IPC çağrısı yapılmaz.
    public func warmUpBiometricType() {
        guard cachedBiometricType == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let detected = self.detectBiometricType()
            DispatchQueue.main.async {
                if self.cachedBiometricType == nil {
                    self.cachedBiometricType = detected
                }
            }
        }
    }
    
    /// Cihazın desteklediği biyometrik tipi döndürür (Face ID, Touch ID vb.)
    /// UI render döngüsünde her seferinde IPC çağrısı yapılmaması için ilk sorgudan sonra önbelleğe alınır.
    public var availableBiometricType: BiometricType {
        if let cached = cachedBiometricType {
            return cached
        }
        let detected = detectBiometricType()
        cachedBiometricType = detected
        return detected
    }
    
    private func detectBiometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                return .faceID
            case .touchID:
                return .touchID
            case .opticID:
                return .opticID
            default:
                return .none
            }
        }
        return .none
    }
    
    /// Kullanıcıyı biyometrik olarak (varsa) veya cihaz parolası ile doğrular.
    /// .deviceOwnerAuthentication politikası: Önce biyometriyi dener, başarısız olursa
    /// veya kullanıcı isterse cihaz parolasını fallback olarak sunar.
    ///
    /// PERFORMANS OPTİMİZASYONU:
    /// `evaluatePolicy` öncesinde yapılan gereksiz `canEvaluatePolicy` IPC sorgusu kaldırılmıştır.
    /// Sistem katmanı politikayı doğrudan `evaluatePolicy` içinde doğrular ve gereksiz gecikmeyi önler.
    public func authenticate(reason: String = "Kasanızın kilidini açmak için lütfen kimliğinizi doğrulayın.") async -> Result<Bool, Error> {
        let context = LAContext()
        context.localizedCancelTitle = "Vazgeç"
        self.currentEvaluatingContext = context
        defer {
            if self.currentEvaluatingContext === context {
                self.currentEvaluatingContext = nil
            }
        }
        
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                self.currentAuthenticatedContext = context
                // Doğrulanmış context üzerinden biyometri tipini güncelle
                switch context.biometryType {
                case .faceID:
                    self.cachedBiometricType = .faceID
                case .touchID:
                    self.cachedBiometricType = .touchID
                case .opticID:
                    self.cachedBiometricType = .opticID
                default:
                    break
                }
                SecureLogger.info("Kimlik doğrulama başarılı")
                return .success(true)
            } else {
                SecureLogger.info("Kimlik doğrulama başarısız")
                return .success(false)
            }
        } catch {
            let nsError = error as NSError
            // Kullanıcı iptal ettiğinde veya sistem geçici olarak iptal ettiğinde bunu sessizce ele al
            if nsError.domain == LAErrorDomain && (nsError.code == LAError.userCancel.rawValue || nsError.code == LAError.systemCancel.rawValue) {
                SecureLogger.info("Kimlik doğrulama kullanıcı tarafından iptal edildi")
                return .success(false)
            }
            
            SecureLogger.error("Kimlik doğrulama hatası", errorCode: nsError.code)
            return .failure(error)
        }
    }
    
    /// Kasa kilitlendiğinde veya arka plana geçildiğinde aktif ve askıdaki LAContext'leri iptal eder.
    /// Askıdaki çağrıyı iptal etmek, arka plandan dönüşte sistem servisinin takılı kalmasını önler.
    public func invalidateAuthenticationContext() {
        currentEvaluatingContext?.invalidate()
        currentEvaluatingContext = nil
        currentAuthenticatedContext?.invalidate()
        currentAuthenticatedContext = nil
        SecureLogger.info("Kimlik doğrulama oturumu iptal edildi")
    }
}
