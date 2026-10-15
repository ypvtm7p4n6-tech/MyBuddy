import SwiftUI
import UniformTypeIdentifiers

// Export en import in de instellingen.
//
// Keuze van bestandstype (zie ook App/Core/Export.swift):
// - JSON voor de volledige back-up: verliesvrij, leesbaar en met een versienummer. Dit kun je terugzetten.
// - CSV voor Numbers of Excel: platte tabellen, alleen exporteren.
// - Excel (.xlsx) en CSV importeren: je eigen begroting. De app herkent de onderdelen en deelt ze in bij inkomen,
//   vaste lasten, variabele lasten, spaarpotten en beleggingen (zie App/Core/ImportMapping.swift). Je ziet eerst een
//   overzicht waarin je alles kunt aanpassen; standaard wordt alleen iets toegevoegd en niets vervangen. Alleen als je
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

/// Een Excel-werkmap als bestand, voor `fileExporter` (het voorbeeldbestand).
struct XLSXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [BackupFileTypes.xlsx] }

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

/// Welke rij een melding, exporter of overzicht toont. Een Form is op iOS een lijst: rijen buiten beeld bestaan dan niet,
/// en een presentatie die eraan hangt verschijnt niet. Daarom hangt elke presentatie aan de rij die je net hebt
/// aangetikt, en die bestaat zeker.
private enum BackupHost: Hashable {
    case json
    case importer
    case template
    case csv(CSVReport)
}

/// Een ingelezen spreadsheet dat wacht op controle in het overzicht.
private struct PendingSpreadsheetImport: Identifiable {
    let id = UUID()
    var draft: ImportDraft
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

/// Secties voor een Form (Instellingen): back-up exporteren en importeren (JSON, Excel, CSV) en cijfers exporteren (CSV).
/// Levert Sections terug, dus nooit in een ScrollView zetten.
struct BackupSection: View {
    @Environment(AppStore.self) private var store

    @State private var jsonDocument: JSONBackupDocument?
    @State private var jsonFileName = ""
    @State private var showJSONExporter = false

    @State private var csvDocument: CSVDocument?
    @State private var csvFileName = ""
    @State private var showCSVExporter = false
    @State private var csvTarget: CSVReport = .monthly

    @State private var templateDocument: XLSXDocument?
    @State private var showTemplateExporter = false

    @State private var showImporter = false
    @State private var isReading = false
    @State private var readingName = ""
    @State private var pendingImport: PendingSpreadsheetImport?

    @State private var activeAlert: BackupAlert?
    @State private var showAlert = false
    @State private var alertHost: BackupHost = .json

    // Elke presentatie hangt aan de rij die je net hebt aangetikt (zie `BackupHost`). Op die rij staat de exporter of
    // importer zelf; de melding en het overzicht hangen elk aan een eigen achtergrond, want twee `fileExporter`s, of een
    // exporter en een importer, op dezelfde view hinderen elkaar.
    var body: some View {
        Section {
            jsonRow
            importRow

            if isReading {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bestand wordt gelezen…")
                        Text(readingName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Back-up en importeren")
        } footer: {
            Text("JSON is de volledige back-up: alles blijft behouden en je kunt hem hier weer importeren. Ook een kaal finance.json werkt. Een Excel- of CSV-bestand voegt toe wat er nog niet is en laat bestaande regels staan, tenzij je in het overzicht kiest voor Bestaande bijwerken. Je ziet altijd eerst een overzicht waarin je alles kunt aanpassen. Een back-up bevat al je persoonlijke gegevens. Bewaar hem op een veilige plek en deel hem niet zomaar.")
        }

        Section {
            templateRow
        } header: {
            Text("Excel en CSV")
        } footer: {
            Text("Je eigen bestand hoeft er niet precies zo uit te zien. MyBuddy zoekt de kolommen Omschrijving en Bedrag, leest kopjes als Vaste lasten en herkent woorden als huur, boodschappen, salaris, sparen en ETF. Heb je kolommen per maand (jan t/m dec), dan neemt MyBuddy de huidige maand of het gemiddelde. Oudere .xls-bestanden en Numbers-bestanden sla je eerst op als .xlsx of .csv.")
        }

        Section {
            csvRow(.monthly)
            csvRow(.transactions)
            csvRow(.holdings)
        } header: {
            Text("Cijfers exporteren (CSV)")
        } footer: {
            Text("CSV is voor spreadsheets zoals Numbers en Excel. Het bevat alleen cijfers, met een puntkomma tussen de kolommen en een komma als decimaalteken. CSV kun je niet terugzetten: gebruik daarvoor de JSON-back-up. Ook deze bestanden bevatten persoonlijke gegevens.")
        }
    }

    // MARK: Rijen

    private var jsonRow: some View {
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
                      onCompletion: { result in handleExport(result, from: .json) })
        .background { alertBackground(for: .json) }
    }

    private var importRow: some View {
        Button {
            showImporter = true
        } label: {
            BackupRowLabel(title: "Importeren",
                           detail: "Een back-up (JSON) terugzetten, of een Excel- of CSV-bestand met je begroting toevoegen.",
                           symbol: "square.and.arrow.down")
        }
        .buttonStyle(.plain)
        .disabled(isReading)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: BackupFileTypes.importable,
                      onCompletion: { result in handleImport(result) })
        .background { alertBackground(for: .importer) }
        .background { importSheetBackground }
    }

    private var templateRow: some View {
        Button {
            prepareTemplateExport()
        } label: {
            BackupRowLabel(title: "Voorbeeldbestand downloaden",
                           detail: "Een Excel-bestand met de kolommen die MyBuddy herkent, om zelf in te vullen.",
                           symbol: "doc.badge.arrow.up")
        }
        .buttonStyle(.plain)
        .fileExporter(isPresented: $showTemplateExporter,
                      document: templateDocument,
                      contentType: BackupFileTypes.xlsx,
                      defaultFilename: ImportTemplate.baseFileName,
                      onCompletion: { result in handleTemplateExport(result) })
        .background { alertBackground(for: .template) }
    }

    private func csvRow(_ report: CSVReport) -> some View {
        Button {
            prepareCSVExport(report)
        } label: {
            BackupRowLabel(title: report.title, detail: report.detail, symbol: report.symbol)
        }
        .buttonStyle(.plain)
        .fileExporter(isPresented: csvExporterBinding(report),
                      document: csvDocument,
                      contentType: .commaSeparatedText,
                      defaultFilename: csvFileName,
                      onCompletion: { result in handleExport(result, from: .csv(report)) })
        .background { alertBackground(for: .csv(report)) }
    }

    /// De melding van een rij: alleen de rij die hem heeft aangevraagd toont hem.
    private func alertBackground(for host: BackupHost) -> some View {
        Color.clear
            .alert(activeAlert?.title ?? "", isPresented: alertBinding(for: host), presenting: activeAlert) { alert in
                alertActions(alert)
            } message: { alert in
                Text(alertMessage(alert))
            }
    }

    /// Het overzicht van een Excel- of CSV-import; hangt aan de rij Importeren.
    private var importSheetBackground: some View {
        Color.clear
            .sheet(item: $pendingImport) { pending in
                SpreadsheetImportSheet(draft: pending.draft,
                                       initialMonth: store.now,
                                       monthOptions: SpreadsheetImportSheet.options(start: store.data.startMonth,
                                                                                     current: store.now))
            }
    }

    private func alertBinding(for host: BackupHost) -> Binding<Bool> {
        Binding(get: { showAlert && alertHost == host },
                set: { isShown in
                    if !isShown { showAlert = false }
                })
    }

    private func csvExporterBinding(_ report: CSVReport) -> Binding<Bool> {
        Binding(get: { showCSVExporter && csvTarget == report },
                set: { isShown in
                    if !isShown { showCSVExporter = false }
                })
    }

    // MARK: Exporteren

    private func prepareJSONExport() {
        do {
            let raw = try BackupService.export(store.data)
            jsonDocument = JSONBackupDocument(data: raw)
            jsonFileName = BackupService.suggestedBaseName(now: Date())
            showJSONExporter = true
        } catch {
            present(.message(title: "Exporteren mislukt", text: error.localizedDescription), from: .json, delayed: false)
        }
    }

    private func prepareCSVExport(_ report: CSVReport) {
        let text = report.csv(for: store.data, current: store.now, today: store.today)
        csvDocument = CSVDocument(data: CSVExport.csvData(text))
        csvFileName = report.baseFileName(now: Date())
        csvTarget = report
        showCSVExporter = true
    }

    private func prepareTemplateExport() {
        templateDocument = XLSXDocument(data: ImportTemplate.workbookData())
        showTemplateExporter = true
    }

    private func handleExport(_ result: Result<URL, Error>, from host: BackupHost) {
        switch result {
        case .success(let url):
            present(.message(title: "Bestand bewaard",
                             text: "\(url.lastPathComponent) is opgeslagen. Het bevat al je persoonlijke gegevens, dus bewaar het op een veilige plek."),
                    from: host)
        case .failure(let error):
            if isCancellation(error) { return }
            present(.message(title: "Exporteren mislukt", text: error.localizedDescription), from: host)
        }
    }

    private func handleTemplateExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            present(.message(title: "Voorbeeldbestand bewaard",
                             text: "\(url.lastPathComponent) is opgeslagen. Vul het in met je eigen bedragen en kies daarna Importeren."),
                    from: .template)
        case .failure(let error):
            if isCancellation(error) { return }
            present(.message(title: "Opslaan mislukt", text: error.localizedDescription), from: .template)
        }
    }

    // MARK: Importeren

    /// Een .json is een back-up; al het andere (Excel, CSV, ...) lezen we als spreadsheet.
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if isCancellation(error) { return }
            present(.message(title: "Importeren mislukt", text: error.localizedDescription), from: .importer)
        case .success(let url):
            if url.pathExtension.lowercased() == "json" {
                importBackup(at: url)
            } else {
                importSpreadsheet(at: url)
            }
        }
    }

    private func importBackup(at url: URL) {
        do {
            let raw = try BackupFileReader.read(url, maxBytes: BackupService.maxImportBytes,
                                                tooLarge: BackupError.unreadable("Het bestand is te groot (meer dan 50 MB)."))
            let contents = try BackupService.inspect(raw)
            present(.confirmImport(contents), from: .importer)
        } catch {
            present(.message(title: "Importeren mislukt", text: error.localizedDescription), from: .importer)
        }
    }

    /// Leest het bestand op een achtergrondtaak (met een voortgangsrij) en toont dan het overzicht.
    private func importSpreadsheet(at url: URL) {
        readingName = url.lastPathComponent
        withAnimation(Theme.motion) { isReading = true }
        let month = store.now
        let configuredSalary = store.data.salary.monthlyAmount()
        let started = Date()
        Task { @MainActor in
            let outcome = await SpreadsheetLoader.load(url: url, month: month)
            // Het systeem weigert een overzicht of melding zolang de bestandskiezer nog aan het sluiten is. Een klein
            // bestand is in een paar milliseconden gelezen, dus wacht tot er minstens een halve seconde voorbij is.
            let remaining = 0.5 - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            withAnimation(Theme.motion) { isReading = false }
            switch outcome {
            case .failure(let error):
                present(.message(title: "Importeren mislukt", text: error.localizedDescription), from: .importer, delayed: false)
            case .success(var draft):
                guard !draft.isEmpty else {
                    var text = "Er zijn geen regels met een bedrag gevonden. MyBuddy zoekt een kolom met namen (Omschrijving) en een kolom met bedragen (Bedrag). Download het voorbeeldbestand om te zien hoe het kan."
                    if let warning = draft.warnings.first { text += " " + warning }
                    present(.message(title: "Niets gevonden", text: text), from: .importer, delayed: false)
                    return
                }
                // Staat je salaris al in de instellingen, dan tellen we het niet nog eens mee.
                draft.disableSalaryRows(configuredSalary: configuredSalary)
                pendingImport = PendingSpreadsheetImport(draft: draft)
            }
        }
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
    /// `host` is de rij die de melding toont; zonder `host` blijft het de rij van de vorige melding (bijvoorbeeld de
    /// uitkomst na "Vervang mijn gegevens").
    private func present(_ alert: BackupAlert, from host: BackupHost? = nil, delayed: Bool = true) {
        let target = host ?? alertHost
        Task { @MainActor in
            if delayed {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            alertHost = target
            activeAlert = alert
            showAlert = true
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return true }
        return false
    }
}

// MARK: - Overzicht voor het importeren

/// Het overzicht na het inlezen van een Excel- of CSV-bestand: wat is gevonden, in welke categorie, en hoe zeker.
/// Je kunt per rij de categorie wijzigen of de rij uitzetten, de maand kiezen en dan importeren.
struct SpreadsheetImportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ImportDraft
    @State private var month: YearMonth
    @State private var updateExisting = false
    @State private var report: ImportReport?
    private let monthOptions: [YearMonth]

    init(draft: ImportDraft, initialMonth: YearMonth, monthOptions: [YearMonth]) {
        _draft = State(initialValue: draft)
        _month = State(initialValue: initialMonth)
        self.monthOptions = monthOptions
    }

    /// De maanden die je kunt kiezen: vanaf je startmaand (hooguit 3 jaar terug) tot een jaar vooruit.
    static func options(start: YearMonth, current: YearMonth) -> [YearMonth] {
        let lowest = max(start, current.adding(-36))
        let first = min(lowest, current)
        return first.range(count: first.months(to: current.adding(12)) + 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let report {
                    ImportResultView(report: report, saveFailed: store.saveFailed) { dismiss() }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    reviewContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .background { MeshBackground() }
            .navigationTitle(report == nil ? "Importeren" : "Klaar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 680)
        #endif
    }

    // MARK: Controleren

    private var reviewContent: some View {
        ScrollView {
            LazyVStack(spacing: Theme.pageSpacing) {
                headerBlock
                ForEach(ImportCategory.selectable) { category in
                    if !draft.rows(in: category).isEmpty {
                        categoryBlock(category)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                if !draft.rows(in: .overslaan).isEmpty {
                    skippedBlock
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: Theme.pageMaxWidth)
            .frame(maxWidth: .infinity)
            .animation(Theme.motion, value: draft)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
    }

    private var headerBlock: some View {
        GlassBlock(title: draft.fileName.isEmpty ? "Bestand" : draft.fileName,
                   symbol: "doc.text.fill",
                   subtitle: headerSubtitle) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Importeren in")
                    Spacer(minLength: 8)
                    Picker("Maand", selection: $month) {
                        ForEach(monthOptions, id: \.self) { option in
                            Text(Fmt.month(option)).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(draft.summary) { item in
                        StatTile(title: item.category.title,
                                 value: Fmt.euro(item.total),
                                 color: item.count == 0 ? .secondary : .primary,
                                 caption: item.count == 1 ? "1 regel" : "\(item.count) regels")
                    }
                }

                Toggle(isOn: $updateExisting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bestaande bijwerken")
                        Text(updateExisting ? "Staat een naam al in je gegevens, dan krijgt die het nieuwe bedrag."
                                            : "Staat een naam al in je gegevens, dan blijft die zoals hij is.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)

                if !draft.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(draft.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(reviewHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// De uitleg onder het overzicht. Wat erin staat over vervangen hangt af van de schakelaar "Bestaande bijwerken".
    private var reviewHint: String {
        let intro = "Controleer de indeling. Een groen bolletje is zeker, oranje redelijk, rood een gok. "
        if updateExisting {
            return intro + "Een naam die al bestaat krijgt het nieuwe bedrag; verder wordt alleen iets toegevoegd."
        }
        return intro + "Er wordt alleen iets toegevoegd; niets wordt vervangen."
    }

    private var headerSubtitle: String {
        let active = draft.activeCount
        let total = draft.rows.count
        return "\(active) van \(total) regels aan"
    }

    private func categoryBlock(_ category: ImportCategory) -> some View {
        let rows = draft.rows(in: category)
        return GlassBlock(title: category.title,
                          symbol: category.symbol,
                          subtitle: "\(draft.count(of: category)) aan · \(Fmt.euro(draft.total(of: category)))") {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    VStack(spacing: 0) {
                        ImportRowView(row: row,
                                      onCategory: { newCategory in
                                          withAnimation(Theme.motion) { draft.setCategory(newCategory, for: row.id) }
                                      },
                                      onIncluded: { included in
                                          withAnimation(Theme.motion) { draft.setIncluded(included, for: row.id) }
                                      },
                                      onMeaning: { meaning in
                                          withAnimation(Theme.motion) { draft.setMeaning(meaning, for: row.id) }
                                      })
                        if row.id != rows.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var skippedBlock: some View {
        let rows = draft.rows(in: .overslaan)
        return GlassBlock(title: "Overgeslagen regels",
                          symbol: ImportCategory.overslaan.symbol,
                          subtitle: "Totaalregels en wat je zelf hebt uitgezet") {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    VStack(spacing: 0) {
                        ImportRowView(row: row,
                                      onCategory: { newCategory in
                                          withAnimation(Theme.motion) { draft.setCategory(newCategory, for: row.id) }
                                      },
                                      onIncluded: { _ in },
                                      onMeaning: { _ in })
                        if row.id != rows.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            ChipButton(title: "Annuleren", symbol: "xmark") {
                dismiss()
            }
            ChipButton(title: "Importeren", symbol: "square.and.arrow.down") {
                runImport()
            }
            .disabled(draft.activeCount == 0)
            .opacity(draft.activeCount == 0 ? 0.45 : 1)
        }
        .animation(Theme.quickMotion, value: draft.activeCount)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: Theme.pageMaxWidth)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func runImport() {
        var result: ImportReport?
        let chosenMonth = month
        let policy: ImportExistingPolicy = updateExisting ? .update : .skip
        let current = draft
        store.mutate { data in
            result = data.applyImport(current, month: chosenMonth, existing: policy)
        }
        withAnimation(Theme.motion) { report = result }
        // Nieuwe beleggingen met ticker en aantal volgen de koers: haal die meteen op.
        if (result?.count(.added, in: .belegging) ?? 0) > 0,
           store.data.holdings.contains(where: { $0.isTracked && $0.lastPrice == nil }) {
            Task { await store.refreshPrices(force: true) }
        }
    }
}

// MARK: - Rij in het overzicht

/// Eén regel: bolletje voor de zekerheid, naam met uitleg, bedrag en een menu om te wijzigen.
private struct ImportRowView: View {
    let row: ImportRow
    let onCategory: (ImportCategory) -> Void
    let onIncluded: (Bool) -> Void
    let onMeaning: (ImportAmountMeaning) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .accessibilityLabel(row.confidence.title)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(!row.isActive)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Fmt.euro(row.amount))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Menu {
                Picker("Categorie", selection: Binding(get: { row.category }, set: { onCategory($0) })) {
                    ForEach(ImportCategory.selectable) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }
                if row.category == .spaarpot || row.category == .belegging {
                    Picker("Bedrag is", selection: Binding(get: { row.meaning }, set: { onMeaning($0) })) {
                        ForEach(ImportAmountMeaning.allCases) { meaning in
                            Text(meaning.title).tag(meaning)
                        }
                    }
                }
                if row.category != .overslaan {
                    Divider()
                    Button {
                        onIncluded(!row.isIncluded)
                    } label: {
                        Label(row.isIncluded ? "Niet importeren" : "Toch importeren",
                              systemImage: row.isIncluded ? "minus.circle" : "plus.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel("Wijzig \(row.name)")
        }
        .padding(.vertical, 6)
        .opacity(row.isActive ? 1 : 0.5)
        .animation(Theme.quickMotion, value: row.isActive)
        .animation(Theme.motion, value: row.amount)
    }

    private var dotColor: Color {
        guard row.isActive else { return Color.secondary.opacity(0.5) }
        switch row.confidence {
        case .hoog: return Theme.positive
        case .middel: return Theme.warning
        case .laag: return Theme.negative
        }
    }

    /// Reden, notitie en bij sparen en beleggen wat het bedrag betekent.
    private var caption: String {
        var parts: [String] = []
        if !row.reason.isEmpty { parts.append(row.reason.prefix(1).uppercased() + row.reason.dropFirst()) }
        if row.category == .spaarpot || row.category == .belegging {
            parts.append(row.meaning.title)
            if row.meaning == .perMaand, let balance = row.balance, balance > 0 {
                parts.append("beginsaldo \(Fmt.euro(balance))")
            }
        }
        if let ticker = row.ticker, row.category == .belegging { parts.append(ticker) }
        if let day = row.day, row.category != .overslaan { parts.append("dag \(day)") }
        if !row.note.isEmpty { parts.append(row.note) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Uitkomst

/// Wat er is toegevoegd en wat is overgeslagen.
private struct ImportResultView: View {
    let report: ImportReport
    let saveFailed: Bool
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: "Import voltooid",
                           symbol: "checkmark.circle.fill",
                           subtitle: Fmt.month(report.month)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(report.summaryText)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                        if report.notSelected > 0 {
                            Text(report.notSelected == 1 ? "1 regel stond uit en is niet meegenomen."
                                                          : "\(report.notSelected) regels stonden uit en zijn niet meegenomen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(report.notes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if saveFailed {
                            Label("Opslaan is mislukt. Controleer of er ruimte is op je apparaat.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.negative)
                        }
                        VStack(spacing: 0) {
                            ForEach(report.categories) { category in
                                HStack(spacing: 10) {
                                    Image(systemName: category.symbol)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 24)
                                    Text(category.title)
                                    Spacer(minLength: 8)
                                    Text(categoryText(category))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 8)
                                Divider().opacity(0.5)
                            }
                        }
                        Text("Je vindt de nieuwe regels bij Inkomen, Vaste lasten, Spaarpotten en Beleggingen. Daar kun je ze aanpassen of weghalen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !added.isEmpty {
                    GlassBlock(title: "Toegevoegd", symbol: "plus.circle.fill", subtitle: "\(added.count) regels") {
                        lineList(added, detail: { Fmt.euro($0.amount) })
                    }
                }
                if !skipped.isEmpty {
                    GlassBlock(title: "Overgeslagen", symbol: "arrow.uturn.forward.circle", subtitle: "Bestaat al") {
                        lineList(skipped, detail: { _ in "bestaat al" })
                    }
                }
                if !updated.isEmpty {
                    GlassBlock(title: "Bijgewerkt", symbol: "arrow.triangle.2.circlepath", subtitle: "\(updated.count) regels") {
                        lineList(updated, detail: { Fmt.euro($0.amount) })
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: Theme.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            ChipButton(title: "Klaar", symbol: "checkmark") {
                onDone()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: Theme.pageMaxWidth)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var added: [ImportReportLine] { report.lines.filter { $0.outcome == .added } }
    private var skipped: [ImportReportLine] { report.lines.filter { $0.outcome == .skippedExisting } }
    private var updated: [ImportReportLine] { report.lines.filter { $0.outcome == .updated } }

    private func categoryText(_ category: ImportCategory) -> String {
        var parts: [String] = []
        let addedCount = report.count(.added, in: category)
        let updatedCount = report.count(.updated, in: category)
        let skippedCount = report.count(.skippedExisting, in: category)
        if addedCount > 0 { parts.append("\(addedCount) toegevoegd") }
        if updatedCount > 0 { parts.append("\(updatedCount) bijgewerkt") }
        if skippedCount > 0 { parts.append("\(skippedCount) overgeslagen") }
        return parts.joined(separator: ", ")
    }

    private func lineList(_ lines: [ImportReportLine], detail: @escaping (ImportReportLine) -> String) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(lines) { line in
                HStack(spacing: 10) {
                    Image(systemName: line.category.symbol)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    Text(line.name)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(detail(line))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                if line.id != lines.last?.id {
                    Divider().opacity(0.5)
                }
            }
        }
    }
}
