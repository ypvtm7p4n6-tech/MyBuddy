import XCTest
@testable import MyBuddyCore

/// Een saldo invullen op een dag met geplande boekingen. Planboekingen (salaris, inkomsten, uitgaven, inleg: ze staan
/// op 12:00) op dezelfde kalenderdag als het meetpunt gelden als al verwerkt. Handmatige bankboekingen houden hun
/// eigen tijdstip. De spaarpotten veranderen niet. Alle momenten zijn vast; niets hangt van de klok af.
/// (November en december: op 25 oktober verzet de klok in Europa, en dan is "12:00 plus 12,1 uur" geen 12:01 meer.)
final class BankSnapshotDayTests: XCTestCase {
    /// Salaris 3000 op de 25e (de standaard salarisdag), geen uitgaven.
    private func salaryData() -> FinanceData {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        return d
    }

    // MARK: Het voorbeeld uit de bevinding

    func testSnapshotOnPayDayMorningNeverCountsTheSalaryTwice() {
        var d = salaryData()
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))

        let beforeNoon = engTime(engNov2026, 25, hour: 11 + 59.0 / 60)
        let afterNoon = engTime(engNov2026, 25, hour: 12 + 1.0 / 60)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 8.5)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: beforeNoon) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: afterNoon) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: beforeNoon), 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: afterNoon), 3_500, accuracy: 0.001)
        // Eind van de dag, en het eind van de maand.
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: engNov2026) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: day(engDec2026, 3)), 3_500, accuracy: 0.001)
        // De dag erna blijft het 3500.
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 26)) ?? .nan, 3_500, accuracy: 0.001)
    }

    func testTheFollowingBookingsCountAgainFromTheNextDay() {
        var d = salaryData()
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))
        // Het volgende salaris, op 25 december om 12:00, telt wel mee.
        XCTAssertEqual(d.bankBalance(on: day(engDec2026, 24)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engDec2026, 25, hour: 11.9)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engDec2026, 25, hour: 12.1)) ?? .nan, 6_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engDec2026, 25)) ?? .nan, 6_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: engDec2026) ?? .nan, 6_500, accuracy: 0.001)
        // En een boeking van de dag direct na het meetpunt (de huur van de 26e) ook.
        d.upsertLine(MoneyLine(name: "Abonnement", amount: 40, day: 26), kind: .expense, in: engNov2026)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 26)) ?? .nan, 3_460, accuracy: 0.001)
    }

    // MARK: Alle soorten planboekingen

    func testAllKindsOfPlannedEventsOnTheDayAreAlreadyIn() {
        var d = salaryData()
        d.upsertLine(MoneyLine(name: "Huur", amount: 1_000, day: 25), kind: .expense, in: engNov2026)
        d.upsertLine(MoneyLine(name: "Teruggave", amount: 250, day: 25), kind: .income, in: engNov2026)
        let pot = Pot(name: "Spaar", monthlyContribution: 300, startMonth: engNov2026)
        d.addPot(pot)
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))
        // Het plan heeft die dag salaris, huur, inkomsten en inleg, maar de bank blijft op het ingevulde saldo.
        XCTAssertEqual(d.eventsOnDay(day(engNov2026, 25)).filter { $0.bankAmount != 0 }.count, 4)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 12.5)) ?? .nan, 3_500, accuracy: 0.001)
        // De pot kent geen meetpunt: zijn inleg telt vanaf 12:00 (de potkant verandert niet).
        XCTAssertEqual(d.potBalance(pot.id, atMoment: engTime(engNov2026, 25, hour: 8.5)), 0, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, atMoment: engTime(engNov2026, 25, hour: 12.5)), 300, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engNov2026, 25)), 300, accuracy: 0.001)
        // De volgende maand komen het salaris en de inleg weer (huur en teruggave zijn eenmalig): 3500 + 3000 - 300.
        XCTAssertEqual(d.bankBalance(at: engDec2026) ?? .nan, 3_500 + 3_000 - 300, accuracy: 0.001)
    }

    func testPlannedEventsEarlierThatDayAreAlreadyInToo() {
        // Meetpunt 's avonds, na het salaris van 12:00: ook dan niets dubbel (en niets gemist).
        var d = salaryData()
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 18))
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 31)) ?? .nan, 3_500, accuracy: 0.001)
    }

    // MARK: Handmatige boekingen houden hun eigen tijdstip

    func testManualEntriesKeepTheirOwnMoment() {
        var d = salaryData()
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))
        d.addBankEntry(amount: 999, note: "Voor het meetpunt", date: engTime(engNov2026, 25, hour: 7))
        d.addBankEntry(amount: 200, note: "Na het meetpunt", date: engTime(engNov2026, 25, hour: 10))
        // Wat voor het meetmoment valt zit al in het saldo, wat erna valt telt mee.
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 9)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 11 + 59.0 / 60)) ?? .nan, 3_700, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 12 + 1.0 / 60)) ?? .nan, 3_700, accuracy: 0.001,
                       "het salaris van 12:00 komt er niet nog eens bij")
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_700, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 26)) ?? .nan, 3_700, accuracy: 0.001)
    }

    func testManualEntryAfterTheSnapshotCountsEvenWhenItIsLateThatDay() {
        var d = salaryData()
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))
        d.addBankEntry(amount: -80, note: "Boodschappen", date: engTime(engNov2026, 25, hour: 20))
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 19)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_420, accuracy: 0.001)
    }

    func testTransferToPotIsAManualEntryAndKeepsItsMoment() {
        var d = salaryData()
        let pot = Pot(name: "Spaar", monthlyContribution: 0, startMonth: engNov2026)
        d.addPot(pot)
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))
        d.transferBankToPot(potID: pot.id, amount: 500, date: engTime(engNov2026, 25, hour: 15))
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 14)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_000, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engNov2026, 25)), 500, accuracy: 0.001)
    }

    // MARK: Meetpunt op een andere dag

    func testSnapshotTheDayBeforeStillCountsThePlannedEventsOfTheNextDay() {
        var d = salaryData()
        d.addBankSnapshot(balance: 500, date: engTime(engNov2026, 24, hour: 23.9))
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 24)) ?? .nan, 500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 11.9)) ?? .nan, 500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 12.1)) ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_500, accuracy: 0.001)
    }

    func testNewestSnapshotOfTheDayWins() {
        var d = salaryData()
        d.addBankSnapshot(balance: 1_000, date: engTime(engNov2026, 25, hour: 7))
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_500, accuracy: 0.001)
        // Vóór het tweede meetpunt geldt het eerste (ook zonder het salaris van 12:00).
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 8)) ?? .nan, 1_000, accuracy: 0.001)
    }

    // MARK: Zonder meetpunt verandert er niets

    func testWithoutASnapshotTheVirtualZeroStillCountsLaterPlannedEventsOfThatDay() {
        // Geen ingevuld saldo, alleen een storting om 08:30: er is niets gemeten, dus niets is "al verwerkt".
        var d = salaryData()
        d.addBankEntry(amount: 100, note: "Storting", date: engTime(engNov2026, 25, hour: 8.5))
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 11.9)) ?? .nan, 100, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 25, hour: 12.1)) ?? .nan, 3_100, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 25)) ?? .nan, 3_100, accuracy: 0.001)
    }

    // MARK: Dagreeks en maandreeks

    func testDailySeriesAndMonthSeriesFollowTheSameRule() {
        var d = salaryData()
        d.addBankSnapshot(balance: 3_500, date: engTime(engNov2026, 25, hour: 8.5))
        let series = d.bankDailySeries(from: day(engNov2026, 24), to: day(engDec2026, 26), asOf: day(engNov2026, 25))
        XCTAssertEqual(series.first?.date, engNov2026.date(day: 25), "pas vanaf de dag van het meetpunt")
        for point in series {
            XCTAssertEqual(d.bankBalance(on: point.date) ?? .nan, point.balance, accuracy: 0.001, "\(point.date)")
        }
        XCTAssertEqual(series.first { YearMonth(date: $0.date) == engNov2026 && engDayNumber($0.date) == 25 }?.balance ?? .nan, 3_500, accuracy: 0.001)
        XCTAssertEqual(series.last?.balance ?? .nan, 6_500, accuracy: 0.001)
        let months = d.bankSeries(from: engNov2026, count: 2, current: engNov2026)
        XCTAssertEqual(months.map(\.balance), [3_500, 6_500])
        XCTAssertEqual(d.lowestBankPoint(in: engNov2026)?.balance ?? .nan, 3_500, accuracy: 0.001)
    }
}
