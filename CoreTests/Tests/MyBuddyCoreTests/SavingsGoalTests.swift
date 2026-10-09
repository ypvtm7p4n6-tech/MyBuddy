import XCTest
@testable import MyBuddyCore

/// Verwachte waarden zijn onafhankelijk berekend in Python.
final class SavingsGoalTests: XCTestCase {
    /// Standaard: doel 10.000, start 1.000, 6% per jaar, 24 maanden, eigen inleg 200.
    private func makePlan(goal: Double = 10_000, start: Double = 1_000, rate: Double = 0.06, months: Int = 24,
                          monthly: Double = 200, inflation: Double = 0.02, real: Bool = false) -> SavingsGoalPlan {
        SavingsGoalPlan(goal: goal, start: start, annualReturn: rate, horizonMonths: months, monthly: monthly,
                        inflation: inflation, realTerms: real)
    }

    // MARK: Hoeveel per maand?

    func testRequiredMonthlyKnownValue() {
        let p = makePlan()
        XCTAssertEqual(p.requiredMonthly, 349.57, accuracy: 0.001)
        XCTAssertEqual(p.months, 24)
        XCTAssertEqual(p.deadlineMonth(from: oct2026), YearMonth(year: 2028, month: 10))
    }

    func testRequiredMonthlyRoundTripWithFutureValue() {
        let p = makePlan()
        let fv = Growth.futureValue(start: 1_000, monthly: p.requiredMonthly, annualReturn: 0.06, months: 24)
        XCTAssertEqual(fv, 10_000, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(fv, 10_000)

        // De uitkomst naast het getoonde bedrag rekent met de hele euro's (350), niet met 349,57.
        let o = p.requiredOutcome
        XCTAssertEqual(o.months, 24)
        XCTAssertEqual(o.monthly, 350, accuracy: 0.001)
        XCTAssertEqual(o.balance, 10_011.03, accuracy: 0.011)
        XCTAssertEqual(o.deposited, 9_400, accuracy: 0.011)
        XCTAssertEqual(o.interest, 611.03, accuracy: 0.011)
        XCTAssertGreaterThanOrEqual(o.balance, 10_000)
    }

    func testRequiredMonthlyAlwaysReachesTheGoalOnTime() {
        // Afgerond op centen is het 204,40, maar daarmee ben je pas na 25 maanden klaar.
        XCTAssertEqual(Growth.requiredMonthly(target: 5_000, start: 0, annualReturn: 0.02, months: 24), 204.40, accuracy: 0.001)
        XCTAssertEqual(Growth.monthsToReach(target: 5_000, start: 0, monthly: 204.40, annualReturn: 0.02), 25)

        let p = makePlan(goal: 5_000, start: 0, rate: 0.02, months: 24, monthly: 0)
        XCTAssertEqual(p.requiredMonthly, 204.41, accuracy: 0.001)
        XCTAssertEqual(Growth.monthsToReach(target: 5_000, start: 0, monthly: p.requiredMonthly, annualReturn: 0.02), 24)

        // Zelfde bij een andere combinatie: 195,00 haalt het pas na 37 maanden.
        let q = makePlan(goal: 8_000, start: 500, rate: 0.04, months: 36, monthly: 0)
        XCTAssertEqual(q.requiredMonthly, 195.01, accuracy: 0.001)
        XCTAssertEqual(Growth.monthsToReach(target: 8_000, start: 500, monthly: q.requiredMonthly, annualReturn: 0.04), 36)
    }

    func testShortfallAgainstRequired() {
        XCTAssertEqual(makePlan(monthly: 200).shortfallMonthly, 149.57, accuracy: 0.001)
        XCTAssertEqual(makePlan(monthly: 400).shortfallMonthly, 0, accuracy: 0.001)
    }

    // MARK: Wanneer klaar?

    func testMonthsToGoalWithOwnDeposit() {
        let p = makePlan(monthly: 200)
        XCTAssertEqual(p.monthsToGoal, 40)
        XCTAssertEqual(p.reachMonth(from: oct2026), YearMonth(year: 2030, month: 2))
        XCTAssertFalse(p.isOnTrack)

        let o = p.chosenOutcome
        XCTAssertEqual(o.months, 40)
        XCTAssertEqual(o.balance, 10_022.71, accuracy: 0.011)
        XCTAssertEqual(o.deposited, 9_000, accuracy: 0.011)
        XCTAssertEqual(o.interest, 1_022.71, accuracy: 0.011)
        XCTAssertGreaterThanOrEqual(o.balance, 10_000)
    }

    func testOnTrackWhenDepositIsEnough() {
        XCTAssertEqual(makePlan(monthly: 350).monthsToGoal, 24)
        XCTAssertTrue(makePlan(monthly: 350).isOnTrack)
        XCTAssertTrue(makePlan(monthly: 349.57).isOnTrack)
        XCTAssertFalse(makePlan(monthly: 349.56).isOnTrack)
        XCTAssertEqual(makePlan(monthly: 349.56).monthsToGoal, 25)
    }

    func testAlreadyReached() {
        let p = makePlan(goal: 500, start: 1_000, monthly: 0)
        XCTAssertTrue(p.isReached)
        XCTAssertEqual(p.monthsToGoal, 0)
        XCTAssertEqual(p.requiredMonthly, 0, accuracy: 0.001)
        XCTAssertTrue(p.isOnTrack)
        XCTAssertEqual(p.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(p.reachMonth(from: oct2026), oct2026)
        XCTAssertTrue(p.yearRows(monthly: 0, months: 0).isEmpty)
    }

    func testProgress() {
        XCTAssertEqual(makePlan(goal: 10_000, start: 2_500).progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(makePlan(goal: 0, start: 100).progress, 0, accuracy: 0.0001)
    }

    // MARK: Zonder rente

    func testZeroInterestCase() {
        let p = makePlan(goal: 12_000, start: 0, rate: 0, months: 24, monthly: 500)
        XCTAssertEqual(p.requiredMonthly, 500, accuracy: 0.001)
        XCTAssertEqual(p.monthsToGoal, 24)
        XCTAssertTrue(p.isOnTrack)
        XCTAssertEqual(makePlan(goal: 12_000, start: 0, rate: 0, months: 24, monthly: 250).monthsToGoal, 48)

        let rows = p.yearRows(monthly: 500, months: 24)
        XCTAssertEqual(rows.map { $0.months }, [12, 24])
        XCTAssertEqual(rows[0].balance, 6_000, accuracy: 0.001)
        XCTAssertEqual(rows[1].balance, 12_000, accuracy: 0.001)
        XCTAssertEqual(rows[0].interest, 0, accuracy: 0.001)
        XCTAssertEqual(rows[1].interest, 0, accuracy: 0.001)
        XCTAssertEqual(p.chosenOutcome.interest, 0, accuracy: 0.001)
    }

    // MARK: Inflatie

    func testInflationUsesRealReturn() {
        let nominal = makePlan(monthly: 200)
        XCTAssertEqual(nominal.effectiveReturn, 0.06, accuracy: 1e-9)
        XCTAssertEqual(nominal.requiredMonthly, 349.57, accuracy: 0.001)
        XCTAssertEqual(nominal.monthsToGoal, 40)

        let real = makePlan(monthly: 200, real: true)
        XCTAssertEqual(real.effectiveReturn, 0.0392157, accuracy: 0.000001)
        XCTAssertEqual(real.requiredMonthly, 358.13, accuracy: 0.001)
        XCTAssertEqual(real.monthsToGoal, 42)
        XCTAssertGreaterThan(real.requiredMonthly, nominal.requiredMonthly)
    }

    func testInflationIsIgnoredWhenSwitchedOff() {
        let a = makePlan(inflation: 0.02, real: false)
        let b = makePlan(inflation: 0.10, real: false)
        XCTAssertEqual(a.requiredMonthly, b.requiredMonthly, accuracy: 0.0001)
    }

    func testNegativeRealReturnGivesNegativeInterest() {
        let p = makePlan(goal: 5_000, start: 0, rate: 0.01, months: 24, monthly: 200, inflation: 0.03, real: true)
        XCTAssertLessThan(p.effectiveReturn, 0)
        XCTAssertEqual(p.monthsToGoal, 26)
        let o = p.chosenOutcome
        XCTAssertEqual(o.balance, 5_095.25, accuracy: 0.011)
        XCTAssertEqual(o.deposited, 5_200, accuracy: 0.011)
        XCTAssertEqual(o.interest, -104.75, accuracy: 0.011)
        // Afgerond is het 212,27, maar dat is net te weinig voor 24 maanden.
        XCTAssertEqual(p.requiredMonthly, 212.28, accuracy: 0.001)
    }

    // MARK: Tabel per jaar

    func testYearRowsWithPartialLastYear() {
        let p = makePlan(goal: 20_000, start: 1_000, rate: 0.05, months: 30, monthly: 200)
        let rows = p.yearRows(monthly: 200, months: 30)
        XCTAssertEqual(rows.map { $0.months }, [12, 24, 30])
        XCTAssertEqual(rows.map { $0.year }, [1, 2, 3])
        XCTAssertEqual(rows.map { $0.isFullYear }, [true, true, false])

        let balances = [3_504.52, 6_134.26, 7_498.03]
        let deposits = [3_400.0, 5_800.0, 7_000.0]
        let interests = [104.52, 334.26, 498.03]
        XCTAssertEqual(rows.count, 3)
        for (i, row) in rows.enumerated() {
            XCTAssertEqual(row.balance, balances[i], accuracy: 0.011)
            XCTAssertEqual(row.deposited, deposits[i], accuracy: 0.011)
            XCTAssertEqual(row.interest, interests[i], accuracy: 0.011)
            // Saldo = ingelegd + rente.
            XCTAssertEqual(row.balance, row.deposited + row.interest, accuracy: 0.011)
        }
        // De laatste rij is precies de uitkomst na 30 maanden.
        XCTAssertEqual(rows[2].balance, p.outcome(monthly: 200, months: 30).balance, accuracy: 0.0001)
    }

    func testYearRowsWholeYearsAndShortPeriods() {
        let p = makePlan(goal: 5_000, start: 500, rate: 0.03, months: 24, monthly: 100)
        let rows = p.yearRows(monthly: 100, months: 24)
        XCTAssertEqual(rows.map { $0.months }, [12, 24])
        XCTAssertEqual(rows[0].balance, 1_731.41, accuracy: 0.011)
        XCTAssertEqual(rows[1].balance, 2_999.77, accuracy: 0.011)
        XCTAssertEqual(rows[0].deposited, 1_700, accuracy: 0.011)
        XCTAssertEqual(rows[1].deposited, 2_900, accuracy: 0.011)
        XCTAssertEqual(rows[1].interest, 99.77, accuracy: 0.011)

        let short = p.yearRows(monthly: 100, months: 8)
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short[0].months, 8)
        XCTAssertEqual(short[0].year, 1)
        XCTAssertFalse(short[0].isFullYear)
        XCTAssertEqual(short[0].balance, 1_316.89, accuracy: 0.011)
        XCTAssertEqual(short[0].interest, 16.89, accuracy: 0.011)

        XCTAssertTrue(p.yearRows(monthly: 100, months: 0).isEmpty)
        XCTAssertTrue(p.yearRows(monthly: 100, months: -5).isEmpty)
    }

    func testSeriesMatchesFutureValue() {
        let p = makePlan(monthly: 200)
        let s = p.series(monthly: 200, months: 40)
        XCTAssertEqual(s.count, 41)
        XCTAssertEqual(s[0], 1_000, accuracy: 0.0001)
        XCTAssertEqual(s[40], 10_022.71, accuracy: 0.011)
        XCTAssertEqual(s[40], Growth.futureValue(start: 1_000, monthly: 200, annualReturn: 0.06, months: 40), accuracy: 0.0001)
        XCTAssertEqual(p.series(monthly: 200, months: 0).count, 1)
        XCTAssertEqual(p.series(monthly: 200, months: -3).count, 1)
    }

    // MARK: Niet haalbaar

    func testUnreachableWithinHundredYears() {
        let p = makePlan(goal: 10_000, start: 0, rate: 0.05, months: 24, monthly: 0)
        XCTAssertNil(p.monthsToGoal)
        XCTAssertNil(p.reachMonth(from: oct2026))
        XCTAssertFalse(p.isOnTrack)
        XCTAssertEqual(p.requiredMonthly, 397.48, accuracy: 0.001)

        // Zonder haalbare uitkomst rekent het scenario "mijn inleg" tot het einde van de termijn.
        let o = p.chosenOutcome
        XCTAssertEqual(o.months, 24)
        XCTAssertEqual(o.balance, 0, accuracy: 0.001)

        let slow = makePlan(goal: 100_000, start: 0, rate: 0, months: 24, monthly: 5)
        XCTAssertNil(slow.monthsToGoal)
    }

    // MARK: Wat als?

    func testWhatIfMonthsSaved() {
        let p = makePlan(monthly: 200)
        XCTAssertEqual(p.monthsToGoal, 40)

        let a = p.whatIf(extra: 25)
        XCTAssertEqual(a.months, 36)
        XCTAssertEqual(a.monthsSaved, 4)
        XCTAssertFalse(a.becomesReachable)

        let b = p.whatIf(extra: 50)
        XCTAssertEqual(b.months, 33)
        XCTAssertEqual(b.monthsSaved, 7)

        let c = p.whatIf(extra: 100)
        XCTAssertEqual(c.months, 28)
        XCTAssertEqual(c.monthsSaved, 12)
    }

    func testWhatIfButtons() {
        let list = makePlan(monthly: 200).whatIfs
        XCTAssertEqual(list.map { $0.extra }, [25, 50, 100])
        XCTAssertEqual(list.map { $0.monthsSaved }, [4, 7, 12])
        XCTAssertEqual(list.map { $0.id }, [25, 50, 100])
    }

    func testWhatIfMakesUnreachableGoalReachable() {
        let p = makePlan(goal: 10_000, start: 0, rate: 0, months: 24, monthly: 0)
        XCTAssertNil(p.monthsToGoal)
        let w = p.whatIf(extra: 25)
        XCTAssertEqual(w.months, 400)
        XCTAssertNil(w.monthsSaved)
        XCTAssertTrue(w.becomesReachable)
        XCTAssertEqual(p.whatIf(extra: 100).months, 100)
    }

    func testWhatIfIgnoresNegativeExtra() {
        let p = makePlan(monthly: 200)
        let w = p.whatIf(extra: -50)
        XCTAssertEqual(w.extra, 0, accuracy: 0.0001)
        XCTAssertEqual(w.months, 40)
        XCTAssertEqual(w.monthsSaved, 0)
        XCTAssertFalse(w.becomesReachable)
    }

    // MARK: Keuzes en hulpfuncties

    func testRatePresets() {
        XCTAssertEqual(SavingsRatePreset.allCases.count, 4)
        XCTAssertEqual(SavingsRatePreset.savings.rate(savingsRate: 0.015, customRate: 0.045), 0.015, accuracy: 1e-12)
        XCTAssertEqual(SavingsRatePreset.bonds.rate(savingsRate: 0.015, customRate: 0.045), 0.03, accuracy: 1e-12)
        XCTAssertEqual(SavingsRatePreset.equities.rate(savingsRate: 0.015, customRate: 0.045), 0.06, accuracy: 1e-12)
        XCTAssertEqual(SavingsRatePreset.custom.rate(savingsRate: 0.015, customRate: 0.045), 0.045, accuracy: 1e-12)
        XCTAssertEqual(Set(SavingsRatePreset.allCases.map { $0.id }).count, 4)
    }

    func testPeriodUnit() {
        XCTAssertEqual(SavingsGoalPeriodUnit.years.monthCount(2), 24)
        XCTAssertEqual(SavingsGoalPeriodUnit.years.monthCount(2.5), 30)
        XCTAssertEqual(SavingsGoalPeriodUnit.months.monthCount(18), 18)
        XCTAssertEqual(SavingsGoalPeriodUnit.months.monthCount(17.6), 18)
        XCTAssertEqual(SavingsGoalPeriodUnit.months.monthCount(-4), 0)
        XCTAssertEqual(SavingsGoalPeriodUnit.years.monthCount(Double.nan), 0)
        XCTAssertEqual(SavingsGoalPeriodUnit.years.monthCount(Double.infinity), 0)
        XCTAssertEqual(SavingsGoalPeriodUnit.years.monthCount(1e12), 100_000)
    }

    func testMonthsUntilDate() {
        XCTAssertEqual(SavingsGoalPlan.monthsUntil(day(YearMonth(year: 2028, month: 10), 15), from: oct2026), 24)
        XCTAssertEqual(SavingsGoalPlan.monthsUntil(day(YearMonth(year: 2027, month: 1), 1), from: oct2026), 3)
        XCTAssertEqual(SavingsGoalPlan.monthsUntil(day(oct2026, 20), from: oct2026), 0)
        XCTAssertEqual(SavingsGoalPlan.monthsUntil(day(aug2026, 5), from: oct2026), 0)
    }

    func testExampleDefaults() {
        let p = SavingsGoalPlan.example(savingsRate: 0.02, inflation: 0.025)
        XCTAssertEqual(p.goal, 5_000, accuracy: 0.001)
        XCTAssertEqual(p.start, 0, accuracy: 0.001)
        XCTAssertEqual(p.horizonMonths, 24)
        XCTAssertEqual(p.annualReturn, 0.02, accuracy: 1e-12)
        XCTAssertEqual(p.inflation, 0.025, accuracy: 1e-12)
        XCTAssertFalse(p.realTerms)
        // 204,41 per maand is nodig; de calculator begint met het naar boven afgeronde bedrag.
        XCTAssertEqual(p.requiredMonthly, 204.41, accuracy: 0.001)
        XCTAssertEqual(p.monthly, 205, accuracy: 0.001)
        XCTAssertTrue(p.isOnTrack)
    }

    func testGarbageInputDoesNotCrash() {
        let p = SavingsGoalPlan(goal: Double.nan, start: -5, annualReturn: Double.infinity, horizonMonths: -3,
                                monthly: Double.nan)
        XCTAssertEqual(p.cleanGoal, 0, accuracy: 0.0001)
        XCTAssertEqual(p.cleanStart, 0, accuracy: 0.0001)
        XCTAssertEqual(p.cleanMonthly, 0, accuracy: 0.0001)
        XCTAssertEqual(p.months, 1)
        XCTAssertEqual(p.requiredMonthly, 0, accuracy: 0.0001)
        XCTAssertEqual(p.monthsToGoal, 0)
        XCTAssertEqual(p.whatIfs.count, 3)

        let big = makePlan(months: 5_000)
        XCTAssertEqual(big.months, Growth.maxMonths)
    }

    // MARK: Spaarpot en doel aanmaken

    func testMakePotUsesGoalDepositAndOpeningBalance() {
        let p = makePlan(monthly: 150)
        let target = day(YearMonth(year: 2028, month: 10), 1)
        let pot = p.makePot(name: "  Auto  ", colorIndex: 2, targetDate: target, now: oct2026)
        XCTAssertEqual(pot.name, "Auto")
        XCTAssertEqual(pot.colorIndex, 2)
        XCTAssertEqual(pot.goalAmount, 10_000)
        XCTAssertEqual(pot.goalDate, target)
        XCTAssertEqual(pot.monthlyContribution, 150, accuracy: 0.001)
        XCTAssertEqual(pot.startMonth, oct2026)
        XCTAssertEqual(p.openingBalance, 1_000, accuracy: 0.001)

        var d = makeBaseData()
        d.addPot(pot, openingBalance: p.openingBalance, now: day(oct2026, 3))
        // 1.000 beginsaldo plus de inleg van oktober.
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1_150, accuracy: 0.001)
    }

    func testMakePotFallsBackToRequiredMonthlyAndDefaultName() {
        let p = makePlan(monthly: 0)
        let pot = p.makePot(name: "   ", colorIndex: 0, targetDate: nil, now: oct2026)
        XCTAssertEqual(pot.name, "Spaardoel")
        XCTAssertEqual(pot.monthlyContribution, 350, accuracy: 0.001)
        XCTAssertNil(pot.goalDate)
        XCTAssertEqual(p.savedMonthly, 350, accuracy: 0.001)
    }

    func testMakeGoalMatchesCalculator() {
        let nominal = makePlan(monthly: 200)
        let goal = nominal.makeGoal(name: "Laptop", targetDate: nil)
        XCTAssertEqual(goal.name, "Laptop")
        XCTAssertEqual(goal.kind, .custom)
        XCTAssertEqual(goal.targetAmount, 10_000, accuracy: 0.001)
        XCTAssertFalse(goal.inflationAdjusted)
        XCTAssertEqual(goal.funding, GoalFunding.custom(start: 1_000, monthly: 200, annualReturn: 0.06))

        var d = makeBaseData()
        d.addGoal(goal)
        XCTAssertNotNil(d.goal(goal.id))
        let analysis = d.analyze(goal, current: oct2026)
        XCTAssertEqual(analysis.monthsToGoal, nominal.monthsToGoal)
        XCTAssertEqual(analysis.inputs.target, 10_000, accuracy: 0.001)
        XCTAssertEqual(analysis.inputs.start, 1_000, accuracy: 0.001)
        XCTAssertEqual(analysis.inputs.monthly, 200, accuracy: 0.001)
    }

    func testMakeGoalInKoopkrachtMatchesCalculator() {
        // De standaardinflatie in de instellingen is 2%, net als in de calculator.
        let real = makePlan(monthly: 200, inflation: 0.02, real: true)
        let target = day(YearMonth(year: 2029, month: 1), 1)
        let goal = real.makeGoal(name: "", targetDate: target)
        XCTAssertEqual(goal.name, "Spaardoel")
        XCTAssertTrue(goal.inflationAdjusted)
        XCTAssertEqual(goal.targetDate, target)

        var d = makeBaseData()
        d.addGoal(goal)
        let analysis = d.analyze(goal, current: oct2026)
        XCTAssertEqual(analysis.monthsToGoal, 42)
        XCTAssertEqual(analysis.monthsToGoal, real.monthsToGoal)
    }

    func testMakeGoalUsesRequiredMonthlyWhenDepositIsEmpty() {
        let p = makePlan(monthly: 0)
        let goal = p.makeGoal(name: "Reis", targetDate: nil)
        XCTAssertEqual(goal.funding, GoalFunding.custom(start: 1_000, monthly: 350, annualReturn: 0.06))
    }
}

// MARK: - Afronden naar boven

/// Een benodigd maandbedrag wordt in hele euro's en naar boven afgerond getoond. Dat bedrag moet het doel altijd halen.
/// Verwachte waarden zijn onafhankelijk berekend in Python.
final class SavingsGoalRoundingTests: XCTestCase {
    private func makePlan(_ goal: Double, _ start: Double, _ rate: Double, _ months: Int, monthly: Double = 0,
                          inflation: Double = 0.02, real: Bool = false) -> SavingsGoalPlan {
        SavingsGoalPlan(goal: goal, start: start, annualReturn: rate, horizonMonths: months, monthly: monthly,
                        inflation: inflation, realTerms: real)
    }

    func testRequiredMonthlyWholeRoundsUp() {
        XCTAssertEqual(makePlan(10_000, 1_000, 0.06, 24).requiredMonthlyWhole, 350)   // 349,57
        XCTAssertEqual(makePlan(5_000, 0, 0.02, 24).requiredMonthlyWhole, 205)        // 204,41
        XCTAssertEqual(makePlan(5_000, 0, 0.01, 24).requiredMonthlyWhole, 207)        // 206,36
        XCTAssertEqual(makePlan(10_000, 0, 0.05, 24).requiredMonthlyWhole, 398)       // 397,48
        XCTAssertEqual(makePlan(5_000, 0, 0.02, 18).requiredMonthlyWhole, 274)        // 273,90
    }

    func testRequiredMonthlyWholeKeepsAnExactWholeAmount() {
        // 12.000 in 24 maanden zonder rente is precies 500: niet naar 501 afronden.
        XCTAssertEqual(makePlan(12_000, 0, 0, 24).requiredMonthlyWhole, 500)
        XCTAssertEqual(makePlan(12_000, 0, 0, 24).requiredMonthly, 500, accuracy: 0.001)
    }

    func testRequiredMonthlyWholeInKoopkracht() {
        XCTAssertEqual(makePlan(10_000, 1_000, 0.06, 24, inflation: 0.02, real: true).requiredMonthlyWhole, 359)   // 358,13
        XCTAssertEqual(makePlan(5_000, 0, 0.01, 24, inflation: 0.03, real: true).requiredMonthlyWhole, 213)        // 212,28
    }

    func testRequiredMonthlyWholeIsZeroWhenAlreadyReached() {
        XCTAssertEqual(makePlan(500, 1_000, 0.03, 24).requiredMonthlyWhole, 0)
        XCTAssertEqual(makePlan(0, 0, 0.03, 24).requiredMonthlyWhole, 0)
    }

    /// Afgerond op centen is het 195,00 en 272,00, maar de echte grens ligt er net boven. Dan moet er een euro bij.
    func testRequiredMonthlyWholeNeverMissesByRounding() {
        let a = makePlan(8_000, 500, 0.04, 36)
        XCTAssertEqual(a.requiredMonthlyWhole, 196)
        XCTAssertNil(Growth.monthsToReach(target: 8_000, start: 500, monthly: 195, annualReturn: 0.04, maxMonths: 36))
        XCTAssertEqual(Growth.monthsToReach(target: 8_000, start: 500, monthly: 196, annualReturn: 0.04, maxMonths: 36), 36)

        let b = makePlan(5_000, 0, 0.03, 18)
        XCTAssertEqual(b.requiredMonthlyWhole, 273)
        XCTAssertNil(Growth.monthsToReach(target: 5_000, start: 0, monthly: 272, annualReturn: 0.03, maxMonths: 18))
        XCTAssertEqual(Growth.monthsToReach(target: 5_000, start: 0, monthly: 273, annualReturn: 0.03, maxMonths: 18), 18)
    }

    /// Over een raster van invoer: het bedrag is een heel getal, haalt het doel op tijd, en een euro minder haalt het niet.
    func testRequiredMonthlyWholeIsTheSmallestWholeAmountThatReachesTheGoal() {
        for goal in [1_000.0, 2_500, 5_000, 12_345, 80_000] {
            for start in [0.0, 250, 1_000] {
                for rate in [0.0, 0.01, 0.03, 0.06] {
                    for months in [1, 6, 18, 24, 60] {
                        let plan = makePlan(goal, start, rate, months)
                        let whole = plan.requiredMonthlyWhole
                        let label = "doel \(goal) start \(start) rente \(rate) maanden \(months)"
                        XCTAssertEqual(whole, whole.rounded(), label)
                        XCTAssertGreaterThanOrEqual(whole, plan.requiredMonthly - 0.0001, label)
                        XCTAssertLessThan(whole, plan.requiredMonthly + 1.011, label)
                        if plan.isReached {
                            XCTAssertEqual(whole, 0, label)
                            continue
                        }
                        XCTAssertNotNil(Growth.monthsToReach(target: goal, start: start, monthly: whole,
                                                             annualReturn: rate, maxMonths: months), label)
                        if whole >= 1 {
                            XCTAssertNil(Growth.monthsToReach(target: goal, start: start, monthly: whole - 1,
                                                              annualReturn: rate, maxMonths: months), label)
                        }
                    }
                }
            }
        }
    }

    func testRequiredOutcomeAndSavedMonthlyUseTheWholeAmount() {
        let p = makePlan(10_000, 1_000, 0.06, 24)
        XCTAssertEqual(p.requiredMonthly, 349.57, accuracy: 0.001)
        XCTAssertEqual(p.requiredOutcome.monthly, 350, accuracy: 0.001)
        XCTAssertEqual(p.savedMonthly, 350, accuracy: 0.001)
        XCTAssertEqual(p.requiredOutcome.balance, 10_011.03, accuracy: 0.011)
        // Met een eigen inleg blijft die gelden.
        XCTAssertEqual(makePlan(10_000, 1_000, 0.06, 24, monthly: 275.5).savedMonthly, 275.5, accuracy: 0.001)
    }

    func testTakingOverTheRequiredAmountIsOnTime() {
        var p = makePlan(10_000, 1_000, 0.06, 24, monthly: 100)
        XCTAssertFalse(p.isOnTrack)
        p.monthly = p.requiredMonthlyWhole
        XCTAssertTrue(p.isOnTrack)
        XCTAssertEqual(p.monthsToGoal, 24)
        XCTAssertEqual(p.shortfallMonthlyWhole, 0, accuracy: 0.0001)
    }

    func testShortfallInWholeEuros() {
        // Nodig 349,57.
        let cases: [(own: Double, shortfall: Double)] = [(200, 150), (200.6, 149), (349.56, 1), (349.57, 0), (350, 0), (1, 349)]
        for item in cases {
            let p = makePlan(10_000, 1_000, 0.06, 24, monthly: item.own)
            XCTAssertEqual(p.shortfallMonthlyWhole, item.shortfall, accuracy: 0.0001, "inleg \(item.own)")
            // Het tekort erbij leggen is genoeg om op tijd te zijn.
            XCTAssertNotNil(Growth.monthsToReach(target: 10_000, start: 1_000, monthly: item.own + item.shortfall,
                                                 annualReturn: 0.06, maxMonths: 24), "inleg \(item.own)")
        }
        // Het exacte tekort blijft op centen.
        XCTAssertEqual(makePlan(10_000, 1_000, 0.06, 24, monthly: 200).shortfallMonthly, 149.57, accuracy: 0.001)
    }

    func testShortfallInWholeEurosIgnoresFloatingPointNoise() {
        // 128,33 in één maand zonder rente is precies 128,33 nodig; met 33,33 eigen inleg mis je 95,00.
        // In drijvende komma is 128,33 min 33,33 gelijk aan 95,00000000000001: dat mag geen 96 worden.
        let p = makePlan(128.33, 0, 0, 1, monthly: 33.33)
        XCTAssertEqual(p.requiredMonthly, 128.33, accuracy: 0.0001)
        XCTAssertEqual(p.shortfallMonthly, 95, accuracy: 0.0001)
        XCTAssertEqual(p.shortfallMonthlyWhole, 95, accuracy: 0.0001)
        // Eén cent meer tekort is wel een euro meer.
        XCTAssertEqual(makePlan(128.33, 0, 0, 1, monthly: 33.32).shortfallMonthlyWhole, 96, accuracy: 0.0001)
    }

    func testRequiredMonthlyWholeForATinyShortfall() {
        // Nog 10 cent te gaan: op centen is dat 0,00 per maand, maar 0 euro haalt het doel niet.
        let p = makePlan(1_000, 999.9, 0, 24)
        XCTAssertEqual(p.requiredMonthlyWhole, 1)
        XCTAssertNil(Growth.monthsToReach(target: 1_000, start: 999.9, monthly: 0, annualReturn: 0, maxMonths: 24))
        XCTAssertNotNil(Growth.monthsToReach(target: 1_000, start: 999.9, monthly: 1, annualReturn: 0, maxMonths: 24))
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 1_000, start: 999.9, annualReturn: 0, months: 24), 1)
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 1_000, start: 999.99, annualReturn: 0, months: 1_200), 1)
        // Met rente groeit het startbedrag zelf al voorbij het doel: dan is niets nodig.
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 1_000, start: 999.99, annualReturn: 0.03, months: 1_200), 0)
        // Precies op het doel blijft 0.
        XCTAssertEqual(makePlan(1_000, 1_000, 0, 24).requiredMonthlyWhole, 0)
        // De calculator volgt dit zolang "Mijn inleg" leeg is.
        var draft = SavingsGoalDraft()
        draft.goal = 1_000
        draft.start = 999.9
        draft.periodUnit = .months
        draft.periodValue = 24
        let plan = draft.plan(savingsRate: 0, inflation: 0.02, now: oct2026)
        XCTAssertEqual(plan.monthly, 1)
        XCTAssertTrue(plan.isOnTrack)
    }

    // MARK: GoalMath

    func testGoalMathEdgeCases() {
        // Zonder maanden is het hele tekort in één keer nodig.
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 1_234.5, start: 0, annualReturn: 0.05, months: 0), 1_235)
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 1_000, start: 400.25, annualReturn: 0.05, months: -3), 600)
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 500, start: 900, annualReturn: 0.05, months: 0), 0)
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 500, start: 900, annualReturn: 0.05, months: 12), 0)
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: Double.nan, start: 0, annualReturn: 0.05, months: 12), 0)
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 1_000, start: 0, annualReturn: Double.infinity, months: 12), 0)
        XCTAssertEqual(GoalMath.wholeMonthlyToReach(target: 8_000, start: 500, annualReturn: 0.04, months: 36), 196)
        // Een heel lange termijn gaat ook goed.
        let long = GoalMath.wholeMonthlyToReach(target: 500_000, start: 10_000, annualReturn: 0.05, months: 1_200)
        XCTAssertEqual(long, long.rounded())
        XCTAssertNotNil(Growth.monthsToReach(target: 500_000, start: 10_000, monthly: long, annualReturn: 0.05))
    }

    // MARK: Samenvatting

    func testSummaryLine() {
        let p = makePlan(5_000, 0, 0.02, 18)
        XCTAssertEqual(p.summaryLine, "Spaar \(Fmt.euro(5_000)) in 1 jaar en 6 maanden: \(Fmt.euro(274)) per maand")
        XCTAssertFalse(p.summaryLine.contains(","), "geen centen in de samenvatting")

        let reached = makePlan(500, 1_000, 0.02, 18)
        XCTAssertTrue(reached.summaryLine.contains("bereikt"))
    }

    func testHubSubtitle() {
        XCTAssertEqual(GoalMath.hubSubtitle(goalCount: 0, hasSavingsGoal: false), "Levensdoelen en spaardoel")
        XCTAssertEqual(GoalMath.hubSubtitle(goalCount: 0, hasSavingsGoal: true), "Spaardoel")
        XCTAssertEqual(GoalMath.hubSubtitle(goalCount: 1, hasSavingsGoal: false), "1 doel")
        XCTAssertEqual(GoalMath.hubSubtitle(goalCount: 1, hasSavingsGoal: true), "1 doel en een spaardoel")
        XCTAssertEqual(GoalMath.hubSubtitle(goalCount: 3, hasSavingsGoal: false), "3 doelen")
        XCTAssertEqual(GoalMath.hubSubtitle(goalCount: 3, hasSavingsGoal: true), "3 doelen en een spaardoel")
    }
}

// MARK: - Bewaarde invoer van de calculator

final class SavingsGoalDraftTests: XCTestCase {
    func testDefaultDraftIsTheExample() {
        let draft = SavingsGoalDraft()
        let plan = draft.plan(savingsRate: 0.02, inflation: 0.025, now: oct2026)
        XCTAssertEqual(plan, SavingsGoalPlan.example(savingsRate: 0.02, inflation: 0.025))
        XCTAssertEqual(plan.goal, 5_000, accuracy: 0.001)
        XCTAssertEqual(plan.horizonMonths, 24)
        XCTAssertEqual(plan.monthly, 205, accuracy: 0.001)   // nog niet zelf ingevuld: de benodigde inleg
        XCTAssertFalse(draft.edited)
        XCTAssertNil(draft.monthly)
    }

    func testOwnMonthlyWinsOverTheRequiredAmount() {
        var draft = SavingsGoalDraft()
        draft.monthly = 150
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).monthly, 150, accuracy: 0.001)
        // Een bewust ingevulde 0 blijft 0 (niet terug naar de benodigde inleg).
        draft.monthly = 0
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).monthly, 0, accuracy: 0.001)
    }

    func testRequiredAmountFollowsTheInputWhileMonthlyIsEmpty() {
        var draft = SavingsGoalDraft()
        draft.goal = 8_000
        draft.start = 500
        // 305,78 nodig bij 2% in 24 maanden.
        let plan = draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026)
        XCTAssertEqual(plan.requiredMonthly, 305.78, accuracy: 0.001)
        XCTAssertEqual(plan.monthly, 306, accuracy: 0.001)
        XCTAssertTrue(plan.isOnTrack)
        // Een ander percentage past de benodigde inleg aan.
        draft.preset = .equities
        draft.periodValue = 30
        draft.periodUnit = .months
        let faster = draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026)
        XCTAssertEqual(faster.annualReturn, 0.06, accuracy: 1e-12)
        XCTAssertEqual(faster.horizonMonths, 30)
        XCTAssertEqual(faster.monthly, 231, accuracy: 0.001)   // 230,36 nodig
    }

    func testTermFromDateOrPeriod() {
        var draft = SavingsGoalDraft()
        draft.useDate = true
        draft.targetDate = day(YearMonth(year: 2028, month: 10), 15)
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).horizonMonths, 24)
        draft.targetDate = day(YearMonth(year: 2027, month: 1), 1)
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).horizonMonths, 3)
        // Datum gekozen maar nog geen datum ingevuld: dan geldt de periode.
        draft.targetDate = nil
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).horizonMonths, 24)
        draft.useDate = false
        draft.periodUnit = .years
        draft.periodValue = 1.5
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).horizonMonths, 18)
    }

    func testRatePresetsAndRealTerms() {
        var draft = SavingsGoalDraft()
        draft.preset = .custom
        draft.customRate = 0.045
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).annualReturn, 0.045, accuracy: 1e-12)
        draft.preset = .savings
        XCTAssertEqual(draft.plan(savingsRate: 0.015, inflation: 0.02, now: oct2026).annualReturn, 0.015, accuracy: 1e-12)
        draft.realTerms = true
        let real = draft.plan(savingsRate: 0.06, inflation: 0.02, now: oct2026)
        XCTAssertTrue(real.realTerms)
        XCTAssertEqual(real.effectiveReturn, 0.0392157, accuracy: 0.000001)
    }

    func testJSONRoundTrip() throws {
        var draft = SavingsGoalDraft()
        draft.goal = 12_500
        draft.start = 750
        draft.monthly = 320.5
        draft.preset = .custom
        draft.customRate = 0.035
        draft.useDate = true
        draft.periodValue = 30
        draft.periodUnit = .months
        draft.targetDate = day(YearMonth(year: 2028, month: 10), 15)
        draft.realTerms = true
        draft.edited = true

        let back = try XCTUnwrap(SavingsGoalDraft.decode(draft.json))
        XCTAssertEqual(back.goal, 12_500, accuracy: 0.0001)
        XCTAssertEqual(back.start, 750, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(back.monthly), 320.5, accuracy: 0.0001)
        XCTAssertEqual(back.preset, .custom)
        XCTAssertEqual(back.customRate, 0.035, accuracy: 1e-12)
        XCTAssertTrue(back.useDate)
        XCTAssertEqual(back.periodValue, 30, accuracy: 0.0001)
        XCTAssertEqual(back.periodUnit, .months)
        XCTAssertEqual(try XCTUnwrap(back.targetDate).timeIntervalSince(try XCTUnwrap(draft.targetDate)), 0, accuracy: 0.001)
        XCTAssertTrue(back.realTerms)
        XCTAssertTrue(back.edited)
    }

    func testEmptyOrZeroFieldMeansOwnMonthlyNotFilledIn() {
        // Het veld "Mijn inleg" geeft 0 als het leeg is: dan geldt de benodigde inleg weer.
        XCTAssertNil(SavingsGoalDraft.ownMonthly(fromField: 0))
        XCTAssertNil(SavingsGoalDraft.ownMonthly(fromField: -25))
        XCTAssertNil(SavingsGoalDraft.ownMonthly(fromField: .nan))
        XCTAssertNil(SavingsGoalDraft.ownMonthly(fromField: .infinity))
        XCTAssertEqual(SavingsGoalDraft.ownMonthly(fromField: 150), 150)
        XCTAssertEqual(SavingsGoalDraft.ownMonthly(fromField: 0.5), 0.5)

        var draft = SavingsGoalDraft()
        draft.monthly = SavingsGoalDraft.ownMonthly(fromField: 150)
        XCTAssertEqual(draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026).monthly, 150, accuracy: 0.001)
        // Veld weer leeg gemaakt: terug naar de benodigde inleg (205 voor 5.000 in 24 maanden bij 2%).
        draft.monthly = SavingsGoalDraft.ownMonthly(fromField: 0)
        XCTAssertNil(draft.monthly)
        let plan = draft.plan(savingsRate: 0.02, inflation: 0.02, now: oct2026)
        XCTAssertEqual(plan.monthly, 205, accuracy: 0.001)
        XCTAssertTrue(plan.isOnTrack)
    }

    func testClearStoredRemovesTheSavedInput() throws {
        let suite = "MyBuddyTests.SavingsGoalDraftClear"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var draft = SavingsGoalDraft()
        draft.goal = 9_000
        draft.edited = true
        defaults.set(draft.json, forKey: SavingsGoalDraft.storageKey)
        XCTAssertEqual(SavingsGoalDraft.decode(defaults.string(forKey: SavingsGoalDraft.storageKey) ?? "")?.goal, 9_000)

        SavingsGoalDraft.clearStored(in: defaults)
        XCTAssertNil(defaults.string(forKey: SavingsGoalDraft.storageKey))
        XCTAssertNil(SavingsGoalDraft.decode(defaults.string(forKey: SavingsGoalDraft.storageKey) ?? ""))
        // Nog eens wissen als er niets staat, mag.
        SavingsGoalDraft.clearStored(in: defaults)
    }

    func testEmptyMonthlyIsNotStored() throws {
        let draft = SavingsGoalDraft()
        XCTAssertFalse(draft.json.contains("\"monthly\""))
        XCTAssertNil(try XCTUnwrap(SavingsGoalDraft.decode(draft.json)).monthly)
    }

    func testOldOrBrokenStoredDataFallsBackToDefaults() throws {
        XCTAssertNil(SavingsGoalDraft.decode(""))
        XCTAssertNil(SavingsGoalDraft.decode("geen json"))
        XCTAssertNil(SavingsGoalDraft.decode("[1, 2]"))

        let empty = try XCTUnwrap(SavingsGoalDraft.decode("{}"))
        XCTAssertEqual(empty, SavingsGoalDraft())

        let partial = try XCTUnwrap(SavingsGoalDraft.decode("{\"goal\": 8000, \"preset\": \"bestaatniet\", \"periodUnit\": 5, \"edited\": true}"))
        XCTAssertEqual(partial.goal, 8_000, accuracy: 0.0001)
        XCTAssertEqual(partial.preset, .savings)
        XCTAssertEqual(partial.periodUnit, .years)
        XCTAssertEqual(partial.periodValue, 2, accuracy: 0.0001)
        XCTAssertTrue(partial.edited)
    }
}

// MARK: - Levensdoelen: haalbaarheid en afronden

final class GoalOutlookTests: XCTestCase {
    private func goal(target: Double, start: Double, monthly: Double, rate: Double = 0, due: YearMonth? = nil) -> LifeGoal {
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = target
        g.inflationAdjusted = false
        g.funding = .custom(start: start, monthly: monthly, annualReturn: rate)
        g.targetDate = due?.firstDay
        return g
    }

    func testReached() {
        let d = makeBaseData()
        let a = d.analyze(goal(target: 100, start: 500, monthly: 0), current: oct2026)
        XCTAssertEqual(a.outlook, .reached)
        XCTAssertEqual(a.outlook.months, 0)
        XCTAssertTrue(a.outlook.isPositive)
    }

    func testReachableWithoutDeadline() {
        let d = makeBaseData()
        // 4.000 te gaan met 200 per maand zonder rente: 20 maanden.
        let a = d.analyze(goal(target: 5_000, start: 1_000, monthly: 200), current: oct2026)
        XCTAssertEqual(a.outlook, .reachable(months: 20))
        XCTAssertEqual(a.outlook.months, 20)
        XCTAssertFalse(a.outlook.isPositive)
        XCTAssertNil(a.requiredMonthlyForDeadlineWhole)
    }

    func testOnTrackAndBehindWithDeadline() {
        let d = makeBaseData()
        let onTrack = d.analyze(goal(target: 1_000, start: 0, monthly: 100, due: YearMonth(year: 2027, month: 10)),
                                current: oct2026)
        XCTAssertEqual(onTrack.outlook, .onTrack(months: 10))
        XCTAssertTrue(onTrack.outlook.isPositive)

        let behind = d.analyze(goal(target: 5_000, start: 1_000, monthly: 200, due: YearMonth(year: 2027, month: 6)),
                               current: oct2026)
        XCTAssertEqual(behind.outlook, .behind(months: 20))
        XCTAssertEqual(behind.outlook.months, 20)
        XCTAssertFalse(behind.outlook.isPositive)
    }

    func testPassedDeadlineCountsAsBehind() {
        let d = makeBaseData()
        let a = d.analyze(goal(target: 1_000, start: 0, monthly: 100, due: YearMonth(year: 2026, month: 5)),
                          current: oct2026)
        XCTAssertEqual(a.outlook, .behind(months: 10))
        XCTAssertNil(a.requiredMonthlyForDeadlineWhole)
    }

    func testUnreachable() {
        let d = makeBaseData()
        let a = d.analyze(goal(target: 1_000, start: 0, monthly: 0), current: oct2026)
        XCTAssertEqual(a.outlook, .unreachable)
        XCTAssertNil(a.outlook.months)
        let withDeadline = d.analyze(goal(target: 1_000, start: 0, monthly: 0, due: YearMonth(year: 2027, month: 6)),
                                     current: oct2026)
        XCTAssertEqual(withDeadline.outlook, .unreachable)
    }

    func testRequiredMonthlyForDeadlineIsRoundedUp() {
        let d = makeBaseData()
        // Doel 5.000, nu 1.000, 3% per jaar, nog 8 maanden: 493,23 per maand is nodig.
        let g = goal(target: 5_000, start: 1_000, monthly: 200, rate: 0.03, due: YearMonth(year: 2027, month: 6))
        let a = d.analyze(g, current: oct2026)
        XCTAssertEqual(a.monthsUntilDeadline, 8)
        XCTAssertEqual(a.requiredMonthlyForDeadline ?? 0, 493.23, accuracy: 0.01)
        XCTAssertEqual(a.requiredMonthlyForDeadlineWhole ?? 0, 494, accuracy: 0.0001)
        // 494 haalt de streefdatum, 493 net niet.
        XCTAssertNotNil(Growth.monthsToReach(target: 5_000, start: 1_000, monthly: 494, annualReturn: 0.03, maxMonths: 8))
        XCTAssertNil(Growth.monthsToReach(target: 5_000, start: 1_000, monthly: 493, annualReturn: 0.03, maxMonths: 8))
    }

    func testGoalWithoutTargetIsNotSet() {
        let d = makeBaseData()
        let empty = d.analyze(goal(target: 0, start: 0, monthly: 0), current: oct2026)
        XCTAssertEqual(empty.outlook, .notSet)
        XCTAssertNil(empty.outlook.months)
        XCTAssertFalse(empty.outlook.isPositive)
        XCTAssertEqual(empty.progress, 0, accuracy: 0.0001)
        // Ook met een startbedrag en een streefdatum is een doel zonder bedrag niet "bereikt" of "op schema".
        let withMoney = d.analyze(goal(target: 0, start: 500, monthly: 100, due: YearMonth(year: 2027, month: 10)),
                                  current: oct2026)
        XCTAssertEqual(withMoney.outlook, .notSet)
        XCTAssertEqual(withMoney.progress, 0, accuracy: 0.0001)
        // Een pensioen zonder uitgaven heeft ook geen doelbedrag.
        var retirement = LifeGoal(name: "Pensioen", kind: .retirement)
        retirement.monthlySpending = 0
        XCTAssertEqual(d.analyze(retirement, current: oct2026).outlook, .notSet)
        // Zodra er een bedrag is, geldt het gewone oordeel weer.
        XCTAssertEqual(d.analyze(goal(target: 100, start: 500, monthly: 0), current: oct2026).outlook, .reached)
    }

    func testRequiredMonthlyForDeadlineKeepsExactWholeAmount() {
        let d = makeBaseData()
        // Zonder rente: 4.000 in 8 maanden is precies 500.
        let a = d.analyze(goal(target: 5_000, start: 1_000, monthly: 200, due: YearMonth(year: 2027, month: 6)),
                          current: oct2026)
        XCTAssertEqual(a.requiredMonthlyForDeadlineWhole ?? 0, 500, accuracy: 0.0001)
    }
}
