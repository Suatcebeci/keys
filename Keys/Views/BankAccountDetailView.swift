import SwiftUI

/// Banka kaydı detay ekranı.
/// Yalnızca Banka Adı ve Şifre görüntüler.
/// Doğrulanmış oturumu (LAContext) yeniden kullanarak ek biyometrik sormadan şifreyi gösterir ve kopyalar.
public struct BankAccountDetailView: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    let entry: PasswordEntry
    @Environment(\.dismiss) private var dismiss
    
    @State private var revealedPassword: String? = nil
    @State private var isPasswordRevealed: Bool = false
    @State private var isLoadingPassword: Bool = false
    @State private var isCopied: Bool = false
    
    @State private var showingEditSheet: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false
    
    public init(viewModel: PasswordVaultViewModel, entry: PasswordEntry) {
        self.viewModel = viewModel
        self.entry = entry
    }
    
    private var currentEntry: PasswordEntry {
        viewModel.entries.first(where: { $0.id == entry.id }) ?? entry
    }
    
    public var body: some View {
        List {
            // MARK: - Banka Adı
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentEntry.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Şifre Alanı
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Şifre")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if isPasswordRevealed, let secret = revealedPassword {
                            Text(secret)
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                                .textSelection(.enabled)
                                .accessibilityLabel("Banka Şifresi")
                                .accessibilityValue("Görünür")
                        } else {
                            Text("••••••••••••••••")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .accessibilityLabel("Banka Şifresi")
                                .accessibilityValue("Gizli")
                        }
                        
                        Spacer()
                        
                        // Göster / Gizle Butonu
                        Button {
                            togglePasswordVisibility()
                        } label: {
                            if isLoadingPassword {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: isPasswordRevealed ? "eye.slash.fill" : "eye.fill")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(isPasswordRevealed ? "Şifreyi Gizle" : "Şifreyi Göster")
                        
                        // Panoya Kopyala Butonu
                        Button {
                            copyPasswordToClipboard()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                if isCopied {
                                    Text("Kopyalandı")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .foregroundColor(isCopied ? .green : .accentColor)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Şifreyi Kopyala")
                    }
                }
                .padding(.vertical, 2)
            } footer: {
                Text("Kopyalanan şifre 45 saniye sonra panodan otomatik olarak silinir.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // MARK: - Kayıt Bilgileri
            Section {
                HStack {
                    Text("Oluşturulma")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currentEntry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundColor(.secondary)
                }
                .font(.footnote)
                
                HStack {
                    Text("Son Değiştirilme")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currentEntry.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundColor(.secondary)
                }
                .font(.footnote)
            }
            
            // MARK: - Silme Aksiyonu
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text("Kaydı Sil")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .frame(minHeight: 36)
                }
                .accessibilityLabel("Kaydı Sil")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentEntry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Düzenle") {
                    showingEditSheet = true
                }
                .fontWeight(.medium)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditBankAccountView(viewModel: viewModel, entry: currentEntry)
        }
        .confirmationDialog(
            "Bu banka kaydını silmek istediğinize emin misiniz?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                deleteRecord()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Banka kaydı ve ilişkili şifresi Keychain'den kalıcı olarak silinecektir.")
        }
        .alert("Hata", isPresented: $showingErrorAlert, actions: {
            Button("Tamam", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "İşlem sırasında bir hata oluştu.")
        })
    }
    
    // MARK: - Şifre Göster / Gizle (LAContext Reuse)
    private func togglePasswordVisibility() {
        if isPasswordRevealed {
            revealedPassword = nil
            isPasswordRevealed = false
        } else {
            isLoadingPassword = true
            do {
                let password = try viewModel.getPassword(for: currentEntry)
                revealedPassword = password
                isPasswordRevealed = true
            } catch {
                errorMessage = "Şifre çözülemedi. Lütfen kasanızı yeniden açın."
                showingErrorAlert = true
            }
            isLoadingPassword = false
        }
    }
    
    // MARK: - Şifreyi Panoya Kopyalama (localOnly: true, 45 sn)
    private func copyPasswordToClipboard() {
        do {
            let password = try viewModel.getPassword(for: currentEntry)
            ClipboardService.shared.copySensitiveText(password)
            withAnimation {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isCopied = false
                }
            }
        } catch {
            errorMessage = "Şifre kopyalanamadı."
            showingErrorAlert = true
        }
    }
    
    // MARK: - Kaydı Kalıcı Silme
    private func deleteRecord() {
        do {
            try viewModel.deleteEntry(currentEntry)
            dismiss()
        } catch {
            errorMessage = "Kayıt silinirken bir hata oluştu."
            showingErrorAlert = true
        }
    }
}
