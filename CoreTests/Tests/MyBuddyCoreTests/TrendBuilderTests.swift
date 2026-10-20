import XCTest
@testable import MyBuddyCore

/// De modelbouwers van de lijngrafieken (koers, vermogen, bank, saldo per dag, toekomstschatting, noodbuffer, spaardoel, versnellers,
/// spaarpot): elk geeft altijd een model met een samenvatting, een lege staat bij te weinig gegevens, en een geldig domein.
final class TrendBuilderTests: XCTestCase {
    private let today = day(oct2026, 15)

    private func assertValid(_ model: TrendModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(model.summary.isEmpty, "samenvatting", file: file, line: line)
        XCTAssertFalse(model.title.isEmpty, "titel", file: file, line: line)
        let domain = model.domain()
        XCTAssertLessThan(domain.lowerBound, domain.upperBound, "domein", file: file, line: line)
        XCTAssertLessThan(model.xDomain.lowerBound, model.xDomain.upperBound, "x-domein", file: file, line: line)
        XCTAssertEqual(model.empty == nil, !model.lines.isEmpty, "lege staat of lijnen", file: file, line: line)
        for item in model.lines {
            XCTAssertTrue(item.points.allSatisfy { $0.value.isFinite }, "eindige punten", file: file, line: line)
            XCTAssertEqual(Set(item.points.map { $0.id }).count, item.points.count, "unieke punt-id's", file: file, line: line)
        }
        if model.empty == nil { XCTAssertFalse(model.xTicks.isEmpty, "x-labels", file: file, line: line) }
    }

    // MARK: Koers

    private func prices(_ closes: [Double]) -> [PricePoint] {
        closes.enumerated().map { PricePoint(date: oct2026.adding(-12).firstDay.addingTimeInterval(Double($0.offset) * 86_400 * 30), close: $0.element) }
    }

    func testPriceTrendStatesLoadingFailedAndEmpty() {
        let loading = PriceTrend.model(history: [], ticker: "VWCE.DE", state: .loading)
        XCTAssertEqual(loading.empty?.isLoading, true)
        XCTAssertEqual(loading.empty?.title, "Koershistorie ophalen")
        let failed = PriceTrend.model(history: [], ticker: "VWCE.DE", state: .failed("Geen verbinding."))
        XCTAssertEqual(failed.empty?.action, .retry)
        XCTAssertEqual(failed.empty?.actionTitle, "Probeer opnieuw")
        XCTAssertTrue(failed.empty?.message.contains("Geen verbinding.") ?? false)
        let none = PriceTrend.model(history: [], ticker: "VWCE.DE", state: .loaded)
        XCTAssertEqual(none.empty?.action, .retry)
        [loading, failed, none].forEach { assertValid($0) }
    }

    func testPriceTrendWithOneAndTwoPrices() {
        let one = PriceTrend.model(history: prices([105.36]), ticker: "VWCE.DE", state: .loaded)
        XCTAssertNil(one.empty)
        XCTAssertEqual(one.lines[0].points.count, 1)
        XCTAssertNotNil(one.footnote)
        assertValid(one)
        let two = PriceTrend.model(history: prices([100.02, 105.36]), ticker: "VWCE.DE", state: .loaded)
        XCTAssertEqual(two.lines[0].segments.first?.points.count, 2)
        XCTAssertNil(two.footnote)
        XCTAssertTrue(two.summary.contains("VWCE.DE"))
        XCTAssertTrue(two.summary.contains("105,36 euro"))
        XCTAssertTrue(two.summary.contains("100,02 euro"))
        assertValid(two)
    }

    func testPriceTrendLabelsAreUniqueAndFailedStateIgnoresOldPrices() {
        let narrow = PriceTrend.model(history: prices([4.00, 4.12, 4.33]), ticker: "X", state: .loaded)
        let ticks = ChartAxis.ticks(in: narrow.domain(nonNegative: true), count: 4)
        let labels = ChartAxis.yLabels(ticks)
        XCTAssertEqual(Set(labels).count, labels.count, "\(labels)")
        // Een mislukte opvraag toont de lege staat, ook als er nog een oude reeks aan hangt.
        let failed = PriceTrend.model(history: prices([100, 101]), ticker: "X", state: .failed("Fout."))
        XCTAssertNotNil(failed.empty)
        XCTAssertTrue(failed.lines.isEmpty)
    }

    func testPriceTrendThinsALongHistoryButKeepsTheEnds() {
        let closes = (0..<400).map { 100 + Double($0) / 10 }
        let model = PriceTrend.model(history: prices(closes), ticker: "X", state: .loaded)
        let points = model.lines[0].points
        XCTAssertLessThanOrEqual(points.count, 161)
        XCTAssertEqual(points.first?.value, 100)
        XCTAssertEqual(points.last?.value ?? 0, 139.9, accuracy: 0.0001)
    }

    // MARK: Vermogen

    private func netWorthData() -> FinanceData {
        var d = makeBaseData()
        _ = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 1_000, date: day(oct2026, 1))
        d.addHolding(Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, expectedReturn: 0, annualCost: 0, startMonth: aug2026),
                     initialValue: 2_000, now: day(oct2026, 2))
        return d
    }

    func testNetWorthTrendDropsMonthsBeforeTheStartAndNotesAMissingBankBalance() {
        let d = netWorthData()
        let months = YearMonth(year: 2026, month: 5).range(count: 8)   // mei t/m december
        let model = NetWorthTrend.model(d, months: months, current: oct2026, today: today)
        XCTAssertNil(model.empty)
        // Mei t/m juli liggen vóór de startmaand (augustus): geen lege punten met 0.
        XCTAssertEqual(model.lines[0].points.count, 5)
        XCTAssertEqual(model.lines[0].points.first?.date, aug2026.firstDay)
        XCTAssertEqual(model.lines[0].points.map { $0.kind }, [.actual, .actual, .actual, .projected, .projected])
        // Het banksaldo begint pas in oktober: augustus en september tellen de bank als 0 en krijgen een noot.
        XCTAssertNotNil(model.footnote)
        XCTAssertTrue(model.footnote?.hasPrefix("Zonder banksaldo") ?? false)
        XCTAssertTrue(model.summary.contains("Vermogen aan het eind van de maand."))
        XCTAssertNotNil(model.caption)
        assertValid(model)
    }

    func testNetWorthTrendWithoutAnythingIsAnEmptyStateWithAnAction() {
        var d = FinanceData(startMonth: aug2026)
        d.materialize(upTo: oct2026)
        let model = NetWorthTrend.model(d, months: aug2026.range(count: 12), current: oct2026, today: today)
        XCTAssertEqual(model.empty?.action, .enterBankBalance)
        assertValid(model)
        XCTAssertEqual(NetWorthTrend.model(d, months: [], current: oct2026, today: today).empty?.action, .enterBankBalance)
    }

    func testNetWorthTrendPointsEqualTheEngineTotals() {
        let d = netWorthData()
        let months = aug2026.range(count: 6)
        let model = NetWorthTrend.model(d, months: months, current: oct2026, today: today)
        let series = d.netWorthSeries(from: aug2026, count: 6, current: oct2026)
        XCTAssertEqual(model.lines[0].points.map { $0.value }, series.map { $0.total })
    }

    // MARK: Bank

    func testBankTrendWithoutABalanceIsAnEmptyStateWithAnAction() {
        let d = makeBaseData()
        let model = BankTrend.model(d, current: oct2026, today: today)
        XCTAssertEqual(model.empty?.action, .enterBankBalance)
        XCTAssertEqual(model.empty?.actionTitle, "Saldo invullen")
        assertValid(model)
    }

    func testBankTrendWithABalanceIsALineWithAProjection() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 1_000, date: day(oct2026, 1))
        let model = BankTrend.model(d, current: oct2026, today: today)
        XCTAssertNil(model.empty)
        let points = model.lines[0].points
        XCTAssertGreaterThan(points.count, 2)
        XCTAssertEqual(points.filter { $0.kind == .projected }.count, 12)
        XCTAssertEqual(points.last?.date, oct2026.adding(12).firstDay)
        XCTAssertNotNil(model.caption)
        assertValid(model)
    }

    // MARK: Saldo per dag

    private func dayItems(_ values: [Double], planned: Int = 0) -> [DayChartItem] {
        values.enumerated().map { i, v in
            DayChartItem(id: day(oct2026, 15).addingTimeInterval(Double(i) * 86_400), value: v, planned: i >= values.count - planned)
        }
    }

    func testDayBalanceTrendEmptyOneDayAndManyDays() {
        let none = DayBalanceTrend.model(items: [], range: .month, focus: oct2026, today: today)
        XCTAssertEqual(none.empty?.action, .enterBankBalance)
        assertValid(none)

        let one = DayBalanceTrend.model(items: dayItems([1_000]), range: .next30, focus: oct2026, today: today)
        XCTAssertNil(one.empty)
        XCTAssertEqual(one.lines[0].points.count, 1)
        XCTAssertTrue(one.markers.isEmpty)      // een dag is een stip met tekst, geen "Laagste"
        XCTAssertEqual(one.xAxis, .days)
        XCTAssertTrue(one.caption?.hasPrefix("Saldo op") ?? false)
        assertValid(one)

        let many = DayBalanceTrend.model(items: dayItems([1_000, 800, 1_200, 900], planned: 2), range: .month, focus: oct2026, today: today)
        XCTAssertEqual(many.lines[0].points.map { $0.kind }, [.actual, .actual, .projected, .projected])
        XCTAssertEqual(many.markers.map { $0.kind }, [.low])
        XCTAssertEqual(many.markers.first?.value, 800)
        XCTAssertNotNil(many.markers.first?.date)
        XCTAssertTrue(many.summary.contains("Laagste saldo 800 euro"))
        assertValid(many)
    }

    func testDayBalanceTrendMarksZeroOnlyWhenTheBalanceGoesNegative() {
        let negative = DayBalanceTrend.model(items: dayItems([200, -50, 100]), range: .month, focus: oct2026, today: today)
        XCTAssertEqual(Set(negative.markers.map { $0.kind }), [.zero, .low])
        XCTAssertLessThan(negative.domain().lowerBound, -50)
        let flat = DayBalanceTrend.model(items: dayItems([1_000, 1_000, 1_000]), range: .month, focus: oct2026, today: today)
        XCTAssertFalse(flat.markers.contains { $0.kind == .zero })
        assertValid(flat)
        assertValid(negative)
    }

    // MARK: Toekomstschatting

    func testProjectionTrendEmptyWithoutStartAndDeposit() {
        let model = ProjectionTrend.model(start: 0, monthly: 0, annualReturn: 0.05, months: 120, unit: .years, target: 0,
                                          inflationAdjusted: false, inflation: 0.02)
        XCTAssertNotNil(model.empty)
        XCTAssertTrue(model.lines.isEmpty)
        assertValid(model)
        let nan = ProjectionTrend.model(start: .nan, monthly: 100, annualReturn: 0.05, months: 120, unit: .years, target: 0,
                                        inflationAdjusted: false, inflation: 0.02)
        XCTAssertNotNil(nan.empty)
    }

    func testProjectionTrendHasThreeScenariosWithDifferentLineStylesAndSymbols() {
        let model = ProjectionTrend.model(start: 10_000, monthly: 300, annualReturn: 0.05, months: 120, unit: .years, target: 0,
                                          inflationAdjusted: false, inflation: 0.02)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.lines.map { $0.name }, ["Voorzichtig", "Verwacht", "Optimistisch"])
        XCTAssertEqual(Set(model.lines.map { $0.dash }).count, 3)
        XCTAssertEqual(Set(model.lines.compactMap { $0.symbol }).count, 3)
        XCTAssertTrue(model.lines.allSatisfy { $0.points.count == 37 })
        XCTAssertEqual(model.xAxis, .elapsed(.years))
        // De laatste punten zijn de uitkomsten van de rekenmotor (Growth.projection), op de as in jaren.
        let expected = Growth.projection(start: 10_000, monthly: 300, annualReturn: 0.05, months: 120, inflation: 0.02).total
        XCTAssertEqual(model.lines[1].points.last?.value ?? 0, expected, accuracy: 0.01)
        XCTAssertEqual(ChartAxis.elapsedValue(model.lines[1].points.last?.date ?? Date()), 10, accuracy: 1e-6)
        XCTAssertEqual(ChartAxis.elapsedValue(model.lines[1].points.first?.date ?? Date()), 0, accuracy: 1e-6)
        XCTAssertTrue(model.includesZero)
        XCTAssertTrue(model.summary.hasPrefix("Toekomstschatting over 10 jaren."))
        XCTAssertTrue(model.summary.contains("Voorzichtig"))
        assertValid(model)
        // De as heeft eigen labels in de gekozen eenheid.
        XCTAssertEqual(model.xLabel(ChartAxis.elapsedDate(5)), "5")
    }

    func testProjectionTrendInflationLowersTheValuesAndATargetIsAMarkerWhenItFits() {
        let plain = ProjectionTrend.model(start: 10_000, monthly: 300, annualReturn: 0.05, months: 120, unit: .years, target: 60_000,
                                          inflationAdjusted: false, inflation: 0.02)
        let real = ProjectionTrend.model(start: 10_000, monthly: 300, annualReturn: 0.05, months: 120, unit: .years, target: 60_000,
                                         inflationAdjusted: true, inflation: 0.02)
        XCTAssertLessThan(real.lines[1].points.last?.value ?? 0, plain.lines[1].points.last?.value ?? 0)
        XCTAssertEqual(plain.markers.map { $0.kind }, [.goal])
        XCTAssertTrue(plain.markers[0].label.hasPrefix("Doel"))
        XCTAssertFalse(plain.markers[0].label.contains("Streefbedrag"))
        // Een doel dat veel hoger ligt dan de grafiek vlakt die niet plat: geen markering, wel een zin.
        let far = ProjectionTrend.model(start: 10_000, monthly: 300, annualReturn: 0.05, months: 120, unit: .years, target: 5_000_000,
                                        inflationAdjusted: false, inflation: 0.02)
        XCTAssertTrue(far.markers.isEmpty)
        XCTAssertNotNil(far.footnote)
        assertValid(plain)
        assertValid(real)
        assertValid(far)
    }

    func testProjectionTrendWorksForEveryUnitAndForAZeroHorizon() {
        for unit in HorizonUnit.allCases {
            for horizon in [0.0, 1, 10] {
                let model = ProjectionTrend.model(start: 1_000, monthly: 0, annualReturn: -0.05, months: unit.months(horizon), unit: unit,
                                                  target: 0, inflationAdjusted: true, inflation: 0.02)
                assertValid(model)
            }
        }
    }

    // MARK: Noodbuffer

    func testBufferTrendMarksTheMonthTheGoalIsReached() {
        let result = BufferCalc.calculate(BufferInputs(months: 3, fixedMonthly: 1_000, current: 500, monthlySaving: 250))
        XCTAssertEqual(result.target, 3_000)
        let model = BufferTrend.model(result, start: oct2026)
        XCTAssertNil(model.empty)
        XCTAssertTrue(model.includesZero)
        let n = result.monthsToFill ?? -1
        XCTAssertEqual(n, 10)
        XCTAssertEqual(model.markers.map { $0.kind }, [.goal, .reached])
        XCTAssertEqual(model.markers[1].label, "Doel bereikt in \(Fmt.month(oct2026.adding(10)))")
        XCTAssertEqual(model.markers[1].date, oct2026.adding(10).firstDay)
        XCTAssertTrue(model.summary.contains("Noodbuffer: nu 500 euro van een doel van 3.000 euro."))
        // De lijn loopt door tot na het moment waarop het doel gehaald wordt en eindigt op het laatste punt.
        XCTAssertGreaterThan(model.lines[0].points.count, 11)
        XCTAssertEqual(model.lines[0].points.first?.kind, .actual)
        assertValid(model)
    }

    func testBufferTrendWithoutATargetAlreadyFullAndNeverReached() {
        let noTarget = BufferCalc.calculate(BufferInputs(months: 3, fixedMonthly: 0, current: 500, monthlySaving: 100))
        XCTAssertNotNil(BufferTrend.model(noTarget, start: oct2026).empty)
        let full = BufferCalc.calculate(BufferInputs(months: 3, fixedMonthly: 1_000, current: 5_000, monthlySaving: 100))
        let fullModel = BufferTrend.model(full, start: oct2026)
        XCTAssertNil(fullModel.empty)
        XCTAssertEqual(fullModel.markers.count, 1)
        XCTAssertTrue(fullModel.markers[0].label.contains("al bereikt"))
        let never = BufferCalc.calculate(BufferInputs(months: 3, fixedMonthly: 1_000, current: 500, monthlySaving: 0))
        let neverModel = BufferTrend.model(never, start: oct2026)
        XCTAssertEqual(neverModel.markers.map { $0.kind }, [.goal])
        XCTAssertTrue(neverModel.summary.contains("niet binnen 100 jaar"))
        [fullModel, neverModel].forEach { assertValid($0) }
    }

    // MARK: Spaardoel

    func testSavingsGoalTrendShowsMineAndNeededAndTheGoal() {
        let plan = SavingsGoalPlan(goal: 5_000, start: 0, annualReturn: 0.02, horizonMonths: 24, monthly: 100)
        let model = SavingsGoalTrend.model(plan: plan, now: oct2026)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.lines.map { $0.name }, ["Mijn inleg", "Benodigde inleg"])
        XCTAssertEqual(model.lines[1].dash, .dashed)
        XCTAssertNotEqual(model.lines[0].symbol, model.lines[1].symbol)
        XCTAssertEqual(model.markers.map { $0.kind }, [.goal])
        XCTAssertEqual(model.markers[0].value, 5_000)
        XCTAssertTrue(model.includesZero)
        // De lijn "Benodigde inleg" haalt het doel precies aan het eind van de termijn.
        XCTAssertGreaterThanOrEqual(model.lines[1].points.last?.value ?? 0, 5_000)
        XCTAssertEqual(model.lines[1].points.last?.date, oct2026.adding(24).firstDay)
        assertValid(model)
    }

    func testSavingsGoalTrendHasOneLineWhenTheDepositIsTheNeededOne() {
        var plan = SavingsGoalPlan(goal: 5_000, start: 0, annualReturn: 0.02, horizonMonths: 24, monthly: 0)
        plan.monthly = plan.requiredMonthlyWhole
        let model = SavingsGoalTrend.model(plan: plan, now: oct2026)
        XCTAssertEqual(model.lines.map { $0.name }, ["Mijn inleg"])
        assertValid(model)
    }

    func testSavingsGoalTrendAlreadyReachedAndNoGoalAreEmptyStates() {
        let reached = SavingsGoalPlan(goal: 5_000, start: 6_000, annualReturn: 0.02, horizonMonths: 24, monthly: 100)
        XCTAssertEqual(SavingsGoalTrend.model(plan: reached, now: oct2026).empty?.title, "Je hebt dit bedrag al")
        let none = SavingsGoalPlan(goal: 0, start: 0, annualReturn: 0.02, horizonMonths: 24, monthly: 100)
        XCTAssertEqual(SavingsGoalTrend.model(plan: none, now: oct2026).empty?.title, "Nog geen doel")
        assertValid(SavingsGoalTrend.model(plan: reached, now: oct2026))
        assertValid(SavingsGoalTrend.model(plan: none, now: oct2026))
    }

    func testSavingsGoalTrendKeepsTheLastPointOfALongPlan() {
        let plan = SavingsGoalPlan(goal: 500_000, start: 0, annualReturn: 0.03, horizonMonths: 600, monthly: 400)
        let model = SavingsGoalTrend.model(plan: plan, now: oct2026)
        XCTAssertLessThanOrEqual(model.lines[0].points.count, 121)
        let expectedLast = max(plan.months, plan.chosenOutcome.months)
        XCTAssertEqual(model.lines[0].points.last?.date, oct2026.adding(expectedLast).firstDay)
        XCTAssertEqual(model.lines[0].points.first?.date, oct2026.firstDay)
        assertValid(model)
    }

    // MARK: Versnellers

    func testGoalCurveTrendKeepsTheLastPointOfEveryCurve() {
        for count in [100, 101, 406, 501] {
            let baseline = (0..<count).map { Double($0) * 100 }
            let scenario = (0..<count).map { Double($0) * 120 }
            let curves = GoalCurves(baseline: baseline, scenario: scenario, target: 40_000, scenarioTarget: 40_000)
            let model = GoalCurveTrend.model(curves: curves, goalName: "Met pensioen", start: oct2026)
            XCTAssertNil(model.empty, "\(count)")
            XCTAssertEqual(model.lines.map { $0.name }, ["Nu", "Met versnellers"])
            XCTAssertEqual(model.lines[0].points.last?.value, baseline.last, "\(count)")
            XCTAssertEqual(model.lines[1].points.last?.value, scenario.last, "\(count)")
            XCTAssertEqual(model.lines[0].points.first?.value, 0)
            XCTAssertEqual(model.lines[0].dash, .solid)
            XCTAssertEqual(model.lines[1].dash, .dashed)
            XCTAssertEqual(model.markers.map { $0.kind }, [.goal])
            assertValid(model)
        }
    }

    func testGoalCurveTrendSummaryNamesTheDurationsAndEmptyWithoutCurves() {
        let baseline = (0..<60).map { Double($0) * 100 }
        let scenario = (0..<60).map { Double($0) * 200 }
        let curves = GoalCurves(baseline: baseline, scenario: scenario, target: 5_000, scenarioTarget: 5_000)
        let model = GoalCurveTrend.model(curves: curves, goalName: "Auto", start: oct2026)
        XCTAssertTrue(model.summary.contains("Auto: zonder versnellers 4 jaar en 2 maanden, met je keuze 2 jaar en 1 maand"), model.summary)
        let empty = GoalCurveTrend.model(curves: GoalCurves(baseline: [], scenario: [], target: 1, scenarioTarget: 1), goalName: "", start: oct2026)
        XCTAssertNotNil(empty.empty)
        assertValid(empty)
        // Een doel dat niet gehaald wordt binnen de grafiek.
        let far = GoalCurveTrend.model(curves: GoalCurves(baseline: baseline, scenario: scenario, target: 1e9, scenarioTarget: 1e9),
                                       goalName: "X", start: oct2026)
        XCTAssertTrue(far.summary.contains("niet binnen de grafiek"))
        XCTAssertEqual(GoalCurveTrend.monthsToReach([0, 5, 10], target: 5), 1)
        XCTAssertNil(GoalCurveTrend.monthsToReach([0, 5], target: 10))
    }

    // MARK: Spaarpot

    func testPotTrendIsEmptyWithoutBookingsAndShowsTheBalanceWithThem() {
        var d = makeBaseData()
        let empty = Pot(name: "Leeg", monthlyContribution: 0, startMonth: aug2026)
        d.addPot(empty)
        d.materialize(upTo: oct2026)
        let none = PotTrend.model(d, potID: empty.id, current: oct2026, today: today)
        XCTAssertEqual(none.empty?.title, "Nog geen verloop")
        assertValid(none)

        let pot = addBufferPot(&d, opening: 500, goal: 2_000)
        d.materialize(upTo: oct2026)
        let model = PotTrend.model(d, potID: pot.id, current: oct2026, today: today)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.title, "Saldo van Buffer")
        // Vanaf de startmaand van de pot (augustus), tot een jaar vooruit.
        XCTAssertEqual(model.lines[0].points.first?.date, aug2026.firstDay)
        XCTAssertEqual(model.lines[0].points.last?.date, oct2026.adding(12).firstDay)
        XCTAssertEqual(model.lines[0].points.filter { $0.kind == .projected }.count, 12)
        // De lopende maand toont het saldo van nu (zoals de pagina van de pot).
        let nowPoint = model.lines[0].points.first { $0.date == oct2026.firstDay }
        XCTAssertEqual(nowPoint?.value ?? 0, d.potBalanceNow(pot.id, current: oct2026, today: today), accuracy: 0.001)
        XCTAssertTrue(model.markers.contains { $0.kind == .goal && $0.value == 2_000 })
        XCTAssertTrue(model.summary.contains("Doel 2.000 euro"))
        XCTAssertTrue(model.summary.contains("Doel bereikt in"))
        assertValid(model)
    }

    func testPotTrendWithoutAGoalHasNoMarkersAndAnUnknownPotIsAnEmptyState() {
        var d = makeBaseData()
        let pot = addBufferPot(&d, opening: 500, goal: nil)
        d.materialize(upTo: oct2026)
        let model = PotTrend.model(d, potID: pot.id, current: oct2026, today: today)
        XCTAssertTrue(model.markers.isEmpty)
        assertValid(model)
        let unknown = PotTrend.model(d, potID: UUID(), current: oct2026, today: today)
        XCTAssertNotNil(unknown.empty)
        assertValid(unknown)
    }
}
