import XCTest
import Foundation
@testable import MyBuddyCore

// Tests voor het echt toepassen en herstellen van versnellers.
// Alle verwachte waarden zijn met de hand nagerekend; geen enkele test hangt van de klok af.

private let accNov = YearMonth(year: 2026, month: 11)
private let accDec = YearMonth(year: 2026, month: 12)
/// "Nu" in alle tests: 12 oktober 2026, 12:00.
private let accNow = day(oct2026, 12)

private struct AccelFixture {
    var data: FinanceData
    var pot: Pot
    var goal: LifeGoal
}

/// Salaris 3000, huur 1000 en toeslag 100 (terugkerend), pot "Vakantie" met inleg 300 en beginsaldo 500 vanaf augustus.
/// Doel "Japan" (6000) wordt uit die pot betaald. Alle maanden t/m oktober zijn vastgelegd.
/// Eind oktober staat er 500 + 3 × 300 = 1400 in de pot; vrije ruimte oktober: 3100 - 1000 - 300 = 1800.
private func accPotFixture(target: Double = 6000) -> AccelFixture {
    var d = makeBaseData()
    let pot = Pot(name: "Vakantie", symbol: "airplane", monthlyContribution: 300, startMonth: aug2026)
    d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
    var g = LifeGoal(name: "Japan", kind: .vacation)
    g.targetAmount = target
    g.inflationAdjusted = false
    g.funding = .pot(pot.id)
    d.addGoal(g)
    d.materialize(upTo: oct2026)
    return AccelFixture(data: d, pot: pot, goal: g)
}

private func accPick(_ prefix: String, _ d: FinanceData, _ goal: LifeGoal) -> Accelerator? {
    d.accelerators(for: goal, current: oct2026, today: accNow).first { $0.id == prefix || $0.id.hasPrefix(prefix + "-") }
}

private func goalMonths(_ d: FinanceData, _ goal: LifeGoal) -> Int? {
    d.analyze(d.goal(goal.id) ?? goal, current: oct2026, today: accNow).monthsToGoal
}

private func accEuro(_ v: Double) -> String { Fmt.euro(v) }

/// Eigen toevalsgenerator met vaste zaadwaarde, zodat de test herhaalbaar is en niet van andere testbestanden afhangt.
private struct AccRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 11
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }

    /// Een bedrag in hele centen tussen `low` en `high` euro.
    mutating func amount(_ low: Int, _ high: Int) -> Double { Double(int(low * 100...high * 100)) / 100 }
}

private func accCents(_ value: Double) -> Int { Int((value * 100).rounded()) }


/// Veel gegevens tegelijk: twee potten, drie beleggingen (een gevolgde), een uurloon, een eenmalige uitgave en vijf
/// soorten doelen. Voor de tests die elke versneller op elk doel proberen.
private func accBigFixture() -> (data: FinanceData, goals: [LifeGoal]) {
    var d = makeBaseData()
    d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
    let vakantie = Pot(name: "Vakantie", symbol: "airplane", monthlyContribution: 300, startMonth: aug2026)
    let buffer = Pot(name: "Buffer", goalAmount: 2000, monthlyContribution: 200, startMonth: aug2026)
    d.addPot(vakantie, openingBalance: 500, now: day(aug2026, 2))
    d.addPot(buffer, openingBalance: 3000, now: day(aug2026, 2))
    d.addHolding(Holding(name: "Duur fonds", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.07, annualCost: 0.015,
                         monthlyContribution: 100, startMonth: aug2026), initialValue: 6000, now: day(sep2026, 1))
    d.addHolding(Holding(name: "Spaar", kind: .savings, ticker: nil, units: nil, expectedReturn: 0.02, annualCost: 0,
                         monthlyContribution: 50, startMonth: aug2026), initialValue: 4000, now: day(sep2026, 1))
    d.addHolding(Holding(name: "Gevolgd", kind: .etf, ticker: "VWCE.DE", units: 5, expectedReturn: 0.06, annualCost: 0.002,
                         startMonth: aug2026, lastPrice: 100, lastPriceDate: day(oct2026, 10)),
                 initialValue: 500, now: day(sep2026, 1))
    d.materialize(upTo: oct2026)
    d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
    d.upsertLine(MoneyLine(name: "Tandarts", amount: 300, isRecurring: false), kind: .expense, in: oct2026)
    d.editPlan(accDec) { _ in }   // een latere maand die al is vastgelegd

    var viaPot = LifeGoal(name: "Via pot", kind: .vacation)
    viaPot.targetAmount = 30_000
    viaPot.inflationAdjusted = false
    viaPot.funding = .pot(vakantie.id)
    var viaPortfolio = LifeGoal(name: "Via beleggingen", kind: .custom)
    viaPortfolio.targetAmount = 300_000
    viaPortfolio.inflationAdjusted = true
    viaPortfolio.funding = .portfolio
    var viaCustom = LifeGoal(name: "Eigen", kind: .custom)
    viaCustom.targetAmount = 40_000
    viaCustom.inflationAdjusted = false
    viaCustom.funding = .custom(start: 1000, monthly: 200, annualReturn: 0.04)
    var pension = LifeGoal(name: "Pensioen", kind: .retirement)
    pension.monthlySpending = 2300
    pension.otherMonthlyIncome = 1200
    pension.funding = .portfolio
    var partTime = LifeGoal(name: "Parttime", kind: .partTime)
    partTime.hoursFrom = 36
    partTime.hoursTo = 28
    partTime.funding = .custom(start: 5000, monthly: 600, annualReturn: 0.05)
    let goals = [viaPot, viaPortfolio, viaCustom, pension, partTime]
    for g in goals { d.addGoal(g) }
    return (d, goals)
}

final class AcceleratorApplyTests: XCTestCase {

    // MARK: Extra maandinleg

    func testFreeSpaceRaisesPotContributionFromThisMonthOn() throws {
        var f = accPotFixture()
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        XCTAssertEqual(acc.change.extraMonthly, 1800, accuracy: 0.001)
        // Op 12 oktober staat er 500 + augustus + september = 1100 in de pot (de inleg van oktober volgt op de 25e).
        XCTAssertEqual(goalMonths(f.data, f.goal), 17)   // (6000 - 1100) / 300 = 16,3

        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let d = f.data

        XCTAssertEqual(d.pot(f.pot.id)?.monthlyContribution ?? 0, 2100, accuracy: 0.001)
        XCTAssertEqual(d.allocation(f.pot.id, in: oct2026), 2100, accuracy: 0.001)
        // Het verleden verandert niet, de toekomst (nog niet vastgelegd) volgt de nieuwe inleg.
        XCTAssertEqual(d.allocation(f.pot.id, in: aug2026), 300, accuracy: 0.001)
        XCTAssertEqual(d.allocation(f.pot.id, in: sep2026), 300, accuracy: 0.001)
        XCTAssertEqual(d.allocation(f.pot.id, in: accNov), 2100, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: oct2026), 0, accuracy: 0.001)

        // De hogere inleg van oktober volgt pas op de 25e, dus het saldo van nu blijft 1100: (6000 - 1100) / 2100 = 2,3 -> 3 maanden.
        XCTAssertEqual(goalMonths(d, f.goal), 3)
        // De versneller rekende met dezelfde uitgangspunten en beloofde dus hetzelfde.
        XCTAssertEqual(acc.newMonths, 3)

        XCTAssertEqual(d.appliedAccelerators.count, 1)
        XCTAssertEqual(record.acceleratorID, "free")
        XCTAssertEqual(record.goalID, f.goal.id)
        XCTAssertEqual(record.title, acc.title)
        XCTAssertEqual(record.date, accNow)
        XCTAssertEqual(record.summary.first,
                       "Inleg Vakantie gaat van \(accEuro(300)) naar \(accEuro(2100)) per maand, vanaf \(Fmt.month(oct2026)).")
        XCTAssertEqual(record.summary.last,
                       "Je haalt Japan nu over \(Fmt.duration(months: 3)) in plaats van over \(Fmt.duration(months: 17)).")
    }

    func testBackupHoldsOnlyWhatChanged() throws {
        var f = accPotFixture()
        let other = Pot(name: "Reserve", monthlyContribution: 50, startMonth: aug2026)
        f.data.addPot(other, openingBalance: 100, now: day(aug2026, 2))
        f.data.materialize(upTo: oct2026)
        let acc = try XCTUnwrap(accPick("income5", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))

        XCTAssertEqual(record.before.pots.map(\.id), [f.pot.id])
        XCTAssertEqual(record.before.pots.first?.monthlyContribution, 300)
        XCTAssertTrue(record.before.holdings.isEmpty)
        XCTAssertTrue(record.before.goals.isEmpty)
        XCTAssertEqual(Set(record.before.plans.keys), [oct2026.key])
        XCTAssertTrue(record.before.newPlanKeys.isEmpty)
        XCTAssertNil(record.before.settings)
        XCTAssertNil(record.before.salary)
    }

    func testFivePercentOfIncomeAndFutureStoredMonthsFollow() throws {
        var f = accPotFixture()
        // December is al vastgelegd, met een eigen verdeling.
        f.data.setAllocation(f.pot.id, in: accDec, amount: 250)
        let acc = try XCTUnwrap(accPick("income5", f.data, f.goal))
        // 5% van 3100 (salaris + toeslag).
        XCTAssertEqual(acc.change.extraMonthly, 155, accuracy: 0.001)
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let d = f.data
        XCTAssertEqual(d.pot(f.pot.id)?.monthlyContribution ?? 0, 455, accuracy: 0.001)
        XCTAssertEqual(d.allocation(f.pot.id, in: oct2026), 455, accuracy: 0.001)
        // Vastgelegde latere maand: dezelfde verhoging bovenop de eigen verdeling.
        XCTAssertEqual(d.allocation(f.pot.id, in: accDec), 405, accuracy: 0.001)
        // Maand daartussen is niet vastgelegd: volgt de nieuwe standaard.
        XCTAssertEqual(d.allocation(f.pot.id, in: accNov), 455, accuracy: 0.001)
    }

    func testPastStoredMonthsWithoutEntryKeepTheirValue() throws {
        var f = accPotFixture()
        // Een maand zonder eigen verdeling voor de pot (zoals bij een pot die later is toegevoegd).
        f.data.months[sep2026.key]?.allocations.removeValue(forKey: f.pot.id.uuidString)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: sep2026), 300, accuracy: 0.001)
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        f.data.apply(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: sep2026), 300, accuracy: 0.001)
        // Ook na het opnieuw vastleggen van het verleden (gebeurt bij het opstarten van de app).
        f.data.materialize(upTo: oct2026)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: sep2026), 300, accuracy: 0.001)
    }

    func testPortfolioContributionIsSpreadByCurrentContribution() throws {
        var d = makeBaseData()
        d.addHolding(Holding(name: "Wereld", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                             monthlyContribution: 200, startMonth: aug2026), initialValue: 5000, now: day(sep2026, 1))
        d.addHolding(Holding(name: "Obligaties", kind: .bonds, ticker: nil, units: nil, expectedReturn: 0.03, annualCost: 0.003,
                             monthlyContribution: 50, startMonth: aug2026), initialValue: 2000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Rust", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)

        // Inkomen 3100 - huur 1000 - inleg 250 = 1850 vrij.
        let acc = try XCTUnwrap(accPick("free", d, g))
        XCTAssertEqual(acc.change.extraMonthly, 1850, accuracy: 0.001)
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))

        // Naar verhouding 200 : 50 = 80% : 20%.
        let world = d.holdings[0], bonds = d.holdings[1]
        XCTAssertEqual(world.monthlyContribution, 200 + 1480, accuracy: 0.001)
        XCTAssertEqual(bonds.monthlyContribution, 50 + 370, accuracy: 0.001)
        XCTAssertEqual(d.allocation(world.id, in: oct2026), 1680, accuracy: 0.001)
        XCTAssertEqual(d.allocation(bonds.id, in: oct2026), 420, accuracy: 0.001)
        XCTAssertEqual(d.allocation(world.id, in: accNov), 1680, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: oct2026), 0, accuracy: 0.001)
        XCTAssertEqual(d.monthlyInvestment(current: oct2026), 2100, accuracy: 0.001)
        XCTAssertEqual(record.summary.count, 3)   // twee beleggingen + de nieuwe looptijd
        XCTAssertEqual(Set(record.before.holdings.map(\.id)), [world.id, bonds.id])
    }

    func testPortfolioSpreadNeverLosesACent() throws {
        var d = makeBaseData()
        for n in 0..<3 {
            d.addHolding(Holding(name: "Fonds \(n)", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                                 monthlyContribution: 100, startMonth: aug2026), initialValue: 1000, now: day(sep2026, 1))
        }
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Rust", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)
        var acc = try XCTUnwrap(accPick("free", d, g))
        acc.change.extraMonthly = 100   // 100 over drie gelijke delen: 33,34 / 33,33 / 33,33
        let before = d.monthlyInvestment(current: oct2026)
        XCTAssertNotNil(d.apply(acc, for: g, current: oct2026, now: accNow))
        XCTAssertEqual(d.monthlyInvestment(current: oct2026), before + 100, accuracy: 0.0001)
        let shares = d.holdings.map { $0.monthlyContribution - 100 }.sorted()
        XCTAssertEqual(shares[0], 33.33, accuracy: 0.0001)
        XCTAssertEqual(shares[1], 33.33, accuracy: 0.0001)
        XCTAssertEqual(shares[2], 33.34, accuracy: 0.0001)
    }

    func testCustomFundingRaisesTheMonthlyAmountOfTheGoal() throws {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Eigen", kind: .custom)
        g.targetAmount = 20_000
        g.inflationAdjusted = false
        g.funding = .custom(start: 1000, monthly: 200, annualReturn: 0)
        d.addGoal(g)
        // 3100 - 1000 = 2100 vrij.
        let acc = try XCTUnwrap(accPick("free", d, g))
        XCTAssertEqual(acc.change.extraMonthly, 2100, accuracy: 0.001)
        XCTAssertEqual(goalMonths(d, g), 95)             // 19000 / 200
        XCTAssertEqual(acc.newMonths, 9)             // 19000 / 2300 = 8,3
        XCTAssertNotNil(d.apply(acc, for: g, current: oct2026, now: accNow))
        XCTAssertEqual(d.goal(g.id)?.funding, .custom(start: 1000, monthly: 2300, annualReturn: 0))
        XCTAssertEqual(goalMonths(d, g), 9)
        // Een eigen financiering raakt geen spaarpotten of maandplannen.
        XCTAssertEqual(d.remaining(in: oct2026), 2100, accuracy: 0.001)
    }

    // MARK: Uitgave 10% omlaag

    func testExpenseCutLowersRentFromThisMonthAndRaisesTheContribution() throws {
        var f = accPotFixture()
        // December is al vastgelegd (met de afgeleide huurregel).
        f.data.editPlan(accDec) { _ in }
        let acc = try XCTUnwrap(accPick("expense", f.data, f.goal))
        XCTAssertEqual(acc.change.extraMonthly, 100, accuracy: 0.001)
        let remainingBefore = f.data.remaining(in: oct2026)
        let decemberBefore = f.data.remaining(in: accDec)
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let d = f.data

        func rent(_ m: YearMonth) -> Double? { d.plan(for: m).expenses.first { $0.name == "Huur" }?.amount }
        XCTAssertEqual(rent(sep2026), 1000)
        XCTAssertEqual(rent(oct2026), 900)
        XCTAssertEqual(rent(accNov), 900)   // niet vastgelegd: volgt de nieuwe huur
        XCTAssertEqual(rent(accDec), 900)   // vastgelegd: ook aangepast
        XCTAssertEqual(d.allocation(f.pot.id, in: oct2026), 400, accuracy: 0.001)
        XCTAssertEqual(d.allocation(f.pot.id, in: accDec), 400, accuracy: 0.001)
        XCTAssertEqual(d.pot(f.pot.id)?.monthlyContribution ?? 0, 400, accuracy: 0.001)
        // Het maandbudget blijft gelijk: 100 minder uitgaven, 100 meer inleg.
        XCTAssertEqual(d.remaining(in: oct2026), remainingBefore, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: accDec), decemberBefore, accuracy: 0.001)
        XCTAssertEqual(record.summary[0],
                       "Uitgave Huur gaat van \(accEuro(1000)) naar \(accEuro(900)) per maand, vanaf \(Fmt.month(oct2026)).")
        XCTAssertEqual(record.summary[1],
                       "Inleg Vakantie gaat van \(accEuro(300)) naar \(accEuro(400)) per maand, vanaf \(Fmt.month(oct2026)).")
        // Het saldo van 12 oktober is 500 + 300 + 300 = 1100 (de hogere inleg volgt op de 25e): (6000 - 1100) / 400 = 12,25 -> 13 maanden.
        XCTAssertEqual(goalMonths(d, f.goal), 13)
    }

    func testASingleExpenseIsNotOfferedAndIsRefusedWhenAsked() throws {
        var f = accPotFixture()
        f.data.upsertLine(MoneyLine(name: "Tandarts", amount: 300, isRecurring: false), kind: .expense, in: oct2026)
        let list = f.data.accelerators(for: f.goal, current: oct2026, today: accNow)
        XCTAssertNil(list.first { $0.title.contains("Tandarts") }, "een eenmalige uitgave levert geen vaste inleg op")
        XCTAssertNotNil(list.first { $0.title == "Verlaag Huur met 10%" })

        // Wordt hij toch aangeboden (bijvoorbeeld een oude versneller), dan weigert de app met een uitleg.
        let lineID = try XCTUnwrap(f.data.plan(for: oct2026).expenses.first { $0.name == "Tandarts" }?.id)
        let acc = Accelerator(id: "expense-\(lineID.uuidString)", title: "Verlaag Tandarts met 10%", detail: "", symbol: "scissors",
                              change: ScenarioChange(extraMonthly: 30), newMonths: 10, monthsSaved: 1, makesReachable: false)
        let copy = f.data
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.message, "Tandarts komt maar één keer voor. Verlagen levert je doel geen vaste maandinleg op.")
        XCTAssertNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data, copy)
    }

    func testExpensePaidFromAPotFreesOnlyTheBankPart() throws {
        var f = accPotFixture()
        let buffer = Pot(name: "Buffer", monthlyContribution: 0, startMonth: aug2026)
        f.data.addPot(buffer, openingBalance: 5000, now: day(aug2026, 2))
        // Huur van 1000 waarvan 950 uit de buffer komt: 10% minder (100) bespaart de bank maar 50.
        var rent = f.data.plan(for: oct2026).expenses.first { $0.name == "Huur" }!
        rent.potShares = [PotShare(potID: buffer.id, amount: 950)]
        f.data.upsertLine(rent, kind: .expense, in: oct2026)
        let acc = try XCTUnwrap(accPick("expense", f.data, f.goal))
        let before = f.data.remaining(in: oct2026)
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.plan(for: oct2026).expenses.first { $0.name == "Huur" }?.amount, 900)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: oct2026), 350, accuracy: 0.001)
        XCTAssertEqual(f.data.remaining(in: oct2026), before, accuracy: 0.001)
    }

    // MARK: Extra uren

    func testExtraHoursAddsRecurringIncomeAndRaisesTheContribution() throws {
        var f = accPotFixture()
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        f.data.editPlan(accDec) { _ in }
        let acc = try XCTUnwrap(accPick("hours", f.data, f.goal))
        // 20 × 2 × 52 / 12 = 173,33
        XCTAssertEqual(acc.change.extraMonthly, 173.33, accuracy: 0.001)
        let incomeBefore = f.data.income(in: oct2026)
        let remainingBefore = f.data.remaining(in: oct2026)
        let novemberBefore = f.data.remaining(in: accNov)
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let d = f.data

        XCTAssertEqual(d.income(in: sep2026), incomeBefore, accuracy: 0.001)             // verleden blijft zoals het was
        XCTAssertEqual(d.income(in: oct2026), incomeBefore + 173.33, accuracy: 0.001)
        XCTAssertEqual(d.income(in: accNov), incomeBefore + 173.33, accuracy: 0.001)     // niet vastgelegd
        XCTAssertEqual(d.income(in: accDec), incomeBefore + 173.33, accuracy: 0.001)     // vastgelegd
        XCTAssertEqual(d.allocation(f.pot.id, in: oct2026), 473.33, accuracy: 0.001)
        XCTAssertEqual(d.allocation(f.pot.id, in: accDec), 473.33, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: oct2026), remainingBefore, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: accNov), novemberBefore, accuracy: 0.001)
        XCTAssertTrue(record.summary[0].contains(Fmt.euroExact(20)), "het uurloon staat exact in de zin: \(record.summary[0])")
        XCTAssertEqual(record.summary[0], "Extra inkomsten van \(accEuro(173.33)) per maand erbij, vanaf \(Fmt.month(oct2026)), "
            + "als \"Extra uren (2 uur per week)\". Bij een uurloon van \(Fmt.euroExact(20)).")
        XCTAssertFalse(record.summary[0].contains("(Extra uren"), "geen haakjes in haakjes")
    }

    func testSecondGoalCannotApplyTheSameHoursAgain() throws {
        var f = accPotFixture()
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        var second = LifeGoal(name: "Tweede", kind: .custom)
        second.targetAmount = 9000
        second.inflationAdjusted = false
        second.funding = .pot(f.pot.id)
        f.data.addGoal(second)
        let acc = try XCTUnwrap(accPick("hours", f.data, f.goal))
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let snapshot = f.data
        XCTAssertNil(f.data.apply(acc, for: second, current: oct2026, now: accNow))
        XCTAssertEqual(f.data, snapshot)
        // De pagina laat bij het tweede doel zien voor welk doel het al is toegepast.
        XCTAssertEqual(f.data.applicationBlocking(acc, for: second.id, current: oct2026)?.goalID, f.goal.id)
        let plan = f.data.applyPlan(acc, for: second, current: oct2026, now: accNow)
        XCTAssertFalse(plan.alreadyApplied, "voor dit doel is hij niet toegepast")
        XCTAssertEqual(plan.message, "Deze versneller is al toegepast voor Japan. Herstel hem eerst als je hem opnieuw wilt toepassen.")
    }

    // MARK: Eenmalig uit de bank of een pot

    private func bankPotFixture() -> AccelFixture {
        var f = accPotFixture(target: 20_000)
        f.data.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        return f
    }

    func testBankSurplusMovesToThePotAndBalancesAdd() throws {
        var f = bankPotFixture()
        let acc = try XCTUnwrap(accPick("bank", f.data, f.goal))
        // Buffer: 2 maanden × gemiddelde uitgaven (1050 + 1000 + 1000) / 3 = 1016,67 -> 2033,34; overschot 7966,66.
        XCTAssertEqual(acc.change.oneOff, 7966.66, accuracy: 0.001)
        XCTAssertEqual(f.data.bankBalanceNow(current: oct2026, today: accNow), 10_000, accuracy: 0.001)
        let potBefore = f.data.potBalanceNow(f.pot.id, current: oct2026, today: accNow)

        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let d = f.data
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: accNow), 2033.34, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(f.pot.id, current: oct2026, today: accNow), potBefore + 7966.66, accuracy: 0.001)
        XCTAssertEqual(d.bankEntries.count, 1)
        XCTAssertEqual(d.bankEntries.first?.kind, .toPot)
        XCTAssertEqual(d.bankEntries.first?.amount ?? 0, -7966.66, accuracy: 0.001)
        XCTAssertEqual(d.potEntries.filter { $0.kind == .deposit }.count, 1)
        // Start op 12 oktober: 1100 + 7966,66 = 9066,66; inleg 300: (20000 - 9066,66) / 300 = 36,4 -> 37.
        XCTAssertEqual(goalMonths(d, f.goal), 37)
        XCTAssertEqual(acc.newMonths, 37)
        XCTAssertTrue(record.before.isEmpty, "geen enkele entiteit is aangepast, alleen boekingen erbij")
        // Daarna is er geen overschot meer en bestaat de versneller niet meer.
        XCTAssertNil(accPick("bank", d, f.goal))
    }

    func testBankSurplusIntoTheStockPortfolio() throws {
        var d = makeBaseData()
        d.addHolding(Holding(name: "Wereld", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                             startMonth: aug2026), initialValue: 6000, now: day(sep2026, 1))
        d.addHolding(Holding(name: "Spaar", kind: .savings, ticker: nil, units: nil, expectedReturn: 0.02, annualCost: 0,
                             startMonth: aug2026), initialValue: 4000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)

        let acc = try XCTUnwrap(accPick("bank", d, g))
        XCTAssertEqual(acc.change.oneOff, 7966.66, accuracy: 0.001)
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))
        // Naar verhouding 60% : 40% van 7966,66 = 4779,996 / 3186,664 -> 4780,00 en 3186,66.
        XCTAssertEqual(d.portfolioValue(current: oct2026), 10_000 + 7966.66, accuracy: 0.001)
        XCTAssertEqual(d.holdingValueNow(d.holdings[0], current: oct2026), 6000 + 4780.00, accuracy: 0.001)
        XCTAssertEqual(d.holdingValueNow(d.holdings[1], current: oct2026), 4000 + 3186.66, accuracy: 0.001)
        XCTAssertEqual(d.portfolioInvested(current: oct2026), d.holdings.reduce(0) { $0 + $1.investedTotal }, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: accNow), 2033.34, accuracy: 0.001)
        XCTAssertEqual(d.bankEntries.count, 1)
        XCTAssertEqual(d.bankEntries.first?.kind, .withdrawal)
        // Het rendement per belegging is niet veranderd; de looptijd volgt de voorspelling (start + eenmalig).
        XCTAssertEqual(goalMonths(d, g), acc.newMonths)
        XCTAssertEqual(Set(record.before.holdings.map(\.id)), Set(d.holdings.map(\.id)))
    }

    func testTrackedHoldingGetsMoreUnitsWhenMoneyIsAdded() throws {
        var d = makeBaseData()
        d.addHolding(Holding(name: "Gevolgd", kind: .etf, ticker: "VWCE.DE", units: 10, expectedReturn: 0.06, annualCost: 0.002,
                             startMonth: aug2026, lastPrice: 100, lastPriceDate: day(oct2026, 10)),
                     initialValue: 1000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)
        let acc = try XCTUnwrap(accPick("bank", d, g))
        XCTAssertNotNil(d.apply(acc, for: g, current: oct2026, now: accNow))
        // 7966,66 / koers 100 = 79,6666 stuks erbij; de waarde (aantal × koers) klopt met het nieuwe meetpunt.
        let h = d.holdings[0]
        XCTAssertEqual(h.units ?? 0, 10 + 79.6666, accuracy: 0.0001)
        XCTAssertEqual((h.units ?? 0) * 100, d.holdingValueNow(h, current: oct2026), accuracy: 0.01)
        // Een nieuwe koers op dezelfde dag vervangt het meetpunt, maar de waarde blijft kloppen.
        d.recordPrice(holdingID: h.id, price: 100, currency: "EUR", date: day(oct2026, 12).addingTimeInterval(60))
        XCTAssertEqual(d.holdingValueNow(d.holdings[0], current: oct2026), 8966.66, accuracy: 0.01)
    }

    func testPotSurplusMovesToTheFundingPot() throws {
        var f = accPotFixture()
        let buffer = Pot(name: "Buffer", goalAmount: 2000, monthlyContribution: 200, startMonth: aug2026)
        f.data.addPot(buffer, openingBalance: 3000, now: day(aug2026, 2))
        f.data.materialize(upTo: oct2026)
        // Op 12 oktober staat er in Buffer 3000 + augustus + september = 3400 (de inleg van oktober volgt op de 25e):
        // 1400 boven het doel van 2000. Dat is wat je nu kunt overboeken.
        let acc = try XCTUnwrap(accPick("pot", f.data, f.goal))
        XCTAssertEqual(acc.change.oneOff, 1400, accuracy: 0.001)
        XCTAssertEqual(acc.newMonths, 12)   // start 1100 + 1400 = 2500, (6000 - 2500) / 300 = 11,7
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let d = f.data
        XCTAssertEqual(d.potBalanceNow(buffer.id, current: oct2026, today: accNow), 2000, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(f.pot.id, current: oct2026, today: accNow), 1100 + 1400, accuracy: 0.001)
        // Eind oktober komt de inleg van beide potten er nog bij: Buffer 2200, Vakantie 2800.
        XCTAssertEqual(d.potBalance(buffer.id, at: oct2026), 2200, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(f.pot.id, at: oct2026), 2800, accuracy: 0.001)
        XCTAssertEqual(goalMonths(d, f.goal), 12)
        XCTAssertEqual(d.potEntries.filter { $0.kind == .transferOut }.count, 1)
        XCTAssertEqual(d.potEntries.filter { $0.kind == .transferIn }.count, 1)
        XCTAssertEqual(d.bankEntries.count, 0)
        XCTAssertTrue(record.before.isEmpty)
        XCTAssertNil(accPick("pot", d, f.goal), "het overschot is weg")
    }

    func testPotSurplusIntoThePortfolio() throws {
        var d = makeBaseData()
        let buffer = Pot(name: "Buffer", goalAmount: 2000, monthlyContribution: 200, startMonth: aug2026)
        d.addPot(buffer, openingBalance: 3000, now: day(aug2026, 2))
        d.addHolding(Holding(name: "Wereld", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                             startMonth: aug2026), initialValue: 5000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)
        let acc = try XCTUnwrap(accPick("pot", d, g))
        XCTAssertEqual(acc.change.oneOff, 1400, accuracy: 0.001)   // 3000 + augustus + september - doel 2000
        XCTAssertNotNil(d.apply(acc, for: g, current: oct2026, now: accNow))
        XCTAssertEqual(d.potBalanceNow(buffer.id, current: oct2026, today: accNow), 2000, accuracy: 0.001)
        XCTAssertEqual(d.portfolioValue(current: oct2026), 6400, accuracy: 0.001)
        XCTAssertEqual(goalMonths(d, g), acc.newMonths)
    }

    func testBankAndPotSurplusRaiseTheStartAmountOfACustomGoal() throws {
        var d = makeBaseData()
        let buffer = Pot(name: "Buffer", goalAmount: 2000, monthlyContribution: 200, startMonth: aug2026)
        d.addPot(buffer, openingBalance: 3000, now: day(aug2026, 2))
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        var g = LifeGoal(name: "Eigen", kind: .custom)
        g.targetAmount = 50_000
        g.inflationAdjusted = false
        g.funding = .custom(start: 1000, monthly: 200, annualReturn: 0.05)
        d.addGoal(g)

        let bank = try XCTUnwrap(accPick("bank", d, g))
        let potAcc = try XCTUnwrap(accPick("pot", d, g))
        XCTAssertEqual(potAcc.change.oneOff, 1400, accuracy: 0.001)   // 3000 + augustus + september - doel 2000
        let potBefore = d.potBalance(buffer.id, at: oct2026)
        let bankBefore = d.bankBalanceNow(current: oct2026, today: accNow)

        XCTAssertNotNil(d.apply(potAcc, for: g, current: oct2026, now: accNow))
        guard case .custom(let startAfterPot, let monthly, let rate) = try XCTUnwrap(d.goal(g.id)).funding else {
            return XCTFail("de financiering moet eigen waarden blijven")
        }
        XCTAssertEqual(startAfterPot, 2400, accuracy: 0.001)
        XCTAssertEqual(monthly, 200, accuracy: 0.001)
        XCTAssertEqual(rate, 0.05, accuracy: 1e-12)

        XCTAssertNotNil(d.apply(bank, for: g, current: oct2026, now: accNow))
        guard case .custom(let startAfterBank, _, _) = try XCTUnwrap(d.goal(g.id)).funding else {
            return XCTFail("de financiering moet eigen waarden blijven")
        }
        XCTAssertEqual(startAfterBank, 2400 + 7966.66, accuracy: 0.001)
        // Een eigen financiering heeft geen echte rekening: er wordt niets overgeboekt.
        XCTAssertEqual(d.potBalance(buffer.id, at: oct2026), potBefore, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: accNow), bankBefore, accuracy: 0.001)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertEqual(d.appliedAccelerators.count, 2)
    }

    // MARK: Rendement en kosten

    private func costFixture() -> (data: FinanceData, goal: LifeGoal) {
        var d = makeBaseData()
        d.addHolding(Holding(name: "Duur fonds", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.07, annualCost: 0.015,
                             startMonth: aug2026), initialValue: 6000, now: day(sep2026, 1))
        d.addHolding(Holding(name: "Spaar", kind: .savings, ticker: nil, units: nil, expectedReturn: 0.02, annualCost: 0,
                             startMonth: aug2026), initialValue: 4000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)
        return (d, g)
    }

    func testLowerCostsSetsTheCostOfTheMostExpensiveHolding() throws {
        var (d, g) = costFixture()
        let acc = try XCTUnwrap(accPick("costs", d, g))
        // Rendement vooraf: (6000 × 0,055 + 4000 × 0,02) / 10000 = 4,1%; erna: (6000 × 0,068 + 80) / 10000 = 4,88%.
        XCTAssertEqual(d.weightedNetReturn(current: oct2026), 0.041, accuracy: 1e-9)
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))
        XCTAssertEqual(d.holdings[0].annualCost, 0.002, accuracy: 1e-12)
        XCTAssertEqual(d.holdings[1].annualCost, 0, accuracy: 1e-12)
        XCTAssertEqual(d.weightedNetReturn(current: oct2026), 0.0488, accuracy: 1e-9)
        XCTAssertEqual(acc.change.extraReturn, 0.0078, accuracy: 1e-9)
        XCTAssertEqual(goalMonths(d, g), Growth.monthsToReach(target: 100_000, start: 10_000, monthly: 0, annualReturn: 0.0488))
        XCTAssertEqual(goalMonths(d, g), acc.newMonths)
        XCTAssertEqual(record.before.holdings.map(\.name), ["Duur fonds"])
        XCTAssertEqual(record.before.holdings.first?.annualCost, 0.015)
        XCTAssertTrue(record.summary[0].contains(Fmt.percent(0.015, digits: 2)))
    }

    func testShiftMovesHalfOfTheLowestReturningHolding() throws {
        var (d, g) = costFixture()
        let acc = try XCTUnwrap(accPick("shift", d, g))
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))
        // De helft van Spaar (2000) gaat naar Duur fonds: 8000 en 2000.
        XCTAssertEqual(d.holdingValueNow(d.holdings[0], current: oct2026), 8000, accuracy: 0.001)
        XCTAssertEqual(d.holdingValueNow(d.holdings[1], current: oct2026), 2000, accuracy: 0.001)
        XCTAssertEqual(d.portfolioValue(current: oct2026), 10_000, accuracy: 0.001)
        // (8000 × 0,055 + 2000 × 0,02) / 10000 = 4,8%
        XCTAssertEqual(d.weightedNetReturn(current: oct2026), 0.048, accuracy: 1e-9)
        XCTAssertEqual(goalMonths(d, g), acc.newMonths)
        XCTAssertEqual(Set(record.before.holdings.map(\.name)), ["Duur fonds", "Spaar"])
    }

    // MARK: Jaarlijkse stijging en lager doel

    func testStepUpBecomesTheEquivalentFixedIncrease() throws {
        var f = accPotFixture(target: 60_000)
        let acc = try XCTUnwrap(accPick("stepup", f.data, f.goal))
        let predicted = try XCTUnwrap(acc.newMonths)
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let d = f.data
        let monthly = d.allocation(f.pot.id, in: oct2026)
        // Toepassen is eenmalig; de titel en de uitleg bovenaan zeggen dat eerlijk (niet "elk jaar 3%").
        XCTAssertEqual(record.title, "Inleg eenmalig \(accEuro(monthly - 300)) per maand verhoogd")
        XCTAssertFalse(record.title.contains("elk jaar"))
        XCTAssertTrue(try XCTUnwrap(plan.headline).contains("geen jaarlijkse verhoging"))
        XCTAssertTrue(try XCTUnwrap(plan.headline).contains(accEuro(monthly - 300)))
        XCTAssertGreaterThan(monthly, 300)
        XCTAssertEqual(monthly, monthly.rounded(), "hele euro's")
        // Het doel is minstens zo snel als beloofd.
        let after = try XCTUnwrap(goalMonths(d, f.goal))
        XCTAssertLessThanOrEqual(after, predicted)
        // En de inleg is niet hoger dan nodig: één euro minder haalt de belofte niet.
        let start = d.potBalanceNow(f.pot.id, current: oct2026, today: accNow)   // de verhoging van deze maand volgt op de 25e: 1100
        let lessMonths = Growth.monthsToReach(target: 60_000, start: start, monthly: monthly - 1, annualReturn: 0)
        XCTAssertGreaterThan(lessMonths ?? Int.max, predicted)
        XCTAssertTrue(record.summary[0].contains("Inleg Vakantie"))
    }

    func testLowerTargetPerKindOfGoal() throws {
        var d = makeBaseData()
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 36)
        d.materialize(upTo: oct2026)

        var retirement = LifeGoal(name: "Pensioen", kind: .retirement)
        retirement.monthlySpending = 2300
        retirement.otherMonthlyIncome = 1200
        retirement.withdrawalRate = 0.04
        retirement.inflationAdjusted = false
        retirement.funding = .custom(start: 50_000, monthly: 1000, annualReturn: 0.05)

        var partTime = LifeGoal(name: "4 dagen", kind: .partTime)
        partTime.hoursFrom = 36
        partTime.hoursTo = 28
        partTime.withdrawalRate = 0.04
        partTime.inflationAdjusted = false
        partTime.funding = .custom(start: 20_000, monthly: 800, annualReturn: 0.05)

        var vacation = LifeGoal(name: "Reis", kind: .vacation)
        vacation.targetAmount = 8000
        vacation.inflationAdjusted = false
        vacation.funding = .custom(start: 1000, monthly: 300, annualReturn: 0)

        for g in [retirement, partTime, vacation] { d.addGoal(g) }

        // Pensioen: (2300 - 1200) × 12 / 0,04 = 330.000 -> 10% minder = 297.000, dus 2190 per maand.
        XCTAssertEqual(d.goalInputs(for: retirement, current: oct2026).target, 330_000, accuracy: 0.01)
        let pensionAcc = try XCTUnwrap(accPick("target", d, retirement))
        XCTAssertNotNil(d.apply(pensionAcc, for: retirement, current: oct2026, now: accNow))
        XCTAssertEqual(d.goal(retirement.id)?.monthlySpending ?? 0, 2190, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: d.goal(retirement.id)!, current: oct2026).target, 297_000, accuracy: 0.05)
        XCTAssertEqual(goalMonths(d, retirement), pensionAcc.newMonths)

        // Parttime: 3000 × (1 - 28/36) = 666,67 gat (op centen) -> 90% = 600; kapitaal 200.001 -> 180.000.
        XCTAssertEqual(d.goalInputs(for: partTime, current: oct2026).target, 200_001, accuracy: 0.05)
        let partAcc = try XCTUnwrap(accPick("target", d, partTime))
        XCTAssertNotNil(d.apply(partAcc, for: partTime, current: oct2026, now: accNow))
        XCTAssertEqual(d.goal(partTime.id)?.monthlyGapOverride ?? 0, 600, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: d.goal(partTime.id)!, current: oct2026).target, 180_000, accuracy: 0.05)
        XCTAssertEqual(goalMonths(d, partTime), partAcc.newMonths)

        // Vakantie: 8000 -> 7200.
        let tripAcc = try XCTUnwrap(accPick("target", d, vacation))
        let record = try XCTUnwrap(d.apply(tripAcc, for: vacation, current: oct2026, now: accNow))
        XCTAssertEqual(d.goal(vacation.id)?.targetAmount ?? 0, 7200, accuracy: 0.001)
        XCTAssertEqual(goalMonths(d, vacation), tripAcc.newMonths)
        XCTAssertEqual(record.summary[0], "Het doelbedrag van Reis gaat van \(accEuro(8000)) naar \(accEuro(7200)).")
        XCTAssertEqual(record.before.goals.map(\.targetAmount), [8000])
        XCTAssertEqual(d.appliedAccelerators.count, 3)
    }

    // MARK: Beschrijving (applyPlan)

    func testPlanDescribesTheChangesWithoutChangingAnything() throws {
        let f = accPotFixture()
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        let copy = f.data
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertEqual(f.data, copy)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertEqual(plan.lines.count, 1)
        XCTAssertEqual(plan.lines[0].title, "Inleg Vakantie")
        XCTAssertEqual(plan.lines[0].oldValue, accEuro(300))
        XCTAssertEqual(plan.lines[0].newValue, accEuro(2100))
        XCTAssertEqual(plan.lines[0].detail, "per maand, vanaf \(Fmt.month(oct2026))")
        XCTAssertEqual(plan.monthsBefore, 17)   // (6000 - 1100) / 300 = 16,3
        XCTAssertEqual(plan.monthsAfter, 3)     // (6000 - 1100) / 2100 = 2,3
        XCTAssertNil(plan.message)
        XCTAssertNil(plan.headline)
        XCTAssertFalse(plan.alreadyApplied)

        // Dezelfde zinnen komen in de samenvatting van de echte toepassing.
        var applied = f.data
        let record = try XCTUnwrap(applied.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(Array(record.summary.prefix(plan.lines.count)), plan.lines.map(\.sentence))
    }

    func testPlanIsEmptyWhenThereIsNothingToDo() throws {
        // Een doel uit je beleggingen zonder beleggingen: de inleg kan nergens heen.
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)
        let acc = Accelerator(id: "free", title: "Zet je vrije ruimte in", detail: "", symbol: "tray",
                              change: ScenarioChange(extraMonthly: 500), newMonths: 100, monthsSaved: nil, makesReachable: true)
        let plan = d.applyPlan(acc, for: g, current: oct2026, now: accNow)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertNotNil(plan.message)
        let copy = d
        XCTAssertNil(d.apply(acc, for: g, current: oct2026, now: accNow))
        XCTAssertEqual(d, copy)
        XCTAssertTrue(d.appliedAccelerators.isEmpty)
    }

    func testUnknownAcceleratorChangesNothing() {
        var f = accPotFixture()
        let acc = Accelerator(id: "bestaat-niet", title: "?", detail: "", symbol: "questionmark",
                              change: ScenarioChange(extraMonthly: 10), newMonths: 1, monthsSaved: 1, makesReachable: false)
        let copy = f.data
        XCTAssertNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data, copy)
    }

    func testDeletedPotOfTheGoalGivesAnExplanation() throws {
        var f = accPotFixture()
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        f.data.pots.removeAll()
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.message, "De spaarpot van dit doel bestaat niet meer.")
    }

    // MARK: Dubbel toepassen

    func testApplyingTheSameAcceleratorTwiceIsRefused() throws {
        var f = accPotFixture()
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        let afterFirst = f.data

        XCTAssertNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data, afterFirst)
        XCTAssertEqual(f.data.appliedAccelerators.count, 1)
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertTrue(plan.alreadyApplied)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertNotNil(plan.message)
        XCTAssertNotNil(f.data.appliedAccelerator("free", for: f.goal.id))

        // Na herstellen mag het weer.
        let id = try XCTUnwrap(f.data.appliedAccelerators.first?.id)
        XCTAssertTrue(f.data.restoreAccelerator(id))
        XCTAssertNil(f.data.appliedAccelerator("free", for: f.goal.id))
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
    }

    // MARK: Herstellen

    func testRestoreGivesBackExactlyTheOldState() throws {
        var f = accPotFixture()
        let original = f.data
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertNotEqual(f.data, original)
        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertEqual(f.data, original)
        XCTAssertTrue(f.data.appliedAccelerators.isEmpty)
        XCTAssertEqual(goalMonths(f.data, f.goal), 17)
    }

    func testRestoreOfAnUnknownRecordDoesNothing() {
        var f = accPotFixture()
        let copy = f.data
        XCTAssertFalse(f.data.restoreAccelerator(UUID()))
        XCTAssertEqual(f.data, copy)
    }

    func testRestoreInReverseOrderOfTwoAcceleratorsIsExact() throws {
        var f = accPotFixture()
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        f.data.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        let original = f.data
        let first = try XCTUnwrap(accPick("free", f.data, f.goal))
        let r1 = try XCTUnwrap(f.data.apply(first, for: f.goal, current: oct2026, now: accNow))
        let afterFirst = f.data
        let second = try XCTUnwrap(accPick("bank", f.data, f.goal))
        let r2 = try XCTUnwrap(f.data.apply(second, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.appliedAccelerators.map(\.id), [r1.id, r2.id])

        XCTAssertTrue(f.data.restoreAccelerator(r2.id))
        XCTAssertEqual(f.data, afterFirst)
        XCTAssertTrue(f.data.restoreAccelerator(r1.id))
        XCTAssertEqual(f.data, original)
    }

    /// De oude, niet-aanbevolen weg (`ignoringOrder`): in elke volgorde komt uiteindelijk exact het origineel terug.
    func testRestoreIgnoringTheOrderStillEndsAtTheOriginalAndNeverCrashes() throws {
        let orders: [[Int]] = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            var f = accPotFixture()
            f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
            f.data.editPlan(accDec) { _ in }
            let original = f.data
            var records: [AppliedAccelerator] = []
            for id in ["income5", "expense", "hours"] {
                let acc = try XCTUnwrap(accPick(id, f.data, f.goal), id)
                records.append(try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow), id))
            }
            XCTAssertEqual(f.data.appliedAccelerators.count, 3)
            var left = 3
            for index in order {
                XCTAssertTrue(f.data.restoreAccelerator(records[index].id, ignoringOrder: true), "volgorde \(order)")
                left -= 1
                XCTAssertEqual(f.data.appliedAccelerators.count, left)
            }
            XCTAssertEqual(f.data, original, "volgorde \(order)")
        }
    }

    // MARK: Herstellen in de goede volgorde

    /// Twee toepassingen die dezelfde inleg aanpassen: eerst de nieuwste terugzetten. Anders verdwijnt het effect van de
    /// nieuwste terwijl die als toegepast blijft staan.
    func testRestoreOfAnOlderApplicationWaitsForTheNewerOneOnTheSameField() throws {
        var f = accPotFixture()
        let original = f.data
        let a = try XCTUnwrap(f.data.apply(try XCTUnwrap(accPick("income5", f.data, f.goal)), for: f.goal, current: oct2026, now: accNow))
        let b = try XCTUnwrap(f.data.apply(try XCTUnwrap(accPick("expense", f.data, f.goal)), for: f.goal, current: oct2026, now: accNow))
        let both = f.data
        // 5% van 3100 = 155 en 10% van de huur = 100.
        XCTAssertEqual(both.pot(f.pot.id)?.monthlyContribution, 300 + 155 + 100)

        XCTAssertEqual(f.data.restoreBlocker(for: a.id)?.id, b.id)
        XCTAssertNil(f.data.restoreBlocker(for: b.id))
        XCTAssertFalse(f.data.restoreAccelerator(a.id), "de oudste kan pas na de nieuwste")
        XCTAssertEqual(f.data, both, "een geweigerd herstel verandert niets")

        XCTAssertTrue(f.data.restoreAccelerator(b.id))
        XCTAssertEqual(f.data.pot(f.pot.id)?.monthlyContribution, 455, "de eerste toepassing blijft intact")
        XCTAssertEqual(f.data.plan(for: oct2026).expenses.first { $0.name == "Huur" }?.amount, 1000)
        XCTAssertNil(f.data.restoreBlocker(for: a.id))
        XCTAssertTrue(f.data.restoreAccelerator(a.id))
        XCTAssertEqual(f.data, original)
    }

    func testTheBlockerIsAlwaysSomethingYouCanRestoreRightAway() throws {
        var f = accPotFixture(target: 60_000)
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        var ids: [UUID] = []
        for id in ["income5", "expense", "hours"] {
            ids.append(try XCTUnwrap(f.data.apply(try XCTUnwrap(accPick(id, f.data, f.goal), id), for: f.goal, current: oct2026, now: accNow), id).id)
        }
        // De oudste wacht op de middelste, maar die wacht weer op de nieuwste: je moet eerst de nieuwste terugzetten.
        XCTAssertEqual(f.data.restoreBlocker(for: ids[0])?.id, ids[2])
        XCTAssertEqual(f.data.restoreBlocker(for: ids[1])?.id, ids[2])
        XCTAssertNil(f.data.restoreBlocker(for: ids[2]))
        XCTAssertNil(f.data.restoreBlocker(for: UUID()))
    }

    func testRestoreIsAllowedWhenTheNewerApplicationChangesSomethingElse() throws {
        var f = accPotFixture()
        let original = f.data
        let a = try XCTUnwrap(f.data.apply(try XCTUnwrap(accPick("target", f.data, f.goal)), for: f.goal, current: oct2026, now: accNow))
        let b = try XCTUnwrap(f.data.apply(try XCTUnwrap(accPick("free", f.data, f.goal)), for: f.goal, current: oct2026, now: accNow))
        // Het doelbedrag en de inleg zijn verschillende dingen.
        XCTAssertNil(f.data.restoreBlocker(for: a.id))
        XCTAssertTrue(f.data.restoreAccelerator(a.id))
        XCTAssertEqual(f.data.goal(f.goal.id)?.targetAmount, 6000)
        XCTAssertEqual(f.data.pot(f.pot.id)?.monthlyContribution, 2100, "de inleg van de nieuwere toepassing blijft")
        XCTAssertEqual(f.data.appliedAccelerators.map(\.id), [b.id])
        XCTAssertTrue(f.data.restoreAccelerator(b.id))
        XCTAssertEqual(f.data, original)
    }

    func testAMissingPotCannotBlockARestore() throws {
        var f = accPotFixture()
        let a = try XCTUnwrap(f.data.apply(try XCTUnwrap(accPick("income5", f.data, f.goal)), for: f.goal, current: oct2026, now: accNow))
        _ = try XCTUnwrap(f.data.apply(try XCTUnwrap(accPick("expense", f.data, f.goal)), for: f.goal, current: oct2026, now: accNow))
        XCTAssertNotNil(f.data.restoreBlocker(for: a.id))
        f.data.deletePot(f.pot.id)
        XCTAssertNil(f.data.restoreBlocker(for: a.id), "de pot bestaat niet meer, dus er valt niets te verliezen")
        XCTAssertTrue(f.data.restoreAccelerator(a.id))
    }

    /// Een bank-toepassing en een verschuiving raken allebei de waarde van dezelfde beleggingen. Zet je de eerste terug
    /// terwijl de tweede nog staat, dan blijft het ingelegde geld in de portefeuille zitten terwijl het van de bank is terug.
    func testValueAcceleratorsOnTheSameHoldingMustBeRestoredNewestFirst() throws {
        var (d, g) = costFixture()
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        let original = d
        let bank = try XCTUnwrap(d.apply(try XCTUnwrap(accPick("bank", d, g)), for: g, current: oct2026, now: accNow))
        let afterBank = d
        let shift = try XCTUnwrap(d.apply(try XCTUnwrap(accPick("shift", d, g)), for: g, current: oct2026, now: accNow))
        let both = d

        XCTAssertEqual(d.restoreBlocker(for: bank.id)?.id, shift.id)
        XCTAssertFalse(d.restoreAccelerator(bank.id))
        XCTAssertEqual(d, both)

        XCTAssertTrue(d.restoreAccelerator(shift.id))
        XCTAssertEqual(d.portfolioValue(current: oct2026), afterBank.portfolioValue(current: oct2026), accuracy: 0.001)
        XCTAssertTrue(d.restoreAccelerator(bank.id))
        XCTAssertEqual(d, original)
        XCTAssertEqual(d.portfolioValue(current: oct2026), 10_000, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: accNow), 10_000, accuracy: 0.001)
    }

    func testCostsAndValueOfTheSameHoldingDoNotBlockEachOther() throws {
        var (d, g) = costFixture()
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        let original = d
        let costs = try XCTUnwrap(d.apply(try XCTUnwrap(accPick("costs", d, g)), for: g, current: oct2026, now: accNow))
        let bank = try XCTUnwrap(d.apply(try XCTUnwrap(accPick("bank", d, g)), for: g, current: oct2026, now: accNow))
        XCTAssertNil(d.restoreBlocker(for: costs.id))
        XCTAssertTrue(d.restoreAccelerator(costs.id))
        XCTAssertEqual(d.holdings[0].annualCost, 0.015, accuracy: 1e-12)
        XCTAssertEqual(d.portfolioValue(current: oct2026), 10_000 + 7966.66, accuracy: 0.001, "de bank-toepassing blijft staan")
        XCTAssertTrue(d.restoreAccelerator(bank.id))
        XCTAssertEqual(d, original)
    }

    /// Voor een doel: wat door een nieuwere toepassing van een ander doel geblokkeerd wordt, blijft staan.
    func testRestoringOneGoalLeavesWhatAnotherGoalBlocks() throws {
        var f = accPotFixture()
        var second = LifeGoal(name: "Tweede", kind: .custom)
        second.targetAmount = 90_000
        second.inflationAdjusted = false
        second.funding = .pot(f.pot.id)
        f.data.addGoal(second)
        let original = f.data
        XCTAssertNotNil(f.data.apply(try XCTUnwrap(accPick("free", f.data, f.goal)), for: f.goal, current: oct2026, now: accNow))
        XCTAssertNotNil(f.data.apply(try XCTUnwrap(accPick("income5", f.data, second)), for: second, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.appliedAccelerators.count, 2)

        // Beide gaan over de inleg van dezelfde pot; de nieuwste (van het tweede doel) moet eerst terug.
        XCTAssertEqual(f.data.restorableAcceleratorCount(for: f.goal.id), 0)
        XCTAssertEqual(f.data.restorableAcceleratorCount(for: second.id), 1)
        XCTAssertEqual(f.data.restorableAcceleratorCount(for: nil), 2)
        let copy = f.data
        XCTAssertEqual(f.data.restoreAccelerators(for: f.goal.id), 0)
        XCTAssertEqual(f.data, copy)

        XCTAssertEqual(f.data.restoreAccelerators(for: second.id), 1)
        XCTAssertEqual(f.data.restoreAccelerators(for: f.goal.id), 1)
        XCTAssertEqual(f.data, original)
        XCTAssertTrue(f.data.appliedAccelerators.isEmpty)
    }

    /// Willekeurige toepassingen op alle soorten doelen, daarna in willekeurige volgorde herstellen: wat geblokkeerd is
    /// wordt geweigerd zonder iets te veranderen, de blokkeerder is zelf te herstellen, en het eind is het origineel.
    /// Tweede ronde: tussen de toepassingen begint er een nieuwe maand (die de nieuwe waarden overneemt).
    func testRestoringWithTheBlockerRuleAlwaysEndsAtTheOriginal() throws {
        var refused = 0
        var applied = 0
        for newMonth in [false, true] {
            var random = AccRandom(seed: newMonth ? 11 : 7)
            let (base, goals) = accBigFixture()
            var expected = base
            if newMonth { expected.materialize(upTo: accNov) }
            for trial in 0..<60 {
                var d = base
                for _ in 0..<random.int(2...6) {
                    let goal = goals[random.int(0...goals.count - 1)]
                    let list = d.accelerators(for: goal, current: oct2026, today: accNow)
                    guard !list.isEmpty else { continue }
                    if d.apply(list[random.int(0...list.count - 1)], for: goal, current: oct2026, now: accNow) != nil { applied += 1 }
                    if newMonth, random.chance(40) { d.materialize(upTo: accNov) }
                }
                if newMonth { d.materialize(upTo: accNov) }
                var rounds = 0
                while !d.appliedAccelerators.isEmpty, rounds < 300 {
                    rounds += 1
                    let record = d.appliedAccelerators[random.int(0...d.appliedAccelerators.count - 1)]
                    let before = d
                    let blocker = d.restoreBlocker(for: record.id)
                    let done = d.restoreAccelerator(record.id)
                    if let blocker {
                        refused += 1
                        XCTAssertFalse(done, "ronde \(trial)")
                        XCTAssertEqual(d, before, "ronde \(trial): geweigerd herstel verandert niets")
                        XCTAssertNil(d.restoreBlocker(for: blocker.id), "ronde \(trial): de blokkeerder is meteen te herstellen")
                    } else {
                        XCTAssertTrue(done, "ronde \(trial)")
                    }
                }
                XCTAssertTrue(d.appliedAccelerators.isEmpty, "ronde \(trial)")
                XCTAssertEqual(d, expected, "ronde \(trial) (nieuwe maand: \(newMonth))")
            }
        }
        XCTAssertGreaterThan(applied, 150, "de test moet echt veel toepassingen doen")
        XCTAssertGreaterThan(refused, 0, "de test moet ook echt geblokkeerde herstellen tegenkomen")
    }

    func testRestoreKeepsChangesToOtherEntities() throws {
        var f = accPotFixture()
        let reserve = Pot(name: "Reserve", monthlyContribution: 50, startMonth: aug2026)
        f.data.addPot(reserve, openingBalance: 100, now: day(aug2026, 2))
        f.data.materialize(upTo: oct2026)
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))

        // Daarna verandert de gebruiker andere dingen: een andere pot, een nieuwe uitgave en een nieuwe belegging.
        var changedReserve = try XCTUnwrap(f.data.pot(reserve.id))
        changedReserve.name = "Reserve nieuw"
        changedReserve.monthlyContribution = 75
        f.data.updatePot(changedReserve, current: oct2026)
        f.data.upsertLine(MoneyLine(name: "Boodschappen", amount: 200), kind: .expense, in: oct2026)
        f.data.addHolding(Holding(name: "Nieuw", kind: .etf, ticker: nil, units: nil, startMonth: oct2026))

        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertEqual(f.data.pot(f.pot.id)?.monthlyContribution, 300)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: oct2026), 300, accuracy: 0.001)
        XCTAssertEqual(f.data.pot(reserve.id)?.name, "Reserve nieuw")
        XCTAssertEqual(f.data.pot(reserve.id)?.monthlyContribution, 75)
        XCTAssertEqual(f.data.allocation(reserve.id, in: oct2026), 75, accuracy: 0.001)
        XCTAssertNotNil(f.data.plan(for: oct2026).expenses.first { $0.name == "Boodschappen" })
        XCTAssertEqual(f.data.holdings.count, 1)
    }

    func testRestoreOnlyTouchesTheFieldsTheAcceleratorChanged() throws {
        var f = accPotFixture()
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        var renamed = try XCTUnwrap(f.data.pot(f.pot.id))
        renamed.name = "Japan-pot"
        renamed.goalAmount = 9000
        f.data.pots[0] = renamed
        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        let pot = try XCTUnwrap(f.data.pot(f.pot.id))
        XCTAssertEqual(pot.name, "Japan-pot")
        XCTAssertEqual(pot.goalAmount, 9000)
        XCTAssertEqual(pot.monthlyContribution, 300)
    }

    /// Wat de gebruiker daarna zelf aan hetzelfde veld veranderde, gaat bij herstel ook terug (herstel = terug naar vóór
    /// de versneller). De bevestiging in de app zegt dat ook. Andere velden en andere dingen blijven staan.
    func testRestoreAlsoResetsTheSameFieldTheUserChangedLater() throws {
        var f = accPotFixture()
        f.data.editPlan(accDec) { _ in }   // december is al vastgelegd
        let acc = try XCTUnwrap(accPick("expense", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.plan(for: accDec).expenses.first { $0.name == "Huur" }?.amount, 900)

        // De gebruiker zet de huur van december zelf op 1200, en de inleg van de pot op 500.
        f.data.editPlan(accDec) { plan in
            if let i = plan.expenses.firstIndex(where: { $0.name == "Huur" }) { plan.expenses[i].amount = 1200 }
        }
        var pot = try XCTUnwrap(f.data.pot(f.pot.id))
        pot.monthlyContribution = 500
        pot.name = "Japan-pot"
        f.data.pots[0] = pot

        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertEqual(f.data.plan(for: accDec).expenses.first { $0.name == "Huur" }?.amount, 1000)
        XCTAssertEqual(f.data.pot(f.pot.id)?.monthlyContribution, 300)
        XCTAssertEqual(f.data.pot(f.pot.id)?.name, "Japan-pot", "andere velden van de pot blijven")
    }

    func testRestoreKeepsPriceHistoryAddedAfterLoweringCosts() throws {
        var (d, g) = costFixture()
        let acc = try XCTUnwrap(accPick("costs", d, g))
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))
        let id = d.holdings[0].id
        d.addSnapshot(holdingID: id, value: 6500, invested: 6000, date: day(oct2026, 20))
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertEqual(d.holdings[0].annualCost, 0.015, accuracy: 1e-12)
        XCTAssertTrue(d.holdings[0].snapshots.contains { $0.value == 6500 }, "het nieuwe meetpunt blijft bestaan")
    }

    func testRestoreKeepsBankEntriesAndSnapshotsTheUserAddedLater() throws {
        var d = makeBaseData()
        d.addHolding(Holding(name: "Wereld", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                             startMonth: aug2026), initialValue: 6000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        var g = LifeGoal(name: "Doel", kind: .custom)
        g.targetAmount = 100_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)
        let acc = try XCTUnwrap(accPick("bank", d, g))
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))
        XCTAssertEqual(d.holdings[0].snapshots.count, 2)

        // Daarna boekt de gebruiker zelf iets bij en komt er een nieuw meetpunt bij.
        d.addBankEntry(amount: -50, note: "Boodschappen", date: day(oct2026, 14))
        d.addSnapshot(holdingID: d.holdings[0].id, value: 15_000, invested: 13_000, date: day(oct2026, 20))
        XCTAssertTrue(d.restoreAccelerator(record.id))

        XCTAssertEqual(d.bankEntries.map(\.note), ["Boodschappen"])
        XCTAssertEqual(d.holdings[0].snapshots.map(\.value), [6000, 15_000])
        XCTAssertEqual(d.holdings[0].units, nil)
    }

    func testPlanForBankSurplusShowsBothBalances() throws {
        let f = {
            var f = accPotFixture(target: 20_000)
            f.data.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
            return f
        }()
        let acc = try XCTUnwrap(accPick("bank", f.data, f.goal))
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertEqual(plan.lines.map(\.title), ["Bankrekening", "Spaarpot Vakantie"])
        XCTAssertEqual(plan.lines[0].oldValue, accEuro(10_000))
        XCTAssertEqual(plan.lines[0].newValue, accEuro(2033.34))
        XCTAssertEqual(plan.lines[1].oldValue, accEuro(1100))   // 500 + augustus + september, de inleg van oktober volgt op de 25e
        XCTAssertEqual(plan.lines[1].newValue, accEuro(9066.66))
        XCTAssertFalse(plan.notes.isEmpty)
        XCTAssertEqual(plan.monthsBefore, 63)   // (20000 - 1100) / 300 = 63
        XCTAssertEqual(plan.monthsAfter, 37)    // (20000 - 9066,66) / 300 = 36,4
    }

    func testPlanWarnsWhenMoreIsAllocatedThanIncome() throws {
        // Een versneller met een bedrag dat groter is dan de vrije ruimte laat de verdeling boven het inkomen uitkomen.
        let f = accPotFixture()
        let acc = Accelerator(id: "income5", title: "Leg 5% van je inkomen extra in", detail: "", symbol: "percent",
                              change: ScenarioChange(extraMonthly: 2500), newMonths: 3, monthsSaved: 13, makesReachable: false)
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertEqual(plan.notes, ["Let op: je verdeelt dan \(accEuro(700)) meer dan je inkomen van deze maand."])
    }

    func testRandomContributionsAreAlwaysSpreadWithoutLosingACent() throws {
        var random = AccRandom(seed: 42)
        for trial in 0..<60 {
            var d = makeBaseData()
            let count = random.int(2...5)
            for n in 0..<count {
                d.addHolding(Holding(name: "Fonds \(n)", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                                     monthlyContribution: random.chance(25) ? 0 : random.amount(1, 400), startMonth: aug2026),
                             initialValue: random.amount(100, 9000), now: day(sep2026, 1))
            }
            d.materialize(upTo: oct2026)
            var g = LifeGoal(name: "Doel", kind: .custom)
            g.targetAmount = 1_000_000
            g.inflationAdjusted = false
            g.funding = .portfolio
            d.addGoal(g)
            let extra = random.amount(1, 900)
            let acc = Accelerator(id: "income5", title: "Extra", detail: "", symbol: "percent",
                                  change: ScenarioChange(extraMonthly: extra), newMonths: 1, monthsSaved: 1, makesReachable: false)
            let before = d.monthlyInvestment(current: oct2026)
            let original = d
            let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow), "ronde \(trial)")
            XCTAssertEqual(accCents(d.monthlyInvestment(current: oct2026)), accCents(before + extra), "ronde \(trial)")
            XCTAssertEqual(accCents(d.holdings.reduce(0) { $0 + $1.monthlyContribution }),
                           accCents(original.holdings.reduce(0) { $0 + $1.monthlyContribution } + extra), "ronde \(trial)")
            XCTAssertTrue(d.restoreAccelerator(record.id))
            XCTAssertEqual(d, original, "ronde \(trial)")
        }
    }

    func testAcceleratorKindsAreRecognizedFromTheirIDs() {
        let line = UUID()
        let pot = UUID()
        XCTAssertEqual(AcceleratorKind(id: "free"), .free)
        XCTAssertEqual(AcceleratorKind(id: "income5"), .income5)
        XCTAssertEqual(AcceleratorKind(id: "stepup"), .stepUp)
        XCTAssertEqual(AcceleratorKind(id: "expense-\(line.uuidString)"), .expense(line))
        XCTAssertEqual(AcceleratorKind(id: "pot-\(pot.uuidString)"), .pot(pot))
        XCTAssertEqual(AcceleratorKind(id: "expense-geen-uuid"), .unknown)
        XCTAssertEqual(AcceleratorKind(id: "iets-anders"), .unknown)
    }

    func testRestoreSkipsWhatNoLongerExists() throws {
        var f = accPotFixture()
        let acc = try XCTUnwrap(accPick("free", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        f.data.deletePot(f.pot.id)
        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertTrue(f.data.pots.isEmpty)
        XCTAssertTrue(f.data.appliedAccelerators.isEmpty)
        XCTAssertNil(f.data.plan(for: oct2026).allocations[f.pot.id.uuidString], "geen verdeling voor een verwijderde pot terug")

        // Hetzelfde voor een verwijderd doel en een verwijderde belegging.
        var (d, g) = costFixture()
        let costAcc = try XCTUnwrap(accPick("costs", d, g))
        let costRecord = try XCTUnwrap(d.apply(costAcc, for: g, current: oct2026, now: accNow))
        d.deleteHolding(d.holdings[0].id)
        d.deleteGoal(g.id)
        XCTAssertTrue(d.restoreAccelerator(costRecord.id))
        XCTAssertEqual(d.holdings.count, 1)
        XCTAssertTrue(d.goals.isEmpty)
    }

    func testRestoreRemovesMonthPlansThatDidNotExistBefore() throws {
        // Oktober is nog niet vastgelegd (de app is net geopend in een nieuwe maand).
        var d = makeBaseData()
        let pot = Pot(name: "Vakantie", monthlyContribution: 300, startMonth: aug2026)
        d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
        var g = LifeGoal(name: "Japan", kind: .vacation)
        g.targetAmount = 6000
        g.inflationAdjusted = false
        g.funding = .pot(pot.id)
        d.addGoal(g)
        XCTAssertNil(d.months[oct2026.key])
        let original = d

        let acc = try XCTUnwrap(accPick("free", d, g))
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))
        XCTAssertNotNil(d.months[oct2026.key])
        XCTAssertEqual(record.before.newPlanKeys, [oct2026.key])
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 300 + acc.change.extraMonthly, accuracy: 0.001)

        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertNil(d.months[oct2026.key])
        XCTAssertEqual(d, original)
    }

    func testRestoreKeepsAMonthPlanTheUserEditedInTheMeantime() throws {
        var d = makeBaseData()
        let pot = Pot(name: "Vakantie", monthlyContribution: 300, startMonth: aug2026)
        d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
        var g = LifeGoal(name: "Japan", kind: .vacation)
        g.targetAmount = 6000
        g.inflationAdjusted = false
        g.funding = .pot(pot.id)
        d.addGoal(g)
        let acc = try XCTUnwrap(accPick("free", d, g))
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: accNow))
        d.upsertLine(MoneyLine(name: "Extra", amount: 40), kind: .expense, in: oct2026)
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertNotNil(d.months[oct2026.key])
        XCTAssertNotNil(d.plan(for: oct2026).expenses.first { $0.name == "Extra" })
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 300, accuracy: 0.001)
    }

    // MARK: Herstellen nadat er een nieuwe maand is begonnen

    func testRestoreAlsoCleansTheMonthThatStartedAfterApplying() throws {
        for id in ["free", "expense", "hours", "income5", "stepup"] {
            var f = accPotFixture(target: 60_000)
            f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
            var expected = f.data
            expected.materialize(upTo: accNov)

            let acc = try XCTUnwrap(accPick(id, f.data, f.goal), id)
            let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow), id)
            // De app wordt in november geopend: de nieuwe maand neemt de verhoogde inleg, lagere huur en extra uren over.
            f.data.materialize(upTo: accNov)
            XCTAssertNotEqual(f.data, expected, id)
            XCTAssertTrue(f.data.restoreAccelerator(record.id), id)
            XCTAssertEqual(f.data, expected, "\(id): november hoort ook terug te zijn")
        }
    }

    func testRestoreOfSeveralRecordsInAnyOrderAfterANewMonth() throws {
        let orders: [[Int]] = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            var f = accPotFixture(target: 60_000)
            f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
            f.data.editPlan(accDec) { _ in }
            var expected = f.data
            expected.materialize(upTo: accNov)

            var records: [AppliedAccelerator] = []
            for (n, id) in ["income5", "expense", "hours"].enumerated() {
                let acc = try XCTUnwrap(accPick(id, f.data, f.goal), id)
                records.append(try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow), id))
                if n == 1 { f.data.materialize(upTo: accNov) }   // tussen twee toepassingen begint een nieuwe maand
            }
            for index in order {
                XCTAssertTrue(f.data.restoreAccelerator(records[index].id, ignoringOrder: true), "volgorde \(order)")
            }
            XCTAssertEqual(f.data, expected, "volgorde \(order)")
        }
    }

    func testRestoreAllRestoresEverythingNewestFirst() throws {
        var f = accPotFixture(target: 60_000)
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        f.data.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        let original = f.data
        for id in ["free", "bank", "target"] {
            let acc = try XCTUnwrap(accPick(id, f.data, f.goal), id)
            XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow), id)
        }
        XCTAssertEqual(f.data.appliedAccelerators.count, 3)
        f.data.restoreAllAccelerators()
        XCTAssertTrue(f.data.appliedAccelerators.isEmpty)
        XCTAssertEqual(f.data, original)
        f.data.restoreAllAccelerators()   // nog een keer: niets te doen
        XCTAssertEqual(f.data, original)
    }

    func testAppliedAcceleratorsOfOneGoalAreListed() throws {
        var f = accPotFixture()
        var other = LifeGoal(name: "Tweede", kind: .custom)
        other.targetAmount = 1000
        other.inflationAdjusted = false
        other.funding = .custom(start: 0, monthly: 10, annualReturn: 0)
        f.data.addGoal(other)
        let a = try XCTUnwrap(accPick("free", f.data, f.goal))
        XCTAssertNotNil(f.data.apply(a, for: f.goal, current: oct2026, now: accNow))
        let b = try XCTUnwrap(accPick("income5", f.data, other))
        XCTAssertNotNil(f.data.apply(b, for: other, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.appliedAccelerators(for: f.goal.id).map(\.acceleratorID), ["free"])
        XCTAssertEqual(f.data.appliedAccelerators(for: other.id).map(\.acceleratorID), ["income5"])
    }

    // MARK: Alles samen

    /// Elke versneller op elk soort doel: toepassen verandert de gegevens, maakt het doel nooit trager,
    /// en herstellen geeft precies de oude gegevens terug.
    func testEveryAcceleratorAppliesAndRestoresExactly() throws {
        let (d, goals) = accBigFixture()

        var applied = 0
        var kinds = Set<String>()
        for goal in goals {
            let list = d.accelerators(for: goal, current: oct2026, today: accNow)
            XCTAssertFalse(list.isEmpty, goal.name)
            for acc in list {
                var copy = d
                let monthsBefore = goalMonths(copy, goal)
                guard let record = copy.apply(acc, for: goal, current: oct2026, now: accNow) else {
                    XCTFail("\(goal.name): \(acc.id) kon niet worden toegepast: \(d.applyPlan(acc, for: goal, current: oct2026, now: accNow).message ?? "-")")
                    continue
                }
                applied += 1
                kinds.insert(String(acc.id.split(separator: "-")[0]))
                XCTAssertNotEqual(copy, d, "\(goal.name): \(acc.id) verandert niets")
                XCTAssertFalse(record.summary.isEmpty)
                XCTAssertFalse(record.before.isEmpty && !["bank", "pot"].contains(String(acc.id.split(separator: "-")[0])), "\(acc.id)")
                if let before = monthsBefore {
                    let after = try XCTUnwrap(goalMonths(copy, goal), "\(goal.name): \(acc.id) maakt het doel onhaalbaar")
                    XCTAssertLessThanOrEqual(after, before, "\(goal.name): \(acc.id) maakt het doel trager")
                }
                XCTAssertTrue(copy.restoreAccelerator(record.id))
                XCTAssertEqual(copy, d, "\(goal.name): herstel van \(acc.id) is niet exact")
            }
        }
        XCTAssertGreaterThan(applied, 25)
        // Alle soorten komen langs.
        for kind in ["free", "income5", "expense", "bank", "pot", "costs", "shift", "hours", "stepup", "target"] {
            XCTAssertTrue(kinds.contains(kind), "\(kind) is niet getest")
        }
    }

    /// Dezelfde controle op de voorbeeldgegevens van de app (rente, uitgaven uit een spaarpot, gevolgde beleggingen).
    func testSampleDataAcceleratorsApplyAndRestoreExactly() throws {
        let d = FinanceData.sample(now: accNow)
        var applied = 0
        for goal in d.goals {
            for acc in d.accelerators(for: goal, current: oct2026, today: accNow) {
                var copy = d
                let before = goalMonths(copy, goal)
                let record = try XCTUnwrap(copy.apply(acc, for: goal, current: oct2026, now: accNow),
                                           "\(goal.name): \(acc.title)")
                applied += 1
                XCTAssertNotEqual(copy, d, acc.title)
                if let before, let after = goalMonths(copy, goal) {
                    XCTAssertLessThanOrEqual(after, before, "\(goal.name): \(acc.title)")
                }
                XCTAssertTrue(copy.restoreAccelerator(record.id))
                XCTAssertEqual(copy, d, "\(goal.name): herstel van \(acc.title)")
            }
        }
        XCTAssertGreaterThan(applied, 8)
    }

    // MARK: Het voorstel van nu, niet van eind van de maand

    func testPotSurplusIsMeasuredNowNotAtTheEndOfTheMonth() throws {
        var f = accPotFixture()
        let buffer = Pot(name: "Buffer", goalAmount: 100, monthlyContribution: 500, startMonth: aug2026)
        f.data.addPot(buffer, openingBalance: 0, now: day(aug2026, 2))
        f.data.materialize(upTo: oct2026)
        // Op 12 oktober staat er augustus + september = 1000; de inleg van oktober (500) volgt pas op de 25e.
        XCTAssertEqual(f.data.potBalanceNow(buffer.id, current: oct2026, today: accNow), 1000, accuracy: 0.001)
        XCTAssertEqual(f.data.potBalance(buffer.id, at: oct2026), 1500, accuracy: 0.001)

        let acc = try XCTUnwrap(accPick("pot", f.data, f.goal))
        XCTAssertEqual(acc.change.oneOff, 900, accuracy: 0.001, "1000 nu min het doel van 100, niet 1400")
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.potBalanceNow(buffer.id, current: oct2026, today: accNow), 100, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(f.data.potBalance(buffer.id, at: oct2026), 0)
    }

    func testAStalePotOfferNeverTakesMoreThanIsThereNow() throws {
        var f = accPotFixture()
        let buffer = Pot(name: "Buffer", goalAmount: 2000, monthlyContribution: 200, startMonth: aug2026)
        f.data.addPot(buffer, openingBalance: 3000, now: day(aug2026, 2))
        var second = LifeGoal(name: "Tweede", kind: .custom)
        second.targetAmount = 9000
        second.inflationAdjusted = false
        second.funding = .pot(f.pot.id)
        f.data.addGoal(second)
        f.data.materialize(upTo: oct2026)
        let acc = try XCTUnwrap(accPick("pot", f.data, f.goal))
        XCTAssertEqual(acc.change.oneOff, 1400, accuracy: 0.001)

        // Intussen haalt de gebruiker zelf 1000 uit Buffer: er is nog 400 boven het doel.
        f.data.addPotEntry(potID: buffer.id, amount: -1000, kind: .withdrawal, note: "Zelf opgenomen", date: day(oct2026, 10))
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertEqual(plan.lines.first?.oldValue, accEuro(2400))
        XCTAssertEqual(plan.lines.first?.newValue, accEuro(2000))
        XCTAssertTrue(plan.notes.contains { $0.contains("lager") }, "\(plan.notes)")
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.potBalanceNow(buffer.id, current: oct2026, today: accNow), 2000, accuracy: 0.001)

        // Dezelfde (verouderde) versneller voor een tweede doel op dezelfde pot: er is niets meer te halen.
        let copy = f.data
        XCTAssertNil(f.data.apply(acc, for: second, current: oct2026, now: accNow))
        XCTAssertEqual(f.data, copy)
        XCTAssertEqual(f.data.applyPlan(acc, for: second, current: oct2026, now: accNow).message,
                       "Buffer staat nu niet meer boven het doel. Er is niets om in te zetten.")
    }

    func testAStaleBankOfferNeverTakesMoreThanIsAboveTheBuffer() throws {
        var f = accPotFixture(target: 20_000)
        f.data.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        var second = LifeGoal(name: "Tweede", kind: .custom)
        second.targetAmount = 90_000
        second.inflationAdjusted = false
        second.funding = .pot(f.pot.id)
        f.data.addGoal(second)
        let acc = try XCTUnwrap(accPick("bank", f.data, f.goal))
        XCTAssertEqual(acc.change.oneOff, 7966.66, accuracy: 0.001)

        // Intussen is er 6000 van de rekening gegaan: nog 1966,66 boven de buffer van 2033,34.
        f.data.addBankEntry(amount: -6000, note: "Betaald", date: day(oct2026, 10))
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: accNow)
        XCTAssertEqual(plan.lines.first?.oldValue, accEuro(4000))
        XCTAssertEqual(plan.lines.first?.newValue, accEuro(2033.34))
        XCTAssertTrue(plan.notes.contains { $0.contains("lager") }, "\(plan.notes)")
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        XCTAssertEqual(f.data.bankBalanceNow(current: oct2026, today: accNow), 2033.34, accuracy: 0.001)

        // Het tweede doel met dezelfde verouderde versneller: de rekening staat op de buffer, dus niets.
        let copy = f.data
        XCTAssertNil(f.data.apply(acc, for: second, current: oct2026, now: accNow))
        XCTAssertEqual(f.data, copy)
        XCTAssertGreaterThanOrEqual(f.data.bankBalanceNow(current: oct2026, today: accNow), 2033.34 - 0.001)
    }

    // MARK: Dezelfde uitgave na een nieuwe maand

    func testTheSameExpenseCannotBeCutTwiceAfterANewMonthStarted() throws {
        var f = accPotFixture(target: 60_000)
        let acc = try XCTUnwrap(accPick("expense", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow))
        f.data.materialize(upTo: accNov)

        // In november heeft Huur een nieuw id, dus ook een nieuw aanbod.
        let novToday = day(accNov, 12)
        let again = try XCTUnwrap(f.data.accelerators(for: f.goal, current: accNov, today: novToday)
            .first { $0.id.hasPrefix("expense-") })
        XCTAssertNotEqual(again.id, acc.id)
        XCTAssertEqual(f.data.applicationBlocking(again, for: f.goal.id, current: accNov)?.id, record.id)

        let before = f.data
        XCTAssertNil(f.data.apply(again, for: f.goal, current: accNov, now: novToday))
        XCTAssertEqual(f.data, before)
        let plan = f.data.applyPlan(again, for: f.goal, current: accNov, now: novToday)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.alreadyApplied)
        XCTAssertEqual(f.data.plan(for: accNov).expenses.first { $0.name == "Huur" }?.amount, 900, "niet nog eens 10% eraf")
        XCTAssertEqual(f.data.appliedAccelerators.count, 1)

        // Een ander doel kan hem ook niet nog eens toepassen.
        var second = LifeGoal(name: "Tweede", kind: .custom)
        second.targetAmount = 90_000
        second.inflationAdjusted = false
        second.funding = .pot(f.pot.id)
        f.data.addGoal(second)
        XCTAssertNil(f.data.apply(again, for: second, current: accNov, now: novToday))
        XCTAssertEqual(f.data.applicationBlocking(again, for: second.id, current: accNov)?.goalID, f.goal.id)

        // Na herstel mag het weer.
        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertNil(f.data.applicationBlocking(again, for: f.goal.id, current: accNov))
        XCTAssertNotNil(f.data.apply(again, for: f.goal, current: accNov, now: novToday))
        XCTAssertEqual(f.data.plan(for: accNov).expenses.first { $0.name == "Huur" }?.amount, 900)
    }

    func testAnotherExpenseIsNotBlockedByTheFirstOne() throws {
        var f = accPotFixture(target: 60_000)
        f.data.upsertLine(MoneyLine(name: "Abonnementen", amount: 200, isRecurring: true), kind: .expense, in: oct2026)
        let rent = try XCTUnwrap(f.data.accelerators(for: f.goal, current: oct2026, today: accNow)
            .first { $0.title == "Verlaag Huur met 10%" })
        let subscriptions = try XCTUnwrap(f.data.accelerators(for: f.goal, current: oct2026, today: accNow)
            .first { $0.title == "Verlaag Abonnementen met 10%" })
        XCTAssertNotNil(f.data.apply(rent, for: f.goal, current: oct2026, now: accNow))
        XCTAssertNil(f.data.applicationBlocking(subscriptions, for: f.goal.id, current: oct2026))
        XCTAssertNotNil(f.data.apply(subscriptions, for: f.goal, current: oct2026, now: accNow))
    }

    // MARK: Uitleg bij niet-terugkerende uitgaven

    func testOneOffExpensesAreNotOfferedAndTheHintKnowsAboutThem() throws {
        var f = accPotFixture()
        XCTAssertFalse(f.data.hasOneOffExpensesWorthCutting(current: oct2026), "alleen een terugkerende huur")
        f.data.upsertLine(MoneyLine(name: "Tandarts", amount: 300, isRecurring: false), kind: .expense, in: oct2026)
        XCTAssertTrue(f.data.hasOneOffExpensesWorthCutting(current: oct2026))
        XCTAssertFalse(f.data.accelerators(for: f.goal, current: oct2026, today: accNow).contains { $0.title.contains("Tandarts") })
        f.data.upsertLine(MoneyLine(name: "Tandarts", amount: 300, isRecurring: true), kind: .expense, in: oct2026)
        XCTAssertTrue(f.data.accelerators(for: f.goal, current: oct2026, today: accNow).contains { $0.title.contains("Tandarts") })
    }

    // MARK: Opslaan

    func testAppliedAcceleratorsSurviveAnEncodeDecodeRoundTrip() throws {
        var f = accPotFixture(target: 60_000)
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        f.data.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        for id in ["free", "expense", "bank"] {
            let acc = try XCTUnwrap(accPick(id, f.data, f.goal), id)
            XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: accNow), id)
        }
        XCTAssertEqual(f.data.appliedAccelerators.count, 3)

        let back = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(f.data))
        XCTAssertEqual(back, f.data)
        XCTAssertEqual(back.appliedAccelerators.map(\.summary), f.data.appliedAccelerators.map(\.summary))

        // Zoals de app opslaat (data in ISO 8601): herstellen werkt daarna nog steeds.
        var stored = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: FinanceStorage.makeEncoder().encode(f.data))
        XCTAssertEqual(stored.appliedAccelerators.count, 3)
        stored.restoreAllAccelerators()
        XCTAssertTrue(stored.appliedAccelerators.isEmpty)
        XCTAssertEqual(stored.pot(f.pot.id)?.monthlyContribution, 300)
        XCTAssertEqual(stored.allocation(f.pot.id, in: oct2026), 300, accuracy: 0.001)
        XCTAssertTrue(stored.bankEntries.isEmpty)
        XCTAssertEqual(stored.plan(for: oct2026).expenses.first { $0.name == "Huur" }?.amount, 1000)
    }

    func testOldFilesWithoutAppliedAcceleratorsStillLoad() throws {
        let json = #"{"startMonth":"2026-08","pots":[],"months":{}}"#
        let d = try JSONDecoder().decode(FinanceData.self, from: Data(json.utf8))
        XCTAssertTrue(d.appliedAccelerators.isEmpty)
    }
}
