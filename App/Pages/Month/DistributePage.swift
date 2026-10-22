import SwiftUI

// Verdelen: wat er van het inkomen van de gekozen maand naar spaarpotten en beleggingen gaat. Een rekenpagina met kaarten:
// elke pot of belegging is een mini-formulier (bedrag of percentage), geen rij in een lijst. De logica zonder SwiftUI staat in
// App/UI/SavingsDisplay.swift (`AllocationEdit`, `DistributeText`), zodat de tests in CoreTests haar meedraaien.

struct DistributePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let month = router.focusMonth
        let beforeStart = month < store.data.startMonth
        PageScaffold(title: "Verdelen") {
            VStack(spacing: Theme.pageSpacing) {
                MonthBar()
                DistributeSummaryCard(month: month)
                DistributePotsCard(month: month)
                DistributeHoldingsCard(month: month)
                DistributeTransferDayCard(month: month)
            }
            .frame(maxWidth: Theme.readableWidth)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { change { $0.applyDefaultAllocations(in: month) } } label: {
                        Label("Standaardverdeling toepassen", systemImage: "arrow.counterclockwise")
                    }
                    Button { change { $0.spreadRemainingOverPots(in: month) } } label: {
                        Label("Rest over potten verdelen", systemImage: "divide")
                    }
                    Button { change { $0.clearAllocations(in: month) } } label: {
                        Label("Alles op nul zetten", systemImage: "xmark.circle")
                    }
                } label: {
                    Label("Meer", systemImage: "ellipsis")
                }
                .help("Meer")
                .disabled(beforeStart)
            }
        }
    }

    private func change(_ edit: (inout FinanceData) -> Void) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.mutate(edit)
        }
    }
}

// MARK: - Nog te verdelen

/// Het getal van de maand: wat er nog te verdelen is, hoeveel er al is verdeeld, en waar de verdeling niet klopt.
private struct DistributeSummaryCard: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        // Dezelfde formule als overal: inkomen − uitgaven van de bank − verdeeld − belegd.
        let figures = d.monthFigures(month)
        let left = CentsMath.value(figures.remaining)
        let allocatedCents = CentsMath.add(figures.saved, figures.invested)
        let availableCents = figures.available
        let over = left < 0
        let progress: Double = availableCents > 0 ? Double(allocatedCents) / Double(availableCents) : 0
        // Nu en in komende maanden is het "Nog te verdelen", in het verleden "Overgehouden" (termenlijst).
        let label = MoneyLabels.remainingLabel(of: month, current: store.now)
        Card(title: label, symbol: "square.split.2x2", domain: .money,
             subtitle: month > store.now ? "Verwacht" : nil) {
            BigAmount(value: left, color: over ? Theme.negative : Color.primary, label: label)
            ProgressMeter(value: progress, tint: over ? Theme.negative : Theme.accent, style: .bar(height: 10),
                          label: "Verdeeld",
                          valueText: "\(Fmt.euro(CentsMath.value(allocatedCents))) van \(Fmt.euro(CentsMath.value(availableCents)))")
            FigureRow {
                StatTile(title: "Inkomen", value: Fmt.euro(CentsMath.value(figures.income)))
                StatTile(title: "Uitgaven", value: Fmt.euro(CentsMath.value(figures.expenses)))
                StatTile(title: "Verdeeld", value: Fmt.euro(CentsMath.value(allocatedCents)))
            }
            notes(d, figures: figures)
        }
    }

    /// Wat er bij het getal hoort: uit spaarpotten betaald, afronding, een maand vóór de start, en waar de verdeling niet klopt.
    @ViewBuilder
    private func notes(_ d: FinanceData, figures: MonthFigures) -> some View {
        let fromPots = CentsMath.value(figures.fromPots)
        // Waar de verdeling niet klopt (percentages samen boven 100%, of meer verdeeld dan er is): tekst van de rekenmotor.
        let warnings = d.allocationWarnings(in: month)
        if fromPots > 0 {
            MonthExplanation(text: "Waarvan \(Fmt.euro(fromPots)) uit een spaarpot. Dat telt niet mee in dit bedrag.")
        }
        if MonthBoard(month: month, figures: figures).roundingHidesSum {
            RoundingNote()
        }
        if month < d.startMonth {
            MonthExplanation(text: "Maanden vóór je startmaand (\(Fmt.month(d.startMonth))) tellen niet mee: daar verdeel je niets.")
        }
        if figures.available < 0 {
            MonthWarningLine(text: "Je uitgaven zijn hoger dan je inkomen deze maand.", color: Theme.negative)
        }
        ForEach(warnings, id: \.message) { warning in
            AllocationWarningLabel(warning: warning)
        }
        if let explanation = DistributeText.percentExplanation(d, month: month) {
            MonthExplanation(text: explanation)
        }
    }
}

// MARK: - Spaarpotten en beleggingen

/// De inleg van elke spaarpot in de gekozen maand.
private struct DistributePotsCard: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        Card(title: "Spaarpotten", symbol: "tray.full", domain: .saving, headerLink: .pots) {
            if d.pots.isEmpty {
                EmptyHint(symbol: "tray", title: "Nog geen spaarpotten",
                          message: "Maak een spaarpot, dan kun je hier geld naartoe verdelen.",
                          actionTitle: "Naar Spaarpotten", action: { router.open(.pots) })
            }
            ForEach(d.pots) { pot in
                MonthAllocationRow(id: pot.id, name: pot.name, symbol: pot.symbol, color: Theme.color(pot.colorIndex),
                                   month: month,
                                   caption: DistributeText.transferCaption(d, id: pot.id, month: month, today: store.today))
                    .disabled(month < d.startMonth)
            }
            if !d.pots.isEmpty || !d.holdings.isEmpty {
                MonthExplanation(text: "Wat je hier invult geldt voor \(Fmt.month(month)). Kies Percentage om een deel van je inkomen te verdelen: het bedrag rekent mee als je inkomen verandert. Een ander percentage in één maand mag ook. Wil je het elke maand, kies dan Maak dit je standaard.")
            }
        }
    }
}

/// De inleg van elke belegging in de gekozen maand.
private struct DistributeHoldingsCard: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        Card(title: "Beleggen", symbol: "chart.line.uptrend.xyaxis", domain: .investing, headerLink: .portfolio) {
            if d.holdings.isEmpty {
                EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                          message: "Voeg een belegging toe, dan kun je hier geld naartoe verdelen.",
                          actionTitle: "Naar Beleggingen", action: { router.open(.portfolio) })
            }
            ForEach(d.holdings) { holding in
                MonthAllocationRow(id: holding.id, name: holding.name, symbol: holding.kind.symbol,
                                   color: Theme.color(holding.kind.colorIndex), month: month,
                                   caption: DistributeText.transferCaption(d, id: holding.id, month: month, today: store.today))
                    .disabled(month < d.startMonth)
            }
        }
    }
}

// MARK: - Overschrijfdag

/// Wanneer het geld naar de potten gaat: een uitklapper met de dag van de maand en uitleg.
private struct DistributeTransferDayCard: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var dayBinding: Binding<Int?> {
        let month = month
        return Binding<Int?>(get: { store.data.months[month.key]?.transferDay },
                             set: { value in
                                 withAnimation(reduceMotion ? nil : Theme.motion) {
                                     store.mutate { $0.editPlan(month) { $0.transferDay = value } }
                                 }
                             })
    }

    var body: some View {
        let d = store.data
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    DayPickerRow(title: "Dag van de maand", day: dayBinding, defaultText: "Standaard")
                    MonthExplanation(text: DistributeText.transferExplanation(d, month: month))
                    MonthExplanation(text: "Op de overschrijfdag gaat het bedrag automatisch van je bankrekening naar de spaarpot of belegging. Dat geldt ook voor maanden die nog komen. Tot die dag telt het bedrag niet mee in het saldo van de pot.")
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Overschrijfdag", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Text(DistributeText.transferSummary(d, month: month))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(minHeight: Theme.minTapTarget, alignment: .leading)
            }
        }
    }
}

// MARK: - Eén spaarpot of belegging

/// Eén spaarpot of belegging op de pagina Verdelen: de inleg van deze maand als vast bedrag of als percentage van het
/// inkomen (per maand te overschrijven), met wat het percentage in euro's oplevert, de overschrijfdag en de standaard.
private struct MonthAllocationRow: View {
    let id: UUID
    let name: String
    let symbol: String
    let color: Color
    let month: YearMonth
    /// "Wordt overgeschreven op de 25e · salarisdag" (de pagina stelt dit samen uit de rekenmotor).
    let caption: String

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var modeBinding: Binding<ContributionMode> {
        Binding(get: { store.data.allocationRule(id, in: month).isPercent ? ContributionMode.percentage : ContributionMode.fixed },
                set: { newMode in
                    withAnimation(reduceMotion ? nil : Theme.motion) {
                        store.mutate { AllocationEdit.setMode(&$0, id: id, month: month, to: newMode) }
                    }
                })
    }

    private var amountBinding: Binding<Double> {
        Binding(get: { store.data.allocation(id, in: month) },
                set: { value in store.mutate { AllocationEdit.setAmount(&$0, id: id, month: month, amount: value) } })
    }

    private var percentBinding: Binding<Double> {
        Binding(get: {
            if case .percent(let rule) = store.data.allocationRule(id, in: month) { return rule.percent }
            return 0
        }, set: { value in
            store.mutate { AllocationEdit.setPercent(&$0, id: id, month: month, percent: value) }
        })
    }

    private var basisBinding: Binding<IncomeBasis> {
        Binding(get: {
            if case .percent(let rule) = store.data.allocationRule(id, in: month) { return rule.basis }
            return IncomeBasis.salary
        }, set: { newBasis in
            withAnimation(reduceMotion ? nil : Theme.motion) {
                store.mutate { AllocationEdit.setBasis(&$0, id: id, month: month, to: newBasis) }
            }
        })
    }

    var body: some View {
        let d = store.data
        let effective = d.effectiveAllocation(id, in: month)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: symbol, color: color, size: 32)
                Text(name)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 6)
                if effective.isOverride {
                    Text("Afwijkend")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.warning)
                }
            }
            ContributionFields(mode: modeBinding, amount: amountBinding, percent: percentBinding, basis: basisBinding,
                               allowsNegativeAmount: true,
                               resolvedAmount: effective.rule.isPercent ? effective.amount : nil,
                               resolvedNote: effective.rule.isPercent ? effective.rule.summary : nil,
                               footnote: noIncomeNote(d, rule: effective.rule), subject: name)
            MonthExplanation(text: caption)
            if effective.isOverride {
                standardRow(d)
            }
        }
        .padding(12)
        .tile()
    }

    /// Een percentage van niets is niets: zeg dat, anders lijkt het veld stuk.
    private func noIncomeNote(_ d: FinanceData, rule: AllocationRule) -> String? {
        guard case .percent(let percent) = rule, d.incomeBases(in: month).cents(for: percent.basis) == 0 else { return nil }
        let what = percent.basis == .salary ? "salaris" : "inkomen"
        return "Er is in \(Fmt.month(month)) geen \(what): het percentage geeft nu € 0."
    }

    /// Wat de standaard is, met de knoppen om daarnaar terug te gaan of van deze maand de standaard te maken.
    @ViewBuilder
    private func standardRow(_ d: FinanceData) -> some View {
        let standard = d.defaultAllocationRule(id, in: month)
        MonthExplanation(text: "Standaard: \(standard?.summary ?? Fmt.euro(0))")
        ActionGroup {
            ActionButton(title: "Terug naar standaard", symbol: "arrow.counterclockwise") {
                withAnimation(reduceMotion ? nil : Theme.motion) {
                    store.mutate { AllocationEdit.resetToStandard(&$0, id: id, month: month) }
                }
            }
            // Van een maand in het verleden maak je geen standaard: dat gaat over wat er vanaf nu gebeurt.
            if month >= store.now {
                ActionButton(title: "Maak dit je standaard", symbol: "pin") {
                    let current = store.now
                    withAnimation(reduceMotion ? nil : Theme.motion) {
                        store.mutate { AllocationEdit.makeStandard(&$0, id: id, month: month, current: current) }
                    }
                }
            }
        }
    }
}
