import XCTest
@testable import MyBuddyCore

/// De donut bij Beleggingen: kleur per SOORT (niet per plek in de rangorde), de aandelen tellen op tot 1, ook bij een soort.
final class DonutModelTests: XCTestCase {
    private let today = day(oct2026, 15)

    private func data(_ items: [(HoldingKind, Double)]) -> FinanceData {
        var d = FinanceData(startMonth: aug2026)
        d.materialize(upTo: oct2026)
        for (i, item) in items.enumerated() {
            let h = Holding(name: "B\(i)", kind: item.0, ticker: nil, units: nil, investedTotal: item.1,
                            expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: aug2026)
            d.addHolding(h, initialValue: item.1, now: day(oct2026, 2))
        }
        return d
    }

    func testSlicesAddUpToOneAndAreSortedByValue() {
        let model = DonutModel.holdingKinds(data([(.etf, 4_888), (.bonds, 2_423), (.crypto, 1_656)]), current: oct2026, today: today)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.slices.map { $0.id }, ["etf", "bonds", "crypto"])
        XCTAssertEqual(model.slices.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
        XCTAssertEqual(model.total, 8_967, accuracy: 0.001)
        XCTAssertEqual(model.summary, "Verdeling van je beleggingen over 3 soorten: Indexfonds / ETF 55 procent (4.888 euro), Obligaties 27 procent (2.423 euro), Crypto 18 procent (1.656 euro).")
    }

    func testTheColorBelongsToTheKindNotToTheRank() {
        // Dezelfde soort heeft dezelfde kleur, ook als de volgorde van de waarden wisselt.
        let first = DonutModel.holdingKinds(data([(.etf, 5_000), (.crypto, 1_000)]), current: oct2026, today: today)
        let flipped = DonutModel.holdingKinds(data([(.etf, 500), (.crypto, 1_000)]), current: oct2026, today: today)
        func index(_ model: DonutModel, _ id: String) -> Int? { model.slices.first { $0.id == id }?.colorIndex }
        XCTAssertEqual(index(first, "etf"), index(flipped, "etf"))
        XCTAssertEqual(index(first, "crypto"), index(flipped, "crypto"))
        XCTAssertNotEqual(index(first, "etf"), index(first, "crypto"))
        XCTAssertEqual(first.slices.map { $0.id }, ["etf", "crypto"])
        XCTAssertEqual(flipped.slices.map { $0.id }, ["crypto", "etf"])
        // De kleurindex is de plek in `HoldingKind.allCases`, en past in het palet van acht kleuren.
        for kind in HoldingKind.allCases {
            XCTAssertEqual(kind.colorIndex, HoldingKind.allCases.firstIndex(of: kind))
            XCTAssertTrue((0..<8).contains(kind.colorIndex))
        }
        XCTAssertEqual(Set(HoldingKind.allCases.map { $0.colorIndex }).count, HoldingKind.allCases.count)
    }

    func testOneKindIsAFullRingNotAMissingBlock() {
        let model = DonutModel.holdingKinds(data([(.etf, 3_000), (.etf, 1_000)]), current: oct2026, today: today)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.slices.count, 1)
        XCTAssertEqual(model.slices[0].share, 1, accuracy: 1e-9)
        XCTAssertEqual(model.slices[0].value, 4_000, accuracy: 0.001)
        XCTAssertTrue(model.summary.contains("over 1 soort:"))
        XCTAssertTrue(model.summary.contains("100 procent"))
    }

    func testNothingToShowIsAnEmptyStateWithASummary() {
        let model = DonutModel.holdingKinds(data([]), current: oct2026, today: today)
        XCTAssertNotNil(model.empty)
        XCTAssertTrue(model.slices.isEmpty)
        XCTAssertEqual(model.total, 0)
        XCTAssertFalse(model.summary.isEmpty)
        // Een belegging zonder waarde telt niet mee.
        let zero = DonutModel.holdingKinds(data([(.etf, 0)]), current: oct2026, today: today)
        XCTAssertNotNil(zero.empty)
    }

    func testAHoldingWithoutAMeasurementCountsWithItsEstimatedValue() {
        var d = data([])
        d.addHolding(Holding(name: "Demo", kind: .etf, ticker: nil, units: nil, investedTotal: 3_000,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: aug2026))
        let model = DonutModel.holdingKinds(d, current: oct2026, today: today)
        XCTAssertEqual(model.total, 3_000, accuracy: 0.001)
        XCTAssertEqual(model.slices.map { $0.id }, ["etf"])
    }
}
