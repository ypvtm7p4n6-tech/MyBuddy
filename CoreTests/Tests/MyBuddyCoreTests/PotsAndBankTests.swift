import XCTest
@testable import MyBuddyCore

final class PotsTests: XCTestCase {
    private func makeData(goal: Double? = 2000) -> (FinanceData, Pot) {
        var d = makeBaseData()
        let pot = addBufferPot(&d, opening: 500, goal: goal)
        d.materialize(upTo: oct2026)
        return (d, pot)
    }

    func testBalanceAddsOpeningAndMonthlyAllocations() {
        let (d, pot) = makeData()
        XCTAssertEqual(d.potBalance(pot.id, at: aug2026), 700, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1100, accuracy: 0.001)
        XCTAssertEqual(d.totalSaved(current: oct2026), 1100, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(UUID(), at: oct2026), 0)
    }

    func testSetBalanceCreatesAdjustment() {
        var (d, pot) = makeData()
        d.setPotBalance(pot.id, to: 1500, current: oct2026, note: "Cadeau", date: day(oct2026, 5))
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1500, accuracy: 0.001)
        let adjustment = d.potEntries.last
        XCTAssertEqual(adjustment?.kind, .adjustment)
        XCTAssertEqual(adjustment?.amount ?? 0, 400, accuracy: 0.001)
        let count = d.potEntries.count
        d.setPotBalance(pot.id, to: 1500, current: oct2026)
        XCTAssertEqual(d.potEntries.count, count)
    }

    func testDepositAndWithdrawal() {
        var (d, pot) = makeData()
        d.addPotEntry(potID: pot.id, amount: 100, kind: .deposit, note: "Verjaardag", date: day(oct2026, 10))
        d.addPotEntry(potID: pot.id, amount: -300, kind: .withdrawal, note: "Reparatie", date: day(oct2026, 12))
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 900, accuracy: 0.001)
        // Nul-boekingen worden genegeerd.
        let count = d.potEntries.count
        d.addPotEntry(potID: pot.id, amount: 0, kind: .deposit)
        XCTAssertEqual(d.potEntries.count, count)
    }

    func testProgressAndGoalMonth() {
        let (d, pot) = makeData(goal: 2000)
        XCTAssertEqual(d.potProgress(pot.id, current: oct2026) ?? 0, 0.55, accuracy: 0.0001)
        XCTAssertEqual(d.potGoalMonth(pot.id, current: oct2026), YearMonth(year: 2027, month: 3))
    }

    func testGoalAlreadyReached() {
        let (d, pot) = makeData(goal: 1000)
        XCTAssertEqual(d.potProgress(pot.id, current: oct2026) ?? 0, 1.1, accuracy: 0.0001)
        XCTAssertEqual(d.potGoalMonth(pot.id, current: oct2026), oct2026)
    }

    func testNoGoalMeansNoProgress() {
        let (d, pot) = makeData(goal: nil)
        XCTAssertNil(d.potProgress(pot.id, current: oct2026))
        XCTAssertNil(d.potGoalMonth(pot.id, current: oct2026))
    }

    func testTransfer() {
        var (d, a) = makeData()
        let b = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: aug2026)
        d.addPot(b)
        d.materialize(upTo: oct2026)
        d.transfer(from: a.id, to: b.id, amount: 100, date: day(oct2026, 8))
        XCTAssertEqual(d.potBalance(a.id, at: oct2026), 1000, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(b.id, at: oct2026), 100, accuracy: 0.001)
        // Ongeldige overboekingen doen niets.
        let count = d.potEntries.count
        d.transfer(from: a.id, to: a.id, amount: 50)
        d.transfer(from: a.id, to: b.id, amount: 0)
        XCTAssertEqual(d.potEntries.count, count)
    }

    func testTimelineMergesEntriesAndAllocations() {
        let (d, pot) = makeData()
        let items = d.potTimeline(pot.id, current: oct2026)
        XCTAssertEqual(items.count, 4) // beginsaldo + 3 maandverdelingen
        XCTAssertEqual(items.first?.id, "alloc-2026-10")
        XCTAssertEqual(items.filter { !$0.isMonthlyAllocation }.count, 1)
    }

    func testDeletePotCleansEverything() {
        var (d, pot) = makeData()
        d.homePotIDs = [pot.id]
        var goal = LifeGoal(name: "Doel", kind: .custom)
        goal.funding = .pot(pot.id)
        d.addGoal(goal)
        d.deletePot(pot.id)
        XCTAssertTrue(d.pots.isEmpty)
        XCTAssertTrue(d.potEntries.isEmpty)
        XCTAssertNil(d.months[oct2026.key]?.allocations[pot.id.uuidString])
        XCTAssertEqual(d.homePotIDs, [])
        XCTAssertEqual(d.goals.first?.funding, .portfolio)
    }

    func testHomePotsDefaultAndChosen() {
        var (d, first) = makeData()
        let p2 = Pot(name: "Twee", startMonth: aug2026)
        let p3 = Pot(name: "Drie", startMonth: aug2026)
        let p4 = Pot(name: "Vier", startMonth: aug2026)
        [p2, p3, p4].forEach { d.addPot($0) }
        XCTAssertEqual(d.homePots().map(\.name), [first.name, "Twee", "Drie"])
        d.homePotIDs = [p4.id, UUID(), first.id]
        XCTAssertEqual(d.homePots().map(\.name), ["Vier", first.name])
    }
}

final class BankTests: XCTestCase {
    private func makeData() -> FinanceData {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 1000, note: "Start", date: day(aug2026, 5))
        return d
    }

    func testBalanceFollowsSnapshotPlusSurplus() {
        let d = makeData()
        XCTAssertNil(d.bankBalance(at: YearMonth(year: 2026, month: 7)))
        XCTAssertEqual(d.bankBalance(at: aug2026) ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: sep2026) ?? 0, 3100, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? 0, 5200, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026), 5200, accuracy: 0.001)
    }

    func testNewestSnapshotWins() {
        var d = makeData()
        d.addBankSnapshot(balance: 4000, date: day(sep2026, 20))
        XCTAssertEqual(d.bankBalance(at: aug2026) ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: sep2026) ?? 0, 4000, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? 0, 6100, accuracy: 0.001)
    }

    func testSeriesMarksProjection() {
        let d = makeData()
        let series = d.bankSeries(from: aug2026, count: 5, current: oct2026)
        XCTAssertEqual(series.count, 5)
        XCTAssertEqual(series.map(\.isProjected), [false, false, false, true, true])
        XCTAssertEqual(series.last?.balance ?? 0, 9400, accuracy: 0.001)
    }

    func testBufferAndSurplus() {
        let d = makeData()
        // Gemiddelde uitgaven: (1050 + 1000 + 1000) / 3 = 1016,67; buffer 2 maanden.
        XCTAssertEqual(d.averageMonthlyExpenses(current: oct2026), 1016.67, accuracy: 0.01)
        XCTAssertEqual(d.bankBuffer(current: oct2026), 2033.34, accuracy: 0.02)
        XCTAssertEqual(d.bankSurplusAboveBuffer(current: oct2026), 3166.66, accuracy: 0.03)
    }

    func testNoSnapshotMeansNoSurplus() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        XCTAssertFalse(d.hasBankBalance)
        XCTAssertEqual(d.bankSurplusAboveBuffer(current: oct2026), 0)
        d.addBankSnapshot(balance: 10)
        d.deleteBankSnapshot(d.bankSnapshots[0].id)
        XCTAssertFalse(d.hasBankBalance)
    }
}
