import SwiftUI

// MARK: - Versnellers

struct AcceleratorsSection: View {
    let goal: LifeGoal
    @Environment(AppStore.self) private var store
    @State private var selected: Set<String> = []

    var body: some View {
        let d = store.data
        let now = store.now
        let inputs = d.goalInputs(for: goal, current: now)
        let baseline = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                            monthly: inputs.monthly, annualReturn: inputs.effectiveReturn)
        let list = d.accelerators(for: goal, current: now)
        let chosen = list.filter { selected.contains($0.id) }
        let change = d.combine(chosen)
        let scenario = d.scenarioMonths(inputs, change: change)

        GlassBlock(title: "Versnellers", symbol: "bolt.fill", subtitle: "Op basis van jouw gegevens") {
            if baseline == 0 {
                Label("Je hebt dit doel al bereikt.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else if list.isEmpty {
                Text("Geen versnellers gevonden. Vul je inkomen, uitgaven, banksaldo en beleggingen in; dan zoekt de app wat je doel sneller maakt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                resultRow(baseline: baseline, scenario: scenario, hasSelection: !chosen.isEmpty)
                if !chosen.isEmpty {
                    GoalCurveChart(curves: d.goalCurves(for: goal, change: change,
                                                        months: horizon(baseline: baseline, scenario: scenario), current: now),
                                   start: now)
                }
                VStack(spacing: 8) {
                    ForEach(list) { acc in
                        AcceleratorRow(accelerator: acc, isOn: selected.contains(acc.id)) {
                            if selected.contains(acc.id) { selected.remove(acc.id) } else { selected.insert(acc.id) }
                        }
                    }
                }
                ChipGrid {
                    ChipButton(title: "Alles kiezen", symbol: "checkmark.circle") { selected = Set(list.map(\.id)) }
                    ChipButton(title: "Niets kiezen", symbol: "circle") { selected = [] }
                }
                Text("Tik op de versnellers die je wilt combineren. De berekening telt ze bij elkaar op.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func horizon(baseline: Int?, scenario: Int?) -> Int {
        var h = max(baseline ?? 0, scenario ?? 0)
        if baseline == nil && scenario == nil { h = 120 }
        return min(600, max(24, h + 12))
    }

    @ViewBuilder
    private func resultRow(baseline: Int?, scenario: Int?, hasSelection: Bool) -> some View {
        HStack(spacing: 8) {
            StatTile(title: "Nu", value: baseline.map { Fmt.duration(months: $0) } ?? "niet haalbaar")
            if hasSelection {
                StatTile(title: "Met je keuze", value: scenario.map { Fmt.duration(months: $0) } ?? "niet haalbaar",
                         color: Theme.positive,
                         caption: savedText(baseline: baseline, scenario: scenario))
            }
        }
    }

    private func savedText(baseline: Int?, scenario: Int?) -> String? {
        switch (baseline, scenario) {
        case (let b?, let s?): return s < b ? "\(Fmt.duration(months: b - s)) eerder" : nil
        case (nil, _?): return "wordt haalbaar"
        default: return nil
        }
    }
}

struct AcceleratorRow: View {
    let accelerator: Accelerator
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(accelerator.title, systemImage: accelerator.symbol)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Text(AcceleratorBadge.text(for: accelerator))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.positive)
                            .multilineTextAlignment(.trailing)
                    }
                    Text(accelerator.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(tint: isOn ? Theme.accent : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Basis (nu) tegenover het scenario met gekozen versnellers.
struct GoalCurveChart: View {
    let curves: GoalCurves
    let start: YearMonth

    private struct Item: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    private var items: [Item] {
        let count = curves.baseline.count
        let step = max(1, count / 100)
        var list: [Item] = []
        var i = 0
        while i < count {
            let date = start.adding(i).firstDay
            list.append(Item(id: "b\(i)", date: date, value: curves.baseline[i], series: "Nu"))
            if i < curves.scenario.count {
                list.append(Item(id: "s\(i)", date: date, value: curves.scenario[i], series: "Met versnellers"))
            }
            i += step
        }
        return list
    }

    var body: some View {
        Chart {
            ForEach(items) { item in
                LineMark(x: .value("Maand", item.date), y: .value("Waarde", item.value),
                         series: .value("Reeks", item.series))
                    .foregroundStyle(by: .value("Reeks", item.series))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Doel", curves.scenarioTarget))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Doel").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale(domain: ["Nu", "Met versnellers"], range: [Color.gray, Theme.accent])
        .chartAxes(shown: true)
        .frame(height: 190)
    }
}

/// Eigen pagina voor het Versnellers-blok: kies een doel en bekijk wat het sneller maakt.
struct AcceleratorsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var chosenID: UUID?

    var body: some View {
        let d = store.data
        let goal = chosenID.flatMap { d.goal($0) } ?? d.goals.first
        PageScaffold(title: "Versnellers") {
            VStack(spacing: Theme.pageSpacing) {
                if d.goals.isEmpty {
                    GlassBlock(title: "Eerst een doel") {
                        EmptyHint(symbol: "flag.checkered", title: "Maak een doel",
                                  message: "Versnellers laten zien wat je doel sneller maakt. Daarvoor heeft de app een doel nodig.",
                                  actionTitle: "Doel maken") { router.toolsPath.append(.goals) }
                    }
                } else if let goal {
                    if d.goals.count > 1 {
                        GlassBlock(title: "Voor welk doel?", symbol: "flag.checkered") {
                            Picker("Doel", selection: Binding(get: { goal.id }, set: { chosenID = $0 })) {
                                ForEach(d.goals) { Text($0.name).tag($0.id) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                    AcceleratorsSection(goal: goal)
                        .id(goal.id)
                }
            }
        }
    }
}
