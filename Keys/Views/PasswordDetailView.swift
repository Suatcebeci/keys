import SwiftUI

/// Sade, zarif ve Apple standartlarında şifre detay ekranı.
/// Şifre varsayılan olarak maskeli tutulur ve doğrulanmış LAContext oturumu yeniden kullanılarak görüntülenir.
public struct PasswordDetailView: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    let entry: PasswordEntry
    @Environment(\.dismiss) private var dismiss
    
    @State private var revealedPassword: String? = nil
    @State private var isPasswordRevealed: Bool = false
    @State private var isLoadingPassword: Bool = false
    
    // Kopyalama geri bildirim durumları
    @State private var copiedField: String? = nil
    
    // Düzenleme ve Silme Sheet / Dialog durumları
    @State private var showingEditSheet: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false
    
    public init(viewModel: PasswordVaultViewModel, entry: PasswordEntry) {
        self.viewModel = viewModel
        self.entry = entry
    }
    
    // Güncel kaydı ViewModel'deki listeden al (Düzenleme yapıldıysa ekrana anında yansıması için)
    private var currentEntry: PasswordEntry {
        viewModel.entries.first(where: { $0.id == entry.id }) ?? entry
    }
    
    public var body: some View {
        List {
            // MARK: - Başlık Başlığı
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentEntry.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Kullanıcı Adı
            if !currentEntry.username.isEmpty {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kullanıcı Adı")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(currentEntry.username)
                                .font(.body.weight(.medium))
                                .textSelection(.enabled)
                        }
                        Spacer()
                        copyButton(text: currentEntry.username, fieldKey: "username", accessibilityName: "Kullanıcı Adını Kopyala")
                    }
                    .padding(.vertical, 2)
                }
            }
            
            // MARK: - Web Sitesi
            if !currentEntry.website.isEmpty {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Web Sitesi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(currentEntry.website)
                                .font(.body)
                                .foregroundColor(.accentColor)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        copyButton(text: currentEntry.website, fieldKey: "website", accessibilityName: "Web Sitesini Kopyala")
                    }
                    .padding(.vertical, 2)
                }
            }
            
            // MARK: - Şifre Alanı (Maskeli & Göster / Kopyala)
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
                                .accessibilityLabel("Şifre")
                                .accessibilityValue("Görünür")
                        } else {
                            Text("••••••••••••••••")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .accessibilityLabel("Şifre")
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
                        
                        // Şifreyi Panoya Kopyala Butonu
                        Button {
                            copyPasswordToClipboard()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedField == "password" ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                if copiedField == "password" {
                                    Text("Kopyalandı")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .foregroundColor(copiedField == "password" ? .green : .accentColor)
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
            
            // MARK: - Gizli Notlar
            if !currentEntry.notes.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notlar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(currentEntry.notes)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 2)
                }
            }
            
            // MARK: - Zaman Damgaları
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
            EditPasswordView(viewModel: viewModel, entry: currentEntry)
        }
        .confirmationDialog(
            "Bu kaydı silmek istediğinize emin misiniz?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                deleteRecord()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kayıt ve ilişkili Keychain şifresi kalıcı olarak silinecektir.")
        }
        .alert("Hata", isPresented: $showingErrorAlert, actions: {
            Button("Tamam", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "İşlem sırasında bir hata oluştu.")
        })
    }
    
    // MARK: - Yardımcı Kopyalama Butonu
    private func copyButton(text: String, fieldKey: String, accessibilityName: String) -> some View {
        Button {
            ClipboardService.shared.copySensitiveText(text)
            withAnimation {
                copiedField = fieldKey
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    if copiedField == fieldKey { copiedField = nil }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copiedField == fieldKey ? "checkmark.circle.fill" : "doc.on.doc.fill")
                if copiedField == fieldKey {
                    Text("Kopyalandı")
                        .font(.caption2.weight(.bold))
                }
            }
            .foregroundColor(copiedField == fieldKey ? .green : .accentColor)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityName)
    }
    
    // MARK: - Şifre Göster / Gizle Mantığı (LAContext Reuse)
    private func togglePasswordVisibility() {
        if isPasswordRevealed {
            // Tekrar gizle ve RAM'den sil
            revealedPassword = nil
            isPasswordRevealed = false
        } else {
            // Keychain'den doğrulanmış oturum ile (ek biyometri sormadan) çek
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
    
    // MARK: - Şifreyi Panoya Kopyalama
    private func copyPasswordToClipboard() {
        do {
            let password = try viewModel.getPassword(for: currentEntry)
            ClipboardService.shared.copySensitiveText(password)
            withAnimation {
                copiedField = "password"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    if copiedField == "password" { copiedField = nil }
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
