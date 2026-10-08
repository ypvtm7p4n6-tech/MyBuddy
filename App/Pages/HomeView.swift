import SwiftUI

/// Tab 1: drie blokken (Overzicht, Spaarpotten, Beleggingen) onder "Nog te verdelen".
/// De volgorde van de blokken kan de gebruiker zelf kiezen (lang indrukken op een blok).
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            PageScaffold(title: "Home", showsSettings: true) {
                VStack(spacing: Theme.pageSpacing) {
                    if let notice = store.startupNotice {
                        NoticeBanner(text: notice, symbol: "exclamationmark.triangle.fill")
                    }
                    if store.data.isEmptyStart {
                        WelcomeBlock()
                    }
                    RemainingHeader()
                    EqualSizeGrid {
                        OrderedBlocks(page: .home) { id in homeBlock(id) }
                    }
                }
            }
            .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
        }
    }

    /// Het blok bij een blok-id (zie `BlockPage.home`).
    @ViewBuilder
    private func homeBlock(_ id: String) -> some View {
        switch id {
        case "overview": OverviewBlock()
        case "pots": PotsBlock()
        case "invest": InvestBlock()
        default: EmptyView()
        }
    }
}

struct NoticeBanner: View {
    let text: String
    var symbol = "info.circle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.warning)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .padding(Theme.cardInset)
        .glassCard(radius: Theme.cardRadius)
    }
}

// MARK: - Welkom

struct WelcomeBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        GlassBlock(title: "Welkom bij MyBuddy", symbol: "sparkles", tint: Theme.olive.opacity(0.3)) {
            Text("Begin met je salaris. Daarna maak je spaarpotten, voeg je beleggingen toe en verdeel je elke maand je geld.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ChipButton(title: "Salaris instellen", symbol: "eurosign.circle") {
                    router.showCurrentMonth(store.now)
                    router.open(.income)
                }
                ChipButton(title: "Voorbeelddata", symbol: "wand.and.stars") {
                    store.loadSampleData()
                }
            }
        }
    }
}

// MARK: - Nog te verdelen

struct RemainingHeader: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let m = store.now
        let left = d.remaining(in: m)
        let fromPots = d.expensesFromPots(in: m)
        // Dit blok gaat over de huidige maand, dus de verdeelpagina opent ook op de huidige maand.
        Button {
            router.showCurrentMonth(m)
            router.open(.distribute)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Nog te verdelen in \(Fmt.month(m))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                BigAmount(value: left, color: left < 0 ? Theme.negative : Color.primary)
                if left < 0 {
                    // De tekst volgt de oorzaak: te hoge uitgaven (bijvoorbeeld nog geen salaris) of te veel verdeeld.
                    let spending = RemainingShortfall.isSpending(income: d.income(in: m),
                                                                 bankExpenses: d.expensesFromBank(in: m))
                    Text(spending ? "Je uitgaven zijn hoger dan je inkomen deze maand."
                                  : "Je hebt meer verdeeld dan er over was deze maand.")
                        .font(.footnote)
                        .foregroundStyle(Theme.negative)
                } else {
                    HStack(spacing: 8) {
                        MiniFigure(title: "Inkomen", value: d.income(in: m))
                        MiniFigure(title: "Uitgaven", value: d.expensesTotal(in: m))
                        MiniFigure(title: "Verdeeld", value: d.savedTotal(in: m) + d.investedTotal(in: m))
                    }
                    // Uitgaven uit een spaarpot kosten dit maandbudget niets: zonder uitleg tellen de drie tegels niet op.
                    if fromPots > 0 {
                        Text("Waarvan \(Fmt.euro(fromPots)) uit een spaarpot. Dat telt niet mee in dit bedrag.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Theme.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: Theme.olive.opacity(0.35), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct MiniFigure: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(Fmt.euro(value))
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .tile()
    }
}

// MARK: - Blok 1: Overzicht

struct FlowLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<FlowChart.kinds.count, id: \.self) { i in
                HStack(spacing: 4) {
                    Circle().fill(FlowChart.colors[i]).frame(width: 7, height: 7)
                    Text(FlowChart.kinds[i]).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct OverviewBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let months = d.summaries(from: now.adding(-4), count: 6, current: now)
        let worth = d.netWorth(at: now, current: now)
        // Dezelfde som als "Nog te verdelen" bovenaan Home.
        let left = d.remaining(in: now)
        // Een tik opent het overzicht altijd op deze maand, niet op de maand waar je op Savings het laatst naar keek.
        LinkedBlock(title: "Overzicht", symbol: "chart.bar.xaxis", subtitle: "Waar gaat je geld heen?",
                    destination: .overview, showsCurrentMonth: true) {
            FlowChart(months: months, height: 130, showsAxes: false)
            FlowLegend()
            HStack(spacing: 8) {
                // Hetzelfde getal en label als op de Overzicht-pagina ("Eind <maand>"): bank, potten en beleggingen
                // aan het eind van de maand, dus inclusief salaris en inleg die nog komen.
                StatTile(title: "Vermogen eind maand", value: Fmt.euro(worth.total))
                StatTile(title: "Over deze maand", value: Fmt.euro(left),
                         color: left < 0 ? Theme.negative : Color.primary)
            }
        }
    }
}

// MARK: - Blok 2: Spaarpotten

struct PotsBlock: View {
    @Environment(AppStore.self) private var store
    @State private var showPicker = false
    @State private var showNewPot = false

    var body: some View {
        let d = store.data
        let pots = d.homePots()
        GlassBlock(title: "Spaarpotten", symbol: "tray.full.fill",
                   subtitle: d.pots.isEmpty ? nil : "Totaal \(Fmt.euro(d.totalSaved(current: store.now, today: store.today)))",
                   headerLink: .pots) {
            if d.pots.isEmpty {
                EmptyHint(symbol: "tray", title: "Nog geen spaarpotten",
                          message: "Maak een pot voor je buffer, vakantie of een grote aankoop.",
                          actionTitle: "Nieuwe spaarpot") { showNewPot = true }
            } else {
                PotsTotals()
                HStack(alignment: .top, spacing: 10) {
                    ForEach(pots) { pot in PotMiniTile(pot: pot) }
                    ForEach(0..<max(0, 3 - pots.count), id: \.self) { _ in
                        EmptySlotTile { showPicker = true }
                    }
                }
                ChipButton(title: "Kies potten", symbol: "slider.horizontal.3") { showPicker = true }
            }
        }
        .sheet(isPresented: $showPicker) { PotPickerSheet() }
        .sheet(isPresented: $showNewPot) { PotEditSheet(pot: nil) }
    }
}

/// Boven de spaarpotten op Home: wat je in totaal hebt gespaard en wat je totale doel is.
struct PotsTotals: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let saved = d.totalSaved(current: now, today: today)
        let goal = d.totalGoal()
        // Met hetzelfde saldo van vandaag als op de tegels, zodat voortgang en bedragen bij elkaar passen.
        let towardGoals = d.pots
            .filter { ($0.goalAmount ?? 0) > 0 }
            .reduce(0) { $0 + d.potBalanceNow($1.id, current: now, today: today) }
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatTile(title: "Totaal gespaard", value: Fmt.euro(saved))
                StatTile(title: "Totaal doel", value: goal > 0 ? Fmt.euro(goal) : "–")
            }
            if goal > 0 {
                ProgressBar(progress: towardGoals / goal, tint: Theme.accent, height: 8)
                Text("\(Fmt.percent(min(towardGoals / goal, 9.99), digits: 0)) van je totale doel gehaald")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PotMiniTile: View {
    @Environment(AppStore.self) private var store
    let pot: Pot

    var body: some View {
        let balance = store.data.potBalanceNow(pot.id, current: store.now, today: store.today)
        let progress = goalProgress(balance: balance)
        let color = Theme.color(pot.colorIndex)
        NavigationLink(value: Destination.pot(pot.id)) {
            VStack(spacing: 6) {
                ZStack {
                    ProgressRing(progress: progress ?? 1, tint: color, lineWidth: 5)
                        .frame(width: 52, height: 52)
                    Image(systemName: pot.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(pot.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(Fmt.euro(balance))
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(pot.goalAmount.map { "doel \(Fmt.euro($0))" } ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .tile(tint: color)
        }
        .buttonStyle(.plain)
    }
}

extension PotMiniTile {
    /// Hoever de pot is met het saldo van vandaag; nil zonder doel. Kan boven 1 uitkomen.
    fileprivate func goalProgress(balance: Double) -> Double? {
        guard let goal = pot.goalAmount, goal > 0 else { return nil }
        return max(0, balance / goal)
    }
}

struct EmptySlotTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 52, height: 52)
                Text("Kies pot").font(.caption).foregroundStyle(.secondary)
                Text(" ").font(.footnote)
                Text(" ").font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Blok 3: Beleggingen

struct InvestBlock: View {
    @Environment(AppStore.self) private var store
    @State private var showPicker = false
    @State private var showNewHolding = false

    var body: some View {
        let d = store.data
        let now = store.now
        let value = d.portfolioValue(current: now)
        let gain = d.portfolioGain(current: now)
        let invested = d.portfolioInvested(current: now)
        let series = d.portfolioSeries(from: now.adding(-6), count: 13, current: now).map { TimePoint($0) }
        let tiles = d.homeHoldings()
        GlassBlock(title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis",
                   subtitle: d.holdings.isEmpty ? nil : "Groei van je portefeuille",
                   headerLink: .portfolio) {
            if d.holdings.isEmpty {
                EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                          message: "Voeg een ETF, aandeel of crypto toe. Koersen worden live opgehaald.",
                          actionTitle: "Belegging toevoegen") { showNewHolding = true }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    BigAmount(value: value, font: .system(.title, design: .rounded, weight: .bold))
                    Spacer()
                    if invested > 0 {
                        GainLabel(gain: gain, fraction: invested > 0 ? gain / invested : nil)
                    }
                }
                TimeLineChart(points: series, showsAxes: false, height: 110)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(tiles) { h in HoldingTile(holding: h) }
                }
                ChipButton(title: "Kies beleggingen", symbol: "slider.horizontal.3") { showPicker = true }
            }
        }
        .sheet(isPresented: $showPicker) { HoldingPickerSheet() }
        .sheet(isPresented: $showNewHolding) { HoldingEditSheet(holding: nil) }
    }
}

struct GainLabel: View {
    let gain: Double
    let fraction: Double?

    var body: some View {
        let positive = gain >= 0
        HStack(spacing: 3) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
            Text(Fmt.euro(abs(gain)))
                .contentTransition(.numericText())
            if let fraction { Text("(\(Fmt.percent(abs(fraction), digits: 1)))") }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(positive ? Theme.positive : Theme.negative)
    }
}

struct HoldingTile: View {
    @Environment(AppStore.self) private var store
    let holding: Holding

    var body: some View {
        let state = store.data.holdingStateNow(holding, current: store.now)
        let color = Theme.color(holdingColorIndex)
        NavigationLink(value: Destination.holding(holding.id)) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: holding.kind.symbol, color: color, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(holding.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(Fmt.euro(state?.value ?? 0))
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(holding.kind.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(tint: color)
        }
        .buttonStyle(.plain)
    }

    private var holdingColorIndex: Int {
        HoldingKind.allCases.firstIndex(of: holding.kind) ?? 0
    }
}

// MARK: - Keuzeschermen voor Home

struct PotPickerSheet: View {
    @Environment(AppStore.self) private var store
    @State private var selected: [UUID] = []
    private let limit = 3

    var body: some View {
        SheetScaffold(title: "Spaarpotten op Home", onSave: {
            let ids = selected
            store.mutate { $0.homePotIDs = ids }
        }) {
            Section {
                ForEach(store.data.pots) { pot in
                    Button { toggle(pot.id) } label: {
                        HStack(spacing: 12) {
                            SymbolBadge(symbol: pot.symbol, color: Theme.color(pot.colorIndex), size: 32)
                            Text(pot.name).foregroundStyle(.primary)
                            Spacer()
                            if let position = selected.firstIndex(of: pot.id) {
                                Text("\(position + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.accent, in: Circle())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Kies maximaal \(limit). De volgorde is de volgorde waarin je tikt.")
            }
        }
        .onAppear { selected = store.data.homePots().map(\.id) }
    }

    private func toggle(_ id: UUID) {
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
        } else if selected.count < limit {
            selected.append(id)
        }
    }
}

struct HoldingPickerSheet: View {
    @Environment(AppStore.self) private var store
    @State private var selected: [UUID] = []
    private let limit = 4

    var body: some View {
        SheetScaffold(title: "Beleggingen op Home", onSave: {
            let ids = selected
            store.mutate { $0.homeHoldingIDs = ids }
        }) {
            Section {
                ForEach(store.data.holdings) { h in
                    Button { toggle(h.id) } label: {
                        HStack(spacing: 12) {
                            SymbolBadge(symbol: h.kind.symbol, color: Theme.accent, size: 32)
                            VStack(alignment: .leading) {
                                Text(h.name).foregroundStyle(.primary)
                                Text(h.kind.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let position = selected.firstIndex(of: h.id) {
                                Text("\(position + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.accent, in: Circle())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Kies maximaal \(limit) beleggingssoorten.")
            }
        }
        .onAppear { selected = store.data.homeHoldings().map(\.id) }
    }

    private func toggle(_ id: UUID) {
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
        } else if selected.count < limit {
            selected.append(id)
        }
    }
}
