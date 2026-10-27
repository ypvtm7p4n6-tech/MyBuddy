import SwiftUI

// De planken Spaarpotten en Beleggingen op Home. Ze tonen de gekozen potten (`homePots()`, hoogstens 3, met lege plekken) en
// beleggingen (`homeHoldings()`, hoogstens 4, met vooraan een samenvattingstegel), met dezelfde keuze, bladen en acties als de oude
// kaarten (K9a t/m K9c): het plankmenu "…" heeft "Kies potten…", "Nieuwe spaarpot", "Kies beleggingen…", "Belegging toevoegen" en
// "Koersen vernieuwen". Het contextmenu van een tegel (lang indrukken) heeft de acties van de detailpagina; verwijderen blijft daar.

// MARK: - Spaarpotten

/// Eén tegel op de plank Spaarpotten: een gekozen pot, een lege plek of (zonder potten) de lege staat.
struct HomePotItem: Identifiable {
    enum Kind {
        case pot(Pot)
        case slot(FavoritePicker.SlotAction)
        case empty
    }

    let id: String
    let kind: Kind

    /// De tegels bij de gekozen potten, met lege plekken tot er drie zijn. Zonder potten alleen de lege staat. Een lege plek kiest
    /// een pot zolang er een is die nog niet gekozen is, en maakt anders een nieuwe pot.
    static func items(chosen: [Pot], available: Int) -> [HomePotItem] {
        if available == 0 {
            return [HomePotItem(id: "empty", kind: .empty)]
        }
        var list: [HomePotItem] = []
        for pot in chosen {
            list.append(HomePotItem(id: "pot-" + pot.id.uuidString, kind: .pot(pot)))
        }
        let slots = FavoritePicker.emptySlots(chosen: chosen.count)
        let action = FavoritePicker.slotAction(chosen: chosen.count, available: available)
        for index in 0..<slots {
            list.append(HomePotItem(id: "slot-\(index)", kind: .slot(action)))
        }
        return list
    }
}

/// De plank Spaarpotten: het totaal gespaard als ondertitel, de gekozen potten als tegels en het plankmenu.
struct HomePotsShelf: View {
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let items = HomePotItem.items(chosen: d.homePots(), available: d.pots.count)
        Shelf("Spaarpotten", subtitle: subtitle(d), showAll: .pots, showAllLabel: "Toon alle spaarpotten",
              actions: actions(hasPots: !d.pots.isEmpty), orderID: "pots", wide: d.pots.isEmpty, items: items) { item in
            HomePotTile(item: item, present: present)
        }
    }

    /// "Totaal € 3.200": het saldo van vandaag van alle potten. Zonder potten geen ondertitel.
    private func subtitle(_ d: FinanceData) -> String? {
        if d.pots.isEmpty { return nil }
        return "Totaal " + Fmt.euro(d.totalSaved(current: store.now, today: store.today))
    }

    private func actions(hasPots: Bool) -> [ShelfAction] {
        var list: [ShelfAction] = []
        if hasPots {
            list.append(ShelfAction("Kies potten…", symbol: "slider.horizontal.3") { present(.pickPots) })
        }
        list.append(ShelfAction("Nieuwe spaarpot", symbol: "plus") { present(.newPot) })
        return list
    }
}

private struct HomePotTile: View {
    let item: HomePotItem
    let present: HomePresent

    var body: some View {
        switch item.kind {
        case .pot(let pot):
            HomePotPoster(pot: pot, present: present)
        case .slot(let action):
            slotTile(action)
        case .empty:
            ShelfCard {
                EmptyHint(symbol: "tray", title: "Nog geen spaarpotten",
                          message: "Maak een pot voor je noodbuffer, een vakantie of een nieuwe laptop.",
                          actionTitle: "Nieuwe spaarpot", action: { present(.newPot) })
            }
        }
    }

    @ViewBuilder
    private func slotTile(_ action: FavoritePicker.SlotAction) -> some View {
        switch action {
        case .choose:
            HomeSlotTile(title: "Kies pot", symbol: "plus") { present(.pickPots) }
        case .create:
            HomeSlotTile(title: "Nieuwe pot", symbol: "plus") { present(.newPot) }
        }
    }
}

/// Een gekozen pot: tegel in de kleur van de pot met symbool, naam, het doel, het saldo van vandaag en de voortgang naar het
/// doel (dezelfde `potProgress` als op de pagina Spaarpotten en bij de pot zelf). Het contextmenu: Storten, Opnemen, Bewerken.
private struct HomePotPoster: View {
    let pot: Pot
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let balance = d.potBalanceNow(pot.id, current: store.now, today: store.today)
        let progress = d.potProgress(pot.id, current: store.now, today: store.today)
        PosterCard(symbol: pot.symbol, hue: Theme.hue(pot.colorIndex), title: pot.name, subtitle: goalText,
                   value: Fmt.euro(balance), progress: progress, destination: .pot(pot.id))
            .homeTileShape()
            .contextMenu {
                Button { present(.movePot(pot.id, .deposit)) } label: {
                    Label("Storten", systemImage: "plus.circle")
                }
                Button { present(.movePot(pot.id, .withdraw)) } label: {
                    Label("Opnemen", systemImage: "minus.circle")
                }
                Divider()
                Button { present(.editPot(pot.id)) } label: {
                    Label("Bewerken", systemImage: "pencil")
                }
            }
    }

    /// "Doel € 2.000", of "Geen doel".
    private var goalText: String {
        if let goal = pot.goalAmount, goal > 0 {
            return "Doel " + Fmt.euro(goal)
        }
        return "Geen doel"
    }
}

// MARK: - Beleggingen

/// Eén tegel op de plank Beleggingen: de samenvatting, een gekozen belegging of (zonder beleggingen) de lege staat.
struct HomeHoldingItem: Identifiable {
    enum Kind {
        case summary
        case holding(Holding)
        case empty
    }

    let id: String
    let kind: Kind

    /// De samenvattingstegel en de gekozen beleggingen. Zonder beleggingen alleen de lege staat.
    static func items(chosen: [Holding], available: Int) -> [HomeHoldingItem] {
        if available == 0 {
            return [HomeHoldingItem(id: "empty", kind: .empty)]
        }
        var list: [HomeHoldingItem] = [HomeHoldingItem(id: "summary", kind: .summary)]
        for holding in chosen {
            list.append(HomeHoldingItem(id: "holding-" + holding.id.uuidString, kind: .holding(holding)))
        }
        return list
    }
}

/// De plank Beleggingen: de waarde als ondertitel, vooraan een samenvattingstegel met winst en verloop, daarna de gekozen
/// beleggingen, en het plankmenu met ook "Koersen vernieuwen" zolang er een belegging met koers is.
struct HomeHoldingsShelf: View {
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let items = HomeHoldingItem.items(chosen: d.homeHoldings(), available: d.holdings.count)
        Shelf("Beleggingen", subtitle: subtitle(d), showAll: .portfolio, showAllLabel: "Toon alle beleggingen",
              actions: actions(hasHoldings: !d.holdings.isEmpty), orderID: "invest", wide: d.holdings.isEmpty,
              items: items) { item in
            HomeHoldingTile(item: item, present: present)
        }
    }

    /// "Waarde € 12.345", met "(geschat)" erachter als alle waarden uit je inleg komen. Zonder beleggingen geen ondertitel.
    private func subtitle(_ d: FinanceData) -> String? {
        if d.holdings.isEmpty { return nil }
        let figures = PortfolioFigures(d, current: store.now, today: store.today)
        return "Waarde " + Fmt.euro(figures.value) + (figures.isEstimated ? " (geschat)" : "")
    }

    private func actions(hasHoldings: Bool) -> [ShelfAction] {
        var list: [ShelfAction] = []
        if hasHoldings {
            list.append(ShelfAction("Kies beleggingen…", symbol: "slider.horizontal.3") { present(.pickHoldings) })
        }
        list.append(ShelfAction("Belegging toevoegen", symbol: "plus") { present(.newHolding) })
        if store.hasTrackedHoldings {
            let title = store.isRefreshingPrices ? "Koersen worden vernieuwd…" : "Koersen vernieuwen"
            list.append(ShelfAction(title, symbol: "arrow.clockwise") {
                Task { await store.refreshPrices(force: true) }
            })
        }
        return list
    }
}

private struct HomeHoldingTile: View {
    let item: HomeHoldingItem
    let present: HomePresent

    var body: some View {
        switch item.kind {
        case .summary:
            HomeHoldingsSummary()
        case .holding(let holding):
            HomeHoldingPoster(holding: holding, present: present)
        case .empty:
            ShelfCard {
                EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                          message: "Voeg een ETF, aandeel of crypto toe. Koersen worden live opgehaald.",
                          actionTitle: "Belegging toevoegen", action: { present(.newHolding) })
            }
        }
    }
}

/// De samenvattingstegel: de waarde van al je beleggingen, de winst met pijltje en teken, en het verloop over 6 maanden als kleine
/// grafiek in een donker paneel. Cijfers uit `PortfolioFigures` en `PortfolioTrend`. De tegel is een link naar Beleggingen en voor
/// VoiceOver één element; staat er niets te tekenen, dan blijft de grafiek weg (de pagina Beleggingen legt het uit).
private struct HomeHoldingsSummary: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let figures = PortfolioFigures(d, current: now, today: today)
        let model = PortfolioTrend.model(d, window: .sixMonths, current: now, today: today)
        ShelfCard(hue: .slate, destination: .portfolio) {
            VStack(alignment: .leading, spacing: 6) {
                Text(figures.isEstimated ? "Waarde, geschat" : "Waarde")
                    .font(.footnote)
                    .foregroundStyle(Theme.onTileSecondary)
                BigAmount(value: figures.value, font: Theme.titleAmount, color: Theme.onTile, label: "Waarde van je beleggingen")
                if figures.showsGain {
                    HomeGainLine(gain: figures.gain, fraction: figures.gainFraction)
                }
                Spacer(minLength: 0)
                if model.empty == nil {
                    TrendChart(model: model, size: .compact, showsAxes: false, nonNegative: true)
                        .heroPanel()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel(figures))
        }
    }

    /// "Beleggingen, waarde € 12.345, winst € 120, 3,1%".
    private func spokenLabel(_ figures: PortfolioFigures) -> String {
        var parts: [String] = ["Beleggingen", (figures.isEstimated ? "geschatte waarde " : "waarde ") + Fmt.euro(figures.value)]
        if figures.showsGain {
            let word = figures.gain >= 0 ? "winst " : "verlies "
            var text = word + Fmt.euro(abs(figures.gain))
            if let fraction = figures.gainFraction { text += ", " + Fmt.percent(abs(fraction), digits: 1) }
            parts.append(text)
        }
        return parts.joined(separator: ", ")
    }
}

/// Winst of verlies in euro's met pijltje, teken en (als die er is) het percentage, in de tekstkleur van een tegel: het teken en
/// het pijltje dragen de betekenis, nooit groen of rood op een tegel.
private struct HomeGainLine: View {
    let gain: Double
    let fraction: Double?

    var body: some View {
        let positive = gain >= 0
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .accessibilityHidden(true)
            Text(shownText(positive: positive))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.onTile)
    }

    /// "+€ 120 (3,1%)" of "−€ 80 (2,0%)", zoals `GainBadge`.
    private func shownText(positive: Bool) -> String {
        var text = (positive ? "+" : "−") + Fmt.euro(abs(gain))
        if let fraction { text += " (" + Fmt.percent(abs(fraction), digits: 1) + ")" }
        return text
    }
}

/// Een gekozen belegging: tegel in de kleur van de soort met symbool, naam, de soort (met "geschat" als de waarde uit je inleg
/// komt) en de waarde van nu. Het contextmenu: Waarde bijwerken, Bewerken.
private struct HomeHoldingPoster: View {
    let holding: Holding
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        let state = store.data.holdingStateNow(holding, current: store.now, today: store.today)
        let figures = HoldingFigures(state)
        PosterCard(symbol: holding.kind.symbol, hue: Theme.hue(holding.kind.colorIndex), title: holding.name,
                   subtitle: figures.isEstimated ? "\(holding.kind.title) · geschat" : holding.kind.title,
                   value: Fmt.euro(figures.value), destination: .holding(holding.id))
            .homeTileShape()
            .contextMenu {
                Button { present(.updateValue(holding.id)) } label: {
                    Label("Waarde bijwerken", systemImage: "arrow.triangle.2.circlepath")
                }
                Divider()
                Button { present(.editHolding(holding.id)) } label: {
                    Label("Bewerken", systemImage: "pencil")
                }
            }
    }
}
