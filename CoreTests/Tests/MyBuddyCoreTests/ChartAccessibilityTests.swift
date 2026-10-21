import XCTest
@testable import MyBuddyCore

/// De gegevens voor de grafiekbeschrijving van VoiceOver (`AXChartDescriptor`) en de bedragen bij een gekozen maand: elke categorie
/// is uniek, elk punt verwijst naar een categorie, en de staafgrafiek en de donut beschrijven hun bedragen als tekst.
final class ChartAccessibilityTests: XCTestCase {
    private func monthLine(_ id: String, values: [Double], start: YearMonth = oct2026) -> ChartLine {
        var points: [ChartPoint] = []
        for (i, value) in values.enumerated() {
            points.append(ChartPoint(id: "\(id)-\(i)", date: start.adding(i).firstDay, value: value, kind: i >= 2 ? .projected : .actual))
        }
        return ChartLine(id: id, name: "Reeks \(id)", points: points)
    }

    private func assertConsistent(_ data: ChartAccessibility, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(data.categories).count, data.categories.count, "unieke categorieën", file: file, line: line)
        for series in data.series {
            XCTAssertFalse(series.name.isEmpty, "reeksnaam", file: file, line: line)
            for point in series.points {
                XCTAssertTrue(data.categories.contains(point.category), "categorie \(point.category)", file: file, line: line)
                XCTAssertTrue(point.value.isFinite, "eindige waarde", file: file, line: line)
            }
        }
    }

    // MARK: Lijngrafiek

    func testTrendDataHasOneCategoryPerDateAndEveryPointPointsAtOne() {
        let model = TrendModel(title: "T", lines: [monthLine("a", values: [1, 2, 3, 4]), monthLine("b", values: [5, 6, 7])], summary: "s")
        let data = model.accessibilityData
        XCTAssertEqual(data.categories, ["Oktober 2026", "November 2026", "December 2026", "Januari 2027"])
        XCTAssertEqual(data.series.map { $0.name }, ["Reeks a", "Reeks b"])
        XCTAssertEqual(data.series[0].points.count, 4)
        XCTAssertEqual(data.series[1].points.count, 3)
        XCTAssertEqual(data.xTitle, "Maand")
        assertConsistent(data)
    }

    func testProjectedAndEstimatedPointsAreLabelled() {
        let line = ChartLine(id: "a", name: "Waarde", points: [
            ChartPoint(id: "0", date: oct2026.firstDay, value: 1, kind: .estimated),
            ChartPoint(id: "1", date: oct2026.adding(1).firstDay, value: 2, kind: .actual),
            ChartPoint(id: "2", date: oct2026.adding(2).firstDay, value: 3, kind: .projected)
        ])
        let data = TrendModel(title: "T", lines: [line], summary: "s").accessibilityData
        XCTAssertEqual(data.series[0].points.map { $0.label }, ["geschat", nil, "verwacht"])
    }

    func testTwoDatesWithTheSameTitleStillGetUniqueCategories() {
        // Twee punten op dezelfde dag (andere tijd) hebben dezelfde titel: de tweede krijgt een nummer.
        let first = day(oct2026, 5)
        let second = first.addingTimeInterval(3_600)
        let line = ChartLine(id: "k", name: "Koers", points: [
            ChartPoint(id: "0", date: first, value: 1, kind: .actual),
            ChartPoint(id: "1", date: second, value: 2, kind: .actual)
        ])
        let data = TrendModel(title: "T", lines: [line], summary: "s").accessibilityData
        XCTAssertEqual(data.categories.count, 2)
        XCTAssertEqual(Set(data.categories).count, 2)
        assertConsistent(data)
    }

    func testDailyPricePointsGetUniqueDayCategories() {
        var points: [ChartPoint] = []
        for i in 0..<40 { points.append(ChartPoint(id: "k\(i)", date: day(oct2026, 1).addingTimeInterval(Double(i) * 86_400), value: 100 + Double(i), kind: .actual)) }
        let data = TrendModel(title: "Koers", lines: [ChartLine(id: "k", name: "Koers", points: points)], summary: "s").accessibilityData
        XCTAssertEqual(data.categories.count, 40)
        assertConsistent(data)
    }

    func testTheElapsedAxisNamesTheUnit() {
        let model = TrendModel(title: "T", lines: [monthLine("a", values: [1, 2])], xAxis: .elapsed(.years), summary: "s")
        XCTAssertEqual(model.accessibilityData.xTitle, "Tijd in jaren")
    }

    func testEveryBuilderGivesConsistentAccessibilityData() {
        var d = FinanceData(startMonth: aug2026)
        d.materialize(upTo: oct2026)
        d.addHolding(Holding(name: "Fonds", kind: .etf, ticker: nil, units: nil, investedTotal: 3_000, expectedReturn: 0.05,
                             annualCost: 0, monthlyContribution: 200, startMonth: aug2026))
        let portfolio = PortfolioTrend.model(d, window: .all, current: oct2026, today: day(oct2026, 15))
        XCTAssertNil(portfolio.empty)
        assertConsistent(portfolio.accessibilityData)
        let projection = ProjectionTrend.model(start: 1_000, monthly: 100, annualReturn: 0.05, months: 120, unit: .years,
                                               target: 0, inflationAdjusted: false, inflation: 0.02)
        assertConsistent(projection.accessibilityData)
        XCTAssertEqual(projection.accessibilityData.series.count, 3)
    }

    // MARK: Staven

    private func summary(_ month: YearMonth, income: Double, expenses: Double, saved: Double = 0, invested: Double = 0,
                         projected: Bool = false) -> MonthSummary {
        MonthSummary(month: month, income: income, expenses: expenses, fromPots: 0, saved: saved, invested: invested, isProjected: projected)
    }

    func testBarDetailRowsFollowTheStackAndNameWhatIsLeftOrTheShortfall() {
        let past = StackedBarModel.months([summary(aug2026, income: 3_000, expenses: 1_000, saved: 500, invested: 200)], startMonth: aug2026)
        XCTAssertEqual(past.entries[0].detailRows.map { $0.label }, ["Inkomen", "Uitgaven", "Gespaard", "Belegd", "Overgehouden"])
        XCTAssertEqual(past.entries[0].detailRows.map { $0.value }, [3_000, 1_000, 500, 200, 1_300])
        let future = StackedBarModel.months([summary(oct2026, income: 3_000, expenses: 1_000, projected: true)], startMonth: aug2026)
        XCTAssertEqual(future.entries[0].detailRows.last?.label, "Nog te verdelen")
        let short = StackedBarModel.months([summary(aug2026, income: 3_000, expenses: 3_500, saved: 200)], startMonth: aug2026)
        XCTAssertEqual(short.entries[0].detailRows.last?.label, "Tekort")
        XCTAssertEqual(short.entries[0].detailRows.last?.value ?? 0, 700, accuracy: 0.001)
        XCTAssertEqual(Set(short.entries[0].detailRows.map { $0.id }).count, short.entries[0].detailRows.count)
    }

    func testTheBarDomainStartsAtZeroAndCoversTheTallestStackAndTheIncome() {
        let list = [summary(aug2026, income: 3_000, expenses: 1_000, saved: 500),
                    summary(sep2026, income: 3_000, expenses: 3_700, saved: 200, invested: 200)]
        let model = StackedBarModel.months(list, startMonth: aug2026)
        let domain = model.domain()
        XCTAssertEqual(domain.lowerBound, 0)
        XCTAssertGreaterThan(domain.upperBound, 4_100)
        XCTAssertLessThan(domain.upperBound, 4_800)
        // Een model zonder maanden heeft toch een geldig domein.
        let empty = StackedBarModel.months([], startMonth: aug2026)
        XCTAssertLessThan(empty.domain().lowerBound, empty.domain().upperBound)
    }

    func testBarEntriesAreFoundByTheirKeyAndHaveAUniqueTitle() {
        let list = [summary(aug2026, income: 1, expenses: 1), summary(sep2026, income: 1, expenses: 1)]
        let model = StackedBarModel.months(list, startMonth: aug2026)
        XCTAssertEqual(model.entry(for: "2026-09")?.title, "September 2026")
        XCTAssertNil(model.entry(for: "2026-12"))
        XCTAssertEqual(Set(model.entries.map { $0.title }).count, 2)
    }

    func testBarAccessibilityHasASeriesPerKindAndTheIncome() {
        let list = [summary(aug2026, income: 3_000, expenses: 1_000, saved: 500, invested: 200),
                    summary(oct2026, income: 3_000, expenses: 1_000, saved: 500, invested: 200, projected: true)]
        let model = StackedBarModel.months(list, startMonth: aug2026)
        let data = model.accessibilityData
        XCTAssertEqual(data.categories, ["Augustus 2026", "Oktober 2026"])
        XCTAssertEqual(data.series.map { $0.name }, ["Uitgaven", "Gespaard", "Belegd", "Overgehouden", "Inkomen"])
        XCTAssertEqual(data.series.last?.points.map { $0.value }, [3_000, 3_000])
        XCTAssertEqual(data.series[0].points.map { $0.label }, [nil, "verwacht"])
        assertConsistent(data)
    }

    // MARK: Donut

    func testDonutAccessibilityHasOneCategoryPerKind() {
        var d = FinanceData(startMonth: aug2026)
        d.materialize(upTo: oct2026)
        for (i, kind) in [HoldingKind.etf, .bonds, .crypto].enumerated() {
            let h = Holding(name: "B\(i)", kind: kind, ticker: nil, units: nil, investedTotal: 1_000 * Double(i + 1),
                            expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: aug2026)
            d.addHolding(h, initialValue: 1_000 * Double(i + 1), now: day(oct2026, 2))
        }
        let model = DonutModel.holdingKinds(d, current: oct2026, today: day(oct2026, 15))
        let data = model.accessibilityData
        XCTAssertEqual(data.categories.count, 3)
        XCTAssertEqual(data.series.count, 1)
        XCTAssertEqual(data.series[0].points.map { $0.value }, model.slices.map { $0.value })
        XCTAssertTrue(data.series[0].points.allSatisfy { $0.label?.hasSuffix("procent") == true })
        assertConsistent(data)
        // De domeinhulp geeft altijd een geldig bereik.
        let range = data.domain(includesZero: true)
        XCTAssertLessThan(range.lowerBound, range.upperBound)
    }
}
