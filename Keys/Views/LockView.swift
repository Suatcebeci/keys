import SwiftUI

/// Sade, profesyonel ve modern kilit ekranı.
/// Face ID / Touch ID ve Cihaz Parolası doğrulamasını destekler; %100 çevrimdışı çalışır.
public struct LockView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: PasswordVaultViewModel
    private let biometricService = BiometricAuthService.shared
    
    public init(viewModel: PasswordVaultViewModel) {
        self.viewModel = viewModel
    }
    
    private var biometricButtonTitle: String {
        switch biometricService.availableBiometricType {
        case .faceID:
            return "Face ID ile Aç"
        case .touchID:
            return "Touch ID ile Aç"
        case .opticID:
            return "Optic ID ile Aç"
        case .none:
            return "Parola ile Aç"
        }
    }
    
    private var biometricIconName: String {
        switch biometricService.availableBiometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "key.fill"
        }
    }
    
    public var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // İkon ve Başlıklar
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    
                    VStack(spacing: 6) {
                        Text("Keys")
                            .font(.system(.largeTitle, design: .default, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Kasan kilitli")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Hata Mesajı Varsa
                if let errorMessage = viewModel.authErrorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Doğrulama Butonu ve Çevrimdışı Göstergesi
                VStack(spacing: 16) {
                    Button {
                        Task(priority: .userInitiated) {
                            await viewModel.unlockVault()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: biometricIconName)
                                .font(.body.weight(.semibold))
                            Text(biometricButtonTitle)
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(viewModel.isAuthenticating)
                    .accessibilityLabel(biometricButtonTitle)
                    
                    // Offline Göstergesi
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.caption2.weight(.bold))
                        Text("Offline")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if !viewModel.isManualLock {
                Task(priority: .userInitiated) {
                    await viewModel.unlockVault()
                }
            }
        }
    }
}
