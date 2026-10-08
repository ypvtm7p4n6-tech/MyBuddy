import SwiftUI

/// Tab 3: beleggingen. Vier blokken, elk met een eigen pagina.
struct InvestView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.investPath) {
            PageScaffold(title: "Beleggingen", showsSettings: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.pageSpacing, alignment: .top)],
                          spacing: Theme.pageSpacing) {
                    PortfolioBlock()
                    ProjectionBlock()
                    GoalsBlock()
                    AcceleratorsBlock()
                }
            }
            .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
        }
    }
}

// MARK: - Portefeuille

struct PortfolioBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let value = d.portfolioValue(current: now)
        let invested = d.portfolioInvested(current: now)
        let gain = d.portfolioGain(current: now)
        let series = d.portfolioSeries(from: now.adding(-6), count: 13, current: now).map { TimePoint($0) }
        LinkedBlock(title: "Portefeuille", symbol: "chart.line.uptrend.xyaxis",
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

// MARK: - Toekomstschatting

struct ProjectionBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let start = d.portfolioValue(current: now)
        let monthly = d.monthlyInvestment(current: now)
        let rate = d.weightedNetReturn(current: now)
        let inflation = d.settings.inflation
        LinkedBlock(title: "Toekomstschatting", symbol: "calendar.badge.clock",
                    subtitle: "Wat is het over x jaar?", destination: .projection) {
            if start == 0 && monthly == 0 {
                Text("Vul beleggingen in en reken uit wat ze over dagen, maanden of jaren waard zijn.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach([5, 10, 20], id: \.self) { years in
                        let r = Growth.projection(start: start, monthly: monthly, annualReturn: rate,
                                                  months: Double(years * 12), inflation: inflation)
                        StatTile(title: "Over \(years) jaar", value: Fmt.euroWhole(r.total))
                    }
                }
                Text("Met \(Fmt.euroWhole(monthly)) per maand en \(Fmt.percent(rate)) rendement na kosten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Doelen

struct GoalsBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let goals = Array(d.goals.prefix(2))
        LinkedBlock(title: "Doelen", symbol: "flag.checkered",
                    subtitle: d.goals.isEmpty ? nil : "\(d.goals.count) \(d.goals.count == 1 ? "doel" : "doelen")",
                    destination: .goals) {
            if goals.isEmpty {
                Text("Stel een doel in: met pensioen, een vakantie of parttime werken. De app rekent uit wat je nodig hebt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(goals) { goal in
                        let a = d.analyze(goal, current: store.now)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(goal.name, systemImage: goal.kind.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(a.monthsToGoal.map { Fmt.duration(months: $0) } ?? "niet haalbaar")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(a.monthsToGoal == nil ? Theme.negative : Theme.accent)
                            }
                            ProgressBar(progress: a.progress, tint: Theme.accent)
                        }
                        .padding(12)
                        .tile()
                    }
                }
            }
        }
    }
}

// MARK: - Versnellers

struct AcceleratorsBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let goal = d.goals.first
        let list = goal.map { d.accelerators(for: $0, current: store.now) } ?? []
        LinkedBlock(title: "Versnellers", symbol: "bolt.fill",
                    subtitle: goal.map { "Voor \($0.name)" }, destination: .accelerators) {
            if goal == nil {
                Text("Maak eerst een doel. Daarna zoekt de app in jouw gegevens wat het sneller maakt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if list.isEmpty {
                Text("Geen versnellers gevonden. Vul inkomsten, uitgaven, je banksaldo en beleggingen in voor persoonlijke tips.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(list.prefix(3))) { acc in
                        HStack(spacing: 10) {
                            Image(systemName: acc.symbol)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            Text(acc.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            Text(AcceleratorBadge.text(for: acc))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.positive)
                        }
                    }
                }
                .padding(12)
                .tile()
            }
        }
    }
}

enum AcceleratorBadge {
    static func text(for acc: Accelerator) -> String {
        if let saved = acc.monthsSaved { return "\(Fmt.duration(months: saved)) eerder" }
        if let months = acc.newMonths { return "haalbaar in \(Fmt.duration(months: months))" }
        return ""
    }
}
