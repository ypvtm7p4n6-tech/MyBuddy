import SwiftUI

// TIJDELIJK (tot golf 1c): wat in dit bestand staat, wordt nog aangeroepen door de oude tabroots (`HomeView`, `SavingsView`) of
// door pagina's van andere pakketten (`BankLegacy.swift`, `CashflowPages.swift`). In golf 1c verwijdert pakket B1 dit hele
// bestand zodra niemand de types hieronder nog aanroept (plan par. 6.6). De nieuwe pagina's van de Maand-tab staan in
// App/Pages/Month/: Inkomen, Salaris, Uitgaven en Verdelen.

// MARK: - Overzicht (alles bij elkaar)

/// De oude pagina Overzicht. Het Overzicht van nu is de kaart "Waar gaat je geld heen" op de Maand-tab; deze pagina is nog
/// bereikbaar via de oude tabroots en toont dezelfde cijfers uit dezelfde bronnen, met de nieuwe componenten.
struct OverviewPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let now = store.now
        let mode = router.periodMode
        let focus = router.focusMonth
        let period = d.periodSummary(mode, containing: focus, current: now)
        // Eén getal voor "Nog te verdelen", overal op deze pagina: voor een maand precies `remaining(in:)`, het getal van het Overzicht.
        let left = mode == .month ? d.remaining(in: focus) : period.remaining
        let label = MoneyLabels.remainingLabel(of: focus, current: now, isPeriod: mode != .month)
        ListScaffold(title: "Overzicht") {
            Section {
                PeriodControl()
            }
            leftSection(mode: mode, focus: focus, period: period, left: left, label: label)
            figuresSection(d, focus: focus, period: period, left: left, label: label)
            chartSection(d, mode: mode, focus: focus, now: now)
            worthSection(d, mode: mode, focus: focus, period: period, now: now)
            monthsSection(period)
            if mode == .month {
                OverviewDayCheck(month: focus)
            }
        }
    }

    @ViewBuilder
    private func leftSection(mode: PeriodMode, focus: YearMonth, period: PeriodSummary, left: Double, label: String) -> some View {
        Section {
            MonthFigureHero(title: "\(label) in \(Fmt.period(mode, containing: focus))", value: left,
                            color: left < 0 ? Theme.negative : Color.primary)
            MonthExplanation(text: "Je inkomen min je uitgaven van de rekening, min wat je verdeelde over spaarpotten en beleggingen.")
            if period.fromPots > 0 {
                MonthExplanation(text: "Waarvan \(Fmt.euro(period.fromPots)) uit spaarpotten betaald. Dat telt niet mee in dit bedrag.")
            }
        } header: {
            SectionHeader(label, symbol: "calendar", domain: .money)
        }
    }

    @ViewBuilder
    private func figuresSection(_ d: FinanceData, focus: YearMonth, period: PeriodSummary, left: Double, label: String) -> some View {
        Section {
            AmountRow(title: "Inkomen", value: Fmt.euro(period.income))
            AmountRow(title: "Uitgaven", value: Fmt.euro(period.expenses))
            AmountRow(title: "Gespaard", value: Fmt.euro(period.saved))
            AmountRow(title: "Belegd", value: Fmt.euro(period.invested))
            AmountRow(title: label, value: Fmt.euro(left), color: left < 0 ? Theme.negative : Color.primary)
            AmountRow(title: "Gemiddeld overgehouden per maand", value: Fmt.euro(period.average(left)))
            if period.hasProjected {
                MonthExplanation(text: "Maanden na deze maand zijn verwacht: ze volgen je salarisschema, terugkerende regels en standaardinleg.")
            }
            if MonthBoard(month: focus, figures: period.figures).roundingHidesSum {
                RoundingNote()
            }
        } header: {
            SectionHeader("Cijfers", symbol: "sum", domain: .money)
        }
    }

    @ViewBuilder
    private func chartSection(_ d: FinanceData, mode: PeriodMode, focus: YearMonth, now: YearMonth) -> some View {
        let months = chartMonths(mode: mode, focus: focus)
        let summaries = d.summaries(from: months.first ?? focus, count: months.count, current: now)
        Section {
            StackedBarChart(model: StackedBarModel.months(summaries, startMonth: d.startMonth), size: .regular)
        } header: {
            SectionHeader("Per maand", symbol: "chart.bar.xaxis", domain: .money)
        }
    }

    @ViewBuilder
    private func worthSection(_ d: FinanceData, mode: PeriodMode, focus: YearMonth, period: PeriodSummary, now: YearMonth) -> some View {
        let months = chartMonths(mode: mode, focus: focus)
        let endMonth = period.months.last?.month ?? focus
        let endWorth = d.netWorth(at: endMonth, current: now)
        Section {
            MonthFigureHero(title: "Vermogen eind \(Fmt.period(mode, containing: focus))", value: endWorth.total)
            TrendChart(model: NetWorthTrend.model(d, months: months, current: now, today: store.today), size: .regular)
            NavigationRow(title: "Bankrekening", symbol: "building.columns", domain: .money,
                          value: Fmt.euro(endWorth.bank), destination: .bank)
            NavigationRow(title: "Spaarpotten", symbol: "tray.full", domain: .saving,
                          value: Fmt.euro(endWorth.pots), destination: .pots)
            NavigationRow(title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis", domain: .investing,
                          value: Fmt.euro(endWorth.investments), destination: .portfolio)
            // Zonder bekend saldo aan het eind van de periode telt de bank als € 0 mee in het vermogen.
            if d.bankBalance(at: endMonth) == nil {
                MonthExplanation(text: "Voor deze periode is je banksaldo nog niet bekend. Vul je saldo in voor een compleet vermogen.")
            }
        } header: {
            SectionHeader("Vermogen", symbol: "building.columns", domain: .overview)
        }
    }

    @ViewBuilder
    private func monthsSection(_ period: PeriodSummary) -> some View {
        Section {
            ForEach(period.months) { summary in
                AmountRow(title: Fmt.month(summary.month), value: Fmt.euro(summary.remaining),
                          detail: monthDetail(summary), color: summary.remaining < 0 ? Theme.negative : Color.primary)
            }
        } header: {
            SectionHeader("Maand voor maand", symbol: "list.bullet", domain: .money)
        }
    }

    private func monthDetail(_ summary: MonthSummary) -> String {
        let flows = "\(Fmt.euro(summary.income)) in · \(Fmt.euro(summary.expenses)) uit"
        return summary.isProjected ? flows + " · verwacht" : flows
    }
}

/// Meldt of de cijfers van een maand (inkomen, uitgaven, gespaard, belegd, nog te verdelen) sluiten met de dagen van die maand,
/// en leidt naar Dag voor dag. Het oordeel komt van de rekenmotor (`MonthLedger.allReconciles`): daar worden dezelfde
/// bedragen op twee onafhankelijke manieren uitgerekend en met elkaar vergeleken.
private struct OverviewDayCheck: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    var body: some View {
        let ledger = store.data.monthLedger(month, asOf: store.today)
        let title: String = ledger.allReconciles ? "Klopt met Dag voor dag" : "Dit klopt niet met Dag voor dag"
        let symbol: String = ledger.allReconciles ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        Section {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ledger.allReconciles ? Theme.positive : Theme.negative)
            NavigationRow(title: "Dag voor dag", symbol: "list.bullet.rectangle", domain: .money, destination: .cashflow)
        }
    }
}

// MARK: - Maand kiezen

/// De oude maandkiezer. Nieuwe code gebruikt `MonthBar`.
struct MonthPickerBlock: View {
    var body: some View {
        MonthBar()
    }
}

// MARK: - Regels: inkomsten en uitgaven (oude kaart)

/// Kaart met regels (extra inkomsten of uitgaven) voor één maand, met toevoegen, bewerken en verwijderen. Bij uitgaven kun je
/// kiezen of je alleen vaste of alleen variabele posten toont. De pagina's Inkomen en Uitgaven gebruiken `MoneyLinesSection`;
/// deze kaart blijft voor de oude Bankrekening tot die is herbouwd.
struct MoneyLinesBlock: View {
    let kind: FinanceData.LineKind
    var expenseKind: ExpenseKind? = nil
    let month: YearMonth

    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var editing: MoneyLine?

    var body: some View {
        let d = store.data
        let plan = d.plan(for: month)
        // Maanden vóór de startmaand tellen nergens mee: regels erin zouden een bedrag tonen dat op geen enkel ander scherm
        // terugkomt. Daarom laat dit blok daar niets zien en niets toevoegen.
        let beforeStart = month < d.startMonth
        let all: [MoneyLine] = beforeStart ? [] : (kind == .income ? plan.extraIncome : plan.expenses)
        let lines = all.filter { expenseKind == nil || kind == .income || $0.kind == expenseKind }
        let fromPots = kind == .expense
            ? CentsMath.value(CentsMath.sum(lines.map { CentsMath.int(d.fromPots(of: $0)) }))
            : 0
        Card(title: MoneyLinesText.title(kind: kind, expenseKind: expenseKind),
             symbol: MoneyLinesText.symbol(kind: kind, expenseKind: expenseKind), domain: .money,
             subtitle: subtitle(total: lines.total, fromPots: fromPots)) {
            if beforeStart {
                MonthExplanation(text: "Maanden vóór je startmaand (\(Fmt.month(d.startMonth))) tellen niet mee: daar vul je niets in.")
            } else if lines.isEmpty {
                MonthExplanation(text: MoneyLinesText.emptyTitle(kind: kind, expenseKind: expenseKind) + ". "
                                 + MoneyLinesText.emptyText(kind: kind, expenseKind: expenseKind))
            }
            VStack(spacing: 0) {
                ForEach(lines) { line in
                    VStack(spacing: 0) {
                        MoneyLineRow(line: line, kind: kind, month: month, showsMenu: true, onEdit: { editing = line })
                            .padding(.vertical, 4)
                        if line.id != lines.last?.id {
                            Divider()
                        }
                    }
                }
            }
            if !beforeStart {
                ActionButton(title: "Toevoegen", symbol: "plus") { showAdd = true }
            }
            if lines.contains(where: { $0.isRecurring }) {
                MonthExplanation(text: MoneyLinesText.recurringHint(month: month, current: store.now))
            }
        }
        .sheet(isPresented: $showAdd) {
            MoneyLineSheet(line: nil, kind: kind, month: month, defaultExpenseKind: expenseKind ?? .fixed)
        }
        .sheet(item: $editing) { line in
            MoneyLineSheet(line: line, kind: kind, month: month, defaultExpenseKind: line.kind)
        }
    }

    private func subtitle(total: Double, fromPots: Double) -> String {
        if fromPots > 0 { return "Totaal \(Fmt.euro(total)) · \(Fmt.euro(fromPots)) uit spaarpotten" }
        return "Totaal \(Fmt.euro(total))"
    }
}
