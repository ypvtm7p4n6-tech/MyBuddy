import XCTest
@testable import MyBuddyCore

final class ExpensesTests: XCTestCase {
    func testOverviewSplitsFixedAndVariable() {
        var d = makeBaseData() // inkomen 3100, huur 1000 + eenmalig 50 (beide vast)
        var o = d.expenseOverview(in: aug2026)
        XCTAssertEqual(o.income, 3100, accuracy: 0.001)
        XCTAssertEqual(o.fixed, 1050, accuracy: 0.001)
        XCTAssertEqual(o.variable, 0, accuracy: 0.001)
        XCTAssertEqual(o.leftAfterExpenses, 2050, accuracy: 0.001)

        d.upsertLine(MoneyLine(name: "Boodschappen", amount: 300, kind: .variable), kind: .expense, in: aug2026)
        o = d.expenseOverview(in: aug2026)
        XCTAssertEqual(o.variable, 300, accuracy: 0.001)
        XCTAssertEqual(o.expenses, 1350, accuracy: 0.001)
        XCTAssertEqual(o.leftAfterExpenses, 1750, accuracy: 0.001)
        XCTAssertEqual(o.fixedShare, 1050.0 / 3100.0, accuracy: 0.0001)
        XCTAssertEqual(o.variableShare, 300.0 / 3100.0, accuracy: 0.0001)
    }

    func testOverviewIncludesTransfersToPotsAndHoldings() {
        var d = makeBaseData()
        _ = addBufferPot(&d) // 200 per maand
        d.addHolding(Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, monthlyContribution: 100, startMonth: aug2026))
        let o = d.expenseOverview(in: aug2026)
        XCTAssertEqual(o.toPots, 200, accuracy: 0.001)
        XCTAssertEqual(o.toInvestments, 100, accuracy: 0.001)
        XCTAssertEqual(o.leftAfterTransfers, 3100 - 1050 - 200 - 100, accuracy: 0.001)
        XCTAssertEqual(o.leftAfterTransfers, d.remaining(in: aug2026), accuracy: 0.001)
    }

    func testOverviewBeforeStartIsEmpty() {
        let d = makeBaseData()
        let o = d.expenseOverview(in: YearMonth(year: 2026, month: 7))
        XCTAssertEqual(o.income, 0)
        XCTAssertEqual(o.expenses, 0)
        XCTAssertEqual(o.fixedShare, 0)
    }

    func testStandardListHasSixteenItems() {
        XCTAssertEqual(StandardExpenses.fixed.count, 8)
        XCTAssertEqual(StandardExpenses.variable.count, 8)
        XCTAssertEqual(StandardExpenses.all.count, 16)
        XCTAssertEqual(StandardExpenses.fixed.reduce(0) { $0 + $1.amount }, 1395, accuracy: 0.001)
        XCTAssertEqual(StandardExpenses.variable.reduce(0) { $0 + $1.amount }, 800, accuracy: 0.001)
        XCTAssertTrue(StandardExpenses.fixed.allSatisfy { $0.kind == .fixed })
        XCTAssertTrue(StandardExpenses.variable.allSatisfy { $0.kind == .variable })
        XCTAssertEqual(Set(StandardExpenses.all.map { $0.name.lowercased() }).count, 16)
    }

    func testFillStandardExpenses() {
        var d = makeBaseData()
        d.materialize(upTo: sep2026)
        // Oktober is nog niet vastgelegd: de terugkerende huur (1000) wordt meegenomen.
        XCTAssertEqual(d.missingStandardExpenses(in: oct2026).count, 16)
        let added = d.fillStandardExpenses(in: oct2026)
        XCTAssertEqual(added, 16)
        let o = d.expenseOverview(in: oct2026)
        XCTAssertEqual(o.fixed, 1000 + 1395, accuracy: 0.001)
        XCTAssertEqual(o.variable, 800, accuracy: 0.001)
        XCTAssertTrue(d.plan(for: oct2026).expenses.allSatisfy { $0.isRecurring })
        // Tweede keer voegt niets toe.
        XCTAssertEqual(d.fillStandardExpenses(in: oct2026), 0)
        XCTAssertEqual(d.plan(for: oct2026).expenses.count, 17)
    }

    func testFillSkipsExistingNamesCaseInsensitively() {
        var d = makeBaseData()
        d.upsertLine(MoneyLine(name: "boodschappen", amount: 10, kind: .variable), kind: .expense, in: oct2026)
        XCTAssertEqual(d.fillStandardExpenses(in: oct2026), 15)
        // Het eigen bedrag blijft staan.
        let own = d.plan(for: oct2026).expenses.first { $0.name == "boodschappen" }
        XCTAssertEqual(own?.amount, 10)
    }

    func testFilledLinesCarryOverToFutureMonths() {
        var d = makeBaseData()
        d.fillStandardExpenses(in: aug2026)
        d.materialize(upTo: sep2026)
        XCTAssertEqual(d.expenseOverview(in: sep2026).variable, 800, accuracy: 0.001)
        XCTAssertEqual(d.expenseLines(in: sep2026, kind: .variable).count, 8)
    }

    func testMoneyLineDecodesOldFilesWithoutKind() throws {
        let json = #"{"id":"5F2A8B0C-1111-4C4C-9999-000000000001","name":"Huur","amount":900,"isRecurring":true}"#
        let line = try JSONDecoder().decode(MoneyLine.self, from: Data(json.utf8))
        XCTAssertEqual(line.kind, .fixed)
        XCTAssertEqual(line.amount, 900)
        XCTAssertTrue(line.isRecurring)
        let bare = try JSONDecoder().decode(MoneyLine.self, from: Data(#"{"name":"X","amount":1}"#.utf8))
        XCTAssertEqual(bare.name, "X")
        XCTAssertFalse(bare.isRecurring)
    }

    func testMoneyLineRoundTripKeepsKind() throws {
        let line = MoneyLine(name: "Uit eten", amount: 80, isRecurring: true, kind: .variable)
        let back = try JSONDecoder().decode(MoneyLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(back, line)
    }

    func testTotalsByKind() {
        let lines = [MoneyLine(name: "a", amount: 10, kind: .fixed), MoneyLine(name: "b", amount: 5, kind: .variable),
                     MoneyLine(name: "c", amount: 2.5, kind: .variable)]
        XCTAssertEqual(lines.total, 17.5, accuracy: 0.001)
        XCTAssertEqual(lines.total(of: .variable), 7.5, accuracy: 0.001)
        XCTAssertEqual(lines.total(of: .fixed), 10, accuracy: 0.001)
    }
}

final class BankEntryTests: XCTestCase {
    private func makeData() -> FinanceData {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 1000, note: "Start", date: day(aug2026, 5))
        return d
    }

    func testDepositsAndWithdrawalsChangeTheBalance() {
        var d = makeData()
        d.addBankEntry(amount: 500, note: "Verjaardag", date: day(sep2026, 10))
        d.addBankEntry(amount: -200, note: "Contant", date: day(oct2026, 3))
        XCTAssertEqual(d.bankBalance(at: aug2026) ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: sep2026) ?? 0, 3600, accuracy: 0.001) // 1000 + 2100 + 500
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? 0, 5500, accuracy: 0.001) // + 2100 - 200
        XCTAssertEqual(d.bankEntries.map(\.kind), [.deposit, .withdrawal])
    }

    func testEntriesBeforeTheSnapshotAreAlreadyInTheBalance() {
        var d = makeData()
        d.addBankEntry(amount: 999, date: day(aug2026, 1))
        XCTAssertEqual(d.bankBalance(at: aug2026) ?? 0, 1000, accuracy: 0.001)
    }

    func testZeroEntryIsIgnoredAndEntriesCanBeDeleted() {
        var d = makeData()
        d.addBankEntry(amount: 0)
        XCTAssertTrue(d.bankEntries.isEmpty)
        d.addBankEntry(amount: 50, date: day(sep2026, 2))
        d.deleteBankEntry(d.bankEntries[0].id)
        XCTAssertTrue(d.bankEntries.isEmpty)
    }

    func testAccountWithoutSnapshotStartsAtZeroWithFirstDeposit() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        XCTAssertFalse(d.hasBankBalance)
        d.addBankEntry(amount: 300, date: day(sep2026, 10))
        XCTAssertTrue(d.hasBankBalance)
        XCTAssertNil(d.bankBalance(at: aug2026))
        XCTAssertEqual(d.bankBalance(at: sep2026) ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? 0, 2400, accuracy: 0.001) // + overschot oktober 2100
    }

    func testTransferBankToPotAndBack() {
        var d = makeBaseData()
        let pot = addBufferPot(&d) // saldo in oktober 1100
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 1000, date: day(oct2026, 1))

        d.transferBankToPot(potID: pot.id, amount: 100, date: day(oct2026, 5))
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1200, accuracy: 0.001)
        XCTAssertEqual(d.bankEntries.last?.kind, .toPot)
        XCTAssertEqual(d.bankEntries.last?.potID, pot.id)

        d.transferPotToBank(potID: pot.id, amount: 50, date: day(oct2026, 6))
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? 0, 950, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1150, accuracy: 0.001)
        XCTAssertEqual(d.bankEntries.last?.kind, .fromPot)
    }

    func testInvalidTransfersDoNothing() {
        var d = makeData()
        let pot = addBufferPot(&d)
        d.transferBankToPot(potID: pot.id, amount: 0)
        d.transferBankToPot(potID: UUID(), amount: 10)
        d.transferPotToBank(potID: pot.id, amount: -5)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertEqual(d.potEntries.count, 1) // alleen het beginsaldo
    }
}

final class PotTotalsTests: XCTestCase {
    func testTotalGoalAndSavedTowardGoals() {
        var d = makeBaseData()
        _ = addBufferPot(&d, opening: 500, goal: 2000)           // saldo oktober 1100
        d.addPot(Pot(name: "Vrij", monthlyContribution: 0, startMonth: aug2026), openingBalance: 300, now: day(aug2026, 3))
        d.materialize(upTo: oct2026)
        XCTAssertEqual(d.totalGoal(), 2000, accuracy: 0.001)
        XCTAssertEqual(d.savedTowardGoals(current: oct2026), 1100, accuracy: 0.001)
        XCTAssertEqual(d.totalSaved(current: oct2026), 1400, accuracy: 0.001)

        d.addPot(Pot(name: "Fiets", goalAmount: 500, monthlyContribution: 0, startMonth: aug2026))
        XCTAssertEqual(d.totalGoal(), 2500, accuracy: 0.001)
    }

    func testNoPotsMeansZero() {
        let d = makeBaseData()
        XCTAssertEqual(d.totalGoal(), 0)
        XCTAssertEqual(d.savedTowardGoals(current: oct2026), 0)
    }
}

final class SettingsDecodingTests: XCTestCase {
    func testPartialSettingsKeepDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"inflation":0.03}"#.utf8))
        XCTAssertEqual(s.inflation, 0.03, accuracy: 0.000001)
        XCTAssertEqual(s.savingsRate, AppSettings().savingsRate, accuracy: 0.000001)
        XCTAssertEqual(s.bankBufferMonths, AppSettings().bankBufferMonths)
        XCTAssertNil(s.lastMarketUpdate)
    }

    func testHolderWithTickerButNoUnitsIsNotTrackedButHasTicker() {
        let h = Holding(name: "ETF", kind: .etf, ticker: "VWCE.DE", units: nil, startMonth: aug2026)
        XCTAssertTrue(h.hasTicker)
        XCTAssertFalse(h.isTracked)
        var priced = h
        priced.units = 3
        XCTAssertTrue(priced.isTracked)
    }

    func testRecordPriceWithoutUnitsStoresPriceButNoSnapshot() {
        var d = makeBaseData()
        let h = Holding(name: "ETF", kind: .etf, ticker: "VWCE.DE", units: nil, startMonth: aug2026)
        d.addHolding(h)
        d.recordPrice(holdingID: h.id, price: 120, currency: "EUR", date: day(oct2026, 2))
        XCTAssertEqual(d.holdings[0].lastPrice, 120)
        XCTAssertTrue(d.holdings[0].snapshots.isEmpty)
    }
}
