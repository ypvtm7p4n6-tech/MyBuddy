import SwiftUI
import Charts

// MARK: - Blok op de Beleggingen-pagina

/// Blok met een rekenvoorbeeld; tikken opent de calculator.
struct SavingsGoalBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let s = store.data.settings
        let plan = SavingsGoalPlan.example(savingsRate: s.savingsRate, inflation: s.inflation)
        LinkedBlock(title: "Spaardoel", symbol: "target",
                    subtitle: "Hoeveel per maand, of wanneer klaar?", destination: .savingsGoal) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Spaar \(Fmt.euroWhole(plan.cleanGoal)) in \(Fmt.duration(months: plan.months)): \(Fmt.euroWhole(plan.requiredMonthly)) per maand")
                    .font(.subheadline.weight(.semibold))
                Text("Voorbeeld. Vul je eigen bedrag, termijn en rendement in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - De calculator

/// Welke inleg de details (ingelegd en rente, tabel) laten zien.
private enum SavingsGoalScenario: String, CaseIterable, Identifiable {
    case mine, needed
    var id: String { rawValue }
    var title: String { self == .mine ? "Mijn inleg" : "Benodigde inleg" }
}

/// Snelle spaardoel-calculator: hoeveel per maand, en wanneer ben je klaar.
/// Staat los van de grote levensdoelen. Alle cijfers worden in `body` berekend, dus alles beweegt direct mee.
struct SavingsGoalPage: View {
    @Environment(AppStore.self) private var store

    @State private var goal = 5_000.0
    @State private var start = 0.0
    @State private var preset: SavingsRatePreset = .savings
    @State private var customRate = 0.05
    @State private var useDate = false
    @State private var periodValue = 2.0
    @State private var periodUnit: SavingsGoalPeriodUnit = .years
    @State private var targetDate = Date()
    @State private var monthly = 0.0
    @State private var realTerms = false
    @State private var scenario: SavingsGoalScenario = .mine
    @State private var showAllRows = false
    @State private var name = "Spaardoel"
    @State private var createdPotID: UUID?
    @State private var createdGoalID: UUID?
    @State private var loaded = false

    // MARK: Invoer omzetten naar een plan

    private var currentRate: Double {
        preset.rate(savingsRate: store.data.settings.savingsRate, customRate: customRate)
    }

    private var horizonMonths: Int {
        if useDate { return SavingsGoalPlan.monthsUntil(targetDate, from: store.now) }
        return periodUnit.monthCount(periodValue)
    }

    private func currentPlan() -> SavingsGoalPlan {
        SavingsGoalPlan(goal: goal, start: start, annualReturn: currentRate, horizonMonths: horizonMonths,
                        monthly: monthly, inflation: store.data.settings.inflation, realTerms: realTerms)
    }

    // MARK: Pagina

    var body: some View {
        let plan = currentPlan()
        PageScaffold(title: "Spaardoel") {
            VStack(spacing: Theme.pageSpacing) {
                resultBlock(plan)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.pageSpacing, alignment: .top)],
                          spacing: Theme.pageSpacing) {
                    goalBlock(plan)
                    rateBlock(plan)
                    if plan.cleanGoal > 0 {
                        if !plan.isReached {
                            whatIfBlock(plan)
                            chartBlock(plan)
                            splitBlock(plan)
                            tableBlock(plan)
                        }
                        saveBlock(plan)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { loadDefaults() }
        .onChange(of: periodUnit) { oldUnit, newUnit in
            convertPeriod(from: oldUnit, to: newUnit)
        }
    }

    // MARK: Uitkomst

    @ViewBuilder
    private func resultBlock(_ plan: SavingsGoalPlan) -> some View {
        GlassBlock(title: "Uitkomst", symbol: "target",
                   subtitle: "Beide antwoorden, direct bijgewerkt", tint: Theme.olive.opacity(0.3)) {
            if plan.cleanGoal <= 0 {
                EmptyHint(symbol: "target", title: "Vul je doelbedrag in",
                          message: "Dan zie je hoeveel je per maand moet sparen en wanneer je klaar bent.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)], spacing: 10) {
                    neededTile(plan)
                    doneTile(plan)
                }
                progressRow(plan)
                statusLine(plan)
                if !plan.isReached && abs(plan.cleanMonthly - plan.requiredMonthly) > 0.004 {
                    ChipButton(title: "Neem benodigde inleg over", symbol: "arrow.down.circle") {
                        monthly = plan.requiredMonthly
                    }
                }
                Text("Rente wordt per maand bijgeschreven en je inleg komt aan het eind van de maand. Rendement is een aanname, geen garantie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Antwoord 1: hoeveel per maand om op tijd te zijn.
    private func neededTile(_ plan: SavingsGoalPlan) -> SavingsGoalResultTile {
        if plan.isReached {
            return SavingsGoalResultTile(title: "Hoeveel per maand?", value: "Niets nodig",
                                         caption: "Je hebt het doelbedrag al.", color: Theme.positive)
        }
        let month = Fmt.month(plan.deadlineMonth(from: store.now))
        return SavingsGoalResultTile(title: "Hoeveel per maand?", value: Fmt.euro(plan.requiredMonthly),
                                     caption: "om \(Fmt.euroWhole(plan.cleanGoal)) te hebben in \(month)")
    }

    /// Antwoord 2: wanneer ben je klaar met je eigen inleg.
    private func doneTile(_ plan: SavingsGoalPlan) -> SavingsGoalResultTile {
        if plan.isReached {
            return SavingsGoalResultTile(title: "Wanneer klaar?", value: "Nu al",
                                         caption: "Je startbedrag is genoeg.", color: Theme.positive)
        }
        guard let n = plan.monthsToGoal else {
            let caption = plan.cleanMonthly > 0
                ? "Met \(Fmt.euro(plan.cleanMonthly)) per maand lukt dat niet binnen 100 jaar."
                : "Vul een inleg per maand in om dit te zien."
            return SavingsGoalResultTile(title: "Wanneer klaar?", value: "Niet haalbaar",
                                         caption: caption, color: Theme.negative)
        }
        let month = Fmt.month(store.now.adding(n))
        return SavingsGoalResultTile(title: "Wanneer klaar?", value: "Over \(Fmt.duration(months: n))",
                                     caption: "In \(month) met \(Fmt.euro(plan.cleanMonthly)) per maand.",
                                     color: plan.isOnTrack ? Theme.positive : Theme.warning)
    }

    @ViewBuilder
    private func progressRow(_ plan: SavingsGoalPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressBar(progress: plan.progress, tint: Theme.accent, height: 8)
            HStack {
                Text("Al gespaard \(Fmt.euroWhole(plan.cleanStart))")
                Spacer(minLength: 8)
                Text("Doel \(Fmt.euroWhole(plan.cleanGoal))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusLine(_ plan: SavingsGoalPlan) -> some View {
        if plan.isReached {
            Label("Je hebt dit bedrag al gespaard.", systemImage: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
        } else if plan.isOnTrack {
            Label("Met \(Fmt.euro(plan.cleanMonthly)) per maand ben je op tijd.", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
        } else if let n = plan.monthsToGoal {
            VStack(alignment: .leading, spacing: 3) {
                Label("Je bent \(Fmt.duration(months: n - plan.months)) te laat voor je termijn.",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                Text("Je mist \(Fmt.euro(plan.shortfallMonthly)) per maand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label("Met deze inleg haal je het niet binnen 100 jaar.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.negative)
                Text("Voor je termijn heb je \(Fmt.euro(plan.requiredMonthly)) per maand nodig.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Invoer

    @ViewBuilder
    private func goalBlock(_ plan: SavingsGoalPlan) -> some View {
        GlassBlock(title: "Je spaardoel", symbol: "flag.checkered") {
            NumberRow(title: "Doelbedrag", value: $goal)
            NumberRow(title: "Al gespaard", value: $start)
            Picker("Termijn", selection: $useDate) {
                Text("Over een periode").tag(false)
                Text("Op een datum").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if useDate {
                DatePicker("Streefdatum", selection: $targetDate, in: store.now.adding(1).firstDay...,
                           displayedComponents: .date)
            } else {
                NumberRow(title: "Over", value: $periodValue, unit: .plain(periodUnit.title), maxDigits: 2)
                Picker("Eenheid", selection: $periodUnit) {
                    ForEach(SavingsGoalPeriodUnit.allCases) { unit in Text(unit.title).tag(unit) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text("Termijn: \(Fmt.duration(months: plan.months)), tot en met \(Fmt.month(plan.deadlineMonth(from: store.now))).")
                .font(.caption)
                .foregroundStyle(.secondary)
            NumberRow(title: "Mijn inleg per maand", value: $monthly)
        }
    }

    @ViewBuilder
    private func rateBlock(_ plan: SavingsGoalPlan) -> some View {
        let settings = store.data.settings
        GlassBlock(title: "Rendement", symbol: "percent",
                   subtitle: "\(Fmt.percent(currentRate, digits: 2)) per jaar") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(SavingsRatePreset.allCases) { option in
                    SavingsGoalPresetTile(
                        title: option.title,
                        detail: Fmt.percent(option.rate(savingsRate: settings.savingsRate, customRate: customRate), digits: 2),
                        selected: preset == option
                    ) { preset = option }
                }
            }
            if preset == .custom {
                NumberRow(title: "Rendement per jaar", value: $customRate, unit: .percent, maxDigits: 2)
            } else if preset == .savings {
                Text("De spaarrente komt uit Instellingen. Daar kun je hem aanpassen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("In koopkracht van vandaag", isOn: $realTerms)
            if realTerms {
                Text("Alle bedragen zijn in euro's van vandaag. Er is gerekend met \(Fmt.percent(settings.inflation)) inflatie per jaar, dus met \(Fmt.percent(plan.effectiveReturn, digits: 2)) reëel rendement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Wat als?

    @ViewBuilder
    private func whatIfBlock(_ plan: SavingsGoalPlan) -> some View {
        GlassBlock(title: "Wat als ik meer inleg?", symbol: "plus.circle", subtitle: "Per maand extra") {
            HStack(spacing: 10) {
                ForEach(plan.whatIfs) { item in
                    SavingsGoalWhatIfButton(title: "+" + Fmt.euroWhole(item.extra), caption: whatIfCaption(item)) {
                        monthly = plan.cleanMonthly + item.extra
                    }
                }
            }
            Text("Tik op een bedrag om het bij je inleg te tellen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func whatIfCaption(_ item: SavingsGoalWhatIf) -> String {
        if item.becomesReachable { return "dan haalbaar" }
        guard let saved = item.monthsSaved else { return "nog niet haalbaar" }
        if saved <= 0 { return "geen verschil" }
        return shortDuration(saved) + " eerder"
    }

    private func shortDuration(_ months: Int) -> String {
        let years = months / 12
        let rest = months % 12
        if years == 0 { return "\(rest) mnd" }
        if rest == 0 { return "\(years) jr" }
        return "\(years) jr \(rest) mnd"
    }

    // MARK: Grafiek

    @ViewBuilder
    private func chartBlock(_ plan: SavingsGoalPlan) -> some View {
        let mine = plan.series(monthly: plan.cleanMonthly, months: plan.chosenOutcome.months)
        let showNeeded = abs(plan.cleanMonthly - plan.requiredMonthly) > 0.5
        let needed: [Double] = showNeeded ? plan.series(monthly: plan.requiredMonthly, months: plan.months) : []
        GlassBlock(title: "Verloop", symbol: "chart.xyaxis.line", subtitle: "Saldo tegenover je doel") {
            SavingsGoalChart(mine: mine, needed: needed, goal: plan.cleanGoal, start: store.now)
        }
    }

    // MARK: Ingelegd en rente

    @ViewBuilder
    private func splitBlock(_ plan: SavingsGoalPlan) -> some View {
        let o = outcome(plan)
        GlassBlock(title: "Ingelegd en rente", symbol: "chart.pie", subtitle: "Na \(Fmt.duration(months: o.months))") {
            Picker("Inleg", selection: $scenario) {
                ForEach(SavingsGoalScenario.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            BigAmount(value: o.balance, font: .system(.title, design: .rounded, weight: .bold))
            ProgressBar(progress: o.balance > 0 ? o.deposited / o.balance : 0, tint: Theme.flowSaved, height: 10)
            HStack(spacing: 8) {
                StatTile(title: "Totaal", value: Fmt.euroWhole(o.balance))
                StatTile(title: "Ingelegd", value: Fmt.euroWhole(o.deposited), color: Theme.flowSaved)
                StatTile(title: "Rente", value: Fmt.euroWhole(o.interest),
                         color: o.interest >= 0 ? Theme.positive : Theme.negative)
            }
            Text(splitExplanation(o, realTerms: plan.realTerms))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func outcome(_ plan: SavingsGoalPlan) -> SavingsGoalOutcome {
        scenario == .mine ? plan.chosenOutcome : plan.requiredOutcome
    }

    private func splitExplanation(_ o: SavingsGoalOutcome, realTerms: Bool) -> String {
        var text: String
        if o.interest >= 0 {
            text = "Zelf leg je \(Fmt.euroWhole(o.deposited)) in, het rendement levert \(Fmt.euroWhole(o.interest)) op."
        } else {
            text = "Het rendement ligt onder de inflatie: je verliest \(Fmt.euroWhole(-o.interest)) aan koopkracht."
        }
        if realTerms { text += " Bedragen in euro's van vandaag." }
        return text
    }

    // MARK: Tabel per jaar

    @ViewBuilder
    private func tableBlock(_ plan: SavingsGoalPlan) -> some View {
        let o = outcome(plan)
        let rows = plan.yearRows(monthly: o.monthly, months: o.months)
        let limit = 6
        let shown: [SavingsGoalYearRow] = showAllRows ? rows : Array(rows.prefix(limit))
        GlassBlock(title: "Per jaar", symbol: "tablecells", subtitle: scenario.title) {
            SavingsGoalTable(rows: shown, goal: plan.cleanGoal)
            if rows.count > limit {
                ChipButton(title: showAllRows ? "Toon minder" : "Toon alle \(rows.count) rijen",
                           symbol: showAllRows ? "chevron.up" : "chevron.down") {
                    showAllRows.toggle()
                }
            }
        }
    }

    // MARK: Bewaren

    @ViewBuilder
    private func saveBlock(_ plan: SavingsGoalPlan) -> some View {
        GlassBlock(title: "Bewaar dit doel", symbol: "tray.and.arrow.down", subtitle: "Maak er een spaarpot of doel van") {
            HStack(spacing: 12) {
                Text("Naam")
                Spacer(minLength: 12)
                TextField("Spaardoel", text: $name)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220)
            }
            Text("Inleg: \(Fmt.euro(plan.savedMonthly)) per maand (je eigen inleg, of de benodigde inleg als je die leeg laat). Een spaarpot start met \(Fmt.euroWhole(plan.cleanStart)). Een doel komt bij Doelen te staan.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                ChipButton(title: "Maak er een spaarpot van", symbol: "banknote") { createPot(plan) }
                ChipButton(title: "Maak er een doel van", symbol: "flag.checkered") { createGoal(plan) }
            }
            if let potID = createdPotID {
                NavigationLink(value: Destination.pot(potID)) {
                    Label("Spaarpot gemaakt. Bekijk de spaarpot.", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.positive)
                }
                .buttonStyle(.plain)
            }
            if let goalID = createdGoalID {
                NavigationLink(value: Destination.goal(goalID)) {
                    Label("Doel gemaakt. Bekijk het doel.", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.positive)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Streefdatum voor een spaarpot of doel: de gekozen datum, of het eind van de termijn.
    private func deadlineDate(_ plan: SavingsGoalPlan) -> Date {
        useDate ? targetDate : plan.deadlineMonth(from: store.now).firstDay
    }

    private func createPot(_ plan: SavingsGoalPlan) {
        let color = store.data.pots.count % Theme.palette.count
        let pot = plan.makePot(name: name, colorIndex: color, targetDate: deadlineDate(plan), now: store.now)
        let opening = plan.openingBalance
        store.mutate { $0.addPot(pot, openingBalance: opening) }
        createdPotID = pot.id
    }

    private func createGoal(_ plan: SavingsGoalPlan) {
        let newGoal = plan.makeGoal(name: name, targetDate: deadlineDate(plan))
        store.mutate { $0.addGoal(newGoal) }
        createdGoalID = newGoal.id
    }

    // MARK: Beginwaarden

    /// Vult de calculator eenmalig met een voorbeeld op basis van de instellingen.
    private func loadDefaults() {
        guard !loaded else { return }
        loaded = true
        let settings = store.data.settings
        let example = SavingsGoalPlan.example(savingsRate: settings.savingsRate, inflation: settings.inflation)
        goal = example.goal
        start = example.start
        preset = .savings
        useDate = false
        periodUnit = .years
        periodValue = Double(example.horizonMonths) / 12
        targetDate = store.now.adding(example.horizonMonths).firstDay
        monthly = example.monthly
    }

    /// Bij een andere eenheid blijft de termijn gelijk: 2 jaar wordt 24 maanden.
    private func convertPeriod(from oldUnit: SavingsGoalPeriodUnit, to newUnit: SavingsGoalPeriodUnit) {
        let months = Double(oldUnit.monthCount(periodValue))
        periodValue = newUnit == .years ? (months / 12 * 100).rounded() / 100 : months
    }
}

// MARK: - Onderdelen

/// Grote uitkomst met een titel en een korte uitleg. Beide tegels naast elkaar zijn even hoog.
private struct SavingsGoalResultTile: View {
    let title: String
    let value: String
    let caption: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .tile()
    }
}

/// Keuzetegel voor een rendement. Alle tegels in het raster zijn even groot.
private struct SavingsGoalPresetTile: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .tile(tint: selected ? Theme.accent : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Knop met een bedrag en daaronder hoeveel maanden je eerder klaar bent. Drie naast elkaar zijn even groot.
private struct SavingsGoalWhatIfButton: View {
    let title: String
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .tile()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Tabel met saldo, ingelegd en rente per jaar.
private struct SavingsGoalTable: View {
    let rows: [SavingsGoalYearRow]
    let goal: Double

    var body: some View {
        VStack(spacing: 6) {
            line(label: "Jaar", balance: "Saldo", deposited: "Ingelegd", interest: "Rente", header: true, reached: false)
            ForEach(rows) { row in
                Divider().opacity(0.4)
                line(label: label(for: row), balance: Fmt.euroWhole(row.balance),
                     deposited: Fmt.euroWhole(row.deposited), interest: Fmt.euroWhole(row.interest),
                     header: false, reached: row.balance >= goal)
            }
        }
    }

    private func label(for row: SavingsGoalYearRow) -> String {
        row.isFullYear ? "Jaar \(row.year)" : "Na \(row.months) mnd"
    }

    private func line(label: String, balance: String, deposited: String, interest: String,
                      header: Bool, reached: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 64, alignment: .leading)
            Text(balance).frame(maxWidth: .infinity, alignment: .trailing)
            Text(deposited).frame(maxWidth: .infinity, alignment: .trailing)
            Text(interest).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(header ? Font.caption.weight(.semibold) : Font.caption)
        .foregroundStyle(header ? Color.secondary : (reached ? Theme.positive : Color.primary))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Saldo per maand tegenover het doel. Met "Benodigde inleg" erbij als die afwijkt van je eigen inleg.
private struct SavingsGoalChart: View {
    let mine: [Double]
    let needed: [Double]
    let goal: Double
    let start: YearMonth

    static let mineName = "Mijn inleg"
    static let neededName = "Benodigde inleg"

    private struct Item: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    private var items: [Item] {
        var list: [Item] = []
        add(mine, name: SavingsGoalChart.mineName, to: &list)
        add(needed, name: SavingsGoalChart.neededName, to: &list)
        return list
    }

    /// Voegt hooguit ongeveer 120 punten per lijn toe, plus altijd het laatste punt.
    private func add(_ values: [Double], name: String, to list: inout [Item]) {
        guard values.count > 1 else { return }
        let last = values.count - 1
        let step = max(1, last / 120)
        var indices: [Int] = Array(stride(from: 0, through: last, by: step))
        if indices.last != last { indices.append(last) }
        for i in indices {
            list.append(Item(id: "\(name)-\(i)", date: start.adding(i).firstDay, value: values[i], series: name))
        }
    }

    var body: some View {
        let both = needed.count > 1
        Chart {
            ForEach(items) { item in
                LineMark(x: .value("Maand", item.date), y: .value("Saldo", item.value),
                         series: .value("Reeks", item.series))
                    .foregroundStyle(by: .value("Reeks", item.series))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Doel", goal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Doel").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale(
            domain: both ? [SavingsGoalChart.mineName, SavingsGoalChart.neededName] : [SavingsGoalChart.mineName],
            range: both ? [Theme.accent, Theme.flowInvested] : [Theme.accent])
        .chartYScale(domain: .automatic(includesZero: true))
        .chartAxes(shown: true)
        .frame(height: 210)
    }
}
