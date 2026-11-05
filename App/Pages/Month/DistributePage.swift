import SwiftUI

// Verdelen: wat er van het inkomen van de gekozen maand naar spaarpotten, beleggingen en de bankrekening gaat. Een rekenpagina met
// kaarten: elke pot, belegging of de bankrekening is een mini-formulier (bedrag, of percentage met een extra bedrag), geen rij in een
// lijst. De rij zelf en de uitklapper met de extra overschrijfdagen staan in DistributeParts.swift. De logica zonder SwiftUI staat in
// App/UI/SavingsDisplay.swift (`AllocationEdit`, `DistributeText`), DistributionText.swift (`BankShareText` en meer) en MoneyFigures.swift
// (`MonthBoard`, `MoneyLabels.left`), zodat de tests in CoreTests haar meedraaien.

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
                DistributeBankCard(month: month)
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
                    Button { change { $0.sendRemainingToBank(in: month) } } label: {
                        Label(BankShareText.restTitle, systemImage: BankShareText.symbol)
                    }
                    .disabled(store.data.unassigned(in: month) <= 0)
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
        let current = store.now
        // Dezelfde formule als overal: inkomen − uitgaven van de bank − verdeeld − belegd. Het getal bij het label kiest
        // `MoneyLabels.left` (via `MonthBoard.left`): nu en straks wat er nog niet is toegewezen (met wat je aan de bankrekening
        // toewees als verdeeld), in het verleden wat er overbleef.
        let figures = d.monthFigures(month)
        let board = MonthBoard(month: month, figures: figures)
        let left = board.left(current: current)
        let over = board.leftIsNegative(current: current)
        let distributed = board.distributedShown(current: current)
        let available = board.available
        let progress: Double = available > 0 ? distributed / available : 0
        // Nu en in komende maanden is het "Nog te verdelen", in het verleden "Overgehouden" (termenlijst).
        let label = MoneyLabels.remainingLabel(of: month, current: current)
        Card(title: label, symbol: "square.split.2x2", domain: .money,
             subtitle: month > current ? "Verwacht" : nil) {
            BigAmount(value: left, color: over ? Theme.negative : Color.primary, label: label)
            ProgressMeter(value: progress, tint: over ? Theme.negative : Theme.accent, style: .bar(height: 10),
                          label: "Verdeeld", valueText: "\(Fmt.euro(distributed)) van \(Fmt.euro(available))")
            FigureRow {
                StatTile(title: "Inkomen", value: Fmt.euro(board.income))
                StatTile(title: "Uitgaven", value: Fmt.euro(board.expensesTotal))
                StatTile(title: "Verdeeld", value: Fmt.euro(distributed))
            }
            notes(d, board: board, current: current)
        }
    }

    /// Wat er bij het getal hoort: wat aan de bankrekening is toegewezen, uit spaarpotten betaald, afronding, een maand vóór de start,
    /// en waar de verdeling niet klopt.
    @ViewBuilder
    private func notes(_ d: FinanceData, board: MonthBoard, current: YearMonth) -> some View {
        // Waar de verdeling niet klopt (percentages samen boven 100%, of meer verdeeld dan er is, ook door een te groot bankdeel):
        // tekst van de rekenmotor.
        let warnings = d.allocationWarnings(in: month)
        // Het bankdeel dat in "Verdeeld" zit: alleen in een maand die "Nog te verdelen" heet (`MonthBoard.distributedShown`).
        let shownToBankCents = CentsMath.int(board.distributedShown(current: current)) - CentsMath.int(board.allocated)
        if let bankNote = BankShareText.summaryNote(toBankCents: shownToBankCents) {
            MonthExplanation(text: bankNote)
        }
        if board.hasPotExpenses {
            MonthExplanation(text: "Waarvan \(Fmt.euro(board.fromPots)) uit een spaarpot. Dat telt niet mee in dit bedrag.")
        }
        if board.roundingHidesLeftSum(current: current) {
            RoundingNote()
        }
        if month < d.startMonth {
            MonthExplanation(text: StartDateText.beforeStartNote(d, .distribute))
        }
        if let note = StartDateText.partialMonthNote(d, month: month) {
            MonthExplanation(text: note)
        }
        if board.spendingExceedsIncome {
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
                MonthExplanation(text: "Wat je hier invult geldt voor \(Fmt.month(month)). Kies Percentage om een deel van je inkomen te verdelen: het bedrag rekent mee als je inkomen verandert. Een ander percentage in één maand mag ook. Wil je het elke maand, kies dan Maak dit je standaard. Bij Percentage kun je \(ExtraAmountText.title) invullen: een vast bedrag bovenop het percentage. Met \(TransferPartsText.title) laat je een deel van de inleg op een eigen dag overgaan.")
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

// MARK: - Bankrekening

/// Wat je aan de bankrekening toewijst: dit deel van je inkomen blijft op je rekening en telt als verdeeld, zodat "Nog te verdelen" op
/// nul kan uitkomen. Er wordt niets overgeschreven: dezelfde invoer als een pot, maar zonder overschrijfdag en extra overschrijfdagen,
/// en zonder negatief bedrag. De kaart staat er ook zonder spaarpotten of beleggingen.
private struct DistributeBankCard: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        Card(title: BankShareText.title, symbol: BankShareText.symbol, domain: .money, subtitle: BankShareText.subtitle) {
            MonthAllocationRow(id: BankShare.id, name: BankShareText.title, symbol: BankShareText.symbol,
                               color: AppDomain.money.color, month: month,
                               caption: BankShareText.caption(toBankCents: d.monthFigures(month).toBank),
                               allowsNegativeAmount: false, movesMoney: false, spokenSubtitle: BankShareText.subtitle)
                .disabled(month < d.startMonth)
            MonthExplanation(text: BankShareText.explanation)
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
                    MonthExplanation(text: "Op de overschrijfdag gaat het bedrag automatisch van je bankrekening naar de spaarpot of belegging. Dat geldt ook voor maanden die nog komen. Tot die dag telt het bedrag niet mee in het saldo van de pot. Een deel van een inleg kan op een eigen dag overgaan: zie \(TransferPartsText.title) bij de pot.")
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
