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

    // Een derde reeks ingrepen (weer een eigen zaadwaarde): inleg als percentage van het inkomen (vast en per maand
    // anders, met allebei de grondslagen, ook samen boven de 100%) en terugkerende regels die worden overgeslagen,
    // gestopt, bewerkt of later toegevoegd. Het dagboek moet ook dan op elke dag sluiten met het maandoverzicht.
    var y = EngRandom(seed: seed &+ 13_000)
    func percent() -> Double {
        // Soms een rond getal, soms een percentage met twee decimalen dat op halve centen uitkomt (33,33%).
        y.chance(40) ? Double(y.int(0...20)) * 5 : Double(y.int(0...10_000)) / 100
    }
    func basis() -> IncomeBasis { y.chance(50) ? .salary : .allIncome }
    if y.chance(40) {
        let ids = d.pots.map(\.id) + d.holdings.map(\.id)
        if !ids.isEmpty {
            features.insert("percentage-inleg")
            for _ in 0..<y.int(1...min(3, ids.count)) {
                d.setContributionPercent(ids[y.int(0...ids.count - 1)], percent: percent(), basis: basis(),
                                         current: start.adding(y.int(0...span)))
            }
        }
    }
    if y.chance(30) {
        let ids = d.pots.map(\.id) + d.holdings.map(\.id)
        if !ids.isEmpty {
            features.insert("percentage per maand")
            for _ in 0..<y.int(1...3) {
                let id = ids[y.int(0...ids.count - 1)]
                let month = start.adding(y.int(0...span))
                switch y.int(0...2) {
                case 0: d.setAllocationPercent(id, in: month, percent: percent(), basis: basis())
                case 1: d.setAllocationPercent(id, in: month, percent: percent())
                default: d.clearAllocationOverride(id, in: month)
                }
            }
        }
    }
    if y.chance(35) {
        let month = start.adding(y.int(0...span))
        let kind: FinanceData.LineKind = y.chance(70) ? .expense : .income
        let plan = d.plan(for: month)
        let recurring = (kind == .expense ? plan.expenses : plan.extraIncome).filter { $0.isRecurring }
        if let line = recurring.isEmpty ? nil : recurring[y.int(0...recurring.count - 1)] {
            switch y.int(0...3) {
            case 0:
                features.insert("reeks overgeslagen")
                d.removeLine(id: line.id, kind: kind, in: month, scope: .thisMonth)
            case 1:
                features.insert("reeks gestopt")
                d.removeLine(id: line.id, kind: kind, in: month, scope: .thisAndFollowing)
            default:
                features.insert("reeks bewerkt")
                var changed = line
                changed.amount = y.amount(5, 900)
                if y.chance(40) { changed.day = y.int(1...31) }
                d.updateLine(changed, kind: kind, in: month, scope: y.chance(50) ? .thisMonth : .thisAndFollowing)
            }
        }
    }
    if y.chance(30) {
        features.insert("reeks later toegevoegd")
        var line = MoneyLine(name: "Abonnement", amount: y.amount(5, 200), isRecurring: true, kind: .fixed,
                             day: y.chance(80) ? y.int(1...31) : nil)
        line.id = StableID.uuid("ledger-test-series|\(seed)")
        d.addRecurringLine(line, kind: y.chance(80) ? .expense : .income, in: start.adding(y.int(0...span)))
    }

    // Een vierde reeks ingrepen (weer een eigen zaadwaarde): het salaris komt niet elke maand maar om de zoveel weken of dagen
    // binnen (elke 4, 2 of 1 week, elke 10 dagen, elke 31 dagen, een willekeurige cyclus, ook zo lang dat sommige maanden
    // geen uitbetaling hebben), met een ankerdatum in het verleden of de toekomst, of zonder (dan telt de salarisdag van de
    // startmaand). Soms heeft een maand een eigen salaris of eigen uren. Overal moeten de uitbetalingen op hun eigen dag
    // vallen en bank, potten en overzicht blijven sluiten.
    var z = EngRandom(seed: seed &+ 21_000)
    if z.chance(45) {
        let choice = z.int(0...7)
        var anchor: CalendarDay?
        if z.chance(80) {
            anchor = CalendarDay(date: engTime(start, 15, hour: 12).addingTimeInterval(Double(z.int(-400...400)) * 86_400))
        }
        switch choice {
        case 0: d.salary.setSchedule(.weeks, interval: 4, anchor: anchor)
        case 1: d.salary.setSchedule(.weeks, interval: 2, anchor: anchor)
        case 2: d.salary.setSchedule(.weeks, interval: 1, anchor: anchor)
        case 3: d.salary.setSchedule(.days, interval: 10, anchor: anchor)
        case 4: d.salary.setSchedule(.days, interval: z.int(1...60), anchor: anchor)
        case 5: d.salary.setSchedule(.weeks, interval: z.int(5...9), anchor: anchor)
        case 6: d.salary.setSchedule(.days, interval: 31, anchor: anchor)
        default: d.salary.setSchedule(.days, interval: z.int(61...366), anchor: anchor)
        }
        features.insert("salaris om de zoveel weken of dagen")
        if z.chance(40) {
            let month = start.adding(z.int(0...span))
            let useSalary = z.chance(50)
            let salaryValue = z.amount(0, 3_000)
            let hoursValue = Double(z.int(0...160))
            features.insert("salarisoverschrijving")
            d.editPlan(month) { plan in
                if useSalary { plan.salaryOverride = salaryValue } else { plan.hoursOverride = hoursValue }
            }
        }
    }

    // Een vijfde reeks ingrepen (weer een eigen zaadwaarde, AAN HET EIND: de vier reeksen hierboven blijven voor elke zaadwaarde
    // gelijk): een startdatum, ook midden in een maand, met handmatige boekingen en een ingevuld saldo van vóór die dag. Wat voor
    // de startdag valt telt niet mee (docs/work/plan.md par. 2.1) en blijft bewaard; het dagboek sluit ook dan op elke dag.
    var q = EngRandom(seed: seed &+ 29_000)
    if q.chance(40) {
        let month = start.adding(q.int(0...2))
        let dayNumber = q.chance(25) ? 1 : q.int(1...month.dayCount)
        let first = CalendarDay(month: month, day: dayNumber)
        d.setStart(first)
        features.insert(dayNumber > 1 ? "startdatum midden in de maand" : "startdatum op de eerste")
        let cutoff = YearMonth.calendar.startOfDay(for: first.date())
        if q.chance(60) {
            let before = cutoff.addingTimeInterval(-Double(q.int(1...20)) * 86_400 - Double(q.int(0...20)) * 3_600)
            d.addBankEntry(amount: q.amount(5, 400), note: "Voor de start", date: before)
            if let pot = d.pots.first { d.addPotEntry(potID: pot.id, amount: q.amount(5, 300), kind: .deposit, note: "Voor de start", date: before) }
            if q.chance(60) { d.addBankSnapshot(balance: q.amount(-200, 3_000), note: "Voor de start", date: before) }
        }
        // Soms heeft de startmaand een eigen salaris of eigen uren: dat is dan het totaal dat telt.
        if q.chance(30) {
            let useSalary = q.chance(50)
            let salaryValue = q.amount(300, 3_000)
            let hoursValue = Double(q.int(20...160))
            d.editPlan(month) { plan in
                if useSalary { plan.salaryOverride = salaryValue } else { plan.hoursOverride = hoursValue }
            }
            features.insert("eigen salaris in de startmaand")
        }
        let hidden = d.entriesBefore(first)
        if hidden.bank + hidden.pots + hidden.balances > 0 { features.insert("boekingen vóór de start") }
    }
    return LedgerScenario(data: d, today: today, months: start.adding(-2).range(count: span + 5), seed: seed, start: start,
                          features: features)
}

// MARK: - Onafhankelijke berekening van het banksaldo

/// Het banksaldo aan het EIND van de dag `date` in hele centen, rechtstreeks uit de gebeurtenissen van de maanden
/// (`dayEvents`) en de regels voor meetpunten, zonder `BankTimeline`: het laatste meetpunt tot en met die dag is de
/// basis; planboekingen op een latere dag dan het meetpunt tellen mee, handmatige boekingen na het meetmoment ook.
/// Zonder meetpunt is de basis een 0 vlak vóór de eerste handmatige boeking (voor planboekingen: aan het begin van de dag van
/// die boeking). nil zolang er geen saldo bekend is.
func referenceBankBalanceCents(_ d: FinanceData, endOfDay date: Date, events eventsOf: (YearMonth) -> [DayEvent]) -> Int? {
    let cal = YearMonth.calendar
    let limit = DayMath.nextDayStart(after: date, calendar: cal)
    // Met een startdatum bestaat wat daarvoor valt niet: handmatige boekingen en ingevulde saldi van vóór het begin van de
    // startdag tellen niet mee. Het orakel leest de startdatum zelf uit de gegevens, niet via de hulpjes van de rekenmotor.
    var cutoff: Date?
    if let startDay = d.startDay, startDay.yearMonth == d.startMonth { cutoff = cal.startOfDay(for: startDay.date(calendar: cal)) }
    func counts(_ moment: Date) -> Bool { cutoff.map { moment >= $0 } ?? true }
    let snapshots = d.bankSnapshots.filter { counts($0.date) }.sorted { $0.date < $1.date }
    var baseCents = 0
    var entriesAfter: Date
    var planCounts: (Date) -> Bool
    if let snapshot = snapshots.last(where: { $0.date < limit }) {
        baseCents = CentsMath.int(snapshot.balance)
        entriesAfter = snapshot.date
        // Planboekingen van de dag van het meetpunt zitten al in het saldo.
        let firstPlanMoment = DayMath.nextDayStart(after: snapshot.date, calendar: cal)
        planCounts = { $0 >= firstPlanMoment }
    } else if snapshots.isEmpty, let firstEntry = d.bankEntries.filter({ counts($0.date) }).map({ $0.date }).min(), firstEntry < limit {
        // Een virtuele 0 vlak vóór de eerste boeking voor de handmatige boekingen; voor het plan (per kalenderdag) ligt hij
        // aan het begin van de dag van die boeking: de planboekingen van die hele dag tellen mee.
        entriesAfter = firstEntry.addingTimeInterval(-1)
        let dayStart = cal.startOfDay(for: firstEntry)
        planCounts = { $0 >= dayStart }
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
/// handmatige boekingen. Alle maanden zijn vastgelegd (`materialize`). Met `percentages` leggen alle potten en
/// beleggingen in als 2,5% van alle inkomsten (het bedrag wordt dan elke maand uit het inkomen uitgerekend).
func ledgerPerformanceData(percentages: Bool = false) -> (data: FinanceData, current: YearMonth) {
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
    if percentages {
        for id in d.pots.map(\.id) + d.holdings.map(\.id) {
            d.setContributionPercent(id, percent: 2.5, basis: .allIncome, current: start)
        }
    }
    d.materialize(upTo: current)
    d.applyDueInterest(upTo: current.firstDay)
    for i in 0..<20 {
        d.addBankEntry(amount: i % 2 == 0 ? 50 : -30, note: "Boeking", date: start.adding(i * 2).date(day: 14))
    }
    return (d, current)
}


// MARK: - Snelheid van deze machine

/// De snelheidstests meten met de klok. Om ze op een trage of drukke machine (een CI-server) niet onterecht te laten falen,
/// schalen hun grenzen mee met hoeveel trager de machine nu is dan waarop ze zijn gekozen: een vaste rekenklus (woordenboek,
/// sorteren, een debug-build zoals de tests zelf) wordt tegen zijn richttijd gelegd. Nooit sneller dan 1: op een snelle
/// machine blijven de grenzen zoals ze zijn. Met `SKIP_PERF_TESTS=1` worden de tijdmetingen overgeslagen.
enum MachineSpeed {
    /// De richttijd van de rekenklus op de machine waarop de grenzen zijn gekozen (mediaan van drie, debug-build).
    static let referenceSeconds = 0.065

    /// Hoe lang de rekenklus nu duurt (mediaan van drie).
    static let measuredSeconds: Double = {
        func work() -> Double {
            let start = Date()
            var dictionary: [Int: Int] = [:]
            var x: UInt64 = 88_172_645_463_325_252
            var numbers: [Int] = []
            for i in 0..<60_000 {
                x ^= x << 13
                x ^= x >> 7
                x ^= x << 17
                dictionary[Int(x % 5_000), default: 0] &+= i
                if i % 2 == 0 { numbers.append(Int(x % 1_000_000)) }
            }
            numbers.sort()
            precondition(dictionary.count > 0 && !numbers.isEmpty)
            return Date().timeIntervalSince(start)
        }
        let times = (0..<3).map { _ in work() }.sorted()
        return times[1]
    }()

    /// Hoeveel trager deze machine nu is dan de richttijd (minstens 1).
    static let slowdown: Double = max(1, measuredSeconds / referenceSeconds)

    /// Een grens voor een tijdmeting, geschaald naar deze machine.
    static func limit(_ seconds: Double) -> Double { seconds * slowdown }

    static var skipsTiming: Bool { ProcessInfo.processInfo.environment["SKIP_PERF_TESTS"] == "1" }
}
