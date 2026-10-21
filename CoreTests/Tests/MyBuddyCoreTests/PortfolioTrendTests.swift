import XCTest
@testable import MyBuddyCore

/// De grafiek bij Beleggingen (`PortfolioTrend`, `PortfolioWindow`): vier lege staten met elk een actie, de afgeleide lijn uit je
/// inleg met haar onderschrift, de keuzebalk die alleen keuzes toont die iets veranderen, en de detailgrafiek van een belegging.
final class PortfolioTrendTests: XCTestCase {
    private let today = day(oct2026, 15)

    private func fresh(_ holdings: [Holding] = []) -> FinanceData {
        var d = FinanceData(startMonth: aug2026)
        d.materialize(upTo: oct2026)
        for h in holdings { d.addHolding(h) }
        return d
    }

    private func holding(_ name: String = "Demo", ticker: String? = nil, units: Double? = nil, invested: Double = 0,
                         monthly: Double = 0, start: YearMonth = aug2026) -> Holding {
        Holding(name: name, kind: .etf, ticker: ticker, units: units, investedTotal: invested,
                expectedReturn: 0, annualCost: 0, monthlyContribution: monthly, startMonth: start)
    }

    // MARK: De vier lege staten (en de vijfde)

    func testNoHoldingsIsAnEmptyStateWithAnAddAction() {
        let model = PortfolioTrend.model(fresh(), window: .all, current: oct2026, today: today)
        XCTAssertEqual(model.empty?.action, .addHolding)
        XCTAssertEqual(model.empty?.actionTitle, "Belegging toevoegen")
        XCTAssertTrue(model.lines.isEmpty)
        XCTAssertFalse(model.summary.isEmpty)
    }

    func testATickerWithoutUnitsAsksForTheUnits() {
        let h = holding("VWCE", ticker: "VWCE.DE")
        let model = PortfolioTrend.model(fresh([h]), window: .all, current: oct2026, today: today)
        XCTAssertEqual(model.empty?.action, .enterUnits(h.id))
        XCTAssertEqual(model.empty?.title, "Vul het aantal stuks in")
    }

    func testATrackedHoldingWithoutAPriceWaitsForTheQuote() {
        let h = holding("VWCE", ticker: "VWCE.DE", units: 10)
        let model = PortfolioTrend.model(fresh([h]), window: .all, current: oct2026, today: today)
        XCTAssertEqual(model.empty?.action, .refreshPrices)
        XCTAssertEqual(model.empty?.title, "Wachten op de koers")
    }

    func testAManualHoldingWithoutAnyValueAsksForAValue() {
        let h = holding("Leeg")
        let model = PortfolioTrend.model(fresh([h]), window: .all, current: oct2026, today: today)
        XCTAssertEqual(model.empty?.action, .enterValue(h.id))
        XCTAssertEqual(model.empty?.title, "Nog geen waarde")
    }

    func testAHoldingThatStartsInTheFutureSaysSoWithoutAnAction() {
        let h = holding("Later", invested: 1_000, start: oct2026.adding(2))
        let model = PortfolioTrend.model(fresh([h]), window: .all, current: oct2026, today: today)
        XCTAssertEqual(model.empty?.title, "Nog niet begonnen")
        XCTAssertNil(model.empty?.action)
    }

    func testEveryEmptyStateHasASummary() {
        let models = [PortfolioTrend.model(fresh(), window: .all, current: oct2026, today: today),
                      PortfolioTrend.model(fresh([holding()]), window: .all, current: oct2026, today: today)]
        for model in models {
            XCTAssertNotNil(model.empty)
            XCTAssertTrue(model.summary.contains("Geen gegevens"))
        }
    }

    // MARK: Afgeleid uit je inleg

    func testOnlyInvestedTotalAndContributionGiveAnEstimatedLineWithItsFootnote() {
        let d = fresh([holding(invested: 3_000, monthly: 200)])
        let model = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        XCTAssertNil(model.empty)
        // Afgeleid is de waarde gelijk aan wat je inlegde: een tweede lijn "Ingelegd" zou er bovenop liggen.
        XCTAssertEqual(model.lines.map { $0.name }, ["Waarde"])
        let points = model.lines[0].points
        XCTAssertEqual(points.count, 3 + PortfolioTrend.forwardMonths)
        XCTAssertEqual(points.prefix(3).map { $0.kind }, [.estimated, .estimated, .estimated])
        XCTAssertEqual(points.suffix(PortfolioTrend.forwardMonths).filter { $0.kind == .projected }.count, PortfolioTrend.forwardMonths)
        // Augustus, september, nu (de inleg van de 25e is op 15 oktober nog gepland), daarna 200 per maand.
        XCTAssertEqual(points.prefix(4).map { $0.value }, [2_800, 3_000, 3_000, 3_200])
        XCTAssertEqual(model.footnote, "Geschat uit je inleg, zonder rendement.")
        XCTAssertTrue(model.summary.contains("Geschat uit je inleg"))
        XCTAssertEqual(model.caption, "Nu \(Fmt.euroWhole(3_000)) (geschat)")
        // Het vlak hoort bij de werkelijke lijn: de afgeleide stukken hebben geen vlak (de view tekent het alleen voor `.actual`).
        XCTAssertTrue(model.lines[0].fillsArea)
    }

    func testTheSingleCurrentPointOfANewHoldingIsADotWithTheProjectionAfterIt() {
        let d = fresh([holding(invested: 3_000, monthly: 200, start: oct2026)])
        let model = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        let segments = model.lines[0].segments
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].points.count, 1)
        XCTAssertEqual(segments[0].kind, .estimated)
        XCTAssertEqual(segments[1].kind, .projected)
        XCTAssertEqual(model.footnote, "Geschat uit je inleg, zonder rendement.")
    }

    func testARealMeasurementReplacesTheEstimate() {
        var d = fresh([holding(invested: 3_000, monthly: 200)])
        d.addSnapshot(holdingID: d.holdings[0].id, value: 3_500, invested: 3_000, date: day(oct2026, 10))
        let model = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.lines.map { $0.name }, ["Waarde", "Ingelegd"])
        XCTAssertTrue(model.lines[0].points.filter { $0.kind != .projected }.allSatisfy { $0.kind == .actual })
        XCTAssertNotEqual(model.footnote, "Geschat uit je inleg, zonder rendement.")
        // Een punt echt verloop: de voetnoot legt uit dat het echte verloop nog begint.
        XCTAssertTrue(model.footnote?.hasPrefix("Je echte verloop begint op") ?? false)
        XCTAssertTrue(model.summary.contains("Ingelegd 3.000 euro"))
    }

    // MARK: Keuzebalk en venster

    func testWindowOptionsOnlyShowChoicesThatChangeTheView() {
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 0), [])
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 1), [])
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 2), [])
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 7), [])
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 8), [.sixMonths, .all])
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 14), [.sixMonths, .year, .all])
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 40), [.sixMonths, .year, .threeYears, .all])
        XCTAssertEqual(PortfolioWindow.options(availableMonths: -3), [])
        XCTAssertEqual(PortfolioWindow.allCases.map { $0.title }, ["6 mnd", "1 jaar", "3 jaar", "Alles"])
    }

    func testAStoredChoiceThatIsNotInTheBarFallsBackToAll() {
        XCTAssertEqual(PortfolioWindow.effective(.sixMonths, availableMonths: 3), .all)
        XCTAssertEqual(PortfolioWindow.effective(.year, availableMonths: 8), .all)
        XCTAssertEqual(PortfolioWindow.effective(.sixMonths, availableMonths: 8), .sixMonths)
        XCTAssertEqual(PortfolioWindow.effective(.threeYears, availableMonths: 40), .threeYears)
        XCTAssertEqual(PortfolioWindow.effective(.all, availableMonths: 0), .all)
        for months in [0, 1, 2, 7, 8, 14, 40] {
            let options = PortfolioWindow.options(availableMonths: months)
            for chosen in PortfolioWindow.allCases {
                let shown = PortfolioWindow.effective(chosen, availableMonths: months)
                XCTAssertTrue(options.isEmpty ? shown == .all : options.contains(shown), "\(months) maanden, keuze \(chosen)")
            }
        }
    }

    /// 22 maanden meetpunten (januari 2025 t/m oktober 2026).
    private func longHistory() -> FinanceData {
        var d = FinanceData(startMonth: YearMonth(year: 2025, month: 1))
        d.materialize(upTo: oct2026)
        let h = holding(invested: 1_000, start: YearMonth(year: 2025, month: 1))
        d.addHolding(h)
        for i in 0..<22 {
            let month = YearMonth(year: 2025, month: 1).adding(i)
            d.addSnapshot(holdingID: h.id, value: 1_000 + Double(i) * 50, invested: 1_000, date: day(month, 10))
        }
        return d
    }

    func testTheWindowCutsTheHistoryAndTheOptionsMatchWhatIsAvailable() {
        let d = longHistory()
        XCTAssertEqual(PortfolioTrend.availableMonths(d, current: oct2026, today: today), 22)
        XCTAssertEqual(PortfolioWindow.options(availableMonths: 22), [.sixMonths, .year, .all])
        func history(_ window: PortfolioWindow) -> Int {
            PortfolioTrend.model(d, window: window, current: oct2026, today: today).lines[0].points.filter { $0.kind != .projected }.count
        }
        XCTAssertEqual(history(.sixMonths), 7)
        XCTAssertEqual(history(.year), 13)
        XCTAssertEqual(history(.all), 22)
        // 3 jaar is meer dan er is: precies "Alles". Daarom staat het niet in de keuzebalk.
        XCTAssertEqual(history(.threeYears), 22)
    }

    func testAvailableMonthsIsZeroWithoutData() {
        XCTAssertEqual(PortfolioTrend.availableMonths(fresh(), current: oct2026, today: today), 0)
        XCTAssertEqual(PortfolioTrend.availableMonths(fresh([holding()]), current: oct2026, today: today), 0)
        // Een belegging met gegevens vanaf nu: een maand.
        XCTAssertEqual(PortfolioTrend.availableMonths(fresh([holding(invested: 500, start: oct2026)]), current: oct2026, today: today), 1)
    }

    // MARK: Een belegging (detailpagina)

    func testOnlyOneHoldingUsesOnlyItsOwnSeries() {
        let a = holding("A", invested: 1_000)
        let b = holding("B", invested: 5_000)
        let d = fresh([a, b])
        let both = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        let onlyA = PortfolioTrend.model(d, window: .all, current: oct2026, today: today, only: [a.id])
        XCTAssertEqual(both.lines[0].points.first?.value, 6_000)
        XCTAssertEqual(onlyA.lines[0].points.first?.value, 1_000)
        XCTAssertEqual(onlyA.title, "Waarde van deze belegging")
        XCTAssertEqual(both.title, "Waarde van je beleggingen")
    }

    func testAnEmptyHoldingOnTheDetailPageAsksForItsOwnValue() {
        let a = holding("A", invested: 1_000)
        let b = holding("B")
        let model = PortfolioTrend.model(fresh([a, b]), window: .all, current: oct2026, today: today, only: [b.id])
        XCTAssertEqual(model.empty?.action, .enterValue(b.id))
    }

    // MARK: Elke uitkomst heeft een samenvatting en een geldig domein

    func testEveryModelHasASummaryAndAValidDomain() {
        let sets: [FinanceData] = [fresh(), fresh([holding()]), fresh([holding(invested: 3_000, monthly: 200)]), longHistory()]
        for d in sets {
            for window in PortfolioWindow.allCases {
                let model = PortfolioTrend.model(d, window: window, current: oct2026, today: today)
                XCTAssertFalse(model.summary.isEmpty)
                let domain = model.domain(nonNegative: true)
                XCTAssertLessThan(domain.lowerBound, domain.upperBound)
                XCTAssertGreaterThanOrEqual(domain.lowerBound, 0)
                XCTAssertTrue(model.lines.allSatisfy { line in line.points.allSatisfy { $0.value.isFinite } })
                XCTAssertEqual(model.empty == nil, !model.lines.isEmpty)
            }
        }
    }
}
