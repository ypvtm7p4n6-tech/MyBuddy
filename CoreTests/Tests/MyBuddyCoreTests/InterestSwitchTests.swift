import XCTest
@testable import MyBuddyCore

/// Rente bij een uitbetaling op de 1e en bij het wisselen van uitbetaalritme of -dag.
/// Opgeslagen rente geldt als uitbetaald t/m de maand die ze meenam: niets wordt dubbel betaald en niets valt weg.
/// Alle verwachte bedragen zijn met de hand nagerekend.
final class InterestSwitchTests: XCTestCase {
    private let jun2027 = YearMonth(year: 2027, month: 6)
    private let dec2027 = YearMonth(year: 2027, month: 12)

    private func payments(_ d: FinanceData, _ pot: Pot, from: Date = day(aug2026, 1), to: Date) -> [InterestPayment] {
        d.interestPayments(for: pot.id, from: from, to: to, asOf: day(aug2026, 1))
    }

    private func cents(_ list: [InterestPayment]) -> [Int] {
        list.map { engCents($0.amount) }
    }

    // MARK: Uitbetaling op de 1e

    func testPayoutOnTheFirstPaysForThePreviousMonth() {
        let (d, pot) = engInterestData(payout: .monthly, payoutDay: 1)
        let list = payments(d, pot, to: day(engDec2026, 31))
        // Augustus: de pot begint pas, er is nog niets om rente over te betalen.
        XCTAssertEqual(list.map { YearMonth(date: $0.date) }, [sep2026, oct2026, engNov2026, engDec2026])
        XCTAssertEqual(list.map { engDayNumber($0.date) }, [1, 1, 1, 1])
        // 1 september: saldo van 1 augustus 1200 -> 2,00. 1 oktober: saldo van 1 september 1202,00 -> 2,0033 -> 2,00.
        // 1 november: saldo van 1 oktober 1204,00 -> 2,0067 -> 2,01. 1 december: 1206,01 -> 2,0100 -> 2,01.
        XCTAssertEqual(cents(list), [200, 200, 201, 201])
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(aug2026, 31)), 1_200, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(sep2026, 1)), 1_202, accuracy: 0.0001)
    }

    func testPayoutOnTheSecondCountsThatMonthItself() {
        let (d, pot) = engInterestData(payout: .monthly, payoutDay: 2)
        let list = payments(d, pot, to: day(sep2026, 30))
        XCTAssertEqual(list.map { YearMonth(date: $0.date) }, [aug2026, sep2026])
        XCTAssertEqual(cents(list), [200, 200])
    }

    func testFirstOfMonthPayoutOfAPotStartingThatMonthGivesNothingYet() {
        let (d, pot) = engInterestData(payout: .yearly, payoutDay: 1, payoutMonth: 8)
        // Elk jaar op 1 augustus. De pot begint op 1 augustus 2026: dan is er nog niets om rente over te betalen.
        // 1 augustus 2027: augustus 2026 t/m juli 2027 = 12 maanden x 1200 = 14400 x 2% / 12 = 24,00.
        let list = payments(d, pot, to: day(YearMonth(year: 2027, month: 12), 31))
        XCTAssertEqual(list.map { YearMonth(date: $0.date) }, [YearMonth(year: 2027, month: 8)])
        XCTAssertEqual(cents(list), [2_400])
    }

    // MARK: Ritme wisselen

    func testSwitchingFromMonthlyToYearlyNeverPaysTwice() {
        var (d, pot) = engInterestData(rate: 0.12, payout: .monthly, payoutDay: 28, opening: 1_000)
        // 12% per jaar = 1% per maand: augustus 10,00, september 10,10, oktober 10,20.
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 3)
        XCTAssertEqual(d.potEntries.filter { $0.kind == .interest }.map { engCents($0.amount) }.sorted(), [1_000, 1_010, 1_020])
        let balanceBefore = d.potBalance(pot.id, at: oct2026)
        XCTAssertEqual(balanceBefore, 1_030.30, accuracy: 0.0001)

        d.pots[0].interestPayout = .yearly
        d.pots[0].interestPayoutMonth = 1
        pot = d.pots[0]

        // Alleen november t/m januari: 3 x 1030,30 = 3090,90 x 1% = 30,91. De rente van augustus t/m oktober
        // is al uitbetaald en komt er niet nog een keer bij (dat zou 61,21 geven).
        let list = payments(d, pot, to: day(engJan2027, 31))
        XCTAssertEqual(list.map { YearMonth(date: $0.date) }, [engJan2027])
        XCTAssertEqual(cents(list), [3_091])
        XCTAssertEqual(list.first?.isProjected, true)

        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), balanceBefore, accuracy: 0.0001, "wisselen verandert het verleden niet")
        XCTAssertEqual(d.potBalance(pot.id, at: engDec2026), 1_030.30, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: engJan2027), 1_061.21, accuracy: 0.0001)

        XCTAssertEqual(d.applyDueInterest(upTo: day(engJan2027, 31)), 1)
        XCTAssertEqual(d.potEntries.first { $0.id == InterestRules.entryID(for: pot.id, month: engJan2027) }.map { engCents($0.amount) }, 3_091)
        XCTAssertEqual(d.potBalance(pot.id, at: engJan2027), 1_061.21, accuracy: 0.0001, "opslaan verandert niets")
    }

    func testSwitchingFromYearlyToMonthlyNeverPaysTwice() {
        var (d, pot) = engInterestData(rate: 0.12, payout: .yearly, payoutDay: 28, payoutMonth: 1, opening: 1_000)
        // Januari 2027: augustus t/m januari = 6 x 1000 x 1% = 60,00.
        XCTAssertEqual(d.applyDueInterest(upTo: day(engJan2027, 31)), 1)
        XCTAssertEqual(d.potBalance(pot.id, at: engDec2026), 1_000, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: engJan2027), 1_060, accuracy: 0.0001)

        d.pots[0].interestPayout = .monthly
        pot = d.pots[0]

        // De maanden augustus t/m december zitten al in de uitbetaling van januari en worden niet opnieuw berekend.
        let list = payments(d, pot, to: day(engJan2027, 31))
        XCTAssertEqual(list.map { YearMonth(date: $0.date) }, [engJan2027])
        XCTAssertEqual(cents(list), [6_000])
        XCTAssertEqual(list.first?.isProjected, false)
        XCTAssertEqual(d.applyDueInterest(upTo: day(engJan2027, 31)), 0)
        XCTAssertEqual(d.potBalance(pot.id, at: engDec2026), 1_000, accuracy: 0.0001)
        XCTAssertEqual(d.potBalance(pot.id, at: engJan2027), 1_060, accuracy: 0.0001)

        // Daarna gaat het maandelijks verder: februari = 1060 x 1% = 10,60.
        let next = d.nextInterestPayment(for: pot.id, asOf: day(engJan2027, 31))
        XCTAssertEqual(next.map { YearMonth(date: $0.date) }, engFeb2027)
        XCTAssertEqual(engCents(next?.amount ?? 0), 1_060)
    }

    func testChangingThePayoutDayLosesNoMonth() {
        var (d, pot) = engInterestData(payout: .monthly, payoutDay: 1)
        // Op de 1e: 1 september (rente over augustus) en 1 oktober (rente over september), elk 2,00.
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 2)
        d.pots[0].interestPayoutDay = 15
        pot = d.pots[0]

        // 15 november betaalt oktober én november: 2 x 1204,00 = 2408 x 2% / 12 = 4,01. 15 december: 1208,01 -> 2,01.
        let list = payments(d, pot, from: day(engNov2026, 1), to: day(engDec2026, 31))
        XCTAssertEqual(list.map { engDayNumber($0.date) }, [15, 15])
        XCTAssertEqual(cents(list), [401, 201])
    }

    func testManualInterestEntryCountsAsPaid() {
        var (d, pot) = engInterestData()
        d.potEntries.append(PotEntry(potID: pot.id, date: day(sep2026, 15), amount: 5, kind: .interest, note: "Van de bank"))
        pot = d.pots[0]
        // Wat de bank al betaalde (t/m september) rekent de app niet nog een keer uit. Oktober: saldo 1205 -> 2,01.
        let list = payments(d, pot, to: day(oct2026, 31))
        XCTAssertEqual(list.map { YearMonth(date: $0.date) }, [oct2026])
        XCTAssertEqual(cents(list), [201])
        XCTAssertEqual(d.applyDueInterest(upTo: day(oct2026, 31)), 1)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 1_207.01, accuracy: 0.0001)
    }

    func testInterestEntriesWithoutAmountDoNotCountAsPaid() {
        var (d, pot) = engInterestData()
        d.potEntries.append(PotEntry(potID: pot.id, date: day(sep2026, 15), amount: 0, kind: .interest))
        pot = d.pots[0]
        XCTAssertEqual(cents(payments(d, pot, to: day(oct2026, 31))), [200, 200, 201])
    }

    func testPaymentsDoNotDependOnHowFarWeLook() {
        // Opgeslagen rente van na de horizon bepaalt wat er vóór die horizon nog verwacht wordt, dus de
        // uitkomst voor een maand mag niet veranderen met `throughMonth`.
        var (d, pot) = engInterestData(rate: 0.12, payout: .yearly, payoutDay: 28, payoutMonth: 1, opening: 1_000)
        d.applyDueInterest(upTo: day(engJan2027, 31))
        d.pots[0].interestPayout = .monthly
        pot = d.pots[0]
        let full = d.potFlows(pot, throughMonth: dec2027).payments
        for last in [aug2026, oct2026, engDec2026, engJan2027, engFeb2027, jun2027] {
            let partial = d.potFlows(pot, throughMonth: last).payments
            XCTAssertEqual(partial, full.filter { YearMonth(date: $0.date) <= last }, "t/m \(last.key)")
        }
    }

    // MARK: Eigenschappen met willekeurige instellingen

    /// Willekeurig wisselen van ritme, dag, maand en percentage, tussendoor rente opslaan, handmatige rente toevoegen
    /// en een opgeslagen uitbetaling verwijderen. Opslaan verandert nooit een saldo en de uitkomst voor een maand
    /// hangt niet af van hoe ver we vooruit kijken.
    func testRandomSettingChangesKeepBalancesStable() {
        let rhythms = InterestPayout.allCases
        let months = aug2026.range(count: 30)
        for seed in UInt64(1)...60 {
            var r = EngRandom(seed: seed)
            var pot = Pot(name: "Spaar", monthlyContribution: r.chance(60) ? r.amount(0, 300) : 0, startMonth: aug2026)
            pot.interestRate = Double(r.int(5...80)) / 1_000
            pot.interestPayout = rhythms[r.int(0...3)]
            pot.interestPayoutDay = r.chance(40) ? 1 : r.int(1...31)
            pot.interestPayoutMonth = r.int(1...12)
            if r.chance(40) { pot.transferDay = r.int(1...31) }
            var d = FinanceData(startMonth: aug2026)
            d.addPot(pot, openingBalance: r.amount(0, 3_000), now: day(aug2026, r.int(1...28)))

            var cursor = aug2026
            for step in 0..<r.int(1...4) {
                cursor = cursor.adding(r.int(1...6))
                let before = months.map { engCents(d.potBalance(pot.id, at: $0)) }
                d.applyDueInterest(upTo: day(cursor, r.int(1...28)))
                let after = months.map { engCents(d.potBalance(pot.id, at: $0)) }
                XCTAssertEqual(before, after, "seed \(seed) stap \(step): opslaan verandert een saldo")

                if r.chance(80) { d.pots[0].interestPayout = rhythms[r.int(0...3)] }
                if r.chance(50) { d.pots[0].interestPayoutDay = r.chance(40) ? 1 : r.int(1...31) }
                if r.chance(50) { d.pots[0].interestPayoutMonth = r.int(1...12) }
                if r.chance(30) { d.pots[0].interestRate = Double(r.int(0...80)) / 1_000 }
                if r.chance(15) {
                    d.potEntries.append(PotEntry(potID: pot.id, date: day(cursor, r.int(1...28)), amount: r.amount(1, 20), kind: .interest))
                }
                if r.chance(10), let victim = d.potEntries.first(where: { $0.kind == .interest }) {
                    d.potEntries.removeAll { $0.id == victim.id }
                }

                let changed = d.pots[0]
                let full = d.potFlows(changed, throughMonth: months[months.count - 1]).payments
                for last in [aug2026.adding(2), aug2026.adding(7), aug2026.adding(13)] {
                    let partial = d.potFlows(changed, throughMonth: last).payments
                    XCTAssertEqual(partial, full.filter { YearMonth(date: $0.date) <= last }, "seed \(seed) stap \(step) t/m \(last.key)")
                }
            }
        }
    }

    // MARK: Eigenschap: niets dubbel, niets weg

    func testSwitchingTheRhythmNeverPaysTwiceNorLosesAMonth() {
        // 1000 euro, 12% per jaar (1% per maand), geen inleg. Elk ritme heeft december als uitbetaalmaand.
        let rhythms: [(InterestPayout, Int)] = [(.monthly, 1), (.quarterly, 12), (.halfYearly, 12), (.yearly, 12)]
        let switchDates = [day(oct2026, 31), day(engJan2027, 31), day(jun2027, 30)]
        for payoutDay in [1, 28] {
            // Betaald wordt over augustus 2026 t/m december 2027 (17 maanden); bij uitbetaling op de 1e t/m november (16).
            let months = payoutDay == 1 ? 16 : 17
            // Minimum: elke maand minstens 1000 x 1% = 10,00 (geen rente op rente).
            let lower = 1_000 * months
            // Maximum: elke maand uitbetaald, dus rente op rente. Onafhankelijk nagerekend in centen.
            var balance = 100_000
            for _ in 0..<months { balance += Int((Double(balance) * 0.01).rounded()) }
            let upper = balance - 100_000 + 10

            for from in rhythms {
                for to in rhythms {
                    for switchDate in switchDates {
                        var (d, pot) = engInterestData(rate: 0.12, payout: from.0, payoutDay: payoutDay,
                                                       payoutMonth: from.1, opening: 1_000)
                        d.applyDueInterest(upTo: switchDate)
                        d.pots[0].interestPayout = to.0
                        d.pots[0].interestPayoutMonth = to.1
                        pot = d.pots[0]
                        let end = day(dec2027, 31)
                        d.applyDueInterest(upTo: end)
                        let total = d.potEntries.filter { $0.kind == .interest }.reduce(0) { $0 + engCents($1.amount) }
                        let label = "dag \(payoutDay): \(from.0) -> \(to.0) na \(switchDate)"
                        XCTAssertGreaterThanOrEqual(total, lower, "rente valt weg, \(label)")
                        XCTAssertLessThanOrEqual(total, upper, "rente dubbel betaald, \(label)")
                        XCTAssertEqual(d.applyDueInterest(upTo: end), 0, label)
                        XCTAssertEqual(engCents(d.potBalance(pot.id, at: dec2027)), 100_000 + total, label)
                    }
                }
            }
        }
    }
}
