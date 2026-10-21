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

    // MARK: Ontvangen rente per kalenderdag

    /// Rente van 12% per jaar op 1200, maandelijks op de 28e (de uitbetaling staat op 12:00): augustus 12,00, september 12,12
    /// (1212 x 1%) en oktober 12,24 (1224,12 x 1%), samen 36,36. Een uitbetaling telt de HELE dag mee, ook voor 12:00, zoals
    /// het saldo van de pot: "Ontvangen" mag er niet onder blijven (een controleur zag 24,12 naast een saldo met 36,36).
    func testReceivedInterestCountsTheWholePayoutDay() {
        let (booked, pot) = {
            var made = engInterestData(rate: 0.12, payoutDay: 28, opening: 1_200)
            made.data.applyDueInterest(upTo: engTime(oct2026, 28, hour: 8))
            return made
        }()
        let (unbooked, unbookedPot) = engInterestData(rate: 0.12, payoutDay: 28, opening: 1_200)
        let morning = engTime(oct2026, 28, hour: 8)

        XCTAssertEqual(booked.potEntries.filter { $0.kind == .interest }.map { engCents($0.amount) }, [1_200, 1_212, 1_224])
        for (name, data, pot) in [("bijgeschreven", booked, pot), ("nog niet bijgeschreven", unbooked, unbookedPot)] {
            let received = PotInterestStats.received(in: data, potID: pot.id, asOf: morning)
            XCTAssertEqual(engCents(received.total), 3_636, name)
            XCTAssertEqual(engCents(received.thisYear), 3_636, name)
            XCTAssertEqual(engCents(PotInterestStats.received(in: data, asOf: morning).total), 3_636, "\(name), alle potten")
            // Het saldo van de pot telt precies deze rente mee.
            XCTAssertEqual(engCents(data.potBalanceNow(pot.id, current: oct2026, today: morning)), 120_000 + 3_636, name)
            // 's Avonds hetzelfde, en de dag ervoor nog zonder de uitbetaling van de 28e.
            XCTAssertEqual(engCents(PotInterestStats.received(in: data, potID: pot.id, asOf: engTime(oct2026, 28, hour: 23.5)).total), 3_636, name)
            XCTAssertEqual(engCents(PotInterestStats.received(in: data, potID: pot.id, asOf: engTime(oct2026, 27, hour: 23.5)).total), 2_412, name)
        }
    }

    func testReceivedInterestOfThisYearLeavesOutLastYear() {
        // Een pot sinds augustus 2026 met jaarlijkse rente op 1 januari: in 2027 telt alleen de uitbetaling van dat jaar.
        var (d, pot) = engInterestData(rate: 0.12, payout: .yearly, payoutDay: 1, payoutMonth: 1, opening: 1_200)
        let jan = engTime(engJan2027, 1, hour: 6)
        d.applyDueInterest(upTo: jan)
        let received = PotInterestStats.received(in: d, potID: pot.id, asOf: jan)
        XCTAssertGreaterThan(received.total, 0)
        XCTAssertEqual(received.thisYear, received.total, "de enige uitbetaling is die van 1 januari 2027")
        let earlier = PotInterestStats.received(in: d, potID: pot.id, asOf: engTime(YearMonth(year: 2026, month: 12), 31, hour: 20))
        XCTAssertEqual(earlier.total, 0)
        pot = d.pots[0]
        XCTAssertEqual(d.interestPayments(for: pot.id, from: jan, to: jan, asOf: jan).count, 1)
    }
}

// MARK: - Doel en voortgang van een spaarpot

final class PotGoalTextTests: XCTestCase {
    func testGoalStatus() {
        XCTAssertEqual(PotFormat.goalStatus(balance: 1_032, goal: 2_400), "Nog \(Fmt.euro(1_368)) te gaan")
        XCTAssertEqual(PotFormat.goalStatus(balance: 2_400, goal: 2_400), "Doel bereikt")
        XCTAssertEqual(PotFormat.goalStatus(balance: 3_000, goal: 2_400), "Doel bereikt")
    }

    func testProgressSpeechNamesPercentageBalanceAndGoal() {
        XCTAssertEqual(PotFormat.progressSpeech(balance: 1_032, goal: 2_400, progress: 0.43),
                       "43 procent, \(ChartText.euro(1_032)) van \(ChartText.euro(2_400))")
        // Boven 100% staat het echte percentage; onzin (NaN, oneindig) wordt 0 en breekt niets.
        XCTAssertEqual(PotFormat.progressSpeech(balance: 3_000, goal: 2_400, progress: 1.25),
                       "125 procent, \(ChartText.euro(3_000)) van \(ChartText.euro(2_400))")
        XCTAssertTrue(PotFormat.progressSpeech(balance: 0, goal: 100, progress: .nan).hasPrefix("0 procent"))
        XCTAssertTrue(PotFormat.progressSpeech(balance: 0, goal: 100, progress: .infinity).hasPrefix("0 procent"))
        XCTAssertTrue(PotFormat.progressSpeech(balance: 0, goal: 100, progress: -3).hasPrefix("0 procent"))
    }
}

// MARK: - De keuze voor het Overzicht

final class FavoritePickerTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    func testTheLimitsAreThreePotsAndFourHoldings() {
        XCTAssertEqual(FavoritePicker.potLimit, 3)
        XCTAssertEqual(FavoritePicker.holdingLimit, 4)
    }

    func testTappingAddsInTheOrderOfTappingUpToTheLimit() {
        var selected: [UUID] = []
        selected = FavoritePicker.toggled(b, in: selected, limit: 3)
        selected = FavoritePicker.toggled(a, in: selected, limit: 3)
        selected = FavoritePicker.toggled(c, in: selected, limit: 3)
        XCTAssertEqual(selected, [b, a, c])
        // Een vierde komt er niet bij: de keuze blijft zoals ze was.
        XCTAssertEqual(FavoritePicker.toggled(d, in: selected, limit: 3), [b, a, c])
        XCTAssertEqual(FavoritePicker.toggled(d, in: [a, b, c], limit: 4), [a, b, c, d])
        XCTAssertEqual(FavoritePicker.toggled(e, in: [a, b, c, d], limit: 4), [a, b, c, d])
    }

    func testTappingAChosenOneRemovesItAndTheRestMovesUp() {
        XCTAssertEqual(FavoritePicker.toggled(a, in: [b, a, c], limit: 3), [b, c])
        // Daarna is er weer plek.
        XCTAssertEqual(FavoritePicker.toggled(d, in: [b, c], limit: 3), [b, c, d])
        XCTAssertEqual(FavoritePicker.toggled(a, in: [a], limit: 3), [])
    }

    func testEmptySlotsAndWhatTheyDo() {
        XCTAssertEqual(FavoritePicker.emptySlots(chosen: 0), 3)
        XCTAssertEqual(FavoritePicker.emptySlots(chosen: 2), 1)
        XCTAssertEqual(FavoritePicker.emptySlots(chosen: 3), 0)
        XCTAssertEqual(FavoritePicker.emptySlots(chosen: 9), 0)
        XCTAssertEqual(FavoritePicker.emptySlots(chosen: 1, limit: 4), 3)
        // Zolang er een pot is die nog niet gekozen is, kiest de plek; anders maakt ze een nieuwe pot.
        XCTAssertEqual(FavoritePicker.slotAction(chosen: 2, available: 5), .choose)
        XCTAssertEqual(FavoritePicker.slotAction(chosen: 2, available: 2), .create)
        XCTAssertEqual(FavoritePicker.slotAction(chosen: 0, available: 0), .create)
    }

    /// De rekenmotor bewaart de keuze en houdt haar schoon: een verwijderde pot verdwijnt uit de keuze (scenario 21).
    func testADeletedPotLeavesTheChoice() {
        var d = makeBaseData()
        let first = Pot(name: "Een", monthlyContribution: 0, startMonth: aug2026)
        let second = Pot(name: "Twee", monthlyContribution: 0, startMonth: aug2026)
        let third = Pot(name: "Drie", monthlyContribution: 0, startMonth: aug2026)
        for pot in [first, second, third] { d.addPot(pot) }
        d.homePotIDs = [third.id, first.id, second.id]
        XCTAssertEqual(d.homePots().map { $0.name }, ["Drie", "Een", "Twee"])
        d.deletePot(first.id)
        XCTAssertEqual(d.homePotIDs ?? [], [third.id, second.id])
        XCTAssertEqual(d.homePots().map { $0.name }, ["Drie", "Twee"])
        // Zonder keuze staan de eerste drie op het Overzicht.
        d.homePotIDs = nil
        XCTAssertEqual(d.homePots().count, 2)
    }
}

// MARK: - Het formulier van een belegging

final class HoldingFormTests: XCTestCase {
    private let today = day(oct2026, 15)

    private func base() -> FinanceData {
        var d = FinanceData(startMonth: oct2026.adding(-12))
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        d.materialize(upTo: oct2026)
        return d
    }

    private func holding(ticker: String? = nil, units: Double? = nil, invested: Double = 3_000, monthly: Double = 200,
                         start: YearMonth = oct2026.adding(-8)) -> Holding {
        Holding(name: "Demo", kind: .etf, ticker: ticker, units: units, investedTotal: invested,
                expectedReturn: 0, annualCost: 0, monthlyContribution: monthly, startMonth: start)
    }

    // MARK: Belegd sinds

    func testStartMonthChoicesCoverTenYearsNewestFirst() {
        let choices = HoldingForm.startMonthChoices(current: oct2026, selected: oct2026)
        XCTAssertEqual(choices.count, 120)
        XCTAssertEqual(choices.first, oct2026)
        XCTAssertEqual(choices.last, oct2026.adding(-119))
        XCTAssertEqual(Set(choices).count, choices.count)
        XCTAssertEqual(choices, choices.sorted(by: >))
    }

    func testAStartMonthOutsideTheTenYearsStillExistsInTheList() {
        let old = oct2026.adding(-200)
        let withOld = HoldingForm.startMonthChoices(current: oct2026, selected: old)
        XCTAssertEqual(withOld.count, 121)
        XCTAssertEqual(withOld.last, old)
        XCTAssertEqual(withOld.first, oct2026)
        // Een maand in de toekomst (uit een import of van een ander apparaat) staat bovenaan.
        let future = oct2026.adding(3)
        let withFuture = HoldingForm.startMonthChoices(current: oct2026, selected: future)
        XCTAssertEqual(withFuture.first, future)
        XCTAssertEqual(withFuture.count, 121)
        // Een maand binnen de tien jaar komt niet dubbel.
        XCTAssertEqual(HoldingForm.startMonthChoices(current: oct2026, selected: oct2026.adding(-5)).count, 120)
    }

    // MARK: Teksten

    func testTheUnitsHintAppearsOnlyForATickerWithoutUnits() {
        XCTAssertTrue(HoldingForm.needsUnitsHint(ticker: "VWCE.DE", units: 0))
        XCTAssertTrue(HoldingForm.needsUnitsHint(ticker: " BTC-EUR ", units: -1))
        XCTAssertFalse(HoldingForm.needsUnitsHint(ticker: "VWCE.DE", units: 12))
        XCTAssertFalse(HoldingForm.needsUnitsHint(ticker: "", units: 0))
        XCTAssertFalse(HoldingForm.needsUnitsHint(ticker: "   ", units: 0))
        XCTAssertTrue(HoldingForm.unitsHint.contains("aantal stuks"))
        XCTAssertTrue(HoldingForm.isTracked(ticker: "VWCE.DE", units: 12))
        XCTAssertFalse(HoldingForm.isTracked(ticker: "VWCE.DE", units: 0))
        XCTAssertFalse(HoldingForm.isTracked(ticker: "", units: 12))
    }

    func testTheEstimateHintNamesTheThreeFields() {
        XCTAssertTrue(HoldingForm.estimateHint.contains("Belegd sinds"))
        XCTAssertTrue(HoldingForm.estimateHint.contains("Totaal ingelegd"))
        XCTAssertTrue(HoldingForm.estimateHint.contains("Huidige waarde"))
        XCTAssertTrue(HoldingForm.estimateHint.contains("zonder rendement"))
    }

    func testTheCurrentValueNoteSaysWhetherTheValueIsEstimated() {
        XCTAssertNil(HoldingForm.currentValueNote(nil))
        var d = base()
        let h = holding()
        d.addHolding(h)
        let estimated = d.holdingStateNow(h, current: oct2026, today: today)
        XCTAssertEqual(HoldingForm.currentValueNote(estimated), "Nu \(Fmt.euro(3_000)), geschat uit je inleg.")
        d.addSnapshot(holdingID: h.id, value: 3_450, invested: 3_000, date: day(oct2026, 10))
        let real = d.holdingStateNow(d.holdings[0], current: oct2026, today: today)
        XCTAssertEqual(HoldingForm.currentValueNote(real), "Nu \(Fmt.euro(3_450)), volgens je laatste waarde-update.")
    }

    // MARK: Bewaren

    /// Het gemelde geval: alleen "Totaal ingelegd" 3.000, inleg 200 per maand en "Belegd sinds" 8 maanden geleden. Er komt GEEN
    /// waarde-update; de grafiek is de afgeleide lijn met zijn onderschrift en "Winst" is verborgen.
    func testANewHoldingWithoutACurrentValueGetsTheDerivedLineAndNoMeasurement() {
        var d = base()
        let h = holding()
        HoldingForm.save(h, isNew: true, enteredValue: 0, into: &d, current: oct2026, now: today)
        XCTAssertEqual(d.holdings.count, 1)
        XCTAssertTrue(d.holdings[0].snapshots.isEmpty, "geen verzonnen waarde-update")
        XCTAssertEqual(d.holdings[0].startMonth, oct2026.adding(-8))

        let model = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.footnote, "Geschat uit je inleg, zonder rendement.")
        XCTAssertGreaterThan(model.allPoints.filter { $0.kind == .estimated }.count, 1, "de lijn loopt vanaf Belegd sinds")
        XCTAssertEqual(model.lines.map { $0.id }, ["waarde"], "afgeleid: geen tweede lijn Ingelegd op dezelfde plek")

        let figures = PortfolioFigures(d, current: oct2026, today: today)
        XCTAssertEqual(figures.value, 3_000, accuracy: 0.001)
        XCTAssertEqual(figures.invested, 3_000, accuracy: 0.001)
        XCTAssertTrue(figures.isEstimated)
        XCTAssertFalse(figures.showsGain, "Winst en Rendement zeggen niets zolang het geschat is")
    }

    func testANewHoldingWithACurrentValueGetsOneMeasurementOfToday() {
        var d = base()
        let h = holding()
        HoldingForm.save(h, isNew: true, enteredValue: 3_450, into: &d, current: oct2026, now: today)
        XCTAssertEqual(d.holdings[0].snapshots.count, 1)
        XCTAssertEqual(d.holdings[0].snapshots[0].value, 3_450, accuracy: 0.001)
        XCTAssertEqual(d.holdings[0].snapshots[0].invested, 3_000, accuracy: 0.001)
        let figures = PortfolioFigures(d, current: oct2026, today: today)
        XCTAssertFalse(figures.isEstimated)
        XCTAssertTrue(figures.showsGain)
        XCTAssertEqual(figures.gain, 450, accuracy: 0.001)
        XCTAssertEqual(figures.gainFraction ?? 0, 0.15, accuracy: 1e-9)
        let model = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.lines.map { $0.id }, ["waarde", "ingelegd"])
    }

    /// Een belegging met een ticker mag ook een huidige waarde krijgen (K19 b); een negatieve of lege waarde telt niet.
    func testACurrentValueWorksWithATickerAndOnlyWhenItIsPositive() {
        var d = base()
        let tracked = holding(ticker: "VWCE.DE", units: nil)
        HoldingForm.save(tracked, isNew: true, enteredValue: 2_900, into: &d, current: oct2026, now: today)
        XCTAssertEqual(d.holdings[0].snapshots.count, 1)
        var other = base()
        HoldingForm.save(holding(), isNew: true, enteredValue: -50, into: &other, current: oct2026, now: today)
        XCTAssertTrue(other.holdings[0].snapshots.isEmpty)
        HoldingForm.save(holding(), isNew: true, enteredValue: .nan, into: &other, current: oct2026, now: today)
        XCTAssertTrue(other.holdings[1].snapshots.isEmpty)
    }

    func testEditingWithACurrentValueReplacesTheMeasurementOfToday() {
        var d = base()
        let h = holding()
        HoldingForm.save(h, isNew: true, enteredValue: 3_300, into: &d, current: oct2026, now: today)
        var edited = d.holdings[0]
        edited.investedTotal = 3_100
        HoldingForm.save(edited, isNew: false, enteredValue: 3_500, into: &d, current: oct2026, now: today)
        // Dezelfde dag: de nieuwe waarde-update vervangt de eerste, er komt er geen bij.
        XCTAssertEqual(d.holdings[0].snapshots.count, 1)
        XCTAssertEqual(d.holdings[0].snapshots[0].value, 3_500, accuracy: 0.001)
        XCTAssertEqual(d.holdings[0].snapshots[0].invested, 3_100, accuracy: 0.001)
        XCTAssertEqual(d.holdings[0].investedTotal, 3_100, accuracy: 0.001)
        // Een andere dag: een tweede waarde-update.
        var later = d.holdings[0]
        later.name = "Demo 2"
        HoldingForm.save(later, isNew: false, enteredValue: 3_600, into: &d, current: oct2026, now: day(oct2026, 20))
        XCTAssertEqual(d.holdings[0].snapshots.count, 2)
        XCTAssertEqual(d.holdings[0].name, "Demo 2")
    }

    func testEditingWithoutACurrentValueLeavesTheValuesAlone() {
        var d = base()
        let h = holding()
        HoldingForm.save(h, isNew: true, enteredValue: 0, into: &d, current: oct2026, now: today)
        var edited = d.holdings[0]
        edited.expectedReturn = 0.05
        edited.startMonth = oct2026.adding(-3)
        HoldingForm.save(edited, isNew: false, enteredValue: 0, into: &d, current: oct2026, now: today)
        XCTAssertTrue(d.holdings[0].snapshots.isEmpty, "een belegging uit je inleg blijft een schatting")
        XCTAssertEqual(d.holdings[0].startMonth, oct2026.adding(-3))
        XCTAssertEqual(d.holdings[0].expectedReturn, 0.05, accuracy: 1e-12)
        // "Totaal ingelegd" wijzigen bij een bestaand meetpunt: "Ingelegd" volgt (scenario 11e, Core C9).
        var measured = base()
        HoldingForm.save(h, isNew: true, enteredValue: 3_300, into: &measured, current: oct2026, now: day(oct2026, 3))
        var raised = measured.holdings[0]
        raised.investedTotal = 3_500
        HoldingForm.save(raised, isNew: false, enteredValue: 0, into: &measured, current: oct2026, now: today)
        let state = measured.holdingStateNow(measured.holdings[0], current: oct2026, today: today)
        XCTAssertEqual(state?.invested ?? 0, 3_500, accuracy: 0.001)
    }
}

// MARK: - De cijfers en de kleine grafiek

final class PortfolioFiguresTests: XCTestCase {
    private let today = day(oct2026, 15)

    private func base() -> FinanceData {
        var d = FinanceData(startMonth: oct2026.adding(-12))
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        d.materialize(upTo: oct2026)
        return d
    }

    private func holding(name: String, invested: Double, monthly: Double = 0, start: YearMonth = oct2026.adding(-8)) -> Holding {
        Holding(name: name, kind: .etf, ticker: nil, units: nil, investedTotal: invested,
                expectedReturn: 0, annualCost: 0, monthlyContribution: monthly, startMonth: start)
    }

    func testNoHoldingsMeansNothingToShow() {
        let figures = PortfolioFigures(base(), current: oct2026, today: today)
        XCTAssertEqual(figures.value, 0)
        XCTAssertEqual(figures.invested, 0)
        XCTAssertFalse(figures.isEstimated, "zonder beleggingen valt er niets te schatten")
        XCTAssertFalse(figures.showsGain)
        XCTAssertNil(figures.gainFraction)
    }

    func testTheFiguresAreEstimatedOnlyWhenEveryHoldingIsEstimated() {
        var d = base()
        d.addHolding(holding(name: "Afgeleid", invested: 3_000, monthly: 200))
        XCTAssertTrue(PortfolioFigures(d, current: oct2026, today: today).isEstimated)
        // Met een echte waarde-update erbij is het geheel niet meer alleen een schatting: Winst telt dan mee.
        d.addHolding(holding(name: "Echt", invested: 1_000), initialValue: 1_200, now: day(oct2026, 5))
        let mixed = PortfolioFigures(d, current: oct2026, today: today)
        XCTAssertFalse(mixed.isEstimated)
        XCTAssertTrue(mixed.showsGain)
        XCTAssertEqual(mixed.value, 4_200, accuracy: 0.001)
        XCTAssertEqual(mixed.gain, 200, accuracy: 0.001)
    }

    func testTheFiguresOfOneHolding() {
        var d = base()
        let h = holding(name: "Een", invested: 3_000, monthly: 200)
        d.addHolding(h)
        let estimated = HoldingFigures(d.holdingStateNow(h, current: oct2026, today: today))
        XCTAssertTrue(estimated.isEstimated)
        XCTAssertFalse(estimated.showsGain)
        XCTAssertEqual(estimated.value, 3_000, accuracy: 0.001)
        let none = HoldingFigures(nil)
        XCTAssertEqual(none.value, 0)
        XCTAssertFalse(none.showsGain)
        XCTAssertFalse(none.isEstimated)
        d.addSnapshot(holdingID: h.id, value: 3_300, invested: 3_000, date: day(oct2026, 10))
        let real = HoldingFigures(d.holdingStateNow(d.holdings[0], current: oct2026, today: today))
        XCTAssertFalse(real.isEstimated)
        XCTAssertTrue(real.showsGain)
        XCTAssertEqual(real.gain, 300, accuracy: 0.001)
        XCTAssertEqual(real.gainFraction ?? 0, 0.1, accuracy: 1e-9)
    }

    // MARK: TrendGlance

    func testTheGlanceOfADerivedLineSaysItIsEstimated() {
        var d = base()
        d.addHolding(holding(name: "Afgeleid", invested: 3_000, monthly: 200))
        let model = PortfolioTrend.model(d, window: .sixMonths, current: oct2026, today: today)
        let glance = TrendGlance(model)
        XCTAssertNotNil(glance)
        XCTAssertEqual(glance?.end, "Nu \(Fmt.euroWhole(3_000)) (geschat)")
        XCTAssertNotNil(glance?.start, "de lijn begint ver genoeg terug om een begin te tonen")
    }

    func testTheGlanceOfARealLineShowsStartAndEnd() {
        var d = base()
        let h = holding(name: "Echt", invested: 1_000, start: aug2026)
        d.addHolding(h)
        d.addSnapshot(holdingID: h.id, value: 1_000, invested: 1_000, date: day(aug2026, 10))
        d.addSnapshot(holdingID: h.id, value: 1_250, invested: 1_000, date: day(oct2026, 10))
        let model = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        let glance = TrendGlance(model)
        XCTAssertEqual(glance?.end, "Nu \(Fmt.euroWhole(1_250))")
        XCTAssertEqual(glance?.start, "\(Fmt.shortMonthYear(aug2026)) \(Fmt.euroWhole(1_000))")
    }

    func testTheGlanceOfASinglePointHasNoStartAndAnEmptyModelHasNoGlance() {
        var d = base()
        d.addHolding(holding(name: "Nieuw", invested: 500, start: oct2026))
        let single = PortfolioTrend.model(d, window: .all, current: oct2026, today: today)
        XCTAssertNil(TrendGlance(single)?.start)
        XCTAssertNotNil(TrendGlance(single))
        let empty = PortfolioTrend.model(base(), window: .all, current: oct2026, today: today)
        XCTAssertNotNil(empty.empty)
        XCTAssertNil(TrendGlance(empty))
    }

    func testPriceHistoryFailureAlwaysEndsWithAPeriod() {
        XCTAssertEqual(PriceHistoryText.failure("Er is geen internetverbinding."), "Er is geen internetverbinding.")
        XCTAssertEqual(PriceHistoryText.failure("Er is geen internetverbinding"), "Er is geen internetverbinding.")
        XCTAssertEqual(PriceHistoryText.failure("  Ophalen mislukt: time-out \n"), "Ophalen mislukt: time-out.")
        XCTAssertEqual(PriceHistoryText.failure("Wat nu?"), "Wat nu?")
        XCTAssertEqual(PriceHistoryText.failure(""), "Ophalen mislukt.")
        XCTAssertEqual(PriceHistoryText.failure("   "), "Ophalen mislukt.")
    }
}

// MARK: - De grafiek bij Beleggingen voor elk gemeld geval (charts.md par. 3.2 en de drie demo-scenario's)

final class HoldingChartScenarioTests: XCTestCase {
    private let today = day(oct2026, 15)
    private let derivedFootnote = "Geschat uit je inleg, zonder rendement."

    private func base() -> FinanceData {
        var d = FinanceData(startMonth: oct2026.adding(-12))
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        d.materialize(upTo: oct2026)
        return d
    }

    private func holding(ticker: String? = nil, units: Double? = nil, invested: Double = 0, monthly: Double = 0,
                         start: YearMonth = oct2026) -> Holding {
        Holding(name: "Demo", kind: .etf, ticker: ticker, units: units, investedTotal: invested,
                expectedReturn: 0, annualCost: 0, monthlyContribution: monthly, startMonth: start)
    }

    private func model(_ d: FinanceData, window: PortfolioWindow = .all) -> TrendModel {
        PortfolioTrend.model(d, window: window, current: oct2026, today: today)
    }

    /// Nooit een lege vlakte: een grafiek met minstens een punt, of een lege staat met een actie. En nooit de oude voetnoot.
    private func assertChartOrActionableEmptyState(_ m: TrendModel, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        if let empty = m.empty {
            XCTAssertNotNil(empty.action, "\(name): een lege staat heeft een actie", file: file, line: line)
            XCTAssertNotNil(empty.actionTitle, "\(name): met een knoptekst", file: file, line: line)
            XCTAssertTrue(m.lines.isEmpty, "\(name): geen lijnen naast een lege staat", file: file, line: line)
        } else {
            XCTAssertFalse(m.lines.isEmpty, "\(name): een grafiek heeft lijnen", file: file, line: line)
            XCTAssertGreaterThanOrEqual(m.allPoints.count, 1, "\(name): en punten", file: file, line: line)
        }
        XCTAssertFalse(m.summary.isEmpty, name, file: file, line: line)
        XCTAssertFalse(m.summary.contains("groeit mee"), name, file: file, line: line)
        XCTAssertFalse((m.footnote ?? "").contains("meetpunt"), name, file: file, line: line)
        let range = m.domain(nonNegative: true)
        XCTAssertLessThan(range.lowerBound, range.upperBound, name, file: file, line: line)
    }

    private func assertDerived(_ m: TrendModel, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(m.empty, name, file: file, line: line)
        XCTAssertEqual(m.footnote, derivedFootnote, "\(name): een afgeleide lijn heeft het onderschrift", file: file, line: line)
        let history = m.allPoints.filter { $0.kind != .projected }
        XCTAssertFalse(history.isEmpty, name, file: file, line: line)
        XCTAssertTrue(history.allSatisfy { $0.kind == .estimated }, name, file: file, line: line)
    }

    // MARK: charts.md 3.2

    func testB1ATickerWithUnitsAndATypedTotalButNoQuoteYet() {
        var d = base()
        d.addHolding(holding(ticker: "VWCE.DE", units: 10, invested: 1_000))
        let m = model(d)
        assertChartOrActionableEmptyState(m, "b1")
        assertDerived(m, "b1")
        XCTAssertEqual(TrendGlance(m)?.end, "Nu \(Fmt.euroWhole(1_000)) (geschat)")
    }

    func testB1cATickerWithoutUnitsAsksForTheUnitsOrDrawsTheTypedTotal() {
        var d = base()
        var h = holding(ticker: "VWCE.DE", units: nil, invested: 0)
        h.lastPrice = 105
        d.addHolding(h)
        let empty = model(d)
        assertChartOrActionableEmptyState(empty, "b1c zonder bedrag")
        XCTAssertEqual(empty.empty?.action, .enterUnits(d.holdings[0].id))
        // Met "Totaal ingelegd" erbij is er wel een lijn.
        var typed = base()
        var withTotal = holding(ticker: "VWCE.DE", units: nil, invested: 1_000)
        withTotal.lastPrice = 105
        typed.addHolding(withTotal)
        assertChartOrActionableEmptyState(model(typed), "b1c met bedrag")
        assertDerived(model(typed), "b1c met bedrag")
    }

    func testB2AManualValueIsARealLine() {
        var d = base()
        d.addHolding(holding(invested: 5_000), initialValue: 5_000, now: day(oct2026, 5))
        let m = model(d)
        assertChartOrActionableEmptyState(m, "b2")
        XCTAssertNil(m.empty)
        XCTAssertTrue(m.allPoints.filter { $0.kind != .projected }.allSatisfy { $0.kind == .actual })
        XCTAssertNotEqual(m.footnote, derivedFootnote)
    }

    func testB3OnlyAMonthlyContributionIsADerivedLine() {
        var d = base()
        d.addHolding(holding(monthly: 200, start: oct2026.adding(-3)))
        let m = model(d)
        assertChartOrActionableEmptyState(m, "b3")
        assertDerived(m, "b3")
    }

    func testB3bATypedTotalPlusAContributionIsADerivedLineEndingAtTheTotal() {
        var d = base()
        d.addHolding(holding(invested: 3_000, monthly: 200, start: oct2026.adding(-3)))
        let m = model(d)
        assertChartOrActionableEmptyState(m, "b3b")
        assertDerived(m, "b3b")
        XCTAssertEqual(PortfolioFigures(d, current: oct2026, today: today).value, 3_000, accuracy: 0.001)
    }

    func testB4aABelegdSindsInThePastDrawsHistoryFromThatMonth() {
        var d = base()
        d.addHolding(holding(invested: 2_000, monthly: 200, start: oct2026.adding(-6)))
        let m = model(d)
        assertChartOrActionableEmptyState(m, "b4a")
        assertDerived(m, "b4a")
        let first = m.allPoints.first
        XCTAssertEqual(first.map { YearMonth(date: $0.date) }, oct2026.adding(-6), "de lijn begint bij Belegd sinds")
    }

    func testG1AMeasurementOfZeroIsAFlatLineNotAnEmptyChart() {
        var d = base()
        let h = holding(invested: 0)
        d.addHolding(h)
        d.addSnapshot(holdingID: h.id, value: 0, invested: 0, date: day(oct2026, 5))
        let m = model(d)
        assertChartOrActionableEmptyState(m, "g1")
        XCTAssertNil(m.empty)
        XCTAssertTrue(m.allPoints.allSatisfy { $0.value == 0 })
    }

    func testG2ANegativeContributionNeverDrawsAValueBelowZero() {
        var d = base()
        d.addHolding(holding(invested: 1_000, monthly: -300, start: oct2026), initialValue: 1_000, now: day(oct2026, 5))
        let m = model(d)
        assertChartOrActionableEmptyState(m, "g2")
        XCTAssertNil(m.empty)
        XCTAssertTrue(m.allPoints.allSatisfy { $0.value >= 0 }, "een verwachte waarde onder 0 bestaat niet")
    }

    // MARK: de drie -mybuddy-demo-holding-scenario's (DebugLaunch.DemoHoldingScenario)

    private func demo(ticker: String?, units: Double?) -> FinanceData {
        var d = base()
        d.addHolding(holding(ticker: ticker, units: units, invested: 3_000, monthly: 200, start: oct2026.adding(-8)))
        return d
    }

    func testDemoOnlyInvested() {
        let m = model(demo(ticker: nil, units: nil))
        assertChartOrActionableEmptyState(m, "only-invested")
        assertDerived(m, "only-invested")
        XCTAssertEqual(m.allPoints.filter { $0.kind != .projected }.count, 9, "negen maanden: Belegd sinds t/m nu")
    }

    func testDemoTickerWithoutUnits() {
        let m = model(demo(ticker: "VWCE.DE", units: nil))
        assertChartOrActionableEmptyState(m, "ticker-no-units")
        assertDerived(m, "ticker-no-units")
    }

    func testDemoTrackedButOffline() {
        let m = model(demo(ticker: "VWCE.DE", units: 12))
        assertChartOrActionableEmptyState(m, "tracked-offline")
        assertDerived(m, "tracked-offline")
    }

    /// De keuzebalk 6 mnd / 1 jaar / 3 jaar bestaat alleen als hij iets verandert (scenario 11f).
    func testTheWindowBarOnlyOffersChoicesThatChangeTheView() {
        let d = demo(ticker: nil, units: nil)
        let available = PortfolioTrend.availableMonths(d, current: oct2026, today: today)
        XCTAssertEqual(available, 9)
        XCTAssertEqual(PortfolioWindow.options(availableMonths: available), [.sixMonths, .all])
        XCTAssertEqual(PortfolioWindow.effective(.year, availableMonths: available), .all, "een keuze die niet bestaat valt terug op Alles")
        XCTAssertEqual(PortfolioWindow.effective(.sixMonths, availableMonths: available), .sixMonths)
        XCTAssertEqual(PortfolioWindow.options(availableMonths: PortfolioTrend.availableMonths(base(), current: oct2026, today: today)), [])
    }
}
