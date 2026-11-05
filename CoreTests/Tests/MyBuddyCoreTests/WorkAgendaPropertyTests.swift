import XCTest
import Foundation
@testable import MyBuddyCore

/// Eigenschapstest voor de werkuren uit de agenda (docs/work/plan.md par. 3.5): voor willekeurige (maar herhaalbare) datasets met diensten
/// uit de agenda, toeslagen, pauzeregels, een salaris per maand of om de zoveel weken of dagen, de uren van deze of de vorige periode, een
/// horizon waarna de agenda niets meer weet, een startdatum en een maand met eigen uren, sluit het dagboek op elke dag, is elke uitbetaling
/// gelijk aan een onafhankelijke berekening (`referenceAgendaPayout`: per dag met `Calendar`, geheel centen), is het rapport van een
/// uitbetaling gelijk aan haar bedrag, en hangt het bedrag nooit van de klok af. Een fout noemt de zaadwaarde, de maand en de dag.
final class WorkAgendaPropertyTests: XCTestCase {
    private struct Coverage {
        var datasets = 0
        var months = 0
        var reportsWithAgenda = 0
        var mixed = 0
        var allExpected = 0
        var previousPeriod = 0
        var surcharge = 0
        var nightShifts = 0
        var schedules = 0
        var startDates = 0
        var ownHoursMonths = 0
        var withWageChange = 0
        var breakMinutes = 0
    }

    func testRandomAgendaScenariosMatchTheIndependentCalculation() {
        var coverage = Coverage()
        // Voor een grotere speurtocht: WORK_AGENDA_SEEDS=1500 swift test --filter WorkAgendaPropertyTests.
        let seeds = max(300, Int(ProcessInfo.processInfo.environment["WORK_AGENDA_SEEDS"] ?? "") ?? 300)
        for seed in 1...seeds {
            verify(seed: UInt64(seed), coverage: &coverage)
        }
        XCTAssertGreaterThan(coverage.datasets, 299)
        XCTAssertGreaterThan(coverage.months, 2_000, "maanden gecontroleerd")
        XCTAssertGreaterThan(coverage.reportsWithAgenda, 1_000, "uitbetalingen met uren uit de agenda")
        XCTAssertGreaterThan(coverage.mixed, 50, "uitbetalingen deels uit de agenda en deels uit het gemiddelde")
        XCTAssertGreaterThan(coverage.allExpected, 50, "uitbetalingen helemaal uit het gemiddelde")
        XCTAssertGreaterThan(coverage.previousPeriod, 60, "datasets met de uren van de vorige periode")
        XCTAssertGreaterThan(coverage.surcharge, 300, "uitbetalingen met uren met een toeslag")
        XCTAssertGreaterThan(coverage.nightShifts, 500, "diensten over middernacht")
        XCTAssertGreaterThan(coverage.schedules, 60, "datasets met een salaris om de zoveel weken of dagen")
        XCTAssertGreaterThan(coverage.startDates, 60, "datasets met een startdatum")
        XCTAssertGreaterThan(coverage.ownHoursMonths, 20, "maanden met eigen uren naast de agenda")
        XCTAssertGreaterThan(coverage.withWageChange, 40, "datasets met een loonwijziging")
        XCTAssertGreaterThan(coverage.breakMinutes, 10_000, "pauzeminuten")
    }

    private func verify(seed: UInt64, coverage: inout Coverage) {
        let f = EngFailures()
        defer { f.report() }
        let cal = YearMonth.calendar
        var scenario = ledgerScenario(seed: seed)
        var d = scenario.data
        var r = EngRandom(seed: seed &+ 37_500)
        // Altijd uren uit de agenda, met nieuwe diensten en regels (de reeks van `ledgerScenario` is maar bij een deel van de datasets).
        engApplyRandomAgenda(&d, &r, around: scenario.start, months: scenario.months.count)
        // Soms een ander schema, soms een startdatum, soms een maand met eigen uren, soms een loonwijziging.
        if r.chance(50) {
            let anchor = CalendarDay(date: engTime(scenario.start, 12, hour: 12))
            switch r.int(0...3) {
            case 0: d.salary.setSchedule(.weeks, interval: 4, anchor: anchor)
            case 1: d.salary.setSchedule(.weeks, interval: 1, anchor: anchor)
            case 2: d.salary.setSchedule(.days, interval: r.int(5...45), anchor: anchor)
            default: d.salary.setSchedule(.weeks, interval: 2, anchor: anchor)
            }
        }
        if !d.salary.isMonthly { coverage.schedules += 1 }
        if r.chance(35) {
            d.setStart(CalendarDay(month: scenario.start.adding(r.int(0...2)), day: r.int(1...28)))
            coverage.startDates += 1
        }
        let ownHoursMonth = r.chance(25) ? scenario.start.adding(r.int(0...3)) : nil
        if let ownHoursMonth {
            let hours = Double(r.int(0...160))
            d.editPlan(ownHoursMonth) { $0.hoursOverride = hours; $0.salaryOverride = nil }
        }
        if r.chance(25) {
            d.setSalaryChange(SalaryChange(from: scenario.start.adding(r.int(0...4)), hourlyRate: r.amount(8, 45),
                                           hoursPerWeek: r.chance(40) ? Double(r.int(8...40)) : nil))
        }
        if !d.salaryChanges.isEmpty { coverage.withWageChange += 1 }
        if d.work.periodBasis == .previous { coverage.previousPeriod += 1 }
        scenario.data = d
        coverage.datasets += 1
        let shifts = d.work.snapshot?.shifts ?? []
        for shift in shifts where cal.component(.hour, from: shift.start) * 60 + cal.component(.minute, from: shift.start) + shift.durationMinutes > 24 * 60 {
            coverage.nightShifts += 1
        }

        for month in scenario.months {
            coverage.months += 1
            let tag = "zaadwaarde \(seed) \(month.key)"
            let ledger = d.monthLedger(month, asOf: scenario.today)
            f.ok(ledger.allReconciles, "\(tag): het dagboek sluit niet (bank \(ledger.bankReconciles), potten \(ledger.potsReconciles), overzicht \(ledger.overviewReconciles))")
            let plan = d.plan(for: month)
            let payouts = d.salaryPayouts(in: month, plan: plan)
            f.eq(CentsMath.sum(payouts.map { $0.cents }), d.salaryCents(in: month, plan: plan), "\(tag): som van de uitbetalingen en het salaris van de maand")
            f.ok(d.salaryCents(in: month, plan: plan) >= 0, "\(tag): negatief salaris")
            f.eq(d.scheduledSalary(in: month) >= 0, true, "\(tag): negatief schemasalaris")
            let hasOverride = plan.salaryOverride != nil || plan.hoursOverride != nil
            if plan.hoursOverride != nil, plan.salaryOverride == nil, month >= d.startMonth { coverage.ownHoursMonths += 1 }
            let events = ledger.days.flatMap { $0.events }.filter { $0.kind == .salary }

            for payout in payouts where !hasOverride {
                let day = CalendarDay(month: month, day: payout.day)
                guard let report = d.workReport(forPayoutOn: day, asOf: scenario.today) else {
                    f.ok(false, "\(tag) dag \(payout.day): geen rapport")
                    continue
                }
                let ref = referenceAgendaPayout(d, payoutDay: day)
                f.eq(payout.cents, ref.cents, "\(tag) dag \(payout.day): uitbetaling tegenover de onafhankelijke berekening")
                f.eq(report.amountCents, payout.cents, "\(tag) dag \(payout.day): rapport tegenover uitbetaling")
                f.eq(d.workPayoutCents(on: day), payout.cents, "\(tag) dag \(payout.day): workPayoutCents")
                f.eq(report.period.lowerBound, ref.firstDay, "\(tag) dag \(payout.day): begin van de periode")
                f.eq(report.period.upperBound, ref.lastDay, "\(tag) dag \(payout.day): einde van de periode")
                f.eq(report.agendaMinutes, ref.agendaMinutes, "\(tag) dag \(payout.day): minuten uit de agenda")
                f.eq(report.expectedMinutes, ref.expectedMinutes, "\(tag) dag \(payout.day): verwachte minuten")
                f.eq(report.breakMinutes, ref.breakMinutes, "\(tag) dag \(payout.day): pauzeminuten")
                f.eq(report.paidMinutes, report.workedMinutes + report.plannedMinutes + report.expectedMinutes, "\(tag): minuten tellen op")
                f.eq(report.byFactor.reduce(0) { $0 + $1.minutes }, report.agendaMinutes, "\(tag) dag \(payout.day): minuten per factor")
                if !ref.isAllExpected {
                    f.eq(report.byFactor.reduce(0) { $0 + $1.factor * $1.minutes } + report.expectedMinutes * 100,
                         ref.weighted100, "\(tag) dag \(payout.day): gewogen minuten")
                } else {
                    f.ok(report.byFactor.isEmpty && report.agendaMinutes == 0, "\(tag) dag \(payout.day): een periode voorbij de agenda heeft geen uren per factor")
                }
                f.eq(report.shiftCount, ref.shiftCount, "\(tag) dag \(payout.day): aantal diensten")
                f.eq(payout.hours, report.payoutHours, "\(tag) dag \(payout.day): uren van de uitbetaling")
                f.eq(report.isAllExpected, ref.agendaMinutes == 0 && ref.shiftCount == 0 && ref.expectedMinutes > 0,
                     "\(tag) dag \(payout.day): helemaal verwacht")
                if ref.isAllExpected {
                    // Voorbij wat de agenda weet is het bedrag precies het handmatige bedrag van de maand van de uitbetaling.
                    f.eq(report.amountCents, CentsMath.int(d.salarySettings(forPayoutOn: day).payoutAmount()), "\(tag) dag \(payout.day): handmatig bedrag")
                }
                // Het bedrag hangt nooit van de klok af, alleen "gewerkt" en "gepland".
                let early = d.workReport(forPayoutOn: day, asOf: Date(timeIntervalSince1970: 0))
                let late = d.workReport(forPayoutOn: day, asOf: Date(timeIntervalSince1970: 4_000_000_000))
                f.eq(early?.amountCents, report.amountCents, "\(tag): bedrag zonder klok")
                f.eq(late?.amountCents, report.amountCents, "\(tag): bedrag zonder klok, ver in de toekomst")
                f.eq(early?.workedMinutes, 0, "\(tag): niets gewerkt in 1970")
                f.eq(late?.plannedMinutes, 0, "\(tag): niets gepland in 2096")
                // De gebeurtenis van de uitbetaling zegt hoeveel uren.
                if payout.cents != 0 {
                    let event = events.first { $0.day == payout.day }
                    f.eq(event?.detail, payout.hours?.detailText, "\(tag) dag \(payout.day): uitleg bij de salarisgebeurtenis")
                }
                if ref.isAllExpected { coverage.allExpected += 1 }
                else {
                    coverage.reportsWithAgenda += 1
                    if ref.expectedMinutes > 0 { coverage.mixed += 1 }
                }
                if report.byFactor.contains(where: { $0.factor != 100 && $0.minutes > 0 }) { coverage.surcharge += 1 }
                coverage.breakMinutes += report.breakMinutes
            }
            // Een maand met eigen salaris of eigen uren heeft geen uren uit de agenda in zijn uitbetalingen.
            if hasOverride { for payout in payouts { f.ok(payout.hours == nil, "\(tag): uren bij een eigen salaris of eigen uren") } }
        }
    }
}
