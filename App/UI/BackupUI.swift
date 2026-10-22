import SwiftUI
import UniformTypeIdentifiers

// Bestanden voor export en import in Instellingen, Gegevens (de pagina zelf staat in App/Pages/Settings/DataPage.swift).
//
// Keuze van bestandstype (zie ook App/Core/Export.swift):
// - JSON voor de volledige back-up: verliesvrij, leesbaar en met een versienummer. Dit kun je terugzetten.
// - CSV voor Numbers of Excel: platte tabellen, alleen exporteren.
// - Excel (.xlsx) en CSV importeren: je eigen begroting. De app herkent de onderdelen en deelt ze in bij inkomen,
//   uitgaven, spaarpotten en beleggingen (zie App/Core/ImportMapping.swift). Je ziet eerst een overzicht waarin je alles kunt
//   aanpassen (pagina `SettingsPage.importReview`); standaard wordt alleen iets toegevoegd en niets vervangen. Alleen als je
//   zelf kiest voor "Bestaande bijwerken" krijgen regels met een naam die al bestaat het nieuwe bedrag.
// Afgewezen: plist of de opslag van Core Data (niet draagbaar) en PDF (niet terug te zetten).
//
// Op de Mac heeft de app (sandbox) de rechten 'Door gebruiker geselecteerde bestanden' nodig om te mogen
// opslaan en openen (ENABLE_USER_SELECTED_FILES = readwrite in project.yml).

// MARK: - Bestandstypen

enum BackupFileTypes {
    /// Excel-werkmap (.xlsx). Het systeem kent dit type; zo niet, dan nemen we het type op extensie.
    static let xlsx: UTType = UTType("org.openxmlformats.spreadsheetml.sheet") ?? UTType(filenameExtension: "xlsx") ?? .data

    /// Wat de importknop mag openen: de JSON-back-up, Excel en CSV. Ook .xls, .ods en .numbers staan erbij,
    /// zodat je een duidelijke uitleg krijgt in plaats van een uitgegrijsd bestand.
    static var importable: [UTType] {
        var types: [UTType] = [.json, .commaSeparatedText, .tabSeparatedText, .plainText, xlsx]
        for ext in ["xlsx", "xlsm", "xls", "ods", "numbers", "csv"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
        }
        return types
    }
}

/// Leest een bestand dat de gebruiker heeft gekozen. Bestanden buiten de app (Bestanden, iCloud Drive, Finder) vragen
/// eerst om toegang; het coördineren zorgt dat een bestand uit iCloud eerst wordt gedownload.
/// Mag op een achtergrondtaak draaien.
enum BackupFileReader {
    static func read(_ url: URL, maxBytes: Int, tooLarge: Error) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        var coordinationError: NSError?
        var readError: Error?
        var fileData: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            do {
                if let size = try? readableURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
                    throw tooLarge
                }
                fileData = try Data(contentsOf: readableURL)
            } catch {
                readError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let result = fileData else { throw CocoaError(.fileReadUnknown) }
        return result
    }
}

/// Leest een spreadsheet en deelt de rijen in, buiten de hoofdtaak (grote bestanden houden de app niet tegen).
enum SpreadsheetLoader {
    static func load(url: URL, month: YearMonth) async -> Result<ImportDraft, Error> {
        let fileName = url.lastPathComponent
        return await Task.detached(priority: .userInitiated) { () -> Result<ImportDraft, Error> in
            do {
                let raw = try BackupFileReader.read(url, maxBytes: SpreadsheetReader.maxBytes, tooLarge: SpreadsheetError.tooLarge)
                let workbook = try SpreadsheetReader.read(raw, fileName: fileName)
                return .success(ImportMapper.draft(from: workbook, preferredMonth: month))
            } catch {
                return .failure(error)
            }
        }.value
    }
}

// MARK: - Bestand om te bewaren

/// Elk bestand dat de app exporteert, voor `fileExporter`: de JSON-back-up, een CSV-tabel (met BOM, zie `CSVExport.csvData`) en
/// het Excel-voorbeeldbestand. Eén documenttype betekent één `fileExporter` op de pagina Gegevens (twee exporters op een view
/// hinderen elkaar). `readableContentTypes` en `writableContentTypes` zijn statisch, dus beide lijsten bevatten alle drie de
/// typen; `fileExporter(contentType:)` kiest per export het juiste type uit die lijst.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, BackupFileTypes.xlsx] }
    static var writableContentTypes: [UTType] { [.json, .commaSeparatedText, BackupFileTypes.xlsx] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - CSV-rapporten

extension CSVReport {
    /// Een regel uitleg bij een CSV-export.
    var detail: String {
        switch self {
        case .monthly: return "Inkomen, uitgaven, sparen en wat je overhoudt per maand."
        case .transactions: return "Alle boekingen op je spaarpotten en bankrekening."
        case .holdings: return "Je beleggingen met waarde, inleg en rendement."
        }
    }

    var symbol: String {
        switch self {
        case .monthly: return "calendar"
        case .transactions: return "list.bullet.rectangle"
        case .holdings: return "chart.line.uptrend.xyaxis"
        }
    }
}
