import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van het loon per maand samen met de uren uit de agenda (docs/work/plan2.md D6.2 en 2.6 regel 6): de hele uitbetaling rekent met het
/// loon van de maand waarin ze op je rekening komt, ook als de uren in de maand ervoor zijn gewerkt; wat de agenda niet kent valt terug op
/// de uren per week van die maand; eigen uren en een eigen salaris van een maand gaan voor.
final class WageCalendarTests: XCTestCase {
    private let cal = YearMonth.calendar
    private let oct = YearMonth(year: 2026, month: 10)
    private let nov = YearMonth(year: 2026, month: 11)
    private let dec = YearMonth(year: 2026, month: 12)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }
    private func shift(_ y: Int, _ m: Int, _ d: Int, from: Int, to: Int) -> WorkShift { engShift(engDate(cal, y, m, d, from), engDate(cal, y, m, d, to)) }

    /// Uurloon 20 euro (vanaf november 24), 24 uur per week, uren uit de agenda; twee werkdagen van acht uur in oktober en in november.
    private func data(basis: HoursPeriodBasis) -> FinanceData {
        var d = FinanceData(startMonth: oct)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 24, payDay: 25)
        d.work.hoursSource = .calendar
        d.work.periodBasis = basis
        d.work.rules.breakRules = []
        let shifts = [shift(2026, 10, 5, from: 9, to: 17), shift(2026, 10, 6, from: 9, to: 17),
                      shift(2026, 11, 2, from: 9, to: 17), shift(2026, 11, 3, from: 9, to: 17)]
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 12, 31))
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 24))
        return d
    }

    func testAPeriodThatCrossesTheMonthBoundaryUsesTheWageOfTheMonthOfThePayout() throws {
        // De vorige periode: de uitbetaling van 25 november betaalt de uren van oktober, tegen het uurloon van november.
        let previous = data(basis: .previous)
        let report = try XCTUnwrap(previous.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(report.period, day(2026, 10, 1).dayNumber...day(2026, 10, 31).dayNumber)
        XCTAssertEqual(report.agendaMinutes, 16 * 60, "twee werkdagen van acht uur in oktober")
        XCTAssertEqual(report.amountCents, 16 * 24 * 100, "16 uur tegen het uurloon van november")
        XCTAssertEqual(previous.salaryAmount(in: nov), 384)
        // De uitbetaling van 25 oktober betaalt september (niets) tegen het uurloon van oktober.
        XCTAssertEqual(previous.salaryAmount(in: oct), 0)
        // De deze periode: oktober betaalt oktober tegen het uurloon van oktober.
        let current = data(basis: .current)
        XCTAssertEqual(current.salaryAmount(in: oct), 320, "16 uur tegen 20 euro")
        XCTAssertEqual(current.salaryAmount(in: nov), 384, "16 uur tegen 24 euro")
    }

    func testACyclePeriodOverTheMonthBoundaryRatesTheWholePayoutAtTheMonthOfThePayout() throws {
        // Om de 4 weken vanaf 23 oktober: de uitbetaling van 20 november betaalt 24 oktober t/m 20 november, helemaal tegen het loon van november.
        var d = data(basis: .current)
        d.salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 10, 23))
        d.work.snapshot = engSnapshot([shift(2026, 10, 26, from: 9, to: 17), shift(2026, 11, 3, from: 9, to: 17)], fetched: day(2026, 12, 31))
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 20)))
        XCTAssertEqual(report.period.count, 28)
        XCTAssertEqual(report.period.lowerBound, day(2026, 10, 24).dayNumber)
        XCTAssertEqual(report.amountCents, 16 * 24 * 100, "één dienst in oktober en één in november, allebei tegen 24 euro")
        // De uitbetaling van 23 oktober eindigt in oktober en rekent met het loon van oktober.
        let october = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 10, 23)))
        XCTAssertEqual(october.amountCents, 0, "9 oktober tot 23 oktober: geen diensten")
        XCTAssertEqual(d.salarySettings(forPayoutOn: day(2026, 10, 23)).hourlyRate, 20)
        XCTAssertEqual(d.salarySettings(forPayoutOn: day(2026, 11, 20)).hourlyRate, 24)
    }

    func testAPayoutOnTheFirstOfAMonthRatesWithThatMonth() throws {
        // Om de 4 weken vanaf 4 oktober: 1 november is een uitbetaling. Ze betaalt 5 oktober t/m 1 november tegen het uurloon van november.
        var d = data(basis: .current)
        d.salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 10, 4))
        d.work.snapshot = engSnapshot([shift(2026, 10, 12, from: 9, to: 17)], fetched: day(2026, 12, 31))
        XCTAssertEqual(d.salaryPayDays(in: nov), [1, 29])
        let first = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 1)))
        XCTAssertEqual(first.period, day(2026, 10, 5).dayNumber...day(2026, 11, 1).dayNumber)
        XCTAssertEqual(first.amountCents, 8 * 24 * 100)
        XCTAssertEqual(d.salaryPayouts(in: nov, plan: d.plan(for: nov)).map { $0.cents }.first, 19_200)
        XCTAssertEqual(d.salaryPayouts(in: oct, plan: d.plan(for: oct)).map { $0.day }, [4], "de uitbetaling van 4 oktober hoort bij oktober")
        XCTAssertEqual(d.salarySettings(forPayoutOn: day(2026, 10, 4)).hourlyRate, 20)
    }

    func testOwnHoursCountWithTheWageOfThatMonthAndAnOwnSalaryStays() {
        var d = data(basis: .current)
        d.editPlan(nov) { $0.hoursOverride = 50 }
        XCTAssertEqual(d.salaryAmount(in: nov), 1_200, "50 uur tegen het uurloon van november")
        d.editPlan(oct) { $0.hoursOverride = 50 }
        XCTAssertEqual(d.salaryAmount(in: oct), 1_000, "50 uur tegen het uurloon van oktober")
        d.editPlan(nov) { $0.hoursOverride = nil; $0.salaryOverride = 777 }
        XCTAssertEqual(d.salaryAmount(in: nov), 777)
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 99))
        XCTAssertEqual(d.salaryAmount(in: nov), 777, "een eigen salaris verandert niet met het loon")
    }

    func testWhatTheAgendaDoesNotKnowFallsBackToTheHoursPerWeekOfThatMonth() throws {
        var d = data(basis: .current)
        d.work.snapshot = nil
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 24, hoursPerWeek: 30))
        // Zonder agenda is de uitbetaling precies het handmatige bedrag van de maand.
        XCTAssertEqual(d.salaryAmount(in: oct), d.salarySettings(in: oct).payoutAmount())
        XCTAssertEqual(d.salaryAmount(in: nov), d.salarySettings(in: nov).payoutAmount())
        XCTAssertEqual(d.salarySettings(in: nov).hoursPerWeek, 30)
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(report.expectedMinutes, Int((30.0 * 52 / 12 * 60).rounded()), "30 uur per week van november")
        // Met een agenda die halverwege november ophoudt: de laatste helft komt uit de uren van november.
        d.work.snapshot = engSnapshot([shift(2026, 11, 2, from: 9, to: 17)], fetched: day(2026, 11, 15))
        let mixed = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(mixed.agendaMinutes, 480)
        XCTAssertEqual(mixed.expectedMinutes, Int((30.0 * 52 / 12 * 60 * 15 / 30).rounded()))
        XCTAssertEqual(mixed.amountCents, SalarySettings.exactPayCents(rate: 24, weightedMinutes100: (480 + mixed.expectedMinutes) * 100))
    }

    func testTheAveragesForEstimatesFollowTheWageButStayOnTheHoursPerWeek() {
        var d = data(basis: .current)
        d.salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 10, 2))
        XCTAssertEqual(d.estimatedFigures(oct).income, CentsMath.int(d.salarySettings(in: oct).averageMonthlyAmount()))
        XCTAssertEqual(d.estimatedFigures(nov).income, CentsMath.int(d.salarySettings(in: nov).averageMonthlyAmount()))
        XCTAssertGreaterThan(d.estimatedFigures(nov).income, d.estimatedFigures(oct).income)
        XCTAssertNotEqual(d.estimatedFigures(oct).income, d.monthFigures(oct).income, "de maand zelf rekent met de agenda")
    }

    func testTheLedgerClosesWithTheAgendaAndWageChangesTogether() {
        for basis in HoursPeriodBasis.allCases {
            var d = data(basis: basis)
            d.addPot(Pot(name: "Spaar", monthlyContribution: 150, startMonth: oct), openingBalance: 100, now: engTime(oct, 12, hour: 12))
            d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 31, hoursPerWeek: 20))
            for month in oct.range(count: 5) {
                XCTAssertTrue(d.monthLedger(month, asOf: engTime(nov, 14, hour: 12)).allReconciles, "\(basis) \(month.key)")
            }
        }
    }
}
