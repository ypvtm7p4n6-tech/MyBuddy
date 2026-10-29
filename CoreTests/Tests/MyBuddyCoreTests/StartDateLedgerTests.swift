import XCTest
import Foundation
@testable import MyBuddyCore

/// Handmatige gegevens en saldi met een startdatum (docs/work/plan.md par. 2.1, R2 en R4, en B7): boekingen en ingevulde saldi van
/// vóór het begin van de startdag tellen niet mee en blijven bewaard; vóór de startdag is het banksaldo onbekend en zijn de potten
/// leeg; een beginsaldo is een ingevuld saldo en `.opening`-boekingen op de startdag; rente begint pas met de eerste maand na de start.
final class StartDateLedgerTests: XCTestCase {
    private let nov2026 = YearMonth(year: 2026, month: 11)

    private func emptyData() -> FinanceData {
        FinanceData(startMonth: oct2026)
    }

    private func potData(_ name: String = "Spaar") -> (data: FinanceData, pot: Pot) {
        var d = emptyData()
        let pot = Pot(name: name, monthlyContribution: 0, startMonth: oct2026)
        d.pots = [pot]
        return (d, pot)
    }

    // MARK: Het banksaldo

    func testABankSnapshotBeforeTheStartDayDoesNotCountAndComesBack() {
        var d = emptyData()
        d.addBankSnapshot(balance: 1_000, note: "Oud", date: startMoment(oct2026, 5))
        d.addBankEntry(amount: 50, note: "Storting", date: startMoment(oct2026, 8))
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 1_050)
        XCTAssertTrue(d.hasBankBalance)

        d.setStart(startOct(15))
        XCTAssertNil(d.bankBalance(on: startMoment(oct2026, 20)), "het saldo van de 5e telt niet meer mee")
        XCTAssertNil(d.bankBalance(at: oct2026))
        XCTAssertFalse(d.hasBankBalance)
        XCTAssertTrue(d.sortedBankSnapshots.isEmpty)
        XCTAssertEqual(d.bankSnapshots.count, 1, "het blijft bewaard")
        XCTAssertEqual(d.bankEntries.count, 1)

        // Een saldo op de startdag zelf telt wel, ook als het ver voor 12:00 is ingevuld.
        d.addBankSnapshot(balance: 300, note: "Begin", date: startMoment(oct2026, 15, hour: 8))
        XCTAssertNil(d.bankBalance(on: startMoment(oct2026, 14)), "vóór de startdag onbekend")
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 15)), 300)
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 300)

        // Een eerdere startdatum brengt het oude saldo en de storting terug.
        d.setStart(startOct(1))
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 10)), 1_050)
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 300)
    }

    func testBankEntriesBeforeTheStartDayDoNotCountWhenThereIsNoSnapshot() {
        var d = emptyData()
        d.addBankEntry(amount: 80, note: "Voor", date: startMoment(oct2026, 3))
        d.addBankEntry(amount: -30, note: "Na", date: startMoment(oct2026, 18))
        d.setStart(startOct(15))
        // De eerste boeking die meetelt is de basis (een virtuele 0 ervoor): 0 - 30.
        XCTAssertNil(d.bankBalance(on: startMoment(oct2026, 14)))
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), -30)
        XCTAssertEqual(d.bankEntryEvents(in: oct2026).map { $0.title }, ["Na"])
        d.setStart(startOct(1))
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 50)
        XCTAssertEqual(d.bankEntryEvents(in: oct2026).count, 2)
    }

    func testTheBankBalanceIsUnknownBeforeTheStartDayAndKnownFromTheSnapshot() {
        var d = startBaseData()
        d.setStart(startOct(15))
        XCTAssertNil(d.bankBalance(on: startMoment(oct2026, 10)))
        d.addBankSnapshot(balance: 2_000, note: "Beginsaldo", date: startMoment(oct2026, 15, hour: 13))
        XCTAssertNil(d.bankBalance(on: startMoment(oct2026, 14)))
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 15)), 2_000)
        // Het salaris, de bijverdienste (de 25e) tellen erbij, net als altijd.
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 25)), 2_000 + 3_000 + 200 + 120)
        let ledger = d.monthLedger(oct2026, asOf: startMoment(oct2026, 28))
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertNil(ledger.openingBank)
        XCTAssertNil(ledger.days[13].bankBalance, "14 oktober")
        XCTAssertEqual(ledger.days[14].bankBalance, 2_000, "15 oktober")
        XCTAssertEqual(ledger.closingBank, d.bankBalance(at: oct2026))
    }

    func testTheOpeningBankOfTheMonthAfterTheStartMonthIsKnown() {
        var d = startBaseData()
        d.setStart(startOct(15))
        d.addBankSnapshot(balance: 2_000, note: "Beginsaldo", date: startMoment(oct2026, 15, hour: 13))
        let november = d.monthLedger(nov2026, asOf: startMoment(oct2026, 28))
        XCTAssertNotNil(november.openingBank)
        XCTAssertEqual(november.openingBank, d.monthLedger(oct2026, asOf: startMoment(oct2026, 28)).closingBank)
        XCTAssertTrue(november.allReconciles)
    }

    // MARK: De spaarpotten

    func testPotEntriesBeforeTheStartDayDoNotCountAndPotsAreEmpty() {
        var d = emptyData()
        let pot = Pot(name: "Spaar", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot, openingBalance: 500, now: startMoment(oct2026, 2))
        d.addPotEntry(potID: pot.id, amount: 100, kind: .deposit, date: startMoment(oct2026, 12))
        d.addPotEntry(potID: pot.id, amount: 25, kind: .deposit, date: startMoment(oct2026, 16))
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 20)), 625, "alles telt zonder startdatum")

        d.setStart(startOct(15))
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 20)), 25)
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 14)), 0, "vóór de startdag is de pot leeg")
        XCTAssertEqual(d.totalSaved(asOf: startMoment(oct2026, 14)), 0)
        XCTAssertEqual(d.potEntries.count, 3, "het blijft bewaard")
        XCTAssertEqual(d.potTimeline(pot.id, current: oct2026, asOf: startMoment(oct2026, 20)).map { $0.amount }, [25])
        let ledger = d.monthLedger(oct2026, asOf: startMoment(oct2026, 28))
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertEqual(ledger.openingPots, 0)
        XCTAssertEqual(ledger.closingPots, 25)

        d.setStart(startOct(1))
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 20)), 625)
    }

    func testTheOpeningBalanceOfANewPotMovesToTheStartDay() {
        var d = emptyData()
        d.setStart(startOct(15))
        let pot = Pot(name: "Nieuw", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot, openingBalance: 400, now: startMoment(oct2026, 3))
        let entry = d.potEntries[0]
        XCTAssertEqual(entry.kind, .opening)
        XCTAssertEqual(entry.date, YearMonth.calendar.startOfDay(for: startMoment(oct2026, 15)), "het begin van de startdag")
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 14)), 0)
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 15)), 400)
        XCTAssertEqual(d.countedPotEntries.count, 1)

        // Na de startdag blijft het moment zoals het was.
        let later = Pot(name: "Later", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(later, openingBalance: 60, now: startMoment(oct2026, 20, hour: 9))
        XCTAssertEqual(d.potEntries[1].date, startMoment(oct2026, 20, hour: 9))
    }

    func testTheOpeningBalanceOfANewPotIsUnchangedWithoutAStartDate() {
        var d = emptyData()
        let when = startMoment(oct2026, 3, hour: 17)
        d.addPot(Pot(name: "Nieuw", monthlyContribution: 0, startMonth: oct2026), openingBalance: 400, now: when)
        XCTAssertEqual(d.potEntries[0].date, when)
    }

    func testTransferPairsAreHiddenTogether() {
        var (d, pot) = potData()
        d.transferBankToPot(potID: pot.id, amount: 70, date: startMoment(oct2026, 4))
        d.transferBankToPot(potID: pot.id, amount: 30, date: startMoment(oct2026, 18))
        d.setStart(startOct(15))
        XCTAssertEqual(d.countedBankEntries.count, 1)
        XCTAssertEqual(d.countedPotEntries.count, 1)
        XCTAssertEqual(d.countedBankEntries[0].pairID, d.countedPotEntries[0].pairID)
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 20)), 30)
    }

    // MARK: Een beginsaldo

    private func openingData() -> (data: FinanceData, a: Pot, b: Pot) {
        var d = emptyData()
        var a = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: oct2026)
        a.transferDay = 20
        let b = Pot(name: "Buffer", monthlyContribution: 0, startMonth: oct2026)
        d.pots = [a, b]
        d.setStart(startOct(20))
        return (d, a, b)
    }

    func testOpeningBalancesSetTheBalancesAtTheEndOfTheStartDay() {
        var (d, a, b) = openingData()
        let now = startMoment(oct2026, 22)
        d.setOpeningBalances(on: startOct(20), bank: 1_000, pots: [a.id: 600, b.id: 50], now: now)
        // De bank: een ingevuld saldo op de startdag, met de geplande boekingen van die dag erin (de inleg van 100).
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 1_000)
        XCTAssertEqual(d.bankSnapshots.filter { $0.note == "Beginsaldo" }.count, 1)
        XCTAssertNil(d.bankBalance(on: startMoment(oct2026, 19)))
        // De potten: het saldo aan het eind van de startdag, met de inleg van die dag erin (100 van de 600).
        XCTAssertEqual(d.potBalance(a.id, asOf: startMoment(oct2026, 20)), 600)
        XCTAssertEqual(d.potBalance(b.id, asOf: startMoment(oct2026, 20)), 50)
        XCTAssertEqual(d.potBalance(a.id, asOf: startMoment(oct2026, 19)), 0)
        let openings = d.potEntries.filter { $0.kind == .opening }
        XCTAssertEqual(openings.count, 2)
        XCTAssertEqual(openings.first { $0.potID == a.id }?.amount, 500, "600 min de inleg van die dag")
        XCTAssertEqual(openings.first { $0.potID == b.id }?.amount, 50)
        XCTAssertTrue(d.monthLedger(oct2026, asOf: now).allReconciles)
    }

    func testOpeningBalancesAreIdempotentAndReplaceWhatWasThere() {
        var (d, a, b) = openingData()
        let now = startMoment(oct2026, 22)
        d.setOpeningBalances(on: startOct(20), bank: 1_000, pots: [a.id: 600, b.id: 50], now: now)
        let once = d
        d.setOpeningBalances(on: startOct(20), bank: 1_000, pots: [a.id: 600, b.id: 50], now: now)
        XCTAssertEqual(d.bankSnapshots.count, once.bankSnapshots.count)
        XCTAssertEqual(d.potEntries.count, once.potEntries.count)
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 1_000)
        XCTAssertEqual(d.potBalance(a.id, asOf: startMoment(oct2026, 25)), 600)

        // Andere waarden vervangen de oude, ze komen er niet bij.
        d.setOpeningBalances(on: startOct(20), bank: 1_200, pots: [a.id: 100, b.id: 80], now: now)
        XCTAssertEqual(d.bankSnapshots.filter { $0.note == "Beginsaldo" }.count, 1)
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 1_200)
        XCTAssertEqual(d.potBalance(a.id, asOf: startMoment(oct2026, 20)), 100)
        XCTAssertEqual(d.potBalance(b.id, asOf: startMoment(oct2026, 20)), 80)
        XCTAssertEqual(d.potEntries.filter { $0.kind == .opening }.count, 1,
                       "voor Vakantie is er geen verschil meer met de inleg van die dag: geen boeking")
    }

    func testOpeningBalancesLeaveWhatYouDoNotMentionAlone() {
        var (d, a, b) = openingData()
        let now = startMoment(oct2026, 22)
        d.setOpeningBalances(on: startOct(20), bank: 700, pots: [b.id: 40], now: now)
        d.setOpeningBalances(on: startOct(20), bank: nil, pots: [a.id: 300], now: now)
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 20)), 700, "de bank bleef zoals hij was")
        XCTAssertEqual(d.potBalance(b.id, asOf: startMoment(oct2026, 20)), 40, "Buffer ook")
        XCTAssertEqual(d.potBalance(a.id, asOf: startMoment(oct2026, 20)), 300)
        // Een pot die niet bestaat doet niets.
        let before = d.potEntries.count
        d.setOpeningBalances(on: startOct(20), bank: nil, pots: [UUID(): 999], now: now)
        XCTAssertEqual(d.potEntries.count, before)
    }

    func testTheOpeningBalanceOnlyReplacesTheBeginsaldoOfThatDay() {
        var (d, a, _) = openingData()
        let now = startMoment(oct2026, 25)
        d.addBankSnapshot(balance: 111, note: "Zelf ingevuld", date: startMoment(oct2026, 21))
        d.addPotEntry(potID: a.id, amount: 15, kind: .deposit, note: "Storting", date: startMoment(oct2026, 21))
        d.setOpeningBalances(on: startOct(20), bank: 500, pots: [a.id: 100], now: now)
        d.setOpeningBalances(on: startOct(20), bank: 520, pots: [a.id: 100], now: now)
        XCTAssertEqual(d.bankSnapshots.filter { $0.note == "Zelf ingevuld" }.count, 1)
        XCTAssertEqual(d.potEntries.filter { $0.kind == .deposit }.count, 1)
        XCTAssertEqual(d.bankSnapshots.filter { $0.note == "Beginsaldo" }.count, 1)
    }

    func testTheOpeningMoment() {
        let cal = YearMonth.calendar
        let day = startOct(10)
        let dayStart = cal.startOfDay(for: day.date())
        let nextStart = DayMath.nextDayStart(after: dayStart, calendar: cal)
        // Een dag in het verleden: het laatste moment van die dag.
        let past = FinanceData.openingMoment(on: day, now: startMoment(oct2026, 20))
        XCTAssertEqual(CalendarDay(date: past, calendar: cal), day)
        XCTAssertLessThan(past, nextStart)
        XCTAssertGreaterThanOrEqual(past, nextStart.addingTimeInterval(-1))
        // Vandaag: nu.
        let now = startMoment(oct2026, 10, hour: 9)
        XCTAssertEqual(FinanceData.openingMoment(on: day, now: now), now)
        // Een dag in de toekomst: het begin van die dag.
        XCTAssertEqual(FinanceData.openingMoment(on: day, now: startMoment(oct2026, 2)), dayStart)
    }

    func testAnOpeningBalanceOnTheStartDayIsKnownTheSameDay() {
        var d = emptyData()
        d.setStart(startOct(10))
        let now = startMoment(oct2026, 10, hour: 9)
        d.setOpeningBalances(on: startOct(10), bank: 700, pots: [:], now: now)
        XCTAssertEqual(d.bankBalanceNowIfKnown(current: oct2026, today: now), 700, "meteen bekend, ook voor 12:00")
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: startMoment(oct2026, 11)), 700)
    }

    func testAnOpeningBalanceForAFutureStartDayAppearsWhenTheDayStarts() {
        var d = emptyData()
        d.setStart(startOct(20))
        let now = startMoment(oct2026, 12)
        d.setOpeningBalances(on: startOct(20), bank: 900, pots: [:], now: now)
        XCTAssertNil(d.bankBalanceNowIfKnown(current: oct2026, today: now), "nog niet begonnen: onbekend")
        XCTAssertEqual(d.bankBalanceNowIfKnown(current: oct2026, today: startMoment(oct2026, 20, hour: 0)) ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: startMoment(oct2026, 22)), 900)
    }

    // MARK: Rente

    private func interestData(rate: Double = 0.12) -> (data: FinanceData, pot: Pot) {
        var d = emptyData()
        var pot = Pot(name: "Rente", monthlyContribution: 0, startMonth: oct2026)
        pot.interestRate = rate
        pot.interestPayout = .monthly
        pot.interestPayoutDay = 28
        d.addPot(pot, openingBalance: 1_200, now: startMoment(oct2026, 1))
        return (d, pot)
    }

    func testInterestStartsWithTheFirstMonthAfterAMidMonthStart() {
        var (d, pot) = interestData()
        // De beginboeking van de 1e telt niet meer; het beginsaldo op de startdag vervangt haar.
        d.setStart(startOct(15))
        d.setOpeningBalances(on: startOct(15), bank: nil, pots: [pot.id: 1_200], now: startMoment(oct2026, 20))
        let payments = d.interestPayments(for: pot.id, from: oct2026.firstDay, to: startMoment(nov2026, 30), asOf: startMoment(oct2026, 20))
        // Oktober: het saldo op de 1e is 0, dus geen rente. November: 1.200 x 12% / 12 = 12 op de 28e.
        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(CalendarDay(date: payments[0].date), CalendarDay(year: 2026, month: 11, day: 28))
        XCTAssertEqual(payments[0].amount, 12, accuracy: 0.0001)
    }

    func testInterestOfAStartOnTheFirstCountsTheStartMonth() {
        var (d, pot) = interestData()
        d.setStart(startOct(1))
        let payments = d.interestPayments(for: pot.id, from: oct2026.firstDay, to: startMoment(nov2026, 30), asOf: startMoment(oct2026, 20))
        XCTAssertEqual(payments.map { CalendarDay(date: $0.date).day }, [28, 28])
        XCTAssertEqual(payments[0].amount, 12, accuracy: 0.0001)
        XCTAssertEqual(payments[1].amount, 12.12, accuracy: 0.0001, "rente op rente: het saldo is dan 1.212")
    }

    func testApplyDueInterestBooksNothingBeforeTheStartDay() {
        var (d, pot) = interestData()
        d.setStart(startOct(15))
        d.setOpeningBalances(on: startOct(15), bank: nil, pots: [pot.id: 1_200], now: startMoment(oct2026, 20))
        XCTAssertEqual(d.applyDueInterest(upTo: startMoment(oct2026, 30)), 0, "oktober: het saldo op de 1e was 0")
        XCTAssertEqual(d.applyDueInterest(upTo: startMoment(nov2026, 30)), 1)
        let interest = d.potEntries.filter { $0.kind == .interest }
        XCTAssertEqual(interest.count, 1)
        XCTAssertEqual(CalendarDay(date: interest[0].date), CalendarDay(year: 2026, month: 11, day: 28))
        XCTAssertEqual(d.applyDueInterest(upTo: startMoment(nov2026, 30)), 0, "nogmaals aanroepen boekt niets dubbel")
        XCTAssertTrue(d.monthLedger(nov2026, asOf: startMoment(nov2026, 30)).allReconciles)
    }

    func testStoredInterestBeforeTheStartDayDoesNotCount() {
        var (d, pot) = interestData()
        d.applyDueInterest(upTo: startMoment(oct2026, 30))
        let stored = d.potEntries.filter { $0.kind == .interest }
        XCTAssertEqual(stored.count, 1)
        d.setStart(startOct(29))
        XCTAssertEqual(d.countedPotEntries.filter { $0.kind == .interest }.count, 0, "de rente van de 28e valt voor de startdag")
        XCTAssertEqual(d.potBalance(pot.id, asOf: startMoment(oct2026, 30)), 0)
        let stats = PotInterestStats.received(in: d, potID: pot.id, asOf: startMoment(oct2026, 30))
        XCTAssertEqual(stats.total, 0)
        let context = PotHistoryContext(pot: pot, data: d, through: oct2026)
        XCTAssertTrue(context.storedInterest.isEmpty)
        XCTAssertTrue(d.monthLedger(oct2026, asOf: startMoment(oct2026, 30)).allReconciles)
        // Een eerdere startdatum brengt de rente terug.
        d.setStart(startOct(1))
        XCTAssertEqual(PotInterestStats.received(in: d, potID: pot.id, asOf: startMoment(oct2026, 30)).total, stored[0].amount)
    }

    // MARK: Lijsten

    func testRecentActivityAndHistoryListsOnlyShowWhatCounts() {
        var (d, pot) = potData()
        d.addBankEntry(amount: 40, note: "Voor", date: startMoment(oct2026, 3))
        d.addBankEntry(amount: 60, note: "Na", date: startMoment(oct2026, 18))
        d.addBankSnapshot(balance: 10, note: "Oud saldo", date: startMoment(oct2026, 4))
        d.addBankSnapshot(balance: 20, note: "Nieuw saldo", date: startMoment(oct2026, 19))
        d.addPotEntry(potID: pot.id, amount: 15, kind: .deposit, note: "Pot voor", date: startMoment(oct2026, 5))
        d.addPotEntry(potID: pot.id, amount: 25, kind: .deposit, note: "Pot na", date: startMoment(oct2026, 21))
        let asOf = startMoment(oct2026, 28)
        XCTAssertEqual(RecentActivity.items(in: d, asOf: asOf, limit: 10).count, 4)
        XCTAssertEqual(BankHistoryItem.items(from: d).count, 4)
        d.setStart(startOct(15))
        let recent = RecentActivity.items(in: d, asOf: asOf, limit: 10)
        XCTAssertEqual(recent.map { $0.amount }.sorted(), [25, 60])
        let history = BankHistoryItem.items(from: d)
        XCTAssertEqual(history.map { $0.detail }.sorted(), ["Na", "Nieuw saldo"])
        XCTAssertEqual(d.hiddenBankCount, 2)
        XCTAssertEqual(d.hiddenPotCount(for: pot.id), 1)
    }

    func testTheMonthLedgerOfTheStartMonthHidesEarlierDays() {
        var (d, pot) = potData()
        d.addPotEntry(potID: pot.id, amount: 100, kind: .deposit, date: startMoment(oct2026, 4))
        d.addBankEntry(amount: 10, date: startMoment(oct2026, 4))
        d.setStart(startOct(15))
        let ledger = d.monthLedger(oct2026, asOf: startMoment(oct2026, 28))
        XCTAssertEqual(ledger.manualInflow, 0)
        XCTAssertEqual(ledger.potEntriesNet, 0)
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertEqual(ledger.days[3].hasActivity, false, "4 oktober ligt voor de start")
    }
}
