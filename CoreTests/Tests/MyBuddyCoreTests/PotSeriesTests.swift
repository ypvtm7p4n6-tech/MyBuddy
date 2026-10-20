import XCTest
@testable import MyBuddyCore

/// `potSeries` (plan par. 5.2, C8): het saldo van een pot aan het eind van elke maand, hetzelfde getal als `potBalance(_:at:)`.
final class PotSeriesTests: XCTestCase {
    func testEveryPointEqualsThePotBalanceAtTheEndOfTheMonth() {
        var d = makeBaseData()
        let pot = addBufferPot(&d, opening: 500, goal: 2_000)
        d.materialize(upTo: oct2026)
        d.addPotEntry(potID: pot.id, amount: 75, kind: .deposit, date: day(sep2026, 10))
        let series = d.potSeries(pot.id, from: aug2026, count: 18, current: oct2026)
        XCTAssertEqual(series.count, 18)
        for point in series {
            XCTAssertEqual(point.balance, d.potBalance(pot.id, at: point.month), accuracy: 0.001, "\(point.month.key)")
        }
        XCTAssertEqual(series.map { $0.isProjected }, (0..<18).map { aug2026.adding($0) > oct2026 })
        XCTAssertEqual(series.map { $0.id }, aug2026.range(count: 18).map { $0.key })
    }

    func testMonthsBeforeThePotStartAreZeroAndTheSeriesRisesWithTheDeposit() {
        var d = makeBaseData()
        let pot = addBufferPot(&d, opening: 500, goal: nil)
        d.materialize(upTo: oct2026)
        let series = d.potSeries(pot.id, from: YearMonth(year: 2026, month: 6), count: 8, current: oct2026)
        XCTAssertEqual(series[0].balance, 0)
        XCTAssertEqual(series[1].balance, 0)
        XCTAssertGreaterThan(series[3].balance, series[2].balance)
        XCTAssertEqual(series.last?.balance ?? 0, d.potBalance(pot.id, at: oct2026.adding(3)), accuracy: 0.001)
    }

    func testAnUnknownPotAndACountOfZeroGiveAnEmptySeries() {
        var d = makeBaseData()
        let pot = addBufferPot(&d)
        XCTAssertTrue(d.potSeries(UUID(), from: aug2026, count: 5, current: oct2026).isEmpty)
        XCTAssertTrue(d.potSeries(pot.id, from: aug2026, count: 0, current: oct2026).isEmpty)
        XCTAssertTrue(d.potSeries(pot.id, from: aug2026, count: -3, current: oct2026).isEmpty)
    }
}
