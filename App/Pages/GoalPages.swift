import SwiftUI

// MARK: - Het doelenblok op Savings

/// Eén blok voor alles wat met doelen te maken heeft: de eerste twee levensdoelen (pensioen, vakantie, parttime,
/// eigen doel) met voortgang en haalbaarheid, en een korte samenvatting van je spaardoel-berekening.
/// Tikken opent de pagina Doelen.
struct GoalsHubBlock: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        // Het concept van de spaardoel-calculator staat per account op dit apparaat bewaard.
        let account = accountPrefsID(auth: auth, cloud: cloud)
        GoalsHubBlockContent(draftKey: SavingsGoalDraft.storageKey(account: account))
    }
}

private struct GoalsHubBlockContent: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var storedDraft: String

    init(draftKey: String) {
        _storedDraft = AppStorage(wrappedValue: "", draftKey)
    }

    var body: some View {
        let d = store.data
        let goals = Array(d.goals.prefix(2))
        let plan = savingsPlan(d)
        // Alleen een berekend spaardoel en nog geen levensdoelen: ga meteen naar de calculator, niet naar een lege lijst.
        let destination: Destination = (goals.isEmpty && plan != nil) ? .savingsGoal : .goals
        LinkedBlock(title: "Doelen", symbol: "flag.checkered",
                    subtitle: GoalMath.hubSubtitle(goalCount: d.goals.count, hasSavingsGoal: plan != nil),
                    destination: destination) {
            if goals.isEmpty && plan == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wat wil je bereiken? Met pensioen, een vakantie of parttime werken. Of bereken hoeveel je per maand spaart voor een bedrag.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ChipLabel(title: "Maak je eerste doel", symbol: "plus")
                }
            } else {
                VStack(spacing: 8) {
                    if goals.isEmpty {
                        GoalsHubNote(text: "Nog geen levensdoelen. Denk aan pensioen, een vakantie of parttime werken.")
                    } else {
                        ForEach(goals) { goal in
                            GoalsHubRow(goal: goal, analysis: d.analyze(goal, current: store.now))
                        }
                        if d.goals.count > 2 {
                            Text("en nog \(d.goals.count - 2) \(d.goals.count - 2 == 1 ? "doel" : "doelen")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    SavingsGoalHubRow(plan: plan)
                }
            }
        }
        .animation(Theme.motion, value: storedDraft)
    }

    /// Het plan uit de spaardoel-calculator, zodra je daar zelf iets hebt ingevuld.
    private func savingsPlan(_ d: FinanceData) -> SavingsGoalPlan? {
        guard let draft = SavingsGoalDraft.decode(storedDraft), draft.edited else { return nil }
        let plan = draft.plan(savingsRate: d.settings.savingsRate, inflation: d.settings.inflation, now: store.now)
        return plan.cleanGoal > 0 ? plan : nil
    }
}

/// Eén levensdoel in het doelenblok: naam, haalbaarheid, percentage en voortgangsbalk.
private struct GoalsHubRow: View {
    let goal: LifeGoal
    let analysis: GoalAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: goal.kind.symbol, color: Theme.accent, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(analysis.outlook.label)
                        .font(.caption)
                        .foregroundStyle(analysis.outlook.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text(Fmt.percent(min(analysis.progress, 9.99), digits: 0))
                    .font(.footnote.weight(.semibold))
                    .contentTransition(.numericText())
            }
            ProgressBar(progress: analysis.progress, tint: Theme.accent, height: 8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}

/// Het spaardoel in het doelenblok: wat je berekend hebt, of een uitnodiging om dat te doen.
private struct SavingsGoalHubRow: View {
    let plan: SavingsGoalPlan?

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(symbol: "target", color: Theme.accent, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let plan {
                    Text(plan.summaryLine)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                    if let status = ownDepositStatus(plan) {
                        Text(status.text)
                            .font(.caption)
                            .foregroundStyle(status.color)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Spaardoel berekenen")
                        .font(.footnote.weight(.semibold))
                    Text("Hoeveel per maand, of wanneer ben je klaar?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }

    /// Wat je eigen inleg doet, maar alleen als die afwijkt van de benodigde inleg.
    private func ownDepositStatus(_ plan: SavingsGoalPlan) -> (text: String, color: Color)? {
        guard !plan.isReached, abs(plan.cleanMonthly - plan.requiredMonthlyWhole) > 0.004 else { return nil }
        if plan.isOnTrack {
            return ("Met jouw inleg van \(Fmt.euro(plan.cleanMonthly)) per maand ben je op tijd.", Theme.positive)
        }
        if let n = plan.monthsToGoal {
            return ("Met jouw inleg van \(Fmt.euro(plan.cleanMonthly)) per maand ben je klaar over \(Fmt.duration(months: n)).",
                    Theme.warning)
        }
        if plan.cleanMonthly > 0 {
            return ("Met jouw inleg van \(Fmt.euro(plan.cleanMonthly)) per maand haal je het niet binnen 100 jaar.", Theme.negative)
        }
        return ("Zonder eigen inleg haal je het niet binnen 100 jaar.", Theme.negative)
    }
}

/// Korte tegel met een uitleg in het doelenblok.
private struct GoalsHubNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(symbol: "flag.checkered", color: Theme.accent, size: 28)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}

// MARK: - Haalbaarheid in woorden en kleur

private extension GoalOutlook {
    /// Korte tekst voor een kaart of blok.
    var label: String {
        switch self {
        case .notSet: return "Nog geen doelbedrag"
        case .reached: return "Bereikt"
        case .onTrack(let months): return "Op schema, over \(Fmt.duration(months: months))"
        case .behind(let months): return "Loopt achter, over \(Fmt.duration(months: months))"
        case .reachable(let months): return "Over \(Fmt.duration(months: months))"
        case .unreachable: return "Niet haalbaar"
        }
    }

    var color: Color {
        switch self {
        case .notSet: return Color.secondary
        case .reached, .onTrack: return Theme.positive
        case .behind: return Theme.warning
        case .reachable: return Theme.accent
        case .unreachable: return Theme.negative
        }
    }
}

// MARK: - De pagina Doelen

/// De twee onderdelen van de pagina Doelen.
enum GoalsSection: String, CaseIterable, Identifiable {
    case goals, calculator
    var id: String { rawValue }

    var title: String {
        switch self {
        case .goals: return "Mijn doelen"
        case .calculator: return "Spaardoel"
        }
    }
}

/// Eén pagina voor al je doelen. Bovenin kies je tussen je levensdoelen en de spaardoel-calculator.
/// `Destination.savingsGoal` opent dezelfde pagina met de calculator al open.
struct GoalsPage: View {
    @Environment(AppStore.self) private var store
    @State private var section: GoalsSection
    @State private var newGoal: LifeGoal?

    init(initialSection: GoalsSection = .goals) {
        _section = State(initialValue: initialSection)
    }

    private var sectionBinding: Binding<GoalsSection> {
        Binding(get: { section },
                set: { newValue in withAnimation(Theme.motion) { section = newValue } })
    }

    var body: some View {
        PageScaffold(title: "Doelen") {
            VStack(spacing: Theme.pageSpacing) {
                Picker("Onderdeel", selection: sectionBinding) {
                    ForEach(GoalsSection.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(Theme.cardInset)
                .glassCard()

                switch section {
                case .goals:
                    goalsSection
                        .transition(.opacity)
                case .calculator:
                    SavingsGoalCalculator()
                        .transition(.opacity)
                }
            }
            .animation(Theme.motion, value: section)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $newGoal) { goal in GoalEditSheet(goal: goal, isNew: true) }
    }

    /// Onderdeel "Mijn doelen": je levensdoelen en knoppen om een nieuw doel te maken.
    private var goalsSection: some View {
        let d = store.data
        return VStack(spacing: Theme.pageSpacing) {
            if d.goals.isEmpty {
                GlassBlock(title: "Nog geen doelen", symbol: "flag.checkered") {
                    EmptyHint(symbol: "flag.checkered", title: "Wat wil je bereiken?",
                              message: "Met pensioen, een vakantie, parttime werken of iets eigens. De app rekent uit wat je nodig hebt en hoe lang het duurt.")
                }
            } else {
                LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                    ForEach(d.goals) { goal in GoalCard(goal: goal) }
                }
            }

            GlassBlock(title: "Nieuw doel", symbol: "plus.circle.fill",
                       subtitle: "Of reken uit hoeveel je per maand spaart voor een bedrag") {
                ChipGrid {
                    ForEach(GoalKind.allCases) { kind in
                        ChipButton(title: kind.title, symbol: kind.symbol) { newGoal = d.goalTemplate(kind) }
                    }
                    ChipButton(title: "Spaardoel berekenen", symbol: "target") {
                        withAnimation(Theme.motion) { section = .calculator }
                    }
                }
            }
        }
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
                // Onder elkaar: de haalbaarheid kan lang zijn ("Loopt achter, over 11 jaar en 11 maanden").
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Fmt.euro(a.inputs.start)) van \(Fmt.euro(a.inputs.target))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                    Text(a.outlook.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(a.outlook.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
                            Text(Fmt.percent(min(a.progress, 9.99), digits: 0))
                                .font(.headline)
                                .contentTransition(.numericText())
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Benodigd").font(.caption).foregroundStyle(.secondary)
                            BigAmount(value: a.inputs.target, font: .system(.title, design: .rounded, weight: .bold))
                            Text("Nu \(Fmt.euro(a.inputs.start))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
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
                withAnimation(Theme.motion) {
                    store.mutate { $0.deleteGoal(id) }
                }
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func reachText(_ goal: LifeGoal, _ a: GoalAnalysis) -> some View {
        if a.outlook == .notSet {
            Label("Er is nog geen doelbedrag. Pas het doel aan, dan zie je hoe lang het duurt.", systemImage: "pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if let months = a.monthsToGoal {
            if months == 0 {
                Label("Je hebt dit doel al bereikt.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Bij je huidige inleg haal je dit over \(Fmt.duration(months: months)).", systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                    if let month = a.reachMonth {
                        Text("Dat is in \(Fmt.month(month))" + (a.reachAge.map { ", als je ongeveer \(SafeInt.clamped($0.rounded(.down), to: 0...150)) jaar bent" } ?? "") + ".")
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
        if let date = goal.targetDate, let until = a.monthsUntilDeadline, a.outlook != .notSet {
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
                    // Naar boven afgerond, zodat het getoonde bedrag de streefdatum zeker haalt.
                    if let needed = a.requiredMonthlyForDeadlineWhole {
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
                return "Je mist \(Fmt.euro(gap)) per maand als je \(Fmt.input(goal.hoursFrom > 0 ? goal.hoursFrom : d.salary.hoursPerWeek)) in plaats van \(Fmt.input(goal.hoursTo)) uur werkt. Voor \(years) jaar heb je daarvoor \(Fmt.euro(a.inputs.target)) nodig."
            }
            return "Je mist \(Fmt.euro(gap)) per maand als je \(Fmt.input(goal.hoursTo)) uur werkt. Zonder einddatum heb je \(Fmt.euro(a.inputs.target)) nodig (\(Fmt.euro(gap)) × 12 ÷ \(Fmt.percent(goal.withdrawalRate)))."
        case .vacation, .custom:
            return "Het doelbedrag is \(Fmt.euro(goal.targetAmount))."
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
                set: { g.currentAge = $0.map { SafeInt.clamped($0, to: 0...150) } })
    }

    private var yearsBinding: Binding<Double?> {
        Binding(get: { g.partTimeYears.map { Double($0) } },
                set: { g.partTimeYears = $0.map { SafeInt.clamped($0, to: 1...150) } })
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
                Text("Mijn beleggingen gebruikt de waarde van je beleggingen, je inleg en het verwachte rendement. Koopkracht van vandaag houdt rekening met inflatie.")
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
        withAnimation(Theme.motion) {
            store.mutate { data in
                if creating { data.addGoal(result) } else { data.updateGoal(result) }
            }
        }
    }
}
