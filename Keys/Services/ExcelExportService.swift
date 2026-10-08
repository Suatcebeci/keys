import Foundation

/// Dışa aktarma veri modeli
public struct ExportItem {
    public let title: String
    public let username: String
    public let website: String
    public let password: String
    public let notes: String
    public let recordType: RecordType
    
    public init(
        title: String,
        username: String = "",
        website: String = "",
        password: String,
        notes: String = "",
        recordType: RecordType
    ) {
        self.title = title
        self.username = username
        self.website = website
        self.password = password
        self.notes = notes
        self.recordType = recordType
    }
}

/// Tamamen yerel, üçüncü taraf bağımlılık veya ağ bağlantısı içermeyen,
/// gerçek Open XML (.xlsx / PKZIP) formatında Excel dosyası üreten servis.
public final class ExcelExportService {
    public static let shared = ExcelExportService()
    
    public init() {}
    
    /// Verilen kayıtları gerçek iki çalışma sayfalı (Giriş Bilgileri & Banka Bilgileri)
    /// .xlsx dosya verisine (Data) dönüştürür.
    public func createXLSXData(items: [ExportItem]) -> Data {
        let loginItems = items.filter { $0.recordType == .login }
        let bankItems = items.filter { $0.recordType == .bank }
        
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
        
        let rootRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        
        let workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Giriş Bilgileri" sheetId="1" r:id="rId1"/>
            <sheet name="Banka Bilgileri" sheetId="2" r:id="rId2"/>
          </sheets>
        </workbook>
        """
        
        let workbookRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
        </Relationships>
        """
        
        let sheet1XML = buildLoginSheetXML(items: loginItems)
        let sheet2XML = buildBankSheetXML(items: bankItems)
        
        // PKZIP Arşivi oluştur
        var zip = MiniZipArchive()
        zip.addFile(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8))
        zip.addFile(path: "_rels/.rels", data: Data(rootRelsXML.utf8))
        zip.addFile(path: "xl/workbook.xml", data: Data(workbookXML.utf8))
        zip.addFile(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRelsXML.utf8))
        zip.addFile(path: "xl/worksheets/sheet1.xml", data: Data(sheet1XML.utf8))
        zip.addFile(path: "xl/worksheets/sheet2.xml", data: Data(sheet2XML.utf8))
        
        return zip.build()
    }
    
    // MARK: - Sheet 1: Giriş Bilgileri (Title, Username, Website, Password, Notes)
    private func buildLoginSheetXML(items: [ExportItem]) -> String {
        var rowsXML = ""
        
        // Başlık Satırı
        rowsXML += """
        <row r="1">
          <c r="A1" t="inlineStr"><is><t>Title</t></is></c>
          <c r="B1" t="inlineStr"><is><t>Username</t></is></c>
          <c r="C1" t="inlineStr"><is><t>Website</t></is></c>
          <c r="D1" t="inlineStr"><is><t>Password</t></is></c>
          <c r="E1" t="inlineStr"><is><t>Notes</t></is></c>
        </row>
        """
        
        for (index, item) in items.enumerated() {
            let rowNum = index + 2
            let title = sanitizeCellText(item.title)
            let username = sanitizeCellText(item.username)
            let website = sanitizeCellText(item.website)
            let password = sanitizeCellText(item.password)
            let notes = sanitizeCellText(item.notes)
            
            rowsXML += """
            <row r="\(rowNum)">
              <c r="A\(rowNum)" t="inlineStr"><is><t>\(title)</t></is></c>
              <c r="B\(rowNum)" t="inlineStr"><is><t>\(username)</t></is></c>
              <c r="C\(rowNum)" t="inlineStr"><is><t>\(website)</t></is></c>
              <c r="D\(rowNum)" t="inlineStr"><is><t>\(password)</t></is></c>
              <c r="E\(rowNum)" t="inlineStr"><is><t>\(notes)</t></is></c>
            </row>
            """
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            \(rowsXML)
          </sheetData>
        </worksheet>
        """
    }
    
    // MARK: - Sheet 2: Banka Bilgileri (Bank Name, Password)
    private func buildBankSheetXML(items: [ExportItem]) -> String {
        var rowsXML = ""
        
        // Başlık Satırı (Yalnızca Bank Name ve Password)
        rowsXML += """
        <row r="1">
          <c r="A1" t="inlineStr"><is><t>Bank Name</t></is></c>
          <c r="B1" t="inlineStr"><is><t>Password</t></is></c>
        </row>
        """
        
        for (index, item) in items.enumerated() {
            let rowNum = index + 2
            let bankName = sanitizeCellText(item.title)
            let password = sanitizeCellText(item.password)
            
            rowsXML += """
            <row r="\(rowNum)">
              <c r="A\(rowNum)" t="inlineStr"><is><t>\(bankName)</t></is></c>
              <c r="B\(rowNum)" t="inlineStr"><is><t>\(password)</t></is></c>
            </row>
            """
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            \(rowsXML)
          </sheetData>
        </worksheet>
        """
    }
    
    // MARK: - Güvenli Hücre Değeri & Formula Injection Koruması
    
    /// Kullanıcı tarafından girilen metinlerin Excel tarafından formül olarak yorumlanmasını engeller.
    /// Hücre değeri '=', '+', '-', '@', tab veya carriage return ile başlıyorsa,
    /// hücrenin çalıştırılabilir formül yerine yalnızca literal TEXT olarak algılanması için
    /// başa tek tırnak (') eklenir (OWASP / Spreadsheet Formula Injection koruması).
    public func sanitizeCellText(_ text: String) -> String {
        let formulaPrefixes: [Character] = ["=", "+", "-", "@", "\t", "\r"]
        var safeText = text
        if let firstChar = safeText.first, formulaPrefixes.contains(firstChar) {
            safeText = "'" + safeText
        }
        return escapeXML(safeText)
    }
    
    /// XML özel karakterlerini (&, <, >, ", ') standart Open XML uyumlu entity'lere dönüştürür.
    public func escapeXML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Saf Swift PKZIP (.zip) Arşiv Üreteci (Harici Bağımlılık İçermez)

private struct MiniZipEntry {
    let path: String
    let data: Data
    let crc32: UInt32
}

private struct MiniZipArchive {
    private var entries: [MiniZipEntry] = []
    
    mutating func addFile(path: String, data: Data) {
        let crc = CRC32.calculate(data)
        entries.append(MiniZipEntry(path: path, data: data, crc32: crc))
    }
    
    func build() -> Data {
        var localEntriesData = Data()
        var centralDirectoryData = Data()
        var offsets: [UInt32] = []
        
        for entry in entries {
            let pathData = Data(entry.path.utf8)
            let offset = UInt32(localEntriesData.count)
            offsets.append(offset)
            
            // 1. Local File Header
            localEntriesData.appendUInt32LE(0x04034b50) // Local file header signature
            localEntriesData.appendUInt16LE(20)         // Version needed: 2.0
            localEntriesData.appendUInt16LE(0)          // General purpose bit flag
            localEntriesData.appendUInt16LE(0)          // Compression method: 0 (Stored / Uncompressed)
            localEntriesData.appendUInt16LE(0)          // File mod time
            localEntriesData.appendUInt16LE(0)          // File mod date
            localEntriesData.appendUInt32LE(entry.crc32) // CRC-32
            localEntriesData.appendUInt32LE(UInt32(entry.data.count)) // Compressed size
            localEntriesData.appendUInt32LE(UInt32(entry.data.count)) // Uncompressed size
            localEntriesData.appendUInt16LE(UInt16(pathData.count))   // Filename length
            localEntriesData.appendUInt16LE(0)                        // Extra field length
            localEntriesData.append(pathData)
            localEntriesData.append(entry.data)
        }
        
        let cdOffset = UInt32(localEntriesData.count)
        
        // 2. Central Directory
        for (i, entry) in entries.enumerated() {
            let pathData = Data(entry.path.utf8)
            centralDirectoryData.appendUInt32LE(0x02014b50) // Central directory signature
            centralDirectoryData.appendUInt16LE(20)         // Version made by
            centralDirectoryData.appendUInt16LE(20)         // Version needed
            centralDirectoryData.appendUInt16LE(0)          // Flags
            centralDirectoryData.appendUInt16LE(0)          // Compression: 0
            centralDirectoryData.appendUInt16LE(0)          // Time
            centralDirectoryData.appendUInt16LE(0)          // Date
            centralDirectoryData.appendUInt32LE(entry.crc32) // CRC-32
            centralDirectoryData.appendUInt32LE(UInt32(entry.data.count)) // Compressed size
            centralDirectoryData.appendUInt32LE(UInt32(entry.data.count)) // Uncompressed size
            centralDirectoryData.appendUInt16LE(UInt16(pathData.count))   // Filename length
            centralDirectoryData.appendUInt16LE(0)          // Extra field length
            centralDirectoryData.appendUInt16LE(0)          // File comment length
            centralDirectoryData.appendUInt16LE(0)          // Disk number start
            centralDirectoryData.appendUInt16LE(0)          // Internal file attributes
            centralDirectoryData.appendUInt32LE(0)          // External file attributes
            centralDirectoryData.appendUInt32LE(offsets[i]) // Relative offset of local header
            centralDirectoryData.append(pathData)
        }
        
        let cdSize = UInt32(centralDirectoryData.count)
        
        // 3. End of Central Directory Record
        var eocdData = Data()
        eocdData.appendUInt32LE(0x06054b50) // EOCD signature
        eocdData.appendUInt16LE(0)          // Number of this disk
        eocdData.appendUInt16LE(0)          // Disk where central directory starts
        eocdData.appendUInt16LE(UInt16(entries.count)) // Records on this disk
        eocdData.appendUInt16LE(UInt16(entries.count)) // Total records
        eocdData.appendUInt32LE(cdSize)     // Size of central directory
        eocdData.appendUInt32LE(cdOffset)   // Offset of start of central directory
        eocdData.appendUInt16LE(0)          // Comment length
        
        var fullData = Data()
        fullData.append(localEntriesData)
        fullData.append(centralDirectoryData)
        fullData.append(eocdData)
        return fullData
    }
}

// MARK: - Standart CRC-32 Hesaplayıcı

private final class CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
    
    static func calculate(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Data Byte Append Yardımcıları

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { self.append(contentsOf: $0) }
    }
    
    mutating func appendUInt32LE(_ value: UInt32) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { self.append(contentsOf: $0) }
    }
}
