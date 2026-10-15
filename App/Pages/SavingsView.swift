import SwiftUI

/// Tab 2: sparen en beleggen. Bovenin kies je maand, half jaar of jaar. Daaronder staan de blokken:
/// overzicht, inkomen, bankrekening, verdelen, spaarpotten, buffer, beleggingen en doelen.
/// Elk blok opent een eigen pagina. De volgorde kies je zelf (lang indrukken op een blok).
struct SavingsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.savingsPath) {
            PageScaffold(title: "Savings", showsSettings: true) {
                VStack(spacing: Theme.pageSpacing) {
                    PeriodControl()
                        .padding(Theme.cardInset)
                        .glassCard()
                    LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                        OrderedBlocks(page: .savings) { id in savingsBlock(id) }
                    }
                }
            }
            .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
        }
    }

    /// Het blok bij een blok-id (zie `BlockPage.savings`).
    @ViewBuilder
    private func savingsBlock(_ id: String) -> some View {
        switch id {
        case "period": PeriodBlock()
        case "income": IncomeBlock()
        case "bank": BankBlock()
        case "distribute": DistributeBlock()
        case "pots": PotsSummaryBlock()
        case "buffer": BufferBlock()
        case "portfolio": PortfolioBlock()
        case "goals": GoalsHubBlock()
        default: EmptyView()
        }
    }
}

// MARK: - Periode

struct PeriodBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let period = d.periodSummary(router.periodMode, containing: router.focusMonth, current: store.now)
        let months = chartMonths(mode: router.periodMode, focus: router.focusMonth)
        let chart = d.summaries(from: months.first ?? router.focusMonth, count: months.count, current: store.now)
        LinkedBlock(title: "Overzicht", symbol: "chart.bar.xaxis",
                    subtitle: Fmt.period(router.periodMode, containing: router.focusMonth),
                    destination: .overview) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                StatTile(title: "Inkomen", value: Fmt.euro(period.income))
                StatTile(title: "Uitgaven", value: Fmt.euro(period.expenses))
                StatTile(title: "Over", value: Fmt.euro(period.remaining),
                         color: period.remaining < 0 ? Theme.negative : Color.primary)
            }
            // Uitgaven uit een spaarpot kosten het maandbudget niets: zonder uitleg tellen de tegels niet op.
            if period.fromPots > 0 {
                Text("Waarvan \(Fmt.euro(period.fromPots)) uit spaarpotten. Dat telt niet mee in Over.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            FlowChart(months: chart, height: 120, showsAxes: false)
            FlowLegend()
        }
    }
}

// MARK: - Salaris en inkomsten

struct IncomeBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let period = d.periodSummary(router.periodMode, containing: router.focusMonth, current: store.now)
        // Salaris (de som van de uitbetalingen van elke maand) en overige inkomsten, in hele centen opgeteld: samen zijn ze
        // het inkomen hierboven.
        let parts = d.incomeParts(in: period.months.map(\.month))
        LinkedBlock(title: "Salaris & inkomsten", symbol: "eurosign.circle.fill",
                    subtitle: Fmt.period(router.periodMode, containing: router.focusMonth),
                    destination: .income) {
            BigAmount(value: period.income, font: .system(.title, design: .rounded, weight: .bold))
            if d.salary.monthlyAmount() == 0 && parts.extra == 0 {
                Text("Stel je salaris in als vast bedrag of met een uurloon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    StatTile(title: "Salaris", value: Fmt.euro(parts.salary))
                    StatTile(title: "Overig", value: Fmt.euro(parts.extra))
                }
                // Een salaris om de zoveel weken of dagen komt niet elke maand even vaak binnen: zeg wanneer.
                if !d.salary.isMonthly {
                    Text("Salaris \(d.salaryScheduleSummary(asOf: store.today)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Verdelen

struct DistributeBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let period = d.periodSummary(router.periodMode, containing: router.focusMonth, current: store.now)
        // Dezelfde rekenregels als voor één maand, in hele centen (`MonthFigures`): wat je te verdelen had (`available`) is
        // inkomen min uitgaven van de bank, en "Nog te verdelen" is dat min wat je verdeelde. Zo volgt het altijd de som van "Over".
        let figures = period.figures
        let allocatedCents = CentsMath.add(figures.saved, figures.invested)
        let progress = figures.available > 0 ? Double(allocatedCents) / Double(figures.available) : 0
        let remaining = CentsMath.value(figures.remaining)
        let over = figures.remaining < 0
        // Onder nul door te hoge uitgaven (bijvoorbeeld nog geen salaris) is niet "te veel verdeeld".
        let spending = figures.available < 0
        LinkedBlock(title: "Verdelen", symbol: "square.split.2x2.fill",
                    subtitle: over ? (spending ? "Je uitgaven zijn hoger dan je inkomen" : "Je hebt te veel verdeeld")
                                   : "Nog te verdelen",
                    destination: .distribute) {
            BigAmount(value: remaining,
                      font: .system(.title, design: .rounded, weight: .bold),
                      color: over ? Theme.negative : Color.primary)
            ProgressBar(progress: progress, tint: over ? Theme.negative : Theme.accent, height: 10)
            HStack {
                Text("Gespaard \(Fmt.euro(period.saved))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Belegd \(Fmt.euro(period.invested))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Spaarpotten

struct PotsSummaryBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let pots = Array(d.pots.prefix(3))
        LinkedBlock(title: "Spaarpotten", symbol: "tray.full.fill",
                    subtitle: d.pots.isEmpty ? nil : "\(d.pots.count) \(d.pots.count == 1 ? "pot" : "potten")",
                    destination: .pots) {
            BigAmount(value: d.totalSaved(current: now, today: today),
                      font: .system(.title, design: .rounded, weight: .bold))
            if pots.isEmpty {
                Text("Maak spaarpotten met een doel, zoals een buffer of een vakantie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(pots) { pot in
                        HStack(spacing: 10) {
                            SymbolBadge(symbol: pot.symbol, color: Theme.color(pot.colorIndex), size: 28)
                            Text(pot.name).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer()
                            Text(Fmt.euro(d.potBalanceNow(pot.id, current: now, today: today)))
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .padding(10)
                .tile()
            }
        }
    }
}

// MARK: - Bankrekening en uitgaven

struct BankBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let months = router.periodMode.months(containing: router.focusMonth)
        let target = months.last ?? router.focusMonth
        // Dezelfde som als "Over" in het Overzicht en bij Verdelen: de cijfers van de periode (`PeriodSummary`).
        let period = d.periodSummary(router.periodMode, containing: router.focusMonth, current: now)
        // Voor de huidige maand telt het saldo van vandaag, en alleen als dat bekend is (een saldo dat pas later in de maand
        // begint zegt niets over vandaag: dan geen "€ 0" maar de uitnodiging om het in te vullen). Voor andere perioden is
        // het het saldo aan het eind ervan.
        let balance: Double? = target == now ? d.bankBalanceNowIfKnown(current: now, today: today) : d.bankBalance(at: target)
        let kinds = d.expenseKindTotals(in: months)
        let left = period.remaining
        LinkedBlock(title: "Bankrekening", symbol: "building.columns.fill",
                    subtitle: "Saldo, uitgaven en overschrijvingen",
                    destination: .bank) {
            if let balance {
                BigAmount(value: balance, font: .system(.title, design: .rounded, weight: .bold))
                Text(balanceNote(target: target, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if d.hasBankBalance {
                Text("Je saldo van vandaag is nog niet bekend. Vul je saldo van vandaag in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Vul je saldo in of zet er geld op. De app houdt het bij en rekent ermee.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                StatTile(title: "Vast", value: Fmt.euro(kinds.fixed))
                StatTile(title: "Variabel", value: Fmt.euro(kinds.variable))
                StatTile(title: "Over", value: Fmt.euro(left),
                         color: left < 0 ? Theme.negative : Color.primary)
            }
            // Vast en Variabel bevatten ook wat uit een spaarpot komt, Over niet: zonder uitleg tellen de tegels niet op.
            if period.fromPots > 0 {
                Text("Waarvan \(Fmt.euro(period.fromPots)) uit spaarpotten. Dat telt niet mee in Over.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func balanceNote(target: YearMonth, now: YearMonth) -> String {
        let period = Fmt.period(router.periodMode, containing: router.focusMonth)
        if target > now { return "Verwacht saldo aan het eind van \(period)." }
        if target == now { return "Saldo van vandaag." }
        return "Saldo aan het eind van \(period)."
    }
}

// MARK: - Beleggingen

/// Het blok "Beleggingen" op Savings (de oude "Portefeuille"). Opent de pagina met alle beleggingen.
struct PortfolioBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        // Wat je nu hebt, per kalenderdag (zoals de bank en de spaarpotten), net als op Home.
        let today = store.today
        let value = d.portfolioValue(current: now, today: today)
        let invested = d.portfolioInvested(current: now, today: today)
        let gain = d.portfolioGain(current: now, today: today)
        let series = d.portfolioSeries(from: now.adding(-6), count: 13, current: now, today: today).map { TimePoint($0) }
        LinkedBlock(title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis",
                    subtitle: d.holdings.isEmpty ? nil : "\(d.holdings.count) \(d.holdings.count == 1 ? "belegging" : "beleggingen")",
                    destination: .portfolio) {
            if d.holdings.isEmpty {
                Text("Voeg je beleggingen toe. Met een ticker haalt de app de koers live op.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    BigAmount(value: value, font: .system(.title, design: .rounded, weight: .bold))
                    Spacer()
                    if invested > 0 { GainLabel(gain: gain, fraction: gain / invested) }
                }
                TimeLineChart(points: series, showsAxes: false, height: 90)
            }
        }
    }
}
