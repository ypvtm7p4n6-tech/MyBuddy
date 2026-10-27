import XCTest
@testable import MyBuddyCore

/// Tests voor `RecentActivity` (B18 van docs/design2/plan.md): de laatste handmatige boekingen voor de groep Recent van de
/// Bibliotheek. Het beginsaldo en de rente tellen niet mee, een overboeking staat eenmaal, een boeking in de toekomst nog niet.
final class RecentActivityTests: XCTestCase {
    /// "Vandaag": 20 oktober 2026 om 12:00.
    private let today = day(oct2026, 20)

    /// Twee potten (Vakantie met beginsaldo 400, Buffer met 900) in eigen kleuren en symbolen, zonder boekingen erbij.
    private func makeData() -> (data: FinanceData, vakantie: Pot, buffer: Pot) {
        var d = FinanceData(startMonth: aug2026)
        var vakantie = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: aug2026)
        vakantie.symbol = "airplane"
        vakantie.colorIndex = 1
        var buffer = Pot(name: "Buffer", monthlyContribution: 0, startMonth: aug2026)
        buffer.symbol = "shield.lefthalf.filled"
        buffer.colorIndex = 2
        d.addPot(vakantie, openingBalance: 400, now: day(aug2026, 1))
        d.addPot(buffer, openingBalance: 900, now: day(aug2026, 1))
        return (d, vakantie, buffer)
    }

    // MARK: Leeg, beginsaldo en rente

    func testNoDataGivesNoItems() {
        let d = FinanceData(startMonth: aug2026)
        XCTAssertTrue(RecentActivity.items(in: d, asOf: today).isEmpty)
    }

    func testOpeningBalancesAreNotRecent() {
        let (d, _, _) = makeData()
        XCTAssertEqual(d.potEntries.count, 2)
        XCTAssertTrue(d.potEntries.allSatisfy { $0.kind == .opening })
        XCTAssertTrue(RecentActivity.items(in: d, asOf: today).isEmpty)
    }

    func testInterestThatTheAppBooksItselfIsNotRecent() {
        var (d, vakantie, _) = makeData()
        d.potEntries.append(PotEntry(potID: vakantie.id, date: day(oct2026, 3), amount: 4, kind: .interest, note: "Rente"))
        XCTAssertTrue(RecentActivity.items(in: d, asOf: today).isEmpty)
        d.addPotEntry(potID: vakantie.id, amount: 25, kind: .deposit, date: day(oct2026, 4))
        XCTAssertEqual(RecentActivity.items(in: d, asOf: today).count, 1)
    }

    func testAnEntryOfAPotThatNoLongerExistsIsLeftOut() {
        var (d, _, _) = makeData()
        d.potEntries.append(PotEntry(potID: UUID(), date: day(oct2026, 3), amount: 50, kind: .deposit))
        XCTAssertTrue(RecentActivity.items(in: d, asOf: today).isEmpty)
    }

    // MARK: Volgorde en inhoud

    func testNewestFirstAcrossBankAndPots() {
        var (d, vakantie, _) = makeData()
        d.addBankEntry(amount: 100, note: "Cadeau", date: day(oct2026, 5))
        d.addPotEntry(potID: vakantie.id, amount: 60, kind: .deposit, note: "Verjaardag", date: day(oct2026, 8))
        d.addBankEntry(amount: -20, date: day(oct2026, 12))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map { $0.date }, [day(oct2026, 12), day(oct2026, 8), day(oct2026, 5)])

        XCTAssertEqual(items[0].title, "Bankrekening")
        XCTAssertEqual(items[0].amount, -20, accuracy: 0.001)
        XCTAssertEqual(items[0].destination, .bank)
        XCTAssertEqual(items[0].symbol, "building.columns")
        XCTAssertEqual(items[0].hue, .terracotta)
        XCTAssertEqual(items[0].subtitle, "Geld eraf · " + Fmt.date(day(oct2026, 12)))

        XCTAssertEqual(items[1].title, "Vakantie")
        XCTAssertEqual(items[1].amount, 60, accuracy: 0.001)
        XCTAssertEqual(items[1].destination, .pot(vakantie.id))
        XCTAssertEqual(items[1].symbol, "airplane")
        XCTAssertEqual(items[1].hue, TileHue.forIndex(1))
        XCTAssertEqual(items[1].subtitle, "Gestort · Verjaardag · " + Fmt.date(day(oct2026, 8)))

        XCTAssertEqual(items[2].subtitle, "Geld erbij · Cadeau · " + Fmt.date(day(oct2026, 5)))
        XCTAssertEqual(items[2].amount, 100, accuracy: 0.001)
    }

    func testTheIDsAreUnique() {
        var (d, vakantie, buffer) = makeData()
        d.addBankEntry(amount: 10, date: day(oct2026, 1))
        d.addBankEntry(amount: 10, date: day(oct2026, 1))
        d.addPotEntry(potID: vakantie.id, amount: 10, kind: .deposit, date: day(oct2026, 1))
        d.transfer(from: vakantie.id, to: buffer.id, amount: 5, date: day(oct2026, 2))
        let ids = RecentActivity.items(in: d, asOf: today, limit: 50).map { $0.id }
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(Set(ids).count, 4)
    }

    func testOnTheSameDayTheEntryAddedLaterComesFirst() {
        var (d, _, _) = makeData()
        d.addBankEntry(amount: 10, note: "eerst", date: day(oct2026, 7))
        d.addBankEntry(amount: 20, note: "daarna", date: day(oct2026, 7))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.map { $0.amount }, [20, 10])
    }

    func testAdjustmentsAndWithdrawalsAreBookings() {
        var (d, vakantie, buffer) = makeData()
        d.addPotEntry(potID: vakantie.id, amount: -75, kind: .withdrawal, date: day(oct2026, 6))
        d.setPotBalance(buffer.id, to: 1000, current: oct2026, date: day(oct2026, 9))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Buffer")
        XCTAssertTrue(items[0].subtitle.hasPrefix("Saldo aangepast"))
        XCTAssertEqual(items[1].title, "Vakantie")
        XCTAssertTrue(items[1].subtitle.hasPrefix("Opgenomen"))
        XCTAssertEqual(items[1].amount, -75, accuracy: 0.001)
    }

    func testEmptyNotesLeaveNoSeparator() {
        var (d, vakantie, _) = makeData()
        d.addPotEntry(potID: vakantie.id, amount: 10, kind: .deposit, note: "   ", date: day(oct2026, 6))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.first?.subtitle, "Gestort · " + Fmt.date(day(oct2026, 6)))
    }

    // MARK: Toekomst en limiet

    func testEntriesAfterTodayAreLeftOutButTodayCounts() {
        var (d, _, _) = makeData()
        d.addBankEntry(amount: 10, date: day(oct2026, 19))
        d.addBankEntry(amount: 20, date: today)
        d.addBankEntry(amount: 30, date: day(oct2026, 21))
        d.addBankEntry(amount: 40, date: day(oct2026, 28))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.map { $0.amount }, [20, 10])
        // Een week later telt alles mee.
        XCTAssertEqual(RecentActivity.items(in: d, asOf: day(oct2026, 29)).count, 4)
    }

    func testLimit() {
        var (d, _, _) = makeData()
        for number in 1...8 {
            d.addBankEntry(amount: Double(number), date: day(oct2026, number))
        }
        let standard = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(standard.count, 5)
        XCTAssertEqual(standard.map { $0.amount }, [8, 7, 6, 5, 4])
        XCTAssertEqual(RecentActivity.items(in: d, asOf: today, limit: 3).map { $0.amount }, [8, 7, 6])
        XCTAssertEqual(RecentActivity.items(in: d, asOf: today, limit: 1).map { $0.amount }, [8])
        XCTAssertEqual(RecentActivity.items(in: d, asOf: today, limit: 50).count, 8)
        XCTAssertTrue(RecentActivity.items(in: d, asOf: today, limit: 0).isEmpty)
        XCTAssertTrue(RecentActivity.items(in: d, asOf: today, limit: -2).isEmpty)
    }

    // MARK: Overboekingen

    func testTransferFromBankToPotShowsOnceFromThePot() {
        var (d, vakantie, _) = makeData()
        d.transferBankToPot(potID: vakantie.id, amount: 150, date: day(oct2026, 10))
        XCTAssertEqual(d.bankEntries.count, 1)
        XCTAssertEqual(d.potEntries.count, 3)
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Vakantie")
        XCTAssertEqual(items[0].amount, 150, accuracy: 0.001)
        XCTAssertEqual(items[0].subtitle, "Van bankrekening · " + Fmt.date(day(oct2026, 10)))
        XCTAssertEqual(items[0].destination, .pot(vakantie.id))
        XCTAssertTrue(items[0].id.hasPrefix("transfer-"))
    }

    func testTransferFromPotToBankShowsOnceFromThePot() {
        var (d, _, buffer) = makeData()
        d.transferPotToBank(potID: buffer.id, amount: 200, date: day(oct2026, 11))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Buffer")
        XCTAssertEqual(items[0].amount, -200, accuracy: 0.001)
        XCTAssertEqual(items[0].subtitle, "Naar bankrekening · " + Fmt.date(day(oct2026, 11)))
        XCTAssertEqual(items[0].destination, .pot(buffer.id))
    }

    func testTransferBetweenPotsShowsOnceFromThePotThatGaveTheMoney() {
        var (d, vakantie, buffer) = makeData()
        d.transfer(from: buffer.id, to: vakantie.id, amount: 80, date: day(oct2026, 13))
        XCTAssertEqual(d.potEntries.count, 4)
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Buffer")
        XCTAssertEqual(items[0].amount, -80, accuracy: 0.001)
        XCTAssertEqual(items[0].subtitle, "Naar Vakantie · " + Fmt.date(day(oct2026, 13)))
        XCTAssertEqual(items[0].destination, .pot(buffer.id))
        XCTAssertEqual(items[0].symbol, "shield.lefthalf.filled")
        XCTAssertEqual(items[0].hue, TileHue.forIndex(2))
    }

    func testTheShownHalfDoesNotDependOnTheOrderOfTheEntries() {
        var (d, vakantie, buffer) = makeData()
        d.transfer(from: vakantie.id, to: buffer.id, amount: 30, date: day(oct2026, 13))
        d.potEntries.reverse()
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Vakantie")
        XCTAssertEqual(items[0].amount, -30, accuracy: 0.001)
    }

    func testTransfersAndPlainEntriesTogether() {
        var (d, vakantie, buffer) = makeData()
        d.addBankEntry(amount: 500, date: day(oct2026, 2))
        d.transferBankToPot(potID: vakantie.id, amount: 100, date: day(oct2026, 3))
        d.transfer(from: vakantie.id, to: buffer.id, amount: 25, date: day(oct2026, 4))
        d.addPotEntry(potID: buffer.id, amount: 10, kind: .deposit, date: day(oct2026, 5))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.map { $0.date }, [day(oct2026, 5), day(oct2026, 4), day(oct2026, 3), day(oct2026, 2)])
    }

    func testDeletingATransferRemovesItFromRecent() {
        var (d, vakantie, _) = makeData()
        d.transferBankToPot(potID: vakantie.id, amount: 100, date: day(oct2026, 3))
        guard let id = d.bankEntries.first?.id else { return XCTFail("geen bankboeking") }
        d.deleteBankEntry(id)
        XCTAssertTrue(RecentActivity.items(in: d, asOf: today).isEmpty)
    }

    func testAnOldTransferWithoutPairShowsTheBankSideAndThePotSideSeparately() {
        var (d, vakantie, _) = makeData()
        d.bankEntries.append(BankEntry(date: day(oct2026, 3), amount: -100, kind: .toPot, note: "Naar Vakantie", potID: vakantie.id))
        d.potEntries.append(PotEntry(potID: vakantie.id, date: day(oct2026, 3), amount: 100, kind: .deposit, note: "Van bankrekening"))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 2)
        let titles = Set(items.map { $0.title })
        XCTAssertEqual(titles, ["Bankrekening", "Vakantie"])
    }

    func testABankHalfWhoseOtherHalfIsGoneStaysAsABankEntry() {
        var (d, vakantie, _) = makeData()
        d.bankEntries.append(BankEntry(date: day(oct2026, 3), amount: -100, kind: .toPot, note: "", potID: vakantie.id, pairID: UUID()))
        let items = RecentActivity.items(in: d, asOf: today)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Bankrekening")
        XCTAssertEqual(items[0].destination, .bank)
    }
}
