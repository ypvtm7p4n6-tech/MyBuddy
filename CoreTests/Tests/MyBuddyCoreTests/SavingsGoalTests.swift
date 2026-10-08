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

        let o = p.requiredOutcome
        XCTAssertEqual(o.months, 24)
        XCTAssertEqual(o.monthly, 349.57, accuracy: 0.001)
        XCTAssertEqual(o.balance, 10_000.11, accuracy: 0.011)
        XCTAssertEqual(o.deposited, 9_389.68, accuracy: 0.011)
        XCTAssertEqual(o.interest, 610.43, accuracy: 0.011)
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
        XCTAssertEqual(p.monthly, 204.41, accuracy: 0.001)
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
        XCTAssertEqual(pot.monthlyContribution, 349.57, accuracy: 0.001)
        XCTAssertNil(pot.goalDate)
        XCTAssertEqual(p.savedMonthly, 349.57, accuracy: 0.001)
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
        XCTAssertEqual(goal.funding, GoalFunding.custom(start: 1_000, monthly: 349.57, annualReturn: 0.06))
    }
}
