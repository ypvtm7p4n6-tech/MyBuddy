import XCTest
@testable import MyBuddyCore

final class InvestTests: XCTestCase {
    /// ETF met meetpunten in augustus en september en 100 inleg per maand.
    private func makeData(annualCost: Double = 0) -> (FinanceData, Holding) {
        var d = makeBaseData()
        let h = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                        expectedReturn: 0.06, annualCost: annualCost, monthlyContribution: 100, startMonth: aug2026)
        d.addHolding(h)
        d.addSnapshot(holdingID: h.id, value: 1000, invested: 900, date: day(aug2026, 15))
        d.addSnapshot(holdingID: h.id, value: 1100, invested: 1000, date: day(sep2026, 15))
        d.materialize(upTo: oct2026)
        return (d, d.holdings[0])
    }

    func testStateUsesLatestSnapshotPlusLaterDeposits() {
        let (d, h) = makeData()
        XCTAssertNil(d.holdingState(h, at: YearMonth(year: 2026, month: 7), current: oct2026))
        let aug = d.holdingState(h, at: aug2026, current: oct2026)
        XCTAssertEqual(aug?.value ?? 0, 1000, accuracy: 0.001)
        let sep = d.holdingState(h, at: sep2026, current: oct2026)
        XCTAssertEqual(sep?.value ?? 0, 1100, accuracy: 0.001)
        XCTAssertEqual(sep?.isProjected, false)
        let oct = d.holdingStateNow(h, current: oct2026)
        XCTAssertEqual(oct?.value ?? 0, 1200, accuracy: 0.001)
        XCTAssertEqual(oct?.invested ?? 0, 1100, accuracy: 0.001)
        XCTAssertEqual(oct?.gain ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(oct?.gainFraction ?? 0, 100.0 / 1100.0, accuracy: 0.0001)
    }

    func testFutureStateGrowsWithNetReturn() {
        let (d, h) = makeData()
        let dec = d.holdingState(h, at: YearMonth(year: 2026, month: 12), current: oct2026)
        XCTAssertEqual(dec?.isProjected, true)
        XCTAssertEqual(dec?.value ?? 0, 1412.20, accuracy: 0.02)
        XCTAssertEqual(dec?.invested ?? 0, 1300, accuracy: 0.001)

        let (d2, h2) = makeData(annualCost: 0.01)
        let dec2 = d2.holdingState(h2, at: YearMonth(year: 2026, month: 12), current: oct2026)
        XCTAssertEqual(dec2?.value ?? 0, 1410.21, accuracy: 0.02)
    }

    func testPortfolioSeries() {
        let (d, _) = makeData()
        let series = d.portfolioSeries(from: YearMonth(year: 2026, month: 7), count: 6, current: oct2026)
        // Juli heeft nog geen meetpunt en wordt overgeslagen.
        XCTAssertEqual(series.count, 5)
        XCTAssertEqual(series.first?.month, aug2026)
        XCTAssertEqual(series.map(\.isProjected), [false, false, false, true, true])
        XCTAssertEqual(d.portfolioValue(current: oct2026), 1200, accuracy: 0.001)
        XCTAssertEqual(d.portfolioInvested(current: oct2026), 1100, accuracy: 0.001)
        XCTAssertEqual(d.portfolioGain(current: oct2026), 100, accuracy: 0.001)
    }

    func testSameDaySnapshotIsReplaced() {
        var (d, h) = makeData()
        d.addSnapshot(holdingID: h.id, value: 1500, invested: 1000, date: day(oct2026, 3))
        d.addSnapshot(holdingID: h.id, value: 1600, invested: 1000, date: day(oct2026, 3))
        h = d.holdings[0]
        XCTAssertEqual(h.snapshots.count, 3)
        XCTAssertEqual(d.holdingValueNow(h, current: oct2026), 1600, accuracy: 0.001)
    }

    func testRecordPriceCreatesSnapshotForTrackedHolding() {
        var d = makeBaseData()
        let h = Holding(name: "VWCE", kind: .etf, ticker: "VWCE.DE", units: 10, investedTotal: 200,
                        expectedReturn: 0.06, annualCost: 0.002, monthlyContribution: 0, startMonth: aug2026)
        XCTAssertTrue(h.isTracked)
        d.addHolding(h)
        d.recordPrice(holdingID: h.id, price: 25, currency: "EUR", date: day(oct2026, 3))
        XCTAssertEqual(d.holdings[0].lastPrice, 25)
        XCTAssertEqual(d.holdings[0].snapshots.count, 1)
        XCTAssertEqual(d.holdings[0].snapshots[0].value, 250, accuracy: 0.001)
        XCTAssertEqual(d.holdings[0].snapshots[0].invested, 200, accuracy: 0.001)
        d.recordPrice(holdingID: h.id, price: 26, currency: "EUR", date: day(oct2026, 3))
        XCTAssertEqual(d.holdings[0].snapshots.count, 1)
        XCTAssertEqual(d.holdingValueNow(d.holdings[0], current: oct2026), 260, accuracy: 0.001)
    }

    func testUntrackedWithoutUnits() {
        let h = Holding(name: "Handmatig", kind: .bonds, ticker: "ABC", units: nil, startMonth: aug2026)
        XCTAssertFalse(h.isTracked)
        let blank = Holding(name: "Leeg", kind: .bonds, ticker: "  ", units: 5, startMonth: aug2026)
        XCTAssertFalse(blank.isTracked)
    }

    func testChangingUnitsAddsSnapshotAtLastPrice() {
        var d = makeBaseData()
        var h = Holding(name: "VWCE", kind: .etf, ticker: "VWCE.DE", units: 10, investedTotal: 200,
                        expectedReturn: 0.06, annualCost: 0.002, monthlyContribution: 0, startMonth: aug2026)
        d.addHolding(h)
        d.recordPrice(holdingID: h.id, price: 25, currency: "EUR", date: day(oct2026, 3))
        h = d.holdings[0]
        h.units = 12
        h.investedTotal = 260
        d.updateHolding(h, current: oct2026, now: day(oct2026, 20))
        XCTAssertEqual(d.holdings[0].snapshots.count, 2)
        XCTAssertEqual(d.holdingValueNow(d.holdings[0], current: oct2026), 300, accuracy: 0.001)
    }

    func testImportHistoryOnlyBeforeFirstSnapshot() {
        var d = makeBaseData()
        let h = Holding(name: "VWCE", kind: .etf, ticker: "VWCE.DE", units: 10, investedTotal: 200,
                        expectedReturn: 0.06, annualCost: 0.002, monthlyContribution: 0, startMonth: aug2026)
        d.addHolding(h)
        d.recordPrice(holdingID: h.id, price: 25, currency: "EUR", date: day(oct2026, 3))
        d.importHistory(holdingID: h.id, prices: [
            (date: day(aug2026, 10), price: 20),
            (date: day(sep2026, 10), price: 22),
            (date: day(oct2026, 20), price: 99) // na het eerste meetpunt: genegeerd
        ])
        XCTAssertEqual(d.holdings[0].snapshots.count, 3)
        XCTAssertEqual(d.holdings[0].snapshots.first?.value ?? 0, 200, accuracy: 0.001)
    }

    func testValueByKindAndWeightedReturn() {
        var d = makeBaseData()
        let a = Holding(name: "A", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0, startMonth: aug2026)
        let b = Holding(name: "B", kind: .bonds, ticker: nil, units: nil, expectedReturn: 0.02, annualCost: 0, startMonth: aug2026)
        d.addHolding(a, initialValue: 3000, now: day(sep2026, 1))
        d.addHolding(b, initialValue: 1000, now: day(sep2026, 1))
        let slices = d.valueByKind(current: oct2026)
        XCTAssertEqual(slices.map(\.kind), [.etf, .bonds])
        XCTAssertEqual(d.weightedNetReturn(current: oct2026), 0.05, accuracy: 0.0001)
        XCTAssertEqual(FinanceData(startMonth: aug2026).weightedNetReturn(current: oct2026), Growth.fallbackReturn)
    }

    func testDeleteHoldingRemovesAllocations() {
        var (d, h) = makeData()
        d.homeHoldingIDs = [h.id]
        d.deleteHolding(h.id)
        XCTAssertTrue(d.holdings.isEmpty)
        XCTAssertNil(d.months[oct2026.key]?.allocations[h.id.uuidString])
        XCTAssertEqual(d.homeHoldingIDs, [])
        XCTAssertEqual(d.investedTotal(in: oct2026), 0)
    }

    func testHomeHoldingsLimitAndOrder() {
        var d = makeBaseData()
        for i in 1...6 { d.addHolding(Holding(name: "H\(i)", kind: .etf, ticker: nil, units: nil, startMonth: aug2026)) }
        XCTAssertEqual(d.homeHoldings().map(\.name), ["H1", "H2", "H3", "H4"])
        d.homeHoldingIDs = [d.holdings[5].id, d.holdings[0].id]
        XCTAssertEqual(d.homeHoldings().map(\.name), ["H6", "H1"])
    }
}
