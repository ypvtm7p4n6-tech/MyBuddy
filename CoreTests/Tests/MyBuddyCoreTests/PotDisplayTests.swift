import XCTest
@testable import MyBuddyCore

/// Tests voor de hulpjes van de spaarpot-pagina's (PotFormat, PotInterestStats, PotHistoryContext).
/// Verwachte bedragen zijn met de hand nagerekend: rente per maand = rente / 12 × saldo op de 1e van de maand.
final class PotDisplayTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(PotFormat.longDate(day(engJan2027, 1)), "1 januari 2027")
        XCTAssertEqual(PotFormat.dayName(25), "de 25e")
        XCTAssertEqual(PotFormat.list(["a"]), "a")
        XCTAssertEqual(PotFormat.list(["a", "b"]), "a en b")
        XCTAssertEqual(PotFormat.list(["a", "b", "c"]), "a, b en c")
        XCTAssertEqual(PotFormat.list([]), "")
        XCTAssertEqual(PotFormat.monthName(1), "januari")
        XCTAssertEqual(PotFormat.monthName(12), "december")
        XCTAssertEqual(PotFormat.monthName(99), "december")
        XCTAssertEqual(PotFormat.monthName(-3), "januari")
        // Onder de 10 euro met centen, daarboven hele euro's.
        XCTAssertEqual(PotFormat.interest(4.37), Fmt.euroExact(4.37))
        XCTAssertTrue(PotFormat.interest(4.37).contains("4,37"))
        XCTAssertTrue(PotFormat.interest(0.4).contains("0,40"))
        XCTAssertEqual(PotFormat.interest(12.4), Fmt.euro(12))
        XCTAssertEqual(PotFormat.interest(0), Fmt.euro(0))
        XCTAssertFalse(PotFormat.interest(0).contains(","))
        XCTAssertTrue(PotFormat.interest(-3.5).contains("3,50"))
    }

    func testSigned() {
        XCTAssertEqual(PotFormat.signed(120), "+" + Fmt.euro(120))
        XCTAssertEqual(PotFormat.signed(-30), Fmt.euro(-30))
        XCTAssertFalse(PotFormat.signed(-30).hasPrefix("+"))
        // Een verschil dat op nul afrondt krijgt geen teken.
        XCTAssertEqual(PotFormat.signed(0), Fmt.euro(0))
        XCTAssertEqual(PotFormat.signed(0.3), Fmt.euro(0))
        XCTAssertEqual(PotFormat.signed(-0.3), Fmt.euro(0))
        XCTAssertFalse(PotFormat.signed(0.3).contains("+"))
        XCTAssertFalse(PotFormat.signed(-0.3).contains("-"))
        // Vanaf een halve euro telt het mee.
        XCTAssertEqual(PotFormat.signed(0.5), "+" + Fmt.euro(0.5))
    }

    func testPayoutMonths() {
        XCTAssertEqual(PotFormat.payoutMonths(.monthly, firstMonth: 5), Array(1...12))
        XCTAssertEqual(PotFormat.payoutMonths(.quarterly, firstMonth: 1), [1, 4, 7, 10])
        XCTAssertEqual(PotFormat.payoutMonths(.quarterly, firstMonth: 3), [3, 6, 9, 12])
        XCTAssertEqual(PotFormat.payoutMonths(.quarterly, firstMonth: 2), [2, 5, 8, 11])
        XCTAssertEqual(PotFormat.payoutMonths(.halfYearly, firstMonth: 4), [4, 10])
        XCTAssertEqual(PotFormat.payoutMonths(.halfYearly, firstMonth: 9), [3, 9])
        XCTAssertEqual(PotFormat.payoutMonths(.yearly, firstMonth: 7), [7])
        XCTAssertEqual(PotFormat.payoutMonths(.yearly, firstMonth: 0), [1])
    }

    /// De UI-lijst met uitbetaalmaanden moet gelijk zijn aan wat de rekenmotor doet.
    func testPayoutMonthsMatchEngine() {
        for payout in InterestPayout.allCases {
            for first in 1...12 {
                var (d, _) = engInterestData(payout: payout, payoutDay: 10, payoutMonth: first, start: YearMonth(year: 2026, month: 1))
                d.startMonth = YearMonth(year: 2026, month: 1)
                let months = d.interestPayoutMonths(for: d.pots[0], through: YearMonth(year: 2026, month: 12)).map { $0.month }
                XCTAssertEqual(months, PotFormat.payoutMonths(payout, firstMonth: first), "\(payout) \(first)")
            }
        }
    }

    func testFirstMonthStaysInsideTheRhythm() {
        // Elk kwartaal: eerste uitbetaling van het jaar is januari t/m maart.
        XCTAssertEqual((1...12).map { PotFormat.firstMonth($0, for: .quarterly) }, [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3])
        // Elk half jaar: januari t/m juni.
        XCTAssertEqual((1...12).map { PotFormat.firstMonth($0, for: .halfYearly) }, [1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6])
        // Elk jaar: elke maand blijft zoals hij is.
        XCTAssertEqual((1...12).map { PotFormat.firstMonth($0, for: .yearly) }, Array(1...12))
        // Maandelijks maakt de maand niet uit; alleen begrensd op 1...12.
        XCTAssertEqual(PotFormat.firstMonth(7, for: .monthly), 7)
        XCTAssertEqual(PotFormat.firstMonth(0, for: .monthly), 1)
        XCTAssertEqual(PotFormat.firstMonth(99, for: .monthly), 12)
        XCTAssertEqual(PotFormat.firstMonth(-4, for: .quarterly), 1)
        // November bij jaarlijks wordt februari bij kwartaal: dezelfde maanden als de oude keuze erbij (feb, mei, aug, nov).
        XCTAssertEqual(PotFormat.firstMonth(11, for: .quarterly), 2)
        XCTAssertTrue(PotFormat.payoutMonths(.quarterly, firstMonth: 2).contains(11))
    }

    /// Normaliseren verandert de uitbetalingen niet: dezelfde maanden, in de UI en in de rekenmotor.
    func testNormalizingKeepsTheSchedule() {
        for payout in InterestPayout.allCases {
            for month in 1...12 {
                let normalized = PotFormat.firstMonth(month, for: payout)
                XCTAssertEqual(PotFormat.payoutMonths(payout, firstMonth: normalized),
                               PotFormat.payoutMonths(payout, firstMonth: month), "\(payout) \(month)")
            }
        }
    }

    func testFirstMonthChoices() {
        XCTAssertEqual(PotFormat.firstMonthChoices(for: .monthly), 1...1)
        XCTAssertEqual(PotFormat.firstMonthChoices(for: .quarterly), 1...3)
        XCTAssertEqual(PotFormat.firstMonthChoices(for: .halfYearly), 1...6)
        XCTAssertEqual(PotFormat.firstMonthChoices(for: .yearly), 1...12)
        // Elke keuze is een ander schema, en samen dekken ze alle mogelijkheden.
        for payout in [InterestPayout.quarterly, .halfYearly, .yearly] {
            let schedules = PotFormat.firstMonthChoices(for: payout).map { PotFormat.payoutMonths(payout, firstMonth: $0) }
            XCTAssertEqual(Set(schedules).count, schedules.count, "\(payout)")
            XCTAssertEqual(Set(schedules.flatMap { $0 }), Set(1...12), "\(payout)")
        }
    }

    func testSchedule() {
        XCTAssertEqual(PotFormat.schedule(.monthly, firstMonth: 1, day: 25), "Je krijgt elke maand rente, op de 25e.")
        XCTAssertEqual(PotFormat.schedule(.quarterly, firstMonth: 1, day: 1), "Je krijgt rente in januari, april, juli en oktober, op de 1e.")
        XCTAssertEqual(PotFormat.schedule(.halfYearly, firstMonth: 3, day: 15), "Je krijgt rente in maart en september, op de 15e.")
        XCTAssertEqual(PotFormat.schedule(.yearly, firstMonth: 12, day: 31),
                       "Je krijgt rente in december, op de 31e. Heeft een maand die dag niet, dan is het de laatste dag van die maand.")
    }

    func testNextPaymentText() {
        let id = UUID()
        let projected = InterestPayment(potID: id, date: day(engJan2027, 1), amount: 12, isProjected: true, id: "x")
        XCTAssertEqual(PotFormat.nextPayment(projected), "1 januari 2027, ongeveer " + Fmt.euro(12))
        var fixed = projected
        fixed.isProjected = false
        XCTAssertEqual(PotFormat.nextPayment(fixed), "1 januari 2027, " + Fmt.euro(12))
        var small = projected
        small.amount = 4.37
        XCTAssertEqual(PotFormat.nextPayment(small), "1 januari 2027, ongeveer " + Fmt.euroExact(4.37))
    }

    // MARK: Ontvangen rente

    /// 2% per jaar, maandelijks op de 28e, beginsaldo 1200 op 1 augustus 2026.
    /// Aug: 1200 × 0,02 / 12 = 2,00. Sep: 1202,00 → 2,0033 = 2,00. Okt: 1204,00 → 2,0067 = 2,01.
    /// Nov: 1206,01 → 2,0100 = 2,01. Dec: 1208,02 → 2,0134 = 2,01. Jan: 1210,03 → 2,0167 = 2,02.
    func testReceivedInterest() {
        let (d0, pot) = engInterestData()
        var d = d0
        let today = day(oct2026, 10)

        // Niets opgeslagen: de twee uitbetalingen die al aan de beurt waren (28 aug, 28 sep) tellen toch mee.
        var r = PotInterestStats.received(in: d, potID: pot.id, asOf: today)
        XCTAssertEqual(engCents(r.total), 400)
        XCTAssertEqual(engCents(r.thisYear), 400)

        // Na opslaan geeft het hetzelfde (geen dubbele telling).
        XCTAssertEqual(d.applyDueInterest(upTo: today), 2)
        r = PotInterestStats.received(in: d, potID: pot.id, asOf: today)
        XCTAssertEqual(engCents(r.total), 400)
        XCTAssertEqual(engCents(r.thisYear), 400)

        // Zonder pot-id telt het alle potten: hier is dat dezelfde ene pot.
        r = PotInterestStats.received(in: d, asOf: today)
        XCTAssertEqual(engCents(r.total), 400)

        // Op 28 oktober na 12:00 komt de derde erbij: 2,00 + 2,00 + 2,01.
        r = PotInterestStats.received(in: d, potID: pot.id, asOf: day(oct2026, 28))
        XCTAssertEqual(engCents(r.total), 601)

        // Half februari 2027: aug t/m jan is 2,00 + 2,00 + 2,01 + 2,01 + 2,01 + 2,02 = 12,05; "dit jaar" is alleen januari.
        r = PotInterestStats.received(in: d, potID: pot.id, asOf: day(engFeb2027, 15))
        XCTAssertEqual(engCents(r.total), 1205)
        XCTAssertEqual(engCents(r.thisYear), 202)

        // Een andere pot telt niet mee.
        r = PotInterestStats.received(in: d, potID: UUID(), asOf: day(oct2026, 28))
        XCTAssertEqual(r, PotInterestReceived(total: 0, thisYear: 0))
    }

    func testReceivedInterestAddsUpAllPots() {
        var (d, first) = engInterestData()
        var second = Pot(name: "Tweede", monthlyContribution: 0, startMonth: aug2026)
        second.interestRate = 0.012
        second.interestPayout = .monthly
        second.interestPayoutDay = 28
        d.addPot(second, openingBalance: 2_400, now: day(aug2026, 1))
        // Tweede pot: 2400 × 0,012 / 12 = 2,40 (aug) en 2402,40 → 2,4024 = 2,40 (sep).
        let today = day(oct2026, 10)
        let one = PotInterestStats.received(in: d, potID: first.id, asOf: today)
        let two = PotInterestStats.received(in: d, potID: second.id, asOf: today)
        let all = PotInterestStats.received(in: d, asOf: today)
        XCTAssertEqual(engCents(one.total), 400)
        XCTAssertEqual(engCents(two.total), 480)
        XCTAssertEqual(engCents(all.total), 880)
    }

    func testNoInterestPotHasNothing() {
        let (d, _) = engInterestData(rate: 0)
        let r = PotInterestStats.received(in: d, asOf: day(oct2026, 10))
        XCTAssertEqual(r, PotInterestReceived(total: 0, thisYear: 0))
    }

    // MARK: Bewaren: eerst de oude rente vastleggen

    /// De volgorde van het bewerkblad: eerst bijschrijven wat al aan de beurt was (oude instellingen), dan wijzigen, dan weer bijschrijven.
    /// Aug en sep staan dan vast op 2,00 en 2,00 (2%); oktober rekent met 4%: 1204,00 × 0,04 / 12 = 4,01.
    func testChangingTheRateKeepsDuePaymentsAtTheOldRate() {
        var (d, pot) = engInterestData()
        let today = day(oct2026, 10)
        pot.interestRate = 0.04

        var fixed = d
        fixed.applyDueInterest(upTo: today)
        fixed.updatePot(pot, current: oct2026)
        fixed.applyDueInterest(upTo: today)
        let stored = fixed.potEntries.filter { $0.kind == .interest }.sorted { $0.date < $1.date }.map { engCents($0.amount) }
        XCTAssertEqual(stored, [200, 200])
        let next = fixed.nextInterestPayment(for: pot.id, asOf: today)
        XCTAssertEqual(engCents(next?.amount ?? 0), 401)
        XCTAssertEqual(next?.isProjected, true)

        // De oude volgorde (eerst wijzigen, dan bijschrijven) rekende het verleden met het nieuwe percentage.
        d.updatePot(pot, current: oct2026)
        d.applyDueInterest(upTo: today)
        let wrong = d.potEntries.filter { $0.kind == .interest }.sorted { $0.date < $1.date }.map { engCents($0.amount) }
        XCTAssertEqual(wrong, [400, 401])
    }

    /// Rente aanzetten op een pot die al langer bestaat: er is vooraf niets te bevriezen, de rente loopt vanaf de startmaand.
    func testEnablingInterestOnAnExistingPotBooksEarlierMonths() {
        var (d, pot) = engInterestData(rate: 0)
        let today = day(oct2026, 10)
        pot.interestRate = 0.02
        XCTAssertEqual(d.applyDueInterest(upTo: today), 0)
        d.updatePot(pot, current: oct2026)
        XCTAssertEqual(d.applyDueInterest(upTo: today), 2)
        XCTAssertEqual(d.applyDueInterest(upTo: today), 0)
    }

    // MARK: Regels in de geschiedenis

    func testHistoryContextFindsTheStoredBookings() {
        var (d, pot) = engInterestData(monthly: 100)
        let today = day(oct2026, 10)
        d.applyDueInterest(upTo: today)
        d.addPotEntry(potID: pot.id, amount: 50, kind: .deposit, note: "Los", date: day(sep2026, 5))
        let deposit = d.potEntries.first { $0.kind == .deposit }!
        let last = oct2026.adding(12)
        let timeline = d.potTimeline(pot.id, current: last, asOf: today)
        pot = d.pots[0]
        let context = PotHistoryContext(pot: pot, data: d, through: last)

        let doneInterest = timeline.filter { $0.kind == .interest && !$0.isPlanned }
        XCTAssertEqual(doneInterest.count, 2)
        for item in doneInterest {
            // Opgeslagen rente: de boeking is te vinden, maar niet te verwijderen zolang de rente aan staat.
            XCTAssertEqual(context.entryID(for: item), InterestRules.entryID(for: pot.id, month: YearMonth(date: item.date)))
            XCTAssertNil(context.deletableEntryID(for: item))
        }

        // Verwachte rente: geen boeking.
        let plannedInterest = timeline.filter { $0.kind == .interest && $0.isPlanned }
        XCTAssertFalse(plannedInterest.isEmpty)
        for item in plannedInterest {
            XCTAssertNil(context.entryID(for: item))
            XCTAssertNil(context.deletableEntryID(for: item))
        }

        // Een gewone boeking is wel te verwijderen.
        let depositItem = timeline.first { $0.id == deposit.id.uuidString }!
        XCTAssertEqual(context.deletableEntryID(for: depositItem), deposit.id)

        // Maandverdelingen niet.
        let allocations = timeline.filter { $0.isMonthlyAllocation }
        XCTAssertFalse(allocations.isEmpty)
        for item in allocations { XCTAssertNil(context.entryID(for: item)) }
    }

    /// Staat de rente uit, dan zijn de bijgeschreven regels te verwijderen en daalt het saldo met dat bedrag.
    func testBookedInterestCanBeRemovedWhenInterestIsOff() {
        var (d, pot) = engInterestData()
        let today = day(oct2026, 10)
        d.applyDueInterest(upTo: today)
        XCTAssertEqual(engCents(d.potBalance(pot.id, atMoment: today)), 120_400)

        d.pots[0].interestRate = 0
        pot = d.pots[0]
        let last = oct2026.adding(12)
        let context = PotHistoryContext(pot: pot, data: d, through: last)
        let items = d.potTimeline(pot.id, current: last, asOf: today).filter { $0.kind == .interest }
        XCTAssertEqual(items.count, 2)
        for item in items {
            let id = context.deletableEntryID(for: item)
            XCTAssertNotNil(id)
            d.deletePotEntry(id!)
        }
        XCTAssertTrue(d.potEntries.filter { $0.kind == .interest }.isEmpty)
        XCTAssertEqual(engCents(d.potBalance(pot.id, atMoment: today)), 120_000)
        // Zonder rente komt er niets meer bij.
        XCTAssertEqual(d.applyDueInterest(upTo: today), 0)
    }
}
