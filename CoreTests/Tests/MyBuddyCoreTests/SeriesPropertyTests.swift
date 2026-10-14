import XCTest
import Foundation
@testable import MyBuddyCore

// Eigenschapstest voor terugkerende regels (wens 4): voor 250 willekeurige maar herhaalbare datasets (vaste zaadwaarden)
// staat elke terugkerende uitgave en extra inkomst in elke maand t/m ruim vijf jaar vooruit precies waar het orakel
// (`SeriesOracle`, zie `SeriesTestSupport.swift`) zegt: op de juiste dag, met het juiste bedrag, één keer, ook na
// bewerken en verwijderen met beide reikwijdtes en na vastleggen van maanden in willekeurige volgorde. Daarna sluiten alle
// berekeningen op dezelfde cijfers: `plan(for:)`, `monthFigures`, `MonthFiguresBuilder`, de gebeurtenissen van de dagen,
// het saldo van de spaarpot en de dagboekhouding.

final class SeriesPropertyTests: XCTestCase {
    private struct Coverage {
        var worlds = 0
        var seriesTotal = 0
        var monthsChecked = 0
        var linesChecked = 0
        var kinds: [String: Int] = [:]
        var day31 = 0
        var shortMonthLines = 0
        var withExceptions = 0
        var endedSeries = 0
        var skippedMonths = 0
        var incomeSeries = 0
        var paidFromPot = 0
        var storedBeforeAdding = 0
        var scheduleMonths = 0
    }

    func testRandomOperationsKeepEveryRecurringLineOnItsDayForFiveYears() {
        let c = Collector()
        var coverage = Coverage()
        // Voor een grotere speurtocht naar fouten: SERIES_SEEDS=3000 SERIES_OPS=25 swift test --filter SeriesPropertyTests.
        let env = ProcessInfo.processInfo.environment
        let seeds = max(250, Int(env["SERIES_SEEDS"] ?? "") ?? 250)
        let operations = 4...max(16, Int(env["SERIES_OPS"] ?? "") ?? 16)
        for seed in 1...seeds {
            let world = seriesWorld(seed: UInt64(seed), operations: operations)
            verify(world, c, &coverage)
        }
        c.report()
        XCTAssertGreaterThan(coverage.seriesTotal, 500, "genoeg reeksen")
        XCTAssertGreaterThan(coverage.linesChecked, 20_000, "genoeg regels gecontroleerd")
        XCTAssertGreaterThan(coverage.day31, 300, "regels op dag 31 (korte maanden)")
        XCTAssertGreaterThan(coverage.shortMonthLines, 1_000, "regels in korte maanden")
        XCTAssertGreaterThan(coverage.withExceptions, 60, "reeksen met een afwijkende maand")
        XCTAssertGreaterThan(coverage.endedSeries, 60, "gestopte reeksen")
        XCTAssertGreaterThan(coverage.skippedMonths, 60, "overgeslagen maanden")
        XCTAssertGreaterThan(coverage.incomeSeries, 100, "extra inkomsten")
        XCTAssertGreaterThan(coverage.paidFromPot, 100, "uitgaven deels uit een pot")
        XCTAssertGreaterThan(coverage.scheduleMonths, 3_000, "maanden met een salaris om de zoveel weken of dagen")
        for key in ["toevoegen", "bewerk volgende", "bewerk alleen", "verwijder alleen", "verwijder volgende", "vastgelegd",
                    "materialize", "eenmalig", "opgeslagen en ingelezen", "migratie", "andere salarisdag"] {
            XCTAssertGreaterThan(coverage.kinds[key] ?? 0, 60, "bewerkingen van soort: \(key)")
        }
    }

    // MARK: Controle van één dataset

    private func verify(_ world: SeriesWorld, _ c: Collector, _ coverage: inout Coverage) {
        let d = world.data
        let builder = d.monthFiguresBuilder()
        let today = world.month(2).date(day: 15)
        coverage.worlds += 1
        coverage.seriesTotal += world.series.count
        for key in ["toevoegen", "bewerk volgende", "bewerk alleen", "verwijder alleen", "verwijder volgende", "vastgelegd",
                    "materialize", "eenmalig", "opgeslagen en ingelezen", "migratie", "andere salarisdag"] {
            coverage.kinds[key, default: 0] += world.ops.filter { $0.contains(key) }.count
        }
        coverage.skippedMonths += world.ops.filter { $0.contains("verwijder alleen") }.count
        coverage.withExceptions += world.series.filter { !$0.exceptions.isEmpty }.count
        coverage.endedSeries += world.series.filter { $0.endedFrom != nil }.count
        coverage.incomeSeries += world.series.filter { $0.income }.count

        let potID = world.pot?.id
        let potStart = world.pot?.startMonth ?? world.start
        var expectedPot = CentsMath.int(world.potOpening)
        var expectedBank = CentsMath.int(world.bankStart)
        let tag = "seed \(world.seed)"

        for k in 0..<world.horizon {
            let month = world.month(k)
            let plan = d.plan(for: month)
            let events = d.planEvents(in: month)
            var eventDays: [UUID: [Int]] = [:]
            for e in events where e.kind == .expense || e.kind == .income {
                if let id = e.lineID { eventDays[id, default: []].append(e.day) }
            }
            coverage.monthsChecked += 1

            // Het salaris: de uitbetalingen van de maand (bij het maandelijkse schema het maandbedrag), onafhankelijk uitgerekend.
            var incomeCents = referenceSalaryPayouts(d.salary, start: d.startMonth, month: month,
                                                     salaryOverride: world.salaryOverrides[k]).reduce(0) { $0 + $1.cents }
            if d.salary.schedule != .monthly { coverage.scheduleMonths += 1 }
            var expenseCents = 0
            var fromPotCents = 0
            for oracle in world.series {
                let lines = (oracle.income ? plan.extraIncome : plan.expenses).filter { $0.name == oracle.name }
                guard let value = oracle.months[k] else {
                    c.eq(lines.count, 0, "\(tag): \(oracle.name) hoort niet in \(month.key) (ops: \(world.ops.suffix(6)))")
                    continue
                }
                coverage.linesChecked += 1
                if value.day == 31 { coverage.day31 += 1 }
                if month.dayCount < 31 { coverage.shortMonthLines += 1 }
                if value.fromPot > 0 { coverage.paidFromPot += 1 }
                c.eq(lines.count, 1, "\(tag): \(oracle.name) moet precies één keer in \(month.key) staan")
                guard let line = lines.first else { continue }
                c.eq(line.amount, value.amount, "\(tag): bedrag van \(oracle.name) in \(month.key)")
                c.eq(line.day, value.day, "\(tag): dag van \(oracle.name) in \(month.key)")
                c.ok(line.isRecurring, "\(tag): \(oracle.name) is terugkerend in \(month.key)")
                c.eq(line.kind, oracle.kind, "\(tag): soort van \(oracle.name) in \(month.key)")
                // Inkomsten zonder eigen dag: de eerste uitbetaling van de maand bij een schema, anders de salarisdag.
                let salaryDay = d.salary.schedule == .monthly ? YearMonth.clampedDay(d.salary.payDay)
                    : (referencePayDays(d.salary, start: d.startMonth, month: month).first ?? YearMonth.clampedDay(d.salary.payDay))
                let rawDay = value.day ?? (oracle.income ? salaryDay : 1)
                let expectedDay = min(rawDay, month.dayCount)
                let days = eventDays[line.id] ?? []
                c.ok(!days.isEmpty && days.allSatisfy { $0 == expectedDay },
                     "\(tag): \(oracle.name) in \(month.key) hoort op dag \(expectedDay), gebeurtenissen: \(days)")
                if let info = d.seriesInfo(of: line, in: month) {
                    c.eq(info.isException, oracle.exceptions.contains(k), "\(tag): afwijkende maand \(oracle.name) in \(month.key)")
                    c.eq(info.lastMonth, oracle.endedFrom.map { world.month($0 - 1) },
                         "\(tag): laatste maand van \(oracle.name) (gezien vanuit \(month.key))")
                } else {
                    c.ok(false, "\(tag): seriesInfo ontbreekt voor \(oracle.name) in \(month.key)")
                }
                let cents = CentsMath.int(value.amount)
                if oracle.income {
                    incomeCents += cents
                } else {
                    expenseCents += cents
                    if value.fromPot > 0 { fromPotCents += min(CentsMath.int(value.fromPot), cents) }
                }
            }
            if let amount = world.oneOffs[k] {
                expenseCents += CentsMath.int(amount)
                c.eq(plan.expenses.filter { $0.name == "Eenmalig" }.count, 1, "\(tag): eenmalige uitgave in \(month.key)")
            } else {
                c.eq(plan.expenses.filter { $0.name == "Eenmalig" }.count, 0, "\(tag): geen eenmalige uitgave in \(month.key)")
            }
            c.eq(Set(events.map(\.id)).count, events.count, "\(tag): gebeurtenissen van \(month.key) hebben unieke id's")

            // Verdeling van de pot.
            var allocationCents = 0
            if let pot = world.pot {
                let planned = world.potAllocation[k] ?? (month >= potStart ? pot.monthlyContribution : 0)
                allocationCents = CentsMath.int(planned)
                c.eq(CentsMath.int(d.allocation(pot.id, in: month)), allocationCents, "\(tag): verdeling pot in \(month.key)")
            }

            // Eén antwoord op alle plekken.
            let f = d.monthFigures(month)
            c.eq(f.income, incomeCents, "\(tag): inkomen \(month.key)")
            c.eq(f.expenses, expenseCents, "\(tag): uitgaven \(month.key)")
            c.eq(f.fromPots, fromPotCents, "\(tag): uit potten \(month.key)")
            c.eq(f.saved, allocationCents, "\(tag): gespaard \(month.key)")
            c.eq(f.remaining, incomeCents - (expenseCents - fromPotCents) - allocationCents, "\(tag): over \(month.key)")
            c.eq(builder.figures(month), f, "\(tag): MonthFiguresBuilder \(month.key)")
            c.eq(CentsMath.int(d.income(in: month)), incomeCents, "\(tag): income(in:) \(month.key)")
            c.eq(CentsMath.int(d.expensesTotal(in: month)), expenseCents, "\(tag): expensesTotal \(month.key)")
            c.eq(CentsMath.int(d.expensesFromPots(in: month)), fromPotCents, "\(tag): expensesFromPots \(month.key)")
            c.eq(CentsMath.int(d.remaining(in: month)), f.remaining, "\(tag): remaining \(month.key)")
            c.eq(CentsMath.int(d.summary(of: month, current: world.month(2)).remaining), f.remaining, "\(tag): summary \(month.key)")

            // Het saldo van de bankrekening aan het eind van de maand: begin + wat er die maand over is (inkomen min uitgaven
            // van de bank min wat naar de spaarpot gaat).
            expectedBank += incomeCents - (expenseCents - fromPotCents) - allocationCents
            if k % 6 == 0 || k == world.horizon - 1 {
                c.eq(d.bankBalance(at: month).map { CentsMath.int($0) }, expectedBank, "\(tag): banksaldo eind \(month.key)")
            }

            // Het saldo van de spaarpot aan het eind van de maand.
            expectedPot += allocationCents - fromPotCents
            if let potID {
                c.eq(CentsMath.int(d.potBalance(potID, at: month)), expectedPot, "\(tag): saldo spaarpot eind \(month.key)")
            }

            // De dagboekhouding van een paar maanden sluit op dezelfde cijfers.
            if k == 0 || k == 2 || k == 14 || k == 40 {
                let ledger = d.monthLedger(month, asOf: today)
                c.ok(ledger.overviewReconciles, "\(tag): dagboek sluit niet met het overzicht in \(month.key)")
                c.ok(ledger.potsReconciles, "\(tag): dagboek sluit niet met de potten in \(month.key)")
                c.eq(CentsMath.int(ledger.expensesTotal), expenseCents, "\(tag): dagboek uitgaven \(month.key)")
                c.eq(CentsMath.int(ledger.income), incomeCents, "\(tag): dagboek inkomen \(month.key)")
                c.eq(CentsMath.int(ledger.remaining), f.remaining, "\(tag): dagboek over \(month.key)")
                c.eq(ledger.closingBank.map { CentsMath.int($0) }, expectedBank, "\(tag): dagboek banksaldo eind \(month.key)")
                c.ok(ledger.bankReconciles, "\(tag): dagboek sluit niet met de bank \(month.key)")
                // Elke dag: het saldo is het saldo van gisteren plus wat de gebeurtenissen van die dag doen.
                var running = ledger.openingBank.map { CentsMath.int($0) }
                for dayTotals in ledger.days {
                    let change = events.filter { $0.day == dayTotals.day && $0.kind != .bankEntry }
                        .reduce(0) { $0 + CentsMath.int($1.bankAmount) }
                    if let before = running { running = before + change }
                    c.eq(dayTotals.bankBalance.map { CentsMath.int($0) }, running, "\(tag): banksaldo eind van dag \(dayTotals.day) in \(month.key)")
                }
            }
        }
    }
}
