import SwiftUI

// Het onderdeel Saldo van Bankrekening: het saldo van vandaag (met "Saldo invullen"), de waarschuwing bij een laag saldo, het
// verwachte verloop, binnen en eruit van een maand en het minimumsaldo. Elk stuk is een sectie van de lijst. De bedragen komen uit
// de rekenmotor: `bankBalanceNowIfKnown`, `bankBalance(at:)`, `BankTrend`, `BankFlowFigures` (= `expenseOverview`) en `bankBuffer`.

struct BankBalanceSections: View {
    @Binding var sheet: BankSheet?
    /// Wisselt naar het onderdeel Dag voor dag.
    let showDays: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        BankHeroSection(sheet: $sheet)
        BankLowPointSection(month: store.now)
        BankForecastSection(sheet: $sheet)
        BankFlowSections(showDays: showDays)
        BankMinimumSection()
    }
}

// MARK: - Saldo vandaag

/// Het saldo van de bankrekening van nu. Dit is hetzelfde getal als het saldo aan het eind van vandaag in de sectie van vandaag
/// op Dag voor dag (`DayTotals.bankBalance`): alles gebeurt per kalenderdag, dus wat vandaag op je plan staat telt al mee.
/// Het eindsaldo van de maand is `bankBalance(at:)` (`MonthLedger.closingBank`).
struct BankHeroSection: View {
    @Binding var sheet: BankSheet?
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        // Alleen een saldo tonen als het van nu bekend is: een saldo dat pas later begint zegt niets over vandaag.
        let balanceNow = d.bankBalanceNowIfKnown(current: now, today: today)
        Section {
            if let balanceNow {
                knownRows(d, balance: balanceNow, now: now, today: today)
            } else {
                unknownRows(d)
            }
        } header: {
            SectionHeader("Saldo vandaag", symbol: "building.columns", domain: .money)
        }
    }

    @ViewBuilder
    private func knownRows(_ d: FinanceData, balance: Double, now: YearMonth, today: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BigAmount(value: balance, color: balance < 0 ? Theme.negative : Color.primary, label: "Saldo vandaag")
            Text(DayText.weekdayShort(today))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        if let monthEnd = d.bankBalance(at: now) {
            AmountRow(title: CashflowText.monthEndTitle(now, current: now), value: Fmt.euro(monthEnd),
                      detail: "Met alles wat nog komt",
                      color: monthEnd < 0 ? Theme.negative : Color.primary)
        }
        Text(explanation(d))
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        ActionButton(title: BankAction.balance.title, symbol: BankAction.balance.symbol) {
            sheet = .move(.balance)
        }
    }

    @ViewBuilder
    private func unknownRows(_ d: FinanceData) -> some View {
        if d.hasBankBalance {
            EmptyHint(symbol: "calendar.badge.clock", title: "Je saldo van vandaag is nog niet bekend",
                      message: "Wat je invulde begint pas op een latere dag. Vul je saldo van vandaag in.",
                      actionTitle: BankAction.balance.title, action: { sheet = .move(.balance) })
        } else {
            EmptyHint(symbol: "building.columns", title: "Begin met je saldo",
                      message: "Je koppelt geen bank. Vul je saldo in of zet er geld op; de app houdt het bij en rekent ermee verder.",
                      actionTitle: BankAction.balance.title, action: { sheet = .move(.balance) })
        }
    }

    /// Hoe het saldo tot stand komt, met de regel voor een ingevuld saldo.
    private func explanation(_ d: FinanceData) -> String {
        if let last = d.sortedBankSnapshots.last {
            return "Laatst ingevuld: \(Fmt.euro(last.balance)) op \(Fmt.date(last.date)); boekingen van die dag zitten er al in. Daarna tellen je stortingen, opnames en je plan per dag mee: wat vandaag op je plan staat, is al meegerekend."
        }
        return "Het saldo volgt je stortingen, opnames en je plan per dag: wat vandaag op je plan staat, is al meegerekend."
    }
}

// MARK: - Waarschuwing bij een laag saldo

/// De waarschuwing "onder nul" of "onder je minimumsaldo", als een eigen sectie. Er is alleen een sectie als er een melding is
/// (een lege sectie zou een lege rij geven). Zonder `book` bouwt de sectie zijn eigen dagboek.
struct BankLowPointSection: View {
    let month: YearMonth
    var book: LedgerBook? = nil
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let today = store.today
        let ledgerBook = book ?? LedgerBook(d, today: today)
        if let note = BankLowPointNote.forMonth(month, in: d, current: store.now, today: today, book: ledgerBook) {
            Section {
                BankLowPointNotice(note: note)
                    .bankBareRow()
            }
        }
    }
}

// MARK: - Verwacht verloop

struct BankForecastSection: View {
    @Binding var sheet: BankSheet?
    @Environment(AppStore.self) private var store

    var body: some View {
        let model = BankTrend.model(store.data, current: store.now, today: store.today)
        Section {
            TrendChart(model: model, size: .regular, onAction: handleChartAction)
            if model.empty == nil {
                Text("Gebaseerd op je saldo, inkomen, uitgaven en verdeling per maand. Het eindsaldo van een maand is hetzelfde getal als bij Dag voor dag.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            SectionHeader("Verwacht verloop", symbol: "chart.line.uptrend.xyaxis", domain: .money)
        }
    }

    /// De knop in de lege staat van de grafiek: "Saldo invullen".
    private func handleChartAction(_ action: ChartEmpty.Action) {
        if case .enterBankBalance = action {
            sheet = .move(.balance)
        }
    }
}

// MARK: - Binnen en eruit

/// Een regel van "Binnen en eruit": een stip in de kleur van het stuk in de balk, de titel, het bedrag en (met `action`) een
/// pijltje naar de pagina waar het bedrag vandaan komt. De stip staat nooit alleen: titel en bedrag staan er altijd bij.
struct BankFlowLine: View {
    let title: String
    let value: String
    var detail: String? = nil
    var color: Color = .primary
    var dot: Color? = nil
    var bold = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                content(showsChevron: true)
            }
            .buttonStyle(BankRowButtonStyle())
            .accessibilityAddTraits(.isLink)
        } else {
            content(showsChevron: false)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            marker
            AmountRow(title: title, value: value, detail: detail, color: color, bold: bold)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var marker: some View {
        if let dot {
            Circle()
                .fill(dot)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
    }
}

/// De maandkiezer en de sectie "Binnen en eruit" voor die maand.
struct BankFlowSections: View {
    let showDays: () -> Void
    @Environment(Router.self) private var router

    var body: some View {
        Section {
            MonthBar()
                .bankBareRow()
        }
        BankFlowSection(month: router.focusMonth, showDays: showDays)
    }
}

/// Wat er in een maand binnenkomt, uitgaat en overblijft: een balk met de stukken, daaronder een regel per stuk met een link naar
/// Inkomen, Uitgaven, Spaarpotten, Beleggingen en Verdelen. De balk toont wat van de bank gaat, zodat alle stukken samen het
/// inkomen vormen.
struct BankFlowSection: View {
    let month: YearMonth
    let showDays: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let figures = BankFlowFigures(d, month: month)
        let leftover = CashflowText.leftoverTitle(month: month, current: store.now)
        Section {
            if figures.isEmpty {
                EmptyHint(symbol: "arrow.left.arrow.right", title: "Nog niets in \(Fmt.month(month))",
                          message: "Stel je salaris en je uitgaven in. Dan zie je hier wat er binnenkomt en uitgaat.",
                          actionTitle: "Salaris instellen", action: { router.open(.salary) })
            } else {
                meter(figures, leftover: leftover)
                flowRows(figures, leftover: leftover)
                flowNotes(d, figures: figures)
            }
        } header: {
            SectionHeader("Binnen en eruit", symbol: "arrow.left.arrow.right", domain: .money)
        }
    }

    private func meter(_ f: BankFlowFigures, leftover: String) -> some View {
        let spoken = "Vaste uitgaven \(ChartText.euro(f.fixedFromBank)), variabele uitgaven \(ChartText.euro(f.variableFromBank)), "
            + "inleg in spaarpotten \(ChartText.euro(f.toPots)), inleg in beleggingen \(ChartText.euro(f.toInvestments)), "
            + "\(leftover.lowercased()) \(ChartText.euro(f.leftAfterTransfers))"
        return SegmentedMeter(
            segments: [
                SegmentedMeter.Segment(id: "fixed", title: "Vaste uitgaven", value: f.fixedFromBank, color: Theme.chartExpenses),
                SegmentedMeter.Segment(id: "variable", title: "Variabele uitgaven", value: f.variableFromBank, color: Theme.chartVariable),
                SegmentedMeter.Segment(id: "pots", title: "Inleg in spaarpotten", value: f.toPots, color: Theme.chartSaved),
                SegmentedMeter.Segment(id: "invest", title: "Inleg in beleggingen", value: f.toInvestments, color: Theme.chartInvested),
                SegmentedMeter.Segment(id: "free", title: leftover, value: max(0, f.leftAfterTransfers), color: Theme.chartFree)
            ],
            label: "Binnen en eruit in \(Fmt.month(month))",
            valueText: spoken)
    }

    @ViewBuilder
    private func flowRows(_ f: BankFlowFigures, leftover: String) -> some View {
        BankFlowLine(title: "Inkomen", value: CashflowText.signed(f.income), color: Theme.positive,
                     action: { router.open(.income) })
        BankFlowLine(title: "Vaste uitgaven", value: CashflowText.signed(-f.fixed), dot: Theme.chartExpenses,
                     action: { router.open(.expenses) })
        BankFlowLine(title: "Variabele uitgaven", value: CashflowText.signed(-f.variable), dot: Theme.chartVariable,
                     action: { router.open(.expenses) })
        if f.fromPots > 0 {
            BankFlowLine(title: "Betaald uit spaarpotten", value: CashflowText.signed(f.fromPots),
                         action: { router.open(.pots) })
        }
        BankFlowLine(title: "Na uitgaven", value: Fmt.euro(f.leftAfterExpenses),
                     color: f.leftAfterExpenses < 0 ? Theme.negative : Color.primary, bold: true)
        BankFlowLine(title: "Inleg in spaarpotten", value: CashflowText.signed(-f.toPots), dot: Theme.chartSaved,
                     action: { router.open(.pots) })
        BankFlowLine(title: "Inleg in beleggingen", value: CashflowText.signed(-f.toInvestments), dot: Theme.chartInvested,
                     action: { router.open(.portfolio) })
        BankFlowLine(title: leftover, value: Fmt.euro(f.leftAfterTransfers),
                     color: f.leftAfterTransfers < 0 ? Theme.negative : Theme.positive, dot: Theme.chartFree, bold: true,
                     action: { router.open(.distribute) })
    }

    @ViewBuilder
    private func flowNotes(_ d: FinanceData, figures: BankFlowFigures) -> some View {
        if let note = payoutNote(d) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        if figures.leftAfterTransfers < 0 {
            Label("Je geeft meer uit en verdeelt meer dan je inkomen. Pas je uitgaven of je verdeling aan.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.negative)
        }
        // Voor deze maand staat het verwachte eindsaldo al bij Saldo vandaag; voor een andere maand staat het hier.
        if month != store.now, let closing = d.bankBalance(at: month) {
            BankFlowLine(title: CashflowText.monthEndTitle(month, current: store.now), value: Fmt.euro(closing),
                         detail: "Met je eigen stortingen, opnames en ingevulde saldo. Per dag zie je het bij Dag voor dag.",
                         color: closing < 0 ? Theme.negative : Color.primary, bold: true, action: showDays)
        }
    }

    /// Komt het salaris vaker dan één keer in de maand binnen, dan staat hier wanneer.
    private func payoutNote(_ d: FinanceData) -> String? {
        let payouts = d.salaryPayouts(in: month, plan: d.plan(for: month)).filter { $0.cents != 0 }
        guard payouts.count > 1 else { return nil }
        return "Je salaris komt in \(Fmt.month(month)) \(payouts.count) keer binnen: \(d.salaryPayoutDaysText(in: month))."
    }
}

// MARK: - Minimumsaldo

/// Het minimum dat je op je rekening wilt houden, in maanden aan uitgaven (`settings.bankBufferMonths`). Dit is de enige plek
/// waar het staat. Het is iets anders dan de noodbuffer: die rekenen je uit bij Noodbuffer.
struct BankMinimumSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        Section {
            // Alleen als het saldo van nu bekend is: zonder saldo zegt "Daarboven" niets.
            if d.hasBankBalanceNow(current: now, today: today) {
                FigureRow {
                    StatTile(title: "Minimumsaldo", value: Fmt.euro(d.bankBuffer(current: now)))
                    StatTile(title: "Daarboven", value: Fmt.euro(d.bankSurplusAboveBuffer(current: now, today: today)),
                             color: Theme.positive)
                }
            }
            NumberRow(title: "Minimumsaldo in maanden aan uitgaven",
                      value: Binding(get: { store.data.settings.bankBufferMonths },
                                     set: { newValue in store.mutate { $0.settings.bankBufferMonths = newValue } }),
                      unit: .plain("mnd"), maxDigits: 1)
            Text("Dit is iets anders dan je noodbuffer: het minimumsaldo is wat er minstens op je betaalrekening hoort te staan. Hoeveel noodbuffer je nodig hebt, reken je uit bij Noodbuffer.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            NavigationRow(title: "Noodbuffer", symbol: "shield.lefthalf.filled", domain: .goals, destination: .buffer)
        } header: {
            SectionHeader("Minimumsaldo", symbol: "shield.lefthalf.filled", domain: .money)
        }
    }
}
