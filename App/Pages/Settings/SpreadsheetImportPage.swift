import SwiftUI

/// Het importoverzicht (`.settings(.importReview)`), geduwd vanuit Gegevens: wat er uit een Excel- of CSV-bestand is gehaald, in
/// welke categorie en hoe zeker. Je kunt per rij de categorie wijzigen of de rij uitzetten, de maand kiezen en dan importeren;
/// daarna toont de pagina wat er is toegevoegd. De ingelezen gegevens komen uit `ImportCoordinator`, die de pagina Gegevens
/// vult voordat hij dit overzicht opent. De pagina houdt een eigen kopie, zodat het overzicht blijft staan als de coordinator
/// weer leeg is.
struct SpreadsheetImportPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: ImportDraft
    @State private var month: YearMonth
    @State private var monthOptions: [YearMonth]
    @State private var hasDraft: Bool
    @State private var updateExisting = false
    @State private var report: ImportReport?
    @State private var importedCount = 0

    @MainActor
    init() {
        let source = ImportCoordinator.shared
        _draft = State(initialValue: source.draft ?? ImportDraft())
        _month = State(initialValue: source.initialMonth)
        _monthOptions = State(initialValue: source.monthOptions)
        _hasDraft = State(initialValue: source.hasDraft)
    }

    var body: some View {
        ListScaffold(title: "Importoverzicht") {
            content
        }
        .toolbar {
            if report == nil && hasDraft {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importeer") { runImport() }
                        .disabled(draft.activeCount == 0)
                }
            }
        }
        .sensoryFeedback(.success, trigger: importedCount)
        .onDisappear { ImportCoordinator.shared.reset() }
    }

    @ViewBuilder
    private var content: some View {
        if let report {
            resultContent(report)
        } else if !hasDraft {
            emptySection
        } else {
            reviewContent
        }
    }

    private var emptySection: some View {
        Section {
            EmptyHint(symbol: "doc.text",
                      title: "Geen bestand om te controleren",
                      message: "Kies bij Gegevens een Excel- of CSV-bestand om te importeren.",
                      actionTitle: "Naar Gegevens",
                      action: { dismiss() })
        }
    }

    // MARK: Controleren

    @ViewBuilder
    private var reviewContent: some View {
        headerSection
        ForEach(ImportCategory.selectable) { category in
            if !draft.rows(in: category).isEmpty {
                categorySection(category)
            }
        }
        if !draft.rows(in: .overslaan).isEmpty {
            skippedSection
        }
    }

    private var headerSection: some View {
        Section {
            Picker("Importeren in", selection: $month) {
                ForEach(monthOptions, id: \.self) { option in
                    Text(Fmt.month(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Theme.minTapTarget)
            ForEach(draft.summary) { item in
                AmountRow(title: item.category.title,
                          value: Fmt.euro(item.total),
                          detail: item.count == 1 ? "1 regel" : "\(item.count) regels",
                          symbol: item.category.symbol)
            }
            Toggle(isOn: $updateExisting) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bestaande bijwerken")
                    Text(updateExisting
                         ? "Staat een naam al in je gegevens, dan krijgt die het nieuwe bedrag."
                         : "Staat een naam al in je gegevens, dan blijft die zoals hij is.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .frame(minHeight: Theme.minTapTarget)
            warningRows
        } header: {
            SectionHeader(draft.fileName.isEmpty ? "Bestand" : draft.fileName, symbol: "doc.text.fill")
        } footer: {
            SettingsFootnote(reviewHint)
        }
    }

    @ViewBuilder
    private var warningRows: some View {
        ForEach(draft.warnings, id: \.self) { warning in
            Label(warning, systemImage: SettingsText.attentionSymbol)
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// De uitleg onder het overzicht. Wat erin staat over vervangen hangt af van de schakelaar "Bestaande bijwerken".
    private var reviewHint: String {
        let intro = "Controleer de indeling. Het symbool bij een regel zegt hoe zeker die is: een vinkje is zeker, een vraagteken redelijk en een uitroepteken een gok. "
        if updateExisting {
            return intro + "Een naam die al bestaat krijgt het nieuwe bedrag; verder wordt alleen iets toegevoegd."
        }
        return intro + "Er wordt alleen iets toegevoegd; niets wordt vervangen."
    }

    private func categorySection(_ category: ImportCategory) -> some View {
        let rows = draft.rows(in: category)
        return Section {
            ForEach(rows) { row in
                ImportRowView(row: row,
                              onCategory: { newCategory in
                                  change { draft.setCategory(newCategory, for: row.id) }
                              },
                              onIncluded: { included in
                                  change { draft.setIncluded(included, for: row.id) }
                              },
                              onMeaning: { meaning in
                                  change { draft.setMeaning(meaning, for: row.id) }
                              })
            }
        } header: {
            SectionHeader(category.title, symbol: category.symbol)
        } footer: {
            SettingsFootnote("\(draft.count(of: category)) aan · \(Fmt.euro(draft.total(of: category)))")
        }
    }

    private var skippedSection: some View {
        let rows = draft.rows(in: .overslaan)
        return Section {
            ForEach(rows) { row in
                ImportRowView(row: row,
                              onCategory: { newCategory in
                                  change { draft.setCategory(newCategory, for: row.id) }
                              },
                              onIncluded: { _ in },
                              onMeaning: { _ in })
            }
        } header: {
            SectionHeader("Overgeslagen regels", symbol: ImportCategory.overslaan.symbol)
        } footer: {
            SettingsFootnote("Totaalregels en wat je zelf hebt uitgezet.")
        }
    }

    /// Een wijziging in het overzicht, met een korte overgang (niet bij Verlaag beweging).
    private func change(_ edit: () -> Void) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            edit()
        }
    }

    private func runImport() {
        var result: ImportReport?
        let chosenMonth = month
        let policy: ImportExistingPolicy = updateExisting ? .update : .skip
        let current = draft
        store.mutate { data in
            result = data.applyImport(current, month: chosenMonth, existing: policy)
        }
        withAnimation(reduceMotion ? nil : Theme.motion) { report = result }
        importedCount += 1
        // Nieuwe beleggingen met ticker en aantal volgen de koers: haal die meteen op.
        if (result?.count(.added, in: .belegging) ?? 0) > 0,
           store.data.holdings.contains(where: { $0.isTracked && $0.lastPrice == nil }) {
            Task { @MainActor in
                await store.refreshPrices(force: true)
            }
        }
    }

    // MARK: Uitkomst

    @ViewBuilder
    private func resultContent(_ report: ImportReport) -> some View {
        resultSummarySection(report)
        lineSection(title: "Toegevoegd", symbol: "plus.circle.fill",
                    lines: report.lines.filter { $0.outcome == .added }, showsAmount: true)
        lineSection(title: "Bijgewerkt", symbol: "arrow.triangle.2.circlepath",
                    lines: report.lines.filter { $0.outcome == .updated }, showsAmount: true)
        lineSection(title: "Overgeslagen", symbol: "arrow.uturn.forward.circle",
                    lines: report.lines.filter { $0.outcome == .skippedExisting }, showsAmount: false)
    }

    private func resultSummarySection(_ report: ImportReport) -> some View {
        Section {
            Label {
                Text(report.summaryText)
                    .font(.headline)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.positive)
            }
            if report.notSelected > 0 {
                SettingsFootnote(report.notSelected == 1
                                 ? "1 regel stond uit en is niet meegenomen."
                                 : "\(report.notSelected) regels stonden uit en zijn niet meegenomen.")
            }
            ForEach(report.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if store.saveFailed {
                Label("Opslaan is mislukt. Controleer of er ruimte is op je apparaat.", systemImage: SettingsText.attentionSymbol)
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
            }
            ForEach(report.categories) { category in
                AmountRow(title: category.title, value: categoryText(category, in: report), symbol: category.symbol)
            }
            ActionButton(title: "Klaar", symbol: "checkmark", prominent: true) {
                dismiss()
            }
            .listRowBackground(Color.clear)
        } header: {
            SectionHeader("Import voltooid", symbol: "checkmark.circle.fill")
        } footer: {
            SettingsFootnote("Toegevoegd aan \(Fmt.month(report.month)). Je vindt de nieuwe regels bij Inkomen, Uitgaven, Spaarpotten en Beleggingen; daar kun je ze aanpassen of weghalen.")
        }
    }

    @ViewBuilder
    private func lineSection(title: String, symbol: String, lines: [ImportReportLine], showsAmount: Bool) -> some View {
        if !lines.isEmpty {
            Section {
                ForEach(lines) { line in
                    AmountRow(title: line.name,
                              value: showsAmount ? Fmt.euro(line.amount) : "bestaat al",
                              symbol: line.category.symbol)
                }
            } header: {
                SectionHeader(title, symbol: symbol)
            } footer: {
                SettingsFootnote(lines.count == 1 ? "1 regel" : "\(lines.count) regels")
            }
        }
    }

    private func categoryText(_ category: ImportCategory, in report: ImportReport) -> String {
        var parts: [String] = []
        let addedCount = report.count(.added, in: category)
        let updatedCount = report.count(.updated, in: category)
        let skippedCount = report.count(.skippedExisting, in: category)
        if addedCount > 0 { parts.append("\(addedCount) toegevoegd") }
        if updatedCount > 0 { parts.append("\(updatedCount) bijgewerkt") }
        if skippedCount > 0 { parts.append("\(skippedCount) overgeslagen") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Rij in het overzicht

/// Eén regel: een symbool voor de zekerheid (naast de kleur), naam met uitleg, bedrag en een menu om de regel te wijzigen. De
/// swipe-actie en het contextmenu hebben "Niet importeren" of "Toch importeren", zoals het menu.
private struct ImportRowView: View {
    let row: ImportRow
    let onCategory: (ImportCategory) -> Void
    let onIncluded: (Bool) -> Void
    let onMeaning: (ImportAmountMeaning) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: confidenceSymbol)
                .foregroundStyle(confidenceColor)
                .accessibilityLabel(row.confidence.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(!row.isActive)
                    .foregroundStyle(row.isActive ? Color.primary : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                changeMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.euro(row.amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.isActive ? Color.primary : Theme.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 4)
        .rowActions(extra: extraActions)
    }

    // MARK: Menu

    private var changeMenu: some View {
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
            HStack(spacing: 4) {
                Text(row.category.title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: Theme.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .accessibilityLabel("Wijzig \(row.name), nu \(row.category.title)")
    }

    private var extraActions: [RowAction] {
        if row.category == .overslaan { return [] }
        let title = row.isIncluded ? "Niet importeren" : "Toch importeren"
        let symbol = row.isIncluded ? "minus.circle" : "plus.circle"
        return [RowAction(title, symbol: symbol) { onIncluded(!row.isIncluded) }]
    }

    // MARK: Zekerheid

    private var confidenceSymbol: String {
        switch row.confidence {
        case .hoog: return "checkmark.circle.fill"
        case .middel: return "questionmark.circle.fill"
        case .laag: return "exclamationmark.circle.fill"
        }
    }

    private var confidenceColor: Color {
        guard row.isActive else { return Theme.textSecondary }
        switch row.confidence {
        case .hoog: return Theme.positive
        case .middel: return Theme.warning
        case .laag: return Theme.negative
        }
    }

    /// Reden, notitie en bij sparen en beleggen wat het bedrag betekent.
    private var caption: String {
        var parts: [String] = []
        if !row.reason.isEmpty { parts.append(row.reason.prefix(1).capitalized + row.reason.dropFirst()) }
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
