import XCTest
@testable import MyBuddyCore

/// Wat de gebruiker invult (ingelegd bedrag, maandinleg, ticker met aantal) moet een reeks opleveren, ook zonder meetpunt:
/// een belegging zonder meetpunt krijgt een afgeleid beginpunt uit "Totaal ingelegd", "Belegd sinds" en de inleg (plan par. 5.2,
/// C1). Deze vijf tests faalden op HEAD 6140902 (drie van de vijf) en beschrijven de fout "de grafiek bij Beleggingen werkt niet".
final class PortfolioSeriesDerivedTests: XCTestCase {
    private func fresh() -> FinanceData {
        var d = FinanceData(startMonth: oct2026)
        d.materialize(upTo: oct2026)
        return d
    }

    private let today = day(oct2026, 15)

    func testHoldingWithOnlyInvestedTotalHasAValueAndASeries() {
        var d = fresh()
        d.addHolding(Holding(name: "Fonds", kind: .etf, ticker: nil, units: nil, investedTotal: 3_000,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 200, startMonth: oct2026))
        // Wat de gebruiker bij "Totaal ingelegd" typte, is de waarde en het ingelegde bedrag van nu.
        XCTAssertEqual(d.portfolioInvested(current: oct2026, today: today), 3_000, accuracy: 0.001)
        XCTAssertEqual(d.portfolioValue(current: oct2026, today: today), 3_000, accuracy: 0.001)
        let series = d.portfolioSeries(from: oct2026, count: 4, current: oct2026, today: today)
        XCTAssertEqual(series.count, 4)
        XCTAssertEqual(series.map(\.value), [3_000, 3_200, 3_400, 3_600])
        XCTAssertEqual(series.map(\.isProjected), [false, true, true, true])
    }

    func testHoldingWithOnlyAMonthlyContributionHasASeries() {
        var d = fresh()
        d.addHolding(Holding(name: "Inleg", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 200, startMonth: oct2026))
        let series = d.portfolioSeries(from: oct2026, count: 3, current: oct2026, today: today)
        XCTAssertEqual(series.map(\.value), [0, 200, 400])
    }

    func testTickerWithUnitsButNoPriceStillGivesASeriesFromInvestedTotal() {
        var d = fresh()
        d.addHolding(Holding(name: "VWCE", kind: .etf, ticker: "VWCE.DE", units: 10, investedTotal: 1_000,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: oct2026))
        XCTAssertFalse(d.portfolioSeries(from: oct2026, count: 3, current: oct2026, today: today).isEmpty)
    }

    func testMeasuredHoldingIsUnchangedByTheFallback() {
        var d = fresh()
        let h = Holding(name: "Fonds", kind: .etf, ticker: nil, units: nil, investedTotal: 900,
                        expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: oct2026)
        d.addHolding(h, initialValue: 1_000, now: today)
        XCTAssertEqual(d.portfolioValue(current: oct2026, today: today), 1_000, accuracy: 0.001)
    }

    func testHoldingWithoutAnyDataStaysEmpty() {
        var d = fresh()
        d.addHolding(Holding(name: "Leeg", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: oct2026))
        XCTAssertTrue(d.portfolioSeries(from: oct2026, count: 3, current: oct2026, today: today).isEmpty)
    }
}
