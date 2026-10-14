import Foundation
// In de app zit alles in één module. In de testpakket (CoreTests) staat dit bestand als symlink tussen de tests en leest
// het de rekenmotor via `@testable import`.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Eén bron per grootheid
//
// Dit bestand bevat alleen Foundation: geen SwiftUI. Het is de plek waar een scherm de cijfers haalt die op meer dan één
// plek voorkomen, zodat Home, Savings, de spaarpot- en beleggingspagina's en de rest hetzelfde getal tonen. Er wordt hier
// niets zelf uitgerekend dat de rekenmotor al kan: de functies pakken een motorwaarde, zetten hem om voor weergave of
// leggen er twee naast elkaar. Waar bedragen worden opgeteld gebeurt dat in hele centen (`CentsMath`).
//
// Welke functie levert welke grootheid (de peilmomenten staan erbij):
//
//   Nog te verdelen / "Over"     maand   FinanceData.remaining(in:) = MonthFigures.remaining; een periode: PeriodSummary.remaining
//   Inkomen                      maand   income(in:) (de som van de salarisuitbetalingen plus extra inkomsten)
//   Uitgaven (totaal)            maand   expensesTotal(in:), met het deel uit potten apart: expensesFromPots(in:)
//   Uitgaven van de bank         maand   expensesFromBank(in:) = totaal min uit potten
//   Verdeeld                     maand   savedTotal(in:) + investedTotal(in:), in centen opgeteld: `MonthBoard.allocated`
//   Saldo bankrekening NU        nu      bankBalanceNowIfKnown(current:today:), nil als dat nog niet bekend is
//   Saldo bankrekening eind      maand   bankBalance(at:)
//   Spaarpot NU                  nu      potBalanceNow(_:current:today:); totaal van alle potten: totalSaved(current:today:)
//   Spaarpot eind maand          maand   potBalance(_:at:); totaal: totalSaved(asOf:) op de laatste dag
//   Spaarpot op een datum        dag     potBalance(_:asOf:) (het saldo aan het eind van die dag)
//   Vermogen eind maand          maand   netWorth(at:current:), label `MoneyLabels.netWorthEnd(of:)`
//   Beleggingen                  maand   portfolioValue / portfolioInvested / holdingStateNow (per maand, niet per dag)
//   Inleg van een pot/belegging  maand   allocation(_:in:) (het bedrag van die maand, ook bij een percentage)
//   Inleg voor SCHATTINGEN       gem.    estimatedAllocation(_:in:), monthlyInvestment(current:) en estimatedMonthlyIncome(in:):
//                                        bij een salaris om de zoveel weken of dagen een GEMIDDELDE maand (zie SalarySchedule.swift)
//
// "nu" rekent altijd per kalenderdag met `store.today`: wat vandaag valt telt de hele dag mee, wat later komt niet.

// MARK: - De cijfers van een maand

/// De cijfers van één maand zoals Home ze toont, in één keer uit `FinanceData.monthFigures(_:)`.
///
/// Inkomen − uitgaven van de bank − verdeeld = nog te verdelen. Dat klopt hier altijd op de cent: alle getallen komen uit
/// dezelfde `MonthFigures`. Een uitgave die uit een spaarpot komt, kost het maandbudget niets: ze staat wel in het totaal
/// van de uitgaven (`expensesTotal`) maar niet in de uitgaven van de bank (`expensesFromBank`) waarmee de som sluit.
struct MonthBoard: Equatable {
    let month: YearMonth
    let figures: MonthFigures

    init(_ data: FinanceData, month: YearMonth) {
        self.month = month
        self.figures = data.monthFigures(month)
    }

    init(month: YearMonth, figures: MonthFigures) {
        self.month = month
        self.figures = figures
    }

    var income: Double { CentsMath.value(figures.income) }
    /// Alle uitgaven van de maand, ook wat uit een spaarpot komt (zoals `expensesTotal(in:)`).
    var expensesTotal: Double { CentsMath.value(figures.expenses) }
    /// Het deel van de uitgaven dat uit spaarpotten komt.
    var fromPots: Double { CentsMath.value(figures.fromPots) }
    /// Wat van de bankrekening gaat: totaal min het deel uit potten (zoals `expensesFromBank(in:)`).
    var expensesFromBank: Double { CentsMath.value(figures.expenses - figures.fromPots) }
    var saved: Double { CentsMath.value(figures.saved) }
    var invested: Double { CentsMath.value(figures.invested) }
    /// Wat er over spaarpotten en beleggingen is verdeeld, in centen opgeteld.
    var allocated: Double { CentsMath.value(CentsMath.add(figures.saved, figures.invested)) }
    /// Wat er te verdelen was voordat er iets is verdeeld: inkomen min uitgaven van de bank.
    var available: Double { CentsMath.value(figures.available) }
    /// Wat er nog te verdelen is (zoals `remaining(in:)`). Negatief als je meer hebt verdeeld of uitgegeven dan je hebt.
    var remaining: Double { CentsMath.value(figures.remaining) }
    /// Hoeveel er meer wordt verdeeld dan er te verdelen is.
    var overAllocated: Double { CentsMath.value(figures.overAllocated) }

    var isNegative: Bool { figures.remaining < 0 }
    /// Zijn de uitgaven van de bank al hoger dan het inkomen? Dan komt een negatief restant niet door te veel verdelen.
    var spendingExceedsIncome: Bool { figures.available < 0 }
    var hasPotExpenses: Bool { figures.fromPots > 0 }

    /// Inkomen − uitgaven van de bank − verdeeld = nog te verdelen, exact in hele centen. Is altijd waar; de tests en de
    /// schermen kunnen het zo controleren.
    var closes: Bool {
        let afterExpenses = CentsMath.add(figures.income, -(figures.expenses - figures.fromPots))
        return CentsMath.add(afterExpenses, -CentsMath.add(figures.saved, figures.invested)) == figures.remaining
    }
}

extension AllocationWarning {
    /// De percentages van de verdeling zijn samen meer dan 100% van het inkomen (in plaats van meer verdeeld dan er is).
    var isPercentageWarning: Bool {
        if case .percentagesOver100 = self { return true }
        return false
    }
}

extension PeriodSummary {
    /// De cijfers van de hele periode als `MonthFigures`, in hele centen. Zo hebben een maand en een periode dezelfde
    /// rekenregels (`available`, `remaining`, `overAllocated`) en rekent geen scherm zelf met Doubles.
    var figures: MonthFigures {
        MonthFigures(income: CentsMath.int(income), expenses: CentsMath.int(expenses), fromPots: CentsMath.int(fromPots),
                     saved: CentsMath.int(saved), invested: CentsMath.int(invested))
    }
}

extension FinanceData {
    /// Salaris en overige inkomsten van de maanden samen (in hele centen opgeteld). Samen zijn ze het inkomen van de periode
    /// (`PeriodSummary.income`): de salarisuitbetalingen van elke maand plus de extra inkomsten.
    func incomeParts(in months: [YearMonth]) -> (salary: Double, extra: Double) {
        let salary = CentsMath.sum(months.map { CentsMath.int(salaryAmount(in: $0)) })
        let extra = CentsMath.sum(months.map { CentsMath.int(extraIncomeTotal(in: $0)) })
        return (CentsMath.value(salary), CentsMath.value(extra))
    }

    /// Vaste en variabele uitgaven van de maanden samen (in hele centen opgeteld). Het zijn totalen, dus ook wat uit
    /// spaarpotten komt: samen zijn ze `PeriodSummary.expenses`.
    func expenseKindTotals(in months: [YearMonth]) -> (fixed: Double, variable: Double) {
        let overviews = months.map { expenseOverview(in: $0) }
        let fixed = CentsMath.sum(overviews.map { CentsMath.int($0.fixed) })
        let variable = CentsMath.sum(overviews.map { CentsMath.int($0.variable) })
        return (CentsMath.value(fixed), CentsMath.value(variable))
    }
}

/// Labels die op meer dan één scherm hetzelfde moeten zijn.
enum MoneyLabels {
    /// "Vermogen eind oktober": bank, spaarpotten en beleggingen aan het eind van de maand, dus met wat er die maand nog
    /// binnenkomt, uitgaat en wordt overgeschreven (`netWorth(at:current:)`). Het getal staat zo op Home en op het Overzicht.
    static func netWorthEnd(of month: YearMonth) -> String {
        "Vermogen eind \(Fmt.monthNames[min(max(month.month, 1), 12) - 1])"
    }
}

// MARK: - Inleg van een pot of belegging

/// Hoe de inleg van een spaarpot of belegging in een maand is opgebouwd: de standaardregel, wat er in die maand geldt
/// (een vast bedrag of een percentage van het inkomen van die maand), het inkomen waarover het percentage rekent en wat
/// het in een gemiddelde maand is. Alle getallen komen uit de rekenmotor.
struct ContributionInfo: Equatable {
    var id: UUID
    var month: YearMonth
    /// De standaardinleg van de pot of belegging, los van een maand.
    var standard: AllocationRule
    /// Wat er in `month` geldt, met het bedrag dat daaruit volgt (hetzelfde als `allocation(_:in:)`).
    var effective: EffectiveAllocation
    /// Het inkomen van `month` waarover het percentage rekent, in euro's (alleen bij een percentage).
    var base: Double?
    /// Het bedrag in een GEMIDDELDE maand (alleen bij een percentage en een salaris om de zoveel weken of dagen, want dan
    /// is het bedrag van de ene maand niet dat van de andere).
    var averageAmount: Double?
    /// Waar de verdeling van `month` niet klopt (percentages samen boven 100%, of meer verdeeld dan er is).
    var warnings: [AllocationWarning]

    /// nil als het id geen spaarpot of belegging is.
    init?(_ data: FinanceData, id: UUID, month: YearMonth) {
        guard let standard = data.contributionRule(of: id) else { return nil }
        self.id = id
        self.month = month
        self.standard = standard
        let effective = data.effectiveAllocation(id, in: month)
        self.effective = effective
        if case .percent(let rule) = effective.rule {
            base = CentsMath.value(data.incomeBases(in: month).cents(for: rule.basis))
            averageAmount = data.salary.isMonthly ? nil : data.estimatedAmount(of: effective.rule, in: month)
        } else {
            base = nil
            averageAmount = nil
        }
        warnings = data.allocationWarnings(in: month)
    }

    /// Het bedrag van deze maand in euro's.
    var amount: Double { effective.amount }
    var isPercent: Bool { effective.rule.isPercent }
    /// De maand wijkt af van de standaardinleg (een eigen bedrag of percentage in de verdeling van die maand).
    var isOverride: Bool { effective.isOverride }
    /// "€ 300" of "10% van je salaris".
    var standardText: String { standard.summary }
    /// De regel van deze maand, zoals `standardText`.
    var ruleText: String { effective.rule.summary }

    /// De waarde van de standaardregel voor een tegel: "€ 300" of "10%".
    var standardValue: String {
        switch standard {
        case .amount(let value): return Fmt.euro(value)
        case .percent(let rule): return Fmt.percent(rule.percent / 100, digits: 2)
        }
    }

    /// Wat er onder `standardValue` staat: "Vast bedrag per maand", "Van je salaris" of "Van al je inkomsten".
    var standardCaption: String {
        switch standard {
        case .amount: return "Vast bedrag per maand"
        case .percent(let rule): return rule.basis == .salary ? "Van je salaris" : "Van al je inkomsten"
        }
    }

    /// Wat er onder het bedrag van deze maand staat: waar het percentage over rekent, of dat de maand afwijkt.
    var amountCaption: String? {
        if let text = baseText { return text }
        return isOverride ? "Afwijkend van je standaard" : nil
    }

    /// "10% van € 3.000 salaris in oktober". nil bij een vast bedrag.
    var baseText: String? {
        guard case .percent(let rule) = effective.rule, let base else { return nil }
        let what = rule.basis == .salary ? "salaris" : "inkomsten"
        return "\(Fmt.percent(rule.percent / 100, digits: 2)) van \(Fmt.euro(base)) \(what) in \(Fmt.monthNames[min(max(month.month, 1), 12) - 1])"
    }

    /// Het inkomen waarover een percentage rekent is er niet (bijvoorbeeld geen salaris in die maand): het percentage is dan € 0.
    var hasNoBase: Bool { isPercent && (base ?? 0) <= 0 }
}

/// De uitkomst van een percentage voor in een invulformulier: "= € 300 in oktober", vóór het bewaren. Rekent met de
/// rekenmotor (`percentAmount`), precies zoals de verdeling het straks doet.
enum ContributionPreview {
    struct Result: Equatable {
        /// Wat het percentage in `month` oplevert.
        var amount: Double
        /// "10% van € 3.000 salaris in oktober".
        var note: String
        /// Uitleg onder het veld (er is geen inkomen, of het salaris komt niet elke maand even vaak binnen). nil = geen.
        var footnote: String?
    }

    static func resolve(_ data: FinanceData, percent: Double, basis: IncomeBasis, month: YearMonth) -> Result {
        let clean = AllocationMath.cleanPercent(percent)
        let amount = data.percentAmount(clean, of: basis, in: month)
        let baseCents = data.incomeBases(in: month).cents(for: basis)
        let base = CentsMath.value(baseCents)
        let what = basis == .salary ? "salaris" : "inkomsten"
        let monthName = Fmt.monthNames[min(max(month.month, 1), 12) - 1]
        let note = "\(Fmt.percent(clean / 100, digits: 2)) van \(Fmt.euro(base)) \(what) in \(monthName)"

        var parts: [String] = []
        if baseCents <= 0 {
            let missing = basis == .salary ? "salaris" : "inkomen"
            parts.append("Er is in \(Fmt.month(month)) geen \(missing): het percentage geeft nu € 0.")
        }
        if !data.salary.isMonthly {
            // Bij een salaris om de zoveel weken of dagen schommelt het inkomen per maand. Toekomstschattingen rekenen met
            // een gemiddelde maand (`estimatedAmount`); zeg dat erbij.
            let average = data.estimatedAmount(of: .percent(PercentRule(percent: clean, basis: basis)), in: month)
            parts.append("Je salaris komt niet elke maand even vaak binnen. In een gemiddelde maand is het \(Fmt.euro(average)).")
        }
        return Result(amount: amount, note: note, footnote: parts.isEmpty ? nil : parts.joined(separator: " "))
    }
}

// MARK: - Komende boekingen van een spaarpot

/// Eén geplande boeking van een spaarpot in de komende dagen.
struct PotUpcomingItem: Identifiable, Equatable {
    /// Het id van de gebeurtenis in de dagboekhouding (`DayEvent.id`).
    var id: String
    /// De dag van de boeking, om 12:00.
    var date: Date
    var kind: DayEventKind
    /// "Inleg", "Rente" of de naam van de uitgave.
    var title: String
    /// Extra regel onder de titel, bijvoorbeeld "10% van je salaris" bij een inleg als percentage. nil = geen.
    var detail: String?
    /// Wat de boeking met deze pot doet: positief erbij, negatief eraf.
    var amount: Double
    /// Het saldo van de pot nadat deze boeking is verwerkt, te beginnen bij het saldo van nu.
    var balanceAfter: Double
    /// Over hoeveel dagen (1 = morgen).
    var daysAhead: Int
}

/// De boekingen die een spaarpot de komende dagen krijgt: de inleg, uitgaven die uit deze pot worden betaald en rente.
/// Ze komen uit dezelfde gebeurtenissen als het dagoverzicht (`dayEvents`), alleen die van deze pot, en het saldo erna loopt
/// door vanaf het saldo van nu (`potBalanceNow`). Op de laatste boeking van een dag is dat precies het saldo aan het eind
/// van die dag (`potBalance(_:asOf:)`).
enum PotUpcoming {
    /// Zoveel dagen vooruit kijkt de lijst op de pagina van een spaarpot.
    static let horizonDays = 30

    /// De boekingen op de dagen na vandaag t/m `days` dagen vooruit, op volgorde. Per kalenderdag: wat vandaag valt telt al
    /// mee in het saldo van nu en staat dus niet in de lijst.
    static func items(_ data: FinanceData, potID: UUID, current: YearMonth, today: Date,
                      days: Int = horizonDays) -> [PotUpcomingItem] {
        guard let pot = data.pot(potID), days > 0 else { return [] }
        let cal = YearMonth.calendar
        let todayStart = cal.startOfDay(for: today)
        guard let firstDay = cal.date(byAdding: .day, value: 1, to: todayStart),
              let lastDay = cal.date(byAdding: .day, value: days, to: todayStart),
              let limit = cal.date(byAdding: .day, value: days + 1, to: todayStart) else { return [] }

        var running = CentsMath.int(data.potBalanceNow(potID, current: current, today: today))
        var result: [PotUpcomingItem] = []
        var month = YearMonth(date: firstDay, calendar: cal)
        let lastMonth = YearMonth(date: lastDay, calendar: cal)
        var count = 0
        while month <= lastMonth && count < 400 {
            for event in data.dayEvents(in: month, asOf: today)
            where event.potID == potID && event.isPlanned && event.date >= firstDay && event.date < limit {
                guard event.kind == .toPot || event.kind == .expense || event.kind == .interest else { continue }
                let cents = CentsMath.int(event.potAmount)
                guard cents != 0 else { continue }
                running = CentsMath.add(running, cents)
                let ahead = cal.dateComponents([.day], from: todayStart, to: cal.startOfDay(for: event.date)).day ?? 0
                result.append(PotUpcomingItem(id: event.id, date: event.date, kind: event.kind,
                                              title: title(of: event, pot: pot),
                                              detail: detail(of: event, pot: pot, data: data),
                                              amount: CentsMath.value(cents),
                                              balanceAfter: CentsMath.value(running),
                                              daysAhead: ahead))
            }
            month = month.adding(1)
            count += 1
        }
        return result
    }

    /// De titel zoals hij op de pagina van de pot zelf klinkt: de pot hoeft er niet bij.
    private static func title(of event: DayEvent, pot: Pot) -> String {
        switch event.kind {
        case .toPot: return "Inleg"
        case .interest: return "Rente"
        default:
            var text = event.title
            let suffix = " (uit \(pot.name))"
            if text.hasSuffix(suffix) { text.removeLast(suffix.count) }
            return text
        }
    }

    private static func detail(of event: DayEvent, pot: Pot, data: FinanceData) -> String? {
        switch event.kind {
        case .toPot:
            let rule = data.allocationRule(pot.id, in: YearMonth(date: event.date))
            return rule.isPercent ? rule.summary : nil
        case .expense: return "Uitgave uit deze pot"
        default: return nil
        }
    }
}

// MARK: - Een spaarpot verwijderen

/// Wat het verwijderen van een spaarpot doet met je rekening, voor in de bevestiging. De getallen komen uit een proef op een
/// kopie van de gegevens met precies dezelfde functies als bij het echte verwijderen (`deletePot`).
struct PotDeleteEffect: Equatable {
    var potName: String
    /// Het saldo van de pot nu.
    var balance: Double
    /// Het banksaldo nu. nil als dat nog niet bekend is.
    var bankNow: Double?
    /// Het banksaldo nu als het saldo van de pot terug naar de bank gaat (`deletePot(_:returningBalanceToBank: true)`).
    var bankIfReturned: Double?
    /// Het banksaldo nu bij gewoon verwijderen (`deletePot(_:)`): de geplande overboekingen naar de pot verdwijnen dan uit
    /// het bankverloop, en het saldo van de pot vervalt.
    var bankIfDiscarded: Double?

    /// Er staat geld op de pot (op centen): dan is er een keuze tussen terugzetten en laten vervallen.
    var hasBalance: Bool { CentsMath.int(balance) > 0 }

    /// Wat je vermogen verandert als het saldo vervalt: wat er op je rekening bij komt (de geplande overboekingen naar de pot
    /// vallen weg) min het saldo dat uit de pot verdwijnt. nil zolang het banksaldo niet bekend is.
    var netWorthChangeIfDiscarded: Double? {
        guard let now = bankNow, let after = bankIfDiscarded else { return nil }
        return CentsMath.value(CentsMath.int(after) - CentsMath.int(now) - CentsMath.int(balance))
    }

    /// De uitleg voor in de bevestiging, met de getallen van de rekenmotor.
    var message: String {
        var parts: [String] = []
        if hasBalance {
            parts.append("Er staat \(Fmt.euro(balance)) op.")
            if let now = bankNow, let back = bankIfReturned, let gone = bankIfDiscarded {
                parts.append("Je rekening staat nu op \(Fmt.euro(now)). Zet je het saldo terug, dan wordt dat \(Fmt.euro(back)). Laat je het vervallen, dan wordt het \(Fmt.euro(gone)).")
                if let change = netWorthChangeIfDiscarded, CentsMath.int(change) != 0 {
                    parts.append("Je vermogen verandert dan met \(change > 0 ? "+" : "−")\(Fmt.euro(abs(change))).")
                }
            } else {
                parts.append("Zet je het saldo terug, dan komt dat bedrag op je rekening. Laat je het vervallen, dan verdwijnt het uit je vermogen.")
            }
        } else if let now = bankNow, let gone = bankIfDiscarded, CentsMath.int(now) != CentsMath.int(gone) {
            parts.append("Je rekening verandert van \(Fmt.euro(now)) naar \(Fmt.euro(gone)): wat er eerder naar deze pot ging, gaat er dan niet meer af.")
        }
        parts.append(hasBalance ? "De boekingen van deze pot verdwijnen in beide gevallen." : "De boekingen van deze pot verdwijnen ook.")
        return parts.joined(separator: " ")
    }

    init?(_ data: FinanceData, potID: UUID, current: YearMonth, today: Date) {
        guard let pot = data.pot(potID) else { return nil }
        potName = pot.name
        balance = data.potBalanceNow(potID, current: current, today: today)
        bankNow = data.bankBalanceNowIfKnown(current: current, today: today)
        var returned = data
        returned.deletePot(potID, returningBalanceToBank: true, current: current, today: today)
        bankIfReturned = returned.bankBalanceNowIfKnown(current: current, today: today)
        var discarded = data
        discarded.deletePot(potID)
        bankIfDiscarded = discarded.bankBalanceNowIfKnown(current: current, today: today)
    }
}
