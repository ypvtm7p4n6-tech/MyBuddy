import SwiftUI
import Charts

/// Rekenmachine: wat is mijn belegging over x dagen, weken, maanden of jaren waard?
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

    private struct SeriesPoint: Identifiable {
        let id: String
        let t: Double
        let value: Double
        let scenario: String
    }

    private struct ScenarioResult: Identifiable {
        let scenario: ReturnScenario
        let result: ProjectionResult
        var id: String { scenario.rawValue }
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
        let points = chartPoints(months: months, inflation: inflation)

        PageScaffold(title: "Toekomstschatting") {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: "Hoe ver kijk je vooruit?", symbol: "calendar.badge.clock") {
                    NumberRow(title: "Over", value: $horizon, unit: .plain(unit.title), maxDigits: 1)
                    Picker("Eenheid", selection: $unit) {
                        ForEach(HorizonUnit.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    ChipGrid(minimumWidth: 90) {
                        ForEach([1, 5, 10, 20, 30], id: \.self) { years in
                            ChipButton(title: "\(years) jaar") {
                                unit = .years
                                horizon = Double(years)
                            }
                        }
                    }
                }

                GlassBlock(title: "Uitgangspunten", symbol: "slider.horizontal.3") {
                    NumberRow(title: "Startbedrag", value: $start)
                    NumberRow(title: "Inleg per maand", value: $monthly)
                    NumberRow(title: "Rendement per jaar", value: $annualReturn, unit: .percent, maxDigits: 2)
                    Toggle("In koopkracht van vandaag", isOn: $inflationAdjusted)
                    if inflationAdjusted {
                        Text("Bedragen zijn gecorrigeerd voor \(Fmt.percent(inflation)) inflatie per jaar. Je past dat aan in Instellingen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ChipButton(title: "Gebruik mijn beleggingen", symbol: "arrow.counterclockwise") { resetToPortfolio() }
                }

                GlassBlock(title: "Verwachte waarde", symbol: "sparkles",
                           subtitle: "Over \(Fmt.input(horizon, maxDigits: 1)) \(unit.title)", tint: Theme.olive.opacity(0.3)) {
                    BigAmount(value: inflationAdjusted ? expected.real : expected.total)
                    HStack(spacing: 8) {
                        ForEach(results) { item in
                            StatTile(title: item.scenario.title,
                                     value: Fmt.euroWhole(inflationAdjusted ? item.result.real : item.result.total),
                                     caption: "\(Fmt.percent(annualReturn + item.scenario.delta)) p.j.")
                        }
                    }
                    breakdown(expected)
                }

                GlassBlock(title: "Verloop", symbol: "chart.xyaxis.line") {
                    Chart(points) { p in
                        LineMark(x: .value("Tijd", p.t), y: .value("Waarde", p.value))
                            .foregroundStyle(by: .value("Scenario", p.scenario))
                            .interpolationMethod(.monotone)
                    }
                    .chartForegroundStyleScale(domain: ReturnScenario.allCases.map { $0.title },
                                               range: [Theme.flowExpenses, Theme.accent, Theme.flowInvested])
                    .chartXAxisLabel(unit.title)
                    .chartAxes(shown: true)
                    .frame(height: 210)
                }

                GlassBlock(title: "Streefbedrag", symbol: "target") {
                    NumberRow(title: "Ik wil graag", value: $target)
                    targetResult(months: months)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            resetToPortfolio()
        }
    }

    // MARK: Onderdelen

    @ViewBuilder
    private func breakdown(_ r: ProjectionResult) -> some View {
        let total = max(r.total, 0.01)
        VStack(alignment: .leading, spacing: 6) {
            ProgressBar(progress: r.contributed / total, tint: Theme.flowSaved, height: 10)
            HStack {
                Label("Ingelegd \(Fmt.euroWhole(r.contributed))", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.flowSaved)
                Spacer()
                Label("Rendement \(Fmt.euroWhole(r.growth))", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func targetResult(months: Double) -> some View {
        if target > 0 {
            let inflation = store.data.settings.inflation
            let rate = inflationAdjusted ? Growth.realReturn(nominal: annualReturn, inflation: inflation) : annualReturn
            let needed = Growth.monthsToReach(target: target, start: start, monthly: monthly, annualReturn: rate)
            let totalMonths = max(1, Int(months.rounded()))
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
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Vul een bedrag in om te zien hoe lang het duurt en wat je per maand moet inleggen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Berekening

    private func chartPoints(months: Double, inflation: Double) -> [SeriesPoint] {
        var points: [SeriesPoint] = []
        for scenario in ReturnScenario.allCases {
            let curve = Growth.curve(start: start, monthly: monthly, annualReturn: annualReturn + scenario.delta,
                                     totalMonths: max(months, 0.1), unit: unit, steps: 36)
            for (i, p) in curve.enumerated() {
                var value = p.value
                if inflationAdjusted {
                    value = Growth.deflate(value, years: unit.months(p.t) / 12, inflation: inflation)
                }
                points.append(SeriesPoint(id: "\(scenario.rawValue)-\(i)", t: p.t, value: value, scenario: scenario.title))
            }
        }
        return points
    }

    private func resetToPortfolio() {
        let d = store.data
        let now = store.now
        start = d.portfolioValue(current: now)
        monthly = d.monthlyInvestment(current: now)
        annualReturn = d.weightedNetReturn(current: now)
    }
}
