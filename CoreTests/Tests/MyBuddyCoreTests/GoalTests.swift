import XCTest
@testable import MyBuddyCore

final class GoalTests: XCTestCase {
    func testRetirementCapital() {
        let d = makeBaseData()
        var g = LifeGoal(name: "Pensioen", kind: .retirement)
        g.monthlySpending = 2300
        g.otherMonthlyIncome = 1200
        g.withdrawalRate = 0.04
        XCTAssertEqual(d.neededCapital(for: g, drawdownReturn: 0.03), 330_000, accuracy: 0.01)
        g.otherMonthlyIncome = 5000 // AOW dekt alles
        XCTAssertEqual(d.neededCapital(for: g, drawdownReturn: 0.03), 0, accuracy: 0.01)
    }

    func testPartTimeGapFromHourlySalary() {
        var d = makeBaseData()
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        var g = LifeGoal(name: "4 dagen", kind: .partTime)
        g.hoursFrom = 36
        g.hoursTo = 28
        XCTAssertEqual(d.monthlyIncomeGap(for: g), 693.33, accuracy: 0.01)
        g.monthlyGapOverride = 500
        XCTAssertEqual(d.monthlyIncomeGap(for: g), 500, accuracy: 0.001)
    }

    func testPartTimeGapFromFixedSalary() {
        let d = makeBaseData() // vast 3000
        var g = LifeGoal(name: "4 dagen", kind: .partTime)
        g.hoursFrom = 40
        g.hoursTo = 32
        XCTAssertEqual(d.monthlyIncomeGap(for: g), 600, accuracy: 0.001)
        g.hoursTo = 40
        XCTAssertEqual(d.monthlyIncomeGap(for: g), 0, accuracy: 0.001)
    }

    func testPartTimeFiniteHorizonUsesAnnuity() {
        let d = makeBaseData()
        var g = LifeGoal(name: "Tijdelijk", kind: .partTime)
        g.monthlyGapOverride = 1000
        g.partTimeYears = 20
        XCTAssertEqual(d.neededCapital(for: g, drawdownReturn: 0.03), 178_529.70, accuracy: 0.05)
        g.partTimeYears = nil
        g.withdrawalRate = 0.04
        XCTAssertEqual(d.neededCapital(for: g, drawdownReturn: 0.03), 300_000, accuracy: 0.01)
    }

    func testAnalysisWithCustomFundingAndDeadline() {
        var d = makeBaseData()
        var g = LifeGoal(name: "Vakantie", kind: .vacation)
        g.targetAmount = 5000
        g.inflationAdjusted = false
        g.funding = .custom(start: 1000, monthly: 200, annualReturn: 0)
        g.targetDate = YearMonth(year: 2027, month: 6).firstDay
        d.addGoal(g)

        let a = d.analyze(g, current: oct2026)
        XCTAssertEqual(a.inputs.target, 5000)
        XCTAssertEqual(a.progress, 0.2, accuracy: 0.0001)
        XCTAssertEqual(a.monthsToGoal, 20)
        XCTAssertEqual(a.reachMonth, YearMonth(year: 2028, month: 6))
        XCTAssertEqual(a.monthsUntilDeadline, 8)
        XCTAssertEqual(a.requiredMonthlyForDeadline ?? 0, 500, accuracy: 0.01)
        XCTAssertEqual(a.onTrack, false)
    }

    func testAnalysisOnTrack() {
        let d = makeBaseData()
        var g = LifeGoal(name: "Auto", kind: .custom)
        g.targetAmount = 1000
        g.inflationAdjusted = false
        g.funding = .custom(start: 0, monthly: 100, annualReturn: 0)
        g.targetDate = YearMonth(year: 2027, month: 10).firstDay
        let a = d.analyze(g, current: oct2026)
        XCTAssertEqual(a.monthsToGoal, 10)
        XCTAssertEqual(a.onTrack, true)
    }

    func testInflationLowersEffectiveReturn() {
        let d = makeBaseData()
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 1000
        g.funding = .custom(start: 0, monthly: 100, annualReturn: 0.06)
        g.inflationAdjusted = true
        let real = d.goalInputs(for: g, current: oct2026)
        XCTAssertEqual(real.effectiveReturn, 0.0392157, accuracy: 0.00001)
        g.inflationAdjusted = false
        XCTAssertEqual(d.goalInputs(for: g, current: oct2026).effectiveReturn, 0.06, accuracy: 0.00001)
    }

    func testPotFundingUsesPotBalanceAndContribution() {
        var d = makeBaseData()
        let pot = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Uit pot", kind: .custom)
        g.targetAmount = 2000
        g.inflationAdjusted = false
        g.funding = .pot(pot.id)
        // Na de inleg van de 25e: 500 + 3 x 200 = 1100. (Voor de 25e is het saldo van nu 900, zie de test hieronder.)
        let afterPayDay = day(oct2026, 26)
        let inputs = d.goalInputs(for: g, current: oct2026, today: afterPayDay)
        XCTAssertEqual(inputs.start, 1100, accuracy: 0.001)
        XCTAssertEqual(inputs.monthly, 200, accuracy: 0.001)
        XCTAssertEqual(inputs.sourceName, "Buffer")
        XCTAssertEqual(d.analyze(g, current: oct2026, today: afterPayDay).monthsToGoal, 5)
    }

    /// De pagina noemt het startbedrag "Nu": het saldo van vandaag, zonder de inleg die nog moet komen.
    func testPotFundingStartsFromTheBalanceOfNowNotOfTheMonthEnd() {
        var d = FinanceData(startMonth: oct2026)
        // Inleg 100 op de 25e (de salarisdag); de pot staat op 1100 vanaf 2 oktober.
        let pot = Pot(name: "Spaar", monthlyContribution: 100, startMonth: oct2026)
        d.addPot(pot, openingBalance: 1100, now: day(oct2026, 2))
        var g = LifeGoal(name: "Uit pot", kind: .custom)
        g.targetAmount = 2000
        g.inflationAdjusted = false
        g.funding = .pot(pot.id)

        // Op de 9e: 1100. De inleg van de 25e is er nog niet.
        let ninth = day(oct2026, 9)
        XCTAssertEqual(d.goalInputs(for: g, current: oct2026, today: ninth).start, 1100, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: g, current: oct2026, today: ninth).monthly, 100, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: g, current: oct2026, today: day(oct2026, 24)).start, 1100, accuracy: 0.001)
        // Vanaf de 25e (12:00): 1200.
        XCTAssertEqual(d.goalInputs(for: g, current: oct2026, today: oct2026.date(day: 25)).start, 1200, accuracy: 0.001)
        // Vandaag in een andere maand dan `current`: het saldo aan het eind van `current`, zoals eerder.
        XCTAssertEqual(d.goalInputs(for: g, current: oct2026, today: day(YearMonth(year: 2026, month: 12), 3)).start, 1200, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: g, current: oct2026, today: day(YearMonth(year: 2026, month: 12), 3)).start,
                       d.potBalance(pot.id, at: oct2026), accuracy: 0.001)

        // De doorrekening gebruikt hetzelfde startbedrag: (2000 - 1100) / 100 = 9 maanden, vanaf 1200 acht.
        XCTAssertEqual(d.analyze(g, current: oct2026, today: ninth).monthsToGoal, 9)
        XCTAssertEqual(d.analyze(g, current: oct2026, today: oct2026.date(day: 25)).monthsToGoal, 8)
        XCTAssertEqual(d.analyze(g, current: oct2026, today: ninth).progress, 1100.0 / 2000.0, accuracy: 0.0001)
    }

    func testReachedGoalHasNoAccelerators() {
        let d = makeBaseData()
        var g = LifeGoal(name: "Klaar", kind: .custom)
        g.targetAmount = 100
        g.inflationAdjusted = false
        g.funding = .custom(start: 500, monthly: 0, annualReturn: 0)
        XCTAssertTrue(d.analyze(g, current: oct2026).isReached)
        XCTAssertTrue(d.accelerators(for: g, current: oct2026, today: day(oct2026, 15)).isEmpty)
    }

    func testTemplatesUseOwnData() {
        var d = makeBaseData()
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        let part = d.goalTemplate(.partTime)
        XCTAssertEqual(part.hoursFrom, 36)
        XCTAssertEqual(part.hoursTo, 28)
        XCTAssertFalse(d.goalTemplate(.vacation).inflationAdjusted)
        XCTAssertTrue(d.goalTemplate(.retirement).inflationAdjusted)
    }
}

final class AcceleratorTests: XCTestCase {
    private let sampleNow = day(oct2026, 12)

    func testSampleDataProducesRankedPersonalAccelerators() {
        let d = FinanceData.sample(now: sampleNow)
        let pension = d.goals[0]
        let list = d.accelerators(for: pension, current: oct2026, today: day(oct2026, 15))
        XCTAssertFalse(list.isEmpty)

        let baseline = d.analyze(pension, current: oct2026).monthsToGoal
        // Gesorteerd: eerst wat het doel haalbaar maakt, daarna de grootste winst.
        var previousSaved = Int.max
        for acc in list where !acc.makesReachable {
            let saved = acc.monthsSaved ?? 0
            XCTAssertGreaterThan(saved, 0, acc.title)
            XCTAssertLessThanOrEqual(saved, previousSaved, acc.title)
            previousSaved = saved
            if let b = baseline, let n = acc.newMonths { XCTAssertEqual(b - n, saved, acc.title) }
        }
        XCTAssertTrue(list.contains { $0.id == "free" })
        XCTAssertTrue(list.contains { $0.id == "stepup" })
        XCTAssertTrue(list.contains { $0.id == "target" })
    }

    func testCombinedScenarioIsAtLeastAsFastAsEachPart() {
        let d = FinanceData.sample(now: sampleNow)
        let goal = d.goals[0]
        let inputs = d.goalInputs(for: goal, current: oct2026)
        let list = Array(d.accelerators(for: goal, current: oct2026, today: day(oct2026, 15)).prefix(3))
        XCTAssertGreaterThanOrEqual(list.count, 2)
        let combined = d.scenarioMonths(inputs, change: d.combine(list))
        for acc in list {
            if let c = combined, let single = acc.newMonths { XCTAssertLessThanOrEqual(c, single, acc.title) }
        }
    }

    func testBankSurplusAndExpenseLeversUseOwnNumbers() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 50_000
        g.inflationAdjusted = false
        g.funding = .custom(start: 0, monthly: 200, annualReturn: 0.05)
        let list = d.accelerators(for: g, current: oct2026, today: day(oct2026, 15))
        let bank = list.first { $0.id == "bank" }
        XCTAssertNotNil(bank)
        // Buffer: 2 maanden × gemiddelde uitgaven (1016,67) = 2033,34; overschot ≈ 7966,66.
        XCTAssertEqual(bank?.change.oneOff ?? 0, 7966.66, accuracy: 0.05)
        // Huur (1000) is de grootste uitgave: 10% = 100 per maand.
        let rent = list.first { $0.title.hasPrefix("Verlaag Huur") }
        XCTAssertEqual(rent?.change.extraMonthly ?? 0, 100, accuracy: 0.001)
    }

    func testCostAndShiftLeversRequirePortfolioFunding() {
        var d = makeBaseData()
        d.addHolding(Holding(name: "Duur fonds", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.07, annualCost: 0.015, startMonth: aug2026),
                     initialValue: 6000, now: day(sep2026, 1))
        d.addHolding(Holding(name: "Spaar", kind: .savings, ticker: nil, units: nil, expectedReturn: 0.02, annualCost: 0, startMonth: aug2026),
                     initialValue: 4000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio

        let ids = Set(d.accelerators(for: g, current: oct2026, today: day(oct2026, 15)).map(\.id))
        XCTAssertTrue(ids.contains("costs"))
        XCTAssertTrue(ids.contains("shift"))

        g.funding = .custom(start: 10_000, monthly: 0, annualReturn: 0.05)
        let idsCustom = Set(d.accelerators(for: g, current: oct2026, today: day(oct2026, 15)).map(\.id))
        XCTAssertFalse(idsCustom.contains("costs"))
        XCTAssertFalse(idsCustom.contains("shift"))
    }

    func testUnreachableGoalMarksLeversThatMakeItReachable() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Onhaalbaar", kind: .custom)
        g.targetAmount = 10_000
        g.inflationAdjusted = false
        g.funding = .custom(start: 0, monthly: 0, annualReturn: 0)
        let list = d.accelerators(for: g, current: oct2026, today: day(oct2026, 15))
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(list.allSatisfy { $0.makesReachable })
        XCTAssertTrue(list.allSatisfy { $0.monthsSaved == nil })
    }

    func testGoalCurves() {
        let d = makeBaseData()
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 5000
        g.inflationAdjusted = false
        g.funding = .custom(start: 1000, monthly: 200, annualReturn: 0)
        let curves = d.goalCurves(for: g, change: ScenarioChange(extraMonthly: 100), months: 12, current: oct2026)
        XCTAssertEqual(curves.baseline.count, 13)
        XCTAssertEqual(curves.baseline.last ?? 0, 3400, accuracy: 0.001)
        XCTAssertEqual(curves.scenario.last ?? 0, 4600, accuracy: 0.001)
        XCTAssertEqual(curves.target, 5000)
    }

    func testScenarioChangeCombination() {
        let a = ScenarioChange(extraMonthly: 50, targetFactor: 0.9)
        let b = ScenarioChange(extraMonthly: 25, extraReturn: 0.01, oneOff: 100, stepUp: 0.03, targetFactor: 0.9)
        let c = a.combined(with: b)
        XCTAssertEqual(c.extraMonthly, 75)
        XCTAssertEqual(c.extraReturn, 0.01, accuracy: 0.0001)
        XCTAssertEqual(c.oneOff, 100)
        XCTAssertEqual(c.targetFactor, 0.81, accuracy: 0.0001)
        XCTAssertTrue(ScenarioChange().isEmpty)
        XCTAssertFalse(c.isEmpty)
    }
}
