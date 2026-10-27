import SwiftUI

// De pagina van één belegging als albumpagina (Apple Muziek, ontwerp 2): een kop met het artwork, de waarde, de winst en de acties
// als eerste rij van de lijst, daaronder de bestaande secties: Koers en waarde (de grafiek), Samenvatting, Uitgangspunten, Inleg en
// Waarde-updates (de tracklijst), met onderaan Verwijderen. De secties staan in HoldingChartSection.swift en
// HoldingDetailSections.swift.

struct HoldingDetailPage: View {
    let holdingID: UUID
    @Environment(AppStore.self) private var store
    @State private var sheet: HoldingDetailSheet?

    /// De bladen die deze pagina opent, via een blad-item.
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
            Section {
                HoldingAlbumHeader(holding: holding, onEdit: { sheet = .edit }, onValueUpdate: { sheet = .value })
                    .albumHeaderRow()
            }
            HoldingChartSection(holding: holding, onAction: { action in handle(action) })
            HoldingSummarySection(holding: holding)
            HoldingAssumptionsSection(holding: holding)
            HoldingContributionSection(holding: holding, onEdit: { sheet = .edit })
            HoldingUpdatesSection(holding: holding, onValueUpdate: { sheet = .value })
            HoldingDeleteSection(holding: holding)
        }
        .environment(\.backdropHue, Theme.hue(holding.kind.colorIndex))
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

    /// "Bewerken", "Waarde bijwerken" (zonder koers) en "Koers vernieuwen" (met een ticker) in het menu van de werkbalk: dezelfde
    /// acties als de pillen in de kop.
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

// MARK: - De kop van het album

/// De kop van de belegging: een groot artwork in de kleur van de soort, de naam, de soort met de ticker, de waarde van nu, de
/// winst (`GainBadge`), de feiten (sinds wanneer, geschat, inleg) en de pillen. De hoofdactie is Waarde bijwerken, of bij een
/// belegging die haar koers volgt Koers vernieuwen; daarnaast Bewerken. Dezelfde acties staan in het menu van de werkbalk.
struct HoldingAlbumHeader: View {
    let holding: Holding
    let onEdit: () -> Void
    let onValueUpdate: () -> Void
    @Environment(AppStore.self) private var store

    init(holding: Holding, onEdit: @escaping () -> Void, onValueUpdate: @escaping () -> Void) {
        self.holding = holding
        self.onEdit = onEdit
        self.onValueUpdate = onValueUpdate
    }

    var body: some View {
        let state = store.data.holdingStateNow(holding, current: store.now, today: store.today)
        let figures = HoldingFigures(state)
        let info = ContributionInfo(store.data, id: holding.id, month: store.now)
        AlbumHeader(symbol: holding.kind.symbol, hue: Theme.hue(holding.kind.colorIndex), title: holding.name,
                    subtitle: SavingAlbumText.holdingSubtitle(kind: holding.kind.title,
                                                              ticker: holding.hasTicker ? holding.ticker : nil),
                    figureLabel: "Waarde", figure: figures.value,
                    facts: SavingAlbumText.holdingFacts(startMonth: holding.startMonth, isEstimated: figures.isEstimated,
                                                        contribution: SavingAlbumText.contributionFact(info)),
                    pills: {
                        pills
                    },
                    extra: {
                        gainBadge(figures)
                    })
    }

    @ViewBuilder
    private func gainBadge(_ figures: HoldingFigures) -> some View {
        if figures.showsGain {
            GainBadge(gain: figures.gain, fraction: figures.gainFraction)
        }
    }

    @ViewBuilder
    private var pills: some View {
        if !holding.isTracked {
            PillButton("Waarde bijwerken", symbol: "arrow.triangle.2.circlepath", style: .prominent) { onValueUpdate() }
        }
        if holding.hasTicker {
            refreshPill
        }
        PillButton("Bewerken", symbol: "pencil") { onEdit() }
    }

    /// Koers vernieuwen: de hoofdactie van een belegging die haar koers volgt, anders een gewone pil. Tijdens het ophalen is hij uit.
    private var refreshPill: some View {
        PillButton(store.isRefreshingPrices ? "Koers ophalen…" : "Koers vernieuwen", symbol: "arrow.clockwise",
                   style: holding.isTracked ? .prominent : .secondary) {
            Task { await store.refreshPrices(force: true) }
        }
        .disabled(store.isRefreshingPrices)
    }
}
