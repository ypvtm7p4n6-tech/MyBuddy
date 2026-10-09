import XCTest
@testable import MyBuddyCore

/// De dagboekhouding (`dayTotals`, `monthLedger`) met voorbeelden die met de hand zijn uitgerekend.
/// Alle momenten zijn vast; niets hangt van de klok af. (Oktober valt af voor tijdstippen: op 25 oktober verzet de klok.)
final class LedgerTests: XCTestCase {
    // MARK: Hulpjes

    private func cents(_ value: Double) -> Int { engCents(value) }

    private func assertDay(_ ledger: MonthLedger, _ number: Int, in: Double = 0, out: Double = 0, toPots: Double = 0,
                           toHoldings: Double = 0, fromPots: Double = 0, interest: Double = 0, bank: Double?, pots: Double,
                           remaining: Double, file: StaticString = #filePath, line: UInt = #line) {
        let day = ledger.days[number - 1]
        let at = "dag \(number)"
        XCTAssertEqual(day.day, number, at, file: file, line: line)
        XCTAssertEqual(cents(day.inflow), cents(`in`), "inflow \(at)", file: file, line: line)
        XCTAssertEqual(cents(day.outflow), cents(out), "outflow \(at)", file: file, line: line)
        XCTAssertEqual(cents(day.toPots), cents(toPots), "toPots \(at)", file: file, line: line)
        XCTAssertEqual(cents(day.toHoldings), cents(toHoldings), "toHoldings \(at)", file: file, line: line)
        XCTAssertEqual(cents(day.paidFromPots), cents(fromPots), "paidFromPots \(at)", file: file, line: line)
        XCTAssertEqual(cents(day.interest), cents(interest), "interest \(at)", file: file, line: line)
        XCTAssertEqual(day.bankBalance.map { cents($0) }, bank.map { cents($0) }, "banksaldo \(at)", file: file, line: line)
        XCTAssertEqual(cents(day.potsTotal), cents(pots), "potten \(at)", file: file, line: line)
        XCTAssertEqual(cents(day.remainingSoFar), cents(remaining), "te verdelen \(at)", file: file, line: line)
        XCTAssertTrue(day.bankReconciles, "bank sluit \(at)", file: file, line: line)
        XCTAssertTrue(day.potsReconciles, "potten sluiten \(at)", file: file, line: line)
    }

    // MARK: November: salaris op de 25e, huur op de 1e, uitgave deels uit een pot, inleg naar twee potten, rente, storting

    /// Start oktober 2026. Salaris 3000 op de 25e. Twee potten, Vakantie (beginsaldo 1200, 2,4% per jaar, elke maand
    /// op de 1e uitgekeerd) en Buffer (beginsaldo 800), die op de 26e 120 en 80 krijgen. Huur 900 op de 1e. Tandarts
    /// 100 op de 10e, waarvan 40 uit Vakantie. Banksaldo 2000 aan het eind van 31 oktober. Een storting van 50 op de
    /// 14e en een overboeking van 30 van de bank naar Buffer op de 20e.
    private func novemberData() -> (data: FinanceData, vakantie: Pot, buffer: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var vakantie = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: oct2026)
        vakantie.interestRate = 0.024
        vakantie.interestPayout = .monthly
        vakantie.interestPayoutDay = 1
        vakantie.transferDay = 26
        var buffer = Pot(name: "Buffer", monthlyContribution: 0, startMonth: oct2026)
        buffer.transferDay = 26
        d.addPot(vakantie, openingBalance: 1_200, now: day(oct2026, 1))
        d.addPot(buffer, openingBalance: 800, now: day(oct2026, 1))
        d.setAllocation(vakantie.id, in: engNov2026, amount: 120)
        d.setAllocation(buffer.id, in: engNov2026, amount: 80)
        d.upsertLine(MoneyLine(name: "Huur", amount: 900, day: 1), kind: .expense, in: engNov2026)
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 100, kind: .variable, day: 10,
                               potShares: [PotShare(potID: vakantie.id, amount: 40)]), kind: .expense, in: engNov2026)
        d.addBankSnapshot(balance: 2_000, note: "Eind oktober", date: engTime(oct2026, 31, hour: 20))
        d.addBankEntry(amount: 50, note: "Contant erbij", date: engTime(engNov2026, 14, hour: 10))
        d.transferBankToPot(potID: buffer.id, amount: 30, date: engTime(engNov2026, 20, hour: 9))
        return (d, vakantie, buffer)
    }

    func testNovemberEveryDayMatchesTheHandCalculation() {
        let (d, vakantie, buffer) = novemberData()
        let today = engTime(engNov2026, 30, hour: 20)
        let ledger = d.monthLedger(engNov2026, asOf: today)
        XCTAssertEqual(ledger.days.count, 30)
        XCTAssertEqual(ledger.month, engNov2026)

        // Rente: 2,4% / 12 van het saldo van 1 oktober (1200) = 2,40, uitgekeerd op 1 november (gerekend vanaf de eerste
        // oktober, de maand die de uitkering van de 1e meeneemt).
        XCTAssertEqual(cents(d.potBalance(vakantie.id, asOf: day(engNov2026, 1)) - d.potBalance(vakantie.id, asOf: day(oct2026, 31))), 240)

        // Bank: 2000 -> huur 900 (1e) -> 1100 -> tandarts 60 van de bank (10e) -> 1040 -> storting 50 (14e) -> 1090
        // -> naar Buffer 30 (20e) -> 1060 -> salaris 3000 (25e) -> 4060 -> inleg 200 (26e) -> 3860.
        // Potten: 2000 -> +2,40 rente (1e) -> 2002,40 -> -40 tandarts (10e) -> 1962,40 -> +30 (20e) -> 1992,40 -> +200 (26e) -> 2192,40.
        // Te verdelen: -900 (1e), -960 (10e), +3000 -> 2040 (25e), -200 -> 1840 (26e).
        assertDay(ledger, 1, out: 900, interest: 2.40, bank: 1_100, pots: 2_002.40, remaining: -900)
        for number in 2...9 { assertDay(ledger, number, bank: 1_100, pots: 2_002.40, remaining: -900) }
        assertDay(ledger, 10, out: 60, fromPots: 40, bank: 1_040, pots: 1_962.40, remaining: -960)
        for number in 11...13 { assertDay(ledger, number, bank: 1_040, pots: 1_962.40, remaining: -960) }
        assertDay(ledger, 14, in: 50, bank: 1_090, pots: 1_962.40, remaining: -960)
        for number in 15...19 { assertDay(ledger, number, bank: 1_090, pots: 1_962.40, remaining: -960) }
        assertDay(ledger, 20, toPots: 30, bank: 1_060, pots: 1_992.40, remaining: -960)
        for number in 21...24 { assertDay(ledger, number, bank: 1_060, pots: 1_992.40, remaining: -960) }
        assertDay(ledger, 25, in: 3_000, bank: 4_060, pots: 1_992.40, remaining: 2_040)
        assertDay(ledger, 26, toPots: 200, bank: 3_860, pots: 2_192.40, remaining: 1_840)
        for number in 27...30 { assertDay(ledger, number, bank: 3_860, pots: 2_192.40, remaining: 1_840) }

        // De geplande en handmatige delen apart.
        XCTAssertEqual(cents(ledger.days[13].manualInflow), 5_000)
        XCTAssertEqual(cents(ledger.days[13].planInflow), 0)
        XCTAssertEqual(cents(ledger.days[24].planInflow), 300_000)
        XCTAssertEqual(cents(ledger.days[19].manualToPots), 3_000)
        XCTAssertEqual(cents(ledger.days[19].planToPots), 0)
        XCTAssertEqual(cents(ledger.days[19].potEntriesNet), 3_000, "de pot krijgt de 30 van de overboeking")
        XCTAssertEqual(cents(ledger.days[25].planToPots), 20_000)
        XCTAssertEqual(cents(ledger.days[25].manualToPots), 0)
        XCTAssertEqual(cents(ledger.days[9].planOutflow), 6_000, "alleen het bankdeel van de tandarts")
        XCTAssertEqual(cents(ledger.days[9].paidFromPots), 4_000)

        // Begin- en eindsaldo van elke dag hangen aan elkaar.
        XCTAssertEqual(ledger.days[0].openingBank, 2_000)
        XCTAssertEqual(ledger.days[25].openingBank, 4_060)
        XCTAssertEqual(cents(ledger.days[0].openingPots), 200_000)
        XCTAssertEqual(cents(ledger.days[25].openingPots), 199_240)

        // De gebeurtenissen van de dag.
        XCTAssertEqual(ledger.days[0].events.map(\.kind), [.interest, .expense])
        XCTAssertEqual(ledger.days[9].events.map(\.title), ["Tandarts", "Tandarts (uit Vakantie)"])
        XCTAssertEqual(ledger.days[13].events.map(\.kind), [.bankEntry])
        XCTAssertEqual(ledger.days[24].events.map(\.kind), [.salary])
        XCTAssertEqual(ledger.days[25].events.map(\.title), ["Naar Buffer", "Naar Vakantie"])
        XCTAssertTrue(ledger.days[1].events.isEmpty)
        XCTAssertFalse(ledger.days[1].hasActivity)
        XCTAssertTrue(ledger.days[0].hasActivity)
        XCTAssertTrue(ledger.days[19].hasActivity, "een overboeking is activiteit")

        // De maand.
        XCTAssertEqual(ledger.openingBank, 2_000)
        XCTAssertEqual(ledger.closingBank, 3_860)
        XCTAssertEqual(cents(ledger.openingPots), 200_000)
        XCTAssertEqual(cents(ledger.closingPots), 219_240)
        XCTAssertEqual(cents(ledger.inflow), 305_000)
        XCTAssertEqual(cents(ledger.outflow), 96_000)
        XCTAssertEqual(cents(ledger.toPots), 23_000)
        XCTAssertEqual(ledger.toHoldings, 0)
        XCTAssertEqual(cents(ledger.paidFromPots), 4_000)
        XCTAssertEqual(cents(ledger.interest), 240)
        XCTAssertEqual(cents(ledger.potEntriesNet), 3_000)
        XCTAssertEqual(ledger.income, 3_000)
        XCTAssertEqual(ledger.expensesTotal, 1_000)
        XCTAssertEqual(ledger.remaining, 1_840)
        XCTAssertEqual(ledger.planInflow, 3_000)
        XCTAssertEqual(ledger.manualInflow, 50)
        XCTAssertEqual(ledger.planOutflow, 960)
        XCTAssertEqual(ledger.manualOutflow, 0)
        XCTAssertEqual(ledger.planToPots, 200)
        XCTAssertEqual(ledger.manualToPots, 30)
        XCTAssertEqual(ledger.bankCorrections, 0)
        XCTAssertEqual(ledger.saved, 200)
        XCTAssertEqual(ledger.invested, 0)
        XCTAssertEqual(ledger.expensesFromBank, 960)
        XCTAssertEqual(ledger.expensesFromPots, 40)
        // 2000 + 3050 - 960 - 230 = 3860 en 2000 + 200 + 30 + 2,40 - 40 = 2192,40.
        XCTAssertTrue(ledger.bankReconciles)
        XCTAssertTrue(ledger.potsReconciles)
        XCTAssertTrue(ledger.overviewReconciles)
        XCTAssertTrue(ledger.allReconciles)

        // Dezelfde cijfers elders in de motor: banksaldo, potten, vermogen en het maandoverzicht.
        XCTAssertEqual(d.bankBalance(at: engNov2026), 3_860)
        XCTAssertEqual(d.bankBalance(on: day(engNov2026, 14)), 1_090)
        XCTAssertEqual(d.potBalance(vakantie.id, at: engNov2026), 1_282.40, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(buffer.id, at: engNov2026), 910, accuracy: 0.001)
        XCTAssertEqual(d.totalSaved(asOf: day(engNov2026, 30)), 2_192.40, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: engNov2026), 1_840)
        let summary = d.summary(of: engNov2026, current: engNov2026)
        XCTAssertEqual(summary.income, 3_000)
        XCTAssertEqual(summary.expenses, 1_000)
        XCTAssertEqual(summary.fromPots, 40)
        XCTAssertEqual(summary.saved, 200)
        XCTAssertEqual(summary.remaining, 1_840)
        let worth = d.netWorth(at: engNov2026, current: engNov2026)
        XCTAssertEqual(worth.bank, 3_860)
        XCTAssertEqual(worth.pots, 2_192.40, accuracy: 0.001)

        // Eén dag los is dezelfde dag uit de maand.
        XCTAssertEqual(d.dayTotals(on: day(engNov2026, 26), asOf: today), ledger.days[25])
        XCTAssertEqual(d.dayTotals(on: engTime(engNov2026, 26, hour: 3), asOf: today), ledger.days[25])
    }

    func testNovemberTodayMarksAndTheBalancesOfNow() {
        let (d, vakantie, buffer) = novemberData()
        let today = engTime(engNov2026, 12, hour: 15)
        let ledger = d.monthLedger(engNov2026, asOf: today)
        for dayTotals in ledger.days {
            XCTAssertEqual(dayTotals.isToday, dayTotals.day == 12, "vandaag \(dayTotals.day)")
            XCTAssertEqual(dayTotals.isPlanned, dayTotals.day > 12, "gepland \(dayTotals.day)")
            XCTAssertTrue(dayTotals.events.allSatisfy { $0.isPlanned == dayTotals.isPlanned })
        }
        // Wat nu op de rekening en in de potten staat, is wat het dagboek voor vandaag zegt: 1040 en 1962,40.
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: today), 1_040)
        XCTAssertEqual(ledger.days[11].bankBalance, 1_040)
        XCTAssertEqual(d.totalSaved(current: engNov2026, today: today), 1_962.40, accuracy: 0.001)
        XCTAssertEqual(ledger.days[11].potsTotal, 1_962.40, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(vakantie.id, current: engNov2026, today: today), 1_162.40, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(buffer.id, current: engNov2026, today: today), 800, accuracy: 0.001)
        XCTAssertEqual(d.netWorthNow(current: engNov2026, today: today).total, 1_040 + 1_962.40, accuracy: 0.001)
        // De bedragen hangen niet van "vandaag" af, alleen de vlaggen.
        let later = d.monthLedger(engNov2026, asOf: engTime(engNov2026, 30, hour: 20))
        XCTAssertEqual(later.days.map(\.bankBalance), ledger.days.map(\.bankBalance))
        XCTAssertEqual(later.days.map(\.potsTotal), ledger.days.map(\.potsTotal))
        XCTAssertEqual(later.days.map(\.inflow), ledger.days.map(\.inflow))
        // Op de laatste dag van de maand is het saldo van nu het saldo van het eind van de maand.
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: engTime(engNov2026, 30, hour: 20)), 3_860)
        XCTAssertEqual(d.totalSaved(current: engNov2026, today: engTime(engNov2026, 30, hour: 20)), 2_192.40, accuracy: 0.001)
    }

    func testRemainingSoFarOnTheLastDayIsTheRemainingOfTheMonth() {
        let (d, _, _) = novemberData()
        let ledger = d.monthLedger(engNov2026, asOf: day(engNov2026, 12))
        XCTAssertEqual(ledger.days[29].remainingSoFar, d.remaining(in: engNov2026))
        XCTAssertEqual(ledger.days[29].remainingSoFar, ledger.remaining)
        // Een handmatige storting of overboeking verandert de te verdelen niet (dat is het plan).
        XCTAssertEqual(ledger.days[13].remainingSoFar, ledger.days[12].remainingSoFar)
        XCTAssertEqual(ledger.days[19].remainingSoFar, ledger.days[18].remainingSoFar)
    }

    // MARK: December: ingevuld saldo midden in de maand, overboeking van pot naar bank, beleggingen

    /// Start december 2026, salaris 2500 op de 25e. Pot Reserve (beginsaldo 500, 100 op de 5e), belegging 150 op de 5e,
    /// huur 800 (1e, terugkerend), boodschappen 60 (12e). Saldo 1000 om 08:00 op de 1e (bevat de huur al), een storting
    /// van 20 op de 3e, 25 gepind op de 12e om 09:00, een saldo van 700 om 18:00 op de 12e, en om 20:00 40 van Reserve naar de bank.
    private func decemberData() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: engDec2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_500, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Reserve", monthlyContribution: 100, startMonth: engDec2026)
        pot.transferDay = 5
        d.addPot(pot, openingBalance: 500, now: engTime(engDec2026, 1, hour: 7))
        var etf = Holding(name: "Wereld", kind: .etf, monthlyContribution: 150, startMonth: engDec2026)
        etf.transferDay = 5
        d.holdings.append(etf)
        d.upsertLine(MoneyLine(name: "Huur", amount: 800, isRecurring: true, day: 1), kind: .expense, in: engDec2026)
        d.upsertLine(MoneyLine(name: "Boodschappen", amount: 60, kind: .variable, day: 12), kind: .expense, in: engDec2026)
        d.addBankSnapshot(balance: 1_000, note: "Begin", date: engTime(engDec2026, 1, hour: 8))
        d.addBankEntry(amount: 20, note: "Cadeau", date: engTime(engDec2026, 3, hour: 10))
        d.addBankEntry(amount: -25, note: "Pinnen", date: engTime(engDec2026, 12, hour: 9))
        d.addBankSnapshot(balance: 700, note: "Gecontroleerd", date: engTime(engDec2026, 12, hour: 18))
        d.transferPotToBank(potID: pot.id, amount: 40, date: engTime(engDec2026, 12, hour: 20))
        return (d, pot)
    }

    func testDecemberSnapshotInTheMiddleOfTheMonthAddsACorrection() {
        let (d, pot) = decemberData()
        let ledger = d.monthLedger(engDec2026, asOf: engTime(engDec2026, 31, hour: 20))
        XCTAssertEqual(ledger.days.count, 31)

        // Dag 1: het saldo van 1000 om 08:00 bevat de huur van die dag al; dit is de eerste dag met een saldo.
        assertDay(ledger, 1, out: 800, bank: 1_000, pots: 500, remaining: -800)
        XCTAssertNil(ledger.days[0].openingBank, "voor de eerste meting is er geen saldo")
        XCTAssertEqual(cents(ledger.days[0].potEntriesNet), 50_000, "het beginsaldo van de pot")
        assertDay(ledger, 2, bank: 1_000, pots: 500, remaining: -800)
        assertDay(ledger, 3, in: 20, bank: 1_020, pots: 500, remaining: -800)
        assertDay(ledger, 4, bank: 1_020, pots: 500, remaining: -800)
        // Dag 5: 100 naar de pot en 150 naar de belegging: -250.
        assertDay(ledger, 5, toPots: 100, toHoldings: 150, bank: 770, pots: 600, remaining: -1_050)
        for number in 6...11 { assertDay(ledger, number, bank: 770, pots: 600, remaining: -1_050) }
        // Dag 12: boodschappen 60 (plan) en 25 gepind (09:00, zit al in het saldo van 18:00), 40 van de pot naar de bank
        // (20:00, komt erbij). Wat de app verwachtte voor 18:00: 770 - 60 - 25 = 685; ingevuld 700: correctie +15.
        // Eind van de dag: 700 + 40 = 740.
        assertDay(ledger, 12, out: 85, toPots: -40, bank: 740, pots: 560, remaining: -1_110)
        XCTAssertEqual(cents(ledger.days[11].bankCorrection), 1_500)
        XCTAssertEqual(ledger.days[11].openingBank, 770)
        XCTAssertEqual(cents(ledger.days[11].manualOutflow), 2_500)
        XCTAssertEqual(cents(ledger.days[11].planOutflow), 6_000)
        XCTAssertEqual(cents(ledger.days[11].manualToPots), -4_000)
        XCTAssertEqual(cents(ledger.days[11].potEntriesNet), -4_000)
        XCTAssertEqual(cents(ledger.days[11].bankChange), -3_000, "700 + 40 - 770")
        XCTAssertTrue(ledger.days[11].toPots < 0, "meer van de pot naar de bank dan andersom")
        for number in 13...24 { assertDay(ledger, number, bank: 740, pots: 560, remaining: -1_110) }
        assertDay(ledger, 25, in: 2_500, bank: 3_240, pots: 560, remaining: 1_390)
        for number in 26...31 { assertDay(ledger, number, bank: 3_240, pots: 560, remaining: 1_390) }
        XCTAssertEqual(ledger.days.filter { $0.bankCorrection != 0 }.map(\.day), [12], "alleen op de dag van het ingevulde saldo")

        // De maand. Het beginsaldo is niet bekend (de eerste meting is op de 1e), dus sluit de bank vanaf de 2e.
        XCTAssertNil(ledger.openingBank)
        XCTAssertEqual(ledger.closingBank, 3_240)
        XCTAssertEqual(ledger.openingPots, 0)
        XCTAssertEqual(ledger.closingPots, 560)
        XCTAssertEqual(ledger.inflow, 2_520)
        XCTAssertEqual(ledger.outflow, 885)
        XCTAssertEqual(ledger.toPots, 60)
        XCTAssertEqual(ledger.toHoldings, 150)
        XCTAssertEqual(ledger.potEntriesNet, 460)
        XCTAssertEqual(ledger.bankCorrections, 15)
        XCTAssertEqual(ledger.income, 2_500)
        XCTAssertEqual(ledger.expensesTotal, 860)
        XCTAssertEqual(ledger.remaining, 1_390)
        XCTAssertEqual(ledger.invested, 150)
        XCTAssertTrue(ledger.allReconciles)

        // Dezelfde saldi uit de rest van de motor.
        XCTAssertEqual(d.bankBalance(on: day(engDec2026, 12)), 740)
        XCTAssertEqual(d.bankBalance(on: day(engDec2026, 11)), 770)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(engDec2026, 12)), 560)
        XCTAssertEqual(d.bankBalance(at: engDec2026), 3_240)
    }

    func testTheMonthAfterContinuesFromTheClosingBalances() {
        let (d, pot) = decemberData()
        let december = d.monthLedger(engDec2026, asOf: engTime(engDec2026, 31, hour: 20))
        let january = d.monthLedger(engJan2027, asOf: engTime(engDec2026, 31, hour: 20))
        // De huur is terugkerend; het salaris en de inleg komen weer. Boodschappen was eenmalig.
        XCTAssertEqual(january.openingBank, december.closingBank)
        XCTAssertEqual(january.openingPots, december.closingPots)
        XCTAssertEqual(january.inflow, 2_500)
        XCTAssertEqual(january.outflow, 800)
        XCTAssertEqual(january.toPots, 100)
        XCTAssertEqual(january.toHoldings, 150)
        XCTAssertEqual(january.remaining, 1_450)
        // 3240 + 2500 - 800 - 100 - 150 = 4690 en 560 + 100 = 660.
        XCTAssertEqual(january.closingBank, 4_690)
        XCTAssertEqual(january.closingPots, 660)
        XCTAssertTrue(january.allReconciles)
        XCTAssertEqual(january.days.filter { $0.isPlanned }.count, 31, "alles ligt na vandaag")
        XCTAssertEqual(january.days[0].openingBank, 3_240)
        XCTAssertEqual(january.days[4].toPots, 100)
        XCTAssertEqual(january.days[4].toHoldings, 150)
        XCTAssertEqual(d.potBalance(pot.id, at: engJan2027), 660)
        // Vóór de eerste meting is er geen saldo, ook niet in november.
        let november = d.monthLedger(engNov2026, asOf: engTime(engDec2026, 31, hour: 20))
        XCTAssertNil(november.openingBank)
        XCTAssertNil(november.closingBank)
        XCTAssertTrue(november.days.allSatisfy { $0.bankBalance == nil })
        XCTAssertTrue(november.days.allSatisfy { $0.inflow == 0 && $0.outflow == 0 && $0.toPots == 0 && $0.toHoldings == 0 })
        XCTAssertTrue(november.allReconciles)
        XCTAssertEqual(november.closingPots, 0)
    }

    // MARK: Zonder meting: alleen handmatige boekingen

    func testWithoutASnapshotTheFirstManualEntryStartsTheBalance() {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.addBankEntry(amount: 100, note: "Storting", date: engTime(engNov2026, 25, hour: 8.5))
        let ledger = d.monthLedger(engNov2026, asOf: engTime(engNov2026, 30, hour: 20))
        XCTAssertTrue(ledger.days[..<24].allSatisfy { $0.bankBalance == nil })
        // Er is niets gemeten, dus het salaris van 12:00 komt na het begin van het saldo en telt mee.
        assertDay(ledger, 25, in: 3_100, bank: 3_100, pots: 0, remaining: 3_000)
        XCTAssertNil(ledger.days[24].openingBank)
        XCTAssertEqual(ledger.days[24].manualInflow, 100)
        XCTAssertEqual(ledger.days[24].planInflow, 3_000)
        assertDay(ledger, 26, bank: 3_100, pots: 0, remaining: 3_000)
        XCTAssertEqual(ledger.closingBank, 3_100)
        XCTAssertNil(ledger.openingBank)
        XCTAssertTrue(ledger.allReconciles)
    }

    func testWithoutAnyBalanceTheFlowsAreStillShown() {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.upsertLine(MoneyLine(name: "Huur", amount: 900, day: 1), kind: .expense, in: engNov2026)
        let ledger = d.monthLedger(engNov2026, asOf: day(engNov2026, 10))
        XCTAssertTrue(ledger.days.allSatisfy { $0.bankBalance == nil })
        XCTAssertEqual(ledger.days[0].outflow, 900)
        XCTAssertEqual(ledger.days[24].inflow, 3_000)
        XCTAssertEqual(ledger.remaining, 2_100)
        XCTAssertEqual(ledger.days[29].remainingSoFar, 2_100)
        XCTAssertNil(ledger.openingBank)
        XCTAssertNil(ledger.closingBank)
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: day(engNov2026, 10)), 0)
    }

    // MARK: Korte maanden en dagen die niet bestaan

    func testDaysThatDoNotExistFallOnTheLastDayOfShortMonths() {
        var d = FinanceData(startMonth: engJan2028)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 31)
        var pot = Pot(name: "Spaar", monthlyContribution: 50, startMonth: engJan2028)
        pot.transferDay = 30
        d.addPot(pot)
        d.upsertLine(MoneyLine(name: "Abonnement", amount: 10, isRecurring: true, day: 31), kind: .expense, in: engJan2028)
        d.addBankSnapshot(balance: 100, note: "Begin", date: engTime(engJan2028, 1, hour: 0.5))
        // Februari 2028 heeft 29 dagen: salaris, abonnement en inleg vallen allemaal op de 29e.
        let february = d.monthLedger(engFeb2028, asOf: day(engJan2028, 15))
        XCTAssertEqual(february.days.count, 29)
        XCTAssertEqual(february.days[28].inflow, 2_000)
        XCTAssertEqual(february.days[28].outflow, 10)
        XCTAssertEqual(february.days[28].toPots, 50)
        XCTAssertEqual(february.days[27].inflow, 0)
        XCTAssertTrue(february.allReconciles)
        // Een jaar later heeft februari er 28.
        let february2029 = d.monthLedger(YearMonth(year: 2029, month: 2), asOf: day(engJan2028, 15))
        XCTAssertEqual(february2029.days.count, 28)
        XCTAssertEqual(february2029.days[27].inflow, 2_000)
        XCTAssertTrue(february2029.allReconciles)
        // April heeft er 30: de inleg van de 30e en het salaris van de 31e vallen allebei op de 30e.
        let april = d.monthLedger(YearMonth(year: 2028, month: 4), asOf: day(engJan2028, 15))
        XCTAssertEqual(april.days.count, 30)
        XCTAssertEqual(april.days[29].inflow, 2_000)
        XCTAssertEqual(april.days[29].toPots, 50)
        XCTAssertTrue(april.allReconciles)
        // En de laatste dag van elke maand van drie jaar is er altijd.
        for month in engJan2028.range(count: 36) {
            let ledger = d.monthLedger(month, asOf: day(engJan2028, 15))
            XCTAssertEqual(ledger.days.count, month.dayCount)
            XCTAssertEqual(ledger.days.last?.day, month.dayCount)
            XCTAssertTrue(ledger.allReconciles, month.key)
        }
    }

    func testMonthsBeforeTheStartHaveNoPlan() {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.addPot(Pot(name: "Spaar", monthlyContribution: 100, startMonth: engNov2026), openingBalance: 250, now: day(oct2026, 5))
        let before = d.monthLedger(oct2026, asOf: day(engNov2026, 10))
        XCTAssertTrue(before.days.allSatisfy { $0.inflow == 0 && $0.outflow == 0 && $0.toPots == 0 && $0.remainingSoFar == 0 })
        XCTAssertEqual(before.income, 0)
        XCTAssertEqual(before.remaining, 0)
        XCTAssertEqual(before.days[3].potsTotal, 0)
        XCTAssertEqual(before.days[4].potsTotal, 250, "het beginsaldo van de pot, op de 5e")
        XCTAssertEqual(before.closingPots, 250)
        XCTAssertTrue(before.allReconciles)
        XCTAssertTrue(before.days.allSatisfy { $0.isToday == false && $0.isPlanned == false })
    }

    // MARK: Voorbeelddata

    func testSampleDataReconcilesEveryMonth() {
        let now = YearMonth(year: 2026, month: 10).date(day: 15)
        let d = FinanceData.sample(now: now)
        let current = YearMonth(date: now)
        for month in d.startMonth.range(count: 6 + 14) {
            let ledger = d.monthLedger(month, asOf: now)
            XCTAssertTrue(ledger.bankReconciles, "bank \(month.key)")
            XCTAssertTrue(ledger.potsReconciles, "potten \(month.key)")
            XCTAssertTrue(ledger.overviewReconciles, "overzicht \(month.key)")
            XCTAssertEqual(ledger.remaining, d.remaining(in: month))
        }
        // De voorbeelddata heeft een beginsaldo, dus een banksaldo op elke dag vanaf de start.
        let ledger = d.monthLedger(current, asOf: now)
        XCTAssertTrue(ledger.days.allSatisfy { $0.bankBalance != nil })
        XCTAssertEqual(ledger.days[14].bankBalance, d.bankBalanceNow(current: current, today: now))
        XCTAssertEqual(ledger.days[14].potsTotal, d.totalSaved(current: current, today: now), accuracy: 0.001)
        XCTAssertGreaterThan(ledger.paidFromPots, 0, "de tandarts komt deels uit de buffer")
    }

    // MARK: Snelheid

    /// Vijf jaar, 10 potten (de helft met maandelijkse rente), 8 beleggingen, 30 uitgaven: één maand duurt in een
    /// debug-build ongeveer 10 ms. De grens is ruim (een vlotte machine zit er ver onder): hij moet alleen een
    /// kwadratische herberekening per dag (zoals `bankBalance(on:)` per dag) of per maand geschiedenis betrappen.
    func testMonthLedgerStaysFastOverFiveYears() {
        let (d, current) = ledgerPerformanceData()
        let today = current.date(day: 10)
        let months = [current, current.adding(-30), current.adding(-58), current.adding(3)]
        var worst = 0.0
        for month in months {
            var times: [Double] = []
            var ledger: MonthLedger?
            for _ in 0..<5 {
                let start = Date()
                ledger = d.monthLedger(month, asOf: today)
                times.append(Date().timeIntervalSince(start))
            }
            times.sort()
            worst = max(worst, times[2])
            XCTAssertEqual(ledger?.days.count, month.dayCount)
            XCTAssertEqual(ledger?.allReconciles, true, month.key)
        }
        XCTAssertLessThan(worst, 0.060, "mediaan van 5 keer, per maand (richtwaarde 15 ms op een gewone machine)")
        // Een heel jaar achter elkaar.
        let start = Date()
        for month in current.adding(-11).range(count: 12) { _ = d.monthLedger(month, asOf: today) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
