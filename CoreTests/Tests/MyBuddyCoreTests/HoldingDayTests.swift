import XCTest
@testable import MyBuddyCore

/// De waarde van beleggingen "nu" rekent per KALENDERDAG, zoals de bank en de spaarpotten: een inleg telt pas mee vanaf de dag
/// waarop hij wordt overgeschreven (dezelfde dag als in de dagboekhouding), en dan de hele dag. De waarde aan het eind van de
/// maand (zonder `today`) blijft de basis voor prognoses en grafieken.
final class HoldingDayTests: XCTestCase {
    /// ETF met een meetpunt op 15 augustus (waarde 1000, ingelegd 900) en 200 inleg per maand op de 25e.
    private func makeData(transferDay: Int? = 25, monthly: Double = 200) -> (FinanceData, Holding) {
        var d = makeBaseData()
        var h = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                        expectedReturn: 0.06, annualCost: 0, monthlyContribution: monthly, startMonth: aug2026)
        h.transferDay = transferDay
        d.addHolding(h)
        d.addSnapshot(holdingID: h.id, value: 1000, invested: 900, date: day(aug2026, 15))
        d.materialize(upTo: oct2026)
        return (d, d.holdings[0])
    }

    private func now(_ d: FinanceData, _ h: Holding, _ today: Date, current: YearMonth = oct2026) -> HoldingState? {
        d.holdingStateNow(h, current: current, today: today)
    }

    // MARK: Een inleg telt vanaf zijn overschrijfdag

    func testDepositCountsFromItsTransferDayAndNotBefore() {
        let (d, h) = makeData()
        // Het eind van de maand heeft de hele inleg van oktober al (de basis voor prognoses): 1000 + 200 (sep) + 200 (okt).
        XCTAssertEqual(engCents(d.holdingStateNow(h, current: oct2026)?.value ?? 0), 140_000)
        XCTAssertEqual(engCents(d.holdingStateNow(h, current: oct2026)?.invested ?? 0), 130_000)

        // Op 14 oktober is de inleg van de 25e nog niet overgeschreven: het geld staat nog op de rekening.
        let early = now(d, h, day(oct2026, 14))
        XCTAssertEqual(engCents(early?.value ?? 0), 120_000)
        XCTAssertEqual(engCents(early?.invested ?? 0), 110_000)
        XCTAssertEqual(early?.isProjected, false)

        // De dag ervoor (laat op de avond) nog niet, en op de dag zelf de hele dag wel, ook 's ochtends.
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 24, hour: 23.9))?.value ?? 0), 120_000)
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 25, hour: 0.1))?.value ?? 0), 140_000)
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 25, hour: 8))?.value ?? 0), 140_000)
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 31, hour: 23))?.value ?? 0), 140_000)
    }

    func testDefaultTransferDayIsTheSalaryDay() {
        // Zonder eigen overschrijfdag geldt de salarisdag (zoals in de dagboekhouding).
        var (d, h) = makeData(transferDay: nil)
        d.salary.payDay = 20
        h = d.holdings[0]
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 19, hour: 12))?.value ?? 0), 120_000)
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 20, hour: 6))?.value ?? 0), 140_000)
    }

    func testOwnTransferDayOfAMonthIsRespected() {
        var (d, h) = makeData()
        d.editPlan(oct2026) { $0.transferDay = 5 }
        h = d.holdings[0]
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 4, hour: 12))?.value ?? 0), 120_000)
        XCTAssertEqual(engCents(now(d, h, engTime(oct2026, 5, hour: 12))?.value ?? 0), 140_000)
    }

    func testDay31IsTheLastDayOfAShortMonth() {
        let (d, h) = makeData(transferDay: 31)
        let nov = YearMonth(year: 2026, month: 11)
        // 1000 + sep + okt = 1400; november komt op de laatste dag (30 november) bij.
        XCTAssertEqual(engCents(now(d, h, engTime(nov, 29, hour: 12), current: nov)?.value ?? 0), 140_000)
        XCTAssertEqual(engCents(now(d, h, engTime(nov, 30, hour: 8), current: nov)?.value ?? 0), 160_000)
    }

    // MARK: Gelijk aan de dagboekhouding

    func testInvestedGrowsExactlyWithTheLedgerEveryDayOfTheMonth() {
        let (d, h) = makeData(transferDay: 17)
        let start = d.holdingState(h, at: sep2026, current: oct2026)?.invested ?? 0
        for dayNumber in 1...31 {
            let today = engTime(oct2026, dayNumber, hour: 9)
            let ledger = d.monthLedger(oct2026, asOf: today)
            let transferred = ledger.days.filter { $0.day <= dayNumber }.reduce(0) { $0 + engCents($1.toHoldings) }
            let invested = now(d, h, today)?.invested ?? 0
            XCTAssertEqual(engCents(invested) - engCents(start), transferred, "dag \(dayNumber)")
            let value = now(d, h, today)?.value ?? 0
            XCTAssertEqual(engCents(value), engCents(invested) + 10_000, "dag \(dayNumber): waarde = ingelegd + rendement van het meetpunt")
        }
    }

    func testPercentageDepositIsTheSameAmountAsInTheLedger() {
        var (d, h) = makeData()
        d.setContributionPercent(h.id, percent: 10, basis: .salary, current: oct2026)
        h = d.holdings[0]
        let after = now(d, h, day(oct2026, 25))
        let before = now(d, h, day(oct2026, 24))
        let ledger = d.monthLedger(oct2026, asOf: day(oct2026, 25))
        let transferred = ledger.days.filter { $0.day == 25 }.reduce(0) { $0 + engCents($1.toHoldings) }
        XCTAssertGreaterThan(transferred, 0)
        XCTAssertEqual(engCents(after?.invested ?? 0) - engCents(before?.invested ?? 0), transferred)
    }

    // MARK: Het meetpunt van de lopende maand

    func testASnapshotInTheCurrentMonthReplacesTheMonthsDepositForNowAndMonthEnd() {
        var (d, h) = makeData()
        d.addSnapshot(holdingID: h.id, value: 1500, invested: 1200, date: day(oct2026, 3))
        h = d.holdings[0]
        // Het meetpunt van 3 oktober is wat je zelf hebt gemeten: de inleg van oktober komt er niet nog eens bij.
        XCTAssertEqual(engCents(d.holdingStateNow(h, current: oct2026)?.value ?? 0), 150_000)
        XCTAssertEqual(engCents(now(d, h, day(oct2026, 14))?.value ?? 0), 150_000)
        XCTAssertEqual(engCents(now(d, h, day(oct2026, 28))?.value ?? 0), 150_000)
    }

    // MARK: Andere maand dan vandaag

    func testWhenTodayIsNotInTheCurrentMonthTheMonthEndCounts() {
        let (d, h) = makeData()
        let nov = YearMonth(year: 2026, month: 11)
        let monthEnd = d.holdingStateNow(h, current: oct2026)
        // "Nu" ligt in november terwijl de gevraagde maand oktober is: er is geen dag binnen de maand, dus het eind van de maand.
        XCTAssertEqual(now(d, h, day(nov, 3), current: oct2026), monthEnd)
        XCTAssertEqual(now(d, h, day(YearMonth(year: 2026, month: 9), 3), current: oct2026), monthEnd)
    }

    func testOnTheLastDayNowEqualsTheMonthEnd() {
        let (d, h) = makeData()
        XCTAssertEqual(now(d, h, engTime(oct2026, 31, hour: 20)), d.holdingStateNow(h, current: oct2026))
    }

    // MARK: Portefeuille, grafiek en soorten

    func testPortfolioFunctionsAgreeWithTheHoldingNow() {
        var d = makeBaseData()
        var etf = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                          expectedReturn: 0.06, annualCost: 0, monthlyContribution: 200, startMonth: aug2026)
        etf.transferDay = 25
        var crypto = Holding(name: "BTC", kind: .crypto, ticker: nil, units: nil, investedTotal: 0,
                             expectedReturn: 0.1, annualCost: 0, monthlyContribution: 50, startMonth: aug2026)
        crypto.transferDay = 10
        d.addHolding(etf)
        d.addHolding(crypto)
        d.addSnapshot(holdingID: etf.id, value: 1000, invested: 900, date: day(aug2026, 15))
        d.addSnapshot(holdingID: crypto.id, value: 300, invested: 250, date: day(aug2026, 20))
        d.materialize(upTo: oct2026)
        let today = day(oct2026, 14)

        // ETF: 1000 + 200 (sep); de inleg van de 25e komt nog. BTC: 300 + 50 (sep) + 50 (okt, de 10e is voorbij).
        let etfNow = d.holdingStateNow(d.holding(etf.id)!, current: oct2026, today: today)
        let btcNow = d.holdingStateNow(d.holding(crypto.id)!, current: oct2026, today: today)
        XCTAssertEqual(engCents(etfNow?.value ?? 0), 120_000)
        XCTAssertEqual(engCents(etfNow?.invested ?? 0), 110_000)
        XCTAssertEqual(engCents(btcNow?.value ?? 0), 40_000)
        XCTAssertEqual(engCents(btcNow?.invested ?? 0), 35_000)

        XCTAssertEqual(engCents(d.portfolioValue(current: oct2026, today: today)), 160_000)
        XCTAssertEqual(engCents(d.portfolioInvested(current: oct2026, today: today)), 145_000)
        XCTAssertEqual(engCents(d.portfolioGain(current: oct2026, today: today)), 15_000)
        let slices = d.valueByKind(current: oct2026, today: today)
        XCTAssertEqual(slices.reduce(0) { $0 + engCents($1.value) }, 160_000)
        XCTAssertEqual(slices.map(\.kind), [.etf, .crypto])

        // Het eind van de maand heeft de inleg van de 25e er wel in: 1400 + 400.
        XCTAssertEqual(engCents(d.portfolioValue(current: oct2026)), 180_000)
        XCTAssertEqual(engCents(d.portfolioInvested(current: oct2026)), 165_000)
    }

    func testSeriesCurrentPointIsTheValueNowAndTheProjectionStartsFromTheMonthEnd() {
        let (d, h) = makeData()
        let today = day(oct2026, 14)
        let nov = YearMonth(year: 2026, month: 11)

        let monthEnd = d.portfolioSeries(from: sep2026, count: 3, current: oct2026)
        let dayBased = d.portfolioSeries(from: sep2026, count: 3, current: oct2026, today: today)
        XCTAssertEqual(monthEnd.map(\.month), [sep2026, oct2026, nov])
        XCTAssertEqual(dayBased.map(\.month), [sep2026, oct2026, nov])

        // September is voorbij en november komt na het eind van oktober: die twee punten veranderen niet.
        XCTAssertEqual(dayBased[0], monthEnd[0])
        XCTAssertEqual(dayBased[2], monthEnd[2])
        // De lopende maand is de waarde van nu.
        XCTAssertEqual(engCents(dayBased[1].value), 120_000)
        XCTAssertEqual(engCents(monthEnd[1].value), 140_000)
        XCTAssertEqual(dayBased[1].value, d.portfolioValue(current: oct2026, today: today))
        XCTAssertEqual(dayBased[1].invested, d.portfolioInvested(current: oct2026, today: today))
        XCTAssertEqual(d.holdingStateNow(h, current: oct2026, today: today)?.value, dayBased[1].value)
        XCTAssertFalse(dayBased[1].isProjected)
        XCTAssertTrue(dayBased[2].isProjected)
    }

    // MARK: Doelen uit beleggingen

    /// Een doel dat uit de beleggingen komt begint bij wat je nu hebt (dezelfde waarde als op Home en bij Beleggingen), niet bij
    /// het eind van de maand: de inleg van de 25e zit dan in de maandinleg en telt niet twee keer.
    func testPortfolioGoalStartsAtTheValueOfToday() {
        var (d, _) = makeData()
        var goal = LifeGoal(name: "Later", kind: .custom)
        goal.targetAmount = 50_000
        goal.inflationAdjusted = false
        goal.funding = .portfolio
        d.addGoal(goal)

        let early = d.goalInputs(for: goal, current: oct2026, today: day(oct2026, 14))
        XCTAssertEqual(engCents(early.start), 120_000)
        XCTAssertEqual(early.start, d.portfolioValue(current: oct2026, today: day(oct2026, 14)))

        // Na de overschrijfdag zit de inleg in de waarde van nu.
        let late = d.goalInputs(for: goal, current: oct2026, today: day(oct2026, 26))
        XCTAssertEqual(engCents(late.start), 140_000)

        // Valt "nu" niet in de maand, dan is het het eind van die maand.
        let other = d.goalInputs(for: goal, current: oct2026, today: day(YearMonth(year: 2026, month: 12), 1))
        XCTAssertEqual(other.start, d.portfolioValue(current: oct2026))
    }

    func testWithoutADepositTodayChangesNothing() {
        let (d, h) = makeData(monthly: 0)
        XCTAssertEqual(now(d, h, day(oct2026, 3)), d.holdingStateNow(h, current: oct2026))
        XCTAssertEqual(d.portfolioValue(current: oct2026, today: day(oct2026, 3)), d.portfolioValue(current: oct2026))
    }

    func testHoldingWithoutMeasurementHasNoStateNow() {
        var d = makeBaseData()
        let h = Holding(name: "Leeg", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                        expectedReturn: 0.06, annualCost: 0, monthlyContribution: 100, startMonth: aug2026)
        d.addHolding(h)
        XCTAssertNil(d.holdingStateNow(h, current: oct2026, today: day(oct2026, 14)))
        XCTAssertEqual(d.portfolioValue(current: oct2026, today: day(oct2026, 14)), 0)
        XCTAssertTrue(d.valueByKind(current: oct2026, today: day(oct2026, 14)).isEmpty)
    }

    // MARK: Veel combinaties

    func testNowNeverExceedsTheMonthEndAndIsMonotonicOverTheMonth() {
        for transferDay in [1, 2, 9, 15, 25, 28, 31] {
            let (d, h) = makeData(transferDay: transferDay)
            let monthEnd = d.holdingStateNow(h, current: oct2026)?.value ?? 0
            var previous = -Double.infinity
            for dayNumber in 1...31 {
                let value = now(d, h, engTime(oct2026, dayNumber, hour: 13))?.value ?? 0
                XCTAssertLessThanOrEqual(value, monthEnd + 0.001, "dag \(dayNumber), overschrijfdag \(transferDay)")
                XCTAssertGreaterThanOrEqual(value, previous - 0.001, "dag \(dayNumber), overschrijfdag \(transferDay)")
                previous = value
            }
            XCTAssertEqual(engCents(previous), engCents(monthEnd), "overschrijfdag \(transferDay)")
        }
    }
}
