import XCTest
@testable import MyBuddyCore

/// Verwachte waarden zijn onafhankelijk berekend in Python.
final class GrowthTests: XCTestCase {
    func testFutureValue() {
        XCTAssertEqual(Growth.futureValue(start: 1000, monthly: 100, annualReturn: 0.06, months: 12), 2292.65, accuracy: 0.01)
        XCTAssertEqual(Growth.futureValue(start: 0, monthly: 100, annualReturn: 0, months: 24), 2400, accuracy: 0.001)
        XCTAssertEqual(Growth.futureValue(start: 5000, monthly: 250, annualReturn: 0.05, months: 120), 46735.26, accuracy: 0.01)
    }

    func testFractionalMonthsGrowStartOnly() {
        XCTAssertEqual(Growth.futureValue(start: 1000, monthly: 0, annualReturn: 0.06, months: 6.5), 1032.0657, accuracy: 0.001)
    }

    func testNegativeHorizonIsTreatedAsZero() {
        XCTAssertEqual(Growth.futureValue(start: 1000, monthly: 100, annualReturn: 0.06, months: -3), 1000, accuracy: 0.001)
    }

    func testMonthsToReach() {
        XCTAssertEqual(Growth.monthsToReach(target: 10_000, start: 1000, monthly: 200, annualReturn: 0.06), 40)
        XCTAssertEqual(Growth.monthsToReach(target: 10_000, start: 1000, monthly: 200, annualReturn: 0), 45)
        XCTAssertEqual(Growth.monthsToReach(target: 10_000, start: 1000, monthly: 200, annualReturn: 0.06, stepUp: 0.03), 39)
        XCTAssertEqual(Growth.monthsToReach(target: 10_000, start: 1000, monthly: 200, annualReturn: 0.06, oneOff: 5000), 17)
    }

    func testMonthsToReachEdgeCases() {
        XCTAssertEqual(Growth.monthsToReach(target: 500, start: 1000, monthly: 0, annualReturn: 0), 0)
        XCTAssertNil(Growth.monthsToReach(target: 10_000, start: 0, monthly: 0, annualReturn: 0.05))
    }

    func testRequiredMonthly() {
        XCTAssertEqual(Growth.requiredMonthly(target: 10_000, start: 1000, annualReturn: 0.06, months: 24), 349.57, accuracy: 0.02)
        XCTAssertEqual(Growth.requiredMonthly(target: 12_000, start: 0, annualReturn: 0, months: 24), 500, accuracy: 0.001)
        XCTAssertEqual(Growth.requiredMonthly(target: 100, start: 1000, annualReturn: 0.06, months: 24), 0)
        XCTAssertEqual(Growth.requiredMonthly(target: 100, start: 0, annualReturn: 0.06, months: 0), 100)
    }

    func testRequiredMonthlyIsConsistentWithFutureValue() {
        let c = Growth.requiredMonthly(target: 25_000, start: 3000, annualReturn: 0.05, months: 60)
        let fv = Growth.futureValue(start: 3000, monthly: c, annualReturn: 0.05, months: 60)
        XCTAssertEqual(fv, 25_000, accuracy: 1)
    }

    func testCapitalNeeded() {
        XCTAssertEqual(Growth.capitalNeeded(monthlyAmount: 1100, withdrawalRate: 0.04), 330_000, accuracy: 0.01)
        XCTAssertEqual(Growth.capitalNeeded(monthlyAmount: 1100, withdrawalRate: 0), 0)
    }

    func testAnnuityCapital() {
        XCTAssertEqual(Growth.annuityCapital(monthlyAmount: 1000, years: 20, annualReturn: 0.03), 178_529.70, accuracy: 0.05)
        XCTAssertEqual(Growth.annuityCapital(monthlyAmount: 1000, years: 10, annualReturn: 0), 120_000, accuracy: 0.001)
    }

    func testInflation() {
        XCTAssertEqual(Growth.realReturn(nominal: 0.06, inflation: 0.02), 0.0392157, accuracy: 0.000001)
        XCTAssertEqual(Growth.deflate(10_000, years: 10, inflation: 0.02), 8203.48, accuracy: 0.01)
    }

    func testProjectionBreakdown() {
        let r = Growth.projection(start: 1000, monthly: 100, annualReturn: 0.06, months: 12, inflation: 0.02)
        XCTAssertEqual(r.total, 2292.65, accuracy: 0.01)
        XCTAssertEqual(r.contributed, 2200, accuracy: 0.001)
        XCTAssertEqual(r.growth, 92.65, accuracy: 0.01)
        XCTAssertEqual(r.real, 2247.70, accuracy: 0.01)
    }

    func testMonthlySeriesMatchesFutureValue() {
        let series = Growth.monthlySeries(start: 1000, monthly: 100, annualReturn: 0.06, months: 12)
        XCTAssertEqual(series.count, 13)
        XCTAssertEqual(series.first!, 1000, accuracy: 0.001)
        XCTAssertEqual(series.last!, 2292.65, accuracy: 0.01)
    }

    func testCurveUnits() {
        let years = Growth.curve(start: 1000, monthly: 0, annualReturn: 0, totalMonths: 24, unit: .years, steps: 4)
        XCTAssertEqual(years.count, 5)
        XCTAssertEqual(years.last!.t, 2, accuracy: 0.0001)
        let days = Growth.curve(start: 1000, monthly: 0, annualReturn: 0, totalMonths: 1, unit: .days, steps: 2)
        XCTAssertEqual(days.last!.t, 30.4375, accuracy: 0.0001)
    }

    func testHorizonUnits() {
        XCTAssertEqual(HorizonUnit.years.months(2), 24)
        XCTAssertEqual(HorizonUnit.months.months(5), 5)
        XCTAssertEqual(HorizonUnit.days.months(30.4375), 1, accuracy: 0.0001)
        XCTAssertEqual(HorizonUnit.weeks.months(52), 11.9589, accuracy: 0.001)
    }
}
