import XCTest
@testable import MyBuddyCore

/// Rente op spaarpotten. Rente per uitbetaling = rente / 12 × som van het saldo op de eerste dag van elke maand
/// in de periode: de maanden na de vorige uitbetaling t/m de laatste maand die de uitbetaling meeneemt (de
/// uitbetaalmaand zelf, maar bij uitbetaling op de 1e de maand ervoor), vanaf de startmaand van de pot.
/// Alle verwachte bedragen hieronder zijn met de hand nagerekend.
final class InterestTests: XCTestCase {
    private func list(_ d: FinanceData, _ pot: Pot, from: Date = day(aug2026, 1), to: Date) -> [InterestPayment] {
        d.interestPayments(for: pot.id, from: from, to: to, asOf: day(aug2026, 1))
    }

    private func amounts(_ payments: [InterestPayment]) -> [Int] {
        payments.map { engCents($0.amount) }
    }

    // MARK: Uitbetalingen

    func testMonthlyInterestFollowsTheBalanceAfterEarlierPayouts() {
        let (d, pot) = engInterestData()
        let payments = list(d, pot, to: day(oct2026, 31))
        // Augustus: 1200 x 2% / 12 = 2,00. September: saldo 1202,00 (met de rente van augustus) geeft 2,0033.
        // Oktober: saldo 1204,00 geeft 2,0067, dus 2,01.
        XCTAssertEqual(amounts(payments), [200, 200, 201])
        XCTAssertEqual(payments.map { engDayNumber($0.date) }, [28, 28, 28])
        XCTAssertEqual(payments.map { YearMonth(date: $0.date) }, [aug2026, sep2026, oct2026])
        XCTAssertTrue(payments.allSatisfy { $0.isProjected && $0.potID == pot.id })
        XCTAssertEqual(payments.map(\.id), ["interest-\(pot.id.uuidString)-2026-08", "interest-\(pot.id.uuidString)-2026-09",
                                            "interest-\(pot.id.uuidString)-2026-10"])
    }

    func testBalanceIncludesExpectedInterestFromItsPayoutDay() {
        let (d, pot) = engInterestData()
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(aug2026, 27)), 1_200, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(aug2026, 28)), 1_202, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: aug2026), 1_202, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: sep2026), 1_204, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1_206.01, accuracy: 0.0001)
        XCTAssertEqual(d.totalSaved(asOf: day(oct2026, 31)), 1_206.01, accuracy: 0.0001)
    }

    func testQuarterlyInterest() {
        let (d, pot) = engInterestData(payout: .quarterly, payoutDay: 15, payoutMonth: 3)
        // Uitbetaalmaanden: maart, juni, september, december.
        let payments = list(d, pot, to: day(engDec2026, 31))
        XCTAssertEqual(payments.map { YearMonth(date: $0.date) }, [sep2026, engDec2026])
        XCTAssertEqual(payments.map { engDayNumber($0.date) }, [15, 15])
        // September: periode juli-september, maar de pot begint in augustus: 1200 + 1200 = 2400 x 2% / 12 = 4,00.
        // December: oktober, november, december, steeds 1204,00: 3612 x 2% / 12 = 6,02.
        XCTAssertEqual(amounts(payments), [400, 602])
        XCTAssertEqual(d.potBalance(pot.id, at: engDec2026), 1_210.02, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1_204, accuracy: 0.0001)
    }

    func testYearlyInterestWithDefaultPayoutMonthAndDay() {
        let (d, pot) = engInterestData(payout: .yearly, payoutDay: 1, payoutMonth: 1)
        let payments = list(d, pot, to: day(engFeb2028, 28))
        XCTAssertEqual(payments.map { YearMonth(date: $0.date) }, [engJan2027, engJan2028])
        XCTAssertEqual(payments.map { engDayNumber($0.date) }, [1, 1])
        // Uitbetaling op de 1e betaalt de rente over de maanden ervoor.
        // 1 januari 2027: augustus t/m december = 5 maanden x 1200 = 6000 x 2% / 12 = 10,00.
        // 1 januari 2028: januari t/m december 2027 = 12 maanden x 1210 = 14520 x 2% / 12 = 24,20.
        XCTAssertEqual(amounts(payments), [1_000, 2_420])
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engJan2027, 1)), 1_210, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 31)), 1_200, accuracy: 0.0001)
    }

    func testYearlyPayoutInAnotherMonth() {
        let (d, pot) = engInterestData(payout: .yearly, payoutDay: 15, payoutMonth: 5)
        let payments = list(d, pot, to: day(YearMonth(year: 2027, month: 12), 31))
        XCTAssertEqual(payments.map { YearMonth(date: $0.date) }, [YearMonth(year: 2027, month: 5)])
        // Augustus t/m mei = 10 maanden x 1200 = 12000 x 2% / 12 = 20,00 op 15 mei.
        XCTAssertEqual(amounts(payments), [2_000])
        XCTAssertEqual(engDayNumber(payments[0].date), 15)
    }

    func testHalfYearlyInterest() {
        let (d, pot) = engInterestData(payout: .halfYearly, payoutDay: 10, payoutMonth: 2)
        // Uitbetaalmaanden: februari en augustus.
        let payments = list(d, pot, to: day(YearMonth(year: 2027, month: 9), 30))
        XCTAssertEqual(payments.map { YearMonth(date: $0.date) }, [aug2026, engFeb2027, YearMonth(year: 2027, month: 8)])
        // Augustus 2026: alleen de startmaand, 1200 -> 2,00. Februari: 6 x 1202 = 7212 -> 12,02.
        // Augustus 2027: 6 x 1214,02 = 7284,12 -> 12,1402 -> 12,14.
        XCTAssertEqual(amounts(payments), [200, 1_202, 1_214])
    }

    func testZeroAndNegativeRateGiveNothing() {
        for rate in [0.0, -0.02] {
            var d = engInterestData(rate: rate).data
            let pot = d.pots[0]
            XCTAssertTrue(list(d, pot, to: day(engJan2028, 31)).isEmpty)
            XCTAssertNil(d.nextInterestPayment(for: pot.id, asOf: day(sep2026, 1)))
            let before = d.potEntries
            XCTAssertEqual(d.applyDueInterest(upTo: day(engJan2028, 31)), 0)
            XCTAssertEqual(d.potEntries, before)
            XCTAssertEqual(d.potBalance(pot.id, at: engJan2028), 1_200, accuracy: 0.0001)
        }
    }

    func testPotStartingLaterGetsNoInterestBeforeItsStartMonth() {
        var d = engInterestData(start: engNov2026).data
        let pot = d.pots[0]
        let payments = list(d, pot, to: day(engDec2026, 31))
        XCTAssertEqual(payments.map { YearMonth(date: $0.date) }, [engNov2026, engDec2026])
        XCTAssertEqual(amounts(payments), [200, 200])
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 0, "nog niet begonnen")
        XCTAssertTrue(d.potEntries.allSatisfy { $0.kind != .interest })
        XCTAssertEqual(d.applyDueInterest(upTo: day(engDec2026, 31)), 2)
    }

    func testPayoutDayIsClampedToShortMonths() {
        let (d, pot) = engInterestData(payoutDay: 31)
        let payments = list(d, pot, to: day(engMar2027, 31))
        XCTAssertEqual(payments.map { YearMonth(date: $0.date) },
                       [aug2026, sep2026, oct2026, engNov2026, engDec2026, engJan2027, engFeb2027, engMar2027])
        XCTAssertEqual(payments.map { engDayNumber($0.date) }, [31, 30, 31, 30, 31, 31, 28, 31])
        let leap = list(d, pot, from: day(engFeb2028, 1), to: day(engFeb2028, 29))
        XCTAssertEqual(leap.map { engDayNumber($0.date) }, [29])
    }

    func testInterestOnAPotWithMonthlyAllocation() {
        // 12% per jaar = 1% per maand. Inleg 100 op de 10e, uitbetaling op de 28e.
        let (d, pot) = engInterestData(rate: 0.12, payoutDay: 28, opening: 1_000, monthly: 100, transferDay: 10)
        let payments = list(d, pot, to: day(oct2026, 31))
        // Augustus: eerste dag 1000 -> 10,00. September: 1000 + 100 + 10 = 1110 -> 11,10.
        // Oktober: 1110 + 100 + 11,10 = 1221,10 -> 12,211 -> 12,21.
        XCTAssertEqual(amounts(payments), [1_000, 1_110, 1_221])
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(aug2026, 27)), 1_100, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: aug2026), 1_110, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: sep2026), 1_221.10, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1_333.31, accuracy: 0.0001)
    }

    func testExpensesFromThePotLowerTheNextInterest() {
        var d = engInterestData().data
        let pot = d.pots[0]
        d.upsertLine(MoneyLine(name: "Fiets", amount: 200, day: 10, potShares: [PotShare(potID: pot.id, amount: 200)]),
                     kind: .expense, in: aug2026)
        let payments = list(d, pot, to: day(sep2026, 30))
        // Augustus: de uitgave volgt na de eerste dag, dus 2,00. September: (1200 - 200 + 2) = 1002 -> 1,67.
        XCTAssertEqual(amounts(payments), [200, 167])
        XCTAssertEqual(d.potBalance(pot.id, at: sep2026), 1_003.67, accuracy: 0.0001)
    }

    func testGoalMonthCountsExpectedInterest() {
        var d = engInterestData(rate: 0.12, opening: 1_000).data
        let pot = d.pots[0]
        d.pots[0].goalAmount = 1_100
        // Het saldo groeit met 1% per maand (afgerond): 1010,00, 1020,10, 1030,30, 1040,60, 1051,01, 1061,52, 1072,14,
        // 1082,86, 1093,69 en in mei 2027 1104,63.
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1_030.30, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: YearMonth(year: 2027, month: 4)), 1_093.69, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: YearMonth(year: 2027, month: 5)), 1_104.63, accuracy: 0.0001)
        XCTAssertEqual(d.potGoalMonth(pot.id, current: oct2026), YearMonth(year: 2027, month: 5))
        // Zonder rente wordt het doel nooit gehaald.
        d.pots[0].interestRate = 0
        XCTAssertNil(d.potGoalMonth(pot.id, current: oct2026))
    }

    // MARK: Opslaan

    func testApplyDueInterestStoresMissingPayoutsOnce() {
        var d = engInterestData().data
        let pot = d.pots[0]
        let expectedIDs = [aug2026, sep2026, oct2026].map { InterestRules.entryID(for: pot.id, month: $0) }
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 3)
        let stored = d.potEntries.filter { $0.kind == .interest }.sorted { $0.date < $1.date }
        XCTAssertEqual(stored.map(\.id), expectedIDs)
        XCTAssertEqual(stored.map { engCents($0.amount) }, [200, 200, 201])
        XCTAssertEqual(stored.map { engDayNumber($0.date) }, [28, 28, 28])
        XCTAssertTrue(stored.allSatisfy { $0.potID == pot.id && $0.note == "Rente 2% per jaar" })

        // Tweede keer: niets nieuws, niets verandert.
        let entries = d.potEntries
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 0)
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 15)), 0)
        XCTAssertEqual(d.potEntries, entries)
    }

    func testStoredAndExpectedInterestNeverCountTwice() {
        var d = engInterestData().data
        let pot = d.pots[0]
        let dates = [day(aug2026, 27), day(aug2026, 28), day(sep2026, 28), day(oct2026, 28), day(oct2026, 31), day(engJan2027, 5)]
        let before = dates.map { engCents(d.potBalance(pot.id, asOf: $0)) }
        let paymentsBefore = list(d, pot, to: day(oct2026, 31))
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 3)
        XCTAssertEqual(dates.map { engCents(d.potBalance(pot.id, asOf: $0)) }, before)
        // Dezelfde uitbetalingen met dezelfde id's, nu opgeslagen.
        let paymentsAfter = list(d, pot, to: day(oct2026, 31))
        XCTAssertEqual(paymentsAfter.map(\.id), paymentsBefore.map(\.id))
        XCTAssertEqual(paymentsAfter.map(\.amount), paymentsBefore.map(\.amount))
        XCTAssertTrue(paymentsBefore.allSatisfy { $0.isProjected })
        XCTAssertTrue(paymentsAfter.allSatisfy { !$0.isProjected })
    }

    func testApplyingInStepsGivesTheSameAsApplyingAtOnce() {
        let (original, pot) = engInterestData()
        var atOnce = original
        XCTAssertEqual(atOnce.applyDueInterest(upTo: day(oct2026, 31)), 3)

        var steps = original
        XCTAssertEqual(steps.applyDueInterest(upTo: day(sep2026, 15)), 1)
        XCTAssertEqual(steps.applyDueInterest(upTo: engTime(sep2026, 28, hour: 12)), 1, "op de dag zelf is de uitbetaling aan de beurt")
        XCTAssertEqual(steps.applyDueInterest(upTo: day(oct2026, 31)), 1)
        let key: (PotEntry) -> Date = { $0.date }
        XCTAssertEqual(atOnce.potEntries.sorted { key($0) < key($1) }, steps.potEntries.sorted { key($0) < key($1) })
        XCTAssertEqual(steps.potBalance(pot.id, at: oct2026), 1_206.01, accuracy: 0.0001)
    }

    func testTwoDevicesNeverMakeDoubleEntries() {
        let (original, pot) = engInterestData()
        var phone = original
        var mac = original
        phone.applyDueInterest(upTo: day(sep2026, 30))
        mac.applyDueInterest(upTo: day(oct2026, 31))
        // Samenvoegen op id: de uitbetalingen die beide apparaten boekten, zijn dezelfde boekingen.
        let phoneIDs = Set(phone.potEntries.map(\.id))
        let macIDs = Set(mac.potEntries.map(\.id))
        XCTAssertEqual(phoneIDs.count, 3, "beginsaldo + 2 uitbetalingen")
        XCTAssertTrue(phoneIDs.isSubset(of: macIDs))
        XCTAssertEqual(macIDs.count, 4)
        var merged = phone
        for entry in mac.potEntries where !phoneIDs.contains(entry.id) { merged.potEntries.append(entry) }
        XCTAssertEqual(merged.applyDueInterest(upTo: day(oct2026, 31)), 0, "alles is al geboekt")
        XCTAssertEqual(merged.potEntries.count, 4)
        XCTAssertEqual(merged.potBalance(pot.id, at: oct2026), 1_206.01, accuracy: 0.0001)
    }

    func testChangingTheRateKeepsStoredPayouts() {
        var d = engInterestData().data
        let pot = d.pots[0]
        d.applyDueInterest(upTo: day(oct2026, 31))
        d.pots[0].interestRate = 0.04
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 0)
        let payments = list(d, pot, to: day(engNov2026, 30))
        // Opgeslagen bedragen blijven; november (verwacht) gebruikt het nieuwe percentage:
        // 1206,01 x 4% / 12 = 4,0200 -> 4,02.
        XCTAssertEqual(amounts(payments), [200, 200, 201, 402])
        XCTAssertEqual(payments.map(\.isProjected), [false, false, false, true])
    }

    func testSwitchingInterestOffKeepsStoredEntriesInTheBalance() {
        var d = engInterestData().data
        let pot = d.pots[0]
        d.applyDueInterest(upTo: day(oct2026, 31))
        d.pots[0].interestRate = 0
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1_206.01, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: engDec2026), 1_206.01, accuracy: 0.0001, "geen nieuwe rente meer")
        XCTAssertTrue(list(d, pot, to: day(engDec2026, 31)).isEmpty)
        // De opgeslagen rente staat nog wel in het dagoverzicht en de geschiedenis.
        XCTAssertEqual(d.dayEvents(in: oct2026, asOf: day(oct2026, 1)).filter { $0.kind == .interest }.map(\.potAmount), [2.01])
        XCTAssertEqual(d.potTimeline(pot.id, current: oct2026).filter { $0.kind == .interest }.count, 3)
    }

    func testPotsWithoutInterestAreSkipped() {
        var d = engInterestData().data
        let plain = Pot(name: "Gewoon", monthlyContribution: 50, startMonth: aug2026)
        d.addPot(plain, openingBalance: 500, now: day(aug2026, 1))
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 3, "alleen de pot met rente")
        XCTAssertTrue(d.potEntries.filter { $0.potID == plain.id }.allSatisfy { $0.kind != .interest })
    }

    func testDeletingAPotRemovesItsInterest() {
        var d = engInterestData().data
        let pot = d.pots[0]
        d.applyDueInterest(upTo: day(oct2026, 31))
        d.deletePot(pot.id)
        XCTAssertTrue(d.potEntries.isEmpty)
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 0)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 0)
    }

    // MARK: Volgende uitbetaling

    func testNextInterestPayment() {
        var d = engInterestData().data
        let pot = d.pots[0]
        let early = d.nextInterestPayment(for: pot.id, asOf: day(aug2026, 10))
        XCTAssertEqual(engCents(early?.amount ?? 0), 200)
        XCTAssertEqual(early.map { YearMonth(date: $0.date) }, aug2026)
        XCTAssertEqual(early?.isProjected, true)
        // Op het moment van de uitbetaling zelf is de volgende die van september.
        let onTheDay = d.nextInterestPayment(for: pot.id, asOf: engTime(aug2026, 28, hour: 12))
        XCTAssertEqual(onTheDay.map { YearMonth(date: $0.date) }, sep2026)
        // Na opslaan: de volgende is november, met het saldo na alle opgeslagen rente (1206,01 -> 2,01).
        d.applyDueInterest(upTo: day(oct2026, 31))
        let afterStoring = d.nextInterestPayment(for: pot.id, asOf: day(oct2026, 31))
        XCTAssertEqual(afterStoring.map { YearMonth(date: $0.date) }, engNov2026)
        XCTAssertEqual(engCents(afterStoring?.amount ?? 0), 201)
        XCTAssertEqual(afterStoring?.isProjected, true)
        XCTAssertNil(d.nextInterestPayment(for: UUID(), asOf: day(oct2026, 31)))
    }

    func testNextYearlyPaymentIsMonthsAway() {
        let (d, pot) = engInterestData(payout: .yearly, payoutDay: 1, payoutMonth: 1)
        let next = d.nextInterestPayment(for: pot.id, asOf: day(oct2026, 8))
        XCTAssertEqual(next.map { YearMonth(date: $0.date) }, engJan2027)
        XCTAssertEqual(engCents(next?.amount ?? 0), 1_000, "augustus t/m december: 5 maanden x 1200 x 2% / 12")
    }

    // MARK: Dagoverzicht en geschiedenis

    func testInterestShowsInTheDayOverviewWithoutTouchingTheBank() {
        var d = engInterestData().data
        let pot = d.pots[0]
        d.addBankSnapshot(balance: 100, date: engTime(sep2026, 1, hour: 0.5))
        let before = d.dayEvents(in: sep2026, asOf: day(sep2026, 10))
        let interest = before.filter { $0.kind == .interest }
        XCTAssertEqual(interest.count, 1)
        XCTAssertEqual(interest.first?.potAmount, 2)
        XCTAssertEqual(interest.first?.bankAmount, 0)
        XCTAssertEqual(interest.first?.potID, pot.id)
        XCTAssertEqual(interest.first?.day, 28)
        XCTAssertEqual(interest.first?.isPlanned, true)
        XCTAssertEqual(interest.first?.title, "Rente Spaar")
        XCTAssertEqual(d.bankBalance(at: sep2026) ?? .nan, 100, accuracy: 0.0001, "rente raakt de bank niet")

        d.applyDueInterest(upTo: day(oct2026, 31))
        let after = d.dayEvents(in: sep2026, asOf: day(sep2026, 10))
        XCTAssertEqual(after.map(\.id), before.map(\.id), "opslaan dubbelt niets en houdt de id")
        XCTAssertEqual(after.filter { $0.kind == .interest }.count, 1)
    }

    func testTimelineShowsExpectedAndStoredInterest() {
        var d = engInterestData().data
        let pot = d.pots[0]
        let expected = d.potTimeline(pot.id, current: oct2026).filter { $0.kind == .interest }
        XCTAssertEqual(expected.count, 3)
        XCTAssertTrue(expected.allSatisfy { $0.note == "Verwacht" && $0.title == "Rente" })
        XCTAssertEqual(expected.map { engCents($0.amount) }, [201, 200, 200], "nieuwste eerst")

        d.applyDueInterest(upTo: day(oct2026, 31))
        let stored = d.potTimeline(pot.id, current: oct2026).filter { $0.kind == .interest }
        XCTAssertEqual(stored.map(\.id), expected.map(\.id), "dezelfde regels, niet verspringen")
        XCTAssertTrue(stored.allSatisfy { $0.note == "Rente 2% per jaar" })
        let all = d.potTimeline(pot.id, current: oct2026)
        XCTAssertEqual(all.map(\.date), all.map(\.date).sorted(by: >))
        XCTAssertEqual(all.filter { $0.kind == .manual }.count, 1, "beginsaldo")
    }

    func testTimelineLeavesOutInterestAfterTheCurrentMonth() {
        let (d, pot) = engInterestData()
        let upToSeptember = d.potTimeline(pot.id, current: sep2026).filter { $0.kind == .interest }
        XCTAssertEqual(upToSeptember.count, 2)
    }
}

// MARK: - Stabiele id's

final class StableIDTests: XCTestCase {
    func testSameTextGivesSameID() {
        XCTAssertEqual(StableID.uuid("interest|abc|2026-10"), StableID.uuid("interest|abc|2026-10"))
        XCTAssertNotEqual(StableID.uuid("interest|abc|2026-10"), StableID.uuid("interest|abc|2026-11"))
        XCTAssertNotEqual(StableID.uuid("interest|abc|2026-10"), StableID.uuid("interest|abd|2026-10"))
        XCTAssertNotEqual(StableID.uuid(""), StableID.uuid(" "))
    }

    func testIDLooksLikeAUUIDAndNeverChanges() {
        // Opgeslagen boekingen zijn aan deze id's te herkennen. Als dit test faalt, is de afleiding veranderd en
        // zouden bestaande rente-uitbetalingen opnieuw worden geboekt.
        XCTAssertEqual(StableID.uuid("interest|00000000-0000-0000-0000-000000000001|2026-10").uuidString,
                       "31277BFC-83E4-5A61-8548-FEF2A06ABFA7")
        let id = StableID.uuid("x")
        let text = id.uuidString
        XCTAssertEqual(text.count, 36)
        XCTAssertEqual(Array(text)[14], "5", "versie-cijfer")
        XCTAssertTrue(["8", "9", "A", "B"].contains(String(Array(text)[19])), "variant")
    }

    func testEntryIDsDependOnPotAndMonth() {
        let a = UUID()
        let b = UUID()
        XCTAssertEqual(InterestRules.entryID(for: a, month: oct2026), InterestRules.entryID(for: a, month: oct2026))
        XCTAssertNotEqual(InterestRules.entryID(for: a, month: oct2026), InterestRules.entryID(for: a, month: sep2026))
        XCTAssertNotEqual(InterestRules.entryID(for: a, month: oct2026), InterestRules.entryID(for: b, month: oct2026))
        XCTAssertEqual(InterestRules.paymentID(for: a, month: oct2026), "interest-\(a.uuidString)-2026-10")
    }

    func testManyIDsAreUnique() {
        let pot = UUID()
        let ids = Set(YearMonth(year: 2000, month: 1).range(count: 1_200).map { InterestRules.entryID(for: pot, month: $0) })
        XCTAssertEqual(ids.count, 1_200)
    }
}
