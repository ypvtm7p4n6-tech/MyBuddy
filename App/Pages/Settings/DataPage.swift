import SwiftUI
import UniformTypeIdentifiers

/// De pagina Gegevens (`.settings(.data)`): back-up maken en terugzetten, Excel en CSV importeren, cijfers exporteren (CSV),
/// voorbeelddata laden en alles wissen. Een gewone pagina: de bestandsdialogen hangen aan de pagina zelf, één `fileExporter`
/// voor alle exports (`ExportDocument`) en één `fileImporter`. Meldingen als "Bestand bewaard" staan inline bovenaan.
/// Het importoverzicht is een eigen pagina (`SpreadsheetImportPage`), geduwd vanuit deze pagina.
struct DataPage: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud
    @Environment(Router.self) private var router
    @Environment(\.openSettingsPage) private var openPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var exportDocument: ExportDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = ""
    @State private var exportKind: ExportKind = .data
    @State private var showExporter = false

    @State private var showImporter = false
    @State private var importTypes: [UTType] = BackupFileTypes.importable
    @State private var isReading = false
    @State private var readingName = ""
    @State private var pendingRestore: BackupContents?

    @State private var confirmSample = false
    @State private var confirmErase = false

    @State private var notice: DataNotice?
    @State private var successCount = 0
    @State private var failureCount = 0

    /// Waar een export voor dient: dat bepaalt de tekst van de melding.
    private enum ExportKind {
        case data, template
    }

    /// Een melding bovenaan de pagina.
    private struct DataNotice {
        var text: String
        var symbol: String
    }

    var body: some View {
        ListScaffold(title: "Gegevens") {
            noticeRows
            backupSection
            importSection
            exportSection
            managementSection
        }
        .background { exporterHost }
        .background { importerHost }
        .sensoryFeedback(.success, trigger: successCount)
        .sensoryFeedback(.error, trigger: failureCount)
    }

    // MARK: Meldingen

    @ViewBuilder
    private var noticeRows: some View {
        if let notice {
            SettingsNotice(text: notice.text, symbol: notice.symbol)
        }
        if store.saveFailed {
            SettingsNotice(text: "Opslaan is mislukt. Controleer of er ruimte is op je apparaat.",
                           symbol: SettingsText.attentionSymbol,
                           actionTitle: "Opnieuw proberen",
                           action: { store.retrySave() })
        }
    }

    private func show(success text: String) {
        notice = DataNotice(text: text, symbol: "checkmark.circle.fill")
        successCount += 1
    }

    private func show(failure text: String) {
        notice = DataNotice(text: text, symbol: SettingsText.attentionSymbol)
        failureCount += 1
    }

    // MARK: Back-up

    private var backupSection: some View {
        Section {
            Button {
                prepareBackupExport()
            } label: {
                SettingsActionLabel(title: "Back-up maken",
                                    detail: "Alles wat je hebt ingevuld, als JSON-bestand om later terug te zetten.",
                                    symbol: "square.and.arrow.up")
            }
            restoreButton
        } header: {
            SectionHeader("Back-up")
        } footer: {
            SettingsFootnote("Een back-up bevat al je persoonlijke gegevens. Bewaar hem op een veilige plek.")
        }
    }

    /// Terugzetten vervangt je gegevens: de bevestiging hangt aan de knop zelf.
    private var restoreButton: some View {
        Button {
            startImport(types: [UTType.json])
        } label: {
            SettingsActionLabel(title: "Back-up terugzetten…",
                                detail: "Vervangt je gegevens door een eerder gemaakte back-up (JSON).",
                                symbol: "arrow.uturn.backward")
        }
        .disabled(isReading)
        .confirmationDialog("Back-up terugzetten?", isPresented: restoreBinding,
                            titleVisibility: .visible, presenting: pendingRestore) { contents in
            Button("Vervang mijn gegevens", role: .destructive) { restore(contents) }
            Button("Annuleer", role: .cancel) {}
        } message: { contents in
            Text(restoreMessage(contents))
        }
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil },
                set: { shown in
                    if !shown { pendingRestore = nil }
                })
    }

    private func restoreMessage(_ contents: BackupContents) -> String {
        var text: String
        if let date = contents.exportedAt {
            text = "Je huidige gegevens worden vervangen door de back-up van \(Fmt.date(date)): \(contents.summaryText)."
        } else {
            text = "Je huidige gegevens worden vervangen door de gegevens uit dit bestand: \(contents.summaryText)."
        }
        if FirebaseConfig.isConfigured {
            text += " Dit geldt straks ook in de cloud en op je andere apparaten."
        }
        return text
    }

    // MARK: Importeren

    private var importSection: some View {
        Section {
            Button {
                startImport(types: spreadsheetTypes)
            } label: {
                SettingsActionLabel(title: "Excel of CSV importeren…",
                                    detail: "Voegt je begroting uit een spreadsheet toe. Je ziet eerst een overzicht.",
                                    symbol: "square.and.arrow.down")
            }
            .disabled(isReading)
            if isReading {
                readingRow
            }
            Button {
                prepareTemplateExport()
            } label: {
                SettingsActionLabel(title: "Voorbeeldbestand downloaden",
                                    detail: "Een Excel-bestand met de kolommen die MyBuddy herkent, om zelf in te vullen.",
                                    symbol: "doc.badge.arrow.up")
            }
        } header: {
            SectionHeader("Importeren")
        } footer: {
            SettingsFootnote("Je bestand hoeft er niet precies zo uit te zien: MyBuddy zoekt zelf de kolommen Omschrijving en Bedrag. Standaard wordt alleen iets toegevoegd.")
        }
    }

    /// Excel, CSV en wat erop lijkt; de JSON-back-up heeft een eigen knop.
    private var spreadsheetTypes: [UTType] {
        BackupFileTypes.importable.filter { $0 != UTType.json }
    }

    private var readingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bestand wordt gelezen…")
                Text(readingName)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func startImport(types: [UTType]) {
        importTypes = types
        showImporter = true
    }

    /// Een .json is een back-up; al het andere (Excel, CSV, ...) lezen we als spreadsheet.
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if isCancellation(error) { return }
            show(failure: "Importeren mislukt. \(error.localizedDescription)")
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
            presentRestore(contents)
        } catch {
            show(failure: "Importeren mislukt. \(error.localizedDescription)")
        }
    }

    /// Na het sluiten van de bestandskiezer even wachten, anders weigert het systeem de bevestiging te tonen.
    private func presentRestore(_ contents: BackupContents) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            pendingRestore = contents
        }
    }

    private func restore(_ contents: BackupContents) {
        store.replaceData(contents.data)
        if store.saveFailed {
            show(failure: "Opslaan mislukt. De back-up is geladen, maar kon niet worden opgeslagen. Controleer of er ruimte is op je apparaat.")
        } else {
            show(success: "Back-up teruggezet. Je gegevens zijn vervangen door de back-up: \(contents.summaryText).")
        }
    }

    /// Leest het bestand op een achtergrondtaak (met een voortgangsrij) en opent dan het importoverzicht als pagina.
    private func importSpreadsheet(at url: URL) {
        readingName = url.lastPathComponent
        withAnimation(reduceMotion ? nil : Theme.motion) { isReading = true }
        let month = store.now
        let configuredSalary = store.data.salary.monthlyAmount()
        let started = Date()
        Task { @MainActor in
            let outcome = await SpreadsheetLoader.load(url: url, month: month)
            // Het systeem weigert een nieuwe presentatie zolang de bestandskiezer nog aan het sluiten is. Een klein
            // bestand is in een paar milliseconden gelezen, dus wacht tot er minstens een halve seconde voorbij is.
            let remaining = 0.5 - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            withAnimation(reduceMotion ? nil : Theme.motion) { isReading = false }
            switch outcome {
            case .failure(let error):
                show(failure: "Importeren mislukt. \(error.localizedDescription)")
            case .success(var draft):
                guard !draft.isEmpty else {
                    var text = "Niets gevonden. Er zijn geen regels met een bedrag gevonden. MyBuddy zoekt een kolom met namen (Omschrijving) en een kolom met bedragen (Bedrag). Download het voorbeeldbestand om te zien hoe het kan."
                    if let warning = draft.warnings.first { text += " " + warning }
                    show(failure: text)
                    return
                }
                // Staat je salaris al in de instellingen, dan tellen we het niet nog eens mee.
                draft.disableSalaryRows(configuredSalary: configuredSalary)
                ImportCoordinator.shared.prepare(
                    draft: draft,
                    initialMonth: store.now,
                    monthOptions: ImportMonths.options(start: store.data.startMonth, current: store.now))
                openImportReview()
            }
        }
    }

    /// Het importoverzicht is een echte bestemming: geduwd op de stapel waar deze pagina in staat.
    private func openImportReview() {
        if let openPage {
            openPage(.importReview)
        } else {
            router.open(.settings(.importReview))
        }
    }

    private var importerHost: some View {
        Color.clear
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: importTypes,
                          onCompletion: { result in handleImport(result) })
    }

    // MARK: Exporteren

    private var exportSection: some View {
        Section {
            ForEach(CSVReport.allCases) { report in
                Button {
                    prepareCSVExport(report)
                } label: {
                    SettingsActionLabel(title: report.title, detail: report.detail, symbol: report.symbol)
                }
            }
        } header: {
            SectionHeader("Exporteren")
        } footer: {
            SettingsFootnote("CSV is voor spreadsheets zoals Numbers en Excel en bevat alleen cijfers. Terugzetten kan alleen met de JSON-back-up.")
        }
    }

    private func prepareBackupExport() {
        do {
            let raw = try BackupService.export(store.data)
            exportDocument = ExportDocument(data: raw)
            exportType = UTType.json
            exportName = BackupService.suggestedBaseName(now: Date())
            exportKind = .data
            showExporter = true
        } catch {
            show(failure: "Exporteren mislukt. \(error.localizedDescription)")
        }
    }

    private func prepareCSVExport(_ report: CSVReport) {
        let text = report.csv(for: store.data, current: store.now, today: store.today)
        exportDocument = ExportDocument(data: CSVExport.csvData(text))
        exportType = UTType.commaSeparatedText
        exportName = report.baseFileName(now: Date())
        exportKind = .data
        showExporter = true
    }

    private func prepareTemplateExport() {
        exportDocument = ExportDocument(data: ImportTemplate.workbookData())
        exportType = BackupFileTypes.xlsx
        exportName = ImportTemplate.baseFileName
        exportKind = .template
        showExporter = true
    }

    private var exporterHost: some View {
        Color.clear
            .fileExporter(isPresented: $showExporter,
                          document: exportDocument,
                          contentType: exportType,
                          defaultFilename: exportName,
                          onCompletion: { result in handleExport(result) })
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            switch exportKind {
            case .data:
                show(success: "\(url.lastPathComponent) is opgeslagen. Het bevat al je persoonlijke gegevens, dus bewaar het op een veilige plek.")
            case .template:
                show(success: "\(url.lastPathComponent) is opgeslagen. Vul het in met je eigen bedragen en kies daarna Excel of CSV importeren.")
            }
        case .failure(let error):
            if isCancellation(error) { return }
            show(failure: "Exporteren mislukt. \(error.localizedDescription)")
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return true }
        return false
    }

    // MARK: Beheer

    private var managementSection: some View {
        Section {
            sampleButton
            eraseButton
        } header: {
            SectionHeader("Beheer")
        } footer: {
            SettingsFootnote(FirebaseConfig.isConfigured
                             ? "Je gegevens staan op dit apparaat en in de cloud. Voorbeelddata laden en alles wissen gelden voor allebei."
                             : "Alles wordt alleen op dit apparaat bewaard.")
        }
    }

    private var sampleButton: some View {
        Button {
            confirmSample = true
        } label: {
            SettingsActionLabel(title: "Voorbeelddata laden",
                                detail: "Vervangt je gegevens door voorbeelden, om de app uit te proberen.",
                                symbol: "wand.and.stars")
        }
        .confirmationDialog("Voorbeelddata laden?", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("Vervang mijn gegevens door voorbeelddata", role: .destructive) { loadSample() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(FirebaseConfig.isConfigured
                 ? "Je huidige gegevens worden vervangen, ook in de cloud en op je andere apparaten."
                 : "Je huidige gegevens worden vervangen.")
        }
    }

    private var eraseButton: some View {
        Button {
            confirmErase = true
        } label: {
            SettingsActionLabel(title: "Alles wissen",
                                detail: nil,
                                symbol: "trash",
                                isDestructive: true)
        }
        .confirmationDialog("Alles wissen?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Wis alle gegevens", role: .destructive) { eraseAll() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(FirebaseConfig.isConfigured
                 ? "Dit wist ook je gegevens in de cloud en op je andere apparaten. Het kan niet ongedaan worden gemaakt."
                 : "Dit kan niet ongedaan worden gemaakt.")
        }
    }

    private func loadSample() {
        // loadSampleData stempelt de wijziging zelf voor de cloud.
        store.loadSampleData()
        Task { @MainActor in
            await store.refreshPrices(force: true)
        }
    }

    private func eraseAll() {
        // eraseEverything stempelt de wijziging zelf voor de cloud.
        store.eraseEverything()
        // Ook wat dit apparaat voor dit account onthoudt (spaardoel-concept, buffer, uurloon) gaat weg.
        let account = accountPrefsID(auth: auth, cloud: cloud)
        AccountPrefs.clearAll(account: account)
        SavingsGoalDraft.clearStored(account: account)
    }
}
