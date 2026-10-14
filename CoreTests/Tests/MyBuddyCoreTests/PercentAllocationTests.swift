import XCTest
import Foundation
@testable import MyBuddyCore

// Inleg als percentage van het inkomen (wens 3). Alle verwachte waarden zijn met de hand nagerekend.
//
// Basisgegevens: salaris 3000 (de 25e), toeslag 120 (de 20e, terugkerend, dus "alle inkomsten" = 3120), huur 1000
// (de 1e, terugkerend), startmaand augustus 2026.

private let pctNov = YearMonth(year: 2026, month: 11)
private let pctDec = YearMonth(year: 2026, month: 12)

private func pctData() -> FinanceData {
    var d = FinanceData(startMonth: aug2026)
    d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
    var plan = MonthPlan()
    plan.expenses = [MoneyLine(name: "Huur", amount: 1_000, isRecurring: true, day: 1)]
    plan.extraIncome = [MoneyLine(name: "Toeslag", amount: 120, isRecurring: true, day: 20)]
    d.months[aug2026.key] = plan
    return d
}

private func pctPot(_ name: String = "Vakantie", percent: Double, basis: IncomeBasis = .salary, start: YearMonth = aug2026,
                    transferDay: Int? = nil) -> Pot {
    var pot = Pot(name: name, monthlyContribution: 0, startMonth: start)
    pot.contributionMode = .percentage
    pot.contributionPercent = percent
    pot.contributionBasis = basis
    pot.transferDay = transferDay
    return pot
}

final class PercentAllocationTests: XCTestCase {
    // MARK: Handgerekende bedragen

    func testTenPercentOfSalaryIsThreeHundred() {
        var d = pctData()
        let pot = pctPot(percent: 10)
        d.addPot(pot)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 300, accuracy: 1e-9)
        XCTAssertEqual(d.savedTotal(in: oct2026), 300, accuracy: 1e-9)
        // 3000 + 120 - 1000 - 300
        XCTAssertEqual(d.remaining(in: oct2026), 1_820, accuracy: 1e-9)
        // Voor de startmaand van de data geldt niets.
        XCTAssertEqual(d.allocation(pot.id, in: YearMonth(year: 2026, month: 7)), 0)
    }

    func testBasisAllIncomeIncludesExtraIncome() {
        var d = pctData()
        let salaryOnly = pctPot("Alleen salaris", percent: 10, basis: .salary)
        let everything = pctPot("Alle inkomsten", percent: 10, basis: .allIncome)
        d.addPot(salaryOnly)
        d.addPot(everything)
        XCTAssertEqual(d.allocation(salaryOnly.id, in: oct2026), 300, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(everything.id, in: oct2026), 312, accuracy: 1e-9)   // 10% van 3120
        XCTAssertEqual(d.savedTotal(in: oct2026), 612, accuracy: 1e-9)
        XCTAssertEqual(d.remaining(in: oct2026), 3_120 - 1_000 - 612, accuracy: 1e-9)
    }

    func testRoundingToWholeCentsHalfUp() {
        var d = pctData()
        // 12,5% van 2999,99 = 374,99875 -> 375,00
        d.salary.fixedMonthly = 2_999.99
        let a = pctPot("A", percent: 12.5)
        // 10% van 1000,05 = 100,005 -> 100,01 (halve cent omhoog)
        let b = pctPot("B", percent: 10)
        d.addPot(a)
        XCTAssertEqual(d.allocation(a.id, in: oct2026), 375.00, accuracy: 1e-9)
        d.salary.fixedMonthly = 1_000.05
        d.addPot(b)
        XCTAssertEqual(d.allocation(b.id, in: oct2026), 100.01, accuracy: 1e-9)
        // 33,33% van 3000 = 999,90; 0,01% van 3000 = 0,30; 100% = 3000
        d.salary.fixedMonthly = 3_000
        var c = pctPot("C", percent: 33.33)
        d.addPot(c)
        XCTAssertEqual(d.allocation(c.id, in: oct2026), 999.90, accuracy: 1e-9)
        c = d.pot(c.id)!
        d.setContributionPercent(c.id, percent: 0.01, basis: .salary, current: oct2026)
        XCTAssertEqual(d.allocation(c.id, in: oct2026), 0.30, accuracy: 1e-9)
        d.setContributionPercent(c.id, percent: 100, basis: .salary, current: oct2026)
        XCTAssertEqual(d.allocation(c.id, in: oct2026), 3_000, accuracy: 1e-9)
    }

    func testPercentIsCleanedToTwoDecimalsAndKeptBetweenZeroAndHundred() {
        XCTAssertEqual(AllocationMath.cleanPercent(33.333), 33.33)
        XCTAssertEqual(AllocationMath.cleanPercent(12.5), 12.5)
        XCTAssertEqual(AllocationMath.cleanPercent(150), 100)
        XCTAssertEqual(AllocationMath.cleanPercent(-5), 0)
        XCTAssertEqual(AllocationMath.cleanPercent(.nan), 0)
        XCTAssertEqual(AllocationMath.cleanPercent(.infinity), 0)
        XCTAssertEqual(AllocationMath.hundredths(12.35), 1_235)
        XCTAssertEqual(AllocationMath.hundredths(0.07), 7)
        // Een pot met een te nauwkeurig percentage rekent met twee decimalen: 12,345% wordt 12,35% (of 12,34%), nooit iets anders.
        var d = pctData()
        let pot = pctPot(percent: 12.345)
        d.addPot(pot)
        let cents = CentsMath.int(d.allocation(pot.id, in: oct2026))
        XCTAssertTrue(cents == 37_050 || cents == 37_020, "gekregen \(cents)")   // 3000 x 12,35% = 370,50 of 12,34% = 370,20
        XCTAssertEqual(d.contributionRule(of: pot.id), .percent(PercentRule(percent: AllocationMath.cleanPercent(12.345), basis: .salary)))
    }

    func testNeverNegativeAndZeroWithoutIncome() {
        var d = pctData()
        let pot = pctPot(percent: 50)
        d.addPot(pot)
        d.editPlan(oct2026) { $0.salaryOverride = -400 }
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 0)
        XCTAssertEqual(d.monthFigures(oct2026).saved, 0)
        d.editPlan(oct2026) { $0.salaryOverride = 0 }
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 0)
        // Zonder inkomen is er ook geen percentage te geven bij een bedrag.
        d.editPlan(pctNov) { $0.salaryOverride = 0 }
        d.editPlan(pctNov) { $0.extraIncome = [] }
        XCTAssertNil(d.percent(forAmount: 100, of: .salary, in: pctNov))
    }

    func testNonsensePercentagesNeverCrashAndStayInRange() {
        var d = pctData()
        let tooBig = pctPot("Te groot", percent: 150)
        let negative = pctPot("Negatief", percent: -20)
        let broken = pctPot("Kapot", percent: .nan)
        let infinite = pctPot("Oneindig", percent: .infinity)
        for pot in [tooBig, negative, broken, infinite] { d.addPot(pot) }
        XCTAssertEqual(d.allocation(tooBig.id, in: oct2026), 3_000, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(negative.id, in: oct2026), 0)
        XCTAssertEqual(d.allocation(broken.id, in: oct2026), 0)
        XCTAssertEqual(d.allocation(infinite.id, in: oct2026), 0)
        // Een eigen percentage voor één maand wordt ook schoongemaakt.
        d.setAllocationPercent(negative.id, in: oct2026, percent: 250)
        XCTAssertEqual(d.allocation(negative.id, in: oct2026), 3_000, accuracy: 1e-9)
        d.setAllocationPercent(negative.id, in: oct2026, percent: .nan)
        XCTAssertEqual(d.allocation(negative.id, in: oct2026), 0)
        // Enorm inkomen: geen overloop.
        d.editPlan(oct2026) { $0.salaryOverride = 9e13 }
        XCTAssertGreaterThan(d.allocation(tooBig.id, in: oct2026), 0)
        XCTAssertTrue(d.allocation(tooBig.id, in: oct2026).isFinite)
        _ = d.allocationWarnings(in: oct2026)
    }

    func testRuleSummariesForTheScreens() {
        XCTAssertEqual(AllocationRule.amount(300).summary, Fmt.euro(300))
        XCTAssertEqual(AllocationRule.percent(PercentRule(percent: 10, basis: .salary)).summary, "10% van je salaris")
        XCTAssertEqual(AllocationRule.percent(PercentRule(percent: 12.5, basis: .allIncome)).summary, "12,5% van al je inkomsten")
        XCTAssertTrue(AllocationRule.percent(PercentRule(percent: 1, basis: .salary)).isPercent)
        XCTAssertFalse(AllocationRule.amount(1).isPercent)
        var d = pctData()
        let pot = pctPot(percent: 10)
        d.addPot(pot)
        XCTAssertEqual(d.contributionRule(of: pot.id)?.summary, "10% van je salaris")
        XCTAssertNil(d.contributionRule(of: UUID()))
        XCTAssertEqual(d.defaultAllocation(pot.id, in: oct2026), 300, accuracy: 1e-9)
        XCTAssertEqual(d.amount(of: .percent(PercentRule(percent: 50, basis: .allIncome)), in: oct2026), 1_560, accuracy: 1e-9)
        XCTAssertEqual(d.amount(of: .amount(42), in: oct2026), 42)
    }

    // MARK: Het inkomen van die maand

    func testAllocationFollowsTheIncomeOfEachMonth() {
        var d = pctData()
        let pot = pctPot(percent: 10)
        d.addPot(pot)
        d.materialize(upTo: oct2026)   // de maanden zijn vastgelegd; het percentage blijft meebewegen
        d.editPlan(sep2026) { $0.salaryOverride = 3_500 }
        XCTAssertEqual(d.allocation(pot.id, in: sep2026), 350, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(pot.id, in: aug2026), 300, accuracy: 1e-9)
        d.salary.fixedMonthly = 3_200
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 320, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 320, accuracy: 1e-9)   // niet vastgelegd: dezelfde regel
        XCTAssertEqual(d.allocation(pot.id, in: sep2026), 350, accuracy: 1e-9)   // eigen salaris van die maand
    }

    func testHourlyIncomeAndExtraIncomeFlowIntoThePercentage() {
        var d = pctData()
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36, payDay: 25)
        let pot = pctPot(percent: 10, basis: .allIncome)
        d.addPot(pot)
        d.editPlan(oct2026) { $0.hoursOverride = 150 }   // 20 x 150 = 3000
        // + toeslag 120 = 3120 -> 312
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 312, accuracy: 1e-9)
        d.upsertLine(MoneyLine(name: "Bonus", amount: 880, isRecurring: false, day: 15), kind: .income, in: oct2026)
        XCTAssertEqual(d.income(in: oct2026), 4_000, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 400, accuracy: 1e-9)    // 10% van 4000
        // Een andere maand krijgt de bonus niet.
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), (d.income(in: pctNov) * 0.1).cents, accuracy: 1e-9)
    }

    func testIncomeNeverDependsOnTheAllocation() {
        var d = pctData()
        let a = pctPot("A", percent: 100, basis: .allIncome)
        let b = pctPot("B", percent: 100, basis: .allIncome)
        let before = d.income(in: oct2026)
        d.addPot(a)
        d.addPot(b)
        XCTAssertEqual(d.income(in: oct2026), before, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(a.id, in: oct2026), 3_120, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(b.id, in: oct2026), 3_120, accuracy: 1e-9)
        // 2 x 3120 verdeeld terwijl er 2120 over is: geen crash, wel een negatief "te verdelen" en een waarschuwing.
        XCTAssertEqual(d.remaining(in: oct2026), 3_120 - 1_000 - 6_240, accuracy: 1e-9)
        XCTAssertEqual(d.allocationWarnings(in: oct2026).count, 2)
    }

    // MARK: Vast percentage, variabel percentage, bedrag naast percentage

    func testVariablePercentageForOneMonth() {
        var d = pctData()
        let pot = pctPot(percent: 10)
        d.addPot(pot)
        d.setAllocationPercent(pot.id, in: pctNov, percent: 15)   // november 15% (grondslag van de pot: salaris)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 450, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(pot.id, in: pctDec), 300, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 300, accuracy: 1e-9)
        let effective = d.effectiveAllocation(pot.id, in: pctNov)
        XCTAssertEqual(effective.rule, .percent(PercentRule(percent: 15, basis: .salary)))
        XCTAssertEqual(effective.amount, 450, accuracy: 1e-9)
        XCTAssertTrue(effective.isOverride)
        XCTAssertFalse(d.effectiveAllocation(pot.id, in: pctDec).isOverride)

        // Een andere grondslag voor één maand.
        d.setAllocationPercent(pot.id, in: pctDec, percent: 10, basis: .allIncome)
        XCTAssertEqual(d.allocation(pot.id, in: pctDec), 312, accuracy: 1e-9)

        // Wissen: de standaard geldt weer.
        d.clearAllocationOverride(pot.id, in: pctNov)
        d.clearAllocationOverride(pot.id, in: pctDec)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 300, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(pot.id, in: pctDec), 300, accuracy: 1e-9)
        XCTAssertFalse(d.effectiveAllocation(pot.id, in: pctNov).isOverride)
    }

    func testAmountOverrideReplacesPercentageAndTheOtherWayAround() {
        var d = pctData()
        let pot = pctPot(percent: 10)
        d.addPot(pot)
        d.setAllocation(pot.id, in: pctNov, amount: 275)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 275)
        XCTAssertEqual(d.effectiveAllocation(pot.id, in: pctNov).rule, .amount(275))
        d.setAllocationPercent(pot.id, in: pctNov, percent: 20)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 600, accuracy: 1e-9)
        XCTAssertNil(d.months[pctNov.key]?.allocations[pot.id.uuidString], "een bedrag en een percentage bestaan niet naast elkaar")
        d.setAllocation(pot.id, in: pctNov, amount: 100)
        XCTAssertNil(d.months[pctNov.key]?.percentAllocations[pot.id.uuidString])
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 100)
    }

    func testFixedAmountPotsKeepWorkingExactlyAsBefore() {
        var d = pctData()
        let pot = Pot(name: "Vast", monthlyContribution: 200, startMonth: aug2026)
        d.addPot(pot)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 200)
        XCTAssertEqual(d.contributionRule(of: pot.id), .amount(200))
        d.setAllocation(pot.id, in: pctNov, amount: 250)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 250)
        XCTAssertTrue(d.effectiveAllocation(pot.id, in: pctNov).isOverride)
        XCTAssertFalse(d.effectiveAllocation(pot.id, in: pctDec).isOverride)
        // Geen enkel percentage in de gegevens.
        XCTAssertTrue(d.months.values.allSatisfy { $0.percentAllocations.isEmpty })
        XCTAssertEqual(d.percentTotal(in: oct2026), 0)
        XCTAssertTrue(d.allocationWarnings(in: oct2026).isEmpty)
    }

    func testChangingTheStandardPercentageAppliesToTheCurrentMonthAndTheFuture() {
        var d = pctData()
        let pot = pctPot(percent: 10)
        d.addPot(pot)
        d.materialize(upTo: oct2026)
        d.setContributionPercent(pot.id, percent: 20, basis: .salary, current: oct2026)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 600, accuracy: 1e-9)           // lopende maand meteen
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 600, accuracy: 1e-9)           // toekomst
        XCTAssertEqual(d.allocation(pot.id, in: sep2026), 300, accuracy: 1e-9)          // verleden blijft zoals het was
        // Terug naar een vast bedrag.
        d.setContributionAmount(pot.id, amount: 150, current: oct2026)
        XCTAssertEqual(d.pot(pot.id)?.contributionMode, .fixed)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 150)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 150)
        XCTAssertEqual(d.allocation(pot.id, in: sep2026), 300, accuracy: 1e-9)
        XCTAssertNil(d.months[oct2026.key]?.percentAllocations[pot.id.uuidString])
    }

    // MARK: Waarschuwingen en rekenhulp

    func testWarningWhenThePercentagesAddUpToMoreThanAHundred() {
        var d = pctData()
        let a = pctPot("A", percent: 70)
        let b = pctPot("B", percent: 50)
        d.addPot(a)
        d.addPot(b)
        XCTAssertEqual(d.percentTotal(in: oct2026), 120, accuracy: 1e-9)
        let warnings = d.allocationWarnings(in: oct2026)
        XCTAssertEqual(warnings.first, .percentagesOver100(total: 120))
        XCTAssertEqual(warnings.first?.message, "De percentages samen zijn 120% van je inkomen. Dat is meer dan 100%.")
        // 3600 verdeeld, 2000 te verdelen (3000 + 120 - 1000 = 2120): 3600 - 2120 = 1480 te veel... 70% + 50% van 3000 = 3600.
        XCTAssertEqual(warnings.last, .overAllocated(by: 1_480))
        XCTAssertEqual(d.allocationWarning(in: oct2026), warnings.first?.message)
        XCTAssertEqual(d.remaining(in: oct2026), 2_120 - 3_600, accuracy: 1e-9)
        // Alles blijft gewoon doorrekenen.
        XCTAssertEqual(d.savedTotal(in: oct2026), 3_600, accuracy: 1e-9)
    }

    func testWarningWhenMoreIsDistributedThanThereIsToDistributeEvenWithoutPercentages() {
        var d = pctData()
        let pot = Pot(name: "Groot", monthlyContribution: 2_500, startMonth: aug2026)
        d.addPot(pot)
        XCTAssertEqual(d.allocationWarnings(in: oct2026), [.overAllocated(by: 380)])   // 2500 - 2120
        XCTAssertEqual(d.allocationWarnings(in: oct2026).first?.message, "Je verdeelt \(Fmt.euro(380)) meer dan je hebt om te verdelen.")
        d.setAllocation(pot.id, in: oct2026, amount: 2_000)
        XCTAssertTrue(d.allocationWarnings(in: oct2026).isEmpty)
        XCTAssertNil(d.allocationWarning(in: oct2026))
        // Vóór de startmaand is er niets om voor te waarschuwen.
        XCTAssertTrue(d.allocationWarnings(in: YearMonth(year: 2026, month: 6)).isEmpty)
    }

    func testCalculatorThisPercentageIsNowThisManyEuros() {
        let d = pctData()
        XCTAssertEqual(d.percentAmount(10, of: .salary, in: oct2026), 300, accuracy: 1e-9)
        XCTAssertEqual(d.percentAmount(10, of: .allIncome, in: oct2026), 312, accuracy: 1e-9)
        XCTAssertEqual(d.percentAmount(12.5, in: oct2026), 375, accuracy: 1e-9)
        XCTAssertEqual(d.percentAmount(0, in: oct2026), 0)
        XCTAssertEqual(d.percentAmount(100, in: oct2026), 3_000, accuracy: 1e-9)
        XCTAssertEqual(d.percentAmount(10, in: YearMonth(year: 2026, month: 6)), 0, "vóór de start is er geen inkomen")
        // En andersom: bij 375 hoort 12,5%.
        XCTAssertEqual(d.percent(forAmount: 375, of: .salary, in: oct2026) ?? -1, 12.5, accuracy: 1e-9)
        XCTAssertEqual(d.percent(forAmount: 312, of: .allIncome, in: oct2026) ?? -1, 10, accuracy: 1e-9)
    }

    // MARK: Overal hetzelfde bedrag

    func testEveryPathGivesTheSameAmount() {
        var d = pctData()
        let pot = pctPot("Vakantie", percent: 12.5, basis: .allIncome, transferDay: 10)
        let other = pctPot("Auto", percent: 5, basis: .salary)
        d.addPot(pot, openingBalance: 100, now: day(aug2026, 1))
        d.addPot(other)
        var holding = Holding(name: "ETF", kind: .etf, monthlyContribution: 0, startMonth: aug2026)
        holding.contributionMode = .percentage
        holding.contributionPercent = 7.5
        holding.contributionBasis = .allIncome
        holding.transferDay = 12
        d.addHolding(holding)
        d.materialize(upTo: oct2026)
        d.setAllocationPercent(pot.id, in: pctNov, percent: 20, basis: .salary)   // variabel: november anders

        let builder = d.monthFiguresBuilder()
        for m in aug2026.range(count: 8) {
            let salaryCents = 300_000
            let allCents = CentsMath.int(d.income(in: m))
            // Onafhankelijk nagerekend met Decimal (halve cent omhoog).
            func part(_ base: Int, _ hundredths: Int) -> Int {
                var value = Decimal(base) * Decimal(hundredths) / 10_000
                var rounded = Decimal()
                NSDecimalRound(&rounded, &value, 0, .plain)
                return NSDecimalNumber(decimal: rounded).intValue
            }
            let potPercent = (m == pctNov) ? (2_000, salaryCents) : (1_250, allCents)
            let expectedPot = part(potPercent.1, potPercent.0)
            let expectedOther = part(salaryCents, 500)
            let expectedHolding = part(allCents, 750)

            let f = d.monthFigures(m)
            XCTAssertEqual(CentsMath.int(d.allocation(pot.id, in: m)), expectedPot, m.key)
            XCTAssertEqual(CentsMath.int(d.allocation(other.id, in: m)), expectedOther, m.key)
            XCTAssertEqual(CentsMath.int(d.allocation(holding.id, in: m)), expectedHolding, m.key)
            XCTAssertEqual(f.saved, expectedPot + expectedOther, m.key)
            XCTAssertEqual(f.invested, expectedHolding, m.key)
            XCTAssertEqual(builder.figures(m), f, m.key)
            XCTAssertEqual(CentsMath.int(d.savedTotal(in: m)), f.saved, m.key)
            XCTAssertEqual(CentsMath.int(d.investedTotal(in: m)), f.invested, m.key)
            XCTAssertEqual(f.remaining, f.income - (f.expenses - f.fromPots) - f.saved - f.invested, m.key)
            XCTAssertEqual(CentsMath.int(d.remaining(in: m)), f.remaining, m.key)

            // De gebeurtenissen van de dagen: de overschrijving op de overschrijfdag is hetzelfde bedrag.
            let events = d.planEvents(in: m)
            XCTAssertEqual(events.first { $0.kind == .toPot && $0.potID == pot.id }.map { CentsMath.int($0.bankAmount) },
                           expectedPot == 0 ? nil : -expectedPot, m.key)
            XCTAssertEqual(events.first { $0.kind == .toPot && $0.potID == pot.id }?.day, expectedPot == 0 ? nil : 10, m.key)
            XCTAssertEqual(events.first { $0.kind == .toHolding }.map { CentsMath.int($0.bankAmount) }, -expectedHolding, m.key)
            XCTAssertEqual(events.first { $0.kind == .toHolding }?.day, 12, m.key)
            XCTAssertEqual(events.first { $0.kind == .toPot && $0.potID == other.id }?.day, 25, "salarisdag")

            // De dagboekhouding en de saldi van de spaarpotten.
            let ledger = d.monthLedger(m, asOf: day(oct2026, 12))
            XCTAssertTrue(ledger.allReconciles, m.key)
            XCTAssertEqual(CentsMath.int(ledger.saved), f.saved, m.key)
            XCTAssertEqual(CentsMath.int(ledger.planToPots), f.saved, m.key)
            XCTAssertEqual(CentsMath.int(ledger.invested), f.invested, m.key)
            XCTAssertEqual(CentsMath.int(ledger.toHoldings), f.invested, m.key)
            XCTAssertEqual(CentsMath.int(ledger.remaining), f.remaining, m.key)
            XCTAssertEqual(ledger.days[9].toPots, CentsMath.value(expectedPot), "dag 10: alleen de vakantiepot")
            XCTAssertEqual(ledger.days[24].toPots, CentsMath.value(expectedOther), "dag 25: alleen de autopot")
            XCTAssertEqual(ledger.days[11].toHoldings, CentsMath.value(expectedHolding), "dag 12: de belegging")
        }
        // Saldo van de pot aan het eind van oktober: 100 + augustus t/m oktober.
        func allocationSum(_ id: UUID, through m: YearMonth) -> Int {
            aug2026.range(count: aug2026.months(to: m) + 1).reduce(0) { $0 + CentsMath.int(d.allocation(id, in: $1)) }
        }
        XCTAssertEqual(CentsMath.int(d.potBalance(pot.id, at: oct2026)), 10_000 + allocationSum(pot.id, through: oct2026))
        XCTAssertEqual(CentsMath.int(d.potBalance(pot.id, at: pctNov)), 10_000 + allocationSum(pot.id, through: pctNov))
    }

    func testHandCalculatedMonthWithEverythingInIt() {
        // Oktober: salaris 3000 + toeslag 120 = 3120; huur 1000; Vakantie 12,5% van alles = 390; Auto 5% van salaris = 150;
        // ETF 7,5% van alles = 234. Over: 3120 - 1000 - 390 - 150 - 234 = 1346.
        var d = pctData()
        d.addPot(pctPot("Vakantie", percent: 12.5, basis: .allIncome))
        d.addPot(pctPot("Auto", percent: 5, basis: .salary))
        var etf = Holding(name: "ETF", kind: .etf, startMonth: aug2026)
        etf.contributionMode = .percentage
        etf.contributionPercent = 7.5
        etf.contributionBasis = .allIncome
        d.addHolding(etf)
        let f = d.monthFigures(oct2026)
        XCTAssertEqual(f.income, 312_000)
        XCTAssertEqual(f.expenses, 100_000)
        XCTAssertEqual(f.saved, 39_000 + 15_000)
        XCTAssertEqual(f.invested, 23_400)
        XCTAssertEqual(f.remaining, 134_600)
        XCTAssertEqual(d.remaining(in: oct2026), 1_346, accuracy: 1e-9)
        XCTAssertEqual(d.expenseOverview(in: oct2026).leftAfterTransfers, 1_346, accuracy: 1e-9)
    }

    // MARK: Start van de pot

    func testPercentagePotStartsInItsStartMonth() {
        var d = pctData()
        let pot = pctPot(percent: 10, start: pctNov)
        d.addPot(pot)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 0)
        XCTAssertEqual(d.allocation(pot.id, in: pctNov), 300, accuracy: 1e-9)
        d.materialize(upTo: pctDec)
        XCTAssertNil(d.months[oct2026.key]?.percentAllocations[pot.id.uuidString], "niets vastgelegd vóór de start")
        XCTAssertNotNil(d.months[pctNov.key]?.percentAllocations[pot.id.uuidString])
    }
}
