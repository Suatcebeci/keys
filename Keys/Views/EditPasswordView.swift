import SwiftUI

/// Mevcut şifre kaydını düzenleme görünümü.
/// Yalnızca değişen alanlar güncellenir; şifre değiştirilmediyse Keychain secret'ı yeniden yazılmaz.
public struct EditPasswordView: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    let entry: PasswordEntry
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var username: String
    @State private var website: String
    @State private var notes: String
    
    // Şifre değiştirme alanları
    @State private var changePassword: Bool = false
    @State private var newPassword: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showingGeneratorSheet: Bool = false
    
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false
    
    public init(viewModel: PasswordVaultViewModel, entry: PasswordEntry) {
        self.viewModel = viewModel
        self.entry = entry
        _title = State(initialValue: entry.title)
        _username = State(initialValue: entry.username)
        _website = State(initialValue: entry.website)
        _notes = State(initialValue: entry.notes)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Temel Bilgiler
                Section {
                    TextField("Başlık", text: $title)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                    
                    TextField("Kullanıcı Adı veya E-posta", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    
                    TextField("Web Sitesi", text: $website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Hesap Bilgileri")
                }
                
                // MARK: - Şifre Güncelleme Bölümü
                Section {
                    Toggle("Şifreyi Değiştir", isOn: $changePassword.animation())
                    
                    if changePassword {
                        HStack {
                            if isPasswordVisible {
                                TextField("Yeni Şifre", text: $newPassword)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("Yeni Şifre", text: $newPassword)
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
                        
                        // Canlı Şifre Güç Göstergesi
                        if !newPassword.isEmpty {
                            PasswordStrengthView(password: newPassword)
                                .padding(.top, 2)
                        }
                        
                        Button {
                            showingGeneratorSheet = true
                        } label: {
                            Label("Şifre Üretici", systemImage: "sparkles")
                                .font(.footnote.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Güvenlik")
                } footer: {
                    if !changePassword {
                        Text("Mevcut şifreniz korunacaktır.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // MARK: - Gizli Notlar
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notlar")
                }
            }
            .navigationTitle("Kaydı Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        cleanStateAndDismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Güncelle") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (changePassword && newPassword.isEmpty))
                }
            }
            .sheet(isPresented: $showingGeneratorSheet) {
                PasswordGeneratorView { generated in
                    self.newPassword = generated
                    self.isPasswordVisible = true
                }
            }
            .alert("Güncelleme Hatası", isPresented: $showingErrorAlert, actions: {
                Button("Tamam", role: .cancel) {}
            }, message: {
                Text(errorMessage ?? "Kayıt güncellenirken bir hata oluştu.")
            })
            .onDisappear {
                cleanState()
            }
        }
    }
    
    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Başlık boş bırakılamaz."
            showingErrorAlert = true
            return
        }
        
        if changePassword && newPassword.isEmpty {
            errorMessage = "Şifreyi değiştir seçeneği açıkken yeni şifre boş bırakılamaz."
            showingErrorAlert = true
            return
        }
        
        var updatedEntry = entry
        updatedEntry.title = trimmedTitle
        updatedEntry.username = username
        updatedEntry.website = website
        updatedEntry.notes = notes
        
        do {
            try viewModel.updateEntry(
                updatedEntry,
                newPassword: changePassword ? newPassword : nil
            )
            cleanStateAndDismiss()
        } catch {
            errorMessage = "Kayıt güncellenemedi: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func cleanState() {
        newPassword = ""
    }
    
    private func cleanStateAndDismiss() {
        cleanState()
        dismiss()
    }
}
