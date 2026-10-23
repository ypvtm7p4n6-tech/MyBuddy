import SwiftUI

// De vijf kaarten van de Maand-tab die naar een pagina leiden: Inkomen, Uitgaven, Verdelen, Bankrekening en Dag voor dag. Elke kaart
// toont het kerncijfer van de gekozen maand (`router.focusMonth`, de `MonthBar`) uit dezelfde bron als de pagina erachter:
// `salaryAmount`/`extraIncomeTotal`, `expenseOverview`, `monthFigures`, `bankBalance` en de dagboekhouding (`LedgerBook`).

// MARK: - Inkomen

/// Het blok `income`: het inkomen van de maand met Salaris en Overige inkomsten. Een tik opent Inkomen.
struct MonthIncomeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        LinkCard(title: "Inkomen", symbol: "eurosign.circle", domain: .money, subtitle: Fmt.month(month),
                 destination: .income) {
            BigAmount(value: d.income(in: month), font: Theme.titleAmount, label: "Inkomen")
            details(d, month: month)
        }
    }

    @ViewBuilder
    private func details(_ d: FinanceData, month: YearMonth) -> some View {
        let salary = d.salaryAmount(in: month)
        let extra = d.extraIncomeTotal(in: month)
        if month < d.startMonth {
            TabNote(text: "Maanden vóór je startmaand (\(Fmt.month(d.startMonth))) tellen niet mee.")
        } else if salary == 0 && extra == 0 {
            TabNote(text: "Stel je salaris in als vast bedrag of met een uurloon.")
        } else {
            FigureRow {
                StatTile(title: "Salaris", value: Fmt.euro(salary))
                StatTile(title: "Overige inkomsten", value: Fmt.euro(extra))
            }
            // Een salaris om de zoveel weken of dagen komt niet elke maand even vaak binnen: zeg wanneer.
            if !d.salary.isMonthly {
                TabNote(text: "Salaris \(d.salaryScheduleSummary(asOf: store.today)).")
            }
        }
    }
}

// MARK: - Uitgaven

/// Het blok `expenses`: de uitgaven van de maand, verdeeld in Vast en Variabel. Een tik opent Uitgaven.
struct MonthExpensesCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let overview = d.expenseOverview(in: month)
        LinkCard(title: "Uitgaven", symbol: "creditcard", domain: .money, subtitle: Fmt.month(month),
                 destination: .expenses) {
            BigAmount(value: overview.expenses, font: Theme.titleAmount, label: "Uitgaven")
            details(d, month: month, overview: overview)
        }
    }

    @ViewBuilder
    private func details(_ d: FinanceData, month: YearMonth, overview: ExpenseOverview) -> some View {
        if month < d.startMonth {
            TabNote(text: "Maanden vóór je startmaand (\(Fmt.month(d.startMonth))) tellen niet mee.")
        } else if overview.expenses == 0 {
            TabNote(text: "Vul je vaste en variabele uitgaven in, dan zie je wat er overblijft.")
        } else {
            FigureRow {
                StatTile(title: "Vast", value: Fmt.euro(overview.fixed))
                StatTile(title: "Variabel", value: Fmt.euro(overview.variable))
            }
            // Uitgaven uit een spaarpot kosten het maandbudget niets: zonder uitleg tellen de bedragen niet op.
            if overview.fromPots > 0 {
                TabNote(text: "Waarvan \(Fmt.euro(overview.fromPots)) uit spaarpotten. Dat telt niet mee in \(MoneyLabels.remainingLabel(of: month, current: store.now)).")
            }
        }
    }
}

// MARK: - Verdelen

/// Het blok `distribute`: wat er van de maand nog te verdelen is (voor het verleden: overgehouden), met hoeveel er al is gespaard
/// en belegd. Dezelfde `MonthFigures` als op Verdelen. Een tik opent Verdelen.
struct MonthDistributeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let month = router.focusMonth
        let figures = store.data.monthFigures(month)
        let left = CentsMath.value(figures.remaining)
        let over = figures.remaining < 0
        let label = MoneyLabels.remainingLabel(of: month, current: store.now)
        // Onder nul door te hoge uitgaven (bijvoorbeeld nog geen salaris) is niet "te veel verdeeld".
        let overText = figures.available < 0 ? "Je uitgaven zijn hoger dan je inkomen" : "Je hebt te veel verdeeld"
        LinkCard(title: "Verdelen", symbol: "square.split.2x2", domain: .money, subtitle: over ? overText : label,
                 destination: .distribute) {
            BigAmount(value: left, font: Theme.titleAmount, color: over ? Theme.negative : Color.primary, label: label)
            ProgressMeter(value: progress(figures), tint: over ? Theme.negative : Theme.accent, style: .bar(height: 10),
                          label: "Verdeeld", valueText: progressText(figures))
            FigureRow {
                StatTile(title: "Gespaard", value: Fmt.euro(CentsMath.value(figures.saved)))
                StatTile(title: "Belegd", value: Fmt.euro(CentsMath.value(figures.invested)))
            }
        }
    }

    /// Het deel van wat er te verdelen was dat al is verdeeld. nil zolang er niets te verdelen is: dan tekent de balk niets.
    private func progress(_ figures: MonthFigures) -> Double? {
        guard figures.available > 0 else { return nil }
        let allocated = CentsMath.add(figures.saved, figures.invested)
        return Double(allocated) / Double(figures.available)
    }

    private func progressText(_ figures: MonthFigures) -> String {
        let allocated = CentsMath.add(figures.saved, figures.invested)
        return "\(Fmt.euro(CentsMath.value(allocated))) van \(Fmt.euro(CentsMath.value(figures.available)))"
    }
}

// MARK: - Bankrekening

/// Het blok `bank`: het saldo. Voor de huidige maand het saldo van vandaag (alleen als dat bekend is), voor een andere maand het
/// saldo aan het eind ervan. Een tik opent Bankrekening.
struct MonthBankCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let now = store.now
        let month = router.focusMonth
        let isNow = month == now
        let balance: Double? = isNow ? d.bankBalanceNowIfKnown(current: now, today: store.today) : d.bankBalance(at: month)
        let title: String = isNow ? "Saldo vandaag" : CashflowText.monthEndTitle(month, current: now)
        LinkCard(title: "Bankrekening", symbol: "building.columns", domain: .money, subtitle: balance == nil ? nil : title,
                 destination: .bank) {
            if let balance {
                BigAmount(value: balance, font: Theme.titleAmount, color: balance < 0 ? Theme.negative : Color.primary,
                          label: title)
            } else {
                TabNote(text: missingText(d, month: month, isNow: isNow))
            }
        }
    }

    /// Waarom er geen saldo staat en wat je kunt doen.
    private func missingText(_ d: FinanceData, month: YearMonth, isNow: Bool) -> String {
        if !isNow {
            return "Voor \(Fmt.month(month)) is je saldo nog niet bekend."
        }
        if d.hasBankBalance {
            return "Je saldo van vandaag is nog niet bekend. Vul je saldo van vandaag in."
        }
        return "Vul je saldo in of zet er geld op. De app houdt het bij en rekent ermee."
    }
}

// MARK: - Dag voor dag

/// Het blok `days`: het laagste saldo van de maand (voor de huidige maand vanaf vandaag, zoals de waarschuwing op Dag voor dag),
/// uit de dagboekhouding. Een tik opent Dag voor dag.
struct MonthDaysCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let now = store.now
        let month = router.focusMonth
        let low = lowestDay(d, month: month, now: now)
        let title = month == now ? "Laagste saldo vanaf vandaag" : "Laagste saldo van de maand"
        LinkCard(title: "Dag voor dag", symbol: "list.bullet.rectangle", domain: .money, subtitle: Fmt.month(month),
                 destination: .cashflow) {
            if let low, let balance = low.bankBalance {
                BigAmount(value: balance, font: Theme.titleAmount, color: balance < 0 ? Theme.negative : Color.primary,
                          label: title)
                TabNote(text: "\(title) · \(DayText.weekdayShort(low.date))")
            } else {
                TabNote(text: d.hasBankBalance ? "Voor deze maand is er nog geen saldo per dag bekend."
                                               : "Vul je saldo in, dan zie je per dag hoeveel je hebt.")
            }
        }
    }

    /// De dag met het laagste saldo, uit de dagboekhouding. nil zolang er nergens een saldo is.
    private func lowestDay(_ d: FinanceData, month: YearMonth, now: YearMonth) -> DayTotals? {
        guard d.hasBankBalance else { return nil }
        let today = store.today
        let book = LedgerBook(d, today: today)
        let window = BankLowPointWindow.range(for: month, current: now, today: today)
        return CashflowLowPoint.lowest(in: book.days(from: window.from, to: window.to))
    }
}
