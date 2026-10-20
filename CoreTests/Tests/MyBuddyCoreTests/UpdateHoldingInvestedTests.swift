import XCTest
@testable import MyBuddyCore

/// `updateHolding` (plan par. 5.2, C9): wijzig je "Totaal ingelegd" van een belegging met een meetpunt (niet gevolgd), dan komt er een
/// meetpunt van vandaag met de waarde van nu en het nieuwe bedrag. Anders bleef de reeks bij het oude bedrag: het scherm toonde 5.000
/// en opgeslagen was 6.000.
final class UpdateHoldingInvestedTests: XCTestCase {
    private let now = day(oct2026, 14)

    /// ETF met een meetpunt op 15 augustus (waarde 1000, ingelegd 900).
    private func make(monthly: Double = 0) -> (FinanceData, Holding) {
        var d = makeBaseData()
        let h = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, investedTotal: 900,
                        expectedReturn: 0, annualCost: 0, monthlyContribution: monthly, startMonth: aug2026)
        d.addHolding(h)
        d.addSnapshot(holdingID: h.id, value: 1_000, invested: 900, date: day(aug2026, 15))
        d.materialize(upTo: oct2026)
        return (d, d.holdings[0])
    }

    func testChangingInvestedTotalAddsASnapshotOfTodayWithTheCurrentValue() {
        var (d, h) = make()
        XCTAssertEqual(d.holdingStateNow(h, current: oct2026, today: now)?.invested, 900)
        h.investedTotal = 1_200
        d.updateHolding(h, current: oct2026, now: now)
        let stored = d.holdings[0]
        XCTAssertEqual(stored.investedTotal, 1_200)
        XCTAssertEqual(stored.snapshots.count, 2)
        let latest = stored.snapshots.sorted { $0.date < $1.date }.last
        XCTAssertEqual(latest?.date, now)
        XCTAssertEqual(latest?.value, 1_000)
        XCTAssertEqual(latest?.invested, 1_200)
        // Het scherm (de reeks) volgt wat er is opgeslagen.
        let state = d.holdingStateNow(stored, current: oct2026, today: now)
        XCTAssertEqual(state?.value, 1_000)
        XCTAssertEqual(state?.invested, 1_200)
        XCTAssertEqual(state?.isEstimated, false)
        XCTAssertEqual(d.portfolioInvested(current: oct2026, today: now), 1_200)
    }

    func testTheNewSnapshotCarriesTheValueWithTheDepositsSoFar() {
        var (d, h) = make(monthly: 100)
        // September is overgeschreven (100), die van oktober (de 25e) is op 14 oktober nog gepland.
        XCTAssertEqual(d.holdingStateNow(h, current: oct2026, today: now)?.value, 1_100)
        h.investedTotal = 2_000
        d.updateHolding(h, current: oct2026, now: now)
        let latest = d.holdings[0].snapshots.sorted { $0.date < $1.date }.last
        XCTAssertEqual(latest?.value, 1_100)
        XCTAssertEqual(latest?.invested, 2_000)
        XCTAssertEqual(d.holdingStateNow(d.holdings[0], current: oct2026, today: now)?.value, 1_100)
    }

    func testEditingSomethingElseAddsNoSnapshot() {
        var (d, h) = make()
        h.name = "Ander"
        d.updateHolding(h, current: oct2026, now: now)
        XCTAssertEqual(d.holdings[0].snapshots.count, 1)
        XCTAssertEqual(d.holdings[0].name, "Ander")
    }

    func testChangingItTwiceOnTheSameDayReplacesTheSnapshot() {
        var (d, h) = make()
        h.investedTotal = 1_200
        d.updateHolding(h, current: oct2026, now: now)
        var again = d.holdings[0]
        again.investedTotal = 1_500
        d.updateHolding(again, current: oct2026, now: now)
        XCTAssertEqual(d.holdings[0].snapshots.count, 2)
        XCTAssertEqual(d.holdingStateNow(d.holdings[0], current: oct2026, today: now)?.invested, 1_500)
    }

    func testAHoldingWithoutASnapshotNeedsNoNewOneBecauseTheDerivedStartFollows() {
        var d = makeBaseData()
        let h = Holding(name: "Demo", kind: .etf, ticker: nil, units: nil, investedTotal: 3_000,
                        expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: aug2026)
        d.addHolding(h)
        d.materialize(upTo: oct2026)
        var edited = d.holdings[0]
        edited.investedTotal = 4_000
        d.updateHolding(edited, current: oct2026, now: now)
        XCTAssertTrue(d.holdings[0].snapshots.isEmpty)
        let state = d.holdingStateNow(d.holdings[0], current: oct2026, today: now)
        XCTAssertEqual(state?.value, 4_000)
        XCTAssertEqual(state?.isEstimated, true)
    }

    func testATrackedHoldingKeepsItsOwnRule() {
        var d = makeBaseData()
        var h = Holding(name: "VWCE", kind: .etf, ticker: "VWCE.DE", units: 10, investedTotal: 900,
                        expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: aug2026)
        h.lastPrice = 105
        d.addHolding(h)
        d.materialize(upTo: oct2026)
        var edited = d.holdings[0]
        edited.investedTotal = 950
        d.updateHolding(edited, current: oct2026, now: now)
        let latest = d.holdings[0].snapshots.sorted { $0.date < $1.date }.last
        XCTAssertEqual(latest?.value, 1_050)      // aantal maal laatste koers, zoals vroeger
        XCTAssertEqual(latest?.invested, 950)
    }
}
