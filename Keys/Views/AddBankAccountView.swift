import SwiftUI

/// Yeni banka kaydı ekleme ekranı.
/// Yalnızca iki alan içerir: Banka Adı (zorunlu) ve Banka Şifresi (zorunlu).
/// Başka hiçbir finansal alan (IBAN, kart no, CVV vb.) içermez.
public struct AddBankAccountView: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var bankName: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false
    
    public init(viewModel: PasswordVaultViewModel) {
        self.viewModel = viewModel
    }
    
    private var isFormValid: Bool {
        !bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Banka Adı (Örn: Akbank)", text: $bankName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Banka Bilgisi")
                }
                
                Section {
                    HStack {
                        if isPasswordVisible {
                            TextField("Şifre", text: $password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Şifre", text: $password)
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
                } header: {
                    Text("Şifre")
                }
            }
            .navigationTitle("Yeni Banka Kaydı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        cleanStateAndDismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        saveBankRecord()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
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
    
    private func saveBankRecord() {
        let trimmedName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Banka adı boş bırakılamaz."
            showingErrorAlert = true
            return
        }
        
        guard !password.isEmpty else {
            errorMessage = "Banka şifresi boş bırakılamaz."
            showingErrorAlert = true
            return
        }
        
        do {
            try viewModel.createBankEntry(bankName: trimmedName, password: password)
            cleanStateAndDismiss()
        } catch {
            errorMessage = "Banka kaydı Keychain'e kaydedilemedi: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func cleanState() {
        password = ""
    }
    
    private func cleanStateAndDismiss() {
        cleanState()
        dismiss()
    }
}
