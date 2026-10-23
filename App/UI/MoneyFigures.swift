import Foundation
// In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat dit bestand als symlink
// tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in MoneyFiguresTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Eén bron per grootheid
//
// Dit bestand bevat alleen Foundation: geen SwiftUI. Het is de plek waar een scherm de cijfers haalt die op meer dan één
// plek voorkomen, zodat het Overzicht, de Maand-pagina's, de spaarpot- en beleggingspagina's en de rest hetzelfde getal tonen. Er wordt hier
// niets zelf uitgerekend dat de rekenmotor al kan: de functies pakken een motorwaarde, zetten hem om voor weergave of
// leggen er twee naast elkaar. Waar bedragen worden opgeteld gebeurt dat in hele centen (`CentsMath`).
//
// Welke functie levert welke grootheid (de peilmomenten staan erbij):
//
//   Nog te verdelen / Overgehouden maand  FinanceData.remaining(in:) = MonthFigures.remaining; een periode: PeriodSummary.remaining
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
//   Beleggingen NU               nu      portfolioValue / portfolioInvested / portfolioGain / holdingStateNow / valueByKind met
//                                        `today:` (per kalenderdag: een inleg telt vanaf zijn overschrijfdag); de grafiek
//                                        (`portfolioSeries(..., today:)`) eindigt in hetzelfde getal
//   Beleggingen eind maand       maand   dezelfde functies zonder `today:`: de start voor toekomstschatting, doelen en versnellers
//                                        (die rekenen per maand verder) en het Vermogen aan het eind van de maand
//   Inleg van een pot/belegging  maand   allocation(_:in:) (het bedrag van die maand, ook bij een percentage), met de opbouw
//                                        en de overschrijfdag in `ContributionInfo`
//   Inleg voor SCHATTINGEN       gem.    estimatedAllocation(_:in:), monthlyInvestment(current:) en estimatedMonthlyIncome(in:):
//                                        bij een salaris om de zoveel weken of dagen een GEMIDDELDE maand (zie SalarySchedule.swift)
//   Komende boekingen van een pot 30 dgn dayEvents(in:asOf:), alleen de events van die pot, door te tellen vanaf potBalanceNow
//                                        (`PotUpcoming`); op de laatste boeking van een dag is dat potBalance(_:asOf:)
//   Waarschuwing verdeling       maand   allocationWarnings(in:); in een invulformulier vooraf op een kopie (`ContributionPreview`)
//
// "nu" rekent altijd per kalenderdag met `store.today`: wat vandaag valt telt de hele dag mee, wat later komt niet.

// MARK: - De cijfers van een maand

/// De cijfers van één maand zoals Home ze toont, in één keer uit `FinanceData.monthFigures(_:)`.
///
/// Inkomen − uitgaven van de bank − verdeeld = nog te verdelen. Dat klopt hier altijd op de cent: alle getallen komen uit
/// dezelfde `MonthFigures`. Een uitgave die uit een spaarpot komt, kost het maandbudget niets: ze staat wel in het totaal
/// van de uitgaven (`expensesTotal`) maar niet in de uitgaven van de bank (`expensesFromBank`) waarmee de som sluit.
/// Bedragen worden op hele euro's getoond terwijl de motor op de cent rekent. Meestal tellen de getoonde bedragen dan gewoon
/// op; soms (ongeveer een op de drie maanden bij bedragen met centen, zoals een percentage van je inkomen) wijkt de som
/// van de getoonde bedragen een euro af van het getoonde totaal. Dan zegt het scherm dat het in de afronding zit.
enum DisplayRounding {
    static let note = "Bedragen staan afgerond op hele euro's; de berekening zelf klopt op de cent."

    /// Een bedrag in centen zoals het wordt getoond: op hele euro's (zoals `Fmt.euro`, half weg van nul).
    static func shown(_ cents: Int) -> Int {
        Int(CentsMath.value(cents).rounded())
    }

    /// Tellen de getoonde delen precies op tot het getoonde totaal? Alles in hele centen, met tekens.
    static func closes(parts: [Int], total: Int) -> Bool {
        var sum = 0
        for part in parts { sum += shown(part) }
        return sum == shown(total)
    }
}

struct MonthBoard: Equatable {
    let month: YearMonth
    let figures: MonthFigures
    /// Bij een salaris om de zoveel weken of dagen: wanneer het salaris in deze maand binnenkomt ("Salaris komt binnen op de
    /// 2e en de 30e."). Het inkomen hierboven is de som van die uitbetalingen. nil bij het maandelijkse schema.
    let salaryNote: String?

    init(_ data: FinanceData, month: YearMonth) {
        self.month = month
        self.figures = data.monthFigures(month)
        if data.salary.isMonthly || month < data.startMonth {
            salaryNote = nil
        } else {
            let days = data.salaryPayoutDaysText(in: month)
            salaryNote = days.isEmpty ? "Deze maand komt er geen salaris binnen." : "Salaris komt binnen op \(days)."
        }
    }

    init(month: YearMonth, figures: MonthFigures) {
        self.month = month
        self.figures = figures
        self.salaryNote = nil
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

    /// Tellen de getoonde (op hele euro's afgeronde) bedragen inkomen, uitgaven van de bank en verdeeld niet precies op tot het
    /// getoonde "nog te verdelen"? Dan staat er een korte uitleg bij (`DisplayRounding.note`): het zit in de afronding.
    var roundingHidesSum: Bool {
        !DisplayRounding.closes(parts: [figures.income, -(figures.expenses - figures.fromPots),
                                        -CentsMath.add(figures.saved, figures.invested)],
                                total: figures.remaining)
    }

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

/// Labels die op meer dan één scherm hetzelfde moeten zijn (termenlijst, plan par. 2.8).
enum MoneyLabels {
    /// Wat er van het maandinkomen nog te verdelen is, voor de huidige en de komende maanden. Nooit kaal "Over".
    static let remaining = "Nog te verdelen"

    /// Wat er van het maandinkomen is overgebleven, voor maanden in het verleden en voor periodes (Half jaar, Jaar).
    static let leftOver = "Overgehouden"

    /// Het label bij het getal "wat blijft er over" van een maand of periode: voor de huidige en de komende maanden
    /// "Nog te verdelen", voor het verleden en voor een periode "Overgehouden".
    static func remainingLabel(of month: YearMonth, current: YearMonth, isPeriod: Bool = false) -> String {
        (isPeriod || month < current) ? leftOver : remaining
    }

    /// "Vermogen eind oktober": bank, spaarpotten en beleggingen aan het eind van de maand, dus met wat er die maand nog
    /// binnenkomt, uitgaat en wordt overgeschreven (`netWorth(at:current:)`). Het getal staat zo op het Overzicht en op de Maand-pagina.
    static func netWorthEnd(of month: YearMonth) -> String {
        "Vermogen eind \(Fmt.monthNames[min(max(month.month, 1), 12) - 1])"
    }
}

// MARK: - Inleg van een pot of belegging

/// Waar de overschrijfdag van een inleg vandaan komt (zie `FinanceData.transferDay(for:in:)`).
enum TransferDayOrigin: Equatable {
    /// De verdeling van die maand heeft een eigen dag.
    case month
    /// De spaarpot of belegging heeft een eigen overschrijfdag.
    case own
    /// Je salarisdag (het maandelijkse schema).
    case salaryDay
    /// Bij een salaris om de zoveel weken of dagen: de eerste uitbetaling van die maand.
    case firstSalaryDay
    /// Bij een salaris om de zoveel weken of dagen komt er die maand geen salaris binnen: de ingestelde salarisdag.
    case salaryDayFallback
}

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
    /// De dag van `month` waarop de inleg wordt overgeboekt (`transferDay(for:in:)`).
    var transferDay: Int
    /// Waar die dag vandaan komt: de verdeling van de maand, een eigen dag, of de salarisdag.
    var transferOrigin: TransferDayOrigin

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
        transferDay = data.transferDay(for: id, in: month)
        // Dezelfde volgorde als `transferDay(for:in:)`: de verdeling van de maand, dan de pot of belegging zelf, dan de salarisdag.
        if data.months[month.key]?.transferDay != nil {
            transferOrigin = .month
        } else if (data.pot(id)?.transferDay ?? data.holding(id)?.transferDay) != nil {
            transferOrigin = .own
        } else if data.salary.isMonthly {
            transferOrigin = .salaryDay
        } else if data.salaryPayDays(in: month).isEmpty {
            transferOrigin = .salaryDayFallback
        } else {
            transferOrigin = .firstSalaryDay
        }
    }

    /// Of er iets wordt ingelegd: deze maand een bedrag, of een standaardregel die niet nul is.
    var hasContribution: Bool { amount != 0 || standard != .amount(0) }

    /// "De inleg gaat op de 25e naar deze pot, je salarisdag." `target` is waar het naartoe gaat ("naar deze pot", "van je
    /// rekening naar deze belegging"). nil als er niets wordt ingelegd. Bij een salaris om de zoveel weken of dagen is de
    /// salarisdag de eerste uitbetaling van de maand, en zonder uitbetaling die maand de ingestelde salarisdag.
    func transferNote(to target: String) -> String? {
        guard hasContribution else { return nil }
        let base = "De inleg gaat op de \(transferDay)e \(target)"
        switch transferOrigin {
        case .month, .own: return base + "."
        case .salaryDay: return base + ", je salarisdag."
        case .firstSalaryDay: return base + ", de eerste salarisdag van de maand."
        case .salaryDayFallback: return base + ", je ingestelde salarisdag. Deze maand komt er geen salaris binnen."
        }
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

extension ContributionInfo {
    /// De regel onder een spaarpot of belegging in een lijst: "Inleg 10% van je salaris, € 300 deze maand". Alleen voor een
    /// pot of belegging met een percentage (als standaard of in deze maand); een vast bedrag krijgt geen extra regel, want
    /// de pagina zelf laat het zien. Licht van aard (geen waarschuwingen), want een lijst bouwt hem voor elke rij.
    static func listLine(_ data: FinanceData, id: UUID, month: YearMonth) -> String? {
        let rule = data.allocationRule(id, in: month)
        guard rule.isPercent || data.contributionRule(of: id)?.isPercent == true else { return nil }
        let amount = Fmt.euro(data.allocation(id, in: month))
        if rule.isPercent { return "Inleg \(rule.summary), \(amount) deze maand" }
        // De standaard is een percentage, maar deze maand heeft een eigen bedrag.
        return "Deze maand een eigen bedrag van \(amount)"
    }
}

/// De uitkomst van een percentage voor in een invulformulier: "= € 300" per maand, vóór het bewaren. Rekent met de
/// rekenmotor (`percentAmount`), precies zoals de verdeling het straks doet.
enum ContributionPreview {
    struct Result: Equatable {
        /// Wat het percentage in `month` oplevert (per maand: elke maand rekent opnieuw met het inkomen van die maand).
        var amount: Double
        /// "Per maand: 10% van € 3.000 salaris in oktober", naast "= € 300" in het invulveld.
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
        let note = "Per maand: \(Fmt.percent(clean / 100, digits: 2)) van \(Fmt.euro(base)) \(what) in \(monthName)"

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

    /// De waarschuwingen van `month` zoals ze zijn nadat deze spaarpot is bewaard: de percentages samen boven 100% van het
    /// inkomen, of meer verdeeld dan er te verdelen is. Rekent op een kopie van de gegevens met precies dezelfde stappen als
    /// bewaren (`updatePot`, `addPot`), dus het scherm waarschuwt vooraf met wat de motor straks ook meldt.
    static func warnings(_ data: FinanceData, pot: Pot, month: YearMonth) -> [AllocationWarning] {
        var trial = data
        if trial.pot(pot.id) != nil { trial.updatePot(pot, current: month) } else { trial.addPot(pot) }
        return trial.allocationWarnings(in: month)
    }

    /// Zoals `warnings(_:pot:month:)`, voor een belegging.
    static func warnings(_ data: FinanceData, holding: Holding, month: YearMonth) -> [AllocationWarning] {
        var trial = data
        if trial.holding(holding.id) != nil { trial.updateHolding(holding, current: month) } else { trial.addHolding(holding) }
        return trial.allocationWarnings(in: month)
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
