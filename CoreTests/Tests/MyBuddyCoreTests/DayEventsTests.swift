import XCTest
@testable import MyBuddyCore

/// Gebeurtenissen per dag en het saldo van de bankrekening per dag.
/// Basisdata (`makeBaseData`): salaris 3000 en toeslag 100 op de 25e, huur 1000 op de 1e (terugkerend),
/// in augustus ook nog een eenmalige uitgave van 50 op de 1e.
final class DayEventsTests: XCTestCase {
    // MARK: Gebeurtenissen van een maand

    func testMonthEventsOfThePlan() {
        let d = makeBaseData()
        let events = d.dayEvents(in: sep2026, asOf: day(sep2026, 10))
        XCTAssertEqual(events.map(\.kind), [.expense, .salary, .income])
        XCTAssertEqual(events.map(\.title), ["Huur", "Salaris", "Toeslag"])
        XCTAssertEqual(events.map(\.day), [1, 25, 25])
        XCTAssertEqual(events.map(\.bankAmount), [-1000, 3000, 100])
        XCTAssertEqual(events.map(\.potAmount), [0, 0, 0])
        XCTAssertEqual(events.map(\.isPlanned), [false, true, true])
        for event in events {
            XCTAssertEqual(engHour(event.date), 12, "op de dag zelf om 12:00")
            XCTAssertEqual(engDayNumber(event.date), event.day)
            XCTAssertNil(event.potID)
            XCTAssertNil(event.holdingID)
        }
        XCTAssertNotNil(events[0].lineID)
        XCTAssertNil(events[1].lineID)
        XCTAssertNotNil(events[2].lineID)
        XCTAssertEqual(Set(events.map(\.id)).count, events.count)
    }

    func testIsPlannedIsDecidedByTheAsOfMoment() {
        let d = makeBaseData()
        // Precies op het moment van de gebeurtenis (12:00) is die niet meer gepland.
        let atNoon = d.dayEvents(in: sep2026, asOf: engTime(sep2026, 25, hour: 12))
        XCTAssertEqual(atNoon.map(\.isPlanned), [false, false, false])
        let justBefore = d.dayEvents(in: sep2026, asOf: engTime(sep2026, 25, hour: 11.9))
        XCTAssertEqual(justBefore.map(\.isPlanned), [false, true, true])
        let allPast = d.dayEvents(in: sep2026, asOf: day(oct2026, 1))
        XCTAssertTrue(allPast.allSatisfy { !$0.isPlanned })
        let allFuture = d.dayEvents(in: sep2026, asOf: day(aug2026, 1))
        XCTAssertTrue(allFuture.allSatisfy { $0.isPlanned })
    }

    func testEventsOnDayReturnsOnlyThatDay() {
        let d = makeBaseData()
        XCTAssertEqual(d.eventsOnDay(day(sep2026, 25), asOf: day(sep2026, 1)).map(\.title), ["Salaris", "Toeslag"])
        XCTAssertEqual(d.eventsOnDay(engTime(sep2026, 25, hour: 0.2), asOf: day(sep2026, 1)).count, 2)
        XCTAssertEqual(d.eventsOnDay(engTime(sep2026, 25, hour: 23.5), asOf: day(sep2026, 1)).count, 2)
        XCTAssertTrue(d.eventsOnDay(day(sep2026, 26), asOf: day(sep2026, 1)).isEmpty)
        XCTAssertEqual(d.eventsOnDay(day(sep2026, 1), asOf: day(sep2026, 1)).map(\.title), ["Huur"])
    }

    func testMonthsBeforeTheStartHaveNoEvents() {
        let d = makeBaseData()
        XCTAssertTrue(d.dayEvents(in: YearMonth(year: 2026, month: 7), asOf: day(aug2026, 1)).isEmpty)
    }

    func testZeroAmountsProduceNoEvents() {
        var d = makeBaseData()
        d.upsertLine(MoneyLine(name: "Niks", amount: 0), kind: .expense, in: sep2026)
        d.upsertLine(MoneyLine(name: "Ook niks", amount: 0), kind: .income, in: sep2026)
        XCTAssertEqual(d.dayEvents(in: sep2026, asOf: day(sep2026, 1)).count, 3)
    }

    func testEventIDsAreStableAcrossCalls() {
        // Een maand die nog niet is vastgelegd krijgt elke keer dezelfde id's, zodat een lijst niet verspringt.
        let d = makeBaseData()
        let first = d.dayEvents(in: engDec2026, asOf: day(sep2026, 1))
        let second = d.dayEvents(in: engDec2026, asOf: day(sep2026, 1))
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.compactMap(\.lineID), second.compactMap(\.lineID))
        // De id's van twee maanden verschillen.
        let other = d.dayEvents(in: engNov2026, asOf: day(sep2026, 1))
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: Set(other.map(\.id))))
    }

    // MARK: Dagen

    func testSalaryAndOwnDaysFollowTheSettings() {
        var d = makeBaseData()
        d.salary.payDay = 20
        d.months[aug2026.key]?.extraIncome[0].day = 5   // toeslag op de 5e
        d.months[aug2026.key]?.expenses[0].day = 3      // huur op de 3e
        let events = d.dayEvents(in: sep2026, asOf: day(sep2026, 1))
        XCTAssertEqual(events.map(\.title), ["Huur", "Toeslag", "Salaris"])
        XCTAssertEqual(events.map(\.day), [3, 5, 20])
        XCTAssertEqual(d.salaryDay(), 20)
    }

    func testIncomeWithoutOwnDayComesInOnThePayDay() {
        var d = makeBaseData()
        d.salary.payDay = 12
        let events = d.dayEvents(in: sep2026, asOf: day(sep2026, 1))
        XCTAssertEqual(events.filter { $0.kind == .salary || $0.kind == .income }.map(\.day), [12, 12])
    }

    func testDaysAreClampedToTheLengthOfTheMonth() {
        var d = makeBaseData()
        d.salary.payDay = 31
        d.months[aug2026.key]?.expenses[0].day = 31
        func salaryEvent(_ m: YearMonth) -> DayEvent? {
            d.dayEvents(in: m, asOf: day(aug2026, 1)).first { $0.kind == .salary }
        }
        XCTAssertEqual(salaryEvent(sep2026)?.day, 30)
        XCTAssertEqual(salaryEvent(oct2026)?.day, 31)
        XCTAssertEqual(salaryEvent(engFeb2027)?.day, 28)
        XCTAssertEqual(salaryEvent(engFeb2028)?.day, 29)
        // De datum van de gebeurtenis ligt echt op die dag.
        XCTAssertEqual(engDayNumber(salaryEvent(engFeb2027)!.date), 28)
        XCTAssertEqual(YearMonth(date: salaryEvent(engFeb2027)!.date), engFeb2027)
        let rent = d.dayEvents(in: engFeb2027, asOf: day(aug2026, 1)).first { $0.kind == .expense }
        XCTAssertEqual(rent?.day, 28)
    }

    func testTransferDayPriorityAndClamping() {
        var d = makeBaseData()
        let plain = Pot(name: "Plain", monthlyContribution: 100, startMonth: aug2026)
        var tenth = Pot(name: "Tiende", monthlyContribution: 100, startMonth: aug2026)
        tenth.transferDay = 10
        var last = Pot(name: "Laatste", monthlyContribution: 100, startMonth: aug2026)
        last.transferDay = 31
        var holding = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, monthlyContribution: 50, startMonth: aug2026)
        holding.transferDay = 5
        [plain, tenth, last].forEach { d.addPot($0) }
        d.addHolding(holding)

        XCTAssertEqual(d.transferDay(for: plain.id, in: sep2026), 25, "zonder eigen dag: de salarisdag")
        XCTAssertEqual(d.transferDay(for: tenth.id, in: sep2026), 10)
        XCTAssertEqual(d.transferDay(for: holding.id, in: sep2026), 5)
        XCTAssertEqual(d.transferDay(for: last.id, in: sep2026), 30, "geklemd op de lengte van de maand")
        XCTAssertEqual(d.transferDay(for: last.id, in: engFeb2027), 28)
        XCTAssertEqual(d.transferDay(for: last.id, in: engFeb2028), 29)
        XCTAssertEqual(d.transferDay(for: UUID(), in: sep2026), 25)

        // De dag van de hele maandverdeling gaat voor de dag van de pot of belegging.
        d.editPlan(sep2026) { $0.transferDay = 15 }
        XCTAssertEqual(d.transferDay(for: plain.id, in: sep2026), 15)
        XCTAssertEqual(d.transferDay(for: tenth.id, in: sep2026), 15)
        XCTAssertEqual(d.transferDay(for: holding.id, in: sep2026), 15)
        XCTAssertEqual(d.transferDay(for: tenth.id, in: oct2026), 10, "andere maanden blijven hun eigen dag houden")

        // De gebeurtenissen volgen dezelfde dag.
        let days = d.dayEvents(in: sep2026, asOf: day(sep2026, 1)).filter { $0.kind == .toPot || $0.kind == .toHolding }.map(\.day)
        XCTAssertEqual(days, [15, 15, 15, 15])
    }

    func testMaterializedPlansKeepTheTransferDayEmptyUnlessTheUserSetsIt() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        XCTAssertNil(d.plan(for: sep2026).transferDay)
        XCTAssertNil(d.synthesizedPlan(for: engDec2026).transferDay)
        d.editPlan(sep2026) { $0.transferDay = 7 }
        XCTAssertNil(d.synthesizedPlan(for: oct2026).transferDay, "wordt niet doorgekopieerd")
        XCTAssertNil(d.plan(for: engNov2026).transferDay)
    }

    // MARK: Saldo per dag

    // Planboekingen (salaris, huur, inleg: ze staan op 12:00) op dezelfde dag als het meetpunt gelden als al verwerkt.
    // De tests hieronder willen de huur van de 1e juist wel laten meetellen, dus hun meetpunt ligt vlak voor de 1e
    // (de dag ervoor om 23:30, `hour: -0.5`) en niet op de 1e zelf.

    func testBalanceOnEveryDayOfAMonthBeforeAndAfterPayday() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 500, date: engTime(sep2026, 1, hour: -0.5))
        XCTAssertNil(d.bankBalance(on: day(aug2026, 30)), "voor het eerste meetpunt is het saldo onbekend")
        XCTAssertEqual(d.bankBalance(on: day(aug2026, 31)) ?? .nan, 500, accuracy: 0.001, "het meetpunt zelf (31 augustus 23:30)")
        for dayNumber in 1...30 {
            // Huur (1000) op de 1e om 12:00, salaris en toeslag (3100) op de 25e.
            let expected: Double = dayNumber < 25 ? -500 : 2_600
            XCTAssertEqual(d.bankBalance(on: day(sep2026, dayNumber)) ?? .nan, expected, accuracy: 0.001, "dag \(dayNumber)")
        }
        XCTAssertEqual(d.bankBalance(at: sep2026) ?? .nan, 2_600, accuracy: 0.001)
        // Oktober: huur eraf op de 1e, salaris erbij op de 25e.
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 1)) ?? .nan, 1_600, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 24)) ?? .nan, 1_600, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 25)) ?? .nan, 4_700, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? .nan, 4_700, accuracy: 0.001)
    }

    func testSnapshotInTheMiddleOfTheMonthCountsTheRestOfThatMonth() {
        var d = makeBaseData()
        // Meetpunt op de 10e om 08:00: de huur van de 1e zit er al in, het salaris van de 25e komt erbij.
        d.addBankSnapshot(balance: 1_000, date: engTime(sep2026, 10, hour: 8))
        XCTAssertNil(d.bankBalance(on: day(sep2026, 9)))
        XCTAssertEqual(d.bankBalance(on: day(sep2026, 10)) ?? .nan, 1_000, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(sep2026, 24)) ?? .nan, 1_000, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(sep2026, 25)) ?? .nan, 4_100, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(sep2026, 30)) ?? .nan, 4_100, accuracy: 0.001)
        // Eerder bleef de hele meetmaand buiten beeld en was het saldo van eind september 1000.
        XCTAssertEqual(d.bankBalance(at: sep2026) ?? .nan, 4_100, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 1)) ?? .nan, 3_100, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 31)) ?? .nan, 6_200, accuracy: 0.001)
    }

    func testSnapshotOnTheSameDayMakesThePlannedEventsOfThatDayAlreadyProcessed() {
        // Planboekingen (huur op de 1e, salaris en toeslag op de 25e, allemaal om 12:00) op de dag van het meetpunt
        // zitten al in het ingevulde saldo, ook als het meetpunt eerder op die dag valt. Anders telt een saldo dat je
        // om 08:30 op salarisdag invult het salaris om 12:00 nog eens mee.
        for hour in [10.0, 14.0] {
            var rentDay = makeBaseData()
            rentDay.addBankSnapshot(balance: 1_000, date: engTime(sep2026, 1, hour: hour))
            XCTAssertEqual(rentDay.bankBalance(on: day(sep2026, 1)) ?? .nan, 1_000, accuracy: 0.001, "huur zit al in het saldo, meetpunt \(hour) uur")
        }
        for hour in [8.0, 18.0] {
            var payDay = makeBaseData()
            payDay.addBankSnapshot(balance: 2_000, date: engTime(sep2026, 25, hour: hour))
            XCTAssertEqual(payDay.bankBalance(on: day(sep2026, 25)) ?? .nan, 2_000, accuracy: 0.001, "salaris zit al in het saldo, meetpunt \(hour) uur")
            // De dag erna telt wat er daarna komt weer mee: oktober, huur op de 1e.
            XCTAssertEqual(payDay.bankBalance(on: day(sep2026, 30)) ?? .nan, 2_000, accuracy: 0.001)
            XCTAssertEqual(payDay.bankBalance(on: day(oct2026, 1)) ?? .nan, 1_000, accuracy: 0.001)
        }
    }

    func testBalanceAtMonthEqualsBalanceOnTheLastDay() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 500, date: engTime(sep2026, 1, hour: -0.5))
        d.addBankEntry(amount: 75.5, date: day(oct2026, 31))
        for m in sep2026.range(count: 12) {
            XCTAssertEqual(d.bankBalance(at: m), d.bankBalance(on: m.date(day: m.dayCount)), m.key)
        }
        // Een boeking op de laatste dag van de maand telt nog mee in die maand.
        XCTAssertEqual(d.bankBalance(at: oct2026) ?? .nan, 4_700 + 75.5, accuracy: 0.001)
    }

    func testBalanceNowUsesTodayInsideTheMonthAndMonthEndOutsideIt() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 500, date: engTime(sep2026, 1, hour: -0.5))
        XCTAssertEqual(d.bankBalanceNow(current: sep2026, today: day(sep2026, 24)), -500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: sep2026, today: day(sep2026, 25)), 2_600, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: sep2026, today: day(oct2026, 3)), 2_600, accuracy: 0.001, "vandaag ligt in een andere maand: eind van de maand")
        XCTAssertEqual(d.bankBalanceNow(current: aug2026, today: day(aug2026, 3)), 0, "onbekend saldo telt als 0")
    }

    // MARK: Verdeling over potten en beleggingen

    func testFutureMonthDistributionLandsInThePotOnItsTransferDay() {
        var d = makeBaseData()
        var pot = Pot(name: "Buffer", monthlyContribution: 200, startMonth: aug2026)
        pot.transferDay = 10
        d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
        XCTAssertNil(d.months[engDec2026.key], "december is nog niet vastgelegd")

        // 500 beginsaldo + inleg van 200 op de 10e van augustus, september, oktober en november.
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 9)), 1_300, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 10)), 1_500, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: engNov2026), 1_300, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: engDec2026), 1_500, accuracy: 0.001)

        let events = d.dayEvents(in: engDec2026, asOf: day(sep2026, 1)).filter { $0.kind == .toPot }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.day, 10)
        XCTAssertEqual(events.first?.bankAmount, -200)
        XCTAssertEqual(events.first?.potAmount, 200)
        XCTAssertEqual(events.first?.potID, pot.id)
        XCTAssertEqual(events.first?.isPlanned, true)

        // Een eigen bedrag voor december: ook dat komt pas op de overschrijfdag in de pot.
        d.setAllocation(pot.id, in: engDec2026, amount: 350)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 9)), 1_300, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 10)), 1_650, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: engDec2026), 1_650, accuracy: 0.001)
    }

    func testMonthTransferDayOverridesThePotDay() {
        var d = makeBaseData()
        var pot = Pot(name: "Buffer", monthlyContribution: 200, startMonth: aug2026)
        pot.transferDay = 10
        d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
        d.editPlan(engDec2026) { $0.transferDay = 20 }
        XCTAssertEqual(d.transferDay(for: pot.id, in: engDec2026), 20)
        XCTAssertEqual(d.transferDay(for: pot.id, in: engNov2026), 10)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 10)), 1_300, accuracy: 0.001, "op de dag van de pot is het nog niet overgeschreven")
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 19)), 1_300, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 20)), 1_500, accuracy: 0.001)
        XCTAssertEqual(d.dayEvents(in: engDec2026, asOf: day(sep2026, 1)).first { $0.kind == .toPot }?.day, 20)
    }

    func testAllocationWithoutOwnDayFollowsThePayDay() {
        var d = makeBaseData()
        let pot = Pot(name: "Buffer", monthlyContribution: 200, startMonth: aug2026)
        d.addPot(pot)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(sep2026, 24)), 200, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(sep2026, 25)), 400, accuracy: 0.001)
        d.salary.payDay = 3
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(sep2026, 2)), 200, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(sep2026, 3)), 400, accuracy: 0.001)
    }

    func testDistributionOverHoldingsLeavesTheBankOnItsTransferDay() {
        var d = makeBaseData()
        var holding = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, monthlyContribution: 100, startMonth: aug2026)
        holding.transferDay = 5
        d.addHolding(holding)
        d.addBankSnapshot(balance: 5_000, date: engTime(sep2026, 1, hour: -0.5))
        XCTAssertEqual(d.bankBalance(on: day(sep2026, 4)) ?? .nan, 4_000, accuracy: 0.001) // huur
        XCTAssertEqual(d.bankBalance(on: day(sep2026, 5)) ?? .nan, 3_900, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(sep2026, 25)) ?? .nan, 7_000, accuracy: 0.001)
        let event = d.dayEvents(in: sep2026, asOf: day(sep2026, 1)).first { $0.kind == .toHolding }
        XCTAssertEqual(event?.holdingID, holding.id)
        XCTAssertEqual(event?.bankAmount, -100)
        XCTAssertEqual(event?.potAmount, 0)
        XCTAssertEqual(event?.title, "Naar ETF")
    }

    // MARK: Uitgaven deels uit spaarpotten

    func testExpensePartlyFromTwoPots() {
        var (d, vakantie, buffer) = engTwoPotData()
        d.addBankSnapshot(balance: 1_000, date: engTime(oct2026, 1, hour: -0.5))
        let withoutShares = d.remaining(in: oct2026)
        XCTAssertEqual(withoutShares, 2_100, accuracy: 0.001)

        let line = MoneyLine(name: "Tandarts", amount: 300, day: 12,
                             potShares: [PotShare(potID: vakantie.id, amount: 100), PotShare(potID: buffer.id, amount: 50)])
        d.upsertLine(line, kind: .expense, in: oct2026)

        // Het totaal blijft 300, het budget van de maand krijgt alleen het deel van de bank (150) te verwerken.
        XCTAssertEqual(d.expensesTotal(in: oct2026), 1_300, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 150, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromBank(in: oct2026), 1_150, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: oct2026), 1_950, accuracy: 0.001)
        XCTAssertEqual(line.fromPots, 150, accuracy: 0.001)
        XCTAssertEqual(line.fromBank, 150, accuracy: 0.001)

        // Drie gebeurtenissen op de 12e: de bank betaalt 150, de potten 100 en 50.
        let events = d.eventsOnDay(day(oct2026, 12), asOf: day(oct2026, 1))
        XCTAssertEqual(events.map(\.title), ["Tandarts", "Tandarts (uit Buffer)", "Tandarts (uit Vakantie)"])
        XCTAssertEqual(events.map(\.bankAmount), [-150, 0, 0])
        XCTAssertEqual(events.map(\.potAmount), [0, -50, -100])
        XCTAssertEqual(events.map(\.potID), [nil, buffer.id, vakantie.id])
        XCTAssertEqual(events.map(\.kind), [.expense, .expense, .expense])
        XCTAssertTrue(events.allSatisfy { $0.lineID == line.id })
        let monthSum = d.dayEvents(in: oct2026, asOf: day(oct2026, 1)).reduce(0) { $0 + engCents($1.bankAmount) }
        XCTAssertEqual(monthSum, engCents(d.remaining(in: oct2026)), "de bank ziet precies het maandbudget")

        // De potten dalen op de uitgavedag, niet eerder.
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(oct2026, 11)), 400, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(oct2026, 12)), 300, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(buffer.id, asOf: day(oct2026, 11)), 900, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(buffer.id, asOf: day(oct2026, 12)), 850, accuracy: 0.001)
        XCTAssertEqual(d.totalSaved(asOf: day(oct2026, 12)), 1_150, accuracy: 0.001)

        // De bank krijgt het restant: huur op de 1e, 150 op de 12e, salaris op de 25e.
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 11)) ?? .nan, 0, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 12)) ?? .nan, -150, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 24)) ?? .nan, -150, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 25)) ?? .nan, 2_950, accuracy: 0.001)
    }

    func testExpenseFullyFromAPotLeavesTheBudgetAlone() {
        var (d, vakantie, _) = engTwoPotData()
        d.addBankSnapshot(balance: 1_000, date: engTime(oct2026, 1, hour: -0.5))
        let before = d.remaining(in: oct2026)
        let line = MoneyLine(name: "Fiets", amount: 200, day: 5, potShares: [PotShare(potID: vakantie.id, amount: 200)])
        d.upsertLine(line, kind: .expense, in: oct2026)

        XCTAssertEqual(d.remaining(in: oct2026), before, accuracy: 0.0001)
        XCTAssertEqual(d.expensesTotal(in: oct2026), 1_200, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 200, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromBank(in: oct2026), 1_000, accuracy: 0.001)
        // Geen bankgebeurtenis voor deze uitgave, wel een potgebeurtenis.
        let events = d.eventsOnDay(day(oct2026, 5), asOf: day(oct2026, 1))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.bankAmount, 0)
        XCTAssertEqual(events.first?.potAmount, -200)
        XCTAssertEqual(d.bankBalance(on: day(oct2026, 4)), d.bankBalance(on: day(oct2026, 5)))
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(oct2026, 4)), 400)
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(oct2026, 5)), 200)
    }

    func testPotSharesLargerThanTheAmountAreCutOffInOrder() {
        var (d, vakantie, buffer) = engTwoPotData()
        let line = MoneyLine(name: "Reparatie", amount: 100, day: 9,
                             potShares: [PotShare(potID: vakantie.id, amount: 80), PotShare(potID: buffer.id, amount: 60)])
        d.upsertLine(line, kind: .expense, in: oct2026)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 100, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromBank(in: oct2026), 1_000, accuracy: 0.001)
        XCTAssertEqual(line.fromPots, 100, accuracy: 0.001, "het model kapt ook af")
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(oct2026, 9)), 320, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(buffer.id, asOf: day(oct2026, 9)), 880, accuracy: 0.001)
        let events = d.eventsOnDay(day(oct2026, 9), asOf: day(oct2026, 1))
        XCTAssertEqual(events.reduce(0) { $0 + engCents($1.potAmount) }, -10_000, "samen precies het bedrag")
        XCTAssertEqual(events.reduce(0) { $0 + engCents($1.bankAmount) }, 0)
    }

    func testShareOfAnUnknownPotIsPaidByTheBank() {
        var d = makeBaseData()
        let line = MoneyLine(name: "Spook", amount: 100, day: 9, potShares: [PotShare(potID: UUID(), amount: 60)])
        d.upsertLine(line, kind: .expense, in: oct2026)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 0)
        XCTAssertEqual(d.expensesFromBank(in: oct2026), 1_100, accuracy: 0.001)
        XCTAssertEqual(d.eventsOnDay(day(oct2026, 9), asOf: day(oct2026, 1)).map(\.bankAmount), [-100])
    }

    // MARK: Laagste dagsaldo en dagreeks

    func testLowestBankPointOfAMonth() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 100, date: engTime(sep2026, 1, hour: -0.5))
        // September: de huur van de 1e brengt het saldo op -900; pas op de 25e komt er salaris bij.
        let sep = d.lowestBankPoint(in: sep2026)
        XCTAssertEqual(sep?.balance ?? .nan, -900, accuracy: 0.001)
        XCTAssertEqual(sep.map { engDayNumber($0.date) }, 1, "bij gelijke saldi de eerste dag")
        XCTAssertEqual(sep?.events.map(\.title), ["Huur"])
        // Oktober: 2200 - 1000 = 1200 vanaf de 1e.
        let oct = d.lowestBankPoint(in: oct2026)
        XCTAssertEqual(oct?.balance ?? .nan, 1_200, accuracy: 0.001)
        XCTAssertEqual(oct.map { engDayNumber($0.date) }, 1)
        // Voor het meetpunt (31 augustus 23:30) is er niets bekend: in augustus alleen die laatste dag.
        let aug = d.lowestBankPoint(in: aug2026)
        XCTAssertEqual(aug?.balance ?? .nan, 100, accuracy: 0.001)
        XCTAssertEqual(aug.map { engDayNumber($0.date) }, 31)
        XCTAssertNil(d.lowestBankPoint(in: YearMonth(year: 2026, month: 7)))
    }

    func testLowestBankPointStartsAtTheFirstKnownDay() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 1_000, date: engTime(sep2026, 10, hour: 8))
        let point = d.lowestBankPoint(in: sep2026)
        XCTAssertEqual(point?.balance ?? .nan, 1_000, accuracy: 0.001)
        XCTAssertEqual(point.map { engDayNumber($0.date) }, 10)
    }

    func testDailySeriesHasOnePointPerDayWithGrowingDates() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 500, date: engTime(sep2026, 1, hour: -0.5))
        let series = d.bankDailySeries(from: day(sep2026, 1), to: day(sep2026, 30), asOf: day(sep2026, 10))
        XCTAssertEqual(series.count, 30)
        for i in series.indices {
            XCTAssertEqual(engDayNumber(series[i].date), i + 1)
            XCTAssertEqual(series[i].id, series[i].date)
            if i > 0 { XCTAssertGreaterThan(series[i].date, series[i - 1].date) }
            XCTAssertEqual(series[i].balance, i < 24 ? -500 : 2_600, accuracy: 0.001, "dag \(i + 1)")
        }
        XCTAssertEqual(series[0].events.map(\.title), ["Huur"])
        XCTAssertEqual(series[0].events.first?.isPlanned, false)
        XCTAssertTrue(series[1].events.isEmpty)
        XCTAssertEqual(series[24].events.map(\.title), ["Salaris", "Toeslag"])
        XCTAssertEqual(series[24].events.first?.isPlanned, true)
    }

    func testDailySeriesStartsAtTheFirstKnownDay() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 1_000, date: engTime(sep2026, 10, hour: 8))
        let series = d.bankDailySeries(from: day(sep2026, 1), to: day(sep2026, 30), asOf: day(sep2026, 1))
        XCTAssertEqual(series.count, 21)
        XCTAssertEqual(engDayNumber(series[0].date), 10)
        XCTAssertEqual(series[0].balance, 1_000, accuracy: 0.001)
        // Zonder enig saldo geen punten.
        XCTAssertTrue(makeBaseData().bankDailySeries(from: day(sep2026, 1), to: day(sep2026, 30)).isEmpty)
    }

    func testDailySeriesIsLimitedTo800DaysAndMatchesTheDailyBalance() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 1_000, date: day(aug2026, 5))
        d.addBankEntry(amount: 40, date: day(oct2026, 14))
        let to = day(YearMonth(year: 2030, month: 1), 1)
        let series = d.bankDailySeries(from: day(aug2026, 5), to: to, asOf: day(oct2026, 8))
        XCTAssertEqual(series.count, 800)
        let cal = YearMonth.calendar
        let expectedLast = cal.date(byAdding: .day, value: 799, to: cal.startOfDay(for: day(aug2026, 5)))!
        XCTAssertTrue(cal.isDate(series.last!.date, inSameDayAs: expectedLast))
        for i in 1..<series.count {
            XCTAssertEqual(cal.dateComponents([.day], from: series[i - 1].date, to: series[i].date).day, 1, "elke dag precies één dag verder")
        }
        // Elk dagsaldo is gelijk aan de losse vraag voor die dag.
        for point in series where engDayNumber(point.date) % 7 == 0 {  // elke zevende dag van de maand
            XCTAssertEqual(point.balance, d.bankBalance(on: point.date) ?? .nan, accuracy: 0.0001)
        }
    }

    func testDailySeriesWithReversedRangeIsEmpty() {
        var d = makeBaseData()
        d.addBankSnapshot(balance: 1_000, date: day(aug2026, 5))
        XCTAssertTrue(d.bankDailySeries(from: day(sep2026, 10), to: day(sep2026, 1)).isEmpty)
        XCTAssertEqual(d.bankDailySeries(from: day(sep2026, 10), to: day(sep2026, 10)).count, 1)
    }

    // MARK: Pot en bank samen

    func testBankAndPotsTogetherOnlyChangeByIncomeAndExpenses() {
        // Geld dat van de bank naar een pot gaat verandert het totaal niet. Uitgaven uit een pot verlagen het totaal
        // net zo goed als uitgaven van de bank: per maand verandert bank + potten met inkomen min alle uitgaven.
        var (d, vakantie, buffer) = engTwoPotData()
        d.pots[0].monthlyContribution = 150
        d.pots[1].monthlyContribution = 75
        d.pots[1].transferDay = 3
        d.addBankSnapshot(balance: 1_000, date: engTime(aug2026, 1, hour: -0.5))
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 300, day: 12,
                               potShares: [PotShare(potID: vakantie.id, amount: 100), PotShare(potID: buffer.id, amount: 50)]),
                     kind: .expense, in: oct2026)

        func wealth(_ m: YearMonth) -> Int {
            let end = m.date(day: m.dayCount)
            return engCents(d.bankBalance(on: end) ?? 0) + engCents(d.totalSaved(asOf: end))
        }
        for m in sep2026.range(count: 5) {
            let delta = wealth(m) - wealth(m.adding(-1))
            let expected = engCents(d.income(in: m)) - engCents(d.expensesTotal(in: m))
            XCTAssertEqual(delta, expected, m.key)
        }
        // En de pot-saldi zelf: 400 + 150 per maand en 900 + 75 per maand (min de uitgave in oktober).
        XCTAssertEqual(d.potBalance(vakantie.id, at: oct2026), 400 + 3 * 150 - 100, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(buffer.id, at: oct2026), 900 + 3 * 75 - 50, accuracy: 0.001)
    }

    func testRecurringExpenseWithPotSharesCarriesOverToFutureMonths() {
        var (d, vakantie, _) = engTwoPotData()
        d.upsertLine(MoneyLine(name: "Abonnement", amount: 30, isRecurring: true, day: 15,
                               potShares: [PotShare(potID: vakantie.id, amount: 10)]),
                     kind: .expense, in: aug2026)
        // Januari is nog niet vastgelegd, maar kent de uitgave en haar potdeel.
        XCTAssertNil(d.months[engJan2027.key])
        XCTAssertEqual(d.expensesFromPots(in: engJan2027), 10, accuracy: 0.001)
        let events = d.eventsOnDay(day(engJan2027, 15), asOf: day(sep2026, 1))
        XCTAssertEqual(events.map(\.potAmount), [0, -10])
        // 400 min 10 voor augustus t/m januari (zes keer) op de 15e.
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(engJan2027, 14)), 400 - 5 * 10, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(vakantie.id, asOf: day(engJan2027, 15)), 400 - 6 * 10, accuracy: 0.001)
    }
}

// MARK: - Eigenschappen met willekeurige gegevens

/// Voor vaste zaadwaarden bouwen we willekeurige gegevens en controleren verbanden die altijd moeten gelden.
final class EngineConsistencyTests: XCTestCase {
    private func randomData(seed: UInt64) -> FinanceData {
        var r = EngRandom(seed: seed)
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: r.amount(1_500, 4_000), hourlyRate: 0, hoursPerWeek: 0,
                                  payDay: r.int(1...31))

        var potIDs: [UUID] = []
        for i in 0..<r.int(1...3) {
            let start = aug2026.adding(r.int(0...2))
            var pot = Pot(name: "Pot \(i)", monthlyContribution: r.chance(70) ? r.amount(0, 300) : 0, startMonth: start)
            if r.chance(50) { pot.transferDay = r.int(1...31) }
            if r.chance(60) {
                pot.interestRate = Double(r.int(5...50)) / 1_000
                pot.interestPayout = InterestPayout.allCases[r.int(0...3)]
                pot.interestPayoutDay = r.int(1...31)
                pot.interestPayoutMonth = r.int(1...12)
            }
            d.addPot(pot, openingBalance: r.amount(0, 2_000), now: day(start, r.int(1...28)))
            potIDs.append(pot.id)
        }
        for i in 0..<r.int(0...2) {
            var holding = Holding(name: "Fonds \(i)", kind: .etf, ticker: nil, units: nil,
                                  monthlyContribution: r.amount(0, 200), startMonth: aug2026)
            if r.chance(50) { holding.transferDay = r.int(1...31) }
            d.addHolding(holding)
        }

        var plan = MonthPlan()
        for i in 0..<r.int(1...5) {
            var line = MoneyLine(name: "Uitgave \(i)", amount: r.amount(5, 900), isRecurring: r.chance(70),
                                 kind: r.chance(50) ? .fixed : .variable)
            if r.chance(60) { line.day = r.int(1...31) }
            if r.chance(40) {
                line.potShares = [PotShare(potID: potIDs[r.int(0...(potIDs.count - 1))], amount: r.amount(1, 600))]
            }
            plan.expenses.append(line)
        }
        for i in 0..<r.int(0...2) {
            var line = MoneyLine(name: "Inkomen \(i)", amount: r.amount(10, 500), isRecurring: r.chance(50))
            if r.chance(50) { line.day = r.int(1...31) }
            plan.extraIncome.append(line)
        }
        d.months[aug2026.key] = plan

        // Eén meetpunt, zodat de uitkomst onafhankelijk na te rekenen is.
        d.addBankSnapshot(balance: r.amount(-500, 5_000),
                          date: day(aug2026.adding(r.int(0...2)), r.int(1...28)).addingTimeInterval(Double(r.int(-5...5)) * 3_600))
        for _ in 0..<r.int(0...4) {
            let amount = r.amount(1, 400)
            d.addBankEntry(amount: r.chance(50) ? amount : -amount, date: day(aug2026.adding(r.int(0...6)), r.int(1...28)))
        }
        if r.chance(50) { d.transferBankToPot(potID: potIDs[0], amount: r.amount(1, 300), date: day(aug2026.adding(r.int(1...5)), r.int(1...28))) }
        if r.chance(40) { d.transferPotToBank(potID: potIDs[0], amount: r.amount(1, 100), date: day(aug2026.adding(r.int(1...5)), r.int(1...28))) }
        if r.chance(50) {
            let month = aug2026.adding(r.int(2...8))
            let transfer = r.int(1...31)
            d.editPlan(month) { $0.transferDay = transfer }
        }
        if r.chance(50) {
            d.setAllocation(potIDs[0], in: aug2026.adding(r.int(1...8)), amount: r.amount(0, 500))
        }
        return d
    }

    private let seeds: [UInt64] = Array(1...40)

    /// Eigen berekening van het banksaldo uit de openbare gebeurtenissen en het ene meetpunt.
    private func independentBank(_ d: FinanceData, endOf month: YearMonth) -> Int? {
        guard let snap = d.bankSnapshots.first else { return nil }
        let limit = month.endExclusive
        guard snap.date < limit else { return nil }
        var total = engCents(snap.balance)
        // Handmatige boekingen tellen vanaf hun eigen tijdstip na het meetpunt; planboekingen pas vanaf de dag erna.
        let cal = YearMonth.calendar
        let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: snap.date)) ?? snap.date
        var m = YearMonth(date: snap.date)
        while m <= month {
            for e in d.dayEvents(in: m, asOf: .distantPast) where e.bankAmount != 0 && e.date < limit {
                let counts = e.kind == .bankEntry ? e.date > snap.date : e.date >= nextDay
                if counts { total += engCents(e.bankAmount) }
            }
            m = m.adding(1)
        }
        return total
    }

    func testBankBalanceAtMonthEqualsBalanceOnTheLastDay() {
        for seed in seeds {
            let d = randomData(seed: seed)
            for m in aug2026.range(count: 12) {
                let atMonth = d.bankBalance(at: m)
                let onLastDay = d.bankBalance(on: m.date(day: m.dayCount))
                XCTAssertEqual(atMonth, onLastDay, "seed \(seed) \(m.key)")
                XCTAssertEqual(atMonth.map(engCents), independentBank(d, endOf: m), "seed \(seed) \(m.key): onafhankelijke som")
            }
            let series = d.bankSeries(from: aug2026, count: 12, current: oct2026)
            for point in series {
                XCTAssertEqual(point.balance, d.bankBalance(at: point.month), "seed \(seed) \(point.month.key)")
            }
            let worth = d.netWorthSeries(from: aug2026, count: 12, current: oct2026)
            for point in worth {
                XCTAssertEqual(point.bank, d.bankBalance(at: point.month) ?? 0, "seed \(seed) \(point.month.key)")
            }
        }
    }

    func testDailySeriesAgreesWithTheBalanceOfEachDay() {
        for seed in seeds {
            let d = randomData(seed: seed)
            let series = d.bankDailySeries(from: day(aug2026, 1), to: day(YearMonth(year: 2027, month: 3), 31), asOf: day(oct2026, 8))
            for point in series where engDayNumber(point.date) % 3 == 0 {
                XCTAssertEqual(d.bankBalance(on: point.date), point.balance, "seed \(seed) \(point.date)")
            }
            // Het laagste punt van een maand komt uit dezelfde reeks.
            if let lowest = d.lowestBankPoint(in: oct2026) {
                let inMonth = series.filter { YearMonth(date: $0.date) == oct2026 }
                XCTAssertEqual(lowest.balance, inMonth.map(\.balance).min(), "seed \(seed)")
            }
        }
    }

    func testPotBalanceAtMonthEqualsBalanceOnTheLastDay() {
        for seed in seeds {
            let d = randomData(seed: seed)
            for pot in d.pots {
                for m in aug2026.range(count: 12) {
                    XCTAssertEqual(d.potBalance(pot.id, at: m), d.potBalance(pot.id, asOf: m.date(day: m.dayCount)), "seed \(seed) \(m.key)")
                }
            }
            let end = day(oct2026, 31)
            XCTAssertEqual(engCents(d.totalSaved(asOf: end)), d.pots.reduce(0) { $0 + engCents(d.potBalance($1.id, asOf: end)) }, "seed \(seed)")
        }
    }

    func testPotBalanceChangesExactlyByTheEventsAndManualEntries() {
        for seed in seeds {
            let d = randomData(seed: seed)
            for pot in d.pots {
                for m in sep2026.range(count: 10) {
                    let before = engCents(d.potBalance(pot.id, asOf: m.adding(-1).date(day: m.adding(-1).dayCount)))
                    let after = engCents(d.potBalance(pot.id, asOf: m.date(day: m.dayCount)))
                    let fromEvents = d.dayEvents(in: m, asOf: .distantPast)
                        .filter { $0.potID == pot.id && $0.kind != .bankEntry }
                        .reduce(0) { $0 + engCents($1.potAmount) }
                    // Handmatige boekingen (ook beginsaldo, stortingen, opnames); rente staat al in de gebeurtenissen.
                    let manual = d.potEntries
                        .filter { $0.potID == pot.id && $0.kind != .interest && YearMonth(date: $0.date) == m }
                        .reduce(0) { $0 + engCents($1.amount) }
                    XCTAssertEqual(after - before, fromEvents + manual, "seed \(seed) \(pot.name) \(m.key)")
                }
            }
        }
    }

    func testBankChangesExactlyByTheBudgetPlusManualEntries() {
        for seed in seeds {
            let d = randomData(seed: seed)
            guard let snap = d.bankSnapshots.first else { continue }
            let snapMonth = YearMonth(date: snap.date)
            for m in snapMonth.adding(1).range(count: 8) {
                guard let after = d.bankBalance(at: m), let before = d.bankBalance(at: m.adding(-1)) else { continue }
                let entries = d.bankEntries.filter { YearMonth(date: $0.date) == m }.reduce(0) { $0 + engCents($1.amount) }
                XCTAssertEqual(engCents(after) - engCents(before), engCents(d.remaining(in: m)) + entries, "seed \(seed) \(m.key)")
            }
        }
    }

    func testEventsOfAMonthAddUpToTheMonthBudget() {
        for seed in seeds {
            let d = randomData(seed: seed)
            for m in aug2026.range(count: 12) {
                let plan = d.dayEvents(in: m, asOf: .distantPast).filter { $0.kind != .bankEntry && $0.kind != .interest }
                XCTAssertEqual(plan.reduce(0) { $0 + engCents($1.bankAmount) }, engCents(d.remaining(in: m)), "seed \(seed) \(m.key)")
                let summary = d.summary(of: m, current: oct2026)
                XCTAssertEqual(engCents(summary.remaining), engCents(d.remaining(in: m)), "seed \(seed) \(m.key)")
                XCTAssertEqual(engCents(summary.fromPots), engCents(d.expensesFromPots(in: m)), "seed \(seed) \(m.key)")
                XCTAssertEqual(engCents(d.expensesFromBank(in: m)), engCents(d.expensesTotal(in: m)) - engCents(d.expensesFromPots(in: m)))
                XCTAssertEqual(d.expenseOverview(in: m).leftAfterTransfers, d.remaining(in: m), "seed \(seed) \(m.key)")
            }
            let half = d.periodSummary(.halfYear, containing: oct2026, current: oct2026)
            let sumOfMonths = half.months.reduce(0) { $0 + engCents($1.remaining) }
            XCTAssertEqual(engCents(half.remaining), sumOfMonths, "seed \(seed): periode en maanden gelijk")
        }
    }

    func testStoringInterestNeverChangesAnyBalance() {
        for seed in seeds {
            var d = randomData(seed: seed)
            let dates = [day(aug2026, 20), day(sep2026, 28), day(oct2026, 31), day(engDec2026, 15), day(engJan2027, 1),
                         day(engMar2027, 31), day(YearMonth(year: 2027, month: 9), 30), day(engJan2028, 1)]
            func snapshot() -> [Int] {
                d.pots.flatMap { pot in dates.map { engCents(d.potBalance(pot.id, asOf: $0)) } }
                    + dates.map { engCents(d.bankBalance(on: $0) ?? 0) }
            }
            let before = snapshot()
            let eventIDsBefore = d.dayEvents(in: oct2026, asOf: .distantPast).map(\.id)
            let first = d.applyDueInterest(upTo: day(YearMonth(year: 2027, month: 2), 14))
            XCTAssertEqual(snapshot(), before, "seed \(seed): opslaan verandert niets (\(first) boekingen)")
            XCTAssertEqual(d.dayEvents(in: oct2026, asOf: .distantPast).map(\.id), eventIDsBefore, "seed \(seed)")
            XCTAssertEqual(d.applyDueInterest(upTo: day(YearMonth(year: 2027, month: 2), 14)), 0, "seed \(seed): tweede keer niets")
            XCTAssertEqual(snapshot(), before)
            _ = d.applyDueInterest(upTo: day(engJan2028, 1))
            XCTAssertEqual(snapshot(), before, "seed \(seed): alles opgeslagen, nog steeds hetzelfde")
        }
    }
}
