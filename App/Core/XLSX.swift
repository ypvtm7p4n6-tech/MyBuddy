import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Spreadsheets lezen: werkmappen (.xlsx, .xlsm) en CSV, allebei als dezelfde tabelstructuur.
//
// Een werkmap is een ZIP (zie Zip.swift) met XML-bestanden: werkbladen, gedeelde teksten (sharedStrings) en
// stijlen (voor datum- en procentopmaak). We lezen de gecachte waarde van formules (<v>), nemen alle
// werkbladen mee en vullen samengevoegde cellen in. Fouten krijgen een Nederlandse melding.

// MARK: - Fouten

enum SpreadsheetError: Error, Equatable, LocalizedError {
    case oldXls
    case encrypted
    case numbers
    case ods
    case xlsb
    case notSpreadsheet
    case corrupt(String)
    case empty
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .oldXls:
            return "Dit is een ouder .xls-bestand. Sla het in Excel op als .xlsx of .csv en probeer opnieuw."
        case .encrypted:
            return "Dit bestand is met een wachtwoord beveiligd. Sla het zonder wachtwoord op als .xlsx of .csv en probeer opnieuw."
        case .numbers:
            return "Dit is een Numbers-bestand. Kies in Numbers Archief > Exporteer naar > Excel (of CSV) en probeer opnieuw."
        case .ods:
            return "Dit is een OpenDocument-bestand (.ods). Sla het in LibreOffice of Numbers op als .xlsx of .csv en probeer opnieuw."
        case .xlsb:
            return "Dit is een binair Excel-bestand (.xlsb). Sla het in Excel op als .xlsx of .csv en probeer opnieuw."
        case .notSpreadsheet:
            return "Dit bestand kon niet als spreadsheet worden gelezen. Kies een .xlsx- of .csv-bestand."
        case .corrupt(let detail):
            return "Het bestand is beschadigd en kon niet worden gelezen (\(detail)). Probeer het opnieuw uit je spreadsheetprogramma te exporteren."
        case .empty:
            return "Het bestand bevat geen gegevens."
        case .tooLarge:
            return "Het bestand is te groot om te importeren (meer dan 50 MB, of meer dan 2 miljoen gevulde cellen). Haal ongebruikte bladen of gegevens weg en probeer opnieuw."
        }
    }

    static func from(_ zip: ZipError) -> SpreadsheetError {
        switch zip {
        case .notAZip: return .notSpreadsheet
        case .encrypted: return .encrypted
        case .tooLarge: return .tooLarge
        case .corrupt(let detail): return .corrupt(detail)
        case .unsupportedMethod: return .corrupt("onbekende inpakmethode")
        }
    }
}

// MARK: - Tabel

/// Een kalenderdatum zonder tijd en zonder tijdzone (zoals Excel die opslaat).
struct SheetDate: Hashable {
    var year: Int
    var month: Int
    var day: Int

    /// "15-10-2026"
    var text: String {
        func pad(_ value: Int, _ width: Int) -> String {
            var s = String(value)
            while s.count < width { s = "0" + s }
            return s
        }
        return pad(day, 2) + "-" + pad(month, 2) + "-" + pad(year, 4)
    }

    /// Dagen sinds 1 januari 1970 (negatief ervoor).
    var daysSince1970: Int { SheetDate.daysFromCivil(year, month, day) }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(daysSince1970 days: Int) {
        let civil = SheetDate.civilFromDays(days)
        self.init(year: civil.year, month: civil.month, day: civil.day)
    }

    /// Excel-serienummer naar datum. Het tijdgedeelte (achter de komma) valt weg.
    /// Serienummer 61 is 1 maart 1900 (Excel telt ten onrechte een 29e februari 1900 mee).
    static func fromExcelSerial(_ serial: Double, date1904: Bool = false) -> SheetDate? {
        guard serial.isFinite, abs(serial) < 1e9 else { return nil }
        let whole = Int(serial.rounded(.down))
        if date1904 {
            guard whole >= 0, whole <= 2_958_465 else { return nil }
            return SheetDate(daysSince1970: whole + daysFromCivil(1904, 1, 1))
        }
        guard whole >= 1, whole <= 2_958_465 else { return nil }
        return SheetDate(daysSince1970: whole >= 61 ? whole - 25_569 : whole - 25_568)
    }

    /// Dagnummer vanaf 1970 voor een burgerlijke datum (algoritme van Howard Hinnant).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

/// De inhoud van één cel.
enum CellValue: Equatable {
    case empty
    case text(String)
    case number(Double)
    /// Een breuk: 21% is 0,21.
    case percent(Double)
    case bool(Bool)
    case date(SheetDate)

    /// Leeg, of alleen spaties.
    var isBlank: Bool {
        switch self {
        case .empty: return true
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }

    /// De tekst zonder spaties aan de randen, als de cel tekst is en niet leeg.
    var trimmedText: String? {
        guard case .text(let value) = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Het getal, als de cel een getal of percentage is.
    var numberValue: Double? {
        switch self {
        case .number(let value), .percent(let value): return value
        default: return nil
        }
    }

    /// Een leesbare tekst voor elke soort cel (voor kopjes en namen).
    var displayText: String {
        switch self {
        case .empty: return ""
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
            return CSVExport.decimal(value, maxDecimals: 4, minDecimals: 0)
        case .percent(let value): return CSVExport.decimal(value * 100, maxDecimals: 2, minDecimals: 0) + "%"
        case .bool(let value): return value ? "ja" : "nee"
        case .date(let date): return date.text
        }
    }
}

/// Eén werkblad (of één CSV-bestand) als rijen met cellen. Rij 0 is rij 1 in het bestand.
struct SpreadsheetTable: Equatable {
    var name: String
    var rows: [[CellValue]]
    var isHidden = false
    /// Het blad had meer rijen dan we lezen.
    var isTruncated = false

    func cell(_ row: Int, _ column: Int) -> CellValue {
        guard row >= 0, row < rows.count, column >= 0, column < rows[row].count else { return .empty }
        return rows[row][column]
    }

    var columnCount: Int { rows.reduce(0) { max($0, $1.count) } }

    /// Heeft minstens één gevulde cel.
    var hasContent: Bool { rows.contains { row in row.contains { !$0.isBlank } } }
}

struct SpreadsheetWorkbook: Equatable {
    var fileName: String
    var tables: [SpreadsheetTable]
    /// Aantal werkbladen dat niet is gelezen omdat het bestand er meer dan `XLSXReader.maxSheets` heeft.
    var skippedSheets = 0
}

// MARK: - Bestand herkennen en lezen

enum SpreadsheetReader {
    static let maxBytes = 50 * 1024 * 1024

    /// Leest een .xlsx, .xlsm of CSV-bestand. De bestandsnaam bepaalt mede wat we proberen;
    /// de inhoud bepaalt wat het echt is.
    static func read(_ data: Data, fileName: String) throws -> SpreadsheetWorkbook {
        guard data.count <= maxBytes else { throw SpreadsheetError.tooLarge }
        guard !data.isEmpty else { throw SpreadsheetError.empty }

        let ext = pathExtension(of: fileName)
        let head = [UInt8](data.prefix(8))
        let stem = baseName(of: fileName)

        // Oude Office-bestanden (OLE2): .xls, of een werkmap met wachtwoord.
        if head.count >= 8, head[0] == 0xD0, head[1] == 0xCF, head[2] == 0x11, head[3] == 0xE0,
           head[4] == 0xA1, head[5] == 0xB1, head[6] == 0x1A, head[7] == 0xE1 {
            if containsUTF16(data, "EncryptedPackage") { throw SpreadsheetError.encrypted }
            throw SpreadsheetError.oldXls
        }

        // ZIP: .xlsx/.xlsm, maar ook .ods, .numbers en andere pakketten.
        if head.count >= 4, head[0] == 0x50, head[1] == 0x4B, head[2] == 0x03 || head[2] == 0x05 {
            return try XLSXReader.read(data, fileName: fileName)
        }

        switch ext {
        case "numbers": throw SpreadsheetError.numbers
        case "ods": throw SpreadsheetError.ods
        case "xlsb": throw SpreadsheetError.xlsb
        case "xlsx", "xlsm", "xltx", "xltm":
            throw SpreadsheetError.corrupt("het is geen geldig Excel-bestand")
        default: break
        }

        // Tekst: CSV, TSV of een export die als .xls is bewaard.
        guard looksLikeText(data) else { throw SpreadsheetError.notSpreadsheet }
        let sample = [UInt8](data.prefix(256))
        if ext == "xls", sample.first == 0x3C {
            // HTML of XML met de naam .xls: geen tabel die we kunnen lezen.
            throw SpreadsheetError.oldXls
        }
        let table = try CSVReader.read(data, name: stem.isEmpty ? "Blad1" : stem)
        guard table.hasContent else { throw SpreadsheetError.empty }
        return SpreadsheetWorkbook(fileName: fileName, tables: [table])
    }

    /// "bestand.XLSX" wordt "xlsx".
    static func pathExtension(of fileName: String) -> String {
        let name = fileName.split(separator: "/").last.map(String.init) ?? fileName
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// "map/bestand.xlsx" wordt "bestand".
    static func baseName(of fileName: String) -> String {
        let name = fileName.split(separator: "/").last.map(String.init) ?? fileName
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// Geen NUL-bytes in het begin (behalve UTF-16 met BOM): dan is het waarschijnlijk tekst.
    static func looksLikeText(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(4_096))
        if head.count >= 2, (head[0] == 0xFF && head[1] == 0xFE) || (head[0] == 0xFE && head[1] == 0xFF) { return true }
        var controls = 0
        for byte in head {
            if byte == 0 { return false }
            if byte < 9 || (byte > 13 && byte < 32) { controls += 1 }
        }
        return controls * 20 < max(head.count, 1)
    }

    private static func containsUTF16(_ data: Data, _ text: String) -> Bool {
        var pattern: [UInt8] = []
        for unit in text.utf16 {
            pattern.append(UInt8(unit & 0xFF))
            pattern.append(UInt8(unit >> 8))
        }
        let bytes = [UInt8](data)
        guard bytes.count >= pattern.count else { return false }
        let last = bytes.count - pattern.count
        var i = 0
        while i <= last {
            if bytes[i] == pattern[0] {
                var match = true
                var j = 1
                while j < pattern.count {
                    if bytes[i + j] != pattern[j] { match = false; break }
                    j += 1
                }
                if match { return true }
            }
            i += 1
        }
        return false
    }
}

// MARK: - XLSX

/// De grenzen waarbinnen een werkmap gelezen wordt. De standaardwaarden staan in `XLSXReader`; tests gebruiken lagere om snel te
/// kunnen zien wat er gebeurt als een grens wordt overschreden.
struct XLSXLimits: Equatable {
    var maxSheets = XLSXReader.maxSheets
    var maxCells = XLSXReader.maxCells
    var maxVisited = XLSXReader.maxVisited
    var maxInflatedBytes = XLSXReader.maxInflatedBytes
}

enum XLSXReader {
    /// Meer rijen per blad lezen we niet.
    static let maxRows = 20_000
    static let maxColumns = 256
    /// Meer werkbladen lezen we niet; de rest wordt overgeslagen (`SpreadsheetWorkbook.skippedSheets`).
    /// Verwijzingen naar hetzelfde werkblad tellen als één blad.
    static let maxSheets = 50
    /// Hoeveel gevulde cellen we in totaal over alle bladen bewaren. Meer is `SpreadsheetError.tooLarge`.
    static let maxCells = 2_000_000
    /// Hoeveel cellen en rijen we in totaal doorlopen, ook lege met alleen een opmaak. Bij een gewoon bestand is dat ruim
    /// genoeg (20.000 rijen van 256 kolommen is 5 miljoen); daarboven is het bestand te groot.
    static let maxVisited = 6_000_000
    /// Langere teksten in een cel kappen we af; een naam, kopje of notitie is korter.
    static let maxTextLength = 500
    /// Hoeveel XML we in totaal uitpakken (alle onderdelen samen). Elk onderdeel heeft daarnaast zijn eigen grens in Zip.swift.
    static let maxInflatedBytes = 2 * Inflate.defaultLimit

    static func read(_ data: Data, fileName: String = "", limits: XLSXLimits = XLSXLimits()) throws -> SpreadsheetWorkbook {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch let error as ZipError {
            throw SpreadsheetError.from(error)
        }

        // Alles wat we uitpakken telt mee, zodat veel grote onderdelen samen ook begrensd zijn.
        var inflatedBytes = 0
        func part(_ name: String) throws -> Data? {
            do {
                guard let data = try archive.data(named: name) else { return nil }
                inflatedBytes += data.count
                if inflatedBytes > limits.maxInflatedBytes { throw SpreadsheetError.tooLarge }
                return data
            } catch let error as ZipError {
                throw SpreadsheetError.from(error)
            }
        }

        // Is dit wel een Excel-werkmap?
        let relsData = try part("_rels/.rels")
        var workbookPath = "xl/workbook.xml"
        if let relsData {
            let rels = RelationshipsParser.parse(relsData)
            if let main = rels.first(where: { $0.type.hasSuffix("/officeDocument") }) {
                workbookPath = resolve(main.target, relativeTo: "")
            }
        }
        // Binaire werkmappen (.xlsb) hebben een workbook.bin.
        if workbookPath.lowercased().hasSuffix(".bin") { throw SpreadsheetError.xlsb }
        guard let workbookData = try part(workbookPath) else {
            throw foreignFormat(archive)
        }

        let ext = SpreadsheetReader.pathExtension(of: fileName)
        if ext == "ods" { throw SpreadsheetError.ods }

        let book = WorkbookParser.parse(workbookData)
        guard !book.sheets.isEmpty else { throw SpreadsheetError.corrupt("geen werkbladen gevonden") }

        let directory = directoryOf(workbookPath)
        let workbookFile = String(workbookPath.dropFirst(directory.count))
        let relationships: [XLSXRelationship]
        if let data = try part(directory + "_rels/" + workbookFile + ".rels") {
            relationships = RelationshipsParser.parse(data)
        } else {
            relationships = []
        }

        // Gedeelde teksten en stijlen.
        var sharedStrings: [String] = []
        let sharedPath = relationships.first(where: { $0.type.hasSuffix("/sharedStrings") })
            .map { resolve($0.target, relativeTo: directory) } ?? (directory + "sharedStrings.xml")
        if let shared = try part(sharedPath) {
            let parsed = SharedStringsParser.parse(shared, maxStrings: limits.maxCells)
            if parsed.tooMany { throw SpreadsheetError.tooLarge }
            sharedStrings = parsed.strings
        }
        // De getrimde waarde van een gedeelde tekst rekenen we één keer uit, hoe vaak hij ook in het blad staat.
        let sharedTexts = SharedTextCache(strings: sharedStrings)
        var styles: [XLSXCellStyle] = []
        let stylesPath = relationships.first(where: { $0.type.hasSuffix("/styles") })
            .map { resolve($0.target, relativeTo: directory) } ?? (directory + "styles.xml")
        if let styleData = try part(stylesPath) {
            styles = StylesParser.parse(styleData)
        }

        var tables: [SpreadsheetTable] = []
        let budget = XLSXBudget(limits: limits)
        // Per pad van een werkblad: de plek in `tables`, of -1 als het onderdeel ontbreekt. Meerdere verwijzingen naar hetzelfde
        // werkblad lezen we één keer; anders kost een bestand met honderden verwijzingen honderden keren de leestijd.
        var seenPaths: [String: Int] = [:]
        var skippedSheets = 0
        // Opzoeken op id (bij dubbele id's geldt de eerste), zodat veel bladen bij veel relaties niet kwadratisch worden.
        let relationshipByID = Dictionary(relationships.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, sheet) in book.sheets.enumerated() {
            var target: String?
            if let relID = sheet.relationshipID, let rel = relationshipByID[relID] {
                // Grafiekbladen en dergelijke hebben geen cellen.
                guard rel.type.isEmpty || rel.type.hasSuffix("/worksheet") else { continue }
                target = resolve(rel.target, relativeTo: directory)
            } else {
                target = directory + "worksheets/sheet\(index + 1).xml"
            }
            guard let path = target else { continue }
            let key = path.lowercased()
            if let known = seenPaths[key] {
                // Hetzelfde werkblad onder een tweede naam: het blad is zichtbaar zodra één van de namen dat is.
                if known >= 0 { tables[known].isHidden = tables[known].isHidden && sheet.isHidden }
                continue
            }
            if tables.count >= limits.maxSheets {
                skippedSheets += 1
                continue
            }
            guard let sheetData = try part(path) else {
                seenPaths[key] = -1
                continue
            }
            seenPaths[key] = tables.count

            let parser = WorksheetParser(sharedTexts: sharedTexts, styles: styles, date1904: book.date1904, budget: budget)
            let parsed = parser.parse(sheetData)
            if budget.exceeded { throw SpreadsheetError.tooLarge }
            guard parsed else {
                throw SpreadsheetError.corrupt("werkblad '\(sheet.name)' is onleesbaar")
            }
            var table = parser.table(named: sheet.name)
            table.isHidden = sheet.isHidden
            tables.append(table)
        }

        guard !tables.isEmpty else { throw SpreadsheetError.corrupt("geen werkbladen gevonden") }
        // Verwijzingen voorbij `maxSheetElements` hebben we niet eens bekeken; ze tellen alleen mee als de bladen al vol zaten.
        if tables.count >= limits.maxSheets { skippedSheets += book.ignoredSheets }
        return SpreadsheetWorkbook(fileName: fileName, tables: tables, skippedSheets: skippedSheets)
    }

    /// Een ZIP zonder Excel-werkmap: wat is het dan?
    private static func foreignFormat(_ archive: ZipArchive) -> SpreadsheetError {
        if archive.contains("xl/workbook.bin") { return .xlsb }
        if archive.contains("content.xml"), archive.contains("mimetype") { return .ods }
        if archive.entries.contains(where: { $0.name.lowercased().hasSuffix(".iwa") || $0.name.hasPrefix("Index/") }) {
            return .numbers
        }
        return .notSpreadsheet
    }

    // MARK: Paden

    private static func directoryOf(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    /// Zet een doel uit een relatie om in een pad binnen de ZIP. "/xl/x.xml" is absoluut; de rest is relatief.
    static func resolve(_ target: String, relativeTo directory: String) -> String {
        var combined = target.hasPrefix("/") ? String(target.dropFirst()) : directory + target
        combined = combined.replacingOccurrences(of: "\\", with: "/")
        var parts: [String] = []
        for piece in combined.split(separator: "/", omittingEmptySubsequences: true) {
            if piece == "." { continue }
            if piece == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(String(piece))
        }
        return parts.joined(separator: "/")
    }
}

// MARK: - XML-hulpjes

private func localName(_ qualified: String) -> String {
    guard let colon = qualified.lastIndex(of: ":") else { return qualified }
    return String(qualified[qualified.index(after: colon)...])
}

private func attribute(_ attributes: [String: String], _ name: String) -> String? {
    if let direct = attributes[name] { return direct }
    for (key, value) in attributes where localName(key) == name { return value }
    return nil
}

/// Is dit tekst waar een XML-lezer veilig mee kan werken? Geldige UTF-8 zonder stuurtekens (of UTF-16 met BOM).
/// Beschadigde bestanden hebben vaak rommelbytes midden in een tag; sommige XML-lezers (zoals die op Linux)
/// lopen daarop vast, dus die weigeren we vooraf met een nette fout.
func isAcceptableXML(_ data: Data) -> Bool {
    let bytes = [UInt8](data)
    let count = bytes.count
    if count >= 2, (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) { return true }
    var i = (count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) ? 3 : 0
    while i < count {
        let b = bytes[i]
        if b < 0x80 {
            if b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D { return false }
            i += 1
            continue
        }
        var extra = 0
        var lowest: UInt8 = 0x80
        var highest: UInt8 = 0xBF
        switch b {
        case 0xC2...0xDF: extra = 1
        case 0xE0: extra = 2; lowest = 0xA0
        case 0xE1...0xEC, 0xEE...0xEF: extra = 2
        case 0xED: extra = 2; highest = 0x9F
        case 0xF0: extra = 3; lowest = 0x90
        case 0xF1...0xF3: extra = 3
        case 0xF4: extra = 3; highest = 0x8F
        default: return false
        }
        guard i + extra < count else { return false }
        let second = bytes[i + 1]
        guard second >= lowest, second <= highest else { return false }
        if extra >= 2 {
            for k in 2...extra where bytes[i + k] < 0x80 || bytes[i + k] > 0xBF { return false }
        }
        i += extra + 1
    }
    return true
}

private func parseXML(_ data: Data, delegate: XMLParserDelegate) -> Bool {
    guard isAcceptableXML(data) else { return false }
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    return parser.parse()
}

// MARK: - Relaties

struct XLSXRelationship: Equatable {
    var id: String
    var type: String
    var target: String
}

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    var items: [XLSXRelationship] = []

    static func parse(_ data: Data) -> [XLSXRelationship] {
        let handler = RelationshipsParser()
        _ = parseXML(data, delegate: handler)
        return handler.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard localName(elementName) == "Relationship" else { return }
        if attribute(attributeDict, "TargetMode") == "External" { return }
        items.append(XLSXRelationship(id: attribute(attributeDict, "Id") ?? "",
                                  type: attribute(attributeDict, "Type") ?? "",
                                  target: attribute(attributeDict, "Target") ?? ""))
    }
}

// MARK: - Werkmap

private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Sheet {
        var name: String
        var relationshipID: String?
        var isHidden: Bool
    }

    /// Meer `<sheet>`-elementen bewaren we niet (een gemaakt bestand kan er honderdduizenden hebben).
    static let maxSheetElements = 1_000

    var sheets: [Sheet] = []
    /// Aantal `<sheet>`-elementen boven `maxSheetElements`.
    var ignoredSheets = 0
    var date1904 = false

    static func parse(_ data: Data) -> WorkbookParser {
        let handler = WorkbookParser()
        _ = parseXML(data, delegate: handler)
        return handler
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "sheet":
            guard sheets.count < WorkbookParser.maxSheetElements else {
                ignoredSheets += 1
                return
            }
            let state = attribute(attributeDict, "state") ?? "visible"
            sheets.append(Sheet(name: attribute(attributeDict, "name") ?? "Blad \(sheets.count + 1)",
                                relationshipID: attribute(attributeDict, "id"),
                                isHidden: state == "hidden" || state == "veryHidden"))
        case "workbookPr":
            let flag = attribute(attributeDict, "date1904")?.lowercased()
            date1904 = flag == "1" || flag == "true"
        default:
            break
        }
    }
}

// MARK: - Gedeelde teksten

/// Tekst die we uit XML verzamelen, met een grens: een cel van een megabyte tekst hoeft niet in zijn geheel in het geheugen.
/// Genoeg bytes voor `XLSXReader.maxTextLength` tekens (hoogstens 4 bytes per teken); de rest laten we weg.
private struct TextBuffer {
    static let byteLimit = XLSXReader.maxTextLength * 4

    private(set) var text = ""
    private var bytes = 0

    mutating func reset() {
        text = ""
        bytes = 0
    }

    mutating func append(_ piece: String) {
        guard bytes < TextBuffer.byteLimit else { return }
        text += piece
        bytes += piece.utf8.count
    }

    /// De tekst, hoogstens `XLSXReader.maxTextLength` tekens.
    var capped: String { cappedCellText(text) }
}

/// Kapt een celtekst af op `XLSXReader.maxTextLength` tekens.
private func cappedCellText(_ text: String) -> String {
    text.count > XLSXReader.maxTextLength ? String(text.prefix(XLSXReader.maxTextLength)) : text
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    /// Er staan meer gedeelde teksten in dan we ooit in cellen kunnen gebruiken (`XLSXLimits.maxCells`).
    var tooMany = false
    private let maxStrings: Int
    private var current = TextBuffer()
    private var inItem = false
    private var collecting = false
    private var phoneticDepth = 0

    init(maxStrings: Int) {
        self.maxStrings = maxStrings
    }

    static func parse(_ data: Data, maxStrings: Int) -> (strings: [String], tooMany: Bool) {
        let handler = SharedStringsParser(maxStrings: maxStrings)
        _ = parseXML(data, delegate: handler)
        return (handler.strings, handler.tooMany)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "si":
            inItem = true
            current.reset()
        case "rPh":
            phoneticDepth += 1
        case "t":
            // Alleen de echte tekst, niet de uitspraakhulp (rPh) van Aziatische talen.
            collecting = inItem && phoneticDepth == 0
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { current.append(string) }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if collecting, let text = String(data: CDATABlock, encoding: .utf8) { current.append(text) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "t":
            collecting = false
        case "rPh":
            phoneticDepth = max(0, phoneticDepth - 1)
        case "si":
            if strings.count >= maxStrings {
                tooMany = true
                parser.abortParsing()
                return
            }
            strings.append(current.capped)
            inItem = false
        default:
            break
        }
    }
}

/// De gedeelde teksten als celwaarde. De getrimde waarde (en of de tekst leeg is) rekenen we één keer per tekst uit,
/// ook als duizenden cellen naar dezelfde tekst verwijzen.
private final class SharedTextCache {
    private let strings: [String]
    private var values: [CellValue?]

    init(strings: [String]) {
        self.strings = strings
        values = [CellValue?](repeating: nil, count: strings.count)
    }

    var count: Int { strings.count }

    /// De waarde van gedeelde tekst `index` (nil als die niet bestaat).
    func value(at index: Int) -> CellValue? {
        guard index >= 0, index < strings.count else { return nil }
        if let known = values[index] { return known }
        let made = WorksheetParser.textValue(strings[index])
        values[index] = made
        return made
    }
}

/// Wat we in één werkmap hoogstens doorlopen en bewaren, over alle werkbladen samen.
private final class XLSXBudget {
    private let limits: XLSXLimits
    private(set) var storedCells = 0
    private(set) var visited = 0
    private(set) var exceeded = false

    init(limits: XLSXLimits) {
        self.limits = limits
    }

    /// Telt een rij of cel die we doorlopen. False zodra het budget op is.
    func visit() -> Bool {
        visited += 1
        if visited > limits.maxVisited { exceeded = true }
        return !exceeded
    }

    /// Telt een gevulde cel die we bewaren. False zodra het budget op is.
    func store() -> Bool {
        storedCells += 1
        if storedCells > limits.maxCells { exceeded = true }
        return !exceeded
    }
}

// MARK: - Stijlen

struct XLSXCellStyle: Equatable {
    var isDate = false
    var isPercent = false
}

private final class StylesParser: NSObject, XMLParserDelegate {
    private var customFormats: [Int: String] = [:]
    private var formatIDs: [Int] = []
    private var inCellXfs = false

    static func parse(_ data: Data) -> [XLSXCellStyle] {
        let handler = StylesParser()
        _ = parseXML(data, delegate: handler)
        return handler.formatIDs.map { id in
            let code = handler.customFormats[id]
            return XLSXCellStyle(isDate: NumberFormatKind.isDate(id: id, code: code),
                             isPercent: NumberFormatKind.isPercent(id: id, code: code))
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "numFmt":
            if let idText = attribute(attributeDict, "numFmtId"), let id = Int(idText),
               let code = attribute(attributeDict, "formatCode") {
                customFormats[id] = code
            }
        case "cellXfs":
            inCellXfs = true
        case "xf":
            if inCellXfs {
                formatIDs.append(Int(attribute(attributeDict, "numFmtId") ?? "") ?? 0)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if localName(elementName) == "cellXfs" { inCellXfs = false }
    }
}

/// Wat voor getal een celopmaak (numFmt) is.
enum NumberFormatKind {
    /// Ingebouwde datumopmaken van Excel (zonder de formaten die alleen een tijd tonen).
    private static let builtInDates: Set<Int> = Set([14, 15, 16, 17, 22]).union(27...36).union(50...58)

    static func isDate(id: Int, code: String?) -> Bool {
        if let code { return codeHasDate(code) }
        return builtInDates.contains(id)
    }

    static func isPercent(id: Int, code: String?) -> Bool {
        if let code { return strippedFormat(code).contains("%") }
        return id == 9 || id == 10
    }

    /// Haalt tekst tussen aanhalingstekens, [kleuren en landinstellingen], _x en *x uit een opmaakcode.
    private static func strippedFormat(_ code: String) -> String {
        var result = ""
        var inQuotes = false
        var inBrackets = false
        var skipNext = false
        for ch in code {
            if skipNext { skipNext = false; continue }
            if inQuotes {
                if ch == "\"" { inQuotes = false }
                continue
            }
            if inBrackets {
                if ch == "]" { inBrackets = false }
                continue
            }
            switch ch {
            case "\"": inQuotes = true
            case "[": inBrackets = true
            case "\\", "_", "*": skipNext = true
            default: result.append(ch)
            }
        }
        return result.lowercased()
    }

    private static func codeHasDate(_ code: String) -> Bool {
        let stripped = strippedFormat(code)
        // Tekstopmaak met "General" of "@" bevat nooit een datum.
        if stripped.contains("y") || stripped.contains("d") { return true }
        // "m" kan minuten zijn (naast h of s) of maand.
        if stripped.contains("m"), !stripped.contains("h"), !stripped.contains("s") { return true }
        return false
    }
}

// MARK: - Werkblad

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedTexts: SharedTextCache
    private let styles: [XLSXCellStyle]
    private let date1904: Bool
    private let budget: XLSXBudget

    /// Hoeveel samengevoegde vakken we onthouden en hoeveel cellen we er in totaal voor invullen.
    private static let maxMerges = 20_000
    private static let maxMergeFill = 1_000_000

    private var cells: [(row: Int, column: Int, value: CellValue)] = []
    private var merges: [(firstRow: Int, firstColumn: Int, lastRow: Int, lastColumn: Int)] = []
    private var truncated = false
    /// We zijn doelbewust gestopt (te veel rijen, of het budget is op): dat is geen kapot bestand.
    private var stoppedOnPurpose = false
    private var activeParser: XMLParser?

    private var rowNumber = 0
    private var nextColumn = 0
    private var inCell = false
    private var cellRow = 0
    private var cellColumn = 0
    private var cellType = ""
    private var cellStyle = 0
    private var valueText = TextBuffer()
    private var inlineText = TextBuffer()
    private var collectingValue = false
    private var collectingInline = false
    private var inInlineString = false
    private var phoneticDepth = 0

    init(sharedTexts: SharedTextCache, styles: [XLSXCellStyle], date1904: Bool, budget: XLSXBudget) {
        self.sharedTexts = sharedTexts
        self.styles = styles
        self.date1904 = date1904
        self.budget = budget
    }

    func parse(_ data: Data) -> Bool {
        guard isAcceptableXML(data) else { return false }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        activeParser = parser
        let ok = parser.parse()
        activeParser = nil
        // Doelbewust gestopt, of een afgebroken bestand met al bruikbare cellen: laten we niet falen.
        return ok || stoppedOnPurpose || !cells.isEmpty
    }

    /// Stopt met lezen van dit blad.
    private func stop() {
        stoppedOnPurpose = true
        activeParser?.abortParsing()
    }

    // MARK: Delegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "row":
            guard budget.visit() else { return stop() }
            if let text = attribute(attributeDict, "r"), let number = Int(text) {
                rowNumber = number
            } else {
                rowNumber += 1
            }
            nextColumn = 0
        case "c":
            guard budget.visit() else { return stop() }
            inCell = true
            valueText.reset()
            inlineText.reset()
            cellType = attribute(attributeDict, "t") ?? ""
            cellStyle = Int(attribute(attributeDict, "s") ?? "") ?? 0
            cellRow = rowNumber
            cellColumn = nextColumn
            if let reference = attribute(attributeDict, "r"), let parsed = WorksheetParser.parseReference(reference) {
                cellColumn = parsed.column
                if let row = parsed.row { cellRow = row }
            }
            nextColumn = cellColumn + 1
            // Rijen staan in een gewoon bestand op volgorde: een cel voorbij de laatste rij die we lezen, betekent dat de rest ook
            // voorbij de grens ligt. Stoppen scheelt veel tijd bij bladen met honderdduizenden opgemaakte rijen.
            if cellRow - 1 >= XLSXReader.maxRows {
                truncated = true
                stop()
            }
        case "v":
            if inCell {
                collectingValue = true
                valueText.reset()
            }
        case "is":
            if inCell {
                inInlineString = true
                inlineText.reset()
            }
        case "rPh":
            phoneticDepth += 1
        case "t":
            collectingInline = inInlineString && phoneticDepth == 0
        case "mergeCell":
            if merges.count < WorksheetParser.maxMerges,
               let reference = attribute(attributeDict, "ref"), let range = WorksheetParser.parseRange(reference) {
                merges.append(range)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingValue {
            valueText.append(string)
        } else if collectingInline {
            inlineText.append(string)
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else { return }
        if collectingValue {
            valueText.append(text)
        } else if collectingInline {
            inlineText.append(text)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "v":
            collectingValue = false
        case "t":
            collectingInline = false
        case "rPh":
            phoneticDepth = max(0, phoneticDepth - 1)
        case "is":
            inInlineString = false
        case "c":
            finishCell()
            inCell = false
        default:
            break
        }
    }

    // MARK: Cellen

    private func finishCell() {
        let row = cellRow - 1
        guard row >= 0, cellColumn >= 0, cellColumn < XLSXReader.maxColumns else { return }
        guard row < XLSXReader.maxRows else {
            truncated = true
            return
        }
        let value = makeValue()
        if case .empty = value { return }
        guard budget.store() else { return stop() }
        cells.append((row: row, column: cellColumn, value: value))
    }

    private func makeValue() -> CellValue {
        let raw = WorksheetParser.trimmed(valueText.text)
        switch cellType {
        case "s":
            guard let index = Int(raw) else { return .empty }
            return sharedTexts.value(at: index) ?? .empty
        case "str":
            return WorksheetParser.textValue(valueText.text)
        case "inlineStr":
            return WorksheetParser.textValue(inlineText.text.isEmpty ? valueText.text : inlineText.text)
        case "b":
            return .bool(raw == "1" || raw.lowercased() == "true")
        case "e":
            // Foutwaarden zoals #DEEL/0! zijn geen gegevens.
            return .empty
        case "d":
            return WorksheetParser.parseISODate(raw).map { CellValue.date($0) } ?? WorksheetParser.textValue(raw)
        default:
            guard !raw.isEmpty else {
                return inlineText.text.isEmpty ? .empty : WorksheetParser.textValue(inlineText.text)
            }
            guard let number = Double(raw), number.isFinite else { return WorksheetParser.textValue(raw) }
            let style = cellStyle >= 0 && cellStyle < styles.count ? styles[cellStyle] : XLSXCellStyle()
            if style.isDate, let date = SheetDate.fromExcelSerial(number, date1904: date1904) {
                return .date(date)
            }
            if style.isPercent { return .percent(number) }
            return .number(number)
        }
    }

    /// Zoals `trimmingCharacters(in: .whitespacesAndNewlines)`, maar zonder Foundation als het begin en eind gewone tekens zijn
    /// (de meeste waarden zijn getallen). Staat er op een rand iets anders dan een ASCII-teken, dan beslist Foundation.
    private static func trimmed(_ text: String) -> String {
        let bytes = text.utf8
        guard let first = bytes.first, let last = bytes.last else { return text }
        func plain(_ byte: UInt8) -> Bool { byte > 32 && byte < 127 }
        return plain(first) && plain(last) ? text : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Een celtekst: leeg (of alleen spaties) is een lege cel, en langer dan `XLSXReader.maxTextLength` tekens wordt afgekapt.
    fileprivate static func textValue(_ text: String) -> CellValue {
        let capped = cappedCellText(text)
        return capped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .text(capped)
    }

    /// "2026-10-08" of "2026-10-08T00:00:00".
    private static func parseISODate(_ text: String) -> SheetDate? {
        let datePart = text.split(separator: "T", maxSplits: 1).first.map(String.init) ?? text
        let parts = datePart.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return SheetDate(year: parts[0], month: parts[1], day: parts[2])
    }

    // MARK: Verwijzingen

    /// "B5" naar (kolom 1, rij 5).
    static func parseReference(_ reference: String) -> (column: Int, row: Int?)? {
        var column = 0
        var row = 0
        var hasRow = false
        var rowOverflow = false
        var sawLetter = false
        for byte in reference.utf8 {
            switch byte {
            case 65...90, 97...122:
                // Letters horen voor de cijfers; hoofd- en kleine letters tellen gelijk (A en a zijn allebei 1).
                if hasRow { return nil }
                column = column * 26 + Int(byte & 0x1F)
                sawLetter = true
                if column > 1_000_000 { return nil }
            case 48...57:
                hasRow = true
                if !rowOverflow {
                    let multiplied = row.multipliedReportingOverflow(by: 10)
                    let added = multiplied.partialValue.addingReportingOverflow(Int(byte - 48))
                    if multiplied.overflow || added.overflow {
                        rowOverflow = true
                    } else {
                        row = added.partialValue
                    }
                }
            case 36:   // "$"
                continue
            default:
                return nil
            }
        }
        guard sawLetter, column > 0 else { return nil }
        // Een rijnummer dat niet in een Int past, lezen we als "geen rijnummer".
        let parsedRow: Int? = (hasRow && !rowOverflow) ? row : nil
        // Excel kent 1.048.576 rijen; alles daarboven is onzin of een poging om ons te laten vastlopen.
        if let parsedRow, parsedRow > 2_000_000 { return nil }
        return (column - 1, parsedRow)
    }

    static func parseRange(_ reference: String) -> (firstRow: Int, firstColumn: Int, lastRow: Int, lastColumn: Int)? {
        let pieces = reference.split(separator: ":").map(String.init)
        guard pieces.count == 2,
              let first = parseReference(pieces[0]), let last = parseReference(pieces[1]),
              let firstRow = first.row, let lastRow = last.row,
              // Rijen tellen vanaf 1; "A0" bestaat niet en zou hieronder een negatieve index geven.
              firstRow >= 1, lastRow >= 1 else { return nil }
        return (firstRow - 1, first.column, lastRow - 1, last.column)
    }

    // MARK: Tabel

    func table(named name: String) -> SpreadsheetTable {
        let rowCount = min((cells.map { $0.row }.max() ?? -1) + 1, XLSXReader.maxRows)
        var rows = [[CellValue]](repeating: [], count: max(rowCount, 0))
        for cell in cells where cell.row < rows.count {
            // Vul de kolommen ervoor aan met lege cellen; een cel op de volgende kolom komt er gewoon achter.
            while rows[cell.row].count < cell.column { rows[cell.row].append(.empty) }
            if rows[cell.row].count == cell.column {
                rows[cell.row].append(cell.value)
            } else {
                rows[cell.row][cell.column] = cell.value
            }
        }

        // Samengevoegde cellen: de waarde linksboven geldt voor het hele vak. In totaal vullen we er hoogstens
        // `maxMergeFill` in: een gemaakt bestand met tienduizenden grote vakken zou anders eindeloos duren.
        var mergeFill = 0
        for merge in merges {
            let height = merge.lastRow - merge.firstRow + 1
            let width = merge.lastColumn - merge.firstColumn + 1
            guard height > 0, width > 0, height * width <= 10_000, height * width > 1 else { continue }
            mergeFill += height * width
            if mergeFill > WorksheetParser.maxMergeFill { break }
            guard merge.firstRow >= 0, merge.firstColumn >= 0,
                  merge.firstRow < rows.count, merge.firstColumn < rows[merge.firstRow].count else { continue }
            let value = rows[merge.firstRow][merge.firstColumn]
            if case .empty = value { continue }
            for r in merge.firstRow...merge.lastRow where r < rows.count {
                for c in merge.firstColumn...merge.lastColumn where c < XLSXReader.maxColumns {
                    if r == merge.firstRow && c == merge.firstColumn { continue }
                    if rows[r].count <= c {
                        rows[r].append(contentsOf: [CellValue](repeating: .empty, count: c + 1 - rows[r].count))
                    }
                    if case .empty = rows[r][c] { rows[r][c] = value }
                }
            }
        }

        while let last = rows.last, last.allSatisfy({ $0.isBlank }) { rows.removeLast() }
        return SpreadsheetTable(name: name, rows: rows, isHidden: false, isTruncated: truncated)
    }
}

// MARK: - CSV

enum CSVReader {
    static func read(_ data: Data, name: String) throws -> SpreadsheetTable {
        let text = decode(data)
        var body = text
        var delimiter: Character? = nil

        // Excel kan de eerste regel "sep=;" gebruiken om het scheidingsteken te vertellen.
        if body.lowercased().hasPrefix("sep="), let newline = body.firstIndex(where: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = body[body.startIndex..<newline]
            if line.count == 5, let sep = line.last {
                delimiter = sep
                body = String(body[body.index(after: newline)...])
                if body.hasPrefix("\n") { body.removeFirst() }
            }
        }
        let separator = delimiter ?? detectDelimiter(body)

        let parsed = parse(body, delimiter: separator)
        var rows: [[CellValue]] = []
        var truncated = false
        for fields in parsed {
            if rows.count >= XLSXReader.maxRows {
                truncated = true
                break
            }
            var row: [CellValue] = []
            for field in fields.prefix(XLSXReader.maxColumns) {
                let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
                row.append(trimmed.isEmpty ? .empty : .text(trimmed))
            }
            while let last = row.last, case .empty = last { row.removeLast() }
            rows.append(row)
        }
        while let last = rows.last, last.isEmpty { rows.removeLast() }
        return SpreadsheetTable(name: name, rows: rows, isHidden: false, isTruncated: truncated)
    }

    // MARK: Tekst

    /// UTF-8 met of zonder BOM, UTF-16 met BOM, anders Windows-1252.
    static func decode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            return decodeUTF16(bytes, from: 2, littleEndian: true)
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return decodeUTF16(bytes, from: 2, littleEndian: false)
        }
        var start = 0
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { start = 3 }
        let slice = Array(bytes[start...])
        if let text = String(bytes: slice, encoding: .utf8) { return text }
        return decodeWindows1252(slice)
    }

    private static func decodeUTF16(_ bytes: [UInt8], from start: Int, littleEndian: Bool) -> String {
        var units: [UInt16] = []
        var i = start
        while i + 1 < bytes.count {
            let low = UInt16(bytes[littleEndian ? i : i + 1])
            let high = UInt16(bytes[littleEndian ? i + 1 : i])
            units.append(low | (high << 8))
            i += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Tekens 0x80...0x9F in Windows-1252; de rest is gelijk aan Latin-1.
    private static let windows1252: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
    ]

    static func decodeWindows1252(_ bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            let code: UInt32 = (byte >= 0x80 && byte <= 0x9F) ? windows1252[Int(byte) - 0x80] : UInt32(byte)
            if let scalar = Unicode.Scalar(code) { scalars.append(scalar) }
        }
        return String(scalars)
    }

    // MARK: Scheidingsteken

    private static let candidates: [Unicode.Scalar] = [";", "\t", ",", "|"]

    /// Kiest het scheidingsteken dat op de meeste regels evenveel keer voorkomt (buiten aanhalingstekens).
    static func detectDelimiter(_ text: String) -> Character {
        var counts: [Unicode.Scalar: [Int]] = [:]
        for candidate in candidates { counts[candidate] = [] }
        var current: [Unicode.Scalar: Int] = [:]
        var inQuotes = false
        var lines = 0
        var seenAnything = false
        var scanned = 0

        func endLine() {
            if seenAnything {
                for candidate in candidates { counts[candidate]?.append(current[candidate] ?? 0) }
                lines += 1
            }
            current = [:]
            seenAnything = false
        }

        for scalar in text.unicodeScalars {
            scanned += 1
            if scanned > 100_000 || lines >= 60 { break }
            if scalar == "\"" {
                inQuotes.toggle()
                seenAnything = true
                continue
            }
            if inQuotes { continue }
            if scalar == "\n" || scalar == "\r" {
                endLine()
                continue
            }
            if candidates.contains(scalar) { current[scalar, default: 0] += 1 }
            seenAnything = true
        }
        endLine()

        var best: Unicode.Scalar = ";"
        var bestScore = 0.0
        for candidate in candidates {
            let list = counts[candidate] ?? []
            let positives = list.filter { $0 > 0 }
            guard !positives.isEmpty else { continue }
            var frequency: [Int: Int] = [:]
            for value in positives { frequency[value, default: 0] += 1 }
            guard let mode = frequency.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }) else { continue }
            // Veel regels met hetzelfde aantal tellen zwaar; meer kolommen wint bij gelijke stand.
            let score = Double(mode.value) + Double(mode.key) * 0.001
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return Character(best)
    }

    // MARK: Splitsen

    /// Splitst CSV in rijen en velden: aanhalingstekens (""), regeleinden binnen aanhalingstekens, \r\n.
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        guard let separator = delimiter.unicodeScalars.first else { return [] }
        let scalars = Array(text.unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var fieldStarted = false
        var rowStarted = false

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            fieldStarted = false
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
            rowStarted = false
        }

        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            i += 1
            rowStarted = true
            if inQuotes {
                if scalar == "\"" {
                    if i < scalars.count, scalars[i] == "\"" {
                        field.append(scalar)
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
                continue
            }
            if scalar == "\"" && !fieldStarted {
                inQuotes = true
                fieldStarted = true
            } else if scalar == separator {
                endField()
            } else if scalar == "\n" || scalar == "\r" {
                if scalar == "\r", i < scalars.count, scalars[i] == "\n" { i += 1 }
                endRow()
            } else {
                field.append(scalar)
                fieldStarted = true
            }
        }
        if rowStarted || !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

// MARK: - Schrijven (voorbeeldbestand)

/// Een cel voor `XLSXWriter`.
enum XLSXWriteCell {
    case empty
    case text(String)
    /// Vetgedrukte kop met een kleurvlak.
    case header(String)
    case number(Double)
    /// Een bedrag met twee decimalen.
    case amount(Double)
}

struct XLSXWriteSheet {
    var name: String
    var rows: [[XLSXWriteCell]]
    /// Breedte per kolom in tekens (optioneel).
    var columnWidths: [Double] = []
}

/// Schrijft een eenvoudige .xlsx: tekst via sharedStrings, getallen, een kopstijl en een bedragstijl.
/// De onderdelen worden niet ingepakt (zie `ZipWriter`); Excel en Numbers openen dat zonder klachten.
enum XLSXWriter {
    static func data(sheets: [XLSXWriteSheet]) -> Data {
        var strings: [String] = []
        var stringIndex: [String: Int] = [:]
        func index(of text: String) -> Int {
            if let existing = stringIndex[text] { return existing }
            strings.append(text)
            stringIndex[text] = strings.count - 1
            return strings.count - 1
        }

        var files: [(name: String, data: Data)] = []
        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        let mainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let packageRelNS = "http://schemas.openxmlformats.org/package/2006/relationships"

        // Werkbladen
        var sheetParts: [(name: String, xml: String)] = []
        for sheet in sheets {
            var xml = header + "<worksheet xmlns=\"\(mainNS)\">"
            if !sheet.columnWidths.isEmpty {
                xml += "<cols>"
                for (i, width) in sheet.columnWidths.enumerated() {
                    xml += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
                }
                xml += "</cols>"
            }
            xml += "<sheetData>"
            for (r, row) in sheet.rows.enumerated() {
                xml += "<row r=\"\(r + 1)\">"
                for (c, cell) in row.enumerated() {
                    let ref = columnLetters(c) + String(r + 1)
                    switch cell {
                    case .empty:
                        break
                    case .text(let text):
                        xml += "<c r=\"\(ref)\" t=\"s\"><v>\(index(of: text))</v></c>"
                    case .header(let text):
                        xml += "<c r=\"\(ref)\" s=\"1\" t=\"s\"><v>\(index(of: text))</v></c>"
                    case .number(let value):
                        xml += "<c r=\"\(ref)\"><v>\(numberText(value))</v></c>"
                    case .amount(let value):
                        xml += "<c r=\"\(ref)\" s=\"2\"><v>\(numberText(value))</v></c>"
                    }
                }
                xml += "</row>"
            }
            xml += "</sheetData></worksheet>"
            sheetParts.append((name: sheet.name, xml: xml))
        }

        // Gedeelde teksten
        var shared = header + "<sst xmlns=\"\(mainNS)\" count=\"\(strings.count)\" uniqueCount=\"\(strings.count)\">"
        for text in strings {
            shared += "<si><t xml:space=\"preserve\">\(escape(text))</t></si>"
        }
        shared += "</sst>"

        // Pakketonderdelen
        var contentTypes = header + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        contentTypes += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        contentTypes += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        contentTypes += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        for i in 0..<sheetParts.count {
            contentTypes += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        contentTypes += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        contentTypes += "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>"
        contentTypes += "</Types>"

        let rootRels = header + "<Relationships xmlns=\"\(packageRelNS)\"><Relationship Id=\"rId1\" Type=\"\(relNS)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"

        var workbook = header + "<workbook xmlns=\"\(mainNS)\" xmlns:r=\"\(relNS)\"><sheets>"
        var workbookRels = header + "<Relationships xmlns=\"\(packageRelNS)\">"
        for (i, part) in sheetParts.enumerated() {
            workbook += "<sheet name=\"\(escape(sheetTitle(part.name)))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
            workbookRels += "<Relationship Id=\"rId\(i + 1)\" Type=\"\(relNS)/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
        }
        workbook += "</sheets></workbook>"
        workbookRels += "<Relationship Id=\"rId\(sheetParts.count + 1)\" Type=\"\(relNS)/styles\" Target=\"styles.xml\"/>"
        workbookRels += "<Relationship Id=\"rId\(sheetParts.count + 2)\" Type=\"\(relNS)/sharedStrings\" Target=\"sharedStrings.xml\"/>"
        workbookRels += "</Relationships>"

        let styles = header + "<styleSheet xmlns=\"\(mainNS)\">"
            + "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
            + "<fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill>"
            + "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FFD9E2B8\"/><bgColor indexed=\"64\"/></patternFill></fill></fills>"
            + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
            + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
            + "<cellXfs count=\"3\">"
            + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
            + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/>"
            + "<xf numFmtId=\"4\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
            + "</cellXfs>"
            + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
            + "</styleSheet>"

        files.append((name: "[Content_Types].xml", data: Data(contentTypes.utf8)))
        files.append((name: "_rels/.rels", data: Data(rootRels.utf8)))
        files.append((name: "xl/workbook.xml", data: Data(workbook.utf8)))
        files.append((name: "xl/_rels/workbook.xml.rels", data: Data(workbookRels.utf8)))
        for (i, part) in sheetParts.enumerated() {
            files.append((name: "xl/worksheets/sheet\(i + 1).xml", data: Data(part.xml.utf8)))
        }
        files.append((name: "xl/styles.xml", data: Data(styles.utf8)))
        files.append((name: "xl/sharedStrings.xml", data: Data(shared.utf8)))
        return ZipWriter.archive(files)
    }

    /// 0 wordt "A", 25 "Z", 26 "AA".
    static func columnLetters(_ index: Int) -> String {
        var number = index + 1
        var letters = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + remainder))) + letters
            number = (number - 1) / 26
        }
        return letters
    }

    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }

    /// Bladnamen zijn hooguit 31 tekens en mogen geen : \ / ? * [ ] bevatten.
    private static func sheetTitle(_ name: String) -> String {
        let forbidden: Set<Character> = [":", "\\", "/", "?", "*", "[", "]"]
        let cleaned = String(name.filter { !forbidden.contains($0) }.prefix(31))
        return cleaned.isEmpty ? "Blad" : cleaned
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default:
                // Stuurtekens (behalve tab en regeleinden) zijn niet toegestaan in XML 1.0.
                if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r" { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
