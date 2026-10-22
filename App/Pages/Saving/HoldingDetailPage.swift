import SwiftUI

// De pagina van één belegging: Samenvatting, Koers en waarde (met de grafiek), Uitgangspunten, Inleg en Waarde-updates, met onderaan
// Verwijderen. Elk blok is een eigen sectie in een kleine view.

struct HoldingDetailPage: View {
    let holdingID: UUID
    @Environment(AppStore.self) private var store
    @State private var sheet: HoldingDetailSheet?

    /// De bladen die deze pagina opent, in een `.sheet(item:)`.
    private enum HoldingDetailSheet: Identifiable {
        case edit
        case value

        var id: String {
            switch self {
            case .edit: return "edit"
            case .value: return "value"
            }
        }
    }

    init(holdingID: UUID) {
        self.holdingID = holdingID
    }

    var body: some View {
        if let holding = store.data.holding(holdingID) {
            content(holding)
        } else {
            ListScaffold(title: "Belegging") {
                Section {
                    EmptyHint(symbol: "questionmark.folder", title: "Deze belegging bestaat niet meer")
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ holding: Holding) -> some View {
        ListScaffold(title: holding.name) {
            HoldingSummarySection(holding: holding)
            HoldingChartSection(holding: holding, onAction: { action in handle(action) })
            HoldingAssumptionsSection(holding: holding)
            HoldingContributionSection(holding: holding, onEdit: { sheet = .edit })
            HoldingUpdatesSection(holding: holding, onValueUpdate: { sheet = .value })
            HoldingDeleteSection(holding: holding)
        }
        .refreshable { await store.refreshPrices(force: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                moreMenu(holding)
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item, holding: holding)
        }
    }

    /// "Bewerken", "Waarde bijwerken" (zonder koers) en "Koers vernieuwen" (met een ticker) in het menu van de werkbalk.
    private func moreMenu(_ holding: Holding) -> some View {
        Menu {
            Button { sheet = .edit } label: {
                Label("Bewerken", systemImage: "pencil")
            }
            if !holding.isTracked {
                Button { sheet = .value } label: {
                    Label("Waarde bijwerken", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if holding.hasTicker {
                Button {
                    Task { await store.refreshPrices(force: true) }
                } label: {
                    Label("Koers vernieuwen", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshingPrices)
            }
        } label: {
            Label("Meer", systemImage: "ellipsis")
        }
        .help("Meer")
    }

    @ViewBuilder
    private func sheetContent(_ item: HoldingDetailSheet, holding: Holding) -> some View {
        switch item {
        case .edit: HoldingEditSheet(holding: holding)
        case .value: ValueUpdateSheet(holding: holding)
        }
    }

    /// De knop in de lege staat van de grafiek: het aantal invullen kan in het formulier, een waarde in het blad voor de waarde.
    private func handle(_ action: ChartEmpty.Action) {
        switch action {
        case .enterUnits, .addHolding:
            sheet = .edit
        case .enterValue:
            sheet = .value
        case .refreshPrices:
            Task { await store.refreshPrices(force: true) }
        case .retry, .enterBankBalance, .openSalary:
            break
        }
    }
}

// MARK: - Samenvatting

/// De waarde van nu met de winst, wat je inlegde en (met een ticker) het aantal en de koers. Is de waarde geschat uit je inleg,
/// dan staat er "Geschat" bij het bedrag en zijn Winst en het percentage verborgen.
struct HoldingSummarySection: View {
    let holding: Holding
    @Environment(AppStore.self) private var store

    init(holding: Holding) {
        self.holding = holding
    }

    var body: some View {
        let state = store.data.holdingStateNow(holding, current: store.now, today: store.today)
        let figures = HoldingFigures(state)
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                valueRow(figures)
                FigureRow {
                    StatTile(title: "Ingelegd", value: Fmt.euro(figures.invested))
                    if figures.showsGain {
                        StatTile(title: "Winst", value: Fmt.euro(figures.gain),
                                 color: figures.gain >= 0 ? Theme.positive : Theme.negative)
                    }
                }
                if holding.hasTicker {
                    trackedInfo
                }
            }
        } header: {
            SectionHeader(holding.kind.title, symbol: holding.kind.symbol, domain: .investing)
        }
    }

    private func valueRow(_ figures: HoldingFigures) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                amountBlock(figures)
                Spacer(minLength: 8)
                gainBadge(figures)
            }
            VStack(alignment: .leading, spacing: 6) {
                amountBlock(figures)
                gainBadge(figures)
            }
        }
    }

    private func amountBlock(_ figures: HoldingFigures) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BigAmount(value: figures.value, label: "Waarde van \(holding.name)")
            if figures.isEstimated {
                Text("Geschat")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func gainBadge(_ figures: HoldingFigures) -> some View {
        if figures.showsGain {
            GainBadge(gain: figures.gain, fraction: figures.gainFraction)
        }
    }

    /// Het aantal en de koers, met wanneer de koers voor het laatst is opgehaald. Zonder aantal staat er wat er nog nodig is.
    @ViewBuilder
    private var trackedInfo: some View {
        let units = holding.units ?? 0
        FigureRow {
            StatTile(title: "Aantal", value: units > 0 ? Fmt.input(units, maxDigits: 6) : "–")
            StatTile(title: "Koers", value: holding.lastPrice.map { Fmt.euroExact($0) } ?? "–", caption: holding.ticker)
        }
        if !(units > 0) {
            Text(HoldingForm.unitsHint)
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        priceStatus
    }

    @ViewBuilder
    private var priceStatus: some View {
        if store.isRefreshingPrices {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Koers ophalen…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else if let date = holding.lastPriceDate {
            Text("Bijgewerkt \(Fmt.dateTime(date))")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Koers en waarde

/// De grafiek van de belegging: de waarde (afgeleid uit je inleg of uit je waarde-updates) en, met een ticker, de koers van het
/// afgelopen jaar. Bij elke ticker begint de koershistorie leeg; laden en een fout zijn lege staten met "Probeer opnieuw".
struct HoldingChartSection: View {
    let holding: Holding
    let onAction: (ChartEmpty.Action) -> Void
    @Environment(AppStore.self) private var store
    @State private var kind: ChartKind = .value
    @State private var history: [PricePoint] = []
    @State private var historyState: PriceTrend.LoadState = .loading

    /// Wat de grafiek toont.
    private enum ChartKind: String, CaseIterable, Identifiable {
        case value
        case price

        var id: String { rawValue }

        var title: String {
            switch self {
            case .value: return "Waarde"
            case .price: return "Koers"
            }
        }
    }

    init(holding: Holding, onAction: @escaping (ChartEmpty.Action) -> Void) {
        self.holding = holding
        self.onAction = onAction
    }

    var body: some View {
        // Zonder ticker is er geen koers: dan is er alleen de waarde.
        let shown: ChartKind = holding.hasTicker ? kind : .value
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if holding.hasTicker {
                    kindPicker(shown: shown)
                }
                chart(shown: shown)
            }
            .task(id: holding.ticker ?? "") { await loadHistory() }
        } header: {
            SectionHeader(holding.hasTicker ? "Koers en waarde" : "Waarde", symbol: "chart.xyaxis.line", domain: .investing)
        }
    }

    private func kindPicker(shown: ChartKind) -> some View {
        Picker("Grafiek", selection: Binding(get: { shown }, set: { kind = $0 })) {
            ForEach(ChartKind.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: shown)
    }

    @ViewBuilder
    private func chart(shown: ChartKind) -> some View {
        switch shown {
        case .price:
            TrendChart(model: PriceTrend.model(history: history, ticker: holding.ticker ?? "", state: historyState),
                       size: .regular, onAction: { action in handlePriceAction(action) })
        case .value:
            TrendChart(model: PortfolioTrend.model(store.data, window: .all, current: store.now, today: store.today,
                                                   only: [holding.id]),
                       size: .regular, nonNegative: true, onAction: onAction)
        }
    }

    private func handlePriceAction(_ action: ChartEmpty.Action) {
        if action == .retry {
            Task { await loadHistory() }
        } else {
            onAction(action)
        }
    }

    /// Haalt de koers van het afgelopen jaar op. De oude koers verdwijnt eerst, zodat een mislukte poging nooit de koers van een
    /// vorige ticker laat staan.
    private func loadHistory() async {
        history = []
        guard holding.hasTicker, let ticker = holding.ticker else {
            historyState = .loaded
            return
        }
        historyState = .loading
        do {
            let points = try await store.priceHistory(ticker: ticker, range: "1y", interval: "1d")
            if Task.isCancelled { return }
            history = points
            historyState = .loaded
        } catch {
            if Task.isCancelled { return }
            history = []
            historyState = .failed(failureReason(error))
        }
    }

    private func failureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Er is geen internetverbinding."
            case .timedOut:
                return "De verbinding duurde te lang."
            default:
                break
            }
        }
        return PriceHistoryText.failure("Ophalen mislukt: \(error.localizedDescription)")
    }
}

// MARK: - Uitgangspunten

struct HoldingAssumptionsSection: View {
    let holding: Holding
    @Environment(AppStore.self) private var store
    @State private var backfillMessage: String?

    init(holding: Holding) {
        self.holding = holding
    }

    var body: some View {
        Section {
            FigureRow {
                StatTile(title: "Rendement per jaar", value: Fmt.percent(holding.expectedReturn))
                StatTile(title: "Kosten per jaar", value: Fmt.percent(holding.annualCost, digits: 2))
            }
            AmountRow(title: "Belegd sinds", value: Fmt.month(holding.startMonth))
            if holding.isTracked {
                backfill
            }
        } header: {
            SectionHeader("Uitgangspunten", symbol: "slider.horizontal.3", domain: .investing)
        }
    }

    @ViewBuilder
    private var backfill: some View {
        ActionButton(title: "Historie aanvullen", symbol: "clock.arrow.circlepath") {
            let id = holding.id
            Task { backfillMessage = await store.backfillHistory(holdingID: id) }
        }
        if let backfillMessage {
            Text(backfillMessage)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        Text("Historie aanvullen neemt aan dat je het afgelopen jaar evenveel stuks had als nu.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Inleg

struct HoldingContributionSection: View {
    let holding: Holding
    let onEdit: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    init(holding: Holding, onEdit: @escaping () -> Void) {
        self.holding = holding
        self.onEdit = onEdit
    }

    var body: some View {
        // De opbouw van de maandelijkse inleg (een bedrag of een percentage van je inkomen), uit de rekenmotor.
        let info = ContributionInfo(store.data, id: holding.id, month: store.now)
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if let info {
                    ContributionSummary(info: info)
                }
                if let note = info?.transferNote(to: "van je rekening naar deze belegging") {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ActionGroup {
                    ActionButton(title: "Bewerken", symbol: "pencil") { onEdit() }
                    // De inleg hoort bij deze maand: de verdeelpagina opent op de huidige maand.
                    ActionButton(title: "Verdelen", symbol: "square.split.2x2") {
                        router.showCurrentMonth(store.now)
                        router.open(.distribute)
                    }
                }
            }
        } header: {
            SectionHeader("Inleg", symbol: "calendar", domain: .investing)
        }
    }
}

// MARK: - Waarde-updates

/// De waarde-updates van de belegging, de nieuwste eerst. Swipe en contextmenu verwijderen een update.
struct HoldingUpdatesSection: View {
    let holding: Holding
    let onValueUpdate: () -> Void
    @Environment(AppStore.self) private var store

    init(holding: Holding, onValueUpdate: @escaping () -> Void) {
        self.holding = holding
        self.onValueUpdate = onValueUpdate
    }

    var body: some View {
        let snapshots = Array(holding.snapshots.sorted { $0.date > $1.date }.prefix(24))
        Section {
            if snapshots.isEmpty {
                Text("Nog geen waarde-updates. Werk de waarde bij of ververs de koers.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(snapshots) { snapshot in
                updateRow(snapshot)
            }
            if !holding.isTracked {
                ActionButton(title: "Waarde bijwerken", symbol: "arrow.triangle.2.circlepath") { onValueUpdate() }
            }
        } header: {
            SectionHeader("Waarde-updates", symbol: "list.bullet.rectangle", domain: .investing)
        }
    }

    private func updateRow(_ snapshot: ValueSnapshot) -> some View {
        AmountRow(title: Fmt.date(snapshot.date), value: Fmt.euro(snapshot.value),
                  detail: "Ingelegd \(Fmt.euro(snapshot.invested))")
            .rowActions(delete: {
                let hid = holding.id
                let sid = snapshot.id
                store.mutate { $0.deleteSnapshot(holdingID: hid, snapshotID: sid) }
            })
    }
}

// MARK: - Verwijderen

/// Onderaan de pagina, rood, met de bevestiging aan de knop zelf.
struct HoldingDeleteSection: View {
    let holding: Holding
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(holding: Holding) {
        self.holding = holding
    }

    var body: some View {
        Section {
            ActionButton(title: "Belegging verwijderen", symbol: "trash", role: .destructive) { confirmDelete = true }
                .modifier(HoldingDeleteDialog(holding: holding, isPresented: $confirmDelete, onDeleted: { dismiss() }))
        }
    }
}
