import SwiftUI

/// Tab 3: gereedschap. Versnellers, toekomstschatting en de aankoopcheck, elk met een eigen pagina.
/// De volgorde van de blokken kies je zelf (lang indrukken op een blok).
struct ToolsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.toolsPath) {
            PageScaffold(title: "Tools", showsSettings: true) {
                LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                    OrderedBlocks(page: .tools) { id in toolsBlock(id) }
                }
            }
            .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
        }
    }

    /// Het blok bij een blok-id (zie `BlockPage.tools`).
    @ViewBuilder
    private func toolsBlock(_ id: String) -> some View {
        switch id {
        case "accelerators": AcceleratorsBlock()
        case "projection": ProjectionBlock()
        case "purchase": PurchaseBlock()
        default: EmptyView()
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
        // Een schatting: wat er per maand wordt ingelegd, en bij een salaris om de zoveel weken of dagen een gemiddelde maand
        // (`monthlyInvestment`, zie SalarySchedule.swift). Zo rekent ook de toekomstschatting zelf.
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
                        StatTile(title: "Over \(years) jaar", value: Fmt.euro(r.total))
                    }
                }
                Text("Met \(d.salary.isMonthly ? "" : "gemiddeld ")\(Fmt.euro(monthly)) per maand en \(Fmt.percent(rate)) rendement na kosten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        // Met het saldo van vandaag (`store.today`), zoals de doelen en de versnellerspagina.
        let list = goal.map { d.accelerators(for: $0, current: store.now, today: store.today) } ?? []
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
                                .multilineTextAlignment(.trailing)
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
