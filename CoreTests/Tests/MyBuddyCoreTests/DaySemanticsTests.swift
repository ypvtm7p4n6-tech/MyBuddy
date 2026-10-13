import XCTest
@testable import MyBuddyCore

/// De dagsemantiek van de hele rekenmotor: alles gebeurt per KALENDERDAG. Een geplande boeking op dag D telt voor
/// "vandaag" mee zodra D <= vandaag (de hele dag, ook voor 12:00); `isPlanned` betekent: de dag ligt na vandaag.
/// Handmatige boekingen (BankEntry, PotEntry) houden hun eigen tijdstip; een ingevuld banksaldo geldt als saldo aan
/// het EIND van die dag. Alle momenten zijn vast; niets hangt van de klok af.
final class DaySemanticsTests: XCTestCase {
    // MARK: Rente

    func testInterestOfTodayCountsTheWholeDay() {
        // 2% per jaar, elke maand op de 28e, beginsaldo 1200 op 1 augustus: 1200 x 2% / 12 = 2,00 op 28 augustus (12:00).
        let (d, pot) = engInterestData()
        let morning = engTime(aug2026, 28, hour: 8)
        let eveningBefore = engTime(aug2026, 27, hour: 23.9)

        // De dag ervoor is er nog niets aan de beurt; op de ochtend van de dag zelf wel.
        var early = d
        XCTAssertEqual(early.applyDueInterest(upTo: eveningBefore), 0)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: aug2026, today: eveningBefore), 1_200, accuracy: 0.001)
        XCTAssertEqual(d.totalSaved(current: aug2026, today: eveningBefore), 1_200, accuracy: 0.001)
        XCTAssertEqual(d.nextInterestPayment(for: pot.id, asOf: eveningBefore).map { DayMath.dayNumber(of: $0.date) }, 28)

        XCTAssertEqual(d.potBalanceNow(pot.id, current: aug2026, today: morning), 1_202, accuracy: 0.001)
        XCTAssertEqual(d.totalSaved(current: aug2026, today: morning), 1_202, accuracy: 0.001)
        XCTAssertEqual(d.nextInterestPayment(for: pot.id, asOf: morning).map { YearMonth(date: $0.date) }, sep2026,
                       "een uitbetaling van vandaag is al ontvangen")
        let events = d.dayEvents(in: aug2026, asOf: morning).filter { $0.kind == .interest }
        XCTAssertEqual(events.map(\.day), [28])
        XCTAssertEqual(events.map(\.isPlanned), [false])
        XCTAssertEqual(d.dayEvents(in: aug2026, asOf: eveningBefore).filter { $0.kind == .interest }.map(\.isPlanned), [true])

        // Boeken: de ochtend van de uitbetaaldag boekt de rente, en het saldo van nu blijft precies hetzelfde.
        var booked = d
        XCTAssertEqual(booked.applyDueInterest(upTo: morning), 1)
        XCTAssertEqual(booked.applyDueInterest(upTo: morning), 0, "tweede keer: niets nieuws")
        XCTAssertEqual(booked.potBalanceNow(pot.id, current: aug2026, today: morning), 1_202, accuracy: 0.001)
        XCTAssertEqual(booked.dayTotals(on: morning, asOf: morning).potsTotal, 1_202, accuracy: 0.001)
        XCTAssertEqual(booked.dayTotals(on: morning, asOf: morning).interest, 2, accuracy: 0.001)
        XCTAssertEqual(booked.potTimeline(pot.id, current: aug2026, asOf: morning).filter { !$0.isPlanned }
            .reduce(0) { $0 + engCents($1.amount) }, 120_200)
    }

    // MARK: Het doel start vanaf het saldo van vandaag

    func testGoalStartIsTheBalanceOfTheEndOfToday() {
        var d = FinanceData(startMonth: oct2026)
        var pot = Pot(name: "Vakantie", goalAmount: 1_000, monthlyContribution: 200, startMonth: oct2026)
        pot.transferDay = 8
        d.addPot(pot, openingBalance: 100, now: day(oct2026, 1))
        var goal = LifeGoal(name: "Vakantie", kind: .vacation)
        goal.targetAmount = 1_000
        goal.funding = .pot(pot.id)

        // Op de ochtend van de overschrijfdag staat de inleg er al in; de avond ervoor nog niet.
        let morning = engTime(oct2026, 8, hour: 7.5)
        let eveningBefore = engTime(oct2026, 7, hour: 23.9)
        XCTAssertEqual(d.goalInputs(for: goal, current: oct2026, today: morning).start, 300, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: goal, current: oct2026, today: morning).monthly, 200, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: goal, current: oct2026, today: eveningBefore).start, 100, accuracy: 0.001)
        XCTAssertEqual(d.goalInputs(for: goal, current: oct2026, today: morning).start,
                       d.dayTotals(on: morning, asOf: morning).potsTotal, accuracy: 0.001)
    }

    // MARK: Saldo van nu = saldo aan het eind van vandaag

    /// Salaris 3000 op de 25e, snapshot 1000 op de 20e om 09:00. Een storting van 50 om 15:00 op de 25e.
    private func paydayData() -> FinanceData {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.addBankSnapshot(balance: 1_000, note: "Meting", date: engTime(engNov2026, 20, hour: 9))
        d.addBankEntry(amount: 50, note: "Storting", date: engTime(engNov2026, 25, hour: 15))
        return d
    }

    func testBalanceNowOnPaydayMorningIsTheEndOfTheDayWithoutLaterManualEntries() {
        let d = paydayData()
        let morning = engTime(engNov2026, 25, hour: 7)
        // Het salaris van de 25e telt de hele dag, dus al om 07:00. De storting van 15:00 is er nog niet.
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: morning), 4_000)
        XCTAssertEqual(d.netWorthNow(current: engNov2026, today: morning).bank, 4_000)
        XCTAssertEqual(d.bankBalance(atMoment: morning), 4_000)
        // Het eind van de dag (het dagboek) heeft de storting wel.
        let ledger = d.monthLedger(engNov2026, asOf: morning)
        XCTAssertEqual(ledger.days[24].bankBalance, 4_050)
        XCTAssertTrue(ledger.days[24].isToday)
        XCTAssertFalse(ledger.days[24].isPlanned)
        XCTAssertTrue(ledger.days[24].events.allSatisfy { !$0.isPlanned })
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: engTime(engNov2026, 25, hour: 15)), 4_050)
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: engTime(engNov2026, 25, hour: 23.9)), 4_050)
        XCTAssertEqual(d.bankBalance(on: morning), 4_050)
        // De dag ervoor (ook 23:59) is er nog geen salaris.
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: engTime(engNov2026, 24, hour: 23.9)), 1_000)
        XCTAssertFalse(ledger.days[24].isPlanned)
        XCTAssertTrue(ledger.days[25].isPlanned, "alleen dagen na vandaag zijn gepland")
    }

    func testManualEntriesKeepTheirOwnMomentInPotsToo() {
        var d = FinanceData(startMonth: engNov2026)
        var pot = Pot(name: "Spaar", monthlyContribution: 100, startMonth: engNov2026)
        pot.transferDay = 10
        d.addPot(pot, openingBalance: 0, now: engTime(engNov2026, 1, hour: 8))
        d.addPotEntry(potID: pot.id, amount: 25, kind: .deposit, note: "Los", date: engTime(engNov2026, 10, hour: 15))
        // Om 10:00 op de 10e: de inleg van de 10e telt (hele dag), de storting van 15:00 nog niet.
        XCTAssertEqual(d.potBalanceNow(pot.id, current: engNov2026, today: engTime(engNov2026, 10, hour: 10)), 100, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: engNov2026, today: engTime(engNov2026, 10, hour: 15)), 125, accuracy: 0.001)
        // Het eind van de dag heeft alles.
        XCTAssertEqual(d.potBalance(pot.id, asOf: engTime(engNov2026, 10, hour: 1)), 125, accuracy: 0.001)
        XCTAssertEqual(d.dayTotals(on: engTime(engNov2026, 10, hour: 1), asOf: engTime(engNov2026, 10, hour: 10)).potsTotal,
                       125, accuracy: 0.001)
        // Een dag eerder is er niets.
        XCTAssertEqual(d.potBalanceNow(pot.id, current: engNov2026, today: engTime(engNov2026, 9, hour: 23.9)), 0, accuracy: 0.001)
    }

    // MARK: Gepland = de dag ligt na vandaag

    func testPlannedIsDecidedPerCalendarDayAcrossTheMonthBoundary() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 0, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.upsertLine(MoneyLine(name: "Huur", amount: 900, isRecurring: true, day: 1), kind: .expense, in: oct2026)
        d.upsertLine(MoneyLine(name: "Laatste", amount: 10, isRecurring: true, day: 31), kind: .expense, in: oct2026)
        let lastMoment = engTime(oct2026, 31, hour: 23.99)
        // Op 31 oktober om 23:59 is alles in oktober gebeurd en alles in november gepland (de uitgave van de 31e valt in
        // november, een maand van 30 dagen, op de 30e).
        let october = d.dayEvents(in: oct2026, asOf: lastMoment)
        XCTAssertEqual(october.map(\.day), [1, 31])
        XCTAssertEqual(october.map(\.isPlanned), [false, false])
        XCTAssertEqual(d.dayEvents(in: engNov2026, asOf: lastMoment).map(\.day), [1, 30])
        XCTAssertTrue(d.dayEvents(in: engNov2026, asOf: lastMoment).allSatisfy(\.isPlanned))
        // Een seconde later is het 1 november: de huur van de 1e is gebeurd, de laatste van november nog niet.
        let midnight = engTime(engNov2026, 1, hour: 0)
        let november = d.dayEvents(in: engNov2026, asOf: midnight)
        XCTAssertEqual(november.map(\.isPlanned), [false, true])
        XCTAssertEqual(DayMath.isPlanned(day(engNov2026, 1), asOf: midnight), false)
        XCTAssertEqual(DayMath.isPlanned(day(engNov2026, 2), asOf: midnight), true)
        XCTAssertEqual(DayMath.isPlanned(day(engNov2026, 1), asOf: lastMoment), true)
        // Het dagboek zegt hetzelfde.
        let ledger = d.monthLedger(engNov2026, asOf: midnight)
        XCTAssertEqual(ledger.days.filter { $0.isToday }.map(\.day), [1])
        XCTAssertEqual(ledger.days.filter { !$0.isPlanned }.map(\.day), [1])
        let before = d.monthLedger(oct2026, asOf: midnight)
        XCTAssertTrue(before.days.allSatisfy { !$0.isPlanned && !$0.isToday })
    }
}
