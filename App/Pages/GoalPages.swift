import SwiftUI
import Charts

// MARK: - Alle doelen

struct GoalsPage: View {
    @Environment(AppStore.self) private var store
    @State private var newGoal: LifeGoal?

    var body: some View {
        let d = store.data
        PageScaffold(title: "Doelen") {
            VStack(spacing: Theme.pageSpacing) {
                if d.goals.isEmpty {
                    GlassBlock(title: "Nog geen doelen", symbol: "flag.checkered") {
                        EmptyHint(symbol: "flag.checkered", title: "Wat wil je bereiken?",
                                  message: "Met pensioen, een vakantie, parttime werken of iets eigens. De app rekent uit wat je nodig hebt en hoe lang het duurt.")
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.pageSpacing, alignment: .top)],
                              spacing: Theme.pageSpacing) {
                        ForEach(d.goals) { goal in GoalCard(goal: goal) }
                    }
                }

                GlassBlock(title: "Nieuw doel", symbol: "plus.circle.fill") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(GoalKind.allCases) { kind in
                            Button { newGoal = d.goalTemplate(kind) } label: {
                                Label(kind.title, systemImage: kind.symbol)
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .glassButton()
                        }
                    }
                }
            }
        }
        .sheet(item: $newGoal) { goal in GoalEditSheet(goal: goal, isNew: true) }
    }
}

struct GoalCard: View {
    @Environment(AppStore.self) private var store
    let goal: LifeGoal

    var body: some View {
        let a = store.data.analyze(goal, current: store.now)
        NavigationLink(value: Destination.goal(goal.id)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    SymbolBadge(symbol: goal.kind.symbol, color: Theme.accent, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(goal.name).font(.headline).lineLimit(1)
                        Text(goal.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressBar(progress: a.progress, tint: Theme.accent, height: 10)
                HStack {
                    Text("\(Fmt.euroWhole(a.inputs.start)) van \(Fmt.euroWhole(a.inputs.target))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(a.monthsToGoal.map { $0 == 0 ? "Bereikt" : "over \(Fmt.duration(months: $0))" } ?? "niet binnen 100 jaar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(a.monthsToGoal == nil ? Theme.negative : Theme.accent)
                }
            }
            .padding(Theme.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Eén doel

struct GoalDetailPage: View {
    let goalID: UUID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        if let goal = store.data.goal(goalID) {
            content(goal)
        } else {
            PageScaffold(title: "Doel") {
                EmptyHint(symbol: "questionmark.folder", title: "Dit doel bestaat niet meer")
            }
        }
    }

    @ViewBuilder
    private func content(_ goal: LifeGoal) -> some View {
        let d = store.data
        let now = store.now
        let a = d.analyze(goal, current: now)

        PageScaffold(title: goal.name) {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: goal.kind.title, symbol: goal.kind.symbol, tint: Theme.olive.opacity(0.3)) {
                    HStack(spacing: 18) {
                        ZStack {
                            ProgressRing(progress: a.progress, tint: Theme.accent, lineWidth: 10)
                                .frame(width: 96, height: 96)
                            Text(Fmt.percent(min(a.progress, 9.99), digits: 0)).font(.headline)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Benodigd").font(.caption).foregroundStyle(.secondary)
                            BigAmount(value: a.inputs.target, font: .system(.title, design: .rounded, weight: .bold))
                            Text("Nu \(Fmt.euroWhole(a.inputs.start))").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    reachText(goal, a)
                    deadlineText(goal, a)
                }

                GlassBlock(title: "Zo is het berekend", symbol: "function") {
                    Text(explanation(goal, a))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        StatTile(title: "Bron", value: a.inputs.sourceName)
                        StatTile(title: "Inleg per maand", value: Fmt.euro(a.inputs.monthly))
                        StatTile(title: "Rendement na kosten", value: Fmt.percent(a.inputs.nominalReturn))
                        StatTile(title: goal.inflationAdjusted ? "Reëel rendement" : "Gebruikt rendement",
                                 value: Fmt.percent(a.inputs.effectiveReturn))
                    }
                    HStack(spacing: 10) {
                        ChipButton(title: "Doel aanpassen", symbol: "pencil") { showEdit = true }
                    }
                }

                AcceleratorsSection(goal: goal)

                ChipButton(title: "Doel verwijderen", symbol: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(isPresented: $showEdit) { GoalEditSheet(goal: goal, isNew: false) }
        .confirmationDialog("Dit doel verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder \(goal.name)", role: .destructive) {
                let id = goal.id
                store.mutate { $0.deleteGoal(id) }
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func reachText(_ goal: LifeGoal, _ a: GoalAnalysis) -> some View {
        if let months = a.monthsToGoal {
            if months == 0 {
                Label("Je hebt dit doel al bereikt.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Bij je huidige inleg haal je dit over \(Fmt.duration(months: months)).", systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                    if let month = a.reachMonth {
                        Text("Dat is in \(Fmt.month(month))" + (a.reachAge.map { ", als je ongeveer \(Int($0)) jaar bent" } ?? "") + ".")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Label("Met je huidige inleg en rendement haal je dit niet binnen 100 jaar. Kijk bij de versnellers hieronder.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.negative)
        }
    }

    @ViewBuilder
    private func deadlineText(_ goal: LifeGoal, _ a: GoalAnalysis) -> some View {
        if let date = goal.targetDate, let until = a.monthsUntilDeadline {
            VStack(alignment: .leading, spacing: 3) {
                if until <= 0 {
                    Text("Je streefdatum (\(Fmt.date(date))) is verstreken.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Streefdatum \(Fmt.month(YearMonth(date: date))): \(a.onTrack == true ? "je ligt op schema" : "je loopt achter").",
                          systemImage: a.onTrack == true ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(a.onTrack == true ? Theme.positive : Theme.warning)
                    if let needed = a.requiredMonthlyForDeadline {
                        Text("Om op tijd te zijn heb je \(Fmt.euro(needed)) per maand nodig; nu is dat \(Fmt.euro(a.inputs.monthly)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func explanation(_ goal: LifeGoal, _ a: GoalAnalysis) -> String {
        let d = store.data
        switch goal.kind {
        case .retirement:
            let net = max(0, goal.monthlySpending - goal.otherMonthlyIncome)
            return "(\(Fmt.euro(goal.monthlySpending)) − \(Fmt.euro(goal.otherMonthlyIncome))) × 12 ÷ \(Fmt.percent(goal.withdrawalRate)) = \(Fmt.euro(Growth.capitalNeeded(monthlyAmount: net, withdrawalRate: goal.withdrawalRate))). Zo veel kapitaal heb je nodig om elke maand op te nemen zonder dat het opraakt (de opnameregel)."
        case .partTime:
            let gap = d.monthlyIncomeGap(for: goal)
            if let years = goal.partTimeYears, years > 0 {
                return "Je mist \(Fmt.euro(gap)) per maand als je \(Fmt.input(goal.hoursFrom > 0 ? goal.hoursFrom : d.salary.hoursPerWeek)) in plaats van \(Fmt.input(goal.hoursTo)) uur werkt. Voor \(years) jaar heb je daarvoor \(Fmt.euroWhole(a.inputs.target)) nodig."
            }
            return "Je mist \(Fmt.euro(gap)) per maand als je \(Fmt.input(goal.hoursTo)) uur werkt. Zonder einddatum heb je \(Fmt.euroWhole(a.inputs.target)) nodig (\(Fmt.euro(gap)) × 12 ÷ \(Fmt.percent(goal.withdrawalRate)))."
        case .vacation, .custom:
            return "Het doelbedrag is \(Fmt.euro(goal.targetAmount))."
        }
    }
}

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
                HStack(spacing: 10) {
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
                                  actionTitle: "Doel maken") { router.investPath.append(.goals) }
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

// MARK: - Doel maken of aanpassen

struct GoalEditSheet: View {
    let isNew: Bool

    enum Funding: String, CaseIterable, Identifiable {
        case portfolio, pot, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .portfolio: return "Mijn beleggingen"
            case .pot: return "Een spaarpot"
            case .custom: return "Eigen waarden"
            }
        }
    }

    @Environment(AppStore.self) private var store
    @State private var g: LifeGoal
    @State private var funding: Funding = .portfolio
    @State private var potID: UUID?
    @State private var customStart = 0.0
    @State private var customMonthly = 0.0
    @State private var customReturn = 0.05

    init(goal: LifeGoal, isNew: Bool) {
        self.isNew = isNew
        _g = State(initialValue: goal)
        switch goal.funding {
        case .portfolio:
            break
        case .pot(let id):
            _funding = State(initialValue: .pot)
            _potID = State(initialValue: id)
        case .custom(let s, let m, let r):
            _funding = State(initialValue: .custom)
            _customStart = State(initialValue: s)
            _customMonthly = State(initialValue: m)
            _customReturn = State(initialValue: r)
        }
    }

    private var ageBinding: Binding<Double?> {
        Binding(get: { g.currentAge.map { Double($0) } },
                set: { g.currentAge = $0.map { Int($0.rounded()) } })
    }

    private var yearsBinding: Binding<Double?> {
        Binding(get: { g.partTimeYears.map { Double($0) } },
                set: { g.partTimeYears = $0.map { max(1, Int($0.rounded())) } })
    }

    private var gapBinding: Binding<Double?> {
        Binding(get: { g.monthlyGapOverride }, set: { g.monthlyGapOverride = $0 })
    }

    var body: some View {
        SheetScaffold(title: isNew ? "Nieuw doel" : "Doel aanpassen",
                      canSave: !g.name.trimmingCharacters(in: .whitespaces).isEmpty,
                      onSave: { save() }) {
            Section("Naam") {
                TextField("Naam van je doel", text: $g.name)
            }

            switch g.kind {
            case .retirement:
                Section {
                    NumberRow(title: "Gewenst netto per maand", value: $g.monthlySpending)
                    NumberRow(title: "AOW en pensioen per maand", value: $g.otherMonthlyIncome)
                    NumberRow(title: "Opnamepercentage", value: $g.withdrawalRate, unit: .percent, maxDigits: 2)
                    OptionalNumberRow(title: "Ik ken mijn leeftijd", value: ageBinding, unit: .plain("jaar"), defaultValue: 35)
                } header: {
                    Text("Met pensioen")
                } footer: {
                    Text("Bedragen in euro's van vandaag. Met 4% heb je 25 keer je jaarlijkse uitgaven nodig.")
                }
            case .partTime:
                Section {
                    NumberRow(title: "Uren per week nu", value: $g.hoursFrom, unit: .plain("uur"), maxDigits: 1)
                    NumberRow(title: "Uren per week straks", value: $g.hoursTo, unit: .plain("uur"), maxDigits: 1)
                    OptionalNumberRow(title: "Inkomensverlies zelf invullen", value: gapBinding, defaultValue: 500)
                    OptionalNumberRow(title: "Maar een aantal jaren", value: yearsBinding, unit: .plain("jaar"), defaultValue: 10)
                    NumberRow(title: "Andere inkomsten per maand", value: $g.otherMonthlyIncome)
                    NumberRow(title: "Opnamepercentage", value: $g.withdrawalRate, unit: .percent, maxDigits: 2)
                    OptionalNumberRow(title: "Ik ken mijn leeftijd", value: ageBinding, unit: .plain("jaar"), defaultValue: 35)
                } header: {
                    Text("Parttime werken")
                } footer: {
                    Text("Het inkomensverlies wordt uit je salaris berekend, tenzij je het zelf invult. Zonder aantal jaren rekent de app met het opnamepercentage.")
                }
            case .vacation, .custom:
                Section("Doel") {
                    NumberRow(title: "Doelbedrag", value: $g.targetAmount)
                }
            }

            Section {
                OptionalDateRow(title: "Ik wil het halen voor", date: $g.targetDate)
            } header: {
                Text("Streefdatum")
            } footer: {
                Text("Met een datum laat de app zien hoeveel je per maand nodig hebt.")
            }

            Section {
                Picker("Waaruit?", selection: $funding) {
                    ForEach(Funding.allCases) { Text($0.title).tag($0) }
                }
                switch funding {
                case .portfolio:
                    EmptyView()
                case .pot:
                    if store.data.pots.isEmpty {
                        Text("Je hebt nog geen spaarpotten.").foregroundStyle(.secondary)
                    } else {
                        Picker("Spaarpot", selection: $potID) {
                            ForEach(store.data.pots) { pot in Text(pot.name).tag(pot.id as UUID?) }
                        }
                    }
                case .custom:
                    NumberRow(title: "Startbedrag", value: $customStart)
                    NumberRow(title: "Inleg per maand", value: $customMonthly)
                    NumberRow(title: "Rendement per jaar", value: $customReturn, unit: .percent, maxDigits: 2)
                }
                Toggle("In koopkracht van vandaag", isOn: $g.inflationAdjusted)
            } header: {
                Text("Rekenen met")
            } footer: {
                Text("Mijn beleggingen gebruikt je portefeuille, inleg en verwacht rendement. Koopkracht van vandaag houdt rekening met inflatie.")
            }
        }
        .onAppear {
            if funding == .pot && potID == nil { potID = store.data.pots.first?.id }
        }
    }

    private func save() {
        var out = g
        out.name = g.name.trimmingCharacters(in: .whitespaces)
        switch funding {
        case .portfolio:
            out.funding = .portfolio
        case .pot:
            if let id = potID ?? store.data.pots.first?.id { out.funding = .pot(id) } else { out.funding = .portfolio }
        case .custom:
            out.funding = .custom(start: customStart, monthly: customMonthly, annualReturn: customReturn)
        }
        let result = out
        let creating = isNew
        store.mutate { data in
            if creating { data.addGoal(result) } else { data.updateGoal(result) }
        }
    }
}
