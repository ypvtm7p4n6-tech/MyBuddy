import XCTest
@testable import MyBuddyCore

/// Controle van de logica achter het scherm "Verdelen" (SavingsPages.swift): inlegwijze per maand, standaard.
final class AllocationEditTests: XCTestCase {
    private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }
    private let now = YearMonth(year: 2026, month: 10)

    private struct Fixture {
        var data: FinanceData
        var potID: UUID
        var otherPotID: UUID
        var holdingID: UUID
    }

    private func fixture() -> Fixture {
        var d = FinanceData(startMonth: YearMonth(year: 2026, month: 8))
        d.salary.fixedMonthly = 3000
        d.salary.payDay = 25
        let pot = Pot(name: "Vakantie", monthlyContribution: 300, startMonth: YearMonth(year: 2026, month: 8))
        let other = Pot(name: "Auto", monthlyContribution: 100, startMonth: YearMonth(year: 2026, month: 8))
        let holding = Holding(name: "ETF", monthlyContribution: 200, startMonth: YearMonth(year: 2026, month: 8))
        d.pots = [pot, other]
        d.holdings = [holding]
        d.materialize(upTo: YearMonth(year: 2026, month: 10))
        // Extra inkomsten in oktober: alleen voor de grondslag "alle inkomsten".
        d.editPlan(YearMonth(year: 2026, month: 10)) { $0.extraIncome.append(MoneyLine(name: "Bonus", amount: 500, day: 10)) }
        return Fixture(data: d, potID: pot.id, otherPotID: other.id, holdingID: holding.id)
    }

    func testSwitchToPercentageKeepsTheAmount() {
        var f = fixture()
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 300)
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        let effective = f.data.effectiveAllocation(f.potID, in: now)
        guard case .percent(let rule) = effective.rule else { return XCTFail("moet een percentage zijn") }
        XCTAssertEqual(rule.percent, 10)
        XCTAssertEqual(rule.basis, .salary)
        XCTAssertEqual(effective.amount, 300)
        XCTAssertTrue(effective.isOverride, "de standaard is een vast bedrag")
        // Hetzelfde bedrag overal.
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 300)
        XCTAssertEqual(f.data.monthFigures(now).saved, 40_000)
    }

    func testPercentRoundsAndFollowsIncomeAcrossScreens() throws {
        var f = fixture()
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.potID, month: now, percent: 12.5)
        let amount = f.data.allocation(f.potID, in: now)
        XCTAssertEqual(amount, 375)
        XCTAssertEqual(f.data.percentAmount(12.5, of: .salary, in: now), 375)
        // Overzicht, te verdelen, dagen en spaarpotten tonen hetzelfde bedrag.
        XCTAssertEqual(f.data.savedTotal(in: now), 475)   // 375 + 100 van de andere pot
        let ledger = f.data.monthLedger(now, asOf: ym(2026, 10).date(day: 14))
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertEqual(ledger.saved, 475)
        let event = try XCTUnwrap(f.data.dayEvents(in: now).first { $0.kind == .toPot && $0.potID == f.potID })
        XCTAssertEqual(event.potAmount, 375)
        XCTAssertEqual(event.bankAmount, -375)
        // Meer salaris: het bedrag gaat mee.
        f.data.editPlan(now) { $0.salaryOverride = 4000 }
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 500)
    }

    func testBasisAllIncomeIncludesExtraIncome() {
        var f = fixture()
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.potID, month: now, percent: 10)
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 300)
        AllocationEdit.setBasis(&f.data, id: f.potID, month: now, to: .allIncome)
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 350)   // 10% van 3000 + 500
        // De grondslag blijft bij een ander percentage.
        AllocationEdit.setPercent(&f.data, id: f.potID, month: now, percent: 20)
        guard case .percent(let rule) = f.data.allocationRule(f.potID, in: now) else { return XCTFail() }
        XCTAssertEqual(rule.basis, .allIncome)
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 700)
    }

    func testSwitchBackToFixedKeepsCurrentAmount() {
        var f = fixture()
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.potID, month: now, percent: 7.5)
        let before = f.data.allocation(f.potID, in: now)
        XCTAssertEqual(before, 225)
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .fixed)
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 225)
        XCTAssertFalse(f.data.allocationRule(f.potID, in: now).isPercent)
        // Zelfde modus nog eens: niets verandert.
        let copy = f.data
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .fixed)
        XCTAssertEqual(f.data, copy)
    }

    func testResetToStandardRemovesTheOverride() {
        var f = fixture()
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.potID, month: now, percent: 50)
        XCTAssertTrue(f.data.effectiveAllocation(f.potID, in: now).isOverride)
        AllocationEdit.resetToStandard(&f.data, id: f.potID, month: now)
        let effective = f.data.effectiveAllocation(f.potID, in: now)
        XCTAssertFalse(effective.isOverride)
        XCTAssertEqual(effective.amount, 300)
        XCTAssertEqual(effective.rule, .amount(300))
    }

    func testMakeStandardAppliesToCurrentAndFutureMonths() {
        var f = fixture()
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.potID, month: now, percent: 15)
        AllocationEdit.makeStandard(&f.data, id: f.potID, month: now, current: now)
        XCTAssertEqual(f.data.contributionRule(of: f.potID), .percent(PercentRule(percent: 15, basis: .salary)))
        XCTAssertFalse(f.data.effectiveAllocation(f.potID, in: now).isOverride)
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 450)
        // Volgende maanden: 15% van het salaris van die maand (met een ander salaris in december).
        XCTAssertEqual(f.data.allocation(f.potID, in: ym(2026, 11)), 450)
        f.data.editPlan(ym(2026, 12)) { $0.salaryOverride = 4000 }
        XCTAssertEqual(f.data.allocation(f.potID, in: ym(2026, 12)), 600)
    }

    func testMakeStandardFromFutureMonthClearsItsOverride() {
        var f = fixture()
        let next = ym(2026, 11)
        AllocationEdit.setMode(&f.data, id: f.potID, month: next, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.potID, month: next, percent: 20)
        XCTAssertTrue(f.data.effectiveAllocation(f.potID, in: next).isOverride)
        AllocationEdit.makeStandard(&f.data, id: f.potID, month: next, current: now)
        XCTAssertFalse(f.data.effectiveAllocation(f.potID, in: next).isOverride)
        XCTAssertEqual(f.data.allocation(f.potID, in: next), 600)
        // De lopende maand krijgt de standaard ook meteen (de motor synchroniseert).
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 600)
    }

    func testMakeStandardForFixedAmount() {
        var f = fixture()
        AllocationEdit.setAmount(&f.data, id: f.potID, month: now, amount: 425)
        AllocationEdit.makeStandard(&f.data, id: f.potID, month: now, current: now)
        XCTAssertEqual(f.data.contributionRule(of: f.potID), .amount(425))
        XCTAssertEqual(f.data.allocation(f.potID, in: ym(2027, 3)), 425)
    }

    func testPastMonthIsNotRewrittenByMakeStandard() {
        var f = fixture()
        let past = ym(2026, 9)
        AllocationEdit.setAmount(&f.data, id: f.potID, month: past, amount: 50)
        AllocationEdit.makeStandard(&f.data, id: f.potID, month: past, current: now)
        // De standaard is nu 50, maar september blijft zijn eigen (vastgelegde) bedrag houden.
        XCTAssertEqual(f.data.contributionRule(of: f.potID), .amount(50))
        XCTAssertEqual(f.data.allocation(f.potID, in: past), 50)
    }

    func testOverHundredPercentWarnsWithoutCrash() {
        var f = fixture()
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.potID, month: now, percent: 60)
        AllocationEdit.setMode(&f.data, id: f.otherPotID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.otherPotID, month: now, percent: 50)
        let warnings = f.data.allocationWarnings(in: now)
        XCTAssertTrue(warnings.contains { if case .percentagesOver100 = $0 { return true } else { return false } })
        XCTAssertEqual(f.data.percentTotal(in: now), 110)
        XCTAssertTrue(warnings.allSatisfy { !$0.message.isEmpty })
        XCTAssertTrue(f.data.monthLedger(now, asOf: ym(2026, 10).date(day: 14)).allReconciles)
    }

    func testStartingPercentWithoutIncomeIsZero() {
        var f = fixture()
        f.data.editPlan(now) { $0.salaryOverride = 0 }
        f.data.editPlan(now) { $0.extraIncome = [] }
        let rule = AllocationEdit.startingPercent(f.data, id: f.potID, month: now)
        XCTAssertEqual(rule.percent, 0)
        // Percentage van niets is niets, en de verdeling blijft rekenen.
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        XCTAssertEqual(f.data.allocation(f.potID, in: now), 0)
    }

    func testPercentOfHoldingWorksLikePot() {
        var f = fixture()
        AllocationEdit.setMode(&f.data, id: f.holdingID, month: now, to: .percentage)
        AllocationEdit.setPercent(&f.data, id: f.holdingID, month: now, percent: 5)
        XCTAssertEqual(f.data.allocation(f.holdingID, in: now), 150)
        XCTAssertEqual(f.data.investedTotal(in: now), 150)
    }

    func testPercentDefaultStartsFromStandardPercent() {
        var f = fixture()
        f.data.setContributionPercent(f.potID, percent: 8, basis: .allIncome, current: now)
        // Nu eerst een vast bedrag voor deze maand, daarna terug naar een percentage: de standaard komt terug.
        AllocationEdit.setAmount(&f.data, id: f.potID, month: now, amount: 123)
        AllocationEdit.setMode(&f.data, id: f.potID, month: now, to: .percentage)
        XCTAssertEqual(f.data.allocationRule(f.potID, in: now), .percent(PercentRule(percent: 8, basis: .allIncome)))
        XCTAssertFalse(f.data.effectiveAllocation(f.potID, in: now).isOverride)
    }
}
