import SwiftUI

// MARK: - De kaart Doelen op het tabblad Plannen

/// Eén kaart voor alles wat met doelen te maken heeft: de eerste twee levensdoelen (pensioen, vakantie, parttime, eigen doel)
/// met voortgang en haalbaarheid, en altijd de rij "Spaardoel berekenen" (met een samenvatting zodra je iets berekend hebt).
/// De kop opent de pagina Doelen; de rij opent de calculator.
struct GoalsSummaryCard: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        // Het concept van de spaardoel-calculator staat per account op dit apparaat bewaard.
        let account = accountPrefsID(auth: auth, cloud: cloud)
        GoalsSummaryCardContent(draftKey: SavingsGoalDraft.storageKey(account: account))
    }
}

/// Overgangsvorm (tot golf 1c): de oude tabroot Savings roept dit blok nog aan en krijgt nu de nieuwe kaart.
struct GoalsHubBlock: View {
    var body: some View {
        GoalsSummaryCard()
    }
}

private struct GoalsSummaryCardContent: View {
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
        Card(title: "Doelen", symbol: "flag.checkered", domain: .goals,
             subtitle: GoalMath.hubSubtitle(goalCount: d.goals.count, hasSavingsGoal: plan != nil),
             headerLink: destination) {
            cardContent(d, goals: goals, plan: plan)
        }
        .animated(by: storedDraft)
    }

    private func cardContent(_ d: FinanceData, goals: [LifeGoal], plan: SavingsGoalPlan?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if goals.isEmpty {
                PlanningFootnote("Wat wil je bereiken? Met pensioen, een vakantie of parttime werken. Of bereken hoeveel je per maand spaart voor een bedrag.")
                ActionLink(title: "Maak je eerste doel", symbol: "plus", destination: .goals)
            } else {
                ForEach(goals) { goal in
                    // Met het saldo van vandaag (`store.today`), zoals de doelpagina en de versnellers.
                    GoalSummaryTile(goal: goal, analysis: d.analyze(goal, current: store.now, today: store.today))
                }
                if d.goals.count > 2 {
                    Text("en nog \(d.goals.count - 2) \(d.goals.count - 2 == 1 ? "doel" : "doelen")")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            SavingsGoalLinkTile(plan: plan)
        }
    }

    /// Het plan uit de spaardoel-calculator, zodra je daar zelf iets hebt ingevuld.
    private func savingsPlan(_ d: FinanceData) -> SavingsGoalPlan? {
        guard let draft = SavingsGoalDraft.decode(storedDraft), draft.edited else { return nil }
        let plan = draft.plan(savingsRate: d.settings.savingsRate, inflation: d.settings.inflation, now: store.now)
        return plan.cleanGoal > 0 ? plan : nil
    }
}

/// Eén levensdoel in de kaart: naam, haalbaarheid, percentage en voortgangsbalk. Een tik opent het doel.
private struct GoalSummaryTile: View {
    let goal: LifeGoal
    let analysis: GoalAnalysis

    private var hasTarget: Bool { analysis.outlook != .notSet }
    private var percentText: String { Fmt.percent(min(analysis.progress, 9.99), digits: 0) }

    var body: some View {
        PlanningLinkTile(destination: .goal(goal.id)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SymbolBadge(symbol: goal.kind.symbol, color: AppDomain.goals.color, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(goal.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(analysis.outlook.label)
                            .font(.footnote)
                            .foregroundStyle(analysis.outlook.color)
                    }
                    Spacer(minLength: 6)
                    if hasTarget {
                        Text(percentText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                }
                ProgressMeter(value: hasTarget ? analysis.progress : nil, tint: Theme.accent, style: .bar(height: 8),
                              label: "Voortgang \(goal.name)", valueText: percentText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hasTarget ? "\(goal.name), \(percentText) bereikt" : goal.name)
            .accessibilityValue(analysis.outlook.label)
        }
    }
}

/// De rij "Spaardoel berekenen" in de kaart: altijd aanwezig, met de samenvatting van je berekening als je er een hebt.
private struct SavingsGoalLinkTile: View {
    let plan: SavingsGoalPlan?

    var body: some View {
        PlanningLinkTile(destination: .savingsGoal) {
            HStack(alignment: .top, spacing: 10) {
                SymbolBadge(symbol: "function", color: AppDomain.tools.color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spaardoel berekenen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    detail
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let plan {
            Text(plan.summaryLine)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
            if let status = ownDepositStatus(plan) {
                Text(status.text)
                    .font(.footnote)
                    .foregroundStyle(status.color)
            }
        } else {
            Text("Hoeveel per maand, of wanneer ben je klaar?")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
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

// MARK: - Haalbaarheid in woorden en kleur

private extension GoalOutlook {
    /// Korte tekst voor een kaart of rij.
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

    /// De kleur van de tekst; de woorden in `label` dragen de betekenis, de kleur versterkt hem.
    var color: Color {
        switch self {
        case .notSet: return Theme.textSecondary
        case .reached, .onTrack: return Theme.positive
        case .behind: return Theme.warning
        case .reachable: return Theme.accent
        case .unreachable: return Theme.negative
        }
    }
}

// MARK: - De pagina Doelen

/// Wat het blad "Nieuw doel" of "Doel bewerken" moet laten zien.
private struct GoalSheetItem: Identifiable {
    let goal: LifeGoal
    let isNew: Bool
    var id: UUID { goal.id }
}

/// Al je doelen als lijst. Een rij opent het doel; vegen (of het contextmenu) bewerkt of verwijdert het. Nieuw doel, Spaardoel
/// berekenen en Noodbuffer staan achter de plus in de werkbalk.
struct GoalsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var sheetItem: GoalSheetItem?

    var body: some View {
        let d = store.data
        ListScaffold(title: "Doelen") {
            if d.goals.isEmpty {
                emptySections
            } else {
                goalsSection(d)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    addMenuItems
                } label: {
                    Label("Toevoegen", systemImage: "plus")
                }
                .help("Toevoegen")
            }
        }
        .sheet(item: $sheetItem) { item in
            GoalEditSheet(goal: item.goal, isNew: item.isNew)
        }
    }

    // MARK: Onderdelen

    private func goalsSection(_ d: FinanceData) -> some View {
        Section {
            ForEach(d.goals) { goal in
                GoalListRow(goal: goal,
                            analysis: d.analyze(goal, current: store.now, today: store.today),
                            onEdit: { sheetItem = GoalSheetItem(goal: goal, isNew: false) },
                            onDelete: { deleteGoal(goal.id) })
            }
        } header: {
            SectionHeader("Doelen", domain: .goals)
        }
    }

    /// Zonder doelen: uitleg en een volgende stap per soort doel.
    @ViewBuilder
    private var emptySections: some View {
        Section {
            EmptyHint(symbol: "flag.checkered", title: "Wat wil je bereiken?",
                      message: "Met pensioen, een vakantie, parttime werken of iets eigens. De app rekent uit wat je nodig hebt en hoe lang het duurt.")
        } header: {
            SectionHeader("Doelen", domain: .goals)
        }
        Section {
            ForEach(GoalKind.allCases) { kind in
                Button {
                    startGoal(kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
            NavigationRow(title: "Spaardoel berekenen", symbol: "function", domain: .tools,
                          subtitle: "Hoeveel per maand, of wanneer ben je klaar?", destination: .savingsGoal)
            NavigationRow(title: "Noodbuffer", symbol: "shield.lefthalf.filled", domain: .goals,
                          subtitle: "Hoeveel geld houd je achter de hand?", destination: .buffer)
        } header: {
            SectionHeader("Nieuw doel", symbol: "plus.circle")
        }
    }

    /// Het menu achter de plus: een nieuw doel per soort, dan de twee rekenhulpen.
    @ViewBuilder
    private var addMenuItems: some View {
        Section("Nieuw doel") {
            ForEach(GoalKind.allCases) { kind in
                Button {
                    startGoal(kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        }
        Section {
            Button {
                router.open(.savingsGoal)
            } label: {
                Label("Spaardoel berekenen", systemImage: "function")
            }
            Button {
                router.open(.buffer)
            } label: {
                Label("Noodbuffer", systemImage: "shield.lefthalf.filled")
            }
        }
    }

    private func startGoal(_ kind: GoalKind) {
        sheetItem = GoalSheetItem(goal: store.data.goalTemplate(kind), isNew: true)
    }

    private func deleteGoal(_ id: UUID) {
        store.mutate { $0.deleteGoal(id) }
    }
}

/// Eén doel in de lijst: symbool, naam, voortgang en haalbaarheid. De bevestiging van het verwijderen hangt aan de rij zelf.
private struct GoalListRow: View {
    let goal: LifeGoal
    let analysis: GoalAnalysis
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(Router.self) private var router
    @State private var confirmDelete = false

    private var hasTarget: Bool { analysis.outlook != .notSet }
    private var percentText: String { Fmt.percent(min(analysis.progress, 9.99), digits: 0) }

    var body: some View {
        Button {
            router.open(.goal(goal.id))
        } label: {
            rowContent
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasTarget ? "\(goal.name), \(goal.kind.title), \(percentText) bereikt" : "\(goal.name), \(goal.kind.title)")
        .accessibilityValue(analysis.outlook.label)
        .accessibilityAddTraits(.isLink)
        .rowActions(edit: onEdit, delete: { confirmDelete = true })
        .confirmationDialog("Dit doel verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder \(goal.name)", role: .destructive) { onDelete() }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: goal.kind.symbol, color: AppDomain.goals.color, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(goal.kind.title)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                ProgressMeter(value: hasTarget ? analysis.progress : nil, tint: Theme.accent, style: .bar(height: 8),
                              label: "Voortgang \(goal.name)", valueText: percentText)
                if hasTarget {
                    Text("\(Fmt.euro(analysis.inputs.start)) van \(Fmt.euro(analysis.inputs.target))")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(analysis.outlook.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(analysis.outlook.color)
            }
            Spacer(minLength: 8)
            if hasTarget {
                Text(percentText)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
    }
}

// MARK: - Eén doel

/// Een rekenpagina: het doeltype met voortgang, hoe het is berekend, de versnellers en wat is toegepast. "Bewerken" staat in de
/// werkbalk; verwijderen onderaan, met een bevestiging aan de knop zelf.
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
        let a = d.analyze(goal, current: store.now, today: store.today)

        PageScaffold(title: goal.name) {
            VStack(spacing: Theme.pageSpacing) {
                typeCard(goal, a)
                calculationCard(goal, a, data: d)
                AcceleratorsSection(goal: goal)
                deleteButton(goal)
            }
            .frame(maxWidth: Theme.readableWidth)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bewerken") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { GoalEditSheet(goal: goal, isNew: false) }
    }

    // MARK: Blokken

    private func typeCard(_ goal: LifeGoal, _ a: GoalAnalysis) -> some View {
        Card(title: goal.kind.title, symbol: goal.kind.symbol, domain: .goals) {
            GoalProgressHeader(analysis: a)
            reachText(goal, a)
            deadlineText(goal, a)
        }
    }

    private func calculationCard(_ goal: LifeGoal, _ a: GoalAnalysis, data d: FinanceData) -> some View {
        Card(title: "Zo is het berekend", symbol: "function", domain: .tools) {
            PlanningFootnote(explanation(goal, a))
            FigureRow {
                StatTile(title: "Bron", value: a.inputs.sourceName)
                StatTile(title: "Inleg per maand", value: Fmt.euro(a.inputs.monthly))
                StatTile(title: "Rendement per jaar", value: Fmt.percent(a.inputs.nominalReturn))
                StatTile(title: goal.inflationAdjusted ? "Reëel rendement" : "Gebruikt rendement",
                         value: Fmt.percent(a.inputs.effectiveReturn))
            }
            // Een doel kijkt vooruit: bij een salaris om de zoveel weken of dagen rekent het met een gemiddelde maand
            // (een maand met twee uitbetalingen is geen maat voor "elke maand"). Zeg dat.
            if !d.salary.isMonthly, !isCustomFunding(goal) {
                PlanningFootnote("Je salaris komt niet elke maand even vaak binnen. Daarom rekent dit doel met een gemiddelde maand.")
            }
        }
    }

    private func deleteButton(_ goal: LifeGoal) -> some View {
        ActionButton(title: "Doel verwijderen", symbol: "trash", role: .destructive) {
            confirmDelete = true
        }
        .confirmationDialog("Dit doel verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder \(goal.name)", role: .destructive) {
                let id = goal.id
                store.mutate { $0.deleteGoal(id) }
                dismiss()
            }
        }
    }

    // MARK: Teksten

    @ViewBuilder
    private func reachText(_ goal: LifeGoal, _ a: GoalAnalysis) -> some View {
        if a.outlook == .notSet {
            Label("Er is nog geen doelbedrag. Bewerk het doel, dan zie je hoe lang het duurt.", systemImage: "pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
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
                        PlanningFootnote(reachSentence(month: month, age: a.reachAge))
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

    /// "Dat is in oktober 2040, als je ongeveer 61 jaar bent."
    private func reachSentence(month: YearMonth, age: Double?) -> String {
        var text = "Dat is in \(Fmt.month(month))"
        if let age {
            let years = SafeInt.clamped(age.rounded(.down), to: 0...150)
            text += ", als je ongeveer \(years) jaar bent"
        }
        return text + "."
    }

    @ViewBuilder
    private func deadlineText(_ goal: LifeGoal, _ a: GoalAnalysis) -> some View {
        if let date = goal.targetDate, let until = a.monthsUntilDeadline, a.outlook != .notSet {
            VStack(alignment: .leading, spacing: 3) {
                if until <= 0 {
                    PlanningFootnote("Je streefdatum (\(Fmt.date(date))) is verstreken.")
                } else {
                    Label("Streefdatum \(Fmt.month(YearMonth(date: date))): \(a.onTrack == true ? "je ligt op schema" : "je loopt achter").",
                          systemImage: a.onTrack == true ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(a.onTrack == true ? Theme.positive : Theme.warning)
                    // Naar boven afgerond, zodat het getoonde bedrag de streefdatum zeker haalt.
                    if let needed = a.requiredMonthlyForDeadlineWhole {
                        PlanningFootnote("Om op tijd te zijn heb je \(Fmt.euro(needed)) per maand nodig; nu is dat \(Fmt.euro(a.inputs.monthly)).")
                    }
                }
            }
        }
    }

    /// Is het doel gefinancierd met eigen waarden (dan speelt je salarisschema geen rol)?
    private func isCustomFunding(_ goal: LifeGoal) -> Bool {
        if case .custom = goal.funding { return true }
        return false
    }

    /// De uitleg bij het benodigde bedrag. Het uitgerekende bedrag zelf komt altijd uit de rekenmotor (`a.inputs.target`), zodat
    /// de tekst en het getal bovenaan hetzelfde zeggen.
    private func explanation(_ goal: LifeGoal, _ a: GoalAnalysis) -> String {
        let d = store.data
        switch goal.kind {
        case .retirement:
            return "(\(Fmt.euro(goal.monthlySpending)) − \(Fmt.euro(goal.otherMonthlyIncome))) × 12 ÷ \(Fmt.percent(goal.withdrawalRate)) = \(Fmt.euro(a.inputs.target)). Zo veel kapitaal heb je nodig om elke maand op te nemen zonder dat het opraakt (de opnameregel)."
        case .partTime:
            // Het inkomensverlies is een schatting: bij een salaris om de zoveel weken of dagen een gemiddelde maand.
            let gap = d.monthlyIncomeGap(for: goal)
            let average = d.salary.isMonthly ? "" : "gemiddeld "
            if let years = goal.partTimeYears, years > 0 {
                return "Je mist \(average)\(Fmt.euro(gap)) per maand als je \(Fmt.input(goal.hoursFrom > 0 ? goal.hoursFrom : d.salary.hoursPerWeek)) in plaats van \(Fmt.input(goal.hoursTo)) uur werkt. Voor \(years) jaar heb je daarvoor \(Fmt.euro(a.inputs.target)) nodig."
            }
            // Wat je zelf nog aan inkomsten hebt gaat van het verlies af (zoals de rekenmotor het doet).
            let formula = goal.otherMonthlyIncome > 0
                ? "(\(Fmt.euro(gap)) − \(Fmt.euro(goal.otherMonthlyIncome))) × 12 ÷ \(Fmt.percent(goal.withdrawalRate))"
                : "\(Fmt.euro(gap)) × 12 ÷ \(Fmt.percent(goal.withdrawalRate))"
            return "Je mist \(average)\(Fmt.euro(gap)) per maand als je \(Fmt.input(goal.hoursTo)) uur werkt. Zonder einddatum heb je \(Fmt.euro(a.inputs.target)) nodig (\(formula))."
        case .vacation, .custom:
            return "Het doelbedrag is \(Fmt.euro(goal.targetAmount))."
        }
    }
}

/// De ring met het percentage en daarnaast het benodigde bedrag. Bij grote tekst staan ze onder elkaar. Zonder doelbedrag is er
/// geen ring: een ring zonder doel zou "klaar" of "niets" zeggen.
private struct GoalProgressHeader: View {
    let analysis: GoalAnalysis
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasTarget: Bool { analysis.outlook != .notSet }
    private var percentText: String { Fmt.percent(min(analysis.progress, 9.99), digits: 0) }

    var body: some View {
        let layout: AnyLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        layout {
            if hasTarget {
                ring
            }
            amounts
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
        }
    }

    private var ring: some View {
        ZStack {
            ProgressMeter(value: analysis.progress, tint: Theme.accent, style: .ring(lineWidth: 10),
                          label: "Voortgang van dit doel", valueText: percentText)
                .frame(width: 96, height: 96)
            Text(percentText)
                .font(.headline)
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        }
    }

    private var amounts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Benodigd")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            BigAmount(value: analysis.inputs.target, font: Theme.titleAmount, label: "Benodigd")
            Text("Nu \(Fmt.euro(analysis.inputs.start))")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Doel maken of bewerken

struct GoalEditSheet: View {
    let isNew: Bool

    enum Funding: String, CaseIterable, Identifiable {
        case portfolio, pot, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .portfolio: return "Beleggingen"
            case .pot: return "Een spaarpot"
            case .custom: return "Eigen waarden"
            }
        }
    }

    @Environment(AppStore.self) private var store
    /// Het doel zoals het het blad binnenkwam: daarmee zie je of er iets is veranderd (`hasChanges`).
    private let original: LifeGoal
    @State private var g: LifeGoal
    @State private var funding: Funding = .portfolio
    @State private var potID: UUID?
    @State private var customStart = 0.0
    @State private var customMonthly = 0.0
    @State private var customReturn = 0.05

    init(goal: LifeGoal, isNew: Bool) {
        self.isNew = isNew
        self.original = goal
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

    /// Het doel zoals het bewaard zou worden (zonder de naam bij te snijden).
    private func builtGoal() -> LifeGoal {
        var out = g
        switch funding {
        case .portfolio:
            out.funding = .portfolio
        case .pot:
            if let id = potID ?? store.data.pots.first?.id { out.funding = .pot(id) } else { out.funding = .portfolio }
        case .custom:
            out.funding = .custom(start: customStart, monthly: customMonthly, annualReturn: customReturn)
        }
        return out
    }

    private var hasChanges: Bool { builtGoal() != original }

    var body: some View {
        SheetScaffold(title: isNew ? "Nieuw doel" : "Doel bewerken",
                      canSave: !g.name.trimmingCharacters(in: .whitespaces).isEmpty,
                      hasChanges: hasChanges,
                      onSave: { save() }) {
            Section("Naam") {
                TextField("Naam van je doel", text: $g.name)
            }

            kindSection

            Section {
                OptionalDateRow(title: "Ik wil het halen voor", date: $g.targetDate)
            } header: {
                Text("Streefdatum")
            } footer: {
                Text("Met een datum laat de app zien hoeveel je per maand nodig hebt.")
            }

            fundingSection
        }
        .onAppear {
            if funding == .pot && potID == nil { potID = store.data.pots.first?.id }
        }
    }

    /// De velden die bij de soort doel horen.
    @ViewBuilder
    private var kindSection: some View {
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
                Text("Bedragen in euro's van vandaag. Het opnamepercentage is het deel van je kapitaal dat je per jaar opneemt. Met 4% heb je 25 keer je jaarlijkse uitgaven nodig.")
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
    }

    /// Waaruit het doel wordt gefinancierd.
    private var fundingSection: some View {
        Section {
            Picker("Waaruit?", selection: $funding) {
                ForEach(Funding.allCases) { Text($0.title).tag($0) }
            }
            switch funding {
            case .portfolio:
                EmptyView()
            case .pot:
                if store.data.pots.isEmpty {
                    Text("Je hebt nog geen spaarpotten.").foregroundStyle(Theme.textSecondary)
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
            Text("Beleggingen gebruikt de waarde van je beleggingen, je inleg en het verwachte rendement. Koopkracht van vandaag houdt rekening met inflatie.")
        }
    }

    private func save() {
        var out = builtGoal()
        out.name = g.name.trimmingCharacters(in: .whitespaces)
        let result = out
        let creating = isNew
        store.mutate { data in
            if creating { data.addGoal(result) } else { data.updateGoal(result) }
        }
    }
}
