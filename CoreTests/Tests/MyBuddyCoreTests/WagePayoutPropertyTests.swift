import XCTest
import Foundation
@testable import MyBuddyCore

/// Eigenschapstests voor het loon per maand (docs/work/plan2.md par. 6.2): voor willekeurige (maar herhaalbare) datasets met loonwijzigingen,
/// een salaris per maand of om de zoveel weken of dagen, een eigen salaris of eigen uren, uren uit de agenda en een startdatum komen de
/// uitbetalingen overeen met een onafhankelijke berekening (`referenceSalarySettings`, `referenceSalaryPayouts`, `referenceAgendaPayout`),
/// sluit het dagboek, en verandert `setWage` het verleden niet. De datasets komen uit `ledgerScenario` (zevende en achtste reeks).
final class WagePayoutPropertyTests: XCTestCase {
    private struct Coverage {
        var datasets = 0
        var withChange = 0
        var scheduleWithChange = 0
        var overrideWithChange = 0
        var agendaWithChange = 0
        var startDateWithChange = 0
        var monthsAfterAChange = 0
        var currentMonthChanges = 0
        var fixedSalaryChanges = 0
    }

    func testPayoutsMatchAnIndependentCalculationOnRandomDatasets() {
        var coverage = Coverage()
        // Voor een grotere speurtocht: WAGE_SEEDS=1500 swift test --filter WagePayoutPropertyTests.
        let seeds = max(300, Int(ProcessInfo.processInfo.environment["WAGE_SEEDS"] ?? "") ?? 300)
        for seed in 1...seeds {
            // De dataset van `ledgerScenario` zelf en een variant met uren uit de agenda en eigen loonwijzigingen (de reeksen van
            // `ledgerScenario` met uren uit de agenda en met loonwijzigingen komen nooit samen voor; de variant zorgt dat ze elkaar raken).
            verify(ledgerScenario(seed: UInt64(seed)), coverage: &coverage)
            var variant = ledgerScenario(seed: UInt64(seed))
            var r = EngRandom(seed: UInt64(seed) &+ 33_300)
            if r.chance(55) { engApplyRandomAgenda(&variant.data, &r, around: variant.start, months: variant.months.count - 5) }
            if r.chance(70) {
                for _ in 0..<r.int(1...3) {
                    let month = variant.start.adding(r.int(-1...variant.months.count - 5))
                    if variant.data.salary.mode == .hourly {
                        variant.data.setSalaryChange(SalaryChange(from: month, hourlyRate: r.amount(8, 45), hoursPerWeek: r.chance(40) ? Double(r.int(8...40)) : nil))
                    } else {
                        variant.data.setSalaryChange(SalaryChange(from: month, fixedMonthly: r.amount(0, 4_500)))
                    }
                }
            }
            verify(variant, coverage: &coverage)
        }
        XCTAssertGreaterThan(coverage.datasets, 599)
        XCTAssertGreaterThan(coverage.withChange, 100, "datasets met een loonwijziging")
        XCTAssertGreaterThan(coverage.scheduleWithChange, 8, "datasets met een salaris om de zoveel weken of dagen en een wijziging")
        XCTAssertGreaterThan(coverage.overrideWithChange, 8, "datasets met een eigen salaris of eigen uren naast een wijziging")
        XCTAssertGreaterThan(coverage.agendaWithChange, 8, "datasets met uren uit de agenda en een wijziging")
        XCTAssertGreaterThan(coverage.startDateWithChange, 8, "datasets met een startdatum en een wijziging")
        XCTAssertGreaterThan(coverage.monthsAfterAChange, 500, "maanden waarin een wijziging al gold")
        XCTAssertGreaterThan(coverage.currentMonthChanges, 8, "datasets met een wijziging vanaf de lopende maand")
        XCTAssertGreaterThan(coverage.fixedSalaryChanges, 8, "datasets met een vast bedrag en een wijziging")
    }

    private func verify(_ scenario: LedgerScenario, coverage: inout Coverage) {
        let f = EngFailures()
        defer { f.report() }
        let d = scenario.data
        let seed = scenario.seed
        coverage.datasets += 1
        guard !d.salaryChanges.isEmpty else {
            // Zonder wijzigingen is het loon van elke maand het loon van het begin.
            f.eq(d.salarySettings(in: scenario.start.adding(3)), d.salary, "zaadwaarde \(seed): zonder wijzigingen")
            return
        }
        coverage.withChange += 1
        if scenario.features.contains("loon vanaf de lopende maand") { coverage.currentMonthChanges += 1 }
        if d.salary.mode == .fixed { coverage.fixedSalaryChanges += 1 }
        let hasOverride = scenario.months.contains { month in
            let plan = d.plan(for: month)
            return month >= d.startMonth && (plan.salaryOverride != nil || plan.hoursOverride != nil)
        }
        if !d.salary.isMonthly { coverage.scheduleWithChange += 1 }
        if hasOverride { coverage.overrideWithChange += 1 }
        if d.usesCalendarHours { coverage.agendaWithChange += 1 }
        if d.effectiveStartDay != nil { coverage.startDateWithChange += 1 }
        for month in scenario.months where month >= d.startMonth {
            let plan = d.plan(for: month)
            let wage = referenceSalarySettings(d, month: month)
            f.eq(d.salarySettings(in: month), wage, "zaadwaarde \(seed) \(month.key): het loon van de maand")
            f.eq(d.salarySettings(forPayoutOn: CalendarDay(month: month, day: 1)), wage, "zaadwaarde \(seed) \(month.key): het loon op de eerste")
            f.eq(d.salarySettings(forPayoutOn: CalendarDay(month: month, day: month.dayCount)), wage, "zaadwaarde \(seed) \(month.key): het loon op de laatste dag")
            let agendaHours = d.work.hoursSource == .calendar && d.salary.mode == .hourly
            let expected = referenceSalaryPayouts(wage, start: d.startMonth, month: month, startDay: d.startDay,
                                                  salaryOverride: plan.salaryOverride, hoursOverride: plan.hoursOverride,
                                                  agenda: agendaHours ? { referenceAgendaPayout(d, payoutDay: $0).cents } : nil)
            let payouts = d.salaryPayouts(in: month, plan: plan)
            f.eq(payouts.map { $0.day }, expected.map { $0.day }, "zaadwaarde \(seed) \(month.key): dagen")
            f.eq(payouts.map { $0.cents }, expected.map { $0.cents }, "zaadwaarde \(seed) \(month.key): bedragen")
            f.eq(d.salaryCents(in: month, plan: plan), expected.reduce(0) { $0 + $1.cents }, "zaadwaarde \(seed) \(month.key): salaris van de maand")
            f.ok(d.monthLedger(month, asOf: scenario.today).allReconciles, "zaadwaarde \(seed) \(month.key): het dagboek sluit niet")
            if let first = d.salaryChanges.first, first.from <= month { coverage.monthsAfterAChange += 1 }
        }
        // De lijst is op maand gesorteerd, één per maand, en een wijziging zonder velden komt er niet in.
        f.eq(d.salaryChanges.map { $0.from.index }, d.salaryChanges.map { $0.from.index }.sorted(), "zaadwaarde \(seed): gesorteerd")
        f.eq(Set(d.salaryChanges.map { $0.from.index }).count, d.salaryChanges.count, "zaadwaarde \(seed): één per maand")
        f.ok(d.salaryChanges.allSatisfy { !$0.isEmpty }, "zaadwaarde \(seed): geen lege wijziging")
    }

    /// `setWage` laat de maanden voor de lopende maand zoals ze waren (er wordt niets vastgelegd) en de lopende en komende maanden volgen
    /// het nieuwe loon, voor willekeurige datasets met een salaris in het verleden.
    func testSetWageNeverChangesThePast() {
        var checked = 0
        var withSalaryBefore = 0
        for seed in 1...150 {
            let scenario = ledgerScenario(seed: UInt64(seed) &+ 900)
            var d = scenario.data
            var r = EngRandom(seed: UInt64(seed) &+ 6_100)
            let current = scenario.start.adding(r.int(1...4))
            let months = scenario.months
            let f = EngFailures()
            let past = months.filter { $0 < current }
            let before = past.map { d.monthFigures($0) }
            let salaryBefore = past.map { d.salaryAmount(in: $0) }
            let hadSalary = d.hasSalary(before: current)
            if hadSalary { withSalaryBefore += 1 }
            let newRate = r.amount(8, 45)
            let newFixed = r.amount(0, 4_500)
            if d.salary.mode == .hourly { d.setWage(current: current, hourlyRate: newRate) } else { d.setWage(current: current, fixedMonthly: newFixed) }
            if hadSalary || !scenario.data.salaryChanges.isEmpty {
                f.eq(past.map { d.monthFigures($0) }, before, "zaadwaarde \(seed): de maanden voor de lopende maand zijn veranderd")
                f.eq(past.map { d.salaryAmount(in: $0) }, salaryBefore, "zaadwaarde \(seed): het salaris van het verleden is veranderd")
                // Er wordt niets vastgelegd: dezelfde maanden hebben dezelfde eigen salarissen als voor de wijziging.
                f.eq(d.months.mapValues { $0.salaryOverride }, scenario.data.months.mapValues { $0.salaryOverride }, "zaadwaarde \(seed): vastgelegde salarissen")
                f.ok(d.salaryChange(startingIn: current) != nil, "zaadwaarde \(seed): de wijziging gaat in op de lopende maand")
                f.eq(d.salary, scenario.data.salary, "zaadwaarde \(seed): het loon van het begin blijft")
            } else {
                // Niets om te beschermen: het loon zelf is aangepast, zoals vroeger, en er komt geen wijziging in de lijst.
                f.ok(d.salaryChanges.isEmpty, "zaadwaarde \(seed): geen wijziging zonder verleden")
                if d.salary.mode == .hourly { f.eq(d.salary.hourlyRate, newRate, "zaadwaarde \(seed): het uurloon is aangepast") }
                else { f.eq(d.salary.fixedMonthly, newFixed, "zaadwaarde \(seed): het bedrag is aangepast") }
            }
            for month in months where month >= current && month >= d.startMonth {
                f.ok(d.monthLedger(month, asOf: scenario.today).allReconciles, "zaadwaarde \(seed) \(month.key): het dagboek sluit niet")
            }
            checked += 1
            f.report()
        }
        XCTAssertEqual(checked, 150)
        XCTAssertGreaterThan(withSalaryBefore, 40, "datasets met een salaris in het verleden")
    }
}
