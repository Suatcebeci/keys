import XCTest
@testable import Keys

@MainActor
final class ExcelExportTests: XCTestCase {
    
    let exportService = ExcelExportService.shared
    
    // MARK: - 1. Gerçek Open XML / PKZIP (.xlsx) Oluşturma Testi
    func testCreateRealXLSXFileFormat() {
        let items = [
            ExportItem(
                title: "Google",
                username: "user@gmail.com",
                website: "google.com",
                password: "GooglePassword123!",
                notes: "Kurtarma: 123",
                recordType: .login
            ),
            ExportItem(
                title: "Garanti BBVA",
                password: "BankSecret456#",
                recordType: .bank
            )
        ]
        
        let data = exportService.createXLSXData(items: items)
        
        XCTAssertFalse(data.isEmpty, "Oluşturulan XLSX verisi boş olamaz.")
        
        // PKZIP Başlık Doğrulaması: İlk 4 bayt PK\x03\x04 (0x50, 0x4B, 0x03, 0x04) olmalıdır
        XCTAssertTrue(data.count >= 4)
        XCTAssertEqual(data[0], 0x50, "PKZIP 'P' baytı")
        XCTAssertEqual(data[1], 0x4B, "PKZIP 'K' baytı")
        XCTAssertEqual(data[2], 0x03, "PKZIP 0x03 baytı")
        XCTAssertEqual(data[3], 0x04, "PKZIP 0x04 baytı")
        
        // Dosya içeriğinde Open XML standart parçaları bulunmalıdır
        let stringContent = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(stringContent.contains("[Content_Types].xml"), "XLSX [Content_Types].xml içermelidir.")
        XCTAssertTrue(stringContent.contains("_rels/.rels"), "XLSX _rels/.rels içermelidir.")
        XCTAssertTrue(stringContent.contains("xl/workbook.xml"), "XLSX xl/workbook.xml içermelidir.")
        XCTAssertTrue(stringContent.contains("xl/_rels/workbook.xml.rels"), "XLSX workbook.xml.rels içermelidir.")
        XCTAssertTrue(stringContent.contains("xl/worksheets/sheet1.xml"), "XLSX sheet1.xml içermelidir.")
        XCTAssertTrue(stringContent.contains("xl/worksheets/sheet2.xml"), "XLSX sheet2.xml içermelidir.")
    }
    
    // MARK: - 2. Çalışma Sayfaları ve Kolon Doğrulamaları
    func testWorksheetSeparationAndColumnValidation() {
        let items = [
            ExportItem(
                title: "GitHub",
                username: "octocat",
                website: "github.com",
                password: "GH_Password_999",
                notes: "Kişisel token yedekli",
                recordType: .login
            ),
            ExportItem(
                title: "İş Bankası",
                password: "IsBank_Secret_888",
                recordType: .bank
            )
        ]
        
        let data = exportService.createXLSXData(items: items)
        let content = String(decoding: data, as: UTF8.self)
        
        // 1. İki sayfanın isimleri workbook'ta bulunmalı
        XCTAssertTrue(content.contains("Giriş Bilgileri"), "Giriş Bilgileri çalışma sayfası mevcut olmalıdır.")
        XCTAssertTrue(content.contains("Banka Bilgileri"), "Banka Bilgileri çalışma sayfası mevcut olmalıdır.")
        
        // 2. Kolon isimleri doğrulaması
        XCTAssertTrue(content.contains("Title"), "Giriş sayfasında Title kolonu bulunmalıdır.")
        XCTAssertTrue(content.contains("Username"), "Giriş sayfasında Username kolonu bulunmalıdır.")
        XCTAssertTrue(content.contains("Website"), "Giriş sayfasında Website kolonu bulunmalıdır.")
        XCTAssertTrue(content.contains("Bank Name"), "Banka sayfasında Bank Name kolonu bulunmalıdır.")
        XCTAssertTrue(content.contains("Password"), "Her iki sayfada da Password kolonu bulunmalıdır.")
        XCTAssertTrue(content.contains("Notes"), "Giriş sayfasında Notes kolonu bulunmalıdır.")
        
        // 3. Veri ayrışması doğrulaması
        XCTAssertTrue(content.contains("GitHub"), "GitHub girişi yer almalıdır.")
        XCTAssertTrue(content.contains("octocat"), "octocat kullanıcı adı yer almalıdır.")
        XCTAssertTrue(content.contains("GH_Password_999"), "Giriş şifresi yer almalıdır.")
        XCTAssertTrue(content.contains("Kişisel token yedekli"), "Giriş notu yer almalıdır.")
        
        XCTAssertTrue(content.contains("İş Bankası"), "Banka adı yer almalıdır.")
        XCTAssertTrue(content.contains("IsBank_Secret_888"), "Banka şifresi yer almalıdır.")
        
        // 4. Kategori kesinlikle bulunmamalı
        XCTAssertFalse(content.contains("category"), "Kategori alanı kesinlikle dışa aktarılmamalıdır.")
        XCTAssertFalse(content.contains("VaultCategory"), "VaultCategory bulunmamalıdır.")
    }
    
    // MARK: - 3. XML Escaping Güvenlik Testi
    func testXMLEscapingSpecialCharacters() {
        let items = [
            ExportItem(
                title: "Garanti & BBVA <Finans>",
                username: "user\"name\" 'admin'",
                website: "https://example.com?a=1&b=2",
                password: "P&<\"'>assword123",
                notes: "Not & < > \" '",
                recordType: .login
            ),
            ExportItem(
                title: "Banka & 'Kredi' <A.Ş.>",
                password: "Bank&<\"'>Secret",
                recordType: .bank
            )
        ]
        
        let data = exportService.createXLSXData(items: items)
        let xmlContent = String(decoding: data, as: UTF8.self)
        
        // XML içinde ham & < > " ' karakterleri düzensiz şekilde bulunmamalı, entity formatında olmalıdır
        XCTAssertTrue(xmlContent.contains("Garanti &amp; BBVA &lt;Finans&gt;"), "Title XML entity olarak encode edilmelidir.")
        XCTAssertTrue(xmlContent.contains("user&quot;name&quot; &apos;admin&apos;"), "Username XML entity olarak encode edilmelidir.")
        XCTAssertTrue(xmlContent.contains("https://example.com?a=1&amp;b=2"), "Website XML entity olarak encode edilmelidir.")
        XCTAssertTrue(xmlContent.contains("P&amp;&lt;&quot;&apos;&gt;assword123"), "Password XML entity olarak encode edilmelidir.")
        XCTAssertTrue(xmlContent.contains("Banka &amp; &apos;Kredi&apos; &lt;A.Ş.&gt;"), "Banka adı XML entity olarak encode edilmelidir.")
        XCTAssertTrue(xmlContent.contains("Bank&amp;&lt;&quot;&apos;&gt;Secret"), "Banka şifresi XML entity olarak encode edilmelidir.")
    }
    
    // MARK: - 4. Excel Formula Injection Koruması Testi
    func testExcelFormulaInjectionProtection() {
        let items = [
            ExportItem(
                title: "=HYPERLINK(\"http://evil.com\",\"Click\")",
                username: "+1234567890",
                website: "-malicious-command",
                password: "=SUM(A1:A10)",
                notes: "@username_mention",
                recordType: .login
            ),
            ExportItem(
                title: "=CMD|' /C calc'!A0",
                password: "+BankPassword123",
                recordType: .bank
            )
        ]
        
        let data = exportService.createXLSXData(items: items)
        let xmlContent = String(decoding: data, as: UTF8.self)
        
        // Formül tetikleyici karakterler (=, +, -, @) ile başlayan değerler tek tırnakla kaçırılmalıdır
        // XML entity olarak tek tırnak &apos; şeklinde encode edilir.
        XCTAssertTrue(xmlContent.contains("&apos;=HYPERLINK"), "= ile başlayan başlık &apos; ile kaçırılmalıdır.")
        XCTAssertTrue(xmlContent.contains("&apos;+1234567890"), "+ ile başlayan kullanıcı adı &apos; ile kaçırılmalıdır.")
        XCTAssertTrue(xmlContent.contains("&apos;-malicious-command"), "- ile başlayan website &apos; ile kaçırılmalıdır.")
        XCTAssertTrue(xmlContent.contains("&apos;=SUM(A1:A10)"), "= ile başlayan şifre &apos; ile kaçırılmalıdır.")
        XCTAssertTrue(xmlContent.contains("&apos;@username_mention"), "@ ile başlayan not &apos; ile kaçırılmalıdır.")
        XCTAssertTrue(xmlContent.contains("&apos;=CMD|"), "= ile başlayan banka adı &apos; ile kaçırılmalıdır.")
        XCTAssertTrue(xmlContent.contains("&apos;+BankPassword123"), "+ ile başlayan banka şifresi &apos; ile kaçırılmalıdır.")
    }
    
    // MARK: - 5. Türkçe Karakter Bütünlüğü Testi
    func testTurkishCharactersPreservation() {
        let items = [
            ExportItem(
                title: "İş Bankası",
                username: "kullanıcı_çalışma",
                website: "https://örnek.com",
                password: "Şifre_ğüşıöç_ĞÜŞİÖÇ_123!",
                notes: "Şifre notu: ğüşıöç",
                recordType: .login
            ),
            ExportItem(
                title: "Türkiye İş Bankası",
                password: "Şifre_Banka_ÇĞİÖŞÜ_999",
                recordType: .bank
            )
        ]
        
        let data = exportService.createXLSXData(items: items)
        let xmlContent = String(decoding: data, as: UTF8.self)
        
        XCTAssertTrue(xmlContent.contains("İş Bankası"), "İş Bankası Türkçe karakterleri korunmalıdır.")
        XCTAssertTrue(xmlContent.contains("kullanıcı_çalışma"), "Türkçe kullanıcı adı korunmalıdır.")
        XCTAssertTrue(xmlContent.contains("https://örnek.com"), "Türkçe URL korunmalıdır.")
        XCTAssertTrue(xmlContent.contains("Şifre_ğüşıöç_ĞÜŞİÖÇ_123!"), "Türkçe şifre karakterleri bozulmamalıdır.")
        XCTAssertTrue(xmlContent.contains("Şifre notu: ğüşıöç"), "Türkçe not karakterleri bozulmamalıdır.")
        XCTAssertTrue(xmlContent.contains("Türkiye İş Bankası"), "Türkiye İş Bankası banka adı korunmalıdır.")
        XCTAssertTrue(xmlContent.contains("Şifre_Banka_ÇĞİÖŞÜ_999"), "Banka şifresindeki Türkçe karakterler korunmalıdır.")
    }
    
    // MARK: - 6. Boş Kasa Export Testi
    func testEmptyVaultExport() {
        let items: [ExportItem] = []
        let data = exportService.createXLSXData(items: items)
        
        XCTAssertFalse(data.isEmpty, "Boş kasa export edildiğinde de geçerli bir XLSX arşivi üretilmelidir.")
        let xmlContent = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(xmlContent.contains("Giriş Bilgileri"))
        XCTAssertTrue(xmlContent.contains("Banka Bilgileri"))
        XCTAssertTrue(xmlContent.contains("Title"))
        XCTAssertTrue(xmlContent.contains("Bank Name"))
    }
    
    // MARK: - 7. Çok Sayıda Kayıt (100+ Entry) Performans ve Kararlılık Testi
    func testLargeNumberOfEntriesExport() {
        var items: [ExportItem] = []
        for i in 1...150 {
            if i % 2 == 0 {
                items.append(ExportItem(
                    title: "Banka \(i)",
                    password: "BankSecret\(i)*#",
                    recordType: .bank
                ))
            } else {
                items.append(ExportItem(
                    title: "Site \(i)",
                    username: "user\(i)@mail.com",
                    website: "https://site\(i).org",
                    password: "Password\(i)!$",
                    notes: "Not \(i)",
                    recordType: .login
                ))
            }
        }
        
        let data = exportService.createXLSXData(items: items)
        XCTAssertTrue(data.count > 1000, "150 kayıt içeren arşiv geçerli boyutta üretilmelidir.")
        
        let xmlContent = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(xmlContent.contains("Site 149"))
        XCTAssertTrue(xmlContent.contains("Banka 150"))
    }
    
    // MARK: - 8. Kasa Kilitliyken Export Engeli Testi
    func testExportBlockedWhenVaultIsLocked() async {
        let keychainService = KeychainService()
        let viewModel = PasswordVaultViewModel(keychainService: keychainService)
        viewModel.isUnlocked = false
        
        do {
            _ = try await viewModel.exportAllEntriesToXLSX()
            XCTFail("Kasa kilitliyken export işlemi hata fırlatmalıdır!")
        } catch {
            XCTAssertTrue(true, "Kilitli kasada export engellendi.")
        }
    }
    
    // MARK: - 9. Export Cleanup Testi
    func testExportCleanupRemovesTemporaryFiles() {
        let viewModel = PasswordVaultViewModel()
        let tempDir = FileManager.default.temporaryDirectory
        let dummyExportFile = tempDir.appendingPathComponent("Keys-Export.xlsx")
        
        // Geçici bir dosya oluştur
        try? "dummy content".data(using: .utf8)?.write(to: dummyExportFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dummyExportFile.path))
        
        // cleanExportFiles çağrıldığında dosya silinmelidir
        viewModel.cleanExportFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dummyExportFile.path), "cleanExportFiles geçici dışa aktarma dosyasını silmelidir.")
        
        // lockVault çağrıldığında da geçici dosyaların silindiğini doğrula
        try? "dummy content 2".data(using: .utf8)?.write(to: dummyExportFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dummyExportFile.path))
        viewModel.lockVault()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dummyExportFile.path), "lockVault geçici export dosyalarını silmelidir.")
    }
}
