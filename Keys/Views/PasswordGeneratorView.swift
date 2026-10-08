import SwiftUI

/// Kullanıcının isteğe göre özelleştirilebilir, yüksek entropili rastgele şifreler üretmesini sağlayan görünüm.
public struct PasswordGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Callback: Kullanıcı oluşturulan şifreyi forma aktarmak istediğinde çağrılır
    var onUsePassword: ((String) -> Void)?
    
    // Yapılandırma Durumları
    @State private var length: Double = 20
    @State private var includeUppercase: Bool = true
    @State private var includeLowercase: Bool = true
    @State private var includeDigits: Bool = true
    @State private var includeSymbols: Bool = true
    
    // Üretilen Şifre ve UI Durumları
    @State private var generatedPassword: String = ""
    @State private var isPasswordVisible: Bool = true
    @State private var isCopied: Bool = false
    @State private var errorMessage: String? = nil
    
    public init(onUsePassword: ((String) -> Void)? = nil) {
        self.onUsePassword = onUsePassword
    }
    
    private var isConfigValid: Bool {
        includeUppercase || includeLowercase || includeDigits || includeSymbols
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Üretilen Şifre Önizleme Kartı
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if isPasswordVisible {
                                Text(generatedPassword.isEmpty ? "••••••••••••••••" : generatedPassword)
                                    .font(.system(.title3, design: .monospaced, weight: .bold))
                                    .textSelection(.enabled)
                                    .foregroundColor(.primary)
                                    .accessibilityLabel("Üretilen şifre")
                                    .accessibilityValue("Görünür")
                            } else {
                                Text(String(repeating: "•", count: Int(length)))
                                    .font(.system(.title3, design: .monospaced, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .accessibilityLabel("Üretilen şifre")
                                    .accessibilityValue("Gizli")
                            }
                            
                            Spacer()
                            
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(isPasswordVisible ? "Şifreyi Gizle" : "Şifreyi Göster")
                        }
                        
                        // Şifre Güç Göstergesi
                        if isConfigValid && !generatedPassword.isEmpty {
                            PasswordStrengthView(password: generatedPassword)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Üretilen Şifre")
                }
                
                // MARK: - Uzunluk Ayarı
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Karakter Uzunluğu")
                            Spacer()
                            Text("\(Int(length))")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.accentColor)
                        }
                        
                        Slider(value: $length, in: 8...64, step: 1) {
                            Text("Uzunluk")
                        } minimumValueLabel: {
                            Text("8").font(.caption2).foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("64").font(.caption2).foregroundColor(.secondary)
                        }
                        .tint(.accentColor)
                        .onChange(of: length) { _, _ in
                            generate()
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Uzunluk")
                }
                
                // MARK: - Karakter Grubu Seçenekleri
                Section {
                    Toggle("Büyük Harf (A-Z)", isOn: $includeUppercase)
                        .onChange(of: includeUppercase) { _, _ in generate() }
                    
                    Toggle("Küçük Harf (a-z)", isOn: $includeLowercase)
                        .onChange(of: includeLowercase) { _, _ in generate() }
                    
                    Toggle("Rakamlar (0-9)", isOn: $includeDigits)
                        .onChange(of: includeDigits) { _, _ in generate() }
                    
                    Toggle("Özel Karakterler (!@#$...)", isOn: $includeSymbols)
                        .onChange(of: includeSymbols) { _, _ in generate() }
                } header: {
                    Text("Karakter Kümeleri")
                } footer: {
                    if !isConfigValid {
                        Text("Güvenli şifre oluşturmak için en az bir karakter grubu seçilmelidir.")
                            .foregroundColor(.red)
                    }
                }
                
                // MARK: - Aksiyon Butonları
                Section {
                    // Yeniden Üret
                    Button {
                        generate()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Yeni Şifre Üret", systemImage: "arrow.clockwise")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!isConfigValid)
                    
                    // Panoya Kopyala
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack {
                            Spacer()
                            Label(isCopied ? "Panoya Kopyalandı!" : "Panoya Kopyala",
                                  systemImage: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.headline)
                                .foregroundColor(isCopied ? .green : .accentColor)
                            Spacer()
                        }
                    }
                    .disabled(!isConfigValid || generatedPassword.isEmpty)
                    
                    // Formda Kullan Butonu (Eğer callback varsa)
                    if let onUse = onUsePassword {
                        Button {
                            onUse(generatedPassword)
                            cleanAndDismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Bu Şifreyi Kullan")
                                    .font(.headline.weight(.bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(isConfigValid ? Color.accentColor : Color.gray.opacity(0.3))
                        .disabled(!isConfigValid || generatedPassword.isEmpty)
                    }
                }
            }
            .navigationTitle("Şifre Üretici")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        cleanAndDismiss()
                    }
                }
            }
            .onAppear {
                generate()
            }
            .onDisappear {
                cleanState()
            }
        }
    }
    
    // MARK: - Mantıksal İşlemler
    
    private func generate() {
        guard isConfigValid else {
            generatedPassword = ""
            return
        }
        
        let config = PasswordGeneratorConfig(
            length: Int(length),
            includeUppercase: includeUppercase,
            includeLowercase: includeLowercase,
            includeDigits: includeDigits,
            includeSymbols: includeSymbols
        )
        
        do {
            self.generatedPassword = try PasswordGenerator.shared.generatePassword(config: config)
        } catch {
            self.generatedPassword = ""
        }
    }
    
    private func copyToClipboard() {
        guard !generatedPassword.isEmpty else { return }
        ClipboardService.shared.copySensitiveText(generatedPassword)
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func cleanState() {
        generatedPassword = ""
        isCopied = false
    }
    
    private func cleanAndDismiss() {
        cleanState()
        dismiss()
    }
}

#Preview {
    PasswordGeneratorView(onUsePassword: { _ in })
}
