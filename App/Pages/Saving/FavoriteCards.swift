import SwiftUI

// De vier kaarten van Sparen en het Overzicht: `HomePotsCard` en `HomeHoldingsCard` (Overzicht), `PotsSummaryCard` en
// `PortfolioSummaryCard` (Sparen). Ze lezen hun gegevens zelf uit `AppStore` en `Router`, hebben een lege `init()`, hun eigen bladen
// en hun eigen lege staat. Beide kaarten van een soort tonen dezelfde gekozen tegels (K9a t/m K9c); de Sparen-kaart van de potten
// toont daarnaast de voortgang naar het totale doel.

// MARK: - Spaarpotten

/// De kaart "Spaarpotten" op het Overzicht: totaal gespaard, de gekozen potten als tegels (met een lege plek zolang er minder dan drie
/// zijn), een kaartmenu "Kies potten…" en een link naar alle spaarpotten.
struct HomePotsCard: View {
    init() {}

    var body: some View {
        FavoritePotsCard(showsGoal: false)
    }
}

/// De kaart "Spaarpotten" op Sparen: dezelfde tegels en hetzelfde totaal, met de voortgang naar het totale doel.
struct PotsSummaryCard: View {
    init() {}

    var body: some View {
        FavoritePotsCard(showsGoal: true)
    }
}

private struct FavoritePotsCard: View {
    let showsGoal: Bool
    @Environment(AppStore.self) private var store
    @State private var sheet: PotsCardSheet?

    /// De bladen die deze kaart opent, in een `.sheet(item:)`.
    private enum PotsCardSheet: Identifiable {
        case newPot
        case pickPots

        var id: String {
            switch self {
            case .newPot: return "new"
            case .pickPots: return "pick"
            }
        }
    }

    var body: some View {
        let d = store.data
        Card(title: "Spaarpotten", domain: .saving) {
            if d.pots.isEmpty {
                EmptyHint(symbol: "tray", title: "Nog geen spaarpotten",
                          message: "Maak een pot voor je noodbuffer, een vakantie of een nieuwe laptop.",
                          actionTitle: "Nieuwe spaarpot", action: { sheet = .newPot })
            } else {
                filled(d)
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
    }

    @ViewBuilder
    private func filled(_ d: FinanceData) -> some View {
        let now = store.now
        let today = store.today
        let chosen = d.homePots()
        headerRow(saved: d.totalSaved(current: now, today: today))
        if showsGoal {
            PotsGoalProgress(goal: d.totalGoal(), towardGoals: d.savedTowardGoals(current: now, today: today))
        }
        tiles(chosen: chosen, available: d.pots.count)
        ActionLink(title: "Alle spaarpotten", symbol: "tray.full", destination: .pots)
    }

    /// Het totaal gespaard (het saldo van vandaag) met het kaartmenu ernaast.
    private func headerRow(saved: Double) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Totaal gespaard")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                BigAmount(value: saved, font: Theme.titleAmount, label: "Totaal gespaard")
            }
            Spacer(minLength: 8)
            SavingCardMenu(title: "Meer opties voor spaarpotten") {
                Button { sheet = .pickPots } label: {
                    Label("Kies potten…", systemImage: "slider.horizontal.3")
                }
                Button { sheet = .newPot } label: {
                    Label("Nieuwe spaarpot", systemImage: "plus")
                }
            }
        }
    }

    /// De gekozen potten; een lege plek kiest een pot zolang er een is die nog niet gekozen is, en maakt anders een nieuwe pot.
    private func tiles(chosen: [Pot], available: Int) -> some View {
        let slots = FavoritePicker.emptySlots(chosen: chosen.count)
        let action = FavoritePicker.slotAction(chosen: chosen.count, available: available)
        return FavoriteTileGrid {
            ForEach(chosen) { pot in
                FavoritePotTile(pot: pot)
            }
            ForEach(0..<slots, id: \.self) { _ in
                slotTile(action)
            }
        }
    }

    @ViewBuilder
    private func slotTile(_ action: FavoritePicker.SlotAction) -> some View {
        switch action {
        case .choose:
            FavoriteSlotTile(title: "Kies pot", symbol: "plus") { sheet = .pickPots }
        case .create:
            FavoriteSlotTile(title: "Nieuwe pot", symbol: "plus") { sheet = .newPot }
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: PotsCardSheet) -> some View {
        switch item {
        case .newPot: PotEditSheet(pot: nil)
        case .pickPots: FavoritePotsSheet()
        }
    }
}

// MARK: - Beleggingen

/// De kaart "Beleggingen" op het Overzicht: waarde en winst, een kleine grafiek met begin en eind als tekst, de gekozen beleggingen
/// als tegels, een kaartmenu "Kies beleggingen…" en een link naar alle beleggingen.
struct HomeHoldingsCard: View {
    init() {}

    var body: some View {
        FavoriteHoldingsCard()
    }
}

/// De kaart "Beleggingen" op Sparen: dezelfde waarde, grafiek en tegels als op het Overzicht.
struct PortfolioSummaryCard: View {
    init() {}

    var body: some View {
        FavoriteHoldingsCard()
    }
}

private struct FavoriteHoldingsCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var sheet: HoldingsCardSheet?

    /// De bladen die deze kaart opent, in een `.sheet(item:)`.
    private enum HoldingsCardSheet: Identifiable {
        case newHolding
        case pickHoldings

        var id: String {
            switch self {
            case .newHolding: return "new"
            case .pickHoldings: return "pick"
            }
        }
    }

    var body: some View {
        let d = store.data
        Card(title: "Beleggingen", domain: .investing) {
            if d.holdings.isEmpty {
                EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                          message: "Voeg een ETF, aandeel of crypto toe. Koersen worden live opgehaald.",
                          actionTitle: "Belegging toevoegen", action: { sheet = .newHolding })
            } else {
                filled(d)
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
    }

    @ViewBuilder
    private func filled(_ d: FinanceData) -> some View {
        let now = store.now
        let today = store.today
        let figures = PortfolioFigures(d, current: now, today: today)
        let model = PortfolioTrend.model(d, window: .sixMonths, current: now, today: today)
        headerRow(figures)
        sparkline(model)
        FavoriteTileGrid(wide: true) {
            ForEach(d.homeHoldings()) { holding in
                FavoriteHoldingTile(holding: holding)
            }
        }
        ActionLink(title: "Alle beleggingen", symbol: "chart.line.uptrend.xyaxis", destination: .portfolio)
    }

    /// De waarde van nu (met "Geschat" of de winst eronder) en het kaartmenu ernaast.
    private func headerRow(_ figures: PortfolioFigures) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Waarde")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                BigAmount(value: figures.value, font: Theme.titleAmount, label: "Waarde van je beleggingen")
                if figures.isEstimated {
                    Text("Geschat")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                if figures.showsGain {
                    GainBadge(gain: figures.gain, fraction: figures.gainFraction)
                }
            }
            Spacer(minLength: 8)
            SavingCardMenu(title: "Meer opties voor beleggingen") {
                Button { sheet = .pickHoldings } label: {
                    Label("Kies beleggingen…", systemImage: "slider.horizontal.3")
                }
                Button { sheet = .newHolding } label: {
                    Label("Belegging toevoegen", systemImage: "plus")
                }
                if store.hasTrackedHoldings {
                    Button {
                        Task { await store.refreshPrices(force: true) }
                    } label: {
                        Label("Koersen vernieuwen", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshingPrices)
                }
            }
        }
    }

    /// De kleine grafiek zonder assen met het begin en het eind als tekst. Is er niets te tekenen, dan is het een regel met een knop.
    private func sparkline(_ model: TrendModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TrendChart(model: model, size: .compact, showsAxes: false, nonNegative: true,
                       onAction: { action in handle(action) })
            if let glance = TrendGlance(model) {
                glanceRow(glance)
            }
        }
    }

    private func glanceRow(_ glance: TrendGlance) -> some View {
        HStack {
            if let start = glance.start {
                Text(start)
            }
            Spacer(minLength: 8)
            Text(glance.end)
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
    }

    /// De knop in de lege staat van de kleine grafiek: invullen kan op de pagina van de belegging.
    private func handle(_ action: ChartEmpty.Action) {
        switch action {
        case .addHolding:
            sheet = .newHolding
        case .enterValue(let id):
            router.open(.holding(id))
        case .enterUnits(let id):
            router.open(.holding(id))
        case .refreshPrices:
            Task { await store.refreshPrices(force: true) }
        case .retry, .enterBankBalance, .openSalary:
            break
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: HoldingsCardSheet) -> some View {
        switch item {
        case .newHolding: HoldingEditSheet(holding: nil)
        case .pickHoldings: FavoriteHoldingsSheet()
        }
    }
}
