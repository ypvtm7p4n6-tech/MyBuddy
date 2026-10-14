import XCTest
@testable import MyBuddyCore

/// Een spaarpot wijzigen (`updatePot`): elke verandering van de standaardinleg (bedrag, inlegwijze, percentage of grondslag)
/// geldt ook meteen voor de lopende maand, ook als die al is vastgelegd. Een wijziging die de inleg niet raakt laat de
/// lopende maand met rust. De dagboekhouding sluit na elke stap.
final class PotContributionModeTests: XCTestCase {
    /// Start november 2026, salaris 3000 op de 25e en in november een bonus van 500 op de 20e. Pot Vakantie legt 100 in;
    /// november is al vastgelegd (met die 100), december nog niet.
    private func makeData() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.upsertLine(MoneyLine(name: "Bonus", amount: 500, day: 20), kind: .income, in: engNov2026)
        let pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: engNov2026)
        d.addPot(pot, openingBalance: 0, now: engTime(engNov2026, 1, hour: 8))
        d.materialize(upTo: engNov2026)
        return (d, pot)
    }

    private func assertConsistent(_ d: FinanceData, _ pot: Pot, nov: Double, dec: Double, file: StaticString = #filePath,
                                  line: UInt = #line) {
        let today = engTime(engNov2026, 30, hour: 20)
        for (month, expected) in [(engNov2026, nov), (engDec2026, dec)] {
            let ledger = d.monthLedger(month, asOf: today)
            XCTAssertEqual(d.allocation(pot.id, in: month), expected, "verdeling \(month.key)", file: file, line: line)
            XCTAssertEqual(ledger.planToPots, expected, "dagboek \(month.key)", file: file, line: line)
            XCTAssertEqual(d.savedTotal(in: month), expected, "overzicht \(month.key)", file: file, line: line)
            XCTAssertEqual(d.potBalance(pot.id, at: month),
                           month == engNov2026 ? expected : nov + expected, "pot \(month.key)", file: file, line: line)
            XCTAssertTrue(ledger.allReconciles, month.key, file: file, line: line)
        }
    }

    func testSwitchingToAPercentageAppliesToTheStoredCurrentMonth() {
        var (d, pot) = makeData()
        assertConsistent(d, pot, nov: 100, dec: 100)
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        pot.contributionBasis = .salary
        d.updatePot(pot, current: engNov2026)
        // 10% van het salaris (3000) in beide maanden.
        assertConsistent(d, pot, nov: 300, dec: 300)
    }

    func testChangingThePercentageOrTheBasisAppliesToTheCurrentMonth() {
        var (d, pot) = makeData()
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.updatePot(pot, current: engNov2026)
        assertConsistent(d, pot, nov: 300, dec: 300)
        pot.contributionPercent = 12.5
        d.updatePot(pot, current: engNov2026)
        assertConsistent(d, pot, nov: 375, dec: 375)
        // Alle inkomsten: november heeft de bonus erbij (3500), december niet (3000).
        pot.contributionBasis = .allIncome
        d.updatePot(pot, current: engNov2026)
        assertConsistent(d, pot, nov: 437.50, dec: 375)
    }

    func testSwitchingBackToAFixedAmountAppliesToTheCurrentMonth() {
        var (d, pot) = makeData()
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.updatePot(pot, current: engNov2026)
        pot.contributionMode = .fixed
        pot.monthlyContribution = 80
        d.updatePot(pot, current: engNov2026)
        assertConsistent(d, pot, nov: 80, dec: 80)
        // Alleen het bedrag veranderen (de inlegwijze blijft vast) werkt zoals altijd.
        pot.monthlyContribution = 120
        d.updatePot(pot, current: engNov2026)
        assertConsistent(d, pot, nov: 120, dec: 120)
    }

    func testChangesThatLeaveTheContributionAloneKeepAMonthlyOverride() {
        var (d, pot) = makeData()
        d.setAllocation(pot.id, in: engNov2026, amount: 250)
        pot.name = "Zomervakantie"
        pot.goalAmount = 2_000
        pot.interestRate = 0.02
        d.updatePot(pot, current: engNov2026)
        XCTAssertEqual(d.allocation(pot.id, in: engNov2026), 250, "eigen bedrag van deze maand blijft")
        XCTAssertEqual(d.allocation(pot.id, in: engDec2026), 100)
        // Het bedrag van de maand zelf blijft ook staan als alleen het verborgen vaste bedrag verandert bij een percentage.
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.updatePot(pot, current: engNov2026)
        XCTAssertEqual(d.allocation(pot.id, in: engNov2026), 300)
        d.setAllocationPercent(pot.id, in: engNov2026, percent: 20)
        pot.monthlyContribution = 999
        d.updatePot(pot, current: engNov2026)
        XCTAssertEqual(d.allocation(pot.id, in: engNov2026), 600, "20% van het eigen percentage van deze maand blijft")
        XCTAssertTrue(d.monthLedger(engNov2026, asOf: engTime(engNov2026, 30, hour: 20)).allReconciles)
    }

    func testMonthsBeforeThePotStartAreNotTouched() {
        var (d, pot) = makeData()
        pot.startMonth = engDec2026
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.updatePot(pot, current: engNov2026)
        XCTAssertEqual(d.allocation(pot.id, in: engNov2026), 100, "de pot begint pas in december: november blijft zoals het was")
        XCTAssertEqual(d.allocation(pot.id, in: engDec2026), 300)
    }

    func testDeletingAPotRemovesItsMonthlyPercentagesAndAmounts() {
        var (d, pot) = makeData()
        d.setAllocationPercent(pot.id, in: engNov2026, percent: 20)
        d.setAllocationPercent(pot.id, in: engDec2026, percent: 25)
        d.setAllocation(pot.id, in: engJan2027, amount: 40)
        XCTAssertEqual(d.allocation(pot.id, in: engDec2026), 750)
        d.deletePot(pot.id)
        for plan in d.months.values {
            XCTAssertTrue(plan.percentAllocations.isEmpty)
            XCTAssertNil(plan.allocations[pot.id.uuidString])
        }
        for month in [engNov2026, engDec2026, engJan2027] {
            let ledger = d.monthLedger(month, asOf: engTime(engNov2026, 30, hour: 20))
            XCTAssertEqual(ledger.planToPots, 0, month.key)
            XCTAssertEqual(ledger.closingPots, 0, month.key)
            XCTAssertTrue(ledger.allReconciles, month.key)
        }
    }
}
