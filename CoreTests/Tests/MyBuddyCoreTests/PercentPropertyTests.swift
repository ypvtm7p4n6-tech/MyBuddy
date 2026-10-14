import XCTest
import Foundation
@testable import MyBuddyCore

// Eigenschapstest voor de inleg als percentage van het inkomen (wens 3): voor 250 willekeurige maar herhaalbare
// datasets (vaste zaadwaarden) met potten en beleggingen op een vast bedrag, een vast percentage en per maand een
// overschrijving (bedrag of percentage), met salaris (vast of uurloon), afwijkend salaris en uren, terugkerende en
// eenmalige extra inkomsten, is het bedrag van elke inleg in elke maand overal hetzelfde:
//
//   allocation(_:in:), effectiveAllocation, allocationCents, savedTotal, investedTotal, monthFigures,
//   MonthFiguresBuilder, de gebeurtenissen van de dagen (op de overschrijfdag), het saldo van de spaarpot,
//   de dagboekhouding (per dag en per maand) en remaining.
//
// De verwachte bedragen komen uit een eigen berekening in de test (Decimal, halve cent omhoog), niet uit de rekenmotor.

private struct PercentEntity {
    var id: UUID
    var isPot: Bool
    var startIndex: Int
    var transferDay: Int?
    var rule: AllocationRule
    var basisForChanges: IncomeBasis
}

private struct PercentWorld {
    var data: FinanceData
    var start: YearMonth
    var seed: UInt64
    var entities: [PercentEntity]
    /// Maandnummer -> overschrijving per pot of belegging.
    var overrides: [Int: [UUID: AllocationRule]] = [:]
    var salaryOverrides: [Int: Double] = [:]
    var hoursOverrides: [Int: Double] = [:]
    var recurringIncome: [(from: Int, amount: Double, day: Int?)] = []
    var oneOffIncome: [Int: Double] = [:]
    var expenseCents: [Int: Int] = [:]
    var bankStart: Double = 0
    var ops: [String] = []
}

private func percentWorld(seed: UInt64) -> PercentWorld {
    var r = EngRandom(seed: seed &+ 55_000)
    let start = YearMonth(year: 2026, month: 1).adding(r.int(0...23))
    var d = FinanceData(startMonth: start)
    let hourly = r.chance(35)
    if hourly {
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: Double(r.int(1_200...4_500)) / 100,
                                  hoursPerWeek: Double(r.int(8...40)), payDay: r.int(1...31))
    } else {
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: r.chance(12) ? 0 : Double(r.int(0...600_000)) / 100, hourlyRate: 0,
                                  hoursPerWeek: 0, payDay: r.int(1...31))
    }
    // Een deel van de datasets krijgt een salaris om de zoveel weken of dagen: het percentage van het salaris rekent dan over
    // de som van de uitbetalingen van die maand, en "de salarisdag" is de eerste uitbetaling van de maand.
    var schedule = EngRandom(seed: seed &+ 88_000)
    if schedule.chance(40) {
        let anchor: CalendarDay? = schedule.chance(80)
            ? CalendarDay(dayNumber: CalendarDay(month: start, day: 15).dayNumber + schedule.int(-300...300)) : nil
        switch schedule.int(0...5) {
        case 0: d.salary.setSchedule(.weeks, interval: 4, anchor: anchor)
        case 1: d.salary.setSchedule(.weeks, interval: 2, anchor: anchor)
        case 2: d.salary.setSchedule(.weeks, interval: 1, anchor: anchor)
        case 3: d.salary.setSchedule(.days, interval: schedule.int(1...45), anchor: anchor)
        case 4: d.salary.setSchedule(.days, interval: schedule.int(46...120), anchor: anchor)
        default: d.salary.setSchedule(.weeks, interval: schedule.int(2...12), anchor: anchor)
        }
    }
    let bankStart = Double(r.int(0...5_000))
    d.addBankSnapshot(balance: bankStart, note: "Start", date: start.adding(-1).date(day: 20))
    var world = PercentWorld(data: d, start: start, seed: seed, entities: [])
    world.bankStart = bankStart
    var counter = 0

    // Eerst de potten en beleggingen: hun standaardinleg verandert daarna niet meer (dat testen andere tests).
    for _ in 0..<r.int(1...5) {
        counter += 1
        let isPot = r.chance(65)
        let startIndex = r.int(0...2)
        let fixed = r.chance(40)
        var rule: AllocationRule
        var mode = ContributionMode.fixed
        var amount = 0.0
        var percent = 0.0
        var basis = IncomeBasis.salary
        if fixed {
            amount = Double(r.int(0...80_000)) / 100
            rule = .amount(amount)
        } else {
            mode = .percentage
            let hundredths = r.chance(10) ? [0, 10_000, 1, 9_999][r.int(0...3)] : r.int(0...4_000)
            percent = Double(hundredths) / 100
            basis = r.chance(50) ? .salary : .allIncome
            rule = .percent(PercentRule(percent: percent, basis: basis))
        }
        let transferDay: Int? = r.chance(50) ? r.int(1...31) : nil
        let id = StableID.uuid("percent-world|\(seed)|entity|\(counter)")
        if isPot {
            var pot = Pot(name: "Pot \(counter)", monthlyContribution: amount, startMonth: start.adding(startIndex))
            pot.id = id
            pot.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
            pot.contributionMode = mode
            pot.contributionPercent = percent
            pot.contributionBasis = basis
            pot.transferDay = transferDay
            world.data.addPot(pot, openingBalance: Double(r.int(0...50_000)) / 100,
                              now: start.firstDay.addingTimeInterval(3_600))
        } else {
            var holding = Holding(name: "Belegging \(counter)", kind: .etf, monthlyContribution: amount,
                                  startMonth: start.adding(startIndex))
            holding.id = id
            holding.contributionMode = mode
            holding.contributionPercent = percent
            holding.contributionBasis = basis
            holding.transferDay = transferDay
            world.data.holdings.append(holding)
        }
        world.entities.append(PercentEntity(id: id, isPot: isPot, startIndex: startIndex, transferDay: transferDay, rule: rule,
                                            basisForChanges: basis))
    }

    // Een vaste uitgave, zodat "te verdelen" iets anders is dan het inkomen.
    world.data.upsertLine(MoneyLine(name: "Huur", amount: Double(r.int(0...150_000)) / 100, isRecurring: true, day: r.int(1...31)),
                          kind: .expense, in: start)
    let rent = world.data.plan(for: start).expenses.first { $0.name == "Huur" }!
    for k in 0..<80 { world.expenseCents[k] = CentsMath.int(rent.amount) }

    for step in 0..<r.int(4...16) {
        let k = r.int(0...20)
        let month = start.adding(k)
        switch r.int(0...9) {
        case 0, 1:   // een vast bedrag voor één maand
            let e = world.entities[r.int(0...world.entities.count - 1)]
            let value = Double(r.int(0...80_000)) / 100
            world.data.setAllocation(e.id, in: month, amount: value)
            world.overrides[k, default: [:]][e.id] = .amount(value)
            world.ops.append("\(step): bedrag \(value) voor \(k)")
        case 2, 3:   // een percentage voor één maand (variabel percentage)
            let e = world.entities[r.int(0...world.entities.count - 1)]
            let hundredths = r.chance(10) ? [0, 10_000][r.int(0...1)] : r.int(0...6_000)
            let basis: IncomeBasis = r.chance(50) ? .salary : .allIncome
            world.data.setAllocationPercent(e.id, in: month, percent: Double(hundredths) / 100, basis: basis)
            world.overrides[k, default: [:]][e.id] = .percent(PercentRule(percent: Double(hundredths) / 100, basis: basis))
            world.ops.append("\(step): percentage \(hundredths) voor \(k)")
        case 4:   // de overschrijving wissen
            let e = world.entities[r.int(0...world.entities.count - 1)]
            world.data.clearAllocationOverride(e.id, in: month)
            world.overrides[k]?[e.id] = nil
            world.ops.append("\(step): wissen voor \(k)")
        case 5:   // een afwijkend salaris of afwijkende uren
            if hourly, r.chance(60) {
                let hours = Double(r.int(0...2_000)) / 10
                world.data.editPlan(month) { $0.hoursOverride = hours }
                world.hoursOverrides[k] = hours
            } else {
                let salary = r.chance(15) ? 0 : Double(r.int(0...700_000)) / 100
                world.data.editPlan(month) { $0.salaryOverride = salary }
                world.salaryOverrides[k] = salary
            }
            world.ops.append("\(step): salaris voor \(k)")
        case 6:   // een terugkerende extra inkomst vanaf een maand
            let amount = Double(r.int(1_000...90_000)) / 100
            let day: Int? = r.chance(70) ? r.int(1...31) : nil
            world.data.upsertLine(MoneyLine(name: "Extra \(step)", amount: amount, isRecurring: true, day: day), kind: .income, in: month)
            world.recurringIncome.append((k, amount, day))
            world.ops.append("\(step): terugkerend inkomen vanaf \(k)")
        case 7:   // een eenmalige extra inkomst
            if world.oneOffIncome[k] == nil {
                let amount = Double(r.int(1_000...90_000)) / 100
                world.data.upsertLine(MoneyLine(name: "Bonus", amount: amount, isRecurring: false, day: r.int(1...31)),
                                      kind: .income, in: month)
                world.oneOffIncome[k] = amount
                world.ops.append("\(step): bonus in \(k)")
            }
        case 8:
            world.data.materialize(upTo: start.adding(r.int(0...8)))
            world.ops.append("\(step): materialize")
        default:   // een maand vastleggen
            world.data.editPlan(month) { _ in }
            world.ops.append("\(step): vastgelegd \(k)")
        }
    }
    return world
}

/// Het verwachte bedrag in centen, met `Decimal` en halve cent omhoog (onafhankelijk van de rekenmotor).
private func expectedCents(_ rule: AllocationRule, salary: Int, all: Int) -> Int {
    switch rule {
    case .amount(let value):
        return Int((value * 100).rounded())
    case .percent(let percent):
        let base = max(0, percent.basis == .salary ? salary : all)
        let hundredths = Int((percent.percent * 100).rounded())
        var value = Decimal(base) * Decimal(hundredths) / 10_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

final class PercentPropertyTests: XCTestCase {
    private struct Coverage {
        var worlds = 0
        var checks = 0
        var percentAllocations = 0
        var fixedAllocations = 0
        var overridesPercent = 0
        var overridesAmount = 0
        var overOneHundred = 0
        var overAllocated = 0
        var zeroIncome = 0
        var hourly = 0
        var allIncomeBasis = 0
        var holdings = 0
        var transferDays: Set<Int> = []
        var scheduleMonths = 0
        var scheduleOverrides = 0
    }

    func testPercentageContributionIsTheSameInEveryCalculation() {
        let c = Collector()
        var coverage = Coverage()
        let env = ProcessInfo.processInfo.environment
        let seeds = max(250, Int(env["PERCENT_SEEDS"] ?? "") ?? 250)
        for seed in 1...seeds {
            verify(percentWorld(seed: UInt64(seed)), c, &coverage)
        }
        c.report()
        XCTAssertGreaterThan(coverage.checks, 40_000)
        XCTAssertGreaterThan(coverage.percentAllocations, 3_000, "inleggen als percentage")
        XCTAssertGreaterThan(coverage.fixedAllocations, 1_000, "inleggen als vast bedrag")
        XCTAssertGreaterThan(coverage.overridesPercent, 300, "maanden met een eigen percentage")
        XCTAssertGreaterThan(coverage.overridesAmount, 300, "maanden met een eigen bedrag")
        XCTAssertGreaterThan(coverage.overOneHundred, 100, "maanden met samen meer dan 100%")
        XCTAssertGreaterThan(coverage.overAllocated, 500, "maanden waarin meer wordt verdeeld dan er is")
        XCTAssertGreaterThan(coverage.zeroIncome, 20, "maanden zonder inkomen")
        XCTAssertGreaterThan(coverage.hourly, 40, "datasets met uurloon")
        XCTAssertGreaterThan(coverage.allIncomeBasis, 1_000, "percentages over alle inkomsten")
        XCTAssertGreaterThan(coverage.holdings, 100, "datasets met beleggingen")
        XCTAssertGreaterThan(coverage.transferDays.count, 25, "verschillende overschrijfdagen")
        XCTAssertGreaterThan(coverage.scheduleMonths, 2_000, "maanden met een salaris om de zoveel weken of dagen")
        XCTAssertGreaterThan(coverage.scheduleOverrides, 50, "schemamaanden met een eigen salaris of eigen uren")
    }

    private func verify(_ world: PercentWorld, _ c: Collector, _ coverage: inout Coverage) {
        let d = world.data
        let builder = d.monthFiguresBuilder()
        let tag = "seed \(world.seed)"
        let today = world.start.adding(3).date(day: 10)
        coverage.worlds += 1
        if d.salary.mode == .hourly { coverage.hourly += 1 }
        if d.holdings.count > 0 { coverage.holdings += 1 }
        let pots = d.pots
        var bankRunning = CentsMath.int(world.bankStart)
        var potRunning: [UUID: Int] = [:]
        for pot in pots {
            potRunning[pot.id] = d.potEntries.filter { $0.potID == pot.id }.reduce(0) { $0 + CentsMath.int($1.amount) }
        }

        for k in 0..<66 {
            let month = world.start.adding(k)
            // Inkomen van deze maand, onafhankelijk uitgerekend.
            var salaryCents: Int
            if d.salary.schedule != .monthly {
                // Het salaris is de som van de uitbetalingen van de maand (zie `SalaryTestSupport.swift`).
                salaryCents = referenceSalaryPayouts(d.salary, start: d.startMonth, month: month,
                                                     salaryOverride: world.salaryOverrides[k], hoursOverride: world.hoursOverrides[k])
                    .reduce(0) { $0 + $1.cents }
                if world.salaryOverrides[k] != nil || world.hoursOverrides[k] != nil { coverage.scheduleOverrides += 1 }
                coverage.scheduleMonths += 1
            } else if let override = world.salaryOverrides[k] {
                salaryCents = Int((override * 100).rounded())
            } else if d.salary.mode == .fixed {
                salaryCents = Int((d.salary.fixedMonthly * 100).rounded())
            } else {
                let hours = world.hoursOverrides[k] ?? d.salary.hoursPerWeek * 52 / 12
                salaryCents = Int((((d.salary.hourlyRate * hours) * 100).rounded() / 100 * 100).rounded())
            }
            var extra = 0
            for item in world.recurringIncome where k >= item.from { extra += Int((item.amount * 100).rounded()) }
            if let bonus = world.oneOffIncome[k] { extra += Int((bonus * 100).rounded()) }
            let allCents = salaryCents + extra
            if allCents <= 0 { coverage.zeroIncome += 1 }
            let expenses = world.expenseCents[k] ?? 0

            var saved = 0
            var invested = 0
            var potMonth: [UUID: Int] = [:]
            var percentSum = 0
            var transferDayTotals: [Int: Int] = [:]   // dag -> bedrag naar potten
            var holdingDayTotals: [Int: Int] = [:]
            for e in world.entities {
                let rule: AllocationRule = world.overrides[k]?[e.id] ?? (k >= e.startIndex ? e.rule : .amount(0))
                let expected = expectedCents(rule, salary: salaryCents, all: allCents)
                coverage.checks += 1
                if case .percent(let p) = rule {
                    coverage.percentAllocations += 1
                    percentSum += Int((p.percent * 100).rounded())
                    if p.basis == .allIncome { coverage.allIncomeBasis += 1 }
                } else {
                    coverage.fixedAllocations += 1
                }
                if let o = world.overrides[k]?[e.id] {
                    if o.isPercent { coverage.overridesPercent += 1 } else { coverage.overridesAmount += 1 }
                }
                c.eq(CentsMath.int(d.allocation(e.id, in: month)), expected, "\(tag): allocation \(month.key) (\(rule))")
                c.eq(CentsMath.int(d.effectiveAllocation(e.id, in: month).amount), expected, "\(tag): effectiveAllocation \(month.key)")
                c.eq(d.allocationCents(e.id, in: month), expected, "\(tag): allocationCents \(month.key)")
                if e.isPot { saved += expected } else { invested += expected }
                // Zonder eigen dag: de eerste uitbetaling van de maand bij een schema, anders de salarisdag.
                let payDay = d.salary.schedule == .monthly ? d.salary.payDay
                    : (referencePayDays(d.salary, start: d.startMonth, month: month).first ?? d.salary.payDay)
                let rawDay = e.transferDay ?? payDay
                let day = min(YearMonth.clampedDay(rawDay), month.dayCount)
                c.eq(d.transferDay(for: e.id, in: month), day, "\(tag): overschrijfdag \(month.key)")
                if expected != 0 {
                    coverage.transferDays.insert(day)
                    if e.isPot { transferDayTotals[day, default: 0] += expected } else { holdingDayTotals[day, default: 0] += expected }
                }
                if e.isPot { potMonth[e.id] = expected }
            }

            let f = d.monthFigures(month)
            c.eq(f.income, allCents, "\(tag): inkomen \(month.key)")
            c.eq(f.expenses, expenses, "\(tag): uitgaven \(month.key)")
            c.eq(f.saved, saved, "\(tag): gespaard \(month.key)")
            c.eq(f.invested, invested, "\(tag): belegd \(month.key)")
            c.eq(f.remaining, allCents - expenses - saved - invested, "\(tag): over \(month.key)")
            c.eq(builder.figures(month), f, "\(tag): MonthFiguresBuilder \(month.key)")
            c.eq(CentsMath.int(d.savedTotal(in: month)), saved, "\(tag): savedTotal \(month.key)")
            c.eq(CentsMath.int(d.investedTotal(in: month)), invested, "\(tag): investedTotal \(month.key)")
            c.eq(CentsMath.int(d.income(in: month)), allCents, "\(tag): income(in:) \(month.key)")
            c.eq(CentsMath.int(d.remaining(in: month)), f.remaining, "\(tag): remaining \(month.key)")
            let summary = d.summary(of: month, current: world.start.adding(3))
            c.eq(CentsMath.int(summary.saved), saved, "\(tag): summary gespaard \(month.key)")
            c.eq(CentsMath.int(summary.remaining), f.remaining, "\(tag): summary over \(month.key)")
            let overview = d.expenseOverview(in: month)
            c.eq(CentsMath.int(overview.leftAfterTransfers), f.remaining, "\(tag): overzicht over \(month.key)")

            // Het banksaldo aan het eind van de maand: begin + wat er die maand over is.
            bankRunning += f.remaining
            if k % 6 == 0 || k == 65 {
                c.eq(d.bankBalance(at: month).map { CentsMath.int($0) }, bankRunning, "\(tag): banksaldo eind \(month.key)")
            }

            // De gebeurtenissen van de dagen.
            let events = d.planEvents(in: month)
            c.eq(events.filter { $0.kind == .toPot }.reduce(0) { $0 + CentsMath.int($1.bankAmount) }, -saved,
                 "\(tag): overschrijvingen naar potten \(month.key)")
            c.eq(events.filter { $0.kind == .toPot }.reduce(0) { $0 + CentsMath.int($1.potAmount) }, saved,
                 "\(tag): bijschrijvingen in potten \(month.key)")
            c.eq(events.filter { $0.kind == .toHolding }.reduce(0) { $0 + CentsMath.int($1.bankAmount) }, -invested,
                 "\(tag): overschrijvingen naar beleggingen \(month.key)")
            for e in world.entities {
                guard e.isPot, let expected = potMonth[e.id], expected != 0 else { continue }
                let event = events.first { $0.kind == .toPot && $0.potID == e.id }
                c.eq(event.map { CentsMath.int($0.potAmount) }, expected, "\(tag): gebeurtenis pot \(month.key)")
            }

            // Saldo van de spaarpotten aan het eind van de maand.
            for pot in pots {
                potRunning[pot.id, default: 0] += potMonth[pot.id] ?? 0
                c.eq(CentsMath.int(d.potBalance(pot.id, at: month)), potRunning[pot.id] ?? 0, "\(tag): saldo pot eind \(month.key)")
            }

            // Waarschuwingen.
            let warnings = d.allocationWarnings(in: month)
            let over100 = percentSum > 10_000
            if over100 { coverage.overOneHundred += 1 }
            c.eq(warnings.contains { if case .percentagesOver100 = $0 { return true } else { return false } }, over100,
                 "\(tag): waarschuwing boven 100% \(month.key)")
            c.eq(CentsMath.int(d.percentTotal(in: month)), percentSum, "\(tag): som van de percentages \(month.key)")
            let allocated = saved + invested
            let available = allCents - expenses
            let isOver = allocated > 0 && allocated > max(0, available)
            if isOver { coverage.overAllocated += 1 }
            c.eq(warnings.contains { if case .overAllocated = $0 { return true } else { return false } }, isOver,
                 "\(tag): waarschuwing te veel verdeeld \(month.key)")
            for warning in warnings {
                if case .overAllocated(let by) = warning {
                    c.eq(CentsMath.int(by), allocated - max(0, available), "\(tag): hoeveel te veel \(month.key)")
                }
                c.ok(!warning.message.isEmpty, "\(tag): waarschuwing heeft een tekst")
            }
            c.eq(d.allocationWarning(in: month), warnings.first?.message, "\(tag): eerste waarschuwing \(month.key)")

            // De dagboekhouding van een paar maanden: per dag en per maand.
            if k == 0 || k == 3 || k == 7 || k == 15 {
                let ledger = d.monthLedger(month, asOf: today)
                c.ok(ledger.overviewReconciles, "\(tag): dagboek sluit niet met het overzicht \(month.key)")
                c.ok(ledger.potsReconciles, "\(tag): dagboek sluit niet met de potten \(month.key)")
                c.eq(CentsMath.int(ledger.saved), saved, "\(tag): dagboek gespaard \(month.key)")
                c.eq(CentsMath.int(ledger.planToPots), saved, "\(tag): dagboek naar potten \(month.key)")
                c.eq(CentsMath.int(ledger.invested), invested, "\(tag): dagboek belegd \(month.key)")
                c.eq(CentsMath.int(ledger.toHoldings), invested, "\(tag): dagboek naar beleggingen \(month.key)")
                c.eq(CentsMath.int(ledger.income), allCents, "\(tag): dagboek inkomen \(month.key)")
                c.eq(CentsMath.int(ledger.remaining), f.remaining, "\(tag): dagboek over \(month.key)")
                c.eq(ledger.closingBank.map { CentsMath.int($0) }, bankRunning, "\(tag): dagboek banksaldo eind \(month.key)")
                c.ok(ledger.bankReconciles, "\(tag): dagboek sluit niet met de bank \(month.key)")
                var running = ledger.openingBank.map { CentsMath.int($0) }
                for dayTotals in ledger.days {
                    let change = events.filter { $0.day == dayTotals.day }.reduce(0) { $0 + CentsMath.int($1.bankAmount) }
                    if let before = running { running = before + change }
                    c.eq(dayTotals.bankBalance.map { CentsMath.int($0) }, running, "\(tag): banksaldo eind van dag \(dayTotals.day) in \(month.key)")
                }
                for (dayNumber, total) in transferDayTotals {
                    c.eq(CentsMath.int(ledger.days[dayNumber - 1].planToPots), total, "\(tag): dag \(dayNumber) naar potten \(month.key)")
                }
                for (dayNumber, total) in holdingDayTotals {
                    c.eq(CentsMath.int(ledger.days[dayNumber - 1].toHoldings), total, "\(tag): dag \(dayNumber) naar beleggingen \(month.key)")
                }
                // Het potsaldo van de laatste dag is het saldo van de maand.
                c.eq(CentsMath.int(ledger.closingPots), pots.reduce(0) { $0 + (potRunning[$1.id] ?? 0) },
                     "\(tag): totaal potten eind \(month.key)")
            }
        }

        // Voor de start van de gegevens telt niets.
        for e in world.entities {
            c.eq(CentsMath.int(d.allocation(e.id, in: world.start.adding(-1))), 0, "\(tag): vóór de start")
        }
        c.eq(CentsMath.int(d.income(in: world.start.adding(-1))), 0, "\(tag): geen inkomen vóór de start")

        // Het inkomen hangt nooit van de verdeling af: alles op 100% van alle inkomsten verandert het inkomen niet.
        var heavy = d
        for e in world.entities { heavy.setContributionPercent(e.id, percent: 100, basis: .allIncome, current: world.start) }
        for k in [0, 1, 2, 5, 12, 40] {
            let month = world.start.adding(k)
            c.eq(heavy.monthFigures(month).income, d.monthFigures(month).income, "\(tag): inkomen hangt niet van de verdeling af \(month.key)")
            c.eq(heavy.incomeBases(in: month), d.incomeBases(in: month), "\(tag): grondslagen \(month.key)")
        }

        // Opslaan en inlezen (bestand, back-up, cloud) verandert niets aan de bedragen.
        if world.seed % 5 == 0 {
            let fileBytes = try? FinanceStorage.makeFileEncoder().encode(d)
            let fromFile = fileBytes.flatMap { try? FinanceStorage.makeDecoder().decode(FinanceData.self, from: $0) }
            c.ok(fromFile == d, "\(tag): bestand")
            let backup = (try? BackupService.export(d, now: Date(timeIntervalSince1970: 1_790_000_000))).flatMap { try? BackupService.importBackup($0) }
            c.ok(backup == d, "\(tag): back-up")
            let cloud = (try? RemoteSnapshot(finance: d)).flatMap { try? $0.decodeFinance() }
            c.ok(cloud == d, "\(tag): cloud")
            if let backup {
                for k in [0, 3, 9] {
                    c.eq(backup.monthFigures(world.start.adding(k)), d.monthFigures(world.start.adding(k)), "\(tag): cijfers na back-up \(k)")
                }
            }
        }
    }
}
