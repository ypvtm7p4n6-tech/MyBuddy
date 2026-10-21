import XCTest
@testable import MyBuddyCore

/// Eigenschappen van de waarde van beleggingen die voor elke combinatie van invoer moeten gelden (plan par. 5.2, C1 t/m C5): wat het
/// getal van nu zegt is het laatste echte punt van de grafiek, de grafiek begint bij het eerste gegeven, een afgeleid beginpunt
/// schrijft niets in de meetpunten, en de verdeling over soorten telt op tot het totaal. Honderden vaste, willekeurige invoeren
/// (een eigen generator met vaste startwaarde, dus elke run gelijk).
final class PortfolioConsistencyTests: XCTestCase {
    /// Een kleine, deterministische generator (geen `SystemRandomNumberGenerator`).
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
        mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }
    }

    private let kinds: [HoldingKind] = HoldingKind.allCases

    private struct Scenario {
        var data: FinanceData
        var today: Date
        var derivedOnly: Bool
        var allContributionsNonNegative: Bool
        var typedTotals: [UUID: Double]
    }

    private func makeScenario(_ g: inout Generator) -> Scenario {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        let today = day(oct2026, g.int(1...31))
        var derivedOnly = true
        var nonNegative = true
        var typed: [UUID: Double] = [:]
        for index in 0..<g.int(1...3) {
            let start = oct2026.adding(-g.int(0...30))
            let total = Double(g.int(0...200)) * 100
            let monthly = Double([0, 0, 50, 100, 200, 250, -100][g.int(0...6)])
            if monthly < 0 { nonNegative = false }
            let kind = kinds[g.int(0...(kinds.count - 1))]
            let holding = Holding(name: "B\(index)", kind: kind, ticker: nil, units: nil, investedTotal: total,
                                  expectedReturn: Double(g.int(0...8)) / 100, annualCost: 0, monthlyContribution: monthly,
                                  startMonth: start)
            d.addHolding(holding)
            typed[holding.id] = total
            if g.chance(35) {
                // Een echt meetpunt ergens tussen de start en nu: dan is dit geen afgeleide belegging meer.
                let offset = g.int(0...start.months(to: oct2026))
                let value = Double(g.int(1...300)) * 100
                d.addSnapshot(holdingID: holding.id, value: value, invested: total, date: day(start.adding(offset), g.int(1...27)))
                derivedOnly = false
            }
        }
        return Scenario(data: d, today: today, derivedOnly: derivedOnly, allContributionsNonNegative: nonNegative, typedTotals: typed)
    }

    func testTheValueOfNowIsTheLastRealPointOfTheSeries() {
        var g = Generator(state: 20_261_020)
        for run in 0..<300 {
            let s = makeScenario(&g)
            let series = s.data.portfolioSeries(from: oct2026.adding(-36), count: 49, current: oct2026, today: s.today)
            let value = s.data.portfolioValue(current: oct2026, today: s.today)
            let invested = s.data.portfolioInvested(current: oct2026, today: s.today)
            guard let lastReal = series.last(where: { !$0.isProjected }) else {
                XCTAssertEqual(value, 0, accuracy: 0.001, "run \(run): geen reeks maar wel een waarde")
                continue
            }
            XCTAssertEqual(lastReal.month, oct2026, "run \(run)")
            XCTAssertEqual(lastReal.value, value, accuracy: 0.011, "run \(run): waarde van nu")
            XCTAssertEqual(lastReal.invested, invested, accuracy: 0.011, "run \(run): ingelegd van nu")
            XCTAssertTrue(series.allSatisfy { $0.isProjected == ($0.month > oct2026) }, "run \(run): verwacht na nu")
            XCTAssertTrue(series.allSatisfy { $0.value.isFinite }, "run \(run): eindig")
            // Een verwachte waarde onder 0 bestaat niet (C4); het verleden volgt de meetpunten en de inleg.
            XCTAssertTrue(series.filter { $0.isProjected }.allSatisfy { $0.value >= 0 }, "run \(run): verwacht nooit onder 0")
        }
    }

    func testTheSeriesBeginsWhereTheDataBegins() {
        var g = Generator(state: 7_777)
        for run in 0..<300 {
            let s = makeScenario(&g)
            let series = s.data.portfolioSeries(from: oct2026.adding(-36), count: 49, current: oct2026, today: s.today)
            let start = s.data.portfolioDataStart(current: oct2026, today: s.today)
            if series.isEmpty {
                XCTAssertNil(start, "run \(run): geen reeks maar wel een begin")
            } else {
                XCTAssertEqual(series.first?.month, start, "run \(run)")
            }
        }
    }

    func testADerivedStartingPointNeverWritesAMeasurement() {
        var g = Generator(state: 99)
        for run in 0..<150 {
            let s = makeScenario(&g)
            let before = s.data.holdings.map { $0.snapshots.count }
            _ = s.data.portfolioSeries(from: oct2026.adding(-36), count: 49, current: oct2026, today: s.today)
            _ = s.data.portfolioValue(current: oct2026, today: s.today)
            _ = s.data.netWorthSeries(from: oct2026.adding(-12), count: 25, current: oct2026)
            XCTAssertEqual(s.data.holdings.map { $0.snapshots.count }, before, "run \(run)")
        }
    }

    func testADerivedHoldingNeverShowsLessThanYouTypedAndGrowsWithItsDeposits() {
        var g = Generator(state: 4_242)
        var checked = 0
        for run in 0..<400 {
            let s = makeScenario(&g)
            guard s.derivedOnly, s.allContributionsNonNegative else { continue }
            checked += 1
            let typedSum = s.typedTotals.values.reduce(0, +)
            let value = s.data.portfolioValue(current: oct2026, today: s.today)
            // Elke belegging die al begonnen is, toont minstens wat je intikte (bij meer inleg sinds "Belegd sinds" meer).
            let started = s.data.holdings.filter { $0.startMonth <= oct2026 }
            let startedTyped = started.reduce(0) { $0 + (s.typedTotals[$1.id] ?? 0) }
            XCTAssertGreaterThanOrEqual(value, startedTyped - 0.011, "run \(run)")
            XCTAssertLessThanOrEqual(startedTyped, typedSum + 0.011)
            // De waarde groeit alleen door inleg: nooit omlaag in het verleden.
            let history = s.data.portfolioSeries(from: oct2026.adding(-36), count: 49, current: oct2026, today: s.today)
                .filter { !$0.isProjected }
            for pair in zip(history, history.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.value, pair.1.value + 0.011, "run \(run): \(pair.0.month.key)")
            }
            // Zonder rendement is wat er staat gelijk aan wat je inlegde: de winst is 0.
            XCTAssertTrue(history.allSatisfy { $0.isEstimated }, "run \(run)")
            XCTAssertEqual(s.data.portfolioGain(current: oct2026, today: s.today), 0, accuracy: 0.011, "run \(run)")
        }
        XCTAssertGreaterThan(checked, 20, "te weinig afgeleide invoeren om iets te bewijzen")
    }

    func testTheKindsAddUpToTheTotal() {
        var g = Generator(state: 31_415)
        for run in 0..<200 {
            let s = makeScenario(&g)
            let total = s.data.portfolioValue(current: oct2026, today: s.today)
            let byKind = s.data.valueByKind(current: oct2026, today: s.today)
            // Een soort met een negatieve waarde (een meetpunt met een negatieve inleg erna) telt niet mee in de verdeling.
            let anyNegative = s.data.holdings.contains { (s.data.holdingStateNow($0, current: oct2026, today: s.today)?.value ?? 0) < 0 }
            if !anyNegative {
                XCTAssertEqual(byKind.reduce(0) { $0 + $1.value }, total, accuracy: 0.011 * Double(max(1, byKind.count)), "run \(run)")
            }
            XCTAssertTrue(byKind.allSatisfy { $0.value > 0 }, "run \(run)")
            let donut = DonutModel.holdingKinds(s.data, current: oct2026, today: s.today)
            XCTAssertEqual(donut.empty == nil, !byKind.isEmpty, "run \(run)")
            if donut.empty == nil { XCTAssertEqual(donut.slices.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9, "run \(run)") }
        }
    }

    func testEveryModelIsValidForEveryScenario() {
        var g = Generator(state: 8_080)
        for run in 0..<200 {
            let s = makeScenario(&g)
            for window in PortfolioWindow.allCases {
                let model = PortfolioTrend.model(s.data, window: window, current: oct2026, today: s.today)
                XCTAssertFalse(model.summary.isEmpty, "run \(run)")
                let domain = model.domain(nonNegative: true)
                XCTAssertLessThan(domain.lowerBound, domain.upperBound, "run \(run)")
                XCTAssertEqual(model.empty == nil, !model.lines.isEmpty, "run \(run)")
                if model.empty == nil {
                    XCTAssertTrue(model.lines.allSatisfy { Set($0.points.map { $0.id }).count == $0.points.count }, "run \(run)")
                    XCTAssertFalse(model.xTicks.isEmpty, "run \(run)")
                    XCTAssertNotNil(model.selection(near: s.today), "run \(run)")
                }
            }
            let available = PortfolioTrend.availableMonths(s.data, current: oct2026, today: s.today)
            let options = PortfolioWindow.options(availableMonths: available)
            XCTAssertTrue(options.isEmpty || options.last == .all, "run \(run)")
        }
    }
}
