import XCTest
@testable import MyBuddyCore

/// `isEmptyStart` bepaalt of de welkomstkaart met "Voorbeelddata" verschijnt. Die knop overschrijft alles,
/// dus zodra de gebruiker zelf iets heeft ingevuld mag de kaart niet meer verschijnen.
final class EmptyStartTests: XCTestCase {
    private func assertFilled(_ d: FinanceData, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(d.isEmptyStart, "\(what) telt als ingevuld", file: file, line: line)
    }

    func testFreshDataIsAnEmptyStart() {
        XCTAssertTrue(FinanceData(startMonth: oct2026).isEmptyStart)
    }

    func testMonthsMaterializedByTheAppAreStillEmpty() {
        var d = FinanceData(startMonth: aug2026)
        d.materialize(upTo: oct2026)
        XCTAssertEqual(d.months.count, 3, "de app legde drie lege maanden vast")
        XCTAssertTrue(d.isEmptyStart)
        // Ook een maand die met `editPlan` is geopend maar leeg bleef.
        d.editPlan(oct2026) { _ in }
        XCTAssertTrue(d.isEmptyStart)
    }

    func testChangedSettingsAloneAreNotContent() {
        var d = FinanceData(startMonth: oct2026)
        d.settings.inflation = 0.031
        d.settings.savingsRate = 0.025
        d.settings.lastMarketUpdate = day(oct2026, 3)
        d.settings.blockOrder = ["home": ["pots", "overview"]]
        XCTAssertTrue(d.isEmptyStart)
    }

    func testOnlyExpensesIsNotEmpty() {
        var d = FinanceData(startMonth: oct2026)
        d.upsertLine(MoneyLine(name: "Huur", amount: 900), kind: .expense, in: oct2026)
        assertFilled(d, "alleen een uitgave")
        // Ook als de app er daarna lege maanden naast legt.
        d.materialize(upTo: YearMonth(year: 2027, month: 2))
        assertFilled(d, "een uitgave met lege maanden ernaast")
    }

    func testOnlyExtraIncomeIsNotEmpty() {
        var d = FinanceData(startMonth: oct2026)
        d.upsertLine(MoneyLine(name: "Bijbaan", amount: 200), kind: .income, in: oct2026)
        assertFilled(d, "alleen extra inkomen")
    }

    func testOnlyAnAllocationIsNotEmpty() {
        var d = FinanceData(startMonth: oct2026)
        d.editPlan(oct2026) { $0.allocations[UUID().uuidString] = 50 }
        assertFilled(d, "alleen een verdeling")
    }

    func testMonthOverridesCount() {
        var salaryOverride = FinanceData(startMonth: oct2026)
        salaryOverride.editPlan(oct2026) { $0.salaryOverride = 2_900 }
        assertFilled(salaryOverride, "een eigen salaris voor een maand")
        var hours = FinanceData(startMonth: oct2026)
        hours.editPlan(oct2026) { $0.hoursOverride = 120 }
        assertFilled(hours, "gewerkte uren")
        var transfer = FinanceData(startMonth: oct2026)
        transfer.editPlan(oct2026) { $0.transferDay = 3 }
        assertFilled(transfer, "een eigen overschrijfdag")
    }

    func testEntriesCount() {
        var bankEntry = FinanceData(startMonth: oct2026)
        bankEntry.addBankEntry(amount: 50, date: day(oct2026, 3))
        assertFilled(bankEntry, "een bankboeking")

        var potEntry = FinanceData(startMonth: oct2026)
        potEntry.potEntries.append(PotEntry(potID: UUID(), date: day(oct2026, 3), amount: 10, kind: .deposit))
        assertFilled(potEntry, "een potboeking")

        var snapshot = FinanceData(startMonth: oct2026)
        snapshot.addBankSnapshot(balance: 100, date: day(oct2026, 3))
        assertFilled(snapshot, "een banksaldo")
    }

    func testObjectsCount() {
        var pot = FinanceData(startMonth: oct2026)
        pot.addPot(Pot(name: "Buffer", monthlyContribution: 0, startMonth: oct2026))
        assertFilled(pot, "een spaarpot")

        var holding = FinanceData(startMonth: oct2026)
        holding.addHolding(Holding(name: "Fonds", kind: .etf, ticker: nil, units: nil, monthlyContribution: 0, startMonth: oct2026))
        assertFilled(holding, "een belegging")

        var goal = FinanceData(startMonth: oct2026)
        goal.addGoal(LifeGoal(name: "Pensioen", kind: .retirement))
        assertFilled(goal, "een doel")

        var accelerator = FinanceData(startMonth: oct2026)
        accelerator.appliedAccelerators.append(AppliedAccelerator(acceleratorID: "free", title: "Extra inleg", date: day(oct2026, 3)))
        assertFilled(accelerator, "een toegepaste versneller")
    }

    func testSalaryCounts() {
        var fixed = FinanceData(startMonth: oct2026)
        fixed.salary.fixedMonthly = 3_000
        assertFilled(fixed, "een vast salaris")

        var hourly = FinanceData(startMonth: oct2026)
        hourly.salary.mode = .hourly
        hourly.salary.hoursPerWeek = 32
        assertFilled(hourly, "uren per week bij uurloon (ook zonder uurloon)")

        var rate = FinanceData(startMonth: oct2026)
        rate.salary.hourlyRate = 25
        assertFilled(rate, "een uurloon")

        var payDay = FinanceData(startMonth: oct2026)
        payDay.salary.payDay = 1
        assertFilled(payDay, "een eigen salarisdag")
    }

    func testSampleDataIsNotEmpty() {
        XCTAssertFalse(FinanceData.sample(now: day(oct2026, 12)).isEmptyStart)
    }

    // MARK: Een startdatum is geen gegevens (docs/work/plan.md, R8)

    func testAStartDateAloneKeepsTheStartEmpty() {
        var d = FinanceData(startMonth: oct2026)
        d.setStart(CalendarDay(year: 2026, month: 10, day: 20))
        XCTAssertTrue(d.isEmptyStart, "een startdatum is geen gegevens: de welkomstkaart blijft")
        XCTAssertFalse(CloudSync.hasContent(d))
        XCTAssertTrue(CloudSync.isPristine(d))
        // Ook met een startdatum in een andere maand.
        d.setStart(CalendarDay(year: 2027, month: 2, day: 1))
        XCTAssertTrue(d.isEmptyStart)
        XCTAssertFalse(CloudSync.hasContent(d))
    }

    func testAStartDateOnADeviceWithContentChangesNothingAboutTheContent() {
        var d = FinanceData(startMonth: oct2026)
        d.upsertLine(MoneyLine(name: "Huur", amount: 900), kind: .expense, in: oct2026)
        XCTAssertFalse(d.isEmptyStart)
        d.setStart(CalendarDay(year: 2026, month: 10, day: 20))
        XCTAssertFalse(d.isEmptyStart)
        XCTAssertTrue(CloudSync.hasContent(d))
    }

    func testASyncDecisionIgnoresAStartDateOnAnEmptyDevice() {
        var local = FinanceData(startMonth: oct2026)
        local.setStart(CalendarDay(year: 2026, month: 10, day: 20))
        // Een apparaat met alleen een startdatum telt als leeg: er valt niets te uploaden.
        XCTAssertEqual(CloudSync.reconcile(local: local, localLastSyncedAt: nil, remote: nil), .noop)
    }
}
