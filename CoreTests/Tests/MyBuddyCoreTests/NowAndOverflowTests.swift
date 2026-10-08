import XCTest
@testable import MyBuddyCore

/// "Nu" tegenover "eind van de maand", het saldo op een moment (niet tot het eind van de dag) en rekenen met
/// absurd grote bedragen. Alle momenten zijn vast; niets hangt van de klok af.
final class NowAndOverflowTests: XCTestCase {
    // MARK: Hulpjes

    /// Salaris 3000 op de 8e, huur 1000 op de 8e, een pot met 100 inleg op de 8e en een meetpunt van 1000 om 08:00.
    private func morningData() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0, payDay: 8)
        var pot = Pot(name: "Spaar", monthlyContribution: 100, startMonth: oct2026)
        pot.transferDay = 8
        d.addPot(pot)
        d.upsertLine(MoneyLine(name: "Huur", amount: 1000, day: 8), kind: .expense, in: oct2026)
        d.addBankSnapshot(balance: 1000, note: "Meting", date: engTime(oct2026, 8, hour: 8))
        return (d, pot)
    }

    // MARK: Saldo van nu telt alleen wat al gebeurd is

    func testBalanceNowIgnoresEventsLaterToday() {
        let (d, pot) = morningData()
        let morning = engTime(oct2026, 8, hour: 8.5)
        // Wat de gebruiker net invulde blijft staan: de drie geplande regels van 12:00 zijn nog niet aan de beurt.
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: morning), 1000, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: morning), 0, accuracy: 0.001)
        XCTAssertEqual(d.totalSaved(current: oct2026, today: morning), 0, accuracy: 0.001)
        XCTAssertTrue(d.dayEvents(in: oct2026, asOf: morning).filter { $0.day == 8 }.allSatisfy(\.isPlanned))

        // Een seconde voor 12:00 is het nog hetzelfde.
        let almost = engTime(oct2026, 8, hour: 12).addingTimeInterval(-1)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: almost), 1000, accuracy: 0.001)

        // Op 12:00 zelf zijn ze aan de beurt: 1000 + 3000 - 1000 - 100 naar de pot.
        let noon = engTime(oct2026, 8, hour: 12)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: noon), 2900, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: noon), 100, accuracy: 0.001)
        XCTAssertTrue(d.dayEvents(in: oct2026, asOf: noon).filter { $0.day == 8 }.allSatisfy { !$0.isPlanned })
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: engTime(oct2026, 8, hour: 23)), 2900, accuracy: 0.001)
    }

    func testEndOfDayVariantsStillCountTheWholeDay() {
        let (d, pot) = morningData()
        let morning = engTime(oct2026, 8, hour: 8.5)
        // `bankBalance(on:)` en `potBalance(_:asOf:)` zijn bedoeld voor grafieken: het saldo aan het EIND van de dag.
        XCTAssertEqual(d.bankBalance(on: morning) ?? -1, 2900, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, asOf: morning), 100, accuracy: 0.001)
        // En het saldo op het moment zelf kan ook rechtstreeks.
        XCTAssertEqual(d.bankBalance(atMoment: morning) ?? -1, 1000, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, atMoment: morning), 0, accuracy: 0.001)
    }

    func testBalanceNowOutsideTheCurrentMonthIsTheEndOfThatMonth() {
        let (d, pot) = morningData()
        // Vandaag ligt in een andere maand dan `current`: het saldo aan het eind van `current`.
        let december = day(engDec2026, 3)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: december), d.bankBalance(at: oct2026) ?? -1, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: december), 2900, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: december), 100, accuracy: 0.001)
    }

    func testMomentBeforeTheFirstMeasurementIsZero() {
        let (d, _) = morningData()
        XCTAssertNil(d.bankBalance(atMoment: engTime(oct2026, 8, hour: 7)))
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: engTime(oct2026, 8, hour: 7)), 0)
        // Het meetpunt zelf telt vanaf zijn eigen tijdstip.
        XCTAssertEqual(d.bankBalance(atMoment: engTime(oct2026, 8, hour: 8)) ?? -1, 1000, accuracy: 0.001)
    }

    func testEventAtTheFirstInstantOfAMonthIsFound() {
        // Een handmatige boeking op het allereerste moment van november hoort bij november, ook als je daar precies
        // op meet. (De grens van de maanden die worden opgebouwd is een fractie vóór het meetmoment.)
        var d = FinanceData(startMonth: oct2026)
        d.addBankSnapshot(balance: 2000, note: "Start", date: engTime(oct2026, 1, hour: 8))
        let first = engNov2026.firstDay
        d.addBankEntry(amount: 500, note: "Middernacht", date: first)
        XCTAssertEqual(d.bankBalance(atMoment: first) ?? -1, 2500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: first), 2500, accuracy: 0.001)
        XCTAssertEqual(d.bankBalance(atMoment: first.addingTimeInterval(-1)) ?? -1, 2000, accuracy: 0.001)
    }

    func testMomentBoundaryHelpers() {
        let t = engTime(oct2026, 8, hour: 12)
        let limit = DayMath.limit(including: t)
        XCTAssertGreaterThan(limit, t)
        XCTAssertFalse(limit > t.addingTimeInterval(0.001), "alleen een boeking op exact `t` valt erbinnen")
        XCTAssertLessThan(DayMath.lastMoment(before: limit), limit)
        XCTAssertEqual(DayMath.lastMoment(before: limit), t)
    }

    /// Het saldo van nu is het meetpunt plus precies de gebeurtenissen die `dayEvents` niet "gepland" noemt.
    func testBalanceNowMatchesNonPlannedDayEvents() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2800, hourlyRate: 0, hoursPerWeek: 0, payDay: 8)
        var pot = Pot(name: "Spaar", monthlyContribution: 100, startMonth: oct2026)
        pot.transferDay = 10
        pot.interestRate = 0.02
        pot.interestPayout = .monthly
        pot.interestPayoutDay = 12
        d.addPot(pot, openingBalance: 1_200, now: day(oct2026, 1))
        d.upsertLine(MoneyLine(name: "Huur", amount: 800, day: 1), kind: .expense, in: oct2026)
        d.upsertLine(MoneyLine(name: "Abonnement", amount: 30, day: 15), kind: .expense, in: oct2026)
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 200, day: 20, potShares: [PotShare(potID: pot.id, amount: 120)]),
                     kind: .expense, in: oct2026)
        d.upsertLine(MoneyLine(name: "Teruggave", amount: 250, day: 15), kind: .income, in: oct2026)
        let snapshotDate = engTime(oct2026, 1, hour: 8)
        d.addBankSnapshot(balance: 1_000, note: "Meting", date: snapshotDate)
        d.addBankEntry(amount: 40, note: "Contant erbij", date: engTime(oct2026, 12, hour: 9.5))

        let moments: [Date] = [
            engTime(oct2026, 1, hour: 8), engTime(oct2026, 1, hour: 11.99), engTime(oct2026, 1, hour: 12),
            engTime(oct2026, 8, hour: 11.9), engTime(oct2026, 8, hour: 12), engTime(oct2026, 8, hour: 12).addingTimeInterval(1),
            engTime(oct2026, 10, hour: 12), engTime(oct2026, 12, hour: 9.4), engTime(oct2026, 12, hour: 9.5),
            engTime(oct2026, 12, hour: 9.6), engTime(oct2026, 12, hour: 12), engTime(oct2026, 15, hour: 0),
            engTime(oct2026, 15, hour: 12), engTime(oct2026, 20, hour: 11), engTime(oct2026, 20, hour: 13),
            engTime(oct2026, 31, hour: 23.9)
        ]
        for t in moments {
            let events = d.dayEvents(in: oct2026, asOf: t).filter { !$0.isPlanned && $0.date > snapshotDate }
            let expectedBank = 100_000 + events.reduce(0) { $0 + engCents($1.bankAmount) }
            XCTAssertEqual(engCents(d.bankBalanceNow(current: oct2026, today: t)), expectedBank, "bank op \(t)")

            let potEvents = d.dayEvents(in: oct2026, asOf: t).filter { !$0.isPlanned && $0.potID == pot.id }
            // Het beginsaldo van 1200 staat op 1 oktober 12:00.
            let opening = t >= day(oct2026, 1) ? 120_000 : 0
            let expectedPot = opening + potEvents.reduce(0) { $0 + engCents($1.potAmount) }
            XCTAssertEqual(engCents(d.potBalanceNow(pot.id, current: oct2026, today: t)), expectedPot, "pot op \(t)")
            XCTAssertEqual(engCents(d.totalSaved(current: oct2026, today: t)), expectedPot, "totaal op \(t)")
        }
    }

    // MARK: Vermogen van nu

    private func netWorthData() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let pot = Pot(name: "Spaar", monthlyContribution: 200, startMonth: oct2026)
        d.addPot(pot, openingBalance: 500, now: day(oct2026, 1))
        d.addBankSnapshot(balance: 2000, note: "Meting", date: engTime(oct2026, 1, hour: 8))
        return (d, pot)
    }

    func testNetWorthNowLeavesOutWhatStillHasToCome() {
        let (d, pot) = netWorthData()
        let now = netWorthDate(10)
        let point = d.netWorthNow(current: oct2026, today: now)
        // Voor de 25e: de bank staat op het meetpunt (2000) en de pot op zijn beginsaldo (500).
        XCTAssertEqual(point.bank, 2000, accuracy: 0.001)
        XCTAssertEqual(point.pots, 500, accuracy: 0.001)
        XCTAssertEqual(point.investments, 0, accuracy: 0.001)
        XCTAssertEqual(point.total, 2500, accuracy: 0.001)
        XCTAssertFalse(point.isProjected)
        XCTAssertEqual(point.month, oct2026)
        XCTAssertEqual(point.pots, d.totalSaved(current: oct2026, today: now), accuracy: 0.001)
        XCTAssertEqual(point.bank, d.bankBalanceNow(current: oct2026, today: now), accuracy: 0.001)

        // Het eind van de maand heeft de salarisdag al gehad: 2000 + 3000 - 200 naar de pot, pot 500 + 200.
        let end = d.netWorth(at: oct2026, current: oct2026)
        XCTAssertEqual(end.bank, 4800, accuracy: 0.001)
        XCTAssertEqual(end.pots, 700, accuracy: 0.001)
        XCTAssertEqual(end.total, 5500, accuracy: 0.001)
        _ = pot
    }

    func testNetWorthNowCatchesUpOnSalaryDay() {
        let (d, _) = netWorthData()
        XCTAssertEqual(d.netWorthNow(current: oct2026, today: netWorthDate(25)).total, 5500, accuracy: 0.001)
        // Buiten de maand is "nu" het eind van `current`.
        XCTAssertEqual(d.netWorthNow(current: oct2026, today: day(engDec2026, 1)).total, 5500, accuracy: 0.001)
        // Zonder gegevens is het vermogen 0.
        XCTAssertEqual(FinanceData(startMonth: oct2026).netWorthNow(current: oct2026, today: netWorthDate(10)).total, 0)
    }

    /// 12:00 plaatselijke tijd. (`day(_:_:)` telt uren op en komt op 25 oktober, als de klok terug gaat, een uur te vroeg uit.)
    private func netWorthDate(_ dayNumber: Int) -> Date { oct2026.date(day: dayNumber) }

    // MARK: Geschiedenis van een pot

    func testTimelineMarksPlannedItemsAndSumsToNowAndToMonthEnd() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Spaar", monthlyContribution: 200, startMonth: oct2026)
        pot.interestRate = 0.024
        pot.interestPayout = .monthly
        pot.interestPayoutDay = 20
        d.addPot(pot, openingBalance: 1_000, now: day(oct2026, 1))
        d.addPotEntry(potID: pot.id, amount: -50, kind: .withdrawal, note: "Pinnen", date: day(oct2026, 5))
        d.upsertLine(MoneyLine(name: "Fiets", amount: 90, day: 12, potShares: [PotShare(potID: pot.id, amount: 90)]),
                     kind: .expense, in: oct2026)

        let today = day(oct2026, 15)
        let items = d.potTimeline(pot.id, current: oct2026, asOf: today)
        let planned = items.filter(\.isPlanned)
        // Rente van de 20e en de inleg van de 25e liggen nog voor ons.
        XCTAssertEqual(Set(planned.map(\.kind)), [.interest, .allocation])
        XCTAssertTrue(planned.allSatisfy { $0.date > today })
        XCTAssertTrue(items.filter { !$0.isPlanned }.allSatisfy { $0.date <= today })

        let now = items.filter { !$0.isPlanned }.reduce(0) { $0 + engCents($1.amount) }
        XCTAssertEqual(now, engCents(d.potBalanceNow(pot.id, current: oct2026, today: today)))
        XCTAssertEqual(now, 86_000, "1000 - 50 - 90")
        let all = items.reduce(0) { $0 + engCents($1.amount) }
        XCTAssertEqual(all, engCents(d.potBalance(pot.id, at: oct2026)))
    }

    func testTimelineWithoutAsOfStillBuildsTheSameItems() {
        let (d, vakantie, _) = engTwoPotData()
        let a = d.potTimeline(vakantie.id, current: oct2026, asOf: day(engDec2026, 1))
        XCTAssertTrue(a.allSatisfy { !$0.isPlanned })
        XCTAssertEqual(a.map(\.id), d.potTimeline(vakantie.id, current: oct2026).map(\.id))
    }

    // MARK: Voortgang en doelen met "nu"

    func testProgressUsesNowOnlyWhenTodayIsGiven() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Spaar", monthlyContribution: 200, startMonth: oct2026)
        pot.goalAmount = 1_000
        d.addPot(pot, openingBalance: 400, now: day(oct2026, 1))
        let today = day(oct2026, 10)
        // Zonder `today`: eind van de maand (400 + 200). Met `today`: nu (400).
        XCTAssertEqual(d.potProgress(pot.id, current: oct2026) ?? -1, 0.6, accuracy: 0.0001)
        XCTAssertEqual(d.potProgress(pot.id, current: oct2026, today: today) ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(d.potProgress(pot.id, current: oct2026, today: oct2026.date(day: 25)) ?? -1, 0.6, accuracy: 0.0001)
        XCTAssertEqual(d.savedTowardGoals(current: oct2026), 600, accuracy: 0.001)
        XCTAssertEqual(d.savedTowardGoals(current: oct2026, today: today), 400, accuracy: 0.001)
        // Een pot zonder doel heeft geen voortgang.
        let plain = Pot(name: "Zonder", startMonth: oct2026)
        d.addPot(plain)
        XCTAssertNil(d.potProgress(plain.id, current: oct2026, today: today))
    }

    // MARK: Saldo zetten op het moment van nu

    func testSetBalanceAsOfNowMeasuresAgainstWhatTheUserSees() {
        var (d, pot) = morningData()
        let morning = engTime(oct2026, 8, hour: 8.5)
        // De gebruiker ziet 0 (de inleg van 12:00 moet nog komen) en vult 50 in.
        d.setPotBalance(pot.id, to: 50, current: oct2026, note: "Geteld", date: morning, asOf: morning)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: morning), 50, accuracy: 0.001)
        XCTAssertEqual(d.potEntries.last?.amount ?? 0, 50, accuracy: 0.001)
        // De geplande inleg komt er om 12:00 gewoon bij.
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: engTime(oct2026, 8, hour: 12)), 150, accuracy: 0.001)
        // Nog eens hetzelfde invullen verandert niets.
        let count = d.potEntries.count
        d.setPotBalance(pot.id, to: 50, current: oct2026, date: morning, asOf: morning)
        XCTAssertEqual(d.potEntries.count, count)
    }

    func testSetBalanceWithoutAsOfKeepsMeasuringAtMonthEnd() {
        var (d, pot) = morningData()
        // Eind oktober staat de pot op 100. Zonder `asOf` is dat het uitgangspunt.
        d.setPotBalance(pot.id, to: 100, current: oct2026)
        XCTAssertTrue(d.potEntries.isEmpty)
        d.setPotBalance(pot.id, to: 130, current: oct2026, date: engTime(oct2026, 9, hour: 9))
        XCTAssertEqual(d.potEntries.last?.amount ?? 0, 30, accuracy: 0.001)
    }

    // MARK: Uitgaven en potdelen: wat de motor boekt

    func testEngineSplitDiffersFromModelHelperForUnknownAndNegativeShares() {
        let (d, pot) = morningData()
        let ghost = UUID()
        let line = MoneyLine(name: "Tandarts", amount: 300,
                             potShares: [PotShare(potID: ghost, amount: 100), PotShare(potID: pot.id, amount: 40)])
        // De bank betaalt het deel van een pot die niet bestaat.
        XCTAssertEqual(d.fromPots(of: line), 40, accuracy: 0.001)
        XCTAssertEqual(d.fromBank(of: line), 260, accuracy: 0.001)
        XCTAssertEqual(line.fromPots, 140, accuracy: 0.001, "het model telt het onbekende deel wel mee")

        let negative = MoneyLine(name: "Raar", amount: 100,
                                 potShares: [PotShare(potID: pot.id, amount: 100), PotShare(potID: pot.id, amount: -50)])
        XCTAssertEqual(d.fromPots(of: negative), 100, accuracy: 0.001)
        XCTAssertEqual(d.fromBank(of: negative), 0, accuracy: 0.001)
        XCTAssertEqual(negative.fromPots, 50, accuracy: 0.001)

        // Delen die samen meer zijn dan het bedrag worden afgekapt; een regel zonder delen komt helemaal van de bank.
        let big = MoneyLine(name: "Groot", amount: 80, potShares: [PotShare(potID: pot.id, amount: 500)])
        XCTAssertEqual(d.fromPots(of: big), 80, accuracy: 0.001)
        XCTAssertEqual(d.fromBank(of: big), 0, accuracy: 0.001)
        XCTAssertEqual(d.fromPots(of: MoneyLine(name: "Gewoon", amount: 25)), 0)
        XCTAssertEqual(d.fromBank(of: MoneyLine(name: "Gewoon", amount: 25)), 25, accuracy: 0.001)
    }

    func testMonthBudgetAgreesWithTheEngineSplit() {
        var (d, pot) = morningData()
        let line = MoneyLine(name: "Tandarts", amount: 300,
                             potShares: [PotShare(potID: UUID(), amount: 100), PotShare(potID: pot.id, amount: 40)])
        d.upsertLine(line, kind: .expense, in: oct2026)
        // Huur 1000 (bank) + tandarts 300, waarvan 40 uit de pot: 1260 van de bank.
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 40, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromBank(in: oct2026), 1260, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), d.fromPots(of: line), accuracy: 0.001)
    }

    // MARK: Eerste maand voor rente

    func testInterestStartsInThePotsStartMonthOrTheDataStart() {
        let early = Pot(name: "Oud", startMonth: aug2026)
        let late = Pot(name: "Nieuw", startMonth: engNov2026)
        XCTAssertEqual(InterestRules.firstMonth(for: early, dataStart: oct2026), oct2026, "de gegevens beginnen later")
        XCTAssertEqual(InterestRules.firstMonth(for: late, dataStart: oct2026), engNov2026)
        XCTAssertEqual(InterestRules.firstMonth(for: early, dataStart: aug2026), aug2026)
    }

    // MARK: Absurd grote bedragen

    func testSaturatingAdditionNeverTraps() {
        XCTAssertEqual(CentsMath.add(2, 3), 5)
        XCTAssertEqual(CentsMath.add(-2, 3), 1)
        XCTAssertEqual(CentsMath.add(CentsMath.limit, CentsMath.limit), CentsMath.limit)
        XCTAssertEqual(CentsMath.add(-CentsMath.limit, -CentsMath.limit), -CentsMath.limit)
        XCTAssertEqual(CentsMath.add(Int.max, Int.max), CentsMath.limit)
        XCTAssertEqual(CentsMath.add(Int.min, Int.min), -CentsMath.limit)
        XCTAssertEqual(CentsMath.add(Int.max, Int.min + 1), 0)
        XCTAssertEqual(CentsMath.sum([1, 2, 3, -4]), 2)
        XCTAssertEqual(CentsMath.sum([Int](repeating: CentsMath.limit, count: 5_000)), CentsMath.limit)
        XCTAssertEqual(CentsMath.sum([Int]()), 0)
        XCTAssertEqual(CentsMath.int(1e300), CentsMath.limit)
        XCTAssertEqual(CentsMath.int(-1e300), -CentsMath.limit)
        XCTAssertEqual(CentsMath.int(.nan), 0)
        XCTAssertEqual(CentsMath.int(.infinity), 0)
    }

    func testAbsurdMonthKeysAreIgnoredInsteadOfCrashing() {
        XCTAssertNil(YearMonth(key: "999999999999999999-01"))
        XCTAssertNil(YearMonth(key: "10000-01"))
        XCTAssertEqual(YearMonth(key: "9999-12")?.year, 9_999)
        XCTAssertEqual(YearMonth(key: "0001-01")?.year, 1)
        var d = FinanceData(startMonth: oct2026)
        d.months["999999999999999999-01"] = MonthPlan()
        d.months["kapot"] = MonthPlan()
        d.addPot(Pot(name: "Spaar", monthlyContribution: 50, startMonth: oct2026), openingBalance: 100)
        d.materialize(upTo: oct2026)
        XCTAssertEqual(d.potBalance(d.pots[0].id, at: oct2026), 150, accuracy: 0.001)
        XCTAssertEqual(d.monthFigures(oct2026.adding(1)).saved, 5_000)
    }

    func testHugeMonthlyContributionWithInterestDoesNotCrash() {
        // Een tikfout van 14 cijfers: 10 biljoen per maand met 5% rente en een doel dat nooit gehaald wordt.
        // Eerder ging dit mis met een rekenfout (overflow) in de rente-som.
        var d = FinanceData(startMonth: aug2026)
        var pot = Pot(name: "Reuze", monthlyContribution: 1e13, startMonth: aug2026)
        pot.interestRate = 0.05
        pot.interestPayout = .yearly
        pot.goalAmount = 1e30
        d.addPot(pot)
        d.materialize(upTo: oct2026)
        XCTAssertNil(d.potGoalMonth(pot.id, current: oct2026))
        let balance = d.potBalance(pot.id, at: oct2026.adding(600))
        XCTAssertTrue(balance.isFinite)
        XCTAssertLessThanOrEqual(balance, 9e13 + 1, "begrensd op het maximum van de rekenmotor")
        XCTAssertTrue(d.totalSaved(current: oct2026, today: day(oct2026, 10)).isFinite)
        XCTAssertTrue(d.netWorthNow(current: oct2026, today: day(oct2026, 10)).total.isFinite)
        _ = d.netWorthSeries(from: aug2026, count: 60, current: oct2026)
        _ = d.potTimeline(pot.id, current: oct2026)
    }

    func testHugeAmountsEverywhereStayFinite() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 1e300, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        // Honderden regels van 1e14 euro: de totalen lopen tegen het maximum aan maar crashen niet.
        let lines = (0..<2_000).map { MoneyLine(name: "Regel \($0)", amount: 1e14) }
        d.editPlan(oct2026) { $0.expenses = lines; $0.extraIncome = lines }
        let p1 = Pot(name: "A", monthlyContribution: 1e15, startMonth: aug2026)
        let p2 = Pot(name: "B", monthlyContribution: 1e15, startMonth: aug2026)
        d.addPot(p1, openingBalance: 1e15)
        d.addPot(p2, openingBalance: 1e15)
        d.addBankSnapshot(balance: 1e15, note: "Reus", date: day(aug2026, 3))
        d.materialize(upTo: oct2026)
        let f = d.monthFigures(oct2026)
        XCTAssertEqual(f.expenses, CentsMath.limit)
        XCTAssertEqual(f.income, CentsMath.limit)
        XCTAssertTrue(d.remaining(in: oct2026).isFinite)
        XCTAssertTrue(d.summary(of: oct2026, current: oct2026).remaining.isFinite)
        XCTAssertTrue(d.periodSummary(.year, containing: oct2026, current: oct2026).remaining.isFinite)
        XCTAssertTrue(d.expenseOverview(in: oct2026).leftAfterTransfers.isFinite)
        XCTAssertTrue((d.bankBalance(at: oct2026.adding(120)) ?? 0).isFinite)
        XCTAssertTrue(d.bankDailySeries(from: day(oct2026, 1), to: day(oct2026, 31)).allSatisfy { $0.balance.isFinite })
        XCTAssertTrue(d.potBalance(p1.id, at: oct2026.adding(240)).isFinite)
        XCTAssertTrue(d.totalSaved(current: oct2026, today: day(oct2026, 10)).isFinite)
        XCTAssertTrue(d.averageMonthlyExpenses(current: oct2026).isFinite)
        XCTAssertTrue(d.bankSurplusAboveBuffer(current: oct2026, today: day(oct2026, 10)).isFinite)
        d.spreadRemainingOverPots(in: oct2026)
        XCTAssertNotNil(d.lowestBankPoint(in: oct2026))
    }
}
