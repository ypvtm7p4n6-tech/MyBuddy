import SwiftUI

// Alle beleggingen (lijstpagina): Samenvatting, Groei, Verdeling en de beleggingen zelf. De pagina van één belegging staat in
// Saving/HoldingDetailPage.swift, de bladen in Saving/HoldingSheets.swift en de kaarten in Saving/FavoriteCards.swift. De cijfers
// bovenaan (`PortfolioFigures`) en de teksten van het formulier (`HoldingForm`) staan zonder SwiftUI in App/UI/PotDisplay.swift.

// MARK: - Winst of verlies

/// Winst of verlies in euro's, met pijltje, teken en (als die er is) het percentage.
struct GainBadge: View {
    let gain: Double
    let fraction: Double?

    init(gain: Double, fraction: Double?) {
        self.gain = gain
        self.fraction = fraction
    }

    var body: some View {
        let positive = gain >= 0
        HStack(spacing: 4) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .accessibilityHidden(true)
            Text(shownText(positive: positive))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(positive ? Theme.positive : Theme.negative)
        .animated(by: gain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText(positive: positive))
    }

    /// "+€ 120 (3,1%)" of "−€ 80 (2,0%)".
    private func shownText(positive: Bool) -> String {
        var text = (positive ? "+" : "−") + Fmt.euro(abs(gain))
        if let fraction { text += " (\(Fmt.percent(abs(fraction), digits: 1)))" }
        return text
    }

    /// "Winst 120 euro, 3,1%" of "Verlies 80 euro, 2,0%".
    private func spokenText(positive: Bool) -> String {
        var text = (positive ? "Winst " : "Verlies ") + ChartText.euro(abs(gain))
        if let fraction { text += ", \(Fmt.percent(abs(fraction), digits: 1))" }
        return text
    }
}

// MARK: - Een belegging verwijderen

/// De bevestiging bij het verwijderen van een belegging, aan de rij of de knop waar je verwijdert (DLG-4). Wat de belegging nu waard
/// is, verdwijnt uit je vermogen: dat moet je vooraf zien.
struct HoldingDeleteDialog: ViewModifier {
    let holding: Holding
    @Binding var isPresented: Bool
    let onDeleted: () -> Void
    @Environment(AppStore.self) private var store

    init(holding: Holding, isPresented: Binding<Bool>, onDeleted: @escaping () -> Void = {}) {
        self.holding = holding
        self._isPresented = isPresented
        self.onDeleted = onDeleted
    }

    private var currentValue: Double {
        store.data.holdingStateNow(holding, current: store.now, today: store.today)?.value ?? 0
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Deze belegging verwijderen?", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Verwijder \(holding.name)", role: .destructive) {
                    let id = holding.id
                    store.mutate { $0.deleteHolding(id) }
                    onDeleted()
                }
                Button("Annuleer", role: .cancel) {}
            } message: {
                if CentsMath.int(currentValue) > 0 {
                    Text("De waarde van \(Fmt.euro(currentValue)) verdwijnt uit je vermogen. Ook de waarde-updates en de geplande inleg verdwijnen.")
                } else {
                    Text("Ook de waarde-updates en de geplande inleg verdwijnen.")
                }
            }
    }
}

// MARK: - Beleggingen

struct PortfolioPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var sheet: PortfolioSheet?
    /// Hoe ver de grafiek terugkijkt. Een keuze die (nog) niets verandert valt terug op "Alles".
    @State private var chosenWindow: PortfolioWindow = .year

    /// De bladen die deze pagina opent, via een blad-item.
    private enum PortfolioSheet: Identifiable {
        case newHolding
        case editHolding(Holding)
        case valueUpdate(Holding)
        case pickFavorites

        var id: String {
            switch self {
            case .newHolding: return "new"
            case .editHolding(let holding): return "edit-" + holding.id.uuidString
            case .valueUpdate(let holding): return "value-" + holding.id.uuidString
            case .pickFavorites: return "favorites"
            }
        }
    }

    var body: some View {
        let d = store.data
        ListScaffold(title: "Beleggingen") {
            if let message = store.priceMessage {
                noticeSection(message)
            }
            if d.holdings.isEmpty {
                emptySection
            } else {
                PortfolioSummarySection()
                PortfolioGrowthSection(window: $chosenWindow, onAction: { action in handle(action) })
                PortfolioKindsSection()
                holdingsSection(d.holdings)
            }
        }
        .refreshable { await store.refreshPrices(force: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                IconButton("Belegging toevoegen", symbol: "plus") { sheet = .newHolding }
            }
            if !d.holdings.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    moreMenu
                }
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
    }

    private func noticeSection(_ message: String) -> some View {
        Section {
            NoticeCard(text: message, symbol: "wifi.exclamationmark")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    private var emptySection: some View {
        Section {
            EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                      message: "Voeg een ETF, aandeel, crypto of spaarrekening toe.",
                      actionTitle: "Belegging toevoegen", action: { sheet = .newHolding })
        }
    }

    private func holdingsSection(_ holdings: [Holding]) -> some View {
        Section {
            ForEach(holdings) { holding in
                HoldingRow(holding: holding, onEdit: { sheet = .editHolding(holding) })
            }
        } header: {
            SectionHeader("Beleggingen", domain: .investing)
        }
    }

    /// "Koersen vernieuwen" (alleen met een gevolgde belegging, ook met trekken om te verversen) en "Kies beleggingen voor het Overzicht…".
    private var moreMenu: some View {
        Menu {
            if store.hasTrackedHoldings {
                Button {
                    Task { await store.refreshPrices(force: true) }
                } label: {
                    Label("Koersen vernieuwen", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshingPrices)
            }
            Button { sheet = .pickFavorites } label: {
                Label("Kies beleggingen voor het Overzicht…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("Meer", systemImage: "ellipsis")
        }
        .help("Meer")
    }

    @ViewBuilder
    private func sheetContent(_ item: PortfolioSheet) -> some View {
        switch item {
        case .newHolding: HoldingEditSheet(holding: nil)
        case .editHolding(let holding): HoldingEditSheet(holding: holding)
        case .valueUpdate(let holding): ValueUpdateSheet(holding: holding)
        case .pickFavorites: FavoriteHoldingsSheet()
        }
    }

    /// De knop in de lege staat van de grafiek: elke actie heeft een plek om de gegevens in te vullen.
    private func handle(_ action: ChartEmpty.Action) {
        switch action {
        case .addHolding:
            sheet = .newHolding
        case .enterValue(let id):
            if let holding = store.data.holding(id) { sheet = .valueUpdate(holding) }
        case .enterUnits(let id):
            if let holding = store.data.holding(id) { sheet = .editHolding(holding) }
        case .refreshPrices:
            Task { await store.refreshPrices(force: true) }
        case .retry:
            break
        case .enterBankBalance:
            router.go(.bank)
        case .openSalary:
            router.go(.salary)
        }
    }
}

// MARK: - Samenvatting

/// Waarde, ingelegd en winst van nu. Zijn alle beleggingen geschat uit je inleg, dan staat er "Geschat" bij het bedrag en zijn Winst
/// en het percentage verborgen.
struct PortfolioSummarySection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        // Wat je nu hebt, per kalenderdag (zoals de bank en de spaarpotten): een inleg die nog moet worden overgeschreven telt pas
        // mee vanaf zijn overschrijfdag. Het laatste echte punt van de grafiek is hetzelfde getal.
        let figures = PortfolioFigures(d, current: now, today: store.today)
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                valueRow(figures)
                FigureRow {
                    StatTile(title: "Ingelegd", value: Fmt.euro(figures.invested))
                    if figures.showsGain {
                        StatTile(title: "Winst", value: Fmt.euro(figures.gain),
                                 color: figures.gain >= 0 ? Theme.positive : Theme.negative)
                    }
                    // Wat je verdeling deze maand naar beleggingen stuurt: dezelfde som als "Belegd" op de Maand-tab en bij Verdelen.
                    StatTile(title: "Inleg deze maand", value: Fmt.euro(d.investedTotal(in: now)))
                }
                Text("De waarde is je laatste waarde-update plus de inleg die al is overgeschreven, zoals bij je bankrekening en spaarpotten. Een inleg die nog moet komen telt mee vanaf de overschrijfdag; \"Inleg deze maand\" is de hele maand.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                priceStatus
            }
        } header: {
            SectionHeader("Samenvatting", domain: .investing)
        }
    }

    private func valueRow(_ figures: PortfolioFigures) -> some View {
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

    private func amountBlock(_ figures: PortfolioFigures) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BigAmount(value: figures.value, label: "Waarde van je beleggingen")
            if figures.isEstimated {
                Text("Geschat")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func gainBadge(_ figures: PortfolioFigures) -> some View {
        if figures.showsGain {
            GainBadge(gain: figures.gain, fraction: figures.gainFraction)
        }
    }

    /// Wanneer de koersen voor het laatst zijn opgehaald, of dat dat nu gebeurt.
    @ViewBuilder
    private var priceStatus: some View {
        if store.hasTrackedHoldings {
            HStack(spacing: 8) {
                if store.isRefreshingPrices {
                    ProgressView().controlSize(.small)
                    Text("Koersen ophalen…")
                } else {
                    Image(systemName: "bolt.horizontal.fill")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(store.lastPriceRefresh.map { "Koersen bijgewerkt \(Fmt.dateTime($0))" } ?? "Koersen worden bij het openen opgehaald")
                }
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Groei

/// De grafiek van de waarde, met de keuzebalk 6 mnd, 1 jaar, 3 jaar en Alles. De balk staat er alleen als hij iets verandert. Zonder
/// waarde-update tekent de grafiek de lijn uit je inleg, met het onderschrift "Geschat uit je inleg, zonder rendement.". Is er
/// niets te tekenen, dan staat er een lege staat met een knop die het invullen oplost.
struct PortfolioGrowthSection: View {
    @Binding var window: PortfolioWindow
    let onAction: (ChartEmpty.Action) -> Void
    @Environment(AppStore.self) private var store

    init(window: Binding<PortfolioWindow>, onAction: @escaping (ChartEmpty.Action) -> Void) {
        self._window = window
        self.onAction = onAction
    }

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let available = PortfolioTrend.availableMonths(d, current: now, today: today)
        let options = PortfolioWindow.options(availableMonths: available)
        let effective = PortfolioWindow.effective(window, availableMonths: available)
        let model = PortfolioTrend.model(d, window: effective, current: now, today: today)
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if !options.isEmpty {
                    windowPicker(options: options, effective: effective)
                }
                TrendChart(model: model, size: .tall, nonNegative: true, onAction: onAction)
            }
        } header: {
            SectionHeader("Groei", symbol: "chart.line.uptrend.xyaxis", domain: .investing)
        }
    }

    private func windowPicker(options: [PortfolioWindow], effective: PortfolioWindow) -> some View {
        Picker("Terugkijken", selection: Binding(get: { effective }, set: { window = $0 })) {
            ForEach(options) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: effective)
    }
}

// MARK: - Verdeling

/// De verdeling over soorten, ook bij één soort: een ring met eronder de lijst met bedrag en percentage. Elke soort heeft overal
/// dezelfde kleur als in de rij.
struct PortfolioKindsSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let model = DonutModel.holdingKinds(store.data, current: store.now, today: store.today)
        Section {
            DonutChart(model: model, size: .regular)
        } header: {
            SectionHeader("Verdeling", symbol: "chart.pie", domain: .investing)
        }
    }
}

// MARK: - Een rij in de lijst

/// Een belegging in de lijst: naam, ticker en koers of soort, de inleg als die een percentage is, de waarde en de winst als
/// percentage (of "Geschat"). Swipe en contextmenu geven Bewerken en Verwijderen.
struct HoldingRow: View {
    let holding: Holding
    let onEdit: () -> Void
    @Environment(AppStore.self) private var store
    @State private var confirmDelete = false

    init(holding: Holding, onEdit: @escaping () -> Void) {
        self.holding = holding
        self.onEdit = onEdit
    }

    var body: some View {
        SavingLink(.holding(holding.id)) { rowLabel }
            .rowActions(edit: { onEdit() }, delete: { confirmDelete = true })
            .modifier(HoldingDeleteDialog(holding: holding, isPresented: $confirmDelete))
    }

    @ViewBuilder
    private var rowLabel: some View {
        let state = store.data.holdingStateNow(holding, current: store.now, today: store.today)
        let figures = HoldingFigures(state)
        HStack(alignment: .top, spacing: 12) {
            SymbolBadge(symbol: holding.kind.symbol, color: Theme.color(holding.kind.colorIndex), size: 40)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    texts
                    Spacer(minLength: 6)
                    amounts(figures)
                }
                VStack(alignment: .leading, spacing: 4) {
                    texts
                    amounts(figures)
                }
            }
            SavingChevron()
                .padding(.top, 4)
        }
        .foregroundStyle(Color.primary)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(holding.name)
                .font(.body.weight(.semibold))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            // Een inleg als percentage van je inkomen: wat het deze maand is (zoals bij een spaarpot).
            if let line = ContributionInfo.listLine(store.data, id: holding.id, month: store.now) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func amounts(_ figures: HoldingFigures) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Fmt.euro(figures.value))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animated(by: figures.value)
            if figures.isEstimated {
                Text("Geschat")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else if let fraction = figures.gainFraction {
                Text((fraction >= 0 ? "+" : "−") + Fmt.percent(abs(fraction)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(fraction >= 0 ? Theme.positive : Theme.negative)
            }
        }
    }

    private var subtitle: String {
        if holding.hasTicker, let ticker = holding.ticker {
            // De koers is een eenheidsprijs: met centen (een koers van 0,52 is geen "€ 1").
            if let price = holding.lastPrice { return "\(ticker) · \(Fmt.euroExact(price))" }
            return ticker
        }
        return holding.kind.title
    }
}
