import XCTest
import Foundation
@testable import MyBuddyCore

// Herstelronde: bank en dagen.
//
// - Zonder ingevuld saldo (alleen handmatige boekingen) telt de dag van de eerste boeking helemaal per kalenderdag: het saldo
//   aan het eind van die dag is wat de dag zelf aan geld ziet komen en gaan.
// - Een pot verwijderen en het saldo naar de bank terugboeken laat de dag niet "naar spaarpotten" tonen terwijl het saldo van
//   de potten niet beweegt; vermogen verandert er niet door.
// - "Saldo van nu" is nil zolang het onbekend is (een meetpunt in de toekomst geeft nog geen saldo).
// - Een uurloon met een halve cent in het product rondt half omhoog, zoals een rekenmachine.

final class RecoveryBankTests: XCTestCase {
    // MARK: Zonder meetpunt

    func testWithoutASnapshotTheDayOfTheFirstEntryCountsCompletely() {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 10)
        d.upsertLine(MoneyLine(name: "Abonnement", amount: 10, isRecurring: true, day: 10), kind: .expense, in: engNov2026)
        // De eerste boeking komt om 15:00, ná het salaris en het abonnement van 12:00 van dezelfde dag.
        d.addBankEntry(amount: 1_000, note: "Storting", date: engTime(engNov2026, 10, hour: 15))
        let today = engTime(engNov2026, 20, hour: 9)
        let ledger = d.monthLedger(engNov2026, asOf: today)
        let tenth = ledger.days[9]
        XCTAssertEqual(tenth.planInflow, 3_000)
        XCTAssertEqual(tenth.manualInflow, 1_000)
        XCTAssertEqual(tenth.outflow, 10)
        XCTAssertNil(tenth.openingBank)
        // Het saldo aan het eind van de dag is wat de dag zelf laat zien: 3000 + 1000 - 10.
        XCTAssertEqual(tenth.bankBalance, 3_990)
        XCTAssertEqual(d.bankBalance(on: engTime(engNov2026, 10, hour: 12)), 3_990)
        XCTAssertEqual(d.bankBalance(atMoment: engTime(engNov2026, 10, hour: 16)), 3_990)
        XCTAssertEqual(d.dayTotals(on: engTime(engNov2026, 10, hour: 12), asOf: today).bankBalance, 3_990)
        // Vóór de eerste boeking is er nog geen saldo, ook niet om 09:00 op diezelfde dag.
        XCTAssertNil(d.bankBalance(atMoment: engTime(engNov2026, 10, hour: 9)))
        XCTAssertNil(ledger.days[8].bankBalance)
        // Daarna loopt het gewoon door.
        XCTAssertEqual(ledger.days[10].bankBalance, 3_990)
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertTrue(ledger.days.allSatisfy { $0.bankReconciles })
        // De maand erna begint met dit saldo en sluit ook.
        let december = d.monthLedger(engDec2026, asOf: today)
        XCTAssertEqual(december.openingBank, ledger.closingBank)
        XCTAssertTrue(december.allReconciles)
    }

    /// Een boeking vroeg op de dag (voor het salaris van 12:00) geeft hetzelfde als eerder: alles van de dag telt.
    func testFirstEntryEarlyInTheDayGivesTheSameBalance() {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 10)
        d.addBankEntry(amount: 1_000, note: "Storting", date: engTime(engNov2026, 10, hour: 8.5))
        XCTAssertEqual(d.bankBalance(on: engTime(engNov2026, 10, hour: 12)), 4_000)
        // Plan van een eerdere dag telt niet mee: er was nog geen saldo.
        XCTAssertNil(d.bankBalance(on: engTime(engNov2026, 9, hour: 12)))
    }

    // MARK: Saldo van nu onbekend

    func testBankBalanceNowIsUnknownWithOnlyAFutureSnapshot() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.addBankSnapshot(balance: 5_000, note: "Straks", date: engTime(engNov2026, 2, hour: 9))
        let today = engTime(oct2026, 14, hour: 10)
        XCTAssertTrue(d.hasBankBalance)
        XCTAssertFalse(d.hasBankBalanceNow(current: oct2026, today: today))
        XCTAssertNil(d.bankBalanceNowIfKnown(current: oct2026, today: today))
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: today), 0)
        XCTAssertNil(d.bankBalance(atMoment: today))
        XCTAssertEqual(d.bankSurplusAboveBuffer(current: oct2026, today: today), 0)
        // Zodra het meetpunt er is, is het saldo bekend.
        let later = engTime(engNov2026, 3, hour: 10)
        XCTAssertTrue(d.hasBankBalanceNow(current: engNov2026, today: later))
        XCTAssertEqual(d.bankBalanceNowIfKnown(current: engNov2026, today: later), 5_000)
        XCTAssertEqual(d.bankBalanceNow(current: engNov2026, today: later), 5_000)
        // Een andere maand dan die van vandaag: het saldo aan het eind van die maand.
        XCTAssertEqual(d.bankBalanceNowIfKnown(current: engDec2026, today: later), d.bankBalance(at: engDec2026))
    }

    // MARK: Een pot verwijderen met terugboeken

    func testDeletingAPotAndReturningTheBalanceKeepsTheDayHonest() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Vakantie", monthlyContribution: 300, startMonth: oct2026)
        pot.transferDay = 5
        d.addPot(pot, openingBalance: 200, now: engTime(oct2026, 1, hour: 9))
        d.addBankSnapshot(balance: 4_000, note: "Start", date: engTime(oct2026, 1, hour: 9))
        let today = engTime(oct2026, 14, hour: 10)
        let worthBefore = d.netWorthNow(current: oct2026, today: today)
        let potBefore = d.potBalanceNow(pot.id, current: oct2026, today: today)
        XCTAssertEqual(potBefore, 500)
        d.deletePot(pot.id, returningBalanceToBank: true, current: oct2026, today: today)
        XCTAssertTrue(d.pots.isEmpty)
        // Het vermogen verandert niet door het verwijderen.
        XCTAssertEqual(d.netWorthNow(current: oct2026, today: today).total, worthBefore.total, accuracy: 0.001)
        let ledger = d.monthLedger(oct2026, asOf: today)
        let fourteenth = ledger.days[13]
        XCTAssertEqual(fourteenth.toPots, 0, "de dag toont geen overboeking naar spaarpotten van een pot die er niet meer is")
        XCTAssertEqual(fourteenth.potsTotal, 0)
        XCTAssertGreaterThanOrEqual(fourteenth.manualInflow, 500)
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertTrue(ledger.days.allSatisfy { $0.bankReconciles && $0.potsReconciles })
        XCTAssertEqual(ledger.manualToPots, 0)
        XCTAssertEqual(d.bankBalance(on: engTime(oct2026, 14, hour: 20)), fourteenth.bankBalance)
    }

    /// Een overboeking naar een pot die er nog is, blijft "naar spaarpotten" (de potkant staat in het saldo van de potten).
    func testTransferToAnExistingPotStillCountsAsToPots() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let pot = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot, openingBalance: 0, now: engTime(oct2026, 1, hour: 9))
        d.addBankSnapshot(balance: 1_000, note: "Start", date: engTime(oct2026, 1, hour: 9))
        d.transferBankToPot(potID: pot.id, amount: 150, date: engTime(oct2026, 10, hour: 10))
        let ledger = d.monthLedger(oct2026, asOf: engTime(oct2026, 14, hour: 10))
        XCTAssertEqual(ledger.days[9].toPots, 150)
        XCTAssertEqual(ledger.days[9].manualOutflow, 0)
        XCTAssertEqual(ledger.days[9].potsTotal, 150)
        XCTAssertTrue(ledger.allReconciles)
    }

    // MARK: Afronden van uurloon

    func testHourlyPayRoundsHalfCentsUpLikeACalculator() {
        // 55,94 x 10,75 uur x 3 weken = 1804,065: 1804,07 (voorheen 1804,06 door kommagetallen).
        var s = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 55.94, hoursPerWeek: 10.75, payDay: 25)
        s.setSchedule(.weeks, interval: 3, anchor: nil)
        XCTAssertEqual(s.payoutAmount(), 1_804.07)
        // Om de 21 dagen is hetzelfde als om de 3 weken.
        var days = s
        days.setSchedule(.days, interval: 21, anchor: nil)
        XCTAssertEqual(days.payoutAmount(), 1_804.07)
        // Uren van een maand: 21,55 x 123,5 = 2661,425: 2661,43.
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 21.55, hoursPerWeek: 36, payDay: 25)
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        d.editPlan(oct2026) { $0.hoursOverride = 123.5 }
        let payouts = d.salaryPayouts(in: oct2026, plan: d.plan(for: oct2026))
        XCTAssertEqual(payouts.reduce(0) { $0 + $1.cents }, 266_143)
        // Het maandelijkse schema blijft zoals het altijd rekende (de oude formule).
        var monthly = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 55.94, hoursPerWeek: 10.75, payDay: 25)
        XCTAssertEqual(monthly.payoutAmount(), (55.94 * (10.75 * 52 / 12)).cents)
        monthly.setSchedule(.monthly, interval: 1, anchor: nil)
        XCTAssertEqual(monthly.monthlyAmount(), (55.94 * (10.75 * 52 / 12)).cents)
    }

    /// Tegen een berekening met gehele getallen (centen x kwartieren): elke uitbetaling klopt op de cent.
    func testHourlyPayMatchesIntegerArithmetic() {
        var r = EngRandom(seed: 515_151)
        for i in 0..<20_000 {
            let rateCents = r.int(500...9_000)
            let quarters = r.int(0...200)        // uren per week in kwartieren
            let n = r.int(1...52)
            var s = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: Double(rateCents) / 100,
                                   hoursPerWeek: Double(quarters) / 4, payDay: 25)
            if i % 2 == 0 {
                s.setSchedule(.weeks, interval: n, anchor: nil)
                // uurloon in centen x kwartieren x weken / 4, half omhoog
                let expected = (rateCents * quarters * n + 2) / 4
                XCTAssertEqual(engCents(s.payoutAmount()), expected, "weken: \(rateCents) x \(Double(quarters) / 4) x \(n)")
            } else {
                let days = r.int(1...366)
                s.setSchedule(.days, interval: days, anchor: nil)
                // uurloon in centen x kwartieren x dagen / 7 / 4, half omhoog
                let expected = (rateCents * quarters * days * 2 + 28) / 56
                XCTAssertEqual(engCents(s.payoutAmount()), expected, "dagen: \(rateCents) x \(Double(quarters) / 4) x \(days)/7")
            }
        }
    }

    // MARK: Snelheid van de machine

    /// De snelheidstests schalen hun grenzen met deze factor (zie `MachineSpeed`): minstens 1.
    func testMachineSpeedCalibrationIsSane() {
        print("MachineSpeed: rekenklus \(MachineSpeed.measuredSeconds) s, richttijd \(MachineSpeed.referenceSeconds) s, factor \(MachineSpeed.slowdown)")
        XCTAssertGreaterThanOrEqual(MachineSpeed.slowdown, 1)
        XCTAssertEqual(MachineSpeed.limit(2), 2 * MachineSpeed.slowdown, accuracy: 1e-12)
    }
}
