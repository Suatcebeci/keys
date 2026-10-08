import SwiftUI

/// App Switcher ve arka plan anında ekrana bindirilen, %100 opak ve güvenli gizlilik katmanı.
/// iOS snapshot mekanizmasının altındaki şifreleri yakalamasını kesinlikle engellemek için
/// herhangi bir animasyon veya şeffaflık içermez.
public struct PrivacyOverlayView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            // Tamamen opak siyah zemin (Snapshot'ta arkadaki görünümü %100 bloke eder)
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 90, height: 90)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 6) {
                    Text("Kasa Kilitlendi")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    
                    Text("Gizlilik koruması nedeniyle içerik gizlendi")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(32)
        }
    }
}

#Preview {
    PrivacyOverlayView()
}
