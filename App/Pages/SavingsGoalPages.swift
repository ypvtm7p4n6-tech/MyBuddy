import SwiftUI

// MARK: - De pagina

/// De spaardoel-calculator als eigen rekenpagina (`Destination.savingsGoal`): de uitkomst bovenaan, daaronder de invoer, het
/// verloop en de details in een uitklapper. De invoer wordt op dit apparaat onthouden, per account (`SavingsGoalDraft`), zodat
/// je cijfers blijven staan en de kaart Doelen ze kan samenvatten.
struct SavingsGoalPage: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        SavingsGoalPageContent(account: accountPrefsID(auth: auth, cloud: cloud))
    }
}

/// Welke inleg de details (ingelegd en rente, tabel) laten zien.
private enum SavingsGoalScenario: String, CaseIterable, Identifiable {
    case mine, needed
    var id: String { rawValue }
    var title: String { self == .mine ? "Mijn inleg" : "Benodigde inleg" }
}

private struct SavingsGoalPageContent: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var storedDraft: String

    @State private var draft: SavingsGoalDraft
    @State private var scenario: SavingsGoalScenario = .mine
    @State private var showAllRows = false
    @State private var name = "Spaardoel"
    @State private var createdPotID: UUID?
    @State private var createdGoalID: UUID?
    /// Gaat omhoog als een knop of keuze de invoer verandert. De invulvelden bouwen zich dan opnieuw op en tonen
    /// meteen de nieuwe waarde (een veld dat nog de focus heeft, werkt zijn tekst anders niet bij).
    @State private var fieldEpoch = 0

    init(account: String) {
        let key = SavingsGoalDraft.storageKey(account: account)
        _storedDraft = AppStorage(wrappedValue: "", key)
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        _draft = State(initialValue: SavingsGoalDraft.decode(saved) ?? SavingsGoalDraft())
    }

    // MARK: Invoer omzetten naar een plan

    private func currentPlan() -> SavingsGoalPlan {
        let settings = store.data.settings
        return draft.plan(savingsRate: settings.savingsRate, inflation: settings.inflation, now: store.now)
    }

    /// Verandert de invoer en onthoudt dat je zelf iets deed.
    private func edit(_ change: (inout SavingsGoalDraft) -> Void) {
        var copy = draft
        change(&copy)
        copy.edited = true
        draft = copy
    }

    /// Verandert de invoer met een knop of keuze (niet door te typen) en ververst de invulvelden.
    private func pick(_ change: (inout SavingsGoalDraft) -> Void) {
        edit(change)
        fieldEpoch += 1
    }

    /// Koppelt een invulveld aan een onderdeel van de invoer. Dit is voor typen: het veld blijft zijn focus houden.
    private func binding<Value>(_ keyPath: WritableKeyPath<SavingsGoalDraft, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: keyPath] },
                set: { newValue in edit { $0[keyPath: keyPath] = newValue } })
    }

    /// Koppelt een schakelaar aan een onderdeel van de invoer en ververst daarna de invulvelden.
    private func pickBinding<Value>(_ keyPath: WritableKeyPath<SavingsGoalDraft, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: keyPath] },
                set: { newValue in pick { $0[keyPath: keyPath] = newValue } })
    }

    /// Eigen inleg. Laat je het veld leeg (of vul je 0 in), dan geldt de benodigde inleg en toont het veld die.
    private var monthlyBinding: Binding<Double> {
        Binding(get: { currentPlan().monthly },
                set: { newValue in edit { $0.monthly = SavingsGoalDraft.ownMonthly(fromField: newValue) } })
    }

    /// Wisselen tussen een periode en een datum houdt de termijn gelijk.
    private var termModeBinding: Binding<Bool> {
        Binding(get: { draft.useDate },
                set: { newValue in
                    let months = currentPlan().months
                    let first = store.now.adding(months).firstDay
                    pick { d in
                        d.useDate = newValue
                        if newValue {
                            d.targetDate = first
                        } else {
                            d.periodValue = d.periodUnit == .years ? (Double(months) / 12 * 100).rounded() / 100 : Double(months)
                        }
                    }
                })
    }

    /// Bij een andere eenheid blijft de termijn gelijk: 2 jaar wordt 24 maanden.
    private var unitBinding: Binding<SavingsGoalPeriodUnit> {
        Binding(get: { draft.periodUnit },
                set: { newUnit in
                    pick { d in
                        let months = Double(d.periodUnit.monthCount(d.periodValue))
                        d.periodValue = newUnit == .years ? (months / 12 * 100).rounded() / 100 : months
                        d.periodUnit = newUnit
                    }
                })
    }

    private var earliestDate: Date { store.now.adding(1).firstDay }

    private var dateBinding: Binding<Date> {
        Binding(get: { max(draft.targetDate ?? store.now.adding(24).firstDay, earliestDate) },
                set: { newDate in pick { $0.targetDate = newDate } })
    }

    // MARK: Pagina

    var body: some View {
        let plan = currentPlan()
        PageScaffold(title: "Spaardoel berekenen") {
            VStack(spacing: Theme.pageSpacing) {
                resultCard(plan)
                inputCard(plan)
                if plan.cleanGoal > 0 {
                    chartCard(plan)
                    if !plan.isReached {
                        detailsCard(plan)
                    }
                    saveCard(plan)
                }
            }
            .frame(maxWidth: Theme.readableWidth)
        }
        .onChange(of: draft) { _, newValue in
            storedDraft = newValue.edited ? newValue.json : ""
            createdPotID = nil
            createdGoalID = nil
        }
        .onChange(of: name) { _, _ in
            createdPotID = nil
            createdGoalID = nil
        }
    }

    // MARK: Uitkomst

    private func resultCard(_ plan: SavingsGoalPlan) -> some View {
        Card(title: "Uitkomst", symbol: "target", domain: .tools, subtitle: "Beide antwoorden, direct bijgewerkt") {
            if plan.cleanGoal <= 0 {
                EmptyHint(symbol: "target", title: "Vul je doelbedrag in",
                          message: "Dan zie je hoeveel je per maand moet sparen en wanneer je klaar bent.")
            } else {
                resultContent(plan)
            }
        }
    }

    private func resultContent(_ plan: SavingsGoalPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            FigureRow {
                neededTile(plan)
                doneTile(plan)
            }
            progressRow(plan)
            statusLine(plan)
            if !plan.isReached && abs(plan.cleanMonthly - plan.requiredMonthlyWhole) > 0.004 {
                ActionButton(title: "Neem benodigde inleg over", symbol: "arrow.down.circle") {
                    pick { $0.monthly = nil }
                }
            }
            PlanningFootnote("Rente wordt per maand bijgeschreven en je inleg komt aan het eind van de maand. Het bedrag per maand is naar boven afgerond, zodat je het doel zeker haalt. Rendement is een aanname, geen garantie.")
        }
    }

    /// Antwoord 1: hoeveel per maand om op tijd te zijn (naar boven afgerond op hele euro's).
    private func neededTile(_ plan: SavingsGoalPlan) -> SavingsGoalResultTile {
        if plan.isReached {
            return SavingsGoalResultTile(title: "Hoeveel per maand?", value: "Niets nodig",
                                         caption: "Je hebt het doelbedrag al.", color: Theme.positive)
        }
        let month = Fmt.month(plan.deadlineMonth(from: store.now))
        return SavingsGoalResultTile(title: "Hoeveel per maand?", value: Fmt.euro(plan.requiredMonthlyWhole),
                                     caption: "om \(Fmt.euro(plan.cleanGoal)) te hebben in \(month)")
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

    private func progressRow(_ plan: SavingsGoalPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressMeter(value: plan.progress, tint: Theme.accent, style: .bar(height: 8),
                          label: "Al gespaard van het doelbedrag",
                          valueText: "\(Fmt.euro(plan.cleanStart)) van \(Fmt.euro(plan.cleanGoal))")
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Al gespaard \(Fmt.euro(plan.cleanStart))")
                    Spacer(minLength: 8)
                    Text("Doel \(Fmt.euro(plan.cleanGoal))")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Al gespaard \(Fmt.euro(plan.cleanStart))")
                    Text("Doel \(Fmt.euro(plan.cleanGoal))")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
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
                PlanningFootnote("Je mist \(Fmt.euro(plan.shortfallMonthlyWhole)) per maand.")
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label("Met deze inleg haal je het niet binnen 100 jaar.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.negative)
                PlanningFootnote("Voor je termijn heb je \(Fmt.euro(plan.requiredMonthlyWhole)) per maand nodig.")
            }
        }
    }

    // MARK: Invoer

    private func inputCard(_ plan: SavingsGoalPlan) -> some View {
        Card(title: "Invoer", symbol: "slider.horizontal.3", domain: .tools) {
            goalFields(plan)
            Divider()
            rateFields(plan)
        }
    }

    @ViewBuilder
    private func goalFields(_ plan: SavingsGoalPlan) -> some View {
        NumberRow(title: "Doelbedrag", value: binding(\.goal))
            .id(fieldEpoch)
        NumberRow(title: "Al gespaard", value: binding(\.start))
            .id(fieldEpoch)
        Picker("Termijn", selection: termModeBinding) {
            Text("Over een periode").tag(false)
            Text("Op een datum").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        termFields
        PlanningFootnote("Termijn: \(Fmt.duration(months: plan.months)), tot en met \(Fmt.month(plan.deadlineMonth(from: store.now))).")
        NumberRow(title: "Mijn inleg per maand", value: monthlyBinding)
            .id(fieldEpoch)
        if draft.edited {
            ActionButton(title: "Begin opnieuw", symbol: "arrow.counterclockwise") {
                createdPotID = nil
                createdGoalID = nil
                name = "Spaardoel"
                draft = SavingsGoalDraft()
                fieldEpoch += 1
            }
        }
    }

    /// De termijn: een datum, of een getal met een eenheid.
    @ViewBuilder
    private var termFields: some View {
        if draft.useDate {
            DatePicker("Streefdatum", selection: dateBinding, in: earliestDate..., displayedComponents: .date)
                .frame(minHeight: Theme.minTapTarget)
        } else {
            NumberRow(title: "Over", value: binding(\.periodValue), unit: .plain(draft.periodUnit.title), maxDigits: 2)
                .id(fieldEpoch)
            Picker("Eenheid", selection: unitBinding) {
                ForEach(SavingsGoalPeriodUnit.allCases) { unit in Text(unit.title).tag(unit) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func rateFields(_ plan: SavingsGoalPlan) -> some View {
        let settings = store.data.settings
        VStack(alignment: .leading, spacing: 2) {
            Text("Rendement")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(Fmt.percent(plan.cleanRate, digits: 2)) per jaar")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(SavingsRatePreset.allCases) { option in
                SavingsGoalPresetTile(
                    title: option.title,
                    detail: Fmt.percent(option.rate(savingsRate: settings.savingsRate, customRate: draft.customRate), digits: 2),
                    selected: draft.preset == option
                ) { pick { $0.preset = option } }
            }
        }
        if draft.preset == .custom {
            NumberRow(title: "Rendement per jaar", value: binding(\.customRate), unit: .percent, maxDigits: 2)
        } else if draft.preset == .savings {
            PlanningFootnote("De spaarrente komt uit Instellingen. Daar kun je hem aanpassen.")
        }
        Toggle("In koopkracht van vandaag", isOn: pickBinding(\.realTerms))
            .frame(minHeight: Theme.minTapTarget)
        if draft.realTerms {
            PlanningFootnote("Alle bedragen zijn in euro's van vandaag. Er is gerekend met \(Fmt.percent(settings.inflation)) inflatie per jaar, dus met \(Fmt.percent(plan.effectiveReturn, digits: 2)) reëel rendement.")
        }
    }

    // MARK: Verloop

    private func chartCard(_ plan: SavingsGoalPlan) -> some View {
        Card(title: "Verloop", symbol: "chart.xyaxis.line", domain: .tools, subtitle: "Saldo tegenover je doel") {
            TrendChart(model: SavingsGoalTrend.model(plan: plan, now: store.now), size: .regular)
        }
    }

    // MARK: Details (uitklappers)

    private func detailsCard(_ plan: SavingsGoalPlan) -> some View {
        Card(title: "Details", symbol: "list.bullet", domain: .tools,
             subtitle: "Wat als je meer inlegt, ingelegd en rente, per jaar") {
            DisclosureGroup("Wat als ik meer inleg?") {
                whatIfFields(plan)
            }
            DisclosureGroup("Ingelegd en rente") {
                splitFields(plan)
            }
            DisclosureGroup("Per jaar") {
                tableFields(plan)
            }
        }
    }

    private func whatIfFields(_ plan: SavingsGoalPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FigureRow(spacing: 8) {
                ForEach(plan.whatIfs) { item in
                    SavingsGoalWhatIfButton(title: "+" + Fmt.euro(item.extra), caption: whatIfCaption(item)) {
                        pick { $0.monthly = plan.cleanMonthly + item.extra }
                    }
                }
            }
            PlanningFootnote("\(PlanningText.tap) op een bedrag om het bij je inleg per maand te tellen.")
        }
        .padding(.top, 8)
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

    private func splitFields(_ plan: SavingsGoalPlan) -> some View {
        let o = outcome(plan)
        return VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Picker("Inleg", selection: $scenario) {
                ForEach(SavingsGoalScenario.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            PlanningFootnote("Na \(Fmt.duration(months: o.months))")
            BigAmount(value: o.balance, font: Theme.titleAmount, label: "Saldo na \(Fmt.duration(months: o.months))")
            ProgressMeter(value: o.balance > 0 ? o.deposited / o.balance : 0, tint: Theme.chartSaved, style: .bar(height: 10),
                          label: "Ingelegd tegenover het saldo",
                          valueText: "\(Fmt.euro(o.deposited)) van \(Fmt.euro(o.balance)) is ingelegd")
            FigureRow {
                StatTile(title: "Totaal", value: Fmt.euro(o.balance))
                StatTile(title: "Ingelegd", value: Fmt.euro(o.deposited), color: Theme.chartSaved)
                StatTile(title: "Rente", value: Fmt.euro(o.interest),
                         color: o.interest >= 0 ? Theme.positive : Theme.negative)
            }
            PlanningFootnote(splitExplanation(o, realTerms: plan.realTerms))
        }
        .padding(.top, 8)
    }

    private func outcome(_ plan: SavingsGoalPlan) -> SavingsGoalOutcome {
        scenario == .mine ? plan.chosenOutcome : plan.requiredOutcome
    }

    private func splitExplanation(_ o: SavingsGoalOutcome, realTerms: Bool) -> String {
        var text: String
        if o.interest >= 0 {
            text = "Zelf leg je \(Fmt.euro(o.deposited)) in, het rendement levert \(Fmt.euro(o.interest)) op."
        } else {
            text = "Het rendement ligt onder de inflatie: je verliest \(Fmt.euro(-o.interest)) aan koopkracht."
        }
        if realTerms { text += " Bedragen in euro's van vandaag." }
        return text
    }

    private func tableFields(_ plan: SavingsGoalPlan) -> some View {
        let o = outcome(plan)
        let rows = plan.yearRows(monthly: o.monthly, months: o.months)
        let limit = 6
        let shown: [SavingsGoalYearRow] = showAllRows ? rows : Array(rows.prefix(limit))
        return VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text(scenario.title)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            SavingsGoalTable(rows: shown, goal: plan.cleanGoal)
            if rows.count > limit {
                ActionButton(title: showAllRows ? "Toon minder" : "Toon alle \(rows.count) rijen",
                             symbol: showAllRows ? "chevron.up" : "chevron.down") {
                    showAllRows.toggle()
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: Bewaren

    private func saveCard(_ plan: SavingsGoalPlan) -> some View {
        Card(title: "Bewaar dit doel", symbol: "tray.and.arrow.down", domain: .tools,
             subtitle: "Maak er een spaarpot of doel van") {
            nameField
            PlanningFootnote("Inleg: \(Fmt.euro(plan.savedMonthly)) per maand (je eigen inleg, of de benodigde inleg als je die leeg laat). Een spaarpot start met \(Fmt.euro(plan.cleanStart)). Een doel komt bij Doelen te staan.")
            // Na een tik is de knop uit, zodat je niet per ongeluk twee keer hetzelfde maakt.
            // Verandert er iets aan de berekening of de naam, dan kan het weer.
            ActionGroup {
                ActionButton(title: "Maak er een spaarpot van", symbol: "banknote") { createPot(plan) }
                    .disabled(createdPotID != nil)
                ActionButton(title: "Maak er een doel van", symbol: "flag.checkered") { createGoal(plan) }
                    .disabled(createdGoalID != nil)
            }
            createdLinks
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Naam")
                .font(.subheadline)
            TextField("Spaardoel", text: $name)
                .padding(.horizontal, 12)
                .frame(minHeight: Theme.minTapTarget)
                .tile()
                .accessibilityLabel("Naam van de spaarpot of het doel")
        }
    }

    /// Na het maken: een bevestiging en een link naar wat er is gemaakt.
    @ViewBuilder
    private var createdLinks: some View {
        if let potID = createdPotID {
            Label("Spaarpot gemaakt.", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
            ActionLink(title: "Bekijk de spaarpot", symbol: "arrow.right", destination: .pot(potID))
        }
        if let goalID = createdGoalID {
            Label("Doel gemaakt.", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
            ActionLink(title: "Bekijk het doel", symbol: "arrow.right", destination: .goal(goalID))
        }
    }

    /// Streefdatum voor een spaarpot of doel: de gekozen datum, of het eind van de termijn.
    private func deadlineDate(_ plan: SavingsGoalPlan) -> Date {
        if draft.useDate, let date = draft.targetDate { return date }
        return plan.deadlineMonth(from: store.now).firstDay
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
}

// MARK: - Onderdelen

/// Een uitkomst met een titel en een korte uitleg. Twee tegels naast elkaar zijn even hoog (in een `FigureRow`).
private struct SavingsGoalResultTile: View {
    let title: String
    let value: String
    let caption: String
    var color: Color = .primary
    @Environment(\.tileFillsHeight) private var fillsHeight

    var body: some View {
        let maxHeight: CGFloat? = fillsHeight ? CGFloat.infinity : nil
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.titleAmount)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .animated(by: value)
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
        .padding(12)
        .tile()
        .accessibilityElement(children: .combine)
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
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .tile(tint: selected ? Theme.accent : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanningPressStyle())
        .animated(by: selected, quick: true)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .tile()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanningPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Tabel met saldo, ingelegd en rente per jaar. Bij grote tekst staat elk jaar als eigen blokje met drie regels, in plaats van
/// vier smalle kolommen.
private struct SavingsGoalTable: View {
    let rows: [SavingsGoalYearRow]
    let goal: Double
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 8) {
            if typeSize.isAccessibilitySize {
                ForEach(rows) { row in
                    stackedRow(row)
                }
            } else {
                headerLine
                ForEach(rows) { row in
                    tableLine(row)
                }
            }
        }
    }

    private func label(for row: SavingsGoalYearRow) -> String {
        row.isFullYear ? "Jaar \(row.year)" : "Na \(row.months) mnd"
    }

    private func reached(_ row: SavingsGoalYearRow) -> Bool { row.balance >= goal }

    /// De rij als zin voor VoiceOver.
    private func speech(_ row: SavingsGoalYearRow) -> String {
        var text = "\(label(for: row)): saldo \(ChartText.euro(row.balance)), ingelegd \(ChartText.euro(row.deposited)), rente \(ChartText.euro(row.interest))"
        if reached(row) { text += ", doel bereikt" }
        return text
    }

    private var headerLine: some View {
        HStack(spacing: 8) {
            Text("Jaar").frame(minWidth: 72, alignment: .leading)
            Text("Saldo").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Ingelegd").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Rente").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }

    private func tableLine(_ row: SavingsGoalYearRow) -> some View {
        VStack(spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    if reached(row) {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                    }
                    Text(label(for: row))
                }
                .frame(minWidth: 72, alignment: .leading)
                Text(Fmt.euro(row.balance)).frame(maxWidth: .infinity, alignment: .trailing)
                Text(Fmt.euro(row.deposited)).frame(maxWidth: .infinity, alignment: .trailing)
                Text(Fmt.euro(row.interest)).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(reached(row) ? Theme.positive : Color.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speech(row))
    }

    private func stackedRow(_ row: SavingsGoalYearRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
            Label(label(for: row), systemImage: reached(row) ? "checkmark.circle.fill" : "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reached(row) ? Theme.positive : Color.primary)
            AmountRow(title: "Saldo", value: Fmt.euro(row.balance))
            AmountRow(title: "Ingelegd", value: Fmt.euro(row.deposited))
            AmountRow(title: "Rente", value: Fmt.euro(row.interest))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speech(row))
    }
}
