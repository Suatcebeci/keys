import SwiftUI
import UniformTypeIdentifiers

/// Minimal, hızlı ve güvenli ana ekran.
/// Ana ekran bir özet/dashboard ekranıdır; kayıt isimleri yalnızca kategori içine girildiğinde gösterilir.
/// "Hesaplar" altında aynı başlığa sahip kayıtlar başlıklarına göre gruplanarak listelenir.
public struct HomeView: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    
    // Sheet Durumları
    @State private var showingAddLoginSheet: Bool = false
    @State private var showingAddBankSheet: Bool = false
    @State private var entryToDelete: PasswordEntry? = nil
    @State private var showingDeleteAlert: Bool = false
    @State private var copiedNoticeText: String? = nil
    
    // Dışa Aktarma (Export - XLSX) Durumları
    @State private var showingExportWarning: Bool = false
    @State private var exportFileURL: URL? = nil
    @State private var isExporting: Bool = false
    
    // Keys Şifreli Yedekleme (Backup & Restore) Durumları
    @State private var showingCreateBackupSheet: Bool = false
    @State private var backupFileURL: URL? = nil
    @State private var showingFilePicker: Bool = false
    @State private var selectedImportURL: URL? = nil
    @State private var showingImportPasswordSheet: Bool = false
    @State private var pendingImportPayload: BackupPayload? = nil
    @State private var showingImportConfirmDialog: Bool = false
    
    public init(viewModel: PasswordVaultViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            mainBodyContent
                .navigationTitle("Keys")
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: $viewModel.searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Ara..."
                )
                .toolbar {
                    toolbarItems
                }
                .navigationDestination(for: RecordFilter.self) { filter in
                    if filter == .banks {
                        banksCategoryView
                    } else {
                        accountsCategoryView
                    }
                }
                .navigationDestination(for: AccountGroup.self) { group in
                    groupEntriesListView(group: group)
                }
                .navigationDestination(for: PasswordEntry.self) { entry in
                    detailViewFor(entry: entry)
                }
        }
        // Hesap Ekleme Sayfası
        .sheet(isPresented: $showingAddLoginSheet) {
            AddPasswordView(viewModel: viewModel)
        }
        // Banka Ekleme Sayfası
        .sheet(isPresented: $showingAddBankSheet) {
            AddBankAccountView(viewModel: viewModel)
        }
        // XLSX Paylaşım Sayfası (Native Share Sheet)
        .sheet(item: Binding<ExportURLWrapper?>(
            get: { exportFileURL.map { ExportURLWrapper(url: $0) } },
            set: { wrapper in
                if wrapper == nil {
                    viewModel.cleanExportFiles()
                }
                exportFileURL = wrapper?.url
            }
        )) { wrapper in
            ShareSheet(fileURL: wrapper.url) {
                viewModel.cleanExportFiles()
                exportFileURL = nil
            }
        }
        // Silme Onay Penceresi
        .confirmationDialog(
            "Kaydı silmek istediğinize emin misiniz?",
            isPresented: $showingDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let entry = entryToDelete {
                    try? viewModel.deleteEntry(entry)
                    entryToDelete = nil
                }
            }
            Button("Vazgeç", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            Text("Bu kayıt ve şifresi Keychain'den kalıcı olarak silinecektir.")
        }
        // Export Güvenlik Uyarısı ve Onayı
        .confirmationDialog(
            "Şifreleri Dışa Aktar",
            isPresented: $showingExportWarning,
            titleVisibility: .visible
        ) {
            Button("Face ID ile Devam Et") {
                startExportFlow()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Tüm hesap ve banka şifreleriniz Excel dosyasına aktarılacaktır.\nBu dosya Keys'in Keychain koruması dışında olacaktır.\nDosyayı güvenli bir yerde saklayın.")
        }
        // Keys Şifreli Yedek (.keysbackup) Paylaşım Sayfası
        .sheet(item: Binding<ExportURLWrapper?>(
            get: { backupFileURL.map { ExportURLWrapper(url: $0) } },
            set: { wrapper in
                if wrapper == nil {
                    viewModel.cleanBackupFiles()
                }
                backupFileURL = wrapper?.url
            }
        )) { wrapper in
            ShareSheet(fileURL: wrapper.url) {
                viewModel.cleanBackupFiles()
                backupFileURL = nil
            }
        }
        // Keys Yedeği Oluşturma Sayfası
        .sheet(isPresented: $showingCreateBackupSheet) {
            CreateBackupSheet(viewModel: viewModel) { generatedURL in
                self.backupFileURL = generatedURL
            }
        }
        // Yedek Dosyası Seçici (File Picker)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                handleSelectedImportFile(url)
            case .failure(let error):
                showTemporaryNotice("Dosya seçilemedi: \(error.localizedDescription)")
            }
        }
        // Yedek Parolası Giriş Sayfası
        .sheet(isPresented: $showingImportPasswordSheet, onDismiss: {
            cleanupSelectedImportFile()
        }) {
            if let importURL = selectedImportURL {
                ImportPasswordSheet(
                    fileURL: importURL,
                    viewModel: viewModel
                ) { payload in
                    self.pendingImportPayload = payload
                    self.showingImportConfirmDialog = true
                }
            }
        }
        // Yedek İçe Aktarma Onay Penceresi
        .confirmationDialog(
            "Yedeği İçe Aktar",
            isPresented: $showingImportConfirmDialog,
            titleVisibility: .visible
        ) {
            Button("İçe Aktar") {
                if let payload = pendingImportPayload {
                    do {
                        let result = try viewModel.restoreBackup(payload: payload)
                        showTemporaryNotice("Yedek içe aktarıldı (\(result.restoredCount) yeni, \(result.updatedCount) güncellendi)")
                    } catch {
                        showTemporaryNotice("İçe aktarma başarısız: \(error.localizedDescription)")
                    }
                    pendingImportPayload = nil
                    cleanupSelectedImportFile()
                }
            }
            Button("Vazgeç", role: .cancel) {
                pendingImportPayload = nil
                cleanupSelectedImportFile()
            }
        } message: {
            if let payload = pendingImportPayload {
                let logins = payload.entries.filter { $0.recordType == .login }.count
                let banks = payload.entries.filter { $0.recordType == .bank }.count
                Text("Yedekte \(logins) hesap ve \(banks) banka kaydı bulundu.\nMevcut kasanıza eklenecektir.")
            } else {
                Text("Yedek kayıtları mevcut kasanıza eklenecektir.")
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = copiedNoticeText {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Ana İçerik Yönlendirici (Arama vs Dashboard)
    @ViewBuilder
    private var mainBodyContent: some View {
        if isSearching {
            // Arama yapılıyorsa sonuçları listele
            searchResultsView
        } else {
            // Arama yoksa Özet / Dashboard görünümü
            dashboardView
        }
    }
    
    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Dashboard / Özet Ekranı
    /// GÜVENLİK KURALI: Bu ekranda hiçbir kayıt adı, kullanıcı adı veya banka detayı GÖRÜNMEZ.
    /// Yalnızca Toplam Şifre, Hesaplar ve Bankalar sayıları dinamik olarak listelenir.
    private var dashboardView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Üst Kategori Kısayolları (Hesaplar & Bankalar)
                HStack(spacing: 12) {
                    NavigationLink(value: RecordFilter.logins) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.accentColor)
                            Text("Hesaplar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Hesaplar kategorisini aç")
                    
                    NavigationLink(value: RecordFilter.banks) {
                        HStack(spacing: 8) {
                            Image(systemName: "building.columns.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.accentColor)
                            Text("Bankalar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Bankalar kategorisini aç")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // 1. Toplam Şifre Kartı
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Toplam Şifre")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: "shield.checkered")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    
                    Text("\(viewModel.totalCount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
                
                // 2. Hesaplar Kartı
                NavigationLink(value: RecordFilter.logins) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: "key.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hesaplar")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Gruplanmış hesap şifreleri")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(viewModel.loginCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .accessibilityLabel("Hesaplar, \(viewModel.loginCount) kayıt")
                
                // 3. Bankalar Kartı
                NavigationLink(value: RecordFilter.banks) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: "building.columns.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bankalar")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Banka ve finans şifreleri")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(viewModel.bankCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .accessibilityLabel("Bankalar, \(viewModel.bankCount) kayıt")
                
                // Kasa tamamen boşsa yönlendirici açıklama
                if viewModel.entries.isEmpty {
                    VStack(spacing: 8) {
                        Text("Kasanızda henüz kayıt yok")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                        
                        Button {
                            showingAddLoginSheet = true
                        } label: {
                            Label("İlk Şifreni Ekle", systemImage: "plus")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.top, 12)
                }
                
                // Versiyon Bilgisi (Sade, küçük ve dinamik)
                VStack(spacing: 2) {
                    Text("Keys")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                    Text(viewModel.appVersion)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Hesaplar Kategori Görünümü (Başlıklara Göre Gruplanmış)
    /// Kullanıcı "Hesaplar"a bastığında başlıklarına göre gruplanmış liste açılır.
    /// Örn: Google (3), Apple (1).
    @ViewBuilder
    private var accountsCategoryView: some View {
        let groups = viewModel.accountGroups
        
        Group {
            if groups.isEmpty {
                emptyAccountsView
            } else {
                List {
                    ForEach(groups) { group in
                        NavigationLink(value: group) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                                
                                Text(group.displayTitle)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text("\(group.count)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Hesaplar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddLoginSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Hesap Ekle")
            }
        }
    }
    
    // MARK: - Grup Detay Listesi (Örn. "Google" Başlığındaki Tüm Hesaplar)
    /// Belirli bir başlığa ait tüm bağımsız hesap kayıtları burada listelenir.
    @ViewBuilder
    private func groupEntriesListView(group: AccountGroup) -> some View {
        let entries = viewModel.entries(forGroup: group)
        
        Group {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bu grupta kayıt kalmadı")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
            } else {
                List {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.username.isEmpty ? "(Kullanıcı adı yok)" : entry.username)
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(entry.username.isEmpty ? .secondary : .primary)
                                        .lineLimit(1)
                                    
                                    if !entry.website.isEmpty {
                                        Text(entry.website)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entryToDelete = entry
                                showingDeleteAlert = true
                            } label: {
                                Label("Sil", systemImage: "trash.fill")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                copyPasswordDirectly(entry: entry)
                            } label: {
                                Label("Şifre", systemImage: "key.fill")
                            }
                            .tint(.accentColor)
                            
                            if !entry.username.isEmpty {
                                Button {
                                    ClipboardService.shared.copySensitiveText(entry.username)
                                    showTemporaryNotice("Kullanıcı adı kopyalandı")
                                } label: {
                                    Label("Kullanıcı", systemImage: "person.fill")
                                }
                                .tint(.secondary)
                            }
                        }
                        .contextMenu {
                            if !entry.username.isEmpty {
                                Button {
                                    ClipboardService.shared.copySensitiveText(entry.username)
                                    showTemporaryNotice("Kullanıcı Adını Kopyala")
                                } label: {
                                    Label("Kullanıcı Adını Kopyala", systemImage: "person.crop.circle")
                                }
                            }
                            
                            Button {
                                copyPasswordDirectly(entry: entry)
                            } label: {
                                Label("Şifreyi Kopyala", systemImage: "key.fill")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                entryToDelete = entry
                                showingDeleteAlert = true
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(group.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddLoginSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Bu Gruba Hesap Ekle")
            }
        }
    }
    
    // MARK: - Bankalar Kategori Görünümü
    /// Bankalar gruplanmaz, doğrudan kayıt bazında listelenir.
    @ViewBuilder
    private var banksCategoryView: some View {
        let entries = viewModel.entries(for: .banks)
        
        Group {
            if entries.isEmpty {
                emptyBanksView
            } else {
                List {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            entryRow(entry)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entryToDelete = entry
                                showingDeleteAlert = true
                            } label: {
                                Label("Sil", systemImage: "trash.fill")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                copyPasswordDirectly(entry: entry)
                            } label: {
                                Label("Şifre", systemImage: "key.fill")
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button {
                                copyPasswordDirectly(entry: entry)
                            } label: {
                                Label("Şifreyi Kopyala", systemImage: "key.fill")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                entryToDelete = entry
                                showingDeleteAlert = true
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Bankalar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddBankSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Banka Ekle")
            }
        }
    }
    
    // MARK: - Boş Hesaplar Ekranı
    private var emptyAccountsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "key")
                .font(.system(size: 52, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                Text("Hesap Bulunmuyor")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                
                Text("Bu kategoride henüz kayıtlı bir hesap yok.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button {
                showingAddLoginSheet = true
            } label: {
                Label("Hesap Ekle", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Boş Bankalar Ekranı
    private var emptyBanksView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "building.columns")
                .font(.system(size: 52, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                Text("Banka Bulunmuyor")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                
                Text("Bu kategoride henüz kayıtlı bir banka şifresi yok.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button {
                showingAddBankSheet = true
            } label: {
                Label("Banka Ekle", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Arama Sonuçları Görünümü
    /// Arama durumunda hem eşleşen gruplar hem de bankalar gösterilir.
    @ViewBuilder
    private var searchResultsView: some View {
        let matchingGroups = viewModel.filteredAccountGroups(query: viewModel.searchText)
        let matchingBanks = viewModel.filteredBankEntries(query: viewModel.searchText)
        
        if matchingGroups.isEmpty && matchingBanks.isEmpty {
            noSearchResultsView
        } else {
            List {
                if !matchingGroups.isEmpty {
                    Section("Hesaplar") {
                        ForEach(matchingGroups) { group in
                            NavigationLink(value: group) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.12))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "key.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.accentColor)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.displayTitle)
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.primary)
                                        
                                        // Eşleşen kullanıcı adı varsa göster
                                        let matchedEntries = group.entries.filter { $0.matches(query: viewModel.searchText) }
                                        if let firstMatch = matchedEntries.first(where: { !$0.username.isEmpty }) {
                                            Text(firstMatch.username)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(group.count)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                                }
                            }
                        }
                    }
                }
                
                if !matchingBanks.isEmpty {
                    Section("Bankalar") {
                        ForEach(matchingBanks) { entry in
                            NavigationLink(value: entry) {
                                entryRow(entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    entryToDelete = entry
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Sil", systemImage: "trash.fill")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    copyPasswordDirectly(entry: entry)
                                } label: {
                                    Label("Şifre", systemImage: "key.fill")
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    
    // MARK: - Tekil Kayıt Satırı
    private func entryRow(_ entry: PasswordEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if entry.recordType == .bank {
                    Text("Banka Hesabı")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if !entry.website.isEmpty {
                    Text(entry.website)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if entry.recordType == .bank {
                Image(systemName: "building.columns")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Arama Sonucu Bulunamadı
    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary)
            
            Text("Sonuç Bulunamadı")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("\"\(viewModel.searchText)\" ile eşleşen bir kayıt veya grup yok.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Kayıt Tipine Göre Detay Ekranı
    @ViewBuilder
    private func detailViewFor(entry: PasswordEntry) -> some View {
        if entry.recordType == .bank {
            BankAccountDetailView(viewModel: viewModel, entry: entry)
        } else {
            PasswordDetailView(viewModel: viewModel, entry: entry)
        }
    }
    
    // MARK: - Toolbar Butonları (Kilitle, Dışa Aktar & Ekle Menüsü)
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                viewModel.lockVault()
            } label: {
                Label("Kilitle", systemImage: "lock.fill")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.secondary)
            .accessibilityLabel("Kasayı Kilitle")
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                // Yedekleme & Raporlama Menüsü
                Menu {
                    Button {
                        showingCreateBackupSheet = true
                    } label: {
                        Label("Keys Yedeği Oluştur", systemImage: "lock.shield.fill")
                    }
                    .disabled(viewModel.entries.isEmpty)
                    
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Yedeği İçe Aktar", systemImage: "square.and.arrow.down")
                    }
                    
                    Divider()
                    
                    Button {
                        showingExportWarning = true
                    } label: {
                        Label("Excel (XLSX) Raporu", systemImage: "tablecells")
                    }
                    .disabled(viewModel.entries.isEmpty || isExporting)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .medium))
                }
                .accessibilityLabel("Yedekleme ve Raporlama Menüsü")
                
                // Yeni Kayıt Menüsü (+ Butonu)
                Menu {
                    Button {
                        showingAddLoginSheet = true
                    } label: {
                        Label("Hesap Bilgisi", systemImage: "key.fill")
                    }
                    
                    Button {
                        showingAddBankSheet = true
                    } label: {
                        Label("Banka Bilgisi", systemImage: "building.columns.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Yeni Kayıt Ekle")
            }
        }
    }
    
    // MARK: - Yardımcı Fonksiyonlar
    private func copyPasswordDirectly(entry: PasswordEntry) {
        do {
            let password = try viewModel.getPassword(for: entry)
            ClipboardService.shared.copySensitiveText(password)
            showTemporaryNotice("Şifre panoya kopyalandı (45 sn)")
        } catch {
            showTemporaryNotice("Şifre kopyalanamadı")
        }
    }
    
    private func startExportFlow() {
        guard !isExporting else { return }
        isExporting = true
        
        Task {
            do {
                let url = try await viewModel.exportAllEntriesToXLSX()
                exportFileURL = url
            } catch {
                viewModel.cleanExportFiles()
                showTemporaryNotice("Dışa aktarma başarısız oldu")
            }
            isExporting = false
        }
    }
    
    private func handleSelectedImportFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            showTemporaryNotice("Yedek dosyasına erişilemedi")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            guard BackupService.shared.verifyBackupHeader(data) else {
                showTemporaryNotice("Geçersiz dosya: Keys yedek biçimi tanınamadı")
                return
            }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).keysbackup")
            try data.write(to: tempURL, options: .atomic)
            self.selectedImportURL = tempURL
            self.showingImportPasswordSheet = true
        } catch {
            showTemporaryNotice("Dosya okunamadı: \(error.localizedDescription)")
        }
    }
    
    private func cleanupSelectedImportFile() {
        if let tempURL = selectedImportURL {
            try? FileManager.default.removeItem(at: tempURL)
            selectedImportURL = nil
        }
    }
    
    private func showTemporaryNotice(_ text: String) {
        withAnimation {
            copiedNoticeText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedNoticeText == text { copiedNoticeText = nil }
            }
        }
    }
}

// MARK: - URL Wrapper for Sheet Binding
private struct ExportURLWrapper: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Keys Yedeği Oluşturma Sayfası
private struct CreateBackupSheet: View {
    @ObservedObject var viewModel: PasswordVaultViewModel
    let onBackupCreated: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    
    private var isPasswordValid: Bool {
        password.count >= 12
    }
    
    private var doPasswordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    private var canCreate: Bool {
        isPasswordValid && doPasswordsMatch && !isProcessing
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Güvenlik Uyarısı")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Bu dosya kasanızdaki şifreleri içerir.\nYedeği güvenli bir yerde saklayın.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Yedek Parolası Belirleyin"), footer: validationFooter) {
                    SecureField("Yedek Parolası (En az 12 karakter)", text: $password)
                        .textContentType(.newPassword)
                    
                    SecureField("Parolayı Doğrulayın", text: $confirmPassword)
                        .textContentType(.newPassword)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button {
                        createBackupAction()
                    } label: {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Şifreli Yedek Oluştur")
                                .font(.headline)
                                .foregroundColor(canCreate ? .white : Color(uiColor: .tertiaryLabel))
                            Spacer()
                        }
                    }
                    .disabled(!canCreate)
                    .listRowBackground(canCreate ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                }
            }
            .navigationTitle("Keys Yedeği Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var validationFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !password.isEmpty && !isPasswordValid {
                Text("• Parola en az 12 karakter olmalıdır (\(password.count)/12)")
                    .foregroundColor(.orange)
            }
            if !confirmPassword.isEmpty && !doPasswordsMatch {
                Text("• Parolalar birbiriyle eşleşmiyor")
                    .foregroundColor(.red)
            } else if doPasswordsMatch && isPasswordValid {
                Text("✓ Parola gereksinimleri karşılandı")
                    .foregroundColor(.green)
            }
            Text("Parolanızı unutursanız yedeği geri yükleyemezsiniz.")
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
    
    private func createBackupAction() {
        guard canCreate else { return }
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let url = try await viewModel.createBackup(password: password)
                dismiss()
                onBackupCreated(url)
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Yedek Parolası Giriş Sayfası
private struct ImportPasswordSheet: View {
    let fileURL: URL
    @ObservedObject var viewModel: PasswordVaultViewModel
    let onDecrypted: (BackupPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var password = ""
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Yedek Doğrulama")
                                .font(.headline)
                            Text("Seçilen Keys yedeğinin şifresini çözmek için yedeği oluştururken kullandığınız parolayı girin.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Yedek Parolası")) {
                    SecureField("Parolayı Girin", text: $password)
                        .textContentType(.password)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button {
                        inspectAction()
                    } label: {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Yedeği Çöz ve İncele")
                                .font(.headline)
                                .foregroundColor(password.isEmpty || isProcessing ? Color(uiColor: .tertiaryLabel) : .white)
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || isProcessing)
                    .listRowBackground(password.isEmpty || isProcessing ? Color(uiColor: .secondarySystemFill) : Color.accentColor)
                }
            }
            .navigationTitle("Yedeği İçe Aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func inspectAction() {
        guard !password.isEmpty && !isProcessing else { return }
        isProcessing = true
        errorMessage = nil
        
        do {
            let payload = try viewModel.inspectBackup(from: fileURL, password: password)
            dismiss()
            onDecrypted(payload)
        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
        }
    }
}
