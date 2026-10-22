import SwiftUI

// Het onderdeel Dag voor dag van Bankrekening (docs/design/plan.md par. 2.4 en K15): de maand dag voor dag. Bovenaan de maandkiezer,
// de waarschuwing bij een laag saldo en (alleen bij een afwijking) de melding dat de cijfers niet sluiten; dan de grafiek Saldo per
// dag, de twee sluitende uitklappers en een sectie per dag. Alle bedragen komen uit de dagboekhouding (`LedgerBook`, dezelfde
// `DayTotals` als overal); hier wordt niets zelf uitgerekend.

struct BankDaysSections: View {
    @Binding var sheet: BankSheet?
    let proxy: ScrollViewProxy
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        // Eén dagboek voor het hele onderdeel: alle cijfers hieronder komen uit dezelfde maanden.
        let book = LedgerBook(d, today: store.today)
        let ledger = book.ledger(month)
        let check = LedgerCheck(ledger)
        Section {
            MonthBar()
                .bankBareRow()
        }
        BankLowPointSection(month: month, book: book)
        if !check.isOK {
            Section {
                CashflowCheckBanner(check: check)
                    .bankBareRow()
            }
        }
        BankDayChartSection(book: book, month: month, sheet: $sheet)
        CashflowBankBlock(ledger: ledger, hasBalance: ledger.openingBank != nil || ledger.closingBank != nil)
        if !d.pots.isEmpty {
            CashflowPotsBlock(ledger: ledger)
        }
        BankDayListSections(ledger: ledger, month: month, sheet: $sheet, proxy: proxy)
    }
}

// MARK: - Saldo per dag

/// De keuze van het venster van de grafiek, voor één maand. Wisselt de maand, dan geldt de keuze niet meer.
private struct DayRangeChoice {
    let month: YearMonth
    let range: DayChartRange
}

/// De grafiek Saldo per dag: de komende 30 dagen (standaard voor de huidige maand) of de hele maand. Een dag is een stip met
/// tekst, pas vanaf twee dagen een lijn; zonder saldo staat er een lege staat met "Saldo invullen" (`DayBalanceTrend`).
struct BankDayChartSection: View {
    let book: LedgerBook
    let month: YearMonth
    @Binding var sheet: BankSheet?
    @Environment(AppStore.self) private var store
    @State private var choice: DayRangeChoice?

    var body: some View {
        let today = store.today
        let defaultRange: DayChartRange = month == store.now ? .next30 : .month
        let range = effectiveRange(default: defaultRange)
        let span = range.window(focus: month, today: today)
        let items = DayChartItem.items(from: book.days(from: span.from, to: span.to))
        let model = DayBalanceTrend.model(items: items, range: range, focus: month, today: today)
        Section {
            Picker("Periode van de grafiek", selection: rangeBinding(default: defaultRange)) {
                Text("Komende 30 dagen").tag(DayChartRange.next30)
                Text(Fmt.month(month)).tag(DayChartRange.month)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TrendChart(model: model, size: .regular, onAction: handleChartAction)
        } header: {
            SectionHeader("Saldo per dag", symbol: "chart.xyaxis.line", domain: .money)
        }
    }

    private func effectiveRange(default defaultRange: DayChartRange) -> DayChartRange {
        if let choice, choice.month == month { return choice.range }
        return defaultRange
    }

    private func rangeBinding(default defaultRange: DayChartRange) -> Binding<DayChartRange> {
        Binding<DayChartRange>(get: { effectiveRange(default: defaultRange) },
                               set: { newRange in choice = DayRangeChoice(month: month, range: newRange) })
    }

    /// De knop in de lege staat van de grafiek: "Saldo invullen".
    private func handleChartAction(_ action: ChartEmpty.Action) {
        if case .enterBankBalance = action {
            sheet = .move(.balance)
        }
    }
}

// MARK: - Een sectie per dag

/// De bediening van de lijst (welke dagen, naar vandaag) en daaronder een sectie per dag. Standaard staan alleen de dagen met
/// boekingen (en vandaag) in de lijst; "Alle dagen" toont elke dag van de maand.
struct BankDayListSections: View {
    let ledger: MonthLedger
    let month: YearMonth
    @Binding var sheet: BankSheet?
    let proxy: ScrollViewProxy
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: CashflowDayFilter = .withEntries

    var body: some View {
        let d = store.data
        let days = filter.days(of: ledger)
        let lookup = CashflowLineLookup(plan: d.plan(for: month))
        let multipleSalaries = ledger.salaryPayoutCount > 1
        controls(count: days.count)
        if days.isEmpty {
            emptySection
        } else {
            ForEach(days, id: \.day) { day in
                BankDaySection(day: day, lookup: lookup, month: month, multipleSalaries: multipleSalaries,
                               hasPots: !d.pots.isEmpty, sheet: $sheet)
            }
        }
    }

    /// De kop van de sectie van vandaag, als vandaag in deze maand valt. Dit is ook het id waar "Naar vandaag" naartoe scrolt.
    private var todayTitle: String? {
        guard let target = CashflowScroll.todayTarget(in: ledger),
              let day = ledger.days.first(where: { $0.day == target }) else { return nil }
        return DayText.weekdayShort(day.date)
    }

    private func controls(count: Int) -> some View {
        Section {
            Picker("Welke dagen", selection: $filter) {
                ForEach(CashflowDayFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let title = todayTitle {
                ActionButton(title: "Naar vandaag", symbol: "arrow.down.to.line") {
                    scrollToToday(title)
                }
            }
        } header: {
            SectionHeader("Dagen in \(Fmt.month(month))", symbol: "calendar", domain: .money)
        } footer: {
            Text("\(CashflowText.days(count)). Een dag met Gepland staat in je plan en is nog niet gebeurd.")
        }
    }

    private var emptySection: some View {
        Section {
            EmptyHint(symbol: "calendar", title: "Niets in \(Fmt.month(month))",
                      message: "Er komt niets binnen, er gaat niets weg en er wordt niets overgeschreven.",
                      actionTitle: "Alle dagen tonen", action: { filter = .all })
        }
    }

    private func scrollToToday(_ title: String) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            proxy.scrollTo(title, anchor: .top)
        }
    }
}

/// Eén dag: de kop (weekdag en datum, met "Vandaag" of "Gepland"), binnen, eruit en overgeschreven, de gebeurtenissen (of "Geen
/// boekingen op deze dag") en de saldi aan het eind van de dag. Een tik op een gebeurtenis opent de pot, de belegging, Inkomen of
/// het blad van de regel.
struct BankDaySection: View {
    let day: DayTotals
    let lookup: CashflowLineLookup
    let month: YearMonth
    let multipleSalaries: Bool
    let hasPots: Bool
    @Binding var sheet: BankSheet?
    @Environment(Router.self) private var router

    var body: some View {
        Section {
            DayFlowTiles(day: day)
            eventRows
            DayBalanceRows(day: day, showsPots: hasPots)
        } header: {
            BankDayHeader(day: day)
        }
    }

    @ViewBuilder
    private var eventRows: some View {
        if day.events.isEmpty {
            Text("Geen boekingen op deze dag.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        } else {
            ForEach(day.events) { event in
                eventRow(event)
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: DayEvent) -> some View {
        let showsDate = multipleSalaries && event.kind == .salary
        switch CashflowAction.make(for: event, lookup: lookup, month: month) {
        case .open(let destination):
            Button {
                router.open(destination)
            } label: {
                DayEventRow(event: event, showsDate: showsDate, showsChevron: true)
            }
            .buttonStyle(BankRowButtonStyle())
            .accessibilityAddTraits(.isLink)
        case .edit(let target):
            Button {
                sheet = .line(target)
            } label: {
                DayEventRow(event: event, showsDate: showsDate, showsChevron: true)
            }
            .buttonStyle(BankRowButtonStyle())
        case .none:
            DayEventRow(event: event, showsDate: showsDate)
        }
    }
}

/// De kop van een dagsectie: weekdag en datum (een kop voor VoiceOver, ook het doel van "Naar vandaag"), met rechts "Vandaag" of
/// "Gepland". Vandaag heeft ook een eigen symbool, zodat het niet aan kleur of tekst alleen hangt.
struct BankDayHeader: View {
    let day: DayTotals

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionHeader(DayText.weekdayShort(day.date), symbol: day.isToday ? "calendar.badge.clock" : nil,
                          domain: day.isToday ? .money : nil)
            Spacer(minLength: 8)
            if let status = CashflowText.status(of: day) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .textCase(nil)
    }
}
