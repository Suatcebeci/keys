import SwiftUI

/// Şifre gücünü 5 parçalı renkli segmentler ve açıklayıcı etiket ile görselleştiren bileşen.
public struct PasswordStrengthView: View {
    let password: String
    
    private var result: PasswordStrengthResult {
        PasswordStrengthAnalyzer.shared.analyze(password)
    }
    
    public init(password: String) {
        self.password = password
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 5 Segmentli İlerleme Çubuğu
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { segment in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            segment <= result.level.segmentCount ?
                            result.level.color :
                            Color(uiColor: .tertiarySystemFill)
                        )
                        .frame(height: 4)
                }
            }
            
            // Seviye İsmi ve Geri Bildirim
            HStack {
                Text("Şifre Gücü:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(result.level.displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(result.level.color)
                
                Spacer()
                
                Text(result.feedback)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .animation(.easeInOut(duration: 0.2), value: result.level)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Şifre gücü: \(result.level.displayName). \(result.feedback)")
    }
}

#Preview {
    VStack(spacing: 20) {
        PasswordStrengthView(password: "123456")
        PasswordStrengthView(password: "qwerty123")
        PasswordStrengthView(password: "Tr7!kP9@xL2#")
    }
    .padding()
}
