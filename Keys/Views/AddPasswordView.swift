import SwiftUI

/// Yeni şifre kaydı ekleme formu (Başlık, Kullanıcı Adı, Web Sitesi, Şifre, Notlar).
/// Güvenlik: Form kapandığında geçici şifre değişkenleri derhal bellekten temizlenir.
public struct AddPasswordView: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var website: String = ""
    @State private var notes: String = ""
    
    @State private var isPasswordVisible: Bool = false
    @State private var showingGeneratorSheet: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false
    @State private var passwordCopiedMessage: Bool = false
    
    public init(viewModel: PasswordVaultViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Temel Bilgiler
                Section {
                    TextField("Başlık (Zorunlu)", text: $title)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                    
                    TextField("Kullanıcı Adı veya E-posta", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    
                    TextField("Web Sitesi (Örn: example.com)", text: $website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Hesap Bilgileri")
                }
                
                // MARK: - Şifre Alanı ve Güç Analizi
                Section {
                    HStack {
                        if isPasswordVisible {
                            TextField("Şifre (Zorunlu)", text: $password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Şifre (Zorunlu)", text: $password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        
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
                    
                    // Canlı Şifre Gücü Göstergesi
                    if !password.isEmpty {
                        PasswordStrengthView(password: password)
                            .padding(.top, 2)
                    }
                    
                    // Şifre Aksiyon Butonları (Şifre Üret & Kopyala)
                    HStack(spacing: 16) {
                        Button {
                            showingGeneratorSheet = true
                        } label: {
                            Label("Şifre Üret", systemImage: "sparkles")
                                .font(.footnote.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        
                        Spacer()
                        
                        if !password.isEmpty {
                            Button {
                                ClipboardService.shared.copySensitiveText(password)
                                passwordCopiedMessage = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    passwordCopiedMessage = false
                                }
                            } label: {
                                Label(passwordCopiedMessage ? "Kopyalandı!" : "Kopyala",
                                      systemImage: passwordCopiedMessage ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                    .font(.footnote.weight(.medium))
                                    .foregroundColor(passwordCopiedMessage ? .green : .accentColor)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Şifre")
                } footer: {
                    Text("Kopyalanan şifre 45 saniye sonra panodan otomatik olarak silinir.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Gizli Notlar
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notlar (İsteğe Bağlı)")
                }
            }
            .navigationTitle("Yeni Kayıt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        cleanStateAndDismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        saveNewEntry()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            }
            .sheet(isPresented: $showingGeneratorSheet) {
                PasswordGeneratorView { generated in
                    self.password = generated
                    self.isPasswordVisible = true
                }
            }
            .alert("Kayıt Hatası", isPresented: $showingErrorAlert, actions: {
                Button("Tamam", role: .cancel) {}
            }, message: {
                Text(errorMessage ?? "Kayıt sırasında bir hata oluştu.")
            })
            .onDisappear {
                cleanState()
            }
        }
    }
    
    // MARK: - Kayıt Mantığı
    private func saveNewEntry() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Lütfen bir başlık girin."
            showingErrorAlert = true
            return
        }
        
        guard !password.isEmpty else {
            errorMessage = "Şifre alanı boş bırakılamaz."
            showingErrorAlert = true
            return
        }
        
        do {
            try viewModel.createEntry(
                title: trimmedTitle,
                username: username,
                password: password,
                website: website,
                notes: notes
            )
            cleanStateAndDismiss()
        } catch {
            errorMessage = "Kayıt Keychain'e kaydedilemedi: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    // MARK: - Bellek Temizliği
    private func cleanState() {
        password = ""
    }
    
    private func cleanStateAndDismiss() {
        cleanState()
        dismiss()
    }
}
