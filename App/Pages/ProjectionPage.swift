import SwiftUI

// MARK: - De pagina

/// Rekenmachine: wat is mijn belegging over x dagen, weken, maanden of jaren waard? De uitkomst en het verloop staan bovenaan,
/// de looptijd is altijd zichtbaar en de uitgangspunten zitten in een uitklapper.
struct ProjectionPage: View {
    @Environment(AppStore.self) private var store

    @State private var horizon = 10.0
    @State private var unit: HorizonUnit = .years
    @State private var start = 0.0
    @State private var monthly = 0.0
    @State private var annualReturn = 0.05
    @State private var inflationAdjusted = false
    @State private var target = 0.0
    @State private var loaded = false
    @State private var assumptionsOpen = false

    private struct ScenarioResult: Identifiable {
        let scenario: ReturnScenario
        let result: ProjectionResult
        var id: String { scenario.rawValue }
    }

    /// De langste looptijd (100 jaar, zoals de rest van de rekenmotor) uitgedrukt in de gekozen eenheid.
    private func maxHorizon(for unit: HorizonUnit) -> Double {
        Double(Growth.maxMonths) / unit.months(1)
    }

    /// De looptijd, begrensd op 0 tot 100 jaar: een veel te groot getal rekent de grafiek en de uitkomst stuk.
    private var horizonBinding: Binding<Double> {
        Binding(get: { horizon },
                set: { newValue in
                    guard newValue.isFinite else { return }
                    horizon = min(max(newValue, 0), maxHorizon(for: unit))
                })
    }

    /// "Gebruik je beleggingen" start bij je beleggingen aan het EIND van deze maand (de schatting rekent per maand
    /// verder, vanaf volgende maand). Staat er nog een inleg van deze maand te wachten, dan is dat meer dan wat je vandaag
    /// hebt: zeg dat erbij, zodat het getal niet tegenspreekt wat Home en Beleggingen tonen.
    private var startNote: String? {
        let d = store.data
        let now = store.now
        let monthEnd = CentsMath.int(d.portfolioValue(current: now))
        let today = CentsMath.int(d.portfolioValue(current: now, today: store.today))
        guard monthEnd > today else { return nil }
        return "Gebruik je beleggingen telt de inleg van deze maand die nog moet worden overgeschreven al mee (\(Fmt.euro(CentsMath.value(monthEnd - today)))). Vandaag heb je \(Fmt.euro(CentsMath.value(today)))."
    }

    var body: some View {
        let inflation = store.data.settings.inflation
        let months = unit.months(horizon)
        let results: [ScenarioResult] = ReturnScenario.allCases.map { scenario in
            ScenarioResult(scenario: scenario,
                           result: Growth.projection(start: start, monthly: monthly,
                                                     annualReturn: annualReturn + scenario.delta,
                                                     months: months, inflation: inflation))
        }
        let expected = results[1].result

        PageScaffold(title: "Toekomstschatting") {
            VStack(spacing: Theme.pageSpacing) {
                outcomeCard(results, expected: expected)
                chartCard(months: months, inflation: inflation)
                horizonCard
                assumptionsCard(inflation: inflation)
                targetCard(months: months)
            }
            .frame(maxWidth: Theme.readableWidth)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            resetToPortfolio()
        }
        // Een andere eenheid kan dezelfde waarde te groot maken (36.000 dagen is 100 jaar, 36.000 jaar niet).
        .onChange(of: unit) { _, newUnit in
            horizon = min(horizon, maxHorizon(for: newUnit))
        }
    }

    // MARK: Uitkomst

    private func outcomeCard(_ results: [ScenarioResult], expected: ProjectionResult) -> some View {
        Card(title: "Uitkomst", symbol: "sparkles", domain: .tools,
             subtitle: "Over \(Fmt.input(horizon, maxDigits: 1)) \(unit.title)") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Verwachte waarde")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                BigAmount(value: inflationAdjusted ? expected.real : expected.total)
            }
            .accessibilityElement(children: .combine)
            FigureRow {
                ForEach(results) { item in
                    StatTile(title: item.scenario.title,
                             value: Fmt.euro(inflationAdjusted ? item.result.real : item.result.total),
                             caption: "\(Fmt.percent(annualReturn + item.scenario.delta)) per jaar")
                }
            }
            breakdown(expected)
        }
    }

    /// Hoeveel van de uitkomst je zelf inlegt en hoeveel het rendement oplevert.
    private func breakdown(_ r: ProjectionResult) -> some View {
        let total = max(r.total, 0.01)
        return VStack(alignment: .leading, spacing: 6) {
            ProgressMeter(value: r.contributed / total, tint: Theme.chartSaved, style: .bar(height: 10),
                          label: "Ingelegd tegenover rendement",
                          valueText: "Ingelegd \(Fmt.euro(r.contributed)), rendement \(Fmt.euro(r.growth))")
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("Ingelegd \(Fmt.euro(r.contributed))", systemImage: "circle.fill")
                        .foregroundStyle(Theme.chartSaved)
                    Spacer()
                    Label("Rendement \(Fmt.euro(r.growth))", systemImage: "circle")
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label("Ingelegd \(Fmt.euro(r.contributed))", systemImage: "circle.fill")
                        .foregroundStyle(Theme.chartSaved)
                    Label("Rendement \(Fmt.euro(r.growth))", systemImage: "circle")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .font(.footnote)
        }
    }

    // MARK: Verloop

    private func chartCard(months: Double, inflation: Double) -> some View {
        Card(title: "Verloop", symbol: "chart.xyaxis.line", domain: .tools) {
            TrendChart(model: ProjectionTrend.model(start: start, monthly: monthly, annualReturn: annualReturn,
                                                    months: months, unit: unit, target: target,
                                                    inflationAdjusted: inflationAdjusted, inflation: inflation),
                       size: .tall)
        }
    }

    // MARK: Looptijd

    /// "Hoe ver kijk je vooruit?" is altijd zichtbaar: het veld, de eenheid en de snelkeuzes.
    private var horizonCard: some View {
        Card(title: "Looptijd", symbol: "calendar.badge.clock", domain: .tools, subtitle: "Hoe ver kijk je vooruit?") {
            NumberRow(title: "Over", value: horizonBinding, unit: .plain(unit.title), maxDigits: 1)
            Picker("Eenheid", selection: $unit) {
                ForEach(HorizonUnit.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            PlanningFootnote("Je kunt maximaal 100 jaar vooruit kijken.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach([1, 5, 10, 20, 30], id: \.self) { years in
                    ActionButton(title: "\(years) jaar") {
                        unit = .years
                        horizon = Double(years)
                    }
                }
            }
        }
    }

    // MARK: Uitgangspunten (uitklapper)

    private func assumptionsCard(inflation: Double) -> some View {
        Card {
            DisclosureGroup(isExpanded: $assumptionsOpen) {
                assumptionFields(inflation: inflation)
                    .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Uitgangspunten", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Start \(Fmt.euro(start)), inleg \(Fmt.euro(monthly)) per maand, \(Fmt.percent(annualReturn)) rendement per jaar")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func assumptionFields(inflation: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            NumberRow(title: "Startbedrag", value: $start)
            NumberRow(title: "Inleg per maand", value: $monthly)
            // Bij een salaris om de zoveel weken of dagen is de voorgestelde inleg een gemiddelde maand.
            if !store.data.salary.isMonthly {
                PlanningFootnote("De voorgestelde inleg is een gemiddelde maand: je salaris komt niet elke maand even vaak binnen.")
            }
            NumberRow(title: "Rendement per jaar", value: $annualReturn, unit: .percent, maxDigits: 2)
            Toggle("In koopkracht van vandaag", isOn: $inflationAdjusted)
                .frame(minHeight: Theme.minTapTarget)
            assumptionNotes(inflation: inflation)
            ActionButton(title: "Gebruik je beleggingen", symbol: "arrow.counterclockwise") { resetToPortfolio() }
        }
    }

    @ViewBuilder
    private func assumptionNotes(inflation: Double) -> some View {
        if inflationAdjusted {
            PlanningFootnote("Bedragen zijn gecorrigeerd voor \(Fmt.percent(inflation)) inflatie per jaar. Je past dat aan in Instellingen.")
        }
        if let note = startNote {
            PlanningFootnote(note)
        }
    }

    // MARK: Doelbedrag

    private func targetCard(months: Double) -> some View {
        Card(title: "Doelbedrag", symbol: "target", domain: .tools, subtitle: "Hoe lang duurt het, en wat leg je in?") {
            NumberRow(title: "Bedrag dat je wilt halen", value: $target)
            targetResult(months: months)
        }
    }

    @ViewBuilder
    private func targetResult(months: Double) -> some View {
        if target > 0 {
            let inflation = store.data.settings.inflation
            let rate = inflationAdjusted ? Growth.realReturn(nominal: annualReturn, inflation: inflation) : annualReturn
            let needed = Growth.monthsToReach(target: target, start: start, monthly: monthly, annualReturn: rate)
            let totalMonths = SafeInt.clamped(months, to: 1...Growth.maxMonths)
            let required = Growth.requiredMonthly(target: target, start: start, annualReturn: rate, months: totalMonths)
            VStack(alignment: .leading, spacing: 8) {
                if let needed {
                    Label(needed == 0 ? "Dit bedrag heb je al." : "Je bereikt dit over \(Fmt.duration(months: needed)), in \(Fmt.month(store.now.adding(needed))).",
                          systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Label("Met deze inleg bereik je dit bedrag niet binnen 100 jaar.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.negative)
                }
                Label("Om het binnen \(Fmt.input(horizon, maxDigits: 1)) \(unit.title) te halen, leg je \(Fmt.euro(required)) per maand in.",
                      systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            PlanningFootnote("Vul een bedrag in om te zien hoe lang het duurt en wat je per maand moet inleggen.")
        }
    }

    // MARK: Berekening

    private func resetToPortfolio() {
        let d = store.data
        let now = store.now
        start = d.portfolioValue(current: now)
        monthly = d.monthlyInvestment(current: now)
        annualReturn = d.weightedNetReturn(current: now)
    }
}
