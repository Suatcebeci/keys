import Foundation
import SwiftUI
import UIKit
import Combine

/// Uygulama arka plana düştüğünde veya App Switcher açıldığında
/// hassas verilerin görünmesini engelleyen deterministik gizlilik servisi.
///
/// GÜVENLİK NOTU:
/// SwiftUI `scenePhase` döngüsü asenkron çalışabildiği için, iOS snapshot almadan
/// ÖNCE tetiklenen `UIApplication.willResignActiveNotification` doğrudan dinlenir.
/// Hiçbir animasyon veya gecikme kullanılmaz.
@MainActor
public final class PrivacyService: ObservableObject {
    public static let shared = PrivacyService()
    
    /// Ekranın gizlilik katmanı ile anında örtülü olup olmadığı
    @Published public var shouldBlurScreen: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupLifecycleObservers()
    }
    
    private func setupLifecycleObservers() {
        // iOS sisteminin App Switcher snapshot'ı almadan önceki İLK senkron bildirimi:
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.showOverlayInstantly()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.hideOverlayInstantly()
            }
            .store(in: &cancellables)
    }
    
    /// SwiftUI scenePhase geçişlerini doğrudan yönetir (Yedek tetikleyici)
    public func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            hideOverlayInstantly()
        case .inactive, .background:
            showOverlayInstantly()
        @unknown default:
            showOverlayInstantly()
        }
    }
    
    /// Gizlilik katmanını sıfır animasyonla, anında ekrana basar
    public func showOverlayInstantly() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.shouldBlurScreen = true
        }
    }
    
    /// Ön plana gelindiğinde katmanı anında kaldırır
    public func hideOverlayInstantly() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.shouldBlurScreen = false
        }
    }
}
