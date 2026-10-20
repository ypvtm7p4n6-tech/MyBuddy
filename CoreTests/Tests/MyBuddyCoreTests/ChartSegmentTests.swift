import XCTest
@testable import MyBuddyCore

/// Een lijn bestaat uit stukken van dezelfde soort (werkelijk, afgeleid, verwacht): elk stuk sluit aan op het laatste punt van het
/// vorige, en een stuk van een punt is een stip (geen lijn).
final class ChartSegmentTests: XCTestCase {
    private func point(_ i: Int, _ kind: ChartPointKind) -> ChartPoint {
        ChartPoint(id: "p\(i)", date: oct2026.adding(i).firstDay, value: Double(i) * 100, kind: kind)
    }

    private func line(_ kinds: [ChartPointKind]) -> ChartLine {
        ChartLine(id: "l", name: "Lijn", points: kinds.enumerated().map { point($0.offset, $0.element) })
    }

    func testActualThenProjectedConnectsAtTheLastActualPoint() {
        let segments = line([.actual, .actual, .actual, .projected, .projected]).segments
        XCTAssertEqual(segments.map { $0.kind }, [.actual, .projected])
        XCTAssertEqual(segments[0].points.map { $0.id }, ["p0", "p1", "p2"])
        // Het verwachte stuk begint op het laatste werkelijke punt: de lijn sluit aan.
        XCTAssertEqual(segments[1].points.map { $0.id }, ["p2", "p3", "p4"])
    }

    func testASingleActualPointIsADotFollowedByTheProjection() {
        let segments = line([.actual, .projected, .projected]).segments
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].kind, .actual)
        XCTAssertEqual(segments[0].points.count, 1)
        XCTAssertEqual(segments[1].points.map { $0.id }, ["p0", "p1", "p2"])
    }

    func testOnePointInTotalIsOneSegmentOfOnePoint() {
        let segments = line([.estimated]).segments
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].points.count, 1)
        XCTAssertTrue(line([]).segments.isEmpty)
    }

    func testEstimatedThenActualThenProjectedGivesThreeSegmentsWithUniqueIDs() {
        let segments = line([.estimated, .estimated, .actual, .actual, .projected]).segments
        XCTAssertEqual(segments.map { $0.kind }, [.estimated, .actual, .projected])
        XCTAssertEqual(Set(segments.map { $0.id }).count, 3)
        XCTAssertEqual(segments[1].points.first?.id, "p1")
        XCTAssertEqual(segments[2].points.first?.id, "p3")
    }

    func testOnlyProjectedPointsAreOneProjectedSegment() {
        let segments = line([.projected, .projected, .projected]).segments
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .projected)
        XCTAssertEqual(segments[0].points.count, 3)
    }

    func testTheModelDomainAndTicksCoverASinglePoint() {
        let model = TrendModel(title: "Een punt", lines: [line([.actual])], summary: "Een punt.")
        let x = model.xDomain
        XCTAssertLessThan(x.lowerBound, x.upperBound)
        XCTAssertFalse(model.xTicks.isEmpty)
        let y = model.domain()
        XCTAssertLessThan(y.lowerBound, y.upperBound)
        // Zonder punten blijft alles geldig.
        let none = TrendModel.placeholder(title: "Leeg", empty: ChartEmpty(symbol: "chart.bar", title: "Leeg", message: "Niets."))
        XCTAssertLessThan(none.domain().lowerBound, none.domain().upperBound)
        XCTAssertLessThan(none.xDomain.lowerBound, none.xDomain.upperBound)
        XCTAssertTrue(none.summary.contains("Geen gegevens"))
        XCTAssertNotNil(none.empty)
    }
}
