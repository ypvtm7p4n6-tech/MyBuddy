import XCTest
@testable import MyBuddyCore

/// Een gekozen punt (tik of aanwijzer) is een zuivere functie van het model: de titel, de rijen met bedragen als tekst en het
/// dichtstbijzijnde punt. Ook de x-labels blijven binnen de grafiek en `showsCents` geeft een koers met centen.
final class ChartSelectionTests: XCTestCase {
    private func point(_ id: String, _ date: Date, _ value: Double, _ kind: ChartPointKind = .actual) -> ChartPoint {
        ChartPoint(id: id, date: date, value: value, kind: kind)
    }

    private func monthLine(_ id: String, name: String, values: [Double], kinds: [ChartPointKind] = []) -> ChartLine {
        var points: [ChartPoint] = []
        for (i, value) in values.enumerated() {
            let kind: ChartPointKind = i < kinds.count ? kinds[i] : .actual
            points.append(point("\(id)-\(i)", oct2026.adding(i).firstDay, value, kind))
        }
        return ChartLine(id: id, name: name, points: points, role: id == "a" ? .primary : .secondary)
    }

    // MARK: Titels

    func testTheTitleFollowsTheKindOfAxis() {
        let months = TrendModel(title: "T", lines: [monthLine("a", name: "A", values: [1, 2])], summary: "s")
        XCTAssertEqual(months.selectionTitle(oct2026.firstDay), "Oktober 2026")
        // Een dagpunt op een maandas (een koers) krijgt een datum met dag.
        XCTAssertTrue(months.selectionTitle(day(oct2026, 21)).hasPrefix("21 "), months.selectionTitle(day(oct2026, 21)))
        let days = TrendModel(title: "T", lines: [monthLine("a", name: "A", values: [1, 2])], xAxis: .days, summary: "s")
        XCTAssertEqual(days.selectionTitle(day(oct2026, 25)), DayText.weekdayShort(day(oct2026, 25)))
        let elapsed = TrendModel(title: "T", lines: [monthLine("a", name: "A", values: [1, 2])], xAxis: .elapsed(.years), summary: "s")
        XCTAssertEqual(elapsed.selectionTitle(ChartAxis.elapsedDate(5)), "Na 5 jaren")
        XCTAssertEqual(elapsed.selectionTitle(ChartAxis.elapsedDate(2.5)), "Na 2,5 jaren")
    }

    func testValueTextHasCentsOnlyForAPrice() {
        let whole = TrendModel(title: "T", lines: [], summary: "s")
        XCTAssertEqual(whole.valueText(1_234.56), Fmt.euroWhole(1_234.56))
        let price = TrendModel(title: "T", lines: [], summary: "s", showsCents: true)
        XCTAssertEqual(price.valueText(105.36), Fmt.euroExact(105.36))
        XCTAssertTrue(price.valueText(105.36).contains("105,36"), price.valueText(105.36))
    }

    // MARK: De dichtstbijzijnde plek

    func testTheNearestPointOfAllLinesDecidesThePlace() {
        let line = monthLine("a", name: "Waarde", values: [100, 200, 300])
        let model = TrendModel(title: "T", lines: [line], summary: "s")
        // Net na 1 november ligt het dichtst bij november.
        let selection = model.selection(near: day(oct2026.adding(1), 3))
        XCTAssertEqual(selection?.date, oct2026.adding(1).firstDay)
        XCTAssertEqual(selection?.title, "November 2026")
        XCTAssertEqual(selection?.rows.count, 1)
        XCTAssertEqual(selection?.rows.first?.value, 200)
        XCTAssertEqual(selection?.rows.first?.text, Fmt.euroWhole(200))
        // Ver voor het begin en ver na het einde: het eerste en het laatste punt.
        XCTAssertEqual(model.selection(near: day(oct2026.adding(-5), 1))?.date, oct2026.firstDay)
        XCTAssertEqual(model.selection(near: day(oct2026.adding(9), 1))?.date, oct2026.adding(2).firstDay)
    }

    func testEstimatedAndProjectedValuesSaySoInTheText() {
        let line = monthLine("a", name: "Waarde", values: [100, 100, 150], kinds: [.estimated, .actual, .projected])
        let model = TrendModel(title: "T", lines: [line], summary: "s")
        XCTAssertEqual(model.selection(near: oct2026.firstDay)?.rows.first?.text, Fmt.euroWhole(100) + " (geschat)")
        XCTAssertEqual(model.selection(near: oct2026.adding(1).firstDay)?.rows.first?.text, Fmt.euroWhole(100))
        XCTAssertEqual(model.selection(near: oct2026.adding(2).firstDay)?.rows.first?.text, Fmt.euroWhole(150) + " (verwacht)")
    }

    func testEveryLineWithAPointThereGetsARowAndAShorterLineDoesNot() {
        let long = monthLine("a", name: "Mijn inleg", values: [100, 200, 300, 400, 500, 600])
        let short = monthLine("b", name: "Benodigde inleg", values: [100, 250, 400])
        let model = TrendModel(title: "T", lines: [long, short], summary: "s")
        let early = model.selection(near: oct2026.adding(1).firstDay)
        XCTAssertEqual(early?.rows.map { $0.name }, ["Mijn inleg", "Benodigde inleg"])
        XCTAssertEqual(early?.rows.map { $0.value }, [200, 250])
        // Na het einde van de korte lijn heeft hij geen waarde meer: alleen de lange lijn staat in de rijen.
        let late = model.selection(near: oct2026.adding(5).firstDay)
        XCTAssertEqual(late?.rows.map { $0.name }, ["Mijn inleg"])
    }

    func testALineThatIsThinnedDifferentlyStillGetsItsNearestPoint() {
        // Twee lijnen met een andere uitdunning: de ene om de maand, de andere om de twee maanden.
        let dense = monthLine("a", name: "Dicht", values: [1, 2, 3, 4, 5])
        var sparsePoints: [ChartPoint] = []
        for i in [0, 2, 4] { sparsePoints.append(point("b-\(i)", oct2026.adding(i).firstDay, Double(i) * 10)) }
        let sparse = ChartLine(id: "b", name: "Ijl", points: sparsePoints, role: .secondary)
        let model = TrendModel(title: "T", lines: [dense, sparse], summary: "s")
        let selection = model.selection(near: oct2026.adding(1).firstDay)
        XCTAssertEqual(selection?.rows.map { $0.name }, ["Dicht", "Ijl"])
    }

    func testAnEmptyModelHasNoSelection() {
        let model = TrendModel(title: "T", lines: [], summary: "s")
        XCTAssertNil(model.selection(near: Date()))
    }

    func testPriceSelectionShowsCents() {
        var points: [ChartPoint] = []
        for i in 0..<5 { points.append(point("k-\(i)", day(oct2026, 1 + i * 5), 100 + Double(i) + 0.36)) }
        let line = ChartLine(id: "k", name: "Koers", points: points)
        let model = TrendModel(title: "Koers", lines: [line], summary: "s", showsCents: true)
        let selection = model.selection(near: day(oct2026, 6))
        XCTAssertEqual(selection?.rows.first?.text, Fmt.euroExact(101.36))
    }

    func testTheMarkerPointIsTheLastRealPoint() {
        let all = monthLine("a", name: "A", values: [1, 2, 3, 4], kinds: [.actual, .actual, .projected, .projected])
        XCTAssertEqual(all.markerPoint?.id, "a-1")
        let projectedOnly = monthLine("a", name: "A", values: [1, 2], kinds: [.projected, .projected])
        XCTAssertEqual(projectedOnly.markerPoint?.id, "a-1")
        let estimated = monthLine("a", name: "A", values: [1, 2, 3], kinds: [.estimated, .estimated, .projected])
        XCTAssertEqual(estimated.markerPoint?.id, "a-1")
        XCTAssertNil(ChartLine(id: "x", name: "X", points: []).markerPoint)
    }

    // MARK: X-labels binnen de grafiek

    func testXTicksStayInsideTheDomainForADailyPriceHistory() {
        var points: [ChartPoint] = []
        let start = day(oct2026.adding(-12), 21)
        for i in 0..<250 {
            points.append(point("k-\(i)", start.addingTimeInterval(Double(i) * 86_400 * 1.5), 100 + Double(i % 7)))
        }
        let model = TrendModel(title: "Koers", lines: [ChartLine(id: "k", name: "Koers", points: points)], summary: "s")
        let range = model.xDomain
        let ticks = model.xTicks
        XCTAssertFalse(ticks.isEmpty)
        XCTAssertTrue(ticks.allSatisfy { range.contains($0) }, "\(ticks) buiten \(range)")
        XCTAssertEqual(ticks, ticks.sorted())
    }

    func testASinglePointStillHasAnXLabel() {
        let model = TrendModel(title: "T", lines: [monthLine("a", name: "A", values: [5])], summary: "s")
        XCTAssertFalse(model.xTicks.isEmpty)
        XCTAssertTrue(model.xTicks.allSatisfy { model.xDomain.contains($0) })
    }
}
