import SwiftUI

/// Tab 2: spaarpotten en bankrekening. Bovenin kies je maand, half jaar of jaar.
/// Elk blok opent een eigen pagina.
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.pageSpacing, alignment: .top)],
                              spacing: Theme.pageSpacing) {
                        PeriodBlock()
                        IncomeBlock()
                        BankBlock()
                        DistributeBlock()
                        PotsSummaryBlock()
                        BufferBlock()
                    }
                }
            }
            .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
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
                StatTile(title: "Inkomen", value: Fmt.euroWhole(period.income))
                StatTile(title: "Uitgaven", value: Fmt.euroWhole(period.expenses))
                StatTile(title: "Over", value: Fmt.euroWhole(period.remaining),
                         color: period.remaining < 0 ? Theme.negative : Color.primary)
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
        let salaryTotal = period.months.reduce(0) { $0 + d.salaryAmount(in: $1.month) }
        let extraTotal = period.months.reduce(0) { $0 + d.extraIncomeTotal(in: $1.month) }
        LinkedBlock(title: "Salaris & inkomsten", symbol: "eurosign.circle.fill",
                    subtitle: Fmt.period(router.periodMode, containing: router.focusMonth),
                    destination: .income) {
            BigAmount(value: period.income, font: .system(.title, design: .rounded, weight: .bold))
            if d.salary.monthlyAmount() == 0 && extraTotal == 0 {
                Text("Stel je salaris in als vast bedrag of met een uurloon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    StatTile(title: "Salaris", value: Fmt.euroWhole(salaryTotal))
                    StatTile(title: "Overig", value: Fmt.euroWhole(extraTotal))
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
        let available = period.income - period.expenses
        let allocated = period.saved + period.invested
        let progress = available > 0 ? allocated / available : 0
        let over = period.remaining < 0
        LinkedBlock(title: "Verdelen", symbol: "square.split.2x2.fill",
                    subtitle: over ? "Je hebt te veel verdeeld" : "Nog te verdelen",
                    destination: .distribute) {
            BigAmount(value: period.remaining,
                      font: .system(.title, design: .rounded, weight: .bold),
                      color: over ? Theme.negative : Color.primary)
            ProgressBar(progress: progress, tint: over ? Theme.negative : Theme.accent, height: 10)
            HStack {
                Text("Gespaard \(Fmt.euroWhole(period.saved))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Belegd \(Fmt.euroWhole(period.invested))").font(.caption).foregroundStyle(.secondary)
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
        let pots = Array(d.pots.prefix(3))
        LinkedBlock(title: "Spaarpotten", symbol: "tray.full.fill",
                    subtitle: d.pots.isEmpty ? nil : "\(d.pots.count) \(d.pots.count == 1 ? "pot" : "potten")",
                    destination: .pots) {
            BigAmount(value: d.totalSaved(current: now), font: .system(.title, design: .rounded, weight: .bold))
            if pots.isEmpty {
                Text("Maak spaarpotten met een doel, zoals een buffer of een vakantie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(pots) { pot in
                        HStack(spacing: 10) {
                            SymbolBadge(symbol: pot.symbol, color: Theme.color(pot.colorIndex), size: 28)
                            Text(pot.name).font(.footnote.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(Fmt.euroWhole(d.potBalance(pot.id, at: now))).font(.footnote.weight(.semibold))
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
        let months = router.periodMode.months(containing: router.focusMonth)
        let target = months.last ?? router.focusMonth
        let balance = d.bankBalance(at: target)
        let overviews = months.map { d.expenseOverview(in: $0) }
        let fixed = overviews.reduce(0) { $0 + $1.fixed }
        let variable = overviews.reduce(0) { $0 + $1.variable }
        let left = overviews.reduce(0) { $0 + $1.leftAfterTransfers }
        LinkedBlock(title: "Bankrekening", symbol: "building.columns.fill",
                    subtitle: "Saldo, uitgaven en overschrijvingen",
                    destination: .bank) {
            if let balance {
                BigAmount(value: balance, font: .system(.title, design: .rounded, weight: .bold))
                if target > store.now {
                    Text("Verwacht eind \(Fmt.period(router.periodMode, containing: router.focusMonth)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Vul je saldo in of zet er geld op. De app houdt het bij en rekent ermee.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                StatTile(title: "Vast", value: Fmt.euroWhole(fixed))
                StatTile(title: "Variabel", value: Fmt.euroWhole(variable))
                StatTile(title: "Over", value: Fmt.euroWhole(left),
                         color: left < 0 ? Theme.negative : Color.primary)
            }
        }
    }
}
