import SwiftUI

/// Mevcut banka kaydını düzenleme ekranı.
/// Banka adı ve şifre değiştirilebilir.
/// Şifre değiştirilmemişse Keychain'deki gizli anahtar gereksiz yere yeniden yazılmaz.
public struct EditBankAccountView: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    let entry: PasswordEntry
    @Environment(\.dismiss) private var dismiss
    
    @State private var bankName: String
    @State private var changePassword: Bool = false
    @State private var newPassword: String = ""
    @State private var isPasswordVisible: Bool = false
    
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false
    
    public init(viewModel: PasswordVaultViewModel, entry: PasswordEntry) {
        self.viewModel = viewModel
        self.entry = entry
        _bankName = State(initialValue: entry.title)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Banka Adı", text: $bankName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Banka Bilgisi")
                }
                
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
            }
            .navigationTitle("Banka Kaydını Düzenle")
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
                    .disabled(bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (changePassword && newPassword.isEmpty))
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
        let trimmedName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Banka adı boş bırakılamaz."
            showingErrorAlert = true
            return
        }
        
        if changePassword && newPassword.isEmpty {
            errorMessage = "Şifreyi değiştir seçeneği açıkken yeni şifre boş bırakılamaz."
            showingErrorAlert = true
            return
        }
        
        do {
            try viewModel.updateBankEntry(
                entry,
                bankName: trimmedName,
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
