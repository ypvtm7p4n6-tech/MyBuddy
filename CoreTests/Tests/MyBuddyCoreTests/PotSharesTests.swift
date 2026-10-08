import XCTest
@testable import MyBuddyCore

/// Uitgaven die (deels) uit één of meer spaarpotten betaald worden, en de manier waarop die in de potgeschiedenis,
/// de opgeslagen gegevens en de voorbeelddata terugkomen.
final class PotSharesTests: XCTestCase {
    // MARK: Model

    func testLineSplitsBetweenPotsAndBank() {
        let a = UUID()
        let b = UUID()
        var line = MoneyLine(name: "Tandarts", amount: 300, potShares: [PotShare(potID: a, amount: 100), PotShare(potID: b, amount: 50)])
        XCTAssertEqual(line.fromPots, 150)
        XCTAssertEqual(line.fromBank, 150)
        line.potShares = [PotShare(potID: a, amount: 400)]
        XCTAssertEqual(line.fromPots, 300, "nooit meer dan het bedrag zelf")
        XCTAssertEqual(line.fromBank, 0)
        line.potShares = [PotShare(potID: a, amount: -20)]
        XCTAssertEqual(line.fromPots, 0, "nooit negatief")
        XCTAssertEqual([line, MoneyLine(name: "x", amount: 10, potShares: [PotShare(potID: a, amount: 4)])].totalFromPots, 4)
    }

    func testLineWithSharesSurvivesEncoding() throws {
        let share = PotShare(potID: UUID(), amount: 12.5)
        let line = MoneyLine(name: "Boodschappen", amount: 80, isRecurring: true, kind: .variable, day: 9, potShares: [share])
        let back = try JSONDecoder().decode(MoneyLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(back, line)
        XCTAssertEqual(back.day, 9)
        XCTAssertEqual(back.potShares, [share])
        let old = try JSONDecoder().decode(MoneyLine.self, from: Data(#"{"name":"Huur","amount":900,"isRecurring":true,"kind":"fixed"}"#.utf8))
        XCTAssertNil(old.day)
        XCTAssertTrue(old.potShares.isEmpty)
    }

    // MARK: Geschiedenis van de pot

    func testTimelineShowsExpensesFromThePot() {
        var (d, vakantie, buffer) = engTwoPotData()
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 300, day: 12,
                               potShares: [PotShare(potID: vakantie.id, amount: 100), PotShare(potID: buffer.id, amount: 50)]),
                     kind: .expense, in: oct2026)
        d.upsertLine(MoneyLine(name: "Fiets", amount: 200, day: 5, potShares: [PotShare(potID: vakantie.id, amount: 200)]),
                     kind: .expense, in: oct2026)

        let items = d.potTimeline(vakantie.id, current: oct2026)
        XCTAssertEqual(items.map(\.title), ["Tandarts", "Fiets", "Beginsaldo"])
        XCTAssertEqual(items.map(\.amount), [-100, -200, 400])
        XCTAssertEqual(items.map(\.kind), [.expense, .expense, .manual])
        XCTAssertEqual(items.map { engDayNumber($0.date) }, [12, 5, 1])
        XCTAssertEqual(items[0].note, "Uitgave betaald")
        XCTAssertTrue(items.prefix(2).allSatisfy { !$0.isMonthlyAllocation })
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)

        XCTAssertEqual(d.potTimeline(buffer.id, current: oct2026).map(\.amount), [-50, 900])
        // Het saldo is de som van de geschiedenis (geen inleg in deze potten).
        let sum = items.reduce(0) { $0 + engCents($1.amount) }
        XCTAssertEqual(sum, engCents(d.potBalance(vakantie.id, at: oct2026)))
        // Eerder dan oktober is er nog niets uitgegeven.
        XCTAssertEqual(d.potTimeline(vakantie.id, current: sep2026).map(\.title), ["Beginsaldo"])
    }

    func testTimelineMixesAllocationsEntriesAndExpensesNewestFirst() {
        var d = makeBaseData()
        var pot = Pot(name: "Buffer", monthlyContribution: 200, startMonth: aug2026)
        pot.transferDay = 10
        d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
        d.addPotEntry(potID: pot.id, amount: 50, kind: .deposit, note: "Cadeau", date: day(sep2026, 20))
        d.upsertLine(MoneyLine(name: "Reparatie", amount: 80, day: 15, potShares: [PotShare(potID: pot.id, amount: 80)]),
                     kind: .expense, in: sep2026)
        let items = d.potTimeline(pot.id, current: oct2026)
        XCTAssertEqual(items.map(\.kind), [.allocation, .manual, .expense, .allocation, .allocation, .manual])
        XCTAssertEqual(items.map(\.date), items.map(\.date).sorted(by: >))
        XCTAssertEqual(items.map(\.id).first, "alloc-2026-10")
        XCTAssertEqual(items.count, 6) // beginsaldo, cadeau, 3 maandverdelingen, 1 uitgave
        let sum = items.reduce(0) { $0 + engCents($1.amount) }
        XCTAssertEqual(sum, engCents(d.potBalance(pot.id, at: oct2026)))
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 500 + 600 + 50 - 80, accuracy: 0.001)
    }

    // MARK: Pot verwijderen

    func testDeletingAPotLetsTheBankPayItsShare() {
        var (d, vakantie, buffer) = engTwoPotData()
        let line = MoneyLine(name: "Tandarts", amount: 300, day: 12,
                             potShares: [PotShare(potID: vakantie.id, amount: 100), PotShare(potID: buffer.id, amount: 50)])
        d.upsertLine(line, kind: .expense, in: oct2026)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 150)
        d.deletePot(vakantie.id)
        let remainingLine = d.plan(for: oct2026).expenses.first { $0.id == line.id }
        XCTAssertEqual(remainingLine?.potShares.map(\.potID), [buffer.id])
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 50)
        XCTAssertEqual(d.expensesFromBank(in: oct2026), 1_250)
        let events = d.eventsOnDay(day(oct2026, 12), asOf: day(oct2026, 1))
        XCTAssertEqual(events.map(\.bankAmount), [-250, 0])
        XCTAssertEqual(events.reduce(0) { $0 + engCents($1.bankAmount + $1.potAmount) }, -30_000, "samen nog steeds het hele bedrag")
        d.deletePot(buffer.id)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 0)
        XCTAssertEqual(d.eventsOnDay(day(oct2026, 12), asOf: day(oct2026, 1)).map(\.bankAmount), [-300])
    }

    func testDeletingAPotOnlyTouchesLinesThatUseIt() {
        var (d, vakantie, buffer) = engTwoPotData()
        d.upsertLine(MoneyLine(name: "A", amount: 10, potShares: [PotShare(potID: buffer.id, amount: 10)]), kind: .expense, in: oct2026)
        d.upsertLine(MoneyLine(name: "B", amount: 20), kind: .expense, in: oct2026)
        let before = d.plan(for: oct2026).expenses
        d.deletePot(vakantie.id)
        XCTAssertEqual(d.plan(for: oct2026).expenses, before)
    }

    // MARK: Inkomsten

    func testIncomeIgnoresPotShares() {
        var (d, vakantie, _) = engTwoPotData()
        d.upsertLine(MoneyLine(name: "Bonus", amount: 500, day: 3, potShares: [PotShare(potID: vakantie.id, amount: 200)]),
                     kind: .income, in: oct2026)
        XCTAssertEqual(d.income(in: oct2026), 3_600)
        let events = d.eventsOnDay(day(oct2026, 3), asOf: day(oct2026, 1))
        XCTAssertEqual(events.map(\.bankAmount), [500])
        XCTAssertEqual(events.map(\.potAmount), [0])
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(oct2026, 4)), 400, accuracy: 0.001)
    }

    // MARK: Voorbeelddata

    func testSampleDataShowsTheNewFeatures() {
        let now = day(oct2026, 10)
        let d = FinanceData.sample(now: now)
        XCTAssertEqual(d.pots.count, 3)
        XCTAssertEqual(d.salary.payDay, 25)

        // Een spaarpot met 2% rente per jaar, uitbetaald op 1 januari.
        let withInterest = d.pots.filter { $0.interestRate > 0 }
        XCTAssertEqual(withInterest.count, 1)
        XCTAssertEqual(withInterest.first?.interestRate ?? 0, 0.02, accuracy: 0.000001)
        XCTAssertEqual(withInterest.first?.interestPayout, .yearly)
        XCTAssertEqual(withInterest.first?.interestPayoutMonth, 1)
        XCTAssertEqual(withInterest.first?.interestPayoutDay, 1)
        let next = d.nextInterestPayment(for: withInterest[0].id, asOf: now)
        XCTAssertEqual(next.map { YearMonth(date: $0.date) }, engJan2027)
        XCTAssertGreaterThan(next?.amount ?? 0, 0)

        // Een uitgave die deels uit een pot komt.
        let tandarts = d.plan(for: oct2026).expenses.first { $0.potShares.count == 1 }
        XCTAssertEqual(tandarts?.name, "Tandarts")
        XCTAssertEqual(tandarts?.fromPots ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(tandarts?.day, 12)
        XCTAssertEqual(tandarts?.potShares.first?.potID, withInterest.first?.id)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 100, accuracy: 0.001)

        // Dagen bij inkomsten en uitgaven.
        let events = d.dayEvents(in: oct2026, asOf: now)
        XCTAssertEqual(events.filter { $0.kind == .salary }.map(\.day), [25])
        XCTAssertEqual(events.filter { $0.kind == .income }.map(\.day), [20])
        XCTAssertEqual(Set(events.filter { $0.kind == .expense }.map(\.day)), [1, 3, 5, 8, 12, 18])
        XCTAssertEqual(events.filter { $0.kind == .toPot }.map(\.day).sorted(), [1, 25, 25])
        XCTAssertEqual(Set(events.map(\.id)).count, events.count)
    }

    func testSampleDataBankNeverDropsBelowZeroAndMatchesTheBudget() {
        let now = day(oct2026, 10)
        let d = FinanceData.sample(now: now)
        let start = oct2026.adding(-5)
        let low = d.lowestBankPoint(in: oct2026)
        XCTAssertGreaterThan(low?.balance ?? -1, 0)
        for m in start.range(count: 12) {
            let sum = d.dayEvents(in: m, asOf: now).filter { $0.kind != .bankEntry && $0.kind != .interest }
                .reduce(0) { $0 + engCents($1.bankAmount) }
            XCTAssertEqual(sum, engCents(d.remaining(in: m)), m.key)
        }
        // Rente zit niet in de bank en de pot-saldi lopen door.
        XCTAssertEqual(d.bankBalance(at: start.adding(-1)), nil)
        XCTAssertNotNil(d.bankBalance(at: start))
    }

    func testSampleDataBacksUpAndLoadsAgain() throws {
        let now = day(oct2026, 10)
        let original = FinanceData.sample(now: now)
        let back = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(back, original)
        XCTAssertEqual(back.remaining(in: oct2026), original.remaining(in: oct2026))
        XCTAssertEqual(back.dayEvents(in: oct2026, asOf: now), original.dayEvents(in: oct2026, asOf: now))
    }

    func testSampleInterestIsBookedWhenItIsDue() {
        // Een voorbeeld van februari 2027: de rente van 1 januari is al aan de beurt en staat in de geschiedenis.
        let now = day(engFeb2027, 10)
        let d = FinanceData.sample(now: now)
        let buffer = d.pots.first { $0.interestRate > 0 }!
        let booked = d.potEntries.filter { $0.potID == buffer.id && $0.kind == .interest }
        XCTAssertEqual(booked.count, 1)
        XCTAssertEqual(YearMonth(date: booked[0].date), engJan2027)
        XCTAssertGreaterThan(booked[0].amount, 0)
        var again = d
        XCTAssertEqual(again.applyDueInterest(upTo: now), 0)
    }
}
