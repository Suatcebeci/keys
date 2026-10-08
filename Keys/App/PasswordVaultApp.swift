import SwiftUI

/// Offline Şifre Kasası ana uygulama yaşam döngüsü.
/// Güvenlik, App Switcher gizliliği ve otomatik kilit mekanizmalarını burada yönetir.
@main
struct PasswordVaultApp: App {
    @StateObject private var viewModel = PasswordVaultViewModel()
    @StateObject private var privacyService = PrivacyService.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Kasa durumuna göre kilit veya ana ekran
                if viewModel.isUnlocked {
                    HomeView(viewModel: viewModel)
                } else {
                    LockView(viewModel: viewModel)
                }
                
                // App Switcher veya arka plana geçildiğinde ekranı örten gizlilik katmanı
                // GÜVENLİK: Animasyon veya geçiş efekti KULLANILMAZ (Anında örtülür).
                // PERFORMANS: scenePhase gecikmeli güncellendiği için doğrudan PrivacyService dinlenir.
                if privacyService.shouldBlurScreen {
                    PrivacyOverlayView()
                        .zIndex(999)
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                privacyService.handleScenePhaseChange(newPhase)
                viewModel.handleScenePhase(from: oldPhase, to: newPhase)
            }
        }
    }
}
