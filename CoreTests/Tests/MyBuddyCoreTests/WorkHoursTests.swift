import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van de werkuren uit de agenda in de rekenmotor (App/Core/WorkHours.swift en de koppeling in SalarySchedule.swift): de periode van
/// een uitbetaling, de uren per kalenderdag met toeslag en pauze, het bedrag dat eenmaal op hele centen wordt afgerond, de terugval op de
/// handmatige uren voor wat de agenda niet kent en de overschrijvingen van een maand (docs/work/plan.md par. 3.2). Een onafhankelijke
/// berekening per minuut met `Calendar` (`referencePerMinute`) legt zich naast de dagtotalen.
final class WorkHoursTests: XCTestCase {
    private let cal = YearMonth.calendar
    private let oct = YearMonth(year: 2026, month: 10)
    private let nov = YearMonth(year: 2026, month: 11)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date { engDate(cal, y, m, d, h, min) }
    private func shift(_ y: Int, _ m: Int, _ d: Int, from: Int, to: Int) -> WorkShift { engShift(at(y, m, d, from), at(y, m, d, to)) }

    /// Uurloon 15 euro, 24 uur per week, salaris op de 25e, vanaf oktober 2026, uren uit de agenda met de deze-periode-regel.
    private func hourlyData(rate: Double = 15, hours: Double = 24, from start: YearMonth? = nil) -> FinanceData {
        var d = FinanceData(startMonth: start ?? oct)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: rate, hoursPerWeek: hours, payDay: 25)
        d.work.hoursSource = .calendar
        return d
    }

    /// Tien diensten van acht uur (09:00 tot 17:00) op werkdagen in oktober 2026 en een zondagsdienst van vier uur; de agenda is bekend
    /// tot en met 31 oktober.
    private func octoberShifts() -> [WorkShift] {
        var shifts: [WorkShift] = [1, 2, 5, 6, 7, 8, 9, 12, 13, 14].map { shift(2026, 10, $0, from: 9, to: 17) }
        shifts.append(shift(2026, 10, 4, from: 10, to: 14))
        return shifts
    }

    private func withOctober(_ d: FinanceData = FinanceData(startMonth: YearMonth(year: 2026, month: 10))) -> FinanceData {
        var e = d
        if e.salary.mode != .hourly { e = hourlyData() }
        e.work.snapshot = engSnapshot(octoberShifts(), fetched: day(2026, 10, 31))
        return e
    }

    // MARK: De periode van een uitbetaling

    func testMonthlyPeriodsAreTheMonthOfThePayoutOrTheMonthBefore() {
        let salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 15, hoursPerWeek: 24, payDay: 25)
        let payout = day(2026, 11, 25)
        let current = WorkPeriods.period(forPayoutOn: payout, salary: salary, basis: .current)
        XCTAssertEqual(current, day(2026, 11, 1).dayNumber...day(2026, 11, 30).dayNumber)
        let previous = WorkPeriods.period(forPayoutOn: payout, salary: salary, basis: .previous)
        XCTAssertEqual(previous, day(2026, 10, 1).dayNumber...day(2026, 10, 31).dayNumber)
        let january = WorkPeriods.period(forPayoutOn: day(2027, 1, 25), salary: salary, basis: .previous)
        XCTAssertEqual(january, day(2026, 12, 1).dayNumber...day(2026, 12, 31).dayNumber, "over de jaargrens")
        let february = WorkPeriods.period(forPayoutOn: day(2028, 2, 29), salary: salary, basis: .current)
        XCTAssertEqual(february.count, 29, "schrikkeljaar")
    }

    func testPeriodsEveryNWeeksEndOnThePayoutDayOrOneCycleBefore() {
        var salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 20, payDay: 25)
        salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 10, 23))
        let current = WorkPeriods.period(forPayoutOn: day(2026, 10, 23), salary: salary, basis: .current)
        XCTAssertEqual(current.count, 28)
        XCTAssertEqual(current.upperBound, day(2026, 10, 23).dayNumber, "de periode eindigt op de uitbetaaldag")
        XCTAssertEqual(current.lowerBound, day(2026, 9, 26).dayNumber)
        let previous = WorkPeriods.period(forPayoutOn: day(2026, 10, 23), salary: salary, basis: .previous)
        XCTAssertEqual(previous.count, 28)
        XCTAssertEqual(previous.upperBound, day(2026, 9, 25).dayNumber, "de periode daarvoor")
        XCTAssertEqual(previous.upperBound + 1, current.lowerBound, "de perioden sluiten op elkaar aan")
    }

    func testPeriodsEveryNDaysUseExactlyNDays() {
        var salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 20, payDay: 25)
        salary.setSchedule(.days, interval: 10, anchor: day(2026, 10, 1))
        let current = WorkPeriods.period(forPayoutOn: day(2026, 10, 21), salary: salary, basis: .current)
        XCTAssertEqual(current, day(2026, 10, 12).dayNumber...day(2026, 10, 21).dayNumber)
        let previous = WorkPeriods.period(forPayoutOn: day(2026, 10, 21), salary: salary, basis: .previous)
        XCTAssertEqual(previous, day(2026, 10, 2).dayNumber...day(2026, 10, 11).dayNumber)
        salary.setSchedule(.days, interval: 1, anchor: day(2026, 10, 1))
        XCTAssertEqual(WorkPeriods.period(forPayoutOn: day(2026, 10, 21), salary: salary, basis: .current).count, 1, "elke dag: één dag")
    }

    // MARK: Het bedrag

    func testAMonthFromTheAgendaWithSurchargesAndBreaks() throws {
        var d = withOctober()
        let manual = (15 * 24 * 52 / 12.0).cents
        XCTAssertEqual(manual, 1_560)
        // Tien diensten van acht uur met een half uur pauze (75 uur) en vier uur op zondag keer 1,5 (6 gewogen uur): 81 gewogen uur.
        XCTAssertEqual(d.salaryAmount(in: oct), 1_215, "81 gewogen uur keer 15 euro")
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 10, 25), asOf: at(2026, 10, 20, 12)))
        XCTAssertEqual(report.workedMinutes, 75 * 60 + 4 * 60, "alles ligt voor 20 oktober")
        XCTAssertEqual(report.plannedMinutes, 0)
        XCTAssertEqual(report.expectedMinutes, 0, "de agenda is bekend tot en met 31 oktober")
        XCTAssertEqual(report.byFactor, [WorkHoursReport.FactorMinutes(factor: 100, minutes: 4_500),
                                         WorkHoursReport.FactorMinutes(factor: 150, minutes: 240)])
        XCTAssertEqual(report.shiftCount, 11)
        XCTAssertEqual(report.breakMinutes, 300, "tien keer een half uur")
        XCTAssertEqual(report.amountCents, 121_500)
        XCTAssertEqual(report.period, day(2026, 10, 1).dayNumber...day(2026, 10, 31).dayNumber)
        XCTAssertFalse(report.isAllExpected)
        XCTAssertEqual(report.paidHours, 79)
        // De uitbetaling is precies het bedrag van het rapport, overal hetzelfde.
        let plan = d.plan(for: oct)
        XCTAssertEqual(d.salaryPayouts(in: oct, plan: plan).map { $0.cents }, [121_500])
        XCTAssertEqual(d.salaryCents(in: oct, plan: plan), 121_500)
        XCTAssertEqual(d.monthFigures(oct).income, 121_500)
        XCTAssertEqual(d.workPayoutCents(on: day(2026, 10, 25)), 121_500)
        // Zonder de bron "agenda" rekent alles weer met de uren per week.
        d.work.hoursSource = .manual
        XCTAssertEqual(d.salaryAmount(in: oct), manual)
        XCTAssertNil(d.workReport(forPayoutOn: day(2026, 10, 25)))
    }

    func testTheAmountIsRoundedOnceOnTheTotal() {
        XCTAssertEqual(SalarySettings.exactPayCents(rate: 14.35, weightedMinutes100: 510 * 150), 18_296, "14,35 keer 8,5 uur keer 1,5 is 182,9625")
        XCTAssertEqual(SalarySettings.exactPayCents(rate: 55.94, weightedMinutes100: 645 * 3 * 100), 180_407, "55,94 keer 10,75 keer 3 is 1804,065: half omhoog")
        XCTAssertEqual(SalarySettings.exactPayCents(rate: 10, weightedMinutes100: 3_000), 500)
        XCTAssertEqual(SalarySettings.exactPayCents(rate: 10, weightedMinutes100: 0), 0)
        XCTAssertEqual(SalarySettings.exactPayCents(rate: 0, weightedMinutes100: 123_456), 0)
        XCTAssertEqual(SalarySettings.exactPayCents(rate: 20, weightedMinutes100: 6_000), 2_000, "een uur")
        // Een dienst op zondag: 9 uur min een half uur pauze, keer 1,5 tegen 14,35 per uur.
        var d = hourlyData(rate: 14.35)
        d.work.snapshot = engSnapshot([shift(2026, 11, 1, from: 9, to: 18)], fetched: day(2026, 11, 30))
        XCTAssertEqual(d.workPayoutCents(on: day(2026, 11, 25)), 18_296)
        XCTAssertEqual(d.salaryAmount(in: nov), 182.96)
    }

    func testRoundingOnTheTotalDiffersFromRoundingEveryShift() {
        // Drie diensten van een half uur tegen 10,01 per uur: elke dienst is 5,005 (afgerond 5,01, samen 15,03), maar samen is het 15,015
        // en dat wordt eenmaal afgerond: 15,02.
        var d = hourlyData(rate: 10.01)
        d.work.rules.breakRules = []
        d.work.snapshot = engSnapshot([2, 3, 4].map { engShift(at(2026, 11, $0, 12), at(2026, 11, $0, 12, 30)) }, fetched: day(2026, 11, 30))
        XCTAssertEqual(d.workPayoutCents(on: day(2026, 11, 25)), 1_502)
        // Een uur van 40,75 uur tegen 55,94 per uur is 2 279,555: half omhoog.
        var e = hourlyData(rate: 55.94)
        e.work.rules.breakRules = []
        e.work.snapshot = engSnapshot([2, 3, 4].map { shift(2026, 11, $0, from: 8, to: 18) } +
                                      [engShift(at(2026, 11, 5, 8), at(2026, 11, 5, 18, 45))], fetched: day(2026, 11, 30))
        XCTAssertEqual(e.workPayoutCents(on: day(2026, 11, 25)), 227_956)
    }

    // MARK: Wat de agenda niet kent

    func testWithoutAnySnapshotTheAmountIsExactlyTheManualAmount() throws {
        var d = hourlyData(rate: 14.35, hours: 32)
        let monthlyManual = d.salary.payoutAmount()
        XCTAssertEqual(d.salaryAmount(in: nov), monthlyManual)
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(report.expectedMinutes, Int((d.salary.hoursPerCycle * 60).rounded()))
        XCTAssertTrue(report.isAllExpected)
        XCTAssertEqual(report.agendaMinutes, 0)
        XCTAssertEqual(report.byFactor, [])
        for (schedule, interval) in [(SalarySchedule.weeks, 4), (.weeks, 1), (.days, 10), (.days, 31)] {
            d.salary.setSchedule(schedule, interval: interval, anchor: day(2026, 10, 2))
            for month in [oct, nov, YearMonth(year: 2026, month: 12)] {
                let plan = d.plan(for: month)
                let payouts = d.salaryPayouts(in: month, plan: plan)
                XCTAssertEqual(payouts.map { $0.cents }, payouts.map { _ in CentsMath.int(d.salary.payoutAmount()) }, "\(schedule) \(interval) \(month.key)")
            }
        }
    }

    func testDaysAfterTheLastShiftAndAfterTheFetchDayFallBackToTheAverage() throws {
        // Om de 4 weken op vrijdag 23 oktober (anker): de uitbetaling van 20 november betaalt 24 oktober t/m 20 november.
        var d = FinanceData(startMonth: oct)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 20, payDay: 25)
        d.salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 10, 23))
        d.work.hoursSource = .calendar
        d.work.snapshot = engSnapshot(octoberShifts(), fetched: day(2026, 10, 31))
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 20), asOf: at(2026, 11, 20, 12)))
        XCTAssertEqual(report.period.count, 28)
        XCTAssertEqual(report.expectedMinutes, 3_429, "20 van de 28 dagen zijn verwacht: 80 uur keer 20/28")
        XCTAssertEqual(report.agendaMinutes, 0, "24 tot en met 31 oktober hebben geen diensten")
        XCTAssertEqual(report.amountCents, 114_300, "3429 minuten tegen 20 euro")
        XCTAssertEqual(d.salaryPayDays(in: nov), [20])
        XCTAssertEqual(d.salaryPayoutCents(in: nov, plan: d.plan(for: nov)).map { $0.cents }, [114_300])
        // Met een dienst in het bekende deel is het een mengsel: de uren uit de agenda plus het deel dat verwacht wordt.
        d.work.snapshot = engSnapshot(octoberShifts() + [shift(2026, 10, 26, from: 9, to: 17)], fetched: day(2026, 10, 31))
        let mixed = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 20), asOf: at(2026, 11, 20, 12)))
        XCTAssertEqual(mixed.agendaMinutes, 450)
        XCTAssertEqual(mixed.expectedMinutes, 3_429)
        XCTAssertEqual(mixed.amountCents, SalarySettings.exactPayCents(rate: 20, weightedMinutes100: (450 + 3_429) * 100))
        XCTAssertFalse(mixed.isAllExpected)
    }

    func testAPeriodEntirelyBeyondTheAgendaIsExactlyTheManualAmount() throws {
        var d = withOctober(hourlyData(rate: 14.35, hours: 33))
        // De agenda is bekend tot en met 31 oktober; december ligt er helemaal achter.
        let december = YearMonth(year: 2026, month: 12)
        XCTAssertEqual(d.salaryAmount(in: december), d.salary.payoutAmount())
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 12, 25)))
        XCTAssertTrue(report.isAllExpected)
        XCTAssertEqual(report.amountCents, CentsMath.int(d.salary.payoutAmount()))
        // De lengte van de periode maakt het niet uit: ook bij de vorige periode (november) is de agenda helemaal voorbij.
        d.work.periodBasis = .previous
        XCTAssertEqual(d.salaryAmount(in: december), d.salary.payoutAmount())
        // En de uitbetaling van 25 november betaalt dan oktober.
        XCTAssertEqual(d.workReport(forPayoutOn: day(2026, 11, 25))?.period, day(2026, 10, 1).dayNumber...day(2026, 10, 31).dayNumber)
    }

    func testAnEmptyButRefreshedCalendarGivesZeroHoursAndAnUnknownOneTheAverage() throws {
        var d = hourlyData()
        d.work.snapshot = engSnapshot([], fetched: day(2026, 10, 31))
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 10, 25)))
        XCTAssertEqual(report.paidMinutes, 0, "een ververste agenda zonder diensten: geen uren")
        XCTAssertEqual(report.amountCents, 0)
        XCTAssertFalse(report.isAllExpected)
        XCTAssertEqual(d.salaryAmount(in: oct), 0, "een maand zonder diensten krijgt geen salaris")
        // Een deel van de periode ligt voorbij de verversing: dat deel komt uit je gemiddelde.
        d.work.snapshot = engSnapshot([], fetched: day(2026, 11, 14))
        let half = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(half.expectedMinutes, Int((d.salary.hoursPerCycle * 60 * 16 / 30).rounded()), "16 van de 30 dagen")
        XCTAssertTrue(half.isAllExpected, "niets uit de agenda en geen enkele dienst")
    }

    // MARK: Overschrijvingen van een maand

    func testOwnHoursAndOwnSalaryOfAMonthGoBeforeTheAgenda() {
        var d = withOctober()
        XCTAssertEqual(d.salaryAmount(in: oct), 1_215)
        d.editPlan(oct) { $0.hoursOverride = 100 }
        XCTAssertEqual(d.salaryAmount(in: oct), 1_500, "eigen uren rekenen uren keer uurloon, zonder toeslagen")
        XCTAssertEqual(d.salaryHours(in: oct), 100)
        XCTAssertEqual(d.scheduledSalary(in: oct), 1_215, "het schema blijft de agenda")
        d.editPlan(oct) { $0.hoursOverride = nil; $0.salaryOverride = 999 }
        XCTAssertEqual(d.salaryAmount(in: oct), 999, "een eigen salaris gaat voor")
        XCTAssertEqual(d.dayEvents(in: oct).filter { $0.kind == .salary }.map { $0.detail }, [nil], "geen uren uit de agenda bij een eigen salaris")
        d.editPlan(oct) { $0.salaryOverride = nil }
        XCTAssertEqual(d.salaryAmount(in: oct), 1_215, "zonder overschrijving weer de agenda")
    }

    func testAFixedSalaryIgnoresTheAgenda() {
        var d = withOctober()
        d.salary.mode = .fixed
        d.salary.fixedMonthly = 1_000
        XCTAssertFalse(d.usesCalendarHours)
        XCTAssertEqual(d.salaryAmount(in: oct), 1_000)
        XCTAssertNil(d.workReport(forPayoutOn: day(2026, 10, 25)))
        XCTAssertEqual(d.workPayoutCents(on: day(2026, 10, 25)), 0)
        XCTAssertEqual(d.scheduledSalary(in: oct), 1_000)
        XCTAssertEqual(d.dayEvents(in: oct).filter { $0.kind == .salary }.map { $0.detail }, [nil])
    }

    func testUsesCalendarHoursNeedsAnHourlyWageAndTheCalendarSource() {
        var d = FinanceData(startMonth: oct)
        XCTAssertFalse(d.usesCalendarHours)
        d.work.hoursSource = .calendar
        XCTAssertFalse(d.usesCalendarHours, "een vast salaris")
        d.salary.mode = .hourly
        XCTAssertTrue(d.usesCalendarHours)
        d.work.hoursSource = .manual
        XCTAssertFalse(d.usesCalendarHours, "de bron is handmatig")
    }

    func testSalaryHoursAndScheduledSalaryFollowTheAgenda() {
        let d = withOctober()
        XCTAssertEqual(d.salaryHours(in: oct), 79, "de betaalde uren van oktober")
        XCTAssertEqual(d.scheduledSalary(in: oct), 1_215)
        XCTAssertEqual(d.salaryHours(in: nov), d.salary.defaultMonthlyHours, "november ligt voorbij de agenda: de uren van het schema")
        XCTAssertEqual(d.scheduledSalary(in: nov), d.salary.payoutAmount())
        XCTAssertEqual(d.salaryHours(in: YearMonth(year: 2026, month: 9)), 0, "vóór de startmaand")
    }

    func testEstimatesKeepUsingTheManualHours() {
        var d = withOctober()
        d.salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 10, 2))
        let average = CentsMath.int(d.salary.averageMonthlyAmount())
        XCTAssertEqual(d.estimatedFigures(oct).income, average, "de gemiddelde maand rekent met de uren per week")
        XCTAssertEqual(d.estimatedIncomeBases(in: oct).salary, average)
        XCTAssertNotEqual(d.monthFigures(oct).income, average, "de maand zelf rekent met de agenda")
    }

    func testHoursBeforeTheStartDateStillCountForAPayoutAfterIt() {
        var d = withOctober()
        d.setStart(day(2026, 10, 20))
        // De uitbetaling van 25 oktober komt na de startdatum: ze betaalt alle uren van oktober, ook die van vóór 20 oktober.
        XCTAssertEqual(d.salaryAmount(in: oct), 1_215)
        XCTAssertTrue(d.monthLedger(oct).allReconciles)
        d.setStart(day(2026, 10, 28))
        XCTAssertEqual(d.salaryAmount(in: oct), 0, "de uitbetaling valt vóór de startdatum: ze zit in je beginsaldo")
        XCTAssertEqual(d.workPayoutCents(on: day(2026, 10, 25)), 121_500, "de uren zelf veranderen niet")
    }

    // MARK: Gewerkt, gepland en de klok

    func testWorkedAndPlannedSplitAtTodayButNeverChangeTheAmount() throws {
        let d = withOctober()
        let payout = day(2026, 10, 25)
        let report = try XCTUnwrap(d.workReport(forPayoutOn: payout, asOf: at(2026, 10, 8, 12)))
        XCTAssertEqual(report.workedMinutes, 6 * 450 + 240, "tot en met 8 oktober")
        XCTAssertEqual(report.plannedMinutes, 4 * 450, "9, 12, 13 en 14 oktober")
        XCTAssertEqual(report.agendaMinutes, 4_740)
        for today in [at(1970, 1, 1), at(2026, 10, 1), at(2026, 10, 14, 23), at(2026, 10, 15), at(2099, 1, 1)] {
            let other = try XCTUnwrap(d.workReport(forPayoutOn: payout, asOf: today))
            XCTAssertEqual(other.amountCents, report.amountCents, "het bedrag hangt niet van de klok af")
            XCTAssertEqual(other.agendaMinutes, report.agendaMinutes)
            XCTAssertEqual(other.workedMinutes + other.plannedMinutes, 4_740)
        }
        let before = try XCTUnwrap(d.workReport(forPayoutOn: payout, asOf: at(2026, 9, 1)))
        XCTAssertEqual(before.workedMinutes, 0)
        XCTAssertEqual(before.plannedMinutes, 4_740)
    }

    // MARK: Nacht, zomertijd en een onafhankelijke telling

    func testANightShiftGetsTheFactorOfEachDayAndASharedBreak() throws {
        var d = hourlyData(rate: 10)
        // Zaterdag 7 november 22:00 tot zondag 8 november 06:00: 8 uur, 30 minuten pauze verdeeld over 2 en 6 uur.
        d.work.snapshot = engSnapshot([engShift(at(2026, 11, 7, 22), at(2026, 11, 8, 6))], fetched: day(2026, 11, 30))
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(report.breakMinutes, 30)
        XCTAssertEqual(report.agendaMinutes, 450)
        XCTAssertEqual(report.byFactor, [WorkHoursReport.FactorMinutes(factor: 100, minutes: 112), WorkHoursReport.FactorMinutes(factor: 150, minutes: 338)],
                       "zaterdag 120 min min 8 pauze, zondag 360 min min 22 pauze: bij gelijke rest krijgt de eerste dag de extra minuut")
        XCTAssertEqual(report.shiftCount, 1, "een dienst over middernacht is een dienst")
        XCTAssertEqual(report.amountCents, SalarySettings.exactPayCents(rate: 10, weightedMinutes100: 112 * 100 + 338 * 150))
    }

    func testTheLedgerOfADaylightSavingNightHasNineElapsedHours() throws {
        let amsterdam = try XCTUnwrap(engAmsterdamCalendar(), "tijdzone Europe/Amsterdam ontbreekt")
        let night = engShift(engDate(amsterdam, 2025, 10, 25, 22), engDate(amsterdam, 2025, 10, 26, 6))
        let ledger = WorkLedger(shifts: [night], rules: WorkRules(), calendar: amsterdam)
        let saturday = ledger.days[day(2025, 10, 25).dayNumber]
        let sunday = ledger.days[day(2025, 10, 26).dayNumber]
        XCTAssertEqual(saturday?.paidMinutes, 113, "120 minuten min 7 pauze")
        XCTAssertEqual(sunday?.paidMinutes, 397, "420 minuten min 23 pauze")
        XCTAssertEqual((saturday?.breakMinutes ?? 0) + (sunday?.breakMinutes ?? 0), 30)
        XCTAssertEqual(saturday?.weighted100, 113 * 100)
        XCTAssertEqual(sunday?.weighted100, 397 * 150, "de zondag heeft factor 1,5")
        XCTAssertEqual(ledger.lastShiftDay, day(2025, 10, 26).dayNumber)
        XCTAssertEqual(ledger.total(day(2025, 10, 25).dayNumber...day(2025, 10, 26).dayNumber).paidMinutes, 510)
    }

    func testTheLedgerAgreesWithAnIndependentCountPerMinute() throws {
        let amsterdam = try XCTUnwrap(engAmsterdamCalendar(), "tijdzone Europe/Amsterdam ontbreekt")
        var rules = WorkRules()
        rules.combine = .add
        rules.payRules.append(PayRule(kind: .weekday(7), factor: 1.25))
        rules.breakRules.append(BreakRule(fromHours: 8, minutes: 45))
        let shifts = [
            engShift(engDate(amsterdam, 2025, 10, 25, 22), engDate(amsterdam, 2025, 10, 26, 6)),    // einde zomertijd, zaterdag naar zondag
            engShift(engDate(amsterdam, 2026, 3, 28, 20), engDate(amsterdam, 2026, 3, 29, 9)),      // begin zomertijd, 13 uur
            engShift(engDate(amsterdam, 2026, 12, 24, 23), engDate(amsterdam, 2026, 12, 26, 1)),    // kerst, twee middernachten
            engShift(engDate(amsterdam, 2026, 4, 5, 8, 15), engDate(amsterdam, 2026, 4, 5, 13, 40)), // Eerste Paasdag, net onder 5,5 uur
            engShift(engDate(amsterdam, 2026, 5, 2, 7), engDate(amsterdam, 2026, 5, 2, 12, 30))      // zaterdag, precies 5,5 uur
        ]
        let ledger = WorkLedger(shifts: shifts, rules: rules, calendar: amsterdam)
        let reference = referencePerMinute(shifts, rules: rules, calendar: amsterdam)
        XCTAssertGreaterThan(reference.count, 8)
        var seen = 0
        for (key, expected) in reference {
            let target = day(key / 10_000, key / 100 % 100, key % 100)
            let actual = ledger.days[target.dayNumber]
            XCTAssertEqual(actual?.paidMinutes, expected.paid, "betaald op \(target.key)")
            XCTAssertEqual(actual?.breakMinutes, expected.breaks, "pauze op \(target.key)")
            XCTAssertEqual(actual?.weighted100, expected.weighted, "gewogen op \(target.key)")
            seen += 1
        }
        XCTAssertEqual(ledger.days.count, seen, "geen dag te veel")
        // Het totaal aan betaalde minuten: de verstreken tijd min de pauzes.
        let elapsed = shifts.reduce(0) { $0 + $1.durationMinutes }
        let paid = ledger.days.values.reduce(0) { $0 + $1.paidMinutes }
        let breaks = ledger.days.values.reduce(0) { $0 + $1.breakMinutes }
        XCTAssertEqual(paid + breaks, elapsed)
    }

    // MARK: Uitleg bij het salaris

    func testTheSalaryEventSaysWhereTheHoursCameFrom() throws {
        var d = withOctober()
        let events = d.dayEvents(in: oct).filter { $0.kind == .salary }
        XCTAssertEqual(events.map { $0.detail }, ["uit agenda: 79 uur"])
        XCTAssertEqual(events.first?.bankAmount, 1_215)
        // Helemaal verwacht: november ligt voorbij de agenda.
        let november = d.dayEvents(in: nov).filter { $0.kind == .salary }
        XCTAssertEqual(november.map { $0.detail }, ["verwacht uit je gemiddelde: 104 uur"])
        // Gemengd: de agenda is bekend tot half november.
        d.work.snapshot = engSnapshot(octoberShifts() + [shift(2026, 11, 2, from: 9, to: 17)], fetched: day(2026, 11, 15))
        let mixed = try XCTUnwrap(d.dayEvents(in: nov).first { $0.kind == .salary })
        XCTAssertEqual(mixed.detail, "uit agenda: 7,5 uur, plus 52 uur uit je gemiddelde")
        // Zonder uren uit de agenda geen uitleg.
        d.work.hoursSource = .manual
        XCTAssertEqual(d.dayEvents(in: oct).filter { $0.kind == .salary }.map { $0.detail }, [nil])
        XCTAssertNil(d.salaryPayouts(in: oct, plan: d.plan(for: oct)).first?.hours)
        // Ander gebeurtenissen hebben nooit een uitleg.
        d.work.hoursSource = .calendar
        d.addRecurringLine(MoneyLine(name: "Huur", amount: 500, isRecurring: true), kind: .expense, in: oct)
        XCTAssertEqual(d.dayEvents(in: oct).filter { $0.kind != .salary }.compactMap { $0.detail }, [])
    }

    func testPayoutPartsCarryTheHoursOnlyForAgendaPayouts() {
        let d = withOctober()
        let parts = d.salaryPayoutParts(in: oct, plan: d.plan(for: oct))
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.cents, 121_500)
        XCTAssertEqual(parts.first?.hours, PayoutHours(paidMinutes: 4_740, expectedMinutes: 0))
        XCTAssertEqual(d.salaryPayoutCents(in: oct, plan: d.plan(for: oct)).map { $0.cents }, [121_500])
        var manual = d
        manual.work.hoursSource = .manual
        XCTAssertNil(manual.salaryPayoutParts(in: oct, plan: manual.plan(for: oct)).first?.hours)
    }

    // MARK: Gemiddelde uit de agenda

    func testTheAverageHoursPerWeekOfTheLastFullWeeks() throws {
        var d = hourlyData()
        let today = at(2026, 11, 4, 12)   // woensdag 4 november: de laatste volle week eindigt zondag 1 november
        XCTAssertEqual(CalendarDay(date: today).weekday, 4)
        // Drie diensten per week (maandag t/m woensdag, 9 tot 17 uur, 7,5 uur betaald): 22,5 uur per week, ook in de lopende week.
        var shifts: [WorkShift] = []
        var monday = day(2026, 7, 6)
        while monday <= day(2026, 11, 2) {
            for offset in 0..<3 { let c = monday.adding(days: offset); shifts.append(shift(c.year, c.month, c.day, from: 9, to: 17)) }
            monday = monday.adding(days: 7)
        }
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 11, 4), from: day(2026, 7, 1))
        XCTAssertEqual(d.averageAgendaHoursPerWeek(weeks: 12, asOf: today), 22.5)
        XCTAssertEqual(d.averageAgendaHoursPerWeek(asOf: today), 22.5, "standaard 12 weken")
        XCTAssertEqual(d.averageAgendaHoursPerWeek(weeks: 1, asOf: today), 22.5)
        // Een drukke week buiten de laatste 12 weken (de week van 3 augustus; de 12 weken beginnen op 10 augustus) telt niet mee.
        let busy = (0..<5).map { shift(2026, 8, 3 + $0, from: 8, to: 20) }
        d.work.snapshot = engSnapshot(shifts + busy, fetched: day(2026, 11, 4), from: day(2026, 7, 1))
        XCTAssertEqual(d.averageAgendaHoursPerWeek(weeks: 12, asOf: today), 22.5)
        // Met 13 weken telt ze wel: 12 weken van 22,5 uur en één week van 57,5 uur (vijf diensten van 12 uur min een half uur pauze;
        // de diensten van maandag t/m woensdag zijn met die van 9 tot 17 uur samengevoegd).
        XCTAssertEqual(d.averageAgendaHoursPerWeek(weeks: 13, asOf: today), 25.2)
    }

    func testTheAverageUsesOnlyWhatTheCalendarKnowsAndIsNilWithoutAFullWeek() {
        var d = hourlyData()
        let today = at(2026, 11, 4, 12)
        XCTAssertNil(d.averageAgendaHoursPerWeek(asOf: today), "zonder gelezen agenda")
        let shifts = (0..<3).map { shift(2026, 10, 26 + $0, from: 9, to: 17) }   // alleen de week van 26 oktober
        // De agenda begint op 26 oktober: precies één volle week (26 oktober t/m 1 november).
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 11, 4), from: day(2026, 10, 26))
        XCTAssertEqual(d.averageAgendaHoursPerWeek(asOf: today), 22.5)
        // Begint de agenda midden in de week, dan telt die week niet: er is geen volle week.
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 11, 4), from: day(2026, 10, 28))
        XCTAssertNil(d.averageAgendaHoursPerWeek(asOf: today))
        // Over twee weken: 22,5 uur gedeeld door twee is 11,25 en wordt op 0,1 uur afgerond.
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 11, 1), from: day(2026, 10, 12))
        XCTAssertEqual(d.averageAgendaHoursPerWeek(weeks: 2, asOf: today), 11.3)
        // Is de agenda lang niet ververst (donderdag 29 oktober), dan telt alleen wat ze kent: de week tot en met zondag 25 oktober.
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 10, 29), from: day(2026, 10, 12))
        XCTAssertEqual(d.averageAgendaHoursPerWeek(weeks: 1, asOf: today), 0, "in die week stonden geen diensten")
        XCTAssertNil(d.averageAgendaHoursPerWeek(weeks: 0, asOf: today))
        XCTAssertNil(d.averageAgendaHoursPerWeek(weeks: -3, asOf: today))
    }

    // MARK: Tussenopslag

    func testTheLedgerCacheFollowsTheWorkSettingsPerCopy() {
        let d = withOctober()
        var e = d
        e.work.rules.payRules[0].factor = 3
        let sunday = day(2026, 10, 4).dayNumber
        XCTAssertEqual(d.workLedger.days[sunday]?.weighted100, 240 * 150, "het origineel houdt zijn uren")
        XCTAssertEqual(e.workLedger.days[sunday]?.weighted100, 240 * 300, "de kopie rekent met de nieuwe toeslag")
        XCTAssertEqual(d.workLedger.days[sunday]?.weighted100, 240 * 150)
        XCTAssertEqual(d.salaryAmount(in: oct), 1_215)
        XCTAssertGreaterThan(e.salaryAmount(in: oct), 1_215)
        // Een wijziging van het rooster in een kopie leegt alleen de tussenopslag van die kopie.
        var f = d
        f.work.snapshot = engSnapshot([], fetched: day(2026, 10, 31))
        XCTAssertEqual(f.salaryAmount(in: oct), 0)
        XCTAssertEqual(d.salaryAmount(in: oct), 1_215)
        // De tussenopslag telt niet mee bij gelijkheid.
        XCTAssertEqual(d, withOctober())
    }

    func testTheLedgerIsReadOnceForManyPayouts() {
        // Een jaar aan diensten en een salaris per week: alle uitbetalingen lezen dezelfde tussenopslag (geen opnieuw bouwen per vraag).
        var d = hourlyData()
        d.salary.setSchedule(.weeks, interval: 1, anchor: day(2026, 10, 2))
        var shifts: [WorkShift] = []
        var cursor = day(2026, 9, 1)
        while cursor < day(2027, 10, 1) {
            shifts.append(shift(cursor.year, cursor.month, cursor.day, from: 9, to: 17))
            cursor = cursor.adding(days: 2)
        }
        d.work.snapshot = engSnapshot(shifts, fetched: day(2027, 9, 30), from: day(2026, 8, 1))
        let started = Date()
        var total = 0
        for month in oct.range(count: 12) { total += d.salaryCents(in: month, plan: d.plan(for: month)) }
        XCTAssertGreaterThan(total, 0)
        if !MachineSpeed.skipsTiming { XCTAssertLessThan(Date().timeIntervalSince(started), MachineSpeed.limit(2.0), "een jaar aan uitbetalingen") }
    }
}
