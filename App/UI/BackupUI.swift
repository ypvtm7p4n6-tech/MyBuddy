import SwiftUI
import UniformTypeIdentifiers

// Export en import in de instellingen.
//
// Keuze van bestandstype (zie ook App/Core/Export.swift):
// - JSON voor de volledige back-up: verliesvrij, leesbaar en met een versienummer. Dit kun je terugzetten.
// - CSV voor Numbers of Excel: platte tabellen, alleen exporteren.
// Afgewezen: plist of de opslag van Core Data (niet draagbaar) en PDF (niet terug te zetten).
//
// Op de Mac heeft de app (sandbox) de rechten 'Door gebruiker geselecteerde bestanden' nodig om te mogen
// opslaan en openen (ENABLE_USER_SELECTED_FILES = readwrite in project.yml).

// MARK: - Bestanden

/// De JSON-back-up als bestand, voor `fileExporter`.
struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

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

/// Een CSV-tabel als bestand, voor `fileExporter`. `data` is de CSV met BOM (zie `CSVExport.csvData`).
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

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

// MARK: - Meldingen

/// Eén melding tegelijk: de bevestiging voor het terugzetten, of een uitkomst. Eén `.alert` voor alles,
/// want meerdere alerts op dezelfde view overschrijven elkaar.
private enum BackupAlert {
    case confirmImport(BackupContents)
    case message(title: String, text: String)

    var title: String {
        switch self {
        case .confirmImport: return "Back-up terugzetten?"
        case .message(let title, _): return title
        }
    }
}

private extension CSVReport {
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

// MARK: - Rij

private struct BackupRowLabel: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sectie voor in Instellingen

/// Secties voor een Form (Instellingen): back-up exporteren en importeren (JSON) en cijfers exporteren (CSV).
/// Levert Sections terug, dus nooit in een ScrollView zetten.
struct BackupSection: View {
    @Environment(AppStore.self) private var store

    @State private var jsonDocument: JSONBackupDocument?
    @State private var jsonFileName = ""
    @State private var showJSONExporter = false

    @State private var csvDocument: CSVDocument?
    @State private var csvFileName = ""
    @State private var showCSVExporter = false

    @State private var showImporter = false

    @State private var activeAlert: BackupAlert?
    @State private var showAlert = false

    // De presentaties hangen elk aan een eigen rij: twee `fileExporter`s, of een exporter en een importer,
    // op dezelfde view hinderen elkaar.
    var body: some View {
        Section {
            Button {
                prepareJSONExport()
            } label: {
                BackupRowLabel(title: "Back-up exporteren (JSON)",
                               detail: "Alles wat je hebt ingevuld, om later terug te zetten.",
                               symbol: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .fileExporter(isPresented: $showJSONExporter,
                          document: jsonDocument,
                          contentType: .json,
                          defaultFilename: jsonFileName,
                          onCompletion: { result in handleExport(result) })

            Button {
                showImporter = true
            } label: {
                BackupRowLabel(title: "Back-up importeren",
                               detail: "Vervangt je huidige gegevens door een eerder gemaakte back-up.",
                               symbol: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json],
                          onCompletion: { result in handleImport(result) })
        } header: {
            Text("Back-up")
        } footer: {
            Text("JSON is de volledige back-up: alles blijft behouden en je kunt hem hier weer importeren. Ook een kaal finance.json werkt. Een back-up bevat al je persoonlijke gegevens. Bewaar hem op een veilige plek en deel hem niet zomaar.")
        }

        Section {
            csvButton(.monthly)
                .fileExporter(isPresented: $showCSVExporter,
                              document: csvDocument,
                              contentType: .commaSeparatedText,
                              defaultFilename: csvFileName,
                              onCompletion: { result in handleExport(result) })

            csvButton(.transactions)
                .alert(activeAlert?.title ?? "", isPresented: $showAlert, presenting: activeAlert) { alert in
                    alertActions(alert)
                } message: { alert in
                    Text(alertMessage(alert))
                }

            csvButton(.holdings)
        } header: {
            Text("Cijfers exporteren (CSV)")
        } footer: {
            Text("CSV is voor spreadsheets zoals Numbers en Excel. Het bevat alleen cijfers, met een puntkomma tussen de kolommen en een komma als decimaalteken. CSV kun je niet terugzetten: gebruik daarvoor de JSON-back-up. Ook deze bestanden bevatten persoonlijke gegevens.")
        }
    }

    private func csvButton(_ report: CSVReport) -> some View {
        Button {
            prepareCSVExport(report)
        } label: {
            BackupRowLabel(title: report.title, detail: report.detail, symbol: report.symbol)
        }
        .buttonStyle(.plain)
    }

    // MARK: Exporteren

    private func prepareJSONExport() {
        do {
            let raw = try BackupService.export(store.data)
            jsonDocument = JSONBackupDocument(data: raw)
            jsonFileName = BackupService.suggestedBaseName(now: Date())
            showJSONExporter = true
        } catch {
            present(.message(title: "Exporteren mislukt", text: error.localizedDescription), delayed: false)
        }
    }

    private func prepareCSVExport(_ report: CSVReport) {
        let text = report.csv(for: store.data, current: store.now)
        csvDocument = CSVDocument(data: CSVExport.csvData(text))
        csvFileName = report.baseFileName(now: Date())
        showCSVExporter = true
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            present(.message(title: "Bestand bewaard",
                             text: "\(url.lastPathComponent) is opgeslagen. Het bevat al je persoonlijke gegevens, dus bewaar het op een veilige plek."))
        case .failure(let error):
            if isCancellation(error) { return }
            present(.message(title: "Exporteren mislukt", text: error.localizedDescription))
        }
    }

    // MARK: Importeren

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if isCancellation(error) { return }
            present(.message(title: "Importeren mislukt", text: error.localizedDescription))
        case .success(let url):
            do {
                let raw = try readFile(at: url)
                let contents = try BackupService.inspect(raw)
                present(.confirmImport(contents))
            } catch {
                present(.message(title: "Importeren mislukt", text: error.localizedDescription))
            }
        }
    }

    /// Leest het gekozen bestand. Bestanden buiten de app (Bestanden, iCloud Drive, Finder) vragen
    /// eerst om toegang; het coördineren zorgt dat een bestand uit iCloud eerst wordt gedownload.
    private func readFile(at url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        var coordinationError: NSError?
        var readError: Error?
        var fileData: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            do {
                if let size = try? readableURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > BackupService.maxImportBytes {
                    throw BackupError.unreadable("Het bestand is te groot (meer dan 50 MB).")
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

    private func restore(_ contents: BackupContents) {
        store.replaceData(contents.data)
        if store.saveFailed {
            present(.message(title: "Opslaan mislukt",
                             text: "De back-up is geladen, maar kon niet worden opgeslagen. Controleer of er ruimte is op je apparaat."))
        } else {
            present(.message(title: "Back-up teruggezet",
                             text: "Je gegevens zijn vervangen door de back-up: \(contents.summaryText)."))
        }
    }

    // MARK: Melding

    @ViewBuilder
    private func alertActions(_ alert: BackupAlert) -> some View {
        switch alert {
        case .confirmImport(let contents):
            Button("Vervang mijn gegevens", role: .destructive) {
                restore(contents)
            }
            Button("Annuleren", role: .cancel) {
                activeAlert = nil
            }
        case .message:
            Button("OK", role: .cancel) {
                activeAlert = nil
            }
        }
    }

    private func alertMessage(_ alert: BackupAlert) -> String {
        switch alert {
        case .confirmImport(let contents):
            if let date = contents.exportedAt {
                return "Je huidige gegevens worden vervangen door de back-up van \(Fmt.date(date)): \(contents.summaryText). Doorgaan?"
            }
            return "Je huidige gegevens worden vervangen door de gegevens uit dit bestand: \(contents.summaryText). Doorgaan?"
        case .message(_, let text):
            return text
        }
    }

    /// Toont een melding. Na het sluiten van de bestandskiezer of een andere melding even wachten,
    /// anders weigert het systeem de nieuwe melding te tonen.
    private func present(_ alert: BackupAlert, delayed: Bool = true) {
        Task { @MainActor in
            if delayed {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            activeAlert = alert
            showAlert = true
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return true }
        return false
    }
}
