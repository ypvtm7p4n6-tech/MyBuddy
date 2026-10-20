import XCTest
@testable import MyBuddyCore

/// De afgeleide waarde van een belegging zonder meetpunt (plan par. 5.2, C1 t/m C5, C7): `isEstimated`, het begin van de gegevens, de
/// waarde van nu die gelijk is aan "Totaal ingelegd", en de klem op 0 voor een verwachte waarde.
final class PortfolioEstimateTests: XCTestCase {
    private func base() -> FinanceData {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        return d
    }

    private func holding(invested: Double, monthly: Double = 0, start: YearMonth = aug2026, name: String = "Demo") -> Holding {
        Holding(name: name, kind: .etf, ticker: nil, units: nil, investedTotal: invested,
                expectedReturn: 0, annualCost: 0, monthlyContribution: monthly, startMonth: start)
    }

    // MARK: isEstimated

    func testStatesAndPointsAreMarkedEstimatedOnlyWithoutAMeasurement() {
        var d = base()
        let derived = holding(invested: 3_000, monthly: 200)
        d.addHolding(derived)
        XCTAssertEqual(d.holdingStateNow(derived, current: oct2026, today: day(oct2026, 15))?.isEstimated, true)
        XCTAssertEqual(d.holdingState(derived, at: oct2026, current: oct2026)?.isEstimated, true)
        // De verwachte maanden erna rekenen vanaf het afgeleide beginpunt: ook geschat, en verwacht.
        let projected = d.holdingState(derived, at: oct2026.adding(2), current: oct2026)
        XCTAssertEqual(projected?.isEstimated, true)
        XCTAssertEqual(projected?.isProjected, true)
        let series = d.portfolioSeries(from: aug2026, count: 6, current: oct2026, today: day(oct2026, 15))
        XCTAssertTrue(series.allSatisfy { $0.isEstimated })

        d.addSnapshot(holdingID: derived.id, value: 3_300, invested: 3_000, date: day(oct2026, 10))
        let real = d.holdings[0]
        XCTAssertEqual(d.holdingStateNow(real, current: oct2026, today: day(oct2026, 15))?.isEstimated, false)
        XCTAssertTrue(d.portfolioSeries(from: aug2026, count: 6, current: oct2026, today: day(oct2026, 15)).allSatisfy { !$0.isEstimated })
    }

    func testAPointIsOnlyEstimatedWhenEveryCountedHoldingIsEstimated() {
        var d = base()
        d.addHolding(holding(invested: 3_000, name: "Afgeleid"))
        d.addHolding(holding(invested: 1_000, name: "Echt"), initialValue: 1_200, now: day(oct2026, 5))
        let series = d.portfolioSeries(from: aug2026, count: 3, current: oct2026, today: day(oct2026, 15))
        // Augustus en september: alleen de afgeleide telt (geschat); oktober telt ook de echte mee.
        XCTAssertEqual(series.map { $0.isEstimated }, [true, true, false])
        XCTAssertEqual(series.last?.value ?? 0, 4_200, accuracy: 0.001)
    }

    // MARK: De waarde van nu is wat je intikte

    func testTheValueOfNowEqualsTheTypedTotalOnAnyDay() {
        var d = base()
        let h = holding(invested: 3_000, monthly: 200)
        d.addHolding(h)
        for dayNumber in [3, 14, 24, 25, 26, 31] {
            let state = d.holdingStateNow(h, current: oct2026, today: day(oct2026, dayNumber))
            XCTAssertEqual(state?.value, 3_000, "dag \(dayNumber)")
            XCTAssertEqual(state?.invested, 3_000, "dag \(dayNumber)")
        }
        // Zonder `today` is het het eind van de maand: ook dan wat je intikte.
        XCTAssertEqual(d.holdingStateNow(h, current: oct2026)?.value, 3_000)
        XCTAssertEqual(d.portfolioValue(current: oct2026, today: day(oct2026, 15)), 3_000)
        XCTAssertEqual(d.portfolioInvested(current: oct2026, today: day(oct2026, 15)), 3_000)
        XCTAssertEqual(d.portfolioGain(current: oct2026, today: day(oct2026, 15)), 0)
        XCTAssertEqual(d.valueByKind(current: oct2026, today: day(oct2026, 15)).map { $0.value }, [3_000])
    }

    func testTheSeriesGrowsByTheDepositsFromBelegdSindsAndNothingIsWrittenToTheSnapshots() {
        var d = base()
        let h = holding(invested: 3_000, monthly: 200)
        d.addHolding(h)
        let series = d.portfolioSeries(from: aug2026, count: 5, current: oct2026, today: day(oct2026, 15))
        XCTAssertEqual(series.map { $0.value }, [2_800, 3_000, 3_000, 3_200, 3_400])
        XCTAssertEqual(series.map { $0.invested }, [2_800, 3_000, 3_000, 3_200, 3_400])
        XCTAssertEqual(series.map { $0.isProjected }, [false, false, false, true, true])
        XCTAssertTrue(d.holdings[0].snapshots.isEmpty)
    }

    func testTheOpeningIsNeverNegative() {
        var d = base()
        let h = holding(invested: 100, monthly: 200)
        d.addHolding(h)
        // Meer inleg sinds "Belegd sinds" dan wat je intikte: het beginpunt is 0, niet negatief.
        let state = d.holdingStateNow(h, current: oct2026, today: day(oct2026, 26))
        XCTAssertEqual(state?.value, 400)
        XCTAssertEqual(d.portfolioSeries(from: aug2026, count: 1, current: oct2026, today: day(oct2026, 26)).first?.value, 0)
    }

    func testAPercentageContributionAloneGivesADerivedSeries() {
        var d = base()
        var h = holding(invested: 0)
        h.contributionMode = .percentage
        h.contributionPercent = 10
        d.addHolding(h)
        // 10% van het salaris (3.000): september is overgeschreven (300), oktober (de 25e) is op 15 oktober nog gepland.
        XCTAssertEqual(d.holdingStateNow(h, current: oct2026, today: day(oct2026, 15))?.value, 300)
        XCTAssertEqual(d.holdingStateNow(h, current: oct2026, today: day(oct2026, 26))?.value, 600)
    }

    func testStoredAllocationsAloneAlsoCountAsAContribution() {
        var d = base()
        let h = holding(invested: 0)
        d.addHolding(h)
        XCTAssertNil(d.holdingStateNow(h, current: oct2026, today: day(oct2026, 26)))
        var plan = d.months[sep2026.key] ?? MonthPlan()
        plan.allocations[h.id.uuidString] = 150
        d.months[sep2026.key] = plan
        XCTAssertEqual(d.holdingStateNow(h, current: oct2026, today: day(oct2026, 26))?.value, 150)
    }

    func testAHoldingWithoutAmountAndWithoutContributionStaysEmpty() {
        var d = base()
        d.addHolding(holding(invested: 0))
        XCTAssertTrue(d.portfolioSeries(from: aug2026, count: 6, current: oct2026, today: day(oct2026, 15)).isEmpty)
        XCTAssertNil(d.portfolioDataStart(current: oct2026, today: day(oct2026, 15)))
    }

    // MARK: Begin van de gegevens

    func testDataStartIsTheFirstMeasurementOrBelegdSinds() {
        var d = base()
        XCTAssertNil(d.portfolioDataStart(current: oct2026))
        let derived = holding(invested: 500, start: sep2026, name: "A")
        d.addHolding(derived)
        XCTAssertEqual(d.portfolioDataStart(current: oct2026, today: day(oct2026, 15)), sep2026)
        // Een meetpunt in augustus is eerder.
        let measured = holding(invested: 100, start: aug2026, name: "B")
        d.addHolding(measured)
        d.addSnapshot(holdingID: measured.id, value: 100, invested: 100, date: day(aug2026, 20))
        XCTAssertEqual(d.portfolioDataStart(current: oct2026, today: day(oct2026, 15)), aug2026)
        // Alleen een belegging.
        XCTAssertEqual(d.portfolioDataStart(current: oct2026, today: day(oct2026, 15), only: [derived.id]), sep2026)
        XCTAssertEqual(d.portfolioDataStart(current: oct2026, today: day(oct2026, 15), only: [measured.id]), aug2026)
        XCTAssertNil(d.portfolioDataStart(current: oct2026, today: day(oct2026, 15), only: [UUID()]))
    }

    func testAHoldingThatStartsAfterNowDoesNotCountForTheDataStart() {
        var d = base()
        d.addHolding(holding(invested: 500, start: oct2026.adding(3)))
        XCTAssertNil(d.portfolioDataStart(current: oct2026, today: day(oct2026, 15)))
        XCTAssertTrue(d.portfolioSeries(from: aug2026, count: 12, current: oct2026, today: day(oct2026, 15)).isEmpty)
    }

    // MARK: Een verwachte waarde onder 0 bestaat niet (C4)

    func testTheExpectedValueNeverGoesBelowZero() {
        var d = base()
        let h = holding(invested: 900, monthly: -300)
        d.addHolding(h)
        d.addSnapshot(holdingID: h.id, value: 1_000, invested: 900, date: day(aug2026, 15))
        let series = d.portfolioSeries(from: oct2026, count: 8, current: oct2026)
        XCTAssertEqual(series.count, 8)
        XCTAssertTrue(series.allSatisfy { $0.value >= 0 }, "\(series.map { $0.value })")
        XCTAssertEqual(series.last?.value, 0)
        XCTAssertEqual(series.map { $0.isProjected }, [false] + [Bool](repeating: true, count: 7))
    }

    // MARK: Vermogen (C7)

    func testNetWorthKnowsWhetherTheBankBalanceIsKnown() {
        var d = base()
        XCTAssertEqual(d.netWorth(at: oct2026, current: oct2026).bankKnown, false)
        XCTAssertEqual(d.netWorthNow(current: oct2026, today: day(oct2026, 15)).bankKnown, false)
        d.addBankSnapshot(balance: 1_000, date: day(oct2026, 1))
        XCTAssertEqual(d.netWorth(at: oct2026, current: oct2026).bankKnown, true)
        XCTAssertEqual(d.netWorthNow(current: oct2026, today: day(oct2026, 15)).bankKnown, true)
        let series = d.netWorthSeries(from: aug2026, count: 5, current: oct2026)
        XCTAssertEqual(series.map { $0.bankKnown }, [false, false, true, true, true])
        // Een onbekend banksaldo telt nog steeds als 0 mee.
        XCTAssertEqual(series[0].bank, 0)
    }

    func testNetWorthCountsADerivedHoldingAndTheSeriesEqualsTheSingleMonths() {
        var d = base()
        d.addHolding(holding(invested: 3_000, monthly: 200))
        d.addBankSnapshot(balance: 1_000, date: day(oct2026, 1))
        XCTAssertEqual(d.netWorth(at: oct2026, current: oct2026).investments, 3_000, accuracy: 0.001)
        let series = d.netWorthSeries(from: aug2026, count: 6, current: oct2026)
        for point in series {
            let single = d.netWorth(at: point.month, current: oct2026)
            XCTAssertEqual(point.investments, single.investments, accuracy: 0.001, point.month.key)
            XCTAssertEqual(point.total, single.total, accuracy: 0.001, point.month.key)
            XCTAssertEqual(point.bankKnown, single.bankKnown, point.month.key)
        }
    }
}
