import XCTest
@testable import MyBuddyCore

final class OverviewTests: XCTestCase {
    func testNetWorthAddsBankPotsAndInvestments() {
        var d = makeBaseData()
        _ = addBufferPot(&d) // 500 + 200 per maand
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 1000, date: day(oct2026, 1))
        d.addHolding(Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, expectedReturn: 0, annualCost: 0, startMonth: aug2026),
                     initialValue: 2000, now: day(oct2026, 2))
        let w = d.netWorth(at: oct2026, current: oct2026)
        XCTAssertEqual(w.bank, 1000, accuracy: 0.001)
        XCTAssertEqual(w.pots, 1100, accuracy: 0.001)
        XCTAssertEqual(w.investments, 2000, accuracy: 0.001)
        XCTAssertEqual(w.total, 4100, accuracy: 0.001)
        XCTAssertFalse(w.isProjected)
    }

    func testSeriesMarksProjectionAndTreatsMissingBankAsZero() {
        var d = makeBaseData()
        _ = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        let series = d.netWorthSeries(from: sep2026, count: 4, current: oct2026)
        XCTAssertEqual(series.count, 4)
        XCTAssertEqual(series.map(\.isProjected), [false, false, true, true])
        XCTAssertEqual(series[0].bank, 0)
        XCTAssertEqual(series[0].pots, 900, accuracy: 0.001) // 500 + aug + sep
    }

    func testEmptyStart() {
        var d = FinanceData(startMonth: aug2026)
        XCTAssertTrue(d.isEmptyStart)
        d.salary.fixedMonthly = 100
        XCTAssertFalse(d.isEmptyStart)
    }
}
