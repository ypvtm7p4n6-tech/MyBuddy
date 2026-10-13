import XCTest
import Foundation
@testable import MyBuddyCore

// Hulpjes voor de tests van de dagboekhouding (`Ledger.swift`): willekeurige maar herhaalbare datasets (vaste
// zaadwaarden), een onafhankelijke berekening van het banksaldo en een grote dataset voor de snelheidsmeting.

/// Een willekeurige dataset met het moment van "vandaag" en de maanden die gecontroleerd worden.
struct LedgerScenario {
    var data: FinanceData
    var today: Date
    /// Van twee maanden vóór de startmaand tot twee maanden na de laatste maand met gegevens.
    var months: [YearMonth]
    var seed: UInt64
    var start: YearMonth
    /// Welke lastige ingrepen deze dataset heeft (om te controleren dat de reeks ze echt bevat).
    var features: Set<String> = []
}

/// Een herhaalbare dataset uit een zaadwaarde: startmaand (ook vóór korte maanden en schrikkeljaar), salaris met een
/// willekeurige dag (ook 29...31), spaarpotten met rente, beleggingen, uitgaven deels uit potten, extra inkomsten,
/// eigen maandplannen, handmatige stortingen en opnames, overboekingen bank <-> pot, potboekingen, banksaldi
/// midden in de maand, en rente die deels al is bijgeschreven.
func ledgerScenario(seed: UInt64) -> LedgerScenario {
    var r = EngRandom(seed: seed)
    let start = YearMonth(year: 2026, month: 1).adding(r.int(0...26))
    let span = r.int(3...9)
    var counter = 0
    func nextID(_ kind: String) -> UUID {
        counter += 1
        return StableID.uuid("ledger-test|\(seed)|\(kind)|\(counter)")
    }
    func moment(_ month: YearMonth) -> Date {
        let dayNumber = r.int(1...month.dayCount)
        return engTime(month, dayNumber, hour: Double(r.int(0...2_359)) / 100)
    }

    var d = FinanceData(startMonth: start)
    if r.chance(70) {
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: r.amount(0, 4_000), hourlyRate: 0, hoursPerWeek: 0,
                                  payDay: r.int(1...31))
    } else {
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: r.amount(10, 40),
                                  hoursPerWeek: Double(r.int(8...40)), payDay: r.int(1...31))
    }

    // Spaarpotten en beleggingen.
    for i in 0..<r.int(0...5) {
        var pot = Pot(name: "Pot \(i)", monthlyContribution: r.chance(25) ? 0 : r.amount(10, 300),
                      startMonth: start.adding(r.int(0...2)))
        pot.id = nextID("pot")
        if r.chance(45) {
            pot.interestRate = Double(r.int(5...50)) / 1_000
            pot.interestPayout = InterestPayout.allCases[r.int(0...3)]
            pot.interestPayoutDay = r.int(1...31)
            pot.interestPayoutMonth = r.int(1...12)
        }
        if r.chance(40) { pot.transferDay = r.int(1...31) }
        let opening = r.chance(70) ? r.amount(0, 2_000) : 0
        d.addPot(pot, openingBalance: opening, now: moment(start.adding(r.int(-1...1))))
    }
    for i in 0..<r.int(0...3) {
        var holding = Holding(name: "Belegging \(i)", kind: .etf, monthlyContribution: r.chance(30) ? 0 : r.amount(10, 200),
                              startMonth: start.adding(r.int(0...2)))
        holding.id = nextID("holding")
        if r.chance(40) { holding.transferDay = r.int(1...31) }
        d.holdings.append(holding)
    }
    let pots = d.pots

    func randomLine(income: Bool) -> MoneyLine {
        let amount = r.chance(5) ? 0 : r.amount(5, income ? 800 : 1_200)
        var line = MoneyLine(name: income ? "Inkomen" : "Uitgave", amount: amount, isRecurring: r.chance(70),
                             kind: r.chance(50) ? .fixed : .variable, day: r.chance(70) ? r.int(1...31) : nil)
        line.id = nextID("line")
        if !income, !pots.isEmpty, r.chance(35) {
            for _ in 0..<r.int(1...2) {
                let pot = pots[r.int(0...pots.count - 1)]
                // Soms meer dan het bedrag zelf, soms een pot die niet bestaat: de motor kapt af en laat de bank betalen.
                line.potShares.append(PotShare(id: nextID("share"), potID: r.chance(5) ? nextID("ghost") : pot.id,
                                               amount: r.amount(1, 400)))
            }
        }
        return line
    }

    // Het plan van de startmaand: terugkerende en eenmalige regels.
    var first = MonthPlan()
    for _ in 0..<r.int(0...7) { first.expenses.append(randomLine(income: false)) }
    for _ in 0..<r.int(0...2) { first.extraIncome.append(randomLine(income: true)) }
    d.months[start.key] = first

    // Eigen plannen in latere maanden: andere overschrijfdag, salaris, extra uitgave of een andere verdeling.
    for m in start.adding(1).range(count: span) where r.chance(35) {
        let extra = randomLine(income: false)
        let transferDay = r.int(1...31)
        let salary = r.amount(500, 4_000)
        let ids = pots.map(\.id) + d.holdings.map(\.id)
        let allocationID = ids.isEmpty ? nil : ids[r.int(0...ids.count - 1)]
        let allocation = r.amount(0, 400)
        let kind = r.int(0...3)
        d.editPlan(m) { plan in
            switch kind {
            case 0: plan.transferDay = transferDay
            case 1: plan.salaryOverride = salary
            case 2: plan.expenses.append(extra)
            default:
                if let allocationID { plan.allocations[allocationID.uuidString] = allocation }
            }
        }
    }
    if r.chance(60) { d.materialize(upTo: start.adding(r.int(0...span))) }

    // Handmatige boekingen op de bank en in de potten.
    for _ in 0..<r.int(0...6) {
        let when = moment(start.adding(r.int(0...span)))
        switch r.int(0...3) {
        case 0: d.addBankEntry(amount: r.amount(10, 500), note: "Storting", date: when)
        case 1: d.addBankEntry(amount: -r.amount(10, 500), note: "Opname", date: when)
        case 2: if let pot = pots.first { d.transferBankToPot(potID: pot.id, amount: r.amount(10, 300), date: when) }
        default: if let pot = pots.last { d.transferPotToBank(potID: pot.id, amount: r.amount(10, 300), date: when) }
        }
    }
    for _ in 0..<r.int(0...6) where !pots.isEmpty {
        let pot = pots[r.int(0...pots.count - 1)]
        let when = moment(start.adding(r.int(0...span)))
        switch r.int(0...3) {
        case 0: d.addPotEntry(potID: pot.id, amount: r.amount(10, 400), kind: .deposit, date: when)
        case 1: d.addPotEntry(potID: pot.id, amount: -r.amount(10, 400), kind: .withdrawal, date: when)
        case 2: d.addPotEntry(potID: pot.id, amount: r.amount(1, 50), kind: .adjustment, date: when)
        default:
            if pots.count > 1 { d.transfer(from: pot.id, to: pots[(pots.firstIndex { $0.id == pot.id }! + 1) % pots.count].id,
                                           amount: r.amount(10, 200), date: when) }
        }
    }
    // Een handmatige rente-boeking die niet bij het rooster hoort.
    if r.chance(15), let pot = pots.first {
        d.addPotEntry(potID: pot.id, amount: r.amount(1, 20), kind: .interest, note: "Los", date: moment(start.adding(r.int(0...span))))
    }

    // Banksaldi, ook midden in een maand (en soms vóór de startmaand).
    if r.chance(75) {
        for _ in 0..<r.int(1...3) {
            d.addBankSnapshot(balance: r.amount(-500, 5_000), note: "Meting", date: moment(start.adding(r.int(-1...span))))
        }
    }

    // Rente die al aan de beurt was, staat gewoon in de potten.
    if r.chance(50) { d.applyDueInterest(upTo: moment(start.adding(r.int(0...span)))) }

    let today = moment(start.adding(r.int(-1...span + 1)))

    // Een tweede, onafhankelijke reeks ingrepen (andere zaadwaarde, zodat de dataset hierboven voor elke zaadwaarde gelijk
    // blijft). Dit zijn de lastige gevallen: meer inkomsten op één dag (meer uitbetalingen per maand), boekingen op de
    // randen van een dag, een saldo precies om 12:00, een pot die verdwijnt, een pot die al voor de start bestond en de
    // hulpjes die het plan in één keer veranderen.
    var x = EngRandom(seed: seed &+ 7_000)
    var features = Set<String>()
    func edgeMoment(_ month: YearMonth) -> Date {
        let dayNumber = x.int(1...month.dayCount)
        switch x.int(0...3) {
        case 0: return engTime(month, dayNumber, hour: 0)
        case 1: return engTime(month, dayNumber, hour: 23.99)
        case 2: return engTime(month, dayNumber, hour: 12)
        default: return engTime(month, dayNumber, hour: Double(x.int(0...2_359)) / 100)
        }
    }
    func extraID(_ kind: String) -> UUID {
        counter += 1
        return StableID.uuid("ledger-test-extra|\(seed)|\(kind)|\(counter)")
    }
    if x.chance(30) {
        features.insert("meer uitbetalingen")
        // Meer uitbetalingen per maand: inkomsten op eigen dagen, soms twee op dezelfde dag.
        d.editPlan(start) { plan in
            for _ in 0..<x.int(1...4) {
                var line = MoneyLine(name: "Uitbetaling", amount: x.amount(20, 900), isRecurring: x.chance(75),
                                     kind: .fixed, day: x.int(1...31))
                line.id = extraID("payout")
                plan.extraIncome.append(line)
            }
        }
    }
    if x.chance(25), let first = d.pots.first {
        features.insert("pot van voor de start")
        var older = first
        older.startMonth = start.adding(-x.int(1...2))
        d.pots[0] = older
    }
    if x.chance(40) {
        features.insert("boekingen op de randen van een dag")
        for _ in 0..<x.int(1...3) {
            let when = edgeMoment(start.adding(x.int(-1...span)))
            d.addBankEntry(amount: x.chance(50) ? x.amount(5, 300) : -x.amount(5, 300), note: "Rand", date: when)
        }
    }
    if x.chance(25) {
        features.insert("saldo op de rand van een dag")
        d.addBankSnapshot(balance: x.amount(-300, 3_000), note: "Rand", date: edgeMoment(start.adding(x.int(-2...span + 1))))
    }
    if x.chance(20), let pot = d.pots.last {
        features.insert("potsaldo gezet")
        d.setPotBalance(pot.id, to: x.amount(0, 1_500), current: start.adding(x.int(0...span)), note: "Gezet",
                        date: edgeMoment(start.adding(x.int(0...span))))
    }
    if x.chance(15) {
        features.insert("plan in één keer veranderd")
        let month = start.adding(x.int(0...span))
        switch x.int(0...3) {
        case 0: d.applyDefaultAllocations(in: month)
        case 1: d.clearAllocations(in: month)
        case 2: d.spreadRemainingOverPots(in: month)
        default:
            if let line = d.plan(for: month).expenses.first { d.deleteLine(id: line.id, kind: .expense, in: month) }
        }
    }
    if x.chance(12), let pot = d.pots.last {
        features.insert("pot verwijderd")
        d.deletePot(pot.id, returningBalanceToBank: x.chance(60), current: YearMonth(date: today), today: today)
    }
    return LedgerScenario(data: d, today: today, months: start.adding(-2).range(count: span + 5), seed: seed, start: start,
                          features: features)
}

// MARK: - Onafhankelijke berekening van het banksaldo

/// Het banksaldo aan het EIND van de dag `date` in hele centen, rechtstreeks uit de gebeurtenissen van de maanden
/// (`dayEvents`) en de regels voor meetpunten, zonder `BankTimeline`: het laatste meetpunt tot en met die dag is de
/// basis; planboekingen op een latere dag dan het meetpunt tellen mee, handmatige boekingen na het meetmoment ook.
/// Zonder meetpunt is de basis een 0 vlak vóór de eerste handmatige boeking. nil zolang er geen saldo bekend is.
func referenceBankBalanceCents(_ d: FinanceData, endOfDay date: Date, events eventsOf: (YearMonth) -> [DayEvent]) -> Int? {
    let cal = YearMonth.calendar
    let limit = DayMath.nextDayStart(after: date, calendar: cal)
    let snapshots = d.bankSnapshots.sorted { $0.date < $1.date }
    var baseCents = 0
    var entriesAfter: Date
    var planCounts: (Date) -> Bool
    if let snapshot = snapshots.last(where: { $0.date < limit }) {
        baseCents = CentsMath.int(snapshot.balance)
        entriesAfter = snapshot.date
        // Planboekingen van de dag van het meetpunt zitten al in het saldo.
        let firstPlanMoment = DayMath.nextDayStart(after: snapshot.date, calendar: cal)
        planCounts = { $0 >= firstPlanMoment }
    } else if snapshots.isEmpty, let firstEntry = d.bankEntries.map({ $0.date }).min(), firstEntry < limit {
        // Een virtuele 0 vlak vóór de eerste boeking: niets is "al verwerkt".
        entriesAfter = firstEntry.addingTimeInterval(-1)
        let from = entriesAfter
        planCounts = { $0 > from }
    } else {
        return nil
    }
    // Alle maanden van de basis (of de startmaand van de gegevens, als die eerder is) tot en met de maand van `date`.
    var total = baseCents
    var m = min(d.startMonth, YearMonth(date: entriesAfter, calendar: cal)).adding(-1)
    let last = YearMonth(date: date, calendar: cal)
    while m <= last {
        for event in eventsOf(m) where event.bankAmount != 0 {
            if event.kind == .bankEntry {
                if event.date > entriesAfter && event.date < limit { total += CentsMath.int(event.bankAmount) }
            } else if planCounts(event.date) && event.date < limit {
                total += CentsMath.int(event.bankAmount)
            }
        }
        m = m.adding(1)
    }
    return total
}

// MARK: - Grote dataset voor de snelheidsmeting

/// Vijf jaar met 10 potten (de helft met maandelijkse rente), 8 beleggingen, 30 uitgaven (één deels uit een pot),
/// twee uitbetalingen per week (negen inkomstenregels per maand, elk op een eigen dag), een beginsaldo en 20
/// handmatige boekingen. Alle maanden zijn vastgelegd (`materialize`).
func ledgerPerformanceData() -> (data: FinanceData, current: YearMonth) {
    let start = YearMonth(year: 2021, month: 11)
    var d = FinanceData(startMonth: start)
    d.salary = SalarySettings(mode: .fixed, fixedMonthly: 0, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
    var plan = MonthPlan()
    for i in 0..<30 {
        plan.expenses.append(MoneyLine(name: "Uitgave \(i)", amount: Double(10 + i * 7), isRecurring: true,
                                       kind: i % 2 == 0 ? .fixed : .variable, day: 1 + (i * 3) % 28))
    }
    // Twee uitbetalingen per week: negen per maand, verspreid over de dagen (het salaris zelf komt later als schema).
    let payoutDays = [1, 4, 8, 11, 15, 18, 22, 25, 29]
    plan.extraIncome = payoutDays.enumerated().map { index, payoutDay in
        MoneyLine(name: "Uitbetaling \(index + 1)", amount: 355, isRecurring: true, day: payoutDay)
    }
    d.months[start.key] = plan
    var firstPot: UUID?
    for i in 0..<10 {
        var pot = Pot(name: "Pot \(i)", monthlyContribution: Double(20 + i * 10), startMonth: start)
        if i % 2 == 0 {
            pot.interestRate = 0.02
            pot.interestPayout = .monthly
            pot.interestPayoutDay = 1
        }
        if i % 3 == 0 { pot.transferDay = 1 + i }
        d.addPot(pot, openingBalance: 500, now: day(start, 1))
        if firstPot == nil { firstPot = pot.id }
    }
    for i in 0..<8 {
        d.holdings.append(Holding(name: "Belegging \(i)", kind: .etf, monthlyContribution: Double(25 + i * 5), startMonth: start))
    }
    if let firstPot {
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 100, day: 10, potShares: [PotShare(potID: firstPot, amount: 40)]),
                     kind: .expense, in: start)
    }
    d.addBankSnapshot(balance: 2_500, note: "Begin", date: start.firstDay.addingTimeInterval(7_200))
    let current = start.adding(59)
    d.materialize(upTo: current)
    d.applyDueInterest(upTo: current.firstDay)
    for i in 0..<20 {
        d.addBankEntry(amount: i % 2 == 0 ? 50 : -30, note: "Boeking", date: start.adding(i * 2).date(day: 14))
    }
    return (d, current)
}
