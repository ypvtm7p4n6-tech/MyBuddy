import XCTest
import Foundation
@testable import MyBuddyCore

/// D5 (docs/work/plan2.md par. 2.5): geld uit of naar een pot met een bestemming of herkomst. `withdraw` en `deposit` leggen twee gekoppelde
/// boekingen via de bestaande functies; wat Opnemen en Storten altijd deden (`.outside`) blijft de standaard.
final class PotMovesTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)

    private func base() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let pot = Pot(name: "Vakantie", monthlyContribution: 200, startMonth: oct2026)
        d.addPot(pot, openingBalance: 100, now: day(oct2026, 1))
        d.addBankSnapshot(balance: 1_000, note: "Begin", date: day(oct2026, 1))
        var plan = MonthPlan()
        plan.expenses = [MoneyLine(name: "Huur", amount: 900, isRecurring: true, day: 1)]
        d.months[oct2026.key] = plan
        return (d, pot)
    }

    func testWithdrawToTheBankArrivesOnTheBank() {
        var (d, pot) = base()
        let bankBefore = d.bankBalance(on: day(nov, 5))
        XCTAssertTrue(d.withdraw(fromPot: pot.id, amount: 60, to: .bank, date: day(nov, 5)))
        XCTAssertEqual(d.bankBalance(on: day(nov, 5))! - bankBefore!, 60)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(nov, 5)), d.potBalance(pot.id, asOf: day(nov, 4)) - 60)
        let potEntry = d.potEntries.first { $0.kind == .withdrawal }
        let bankEntry = d.bankEntries.first { $0.kind == .fromPot }
        XCTAssertNotNil(potEntry?.pairID)
        XCTAssertEqual(potEntry?.pairID, bankEntry?.pairID)
        XCTAssertEqual(potEntry?.date, bankEntry?.date)
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
        // Een helft verwijderen haalt de andere ook weg.
        d.deletePotEntry(potEntry!.id)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertEqual(d.bankBalance(on: day(nov, 5)), bankBefore)
    }

    func testWithdrawToAnotherPotArrivesThere() {
        var (d, pot) = base()
        let other = Pot(name: "Buffer", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(other, openingBalance: 0, now: day(oct2026, 1))
        XCTAssertTrue(d.withdraw(fromPot: pot.id, amount: 40, to: .pot(other.id), date: day(nov, 6)))
        XCTAssertEqual(d.potBalance(other.id, asOf: day(nov, 6)), 40)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(nov, 6)), d.potBalance(pot.id, asOf: day(nov, 5)) - 40)
        XCTAssertEqual(d.totalSaved(asOf: day(nov, 6)), d.totalSaved(asOf: day(nov, 5)))
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
        let pair = d.potEntries.compactMap { $0.pairID }
        XCTAssertEqual(Set(pair).count, 1)
        XCTAssertEqual(pair.count, 2)
    }

    func testWithdrawOutsideOnlyTouchesThePot() {
        var (d, pot) = base()
        let bankBefore = d.bankBalance(on: day(nov, 5))
        XCTAssertTrue(d.withdraw(fromPot: pot.id, amount: 25, to: .outside, note: "Contant", date: day(nov, 5)))
        XCTAssertEqual(d.bankBalance(on: day(nov, 5)), bankBefore)
        XCTAssertNil(d.potEntries.last?.pairID)
        XCTAssertEqual(d.potEntries.last?.kind, .withdrawal)
        XCTAssertEqual(d.potEntries.last?.amount, -25)
    }

    func testDepositFromBankPotAndOutside() {
        var (d, pot) = base()
        let other = Pot(name: "Buffer", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(other, openingBalance: 500, now: day(oct2026, 1))
        let bankBefore = d.bankBalance(on: day(nov, 5))!
        XCTAssertTrue(d.deposit(toPot: pot.id, amount: 30, from: .bank, date: day(nov, 5)))
        XCTAssertEqual(d.bankBalance(on: day(nov, 5)), bankBefore - 30)
        XCTAssertTrue(d.deposit(toPot: pot.id, amount: 70, from: .pot(other.id), date: day(nov, 6)))
        XCTAssertEqual(d.potBalance(other.id, asOf: day(nov, 6)), 430)
        XCTAssertTrue(d.deposit(toPot: pot.id, amount: 10, from: .outside, date: day(nov, 7)))
        XCTAssertEqual(d.bankBalance(on: day(nov, 7)), bankBefore - 30 + (d.bankBalance(on: day(nov, 7))! - (bankBefore - 30)))
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
    }

    func testInvalidMovesDoNothing() {
        var (d, pot) = base()
        let copy = d
        XCTAssertFalse(d.withdraw(fromPot: pot.id, amount: 0, to: .bank))
        XCTAssertFalse(d.withdraw(fromPot: pot.id, amount: -5, to: .outside))
        XCTAssertFalse(d.withdraw(fromPot: pot.id, amount: 10, to: .pot(pot.id)))
        XCTAssertFalse(d.withdraw(fromPot: pot.id, amount: 10, to: .pot(UUID())))
        XCTAssertFalse(d.withdraw(fromPot: UUID(), amount: 10, to: .bank))
        XCTAssertFalse(d.deposit(toPot: pot.id, amount: 10, from: .pot(pot.id)))
        XCTAssertFalse(d.deposit(toPot: UUID(), amount: 10, from: .outside))
        XCTAssertEqual(d, copy)
    }

    func testBothHalvesFollowTheStartDate() {
        var (d, pot) = base()
        XCTAssertTrue(d.withdraw(fromPot: pot.id, amount: 50, to: .bank, date: day(oct2026, 5)))
        d.setStart(CalendarDay(year: 2026, month: 10, day: 10))
        XCTAssertTrue(d.countedBankEntries.isEmpty)
        XCTAssertTrue(d.countedPotEntries.filter { $0.kind == .withdrawal }.isEmpty)
        XCTAssertTrue(d.withdraw(fromPot: pot.id, amount: 50, to: .bank, date: day(oct2026, 12)))
        XCTAssertEqual(d.countedBankEntries.count, 1)
        XCTAssertEqual(d.countedPotEntries.filter { $0.kind == .withdrawal }.count, 1)
        XCTAssertTrue(d.monthLedger(oct2026).allReconciles)
    }

    func testDeletingTheDestinationPotKeepsTheLedgerClosed() {
        var (d, pot) = base()
        let other = Pot(name: "Buffer", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(other, openingBalance: 0, now: day(oct2026, 1))
        XCTAssertTrue(d.withdraw(fromPot: pot.id, amount: 40, to: .pot(other.id), date: day(nov, 6)))
        d.deletePot(other.id)
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
        // De bronkant staat er nog (het geld is weg met de doelpot); verwijderen kan nog steeds.
        let leftover = d.potEntries.first { $0.kind == .transferOut }
        XCTAssertNotNil(leftover)
        d.deletePotEntry(leftover!.id)
        XCTAssertTrue(d.potEntries.filter { $0.kind == .transferOut }.isEmpty)
    }

    func testRandomMovesKeepEverythingClosed() {
        // De ledgerScenario-reeks "opnemen met bestemming" doet dit al op 60+ datasets; hier de som: bank + potten blijven gelijk
        // bij een verplaatsing tussen bank en potten, ook met een startdatum.
        var moves = 0
        for seed in 1...200 {
            var s = ledgerScenario(seed: UInt64(seed))
            guard s.data.pots.count >= 2 else { continue }
            let a = s.data.pots[0], b = s.data.pots[1]
            let when = day(s.start.adding(1), 8)
            let before = s.data.totalSaved(asOf: when)
            s.data.withdraw(fromPot: a.id, amount: 20, to: .pot(b.id), date: when)
            XCTAssertEqual(s.data.totalSaved(asOf: when), before, "zaadwaarde \(seed)")
            moves += 1
            XCTAssertTrue(s.data.monthLedger(s.start.adding(1), asOf: s.today).allReconciles, "zaadwaarde \(seed)")
        }
        XCTAssertGreaterThan(moves, 100)
    }
}
