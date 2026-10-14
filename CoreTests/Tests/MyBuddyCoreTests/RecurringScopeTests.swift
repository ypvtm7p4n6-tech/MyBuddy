import XCTest
import Foundation
@testable import MyBuddyCore

// Terugkerende regels met reikwijdte (wens 4): toevoegen, bewerken en verwijderen voor "alleen deze maand" of "deze en
// alle volgende maanden", overslaan en stoppen (de grafsteen), de vraag "hoort deze regel bij een reeks en tot wanneer",
// oude gegevens zonder reeks-id's, en opslaan/herstellen.
//
// Gegevens: salaris 3000, geen potten, startmaand augustus 2026, "nu" is oktober 2026.

private func now() -> FinanceData {
    var d = recEmptyData()
    d.materialize(upTo: oct2026)
    return d
}

private func gym(amount: Double = 40, day: Int? = 31) -> MoneyLine {
    MoneyLine(name: "Sportschool", amount: amount, isRecurring: true, day: day)
}

private func amount(_ d: FinanceData, _ name: String, _ m: YearMonth) -> Double? {
    recExpense(d, name, in: m)?.amount
}

final class RecurringScopeTests: XCTestCase {
    // MARK: Toevoegen en vragen

    func testAddRecurringLineReturnsTheStoredLineAndTheSeriesAnswersQuestions() throws {
        var d = now()
        let stored = d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        XCTAssertTrue(stored.isRecurring)
        XCTAssertEqual(stored.seriesID, stored.id, "de reeks begint met het id van de eerste regel")

        let line = try XCTUnwrap(recExpense(d, "Sportschool", in: recJan2027))
        XCTAssertNotEqual(line.id, stored.id, "elke maand heeft zijn eigen regel-id")
        XCTAssertEqual(line.seriesID, stored.id, "maar alle maanden delen het reeks-id")
        XCTAssertEqual(line.id, MoneyLine.seriesLineID(stored.id, in: recJan2027), "het afgeleide id is altijd hetzelfde")

        let info = try XCTUnwrap(d.seriesInfo(of: line, in: recJan2027))
        XCTAssertEqual(info.seriesID, stored.id)
        XCTAssertEqual(info.kind, .expense)
        XCTAssertEqual(info.firstMonth, oct2026)
        XCTAssertNil(info.lastMonth)
        XCTAssertTrue(info.isOpenEnded)
        XCTAssertTrue(info.skippedMonths.isEmpty)
        XCTAssertFalse(info.isException)
        XCTAssertEqual(info.latest.amount, 40)
        XCTAssertEqual(info.latest.day, 31)

        XCTAssertEqual(d.recurringSeries(kind: .expense).map(\.seriesID), [stored.id])
        XCTAssertTrue(d.recurringSeries(kind: .income).isEmpty)
        // Een eenmalige regel hoort bij geen reeks.
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 90, isRecurring: false, day: 3), kind: .expense, in: oct2026)
        XCTAssertNil(d.seriesInfo(of: try XCTUnwrap(recExpense(d, "Tandarts", in: oct2026)), in: oct2026))
        XCTAssertNil(recExpense(d, "Tandarts", in: recNov2026))
    }

    func testSeriesInfoOfAnUnknownLineIsNil() {
        let d = now()
        XCTAssertNil(d.seriesInfo(of: MoneyLine(name: "Spook", amount: 5, isRecurring: true), in: oct2026))
    }

    func testDayOfTheMonthAcrossShortMonthsAndLeapYear() {
        var d = now()
        d.addRecurringLine(gym(day: 30), kind: .expense, in: oct2026)
        XCTAssertEqual(recExpenseDay(d, "Sportschool", in: recFeb2027), 28)
        XCTAssertEqual(recExpenseDay(d, "Sportschool", in: YearMonth(year: 2028, month: 2)), 29)
        XCTAssertEqual(recExpenseDay(d, "Sportschool", in: YearMonth(year: 2028, month: 3)), 30)
        XCTAssertEqual(recExpenseDay(d, "Sportschool", in: YearMonth(year: 2031, month: 11)), 30)
    }

    // MARK: Bewerken

    func testEditThisMonthOnlyLeavesTheOtherMonthsAlone() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var edited = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        edited.amount = 55
        d.upsertLine(edited, kind: .expense, in: recDec2026, scope: .thisMonth)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        XCTAssertEqual(amount(d, "Sportschool", recDec2026), 55)
        XCTAssertEqual(amount(d, "Sportschool", recJan2027), 40, "de reeks gaat daarna gewoon door")
        XCTAssertEqual(amount(d, "Sportschool", YearMonth(year: 2029, month: 6)), 40)
        let info = try XCTUnwrap(d.seriesInfo(of: try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026)), in: recDec2026))
        XCTAssertTrue(info.isException)
        XCTAssertEqual(info.latest.amount, 40, "de reeks zelf blijft 40")
        let other = try XCTUnwrap(d.seriesInfo(of: try XCTUnwrap(recExpense(d, "Sportschool", in: recJan2027)), in: recJan2027))
        XCTAssertFalse(other.isException)
    }

    func testEditThisAndFollowingChangesStoredAndFutureMonths() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        d.editPlan(recJan2027) { _ in }   // januari is al vastgelegd (met de regel erin)
        var edited = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        edited.amount = 60
        edited.day = 12
        d.upsertLine(edited, kind: .expense, in: recDec2026, scope: .thisAndFollowing)
        XCTAssertEqual(amount(d, "Sportschool", oct2026), 40)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        for m in [recDec2026, recJan2027, recFeb2027, YearMonth(year: 2030, month: 5)] {
            XCTAssertEqual(amount(d, "Sportschool", m), 60, m.key)
            XCTAssertEqual(recExpenseDay(d, "Sportschool", in: m), 12, m.key)
        }
        XCTAssertEqual(recExpenseDay(d, "Sportschool", in: recNov2026), 30, "november blijft op dag 31 (30 in november)")
    }

    func testEditThisAndFollowingDoesNotOverwriteAMonthYouChangedOnlyForThatMonth() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var special = try XCTUnwrap(recExpense(d, "Sportschool", in: recJan2027))
        special.amount = 99
        d.upsertLine(special, kind: .expense, in: recJan2027, scope: .thisMonth)
        var edited = try XCTUnwrap(recExpense(d, "Sportschool", in: oct2026))
        edited.amount = 45
        d.upsertLine(edited, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        XCTAssertEqual(amount(d, "Sportschool", oct2026), 45)
        XCTAssertEqual(amount(d, "Sportschool", recDec2026), 45)
        XCTAssertEqual(amount(d, "Sportschool", recJan2027), 99, "de afwijkende maand blijft")
        XCTAssertEqual(amount(d, "Sportschool", recFeb2027), 45)
    }

    func testMakingAnExceptionTheNewBaselineChangesItsFollowers() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var special = try XCTUnwrap(recExpense(d, "Sportschool", in: recJan2027))
        special.amount = 99
        d.upsertLine(special, kind: .expense, in: recJan2027, scope: .thisMonth)
        d.editPlan(recMar2027) { _ in }   // maart is vastgelegd met de basis (40)
        // De afwijkende maand wordt de nieuwe basis: alleen de naam verandert, maar het hele nieuwe bedrag geldt voortaan.
        var renamed = try XCTUnwrap(recExpense(d, "Sportschool", in: recJan2027))
        renamed.name = "Sportschool Plus"
        d.upsertLine(renamed, kind: .expense, in: recJan2027, scope: .thisAndFollowing)
        for m in [recJan2027, recFeb2027, recMar2027, YearMonth(year: 2028, month: 1)] {
            XCTAssertEqual(amount(d, "Sportschool Plus", m), 99, m.key)
        }
        XCTAssertEqual(amount(d, "Sportschool", recDec2026), 40)
        XCTAssertNil(amount(d, "Sportschool", recFeb2027))
    }

    func testEditingTheOnlyStoredLineOfAMonthOnlyDoesNotLoseTheSeriesAfterwards() throws {
        // De regel van oktober is de enige opgeslagen regel van de reeks. Alleen oktober aanpassen mag de basis voor
        // november en later niet veranderen.
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var edited = try XCTUnwrap(recExpense(d, "Sportschool", in: oct2026))
        edited.amount = 5
        d.upsertLine(edited, kind: .expense, in: oct2026, scope: .thisMonth)
        XCTAssertEqual(amount(d, "Sportschool", oct2026), 5)
        for m in [recNov2026, recDec2026, YearMonth(year: 2031, month: 12)] {
            XCTAssertEqual(amount(d, "Sportschool", m), 40, m.key)
        }
    }

    func testEditingALaterBaselineThisMonthOnlyKeepsTheLaterBaselineForTheMonthsAfter() throws {
        // Dit was een echte fout: de basis veranderde in december (60); december alleen aanpassen zette de maanden erna
        // terug naar de oude basis (40) in plaats van de basis van december (60) te houden.
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var raise = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        raise.amount = 60
        d.upsertLine(raise, kind: .expense, in: recDec2026, scope: .thisAndFollowing)
        var once = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        once.amount = 7
        d.upsertLine(once, kind: .expense, in: recDec2026, scope: .thisMonth)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        XCTAssertEqual(amount(d, "Sportschool", recDec2026), 7)
        for m in [recJan2027, recFeb2027, YearMonth(year: 2029, month: 3)] {
            XCTAssertEqual(amount(d, "Sportschool", m), 60, m.key)
        }
    }

    func testToggleRecurringOffThisAndFollowingStopsTheSeriesButKeepsThisLineOnce() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        d.editPlan(recJan2027) { _ in }
        var once = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        once.isRecurring = false
        d.upsertLine(once, kind: .expense, in: recDec2026, scope: .thisAndFollowing)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        XCTAssertEqual(amount(d, "Sportschool", recDec2026), 40, "deze regel blijft, maar eenmalig")
        XCTAssertFalse(try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026)).isRecurring)
        XCTAssertNil(amount(d, "Sportschool", recJan2027), "ook niet in de al vastgelegde maand")
        XCTAssertNil(amount(d, "Sportschool", recFeb2027))
    }

    func testToggleRecurringOffThisMonthOnlySkipsThisMonth() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var once = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        once.isRecurring = false
        d.upsertLine(once, kind: .expense, in: recDec2026, scope: .thisMonth)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        XCTAssertEqual(amount(d, "Sportschool", recDec2026), 40)
        XCTAssertEqual(amount(d, "Sportschool", recJan2027), 40, "de reeks loopt door")
        XCTAssertEqual(d.plan(for: recDec2026).expenses.filter { $0.name == "Sportschool" }.count, 1, "niet dubbel in december")
    }

    func testMakingAOneOffLineRecurringStartsASeries() throws {
        var d = now()
        d.upsertLine(MoneyLine(name: "Krant", amount: 20, isRecurring: false, day: 4), kind: .expense, in: oct2026)
        XCTAssertNil(amount(d, "Krant", recNov2026))
        var line = try XCTUnwrap(recExpense(d, "Krant", in: oct2026))
        line.isRecurring = true
        d.upsertLine(line, kind: .expense, in: oct2026)
        for m in [recNov2026, recDec2026, recFeb2027] {
            XCTAssertEqual(amount(d, "Krant", m), 20, m.key)
            XCTAssertEqual(recExpenseDay(d, "Krant", in: m), 4, m.key)
        }
        XCTAssertEqual(d.plan(for: oct2026).expenses.filter { $0.name == "Krant" }.count, 1)
    }

    // MARK: Verwijderen

    func testRemoveThisMonthSkipsOnlyThatMonth() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        d.editPlan(recJan2027) { _ in }
        let line = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        d.deleteLine(id: line.id, kind: .expense, in: recDec2026, scope: .thisMonth)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        XCTAssertNil(amount(d, "Sportschool", recDec2026))
        XCTAssertEqual(amount(d, "Sportschool", recJan2027), 40)
        XCTAssertEqual(amount(d, "Sportschool", YearMonth(year: 2030, month: 1)), 40)
        let info = try XCTUnwrap(d.seriesInfo(of: try XCTUnwrap(recExpense(d, "Sportschool", in: recJan2027)), in: recJan2027))
        XCTAssertEqual(info.skippedMonths, [recDec2026])
        XCTAssertNil(info.lastMonth)

        // De overgeslagen maand terugzetten: de regel is er weer.
        d.restoreSkippedLine(seriesID: info.seriesID, in: recDec2026)
        XCTAssertEqual(amount(d, "Sportschool", recDec2026), 40)
        XCTAssertTrue(try XCTUnwrap(d.seriesInfo(of: try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026)), in: recDec2026)).skippedMonths.isEmpty)
    }

    func testRemoveThisAndFollowingStopsTheSeriesEvenInStoredMonths() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        d.editPlan(recJan2027) { _ in }
        d.editPlan(YearMonth(year: 2027, month: 6)) { _ in }
        let line = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        d.deleteLine(id: line.id, kind: .expense, in: recDec2026, scope: .thisAndFollowing)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        for m in [recDec2026, recJan2027, recFeb2027, YearMonth(year: 2027, month: 6), YearMonth(year: 2031, month: 1)] {
            XCTAssertNil(amount(d, "Sportschool", m), "\(m.key): de reeks is gestopt")
        }
        let info = try XCTUnwrap(d.seriesInfo(of: try XCTUnwrap(recExpense(d, "Sportschool", in: recNov2026)), in: recNov2026))
        XCTAssertEqual(info.lastMonth, recNov2026)
        XCTAssertFalse(info.isOpenEnded)
        // Een nieuwe regel met dezelfde naam is een nieuwe reeks.
        d.addRecurringLine(gym(amount: 30), kind: .expense, in: recMar2027)
        XCTAssertNil(amount(d, "Sportschool", recFeb2027))
        XCTAssertEqual(amount(d, "Sportschool", recMar2027), 30)
        XCTAssertEqual(amount(d, "Sportschool", YearMonth(year: 2031, month: 1)), 30)
        XCTAssertEqual(d.recurringSeries(kind: .expense).count, 2)
    }

    func testRemovingTheFirstMonthThisMonthOnlyKeepsTheRest() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        let line = try XCTUnwrap(recExpense(d, "Sportschool", in: oct2026))
        d.deleteLine(id: line.id, kind: .expense, in: oct2026, scope: .thisMonth)
        XCTAssertNil(amount(d, "Sportschool", oct2026))
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        XCTAssertEqual(amount(d, "Sportschool", YearMonth(year: 2032, month: 5)), 40)
    }

    func testRemovingTheFirstMonthAndFollowingRemovesTheSeriesCompletely() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        let line = try XCTUnwrap(recExpense(d, "Sportschool", in: oct2026))
        d.deleteLine(id: line.id, kind: .expense, in: oct2026)
        XCTAssertNil(amount(d, "Sportschool", oct2026))
        XCTAssertNil(amount(d, "Sportschool", recNov2026))
        XCTAssertTrue(d.recurringSeries(kind: .expense).isEmpty)
    }

    func testRemovingALaterBaselineThisMonthOnlyKeepsThatBaselineForTheMonthsAfter() throws {
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var raise = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        raise.amount = 60
        d.upsertLine(raise, kind: .expense, in: recDec2026, scope: .thisAndFollowing)
        d.deleteLine(id: try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026)).id, kind: .expense, in: recDec2026,
                     scope: .thisMonth)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
        XCTAssertNil(amount(d, "Sportschool", recDec2026))
        XCTAssertEqual(amount(d, "Sportschool", recJan2027), 60)
        XCTAssertEqual(amount(d, "Sportschool", YearMonth(year: 2030, month: 1)), 60)
    }

    func testRemovingALineWithEditPlanSkipsThatMonthOnlyAndKeepsTheBaseline() throws {
        // Wie een regel rechtstreeks uit het maandplan haalt (zonder de functies voor reikwijdte) slaat die maand over.
        var d = now()
        d.addRecurringLine(gym(), kind: .expense, in: oct2026)
        var raise = try XCTUnwrap(recExpense(d, "Sportschool", in: recDec2026))
        raise.amount = 60
        d.upsertLine(raise, kind: .expense, in: recDec2026)
        d.editPlan(recDec2026) { plan in plan.expenses.removeAll { $0.name == "Sportschool" } }
        XCTAssertNil(amount(d, "Sportschool", recDec2026))
        XCTAssertEqual(amount(d, "Sportschool", recJan2027), 60)
        XCTAssertEqual(amount(d, "Sportschool", recNov2026), 40)
    }

    func testIncomeSeriesBehaveTheSame() throws {
        var d = now()
        d.addRecurringLine(MoneyLine(name: "Toeslag", amount: 120, isRecurring: true, day: 20), kind: .income, in: oct2026)
        var edited = try XCTUnwrap(recIncome(d, "Toeslag", in: recDec2026))
        edited.amount = 150
        d.upsertLine(edited, kind: .income, in: recDec2026, scope: .thisAndFollowing)
        d.deleteLine(id: try XCTUnwrap(recIncome(d, "Toeslag", in: recFeb2027)).id, kind: .income, in: recFeb2027, scope: .thisMonth)
        XCTAssertEqual(recIncome(d, "Toeslag", in: recNov2026)?.amount, 120)
        XCTAssertEqual(recIncome(d, "Toeslag", in: recJan2027)?.amount, 150)
        XCTAssertNil(recIncome(d, "Toeslag", in: recFeb2027))
        XCTAssertEqual(recIncome(d, "Toeslag", in: recMar2027)?.amount, 150)
        XCTAssertEqual(recIncomeDay(d, "Toeslag", in: recMar2027), 20)
        XCTAssertEqual(d.income(in: recMar2027), 3_150, accuracy: 1e-9)
        XCTAssertEqual(d.income(in: recFeb2027), 3_000, accuracy: 1e-9)
        XCTAssertEqual(d.recurringSeries(kind: .income).count, 1)
    }

    // MARK: Eén antwoord overal

    func testAllCalculationsAgreeAfterEditsAndRemovals() throws {
        var d = now()
        let pot = Pot(name: "Auto", monthlyContribution: 100, startMonth: aug2026)
        d.addPot(pot, openingBalance: 1_000, now: day(aug2026, 1))
        d.addRecurringLine(MoneyLine(name: "Verzekering", amount: 100, isRecurring: true, day: 10,
                                     potShares: [PotShare(potID: pot.id, amount: 60)]), kind: .expense, in: oct2026)
        d.editPlan(recJan2027) { $0.transferDay = 3 }
        var edited = try XCTUnwrap(recExpense(d, "Verzekering", in: recDec2026))
        edited.amount = 120
        d.upsertLine(edited, kind: .expense, in: recDec2026, scope: .thisAndFollowing)
        d.deleteLine(id: try XCTUnwrap(recExpense(d, "Verzekering", in: recFeb2027)).id, kind: .expense, in: recFeb2027, scope: .thisMonth)

        let builder = d.monthFiguresBuilder()
        var potBalance = 1_000.0
        // Verzekering: okt/nov 100 (60 uit de pot), dec t/m jan 120 (60 uit de pot), feb overgeslagen, maart 120.
        let expectedExpenses: [YearMonth: Double] = [oct2026: 100, recNov2026: 100, recDec2026: 120, recJan2027: 120, recFeb2027: 0, recMar2027: 120]
        for m in aug2026.range(count: 8) {
            let f = d.monthFigures(m)
            XCTAssertEqual(builder.figures(m), f, m.key)
            XCTAssertEqual(CentsMath.value(f.expenses), expectedExpenses[m] ?? 0, m.key)
            XCTAssertEqual(f.remaining, f.income - (f.expenses - f.fromPots) - f.saved - f.invested, m.key)
            potBalance += 100 - CentsMath.value(f.fromPots)
            XCTAssertEqual(d.potBalance(pot.id, at: m), potBalance, accuracy: 1e-9, m.key)
            XCTAssertEqual(d.expensesTotal(in: m), CentsMath.value(f.expenses), m.key)
            XCTAssertEqual(d.remaining(in: m), CentsMath.value(f.remaining), m.key)
            XCTAssertTrue(d.monthLedger(m, asOf: day(oct2026, 12)).allReconciles, m.key)
        }
    }

    func testRecurringExpenseFromAPotThatStartsLaterStillReturnsAndEverythingAgrees() throws {
        // De pot begint pas in november (beginsaldo 1000 op 1 november), maar de verzekering loopt al vanaf augustus en
        // betaalt 60 per maand uit die pot. Vóór november staat de pot daardoor onder nul; elke berekening ziet dat gelijk.
        var d = recEmptyData()
        let pot = Pot(name: "Auto", monthlyContribution: 0, startMonth: recNov2026)
        d.addPot(pot, openingBalance: 1_000, now: day(recNov2026, 1))
        d.editPlan(recNov2026) { $0.transferDay = 3 }
        d.addRecurringLine(MoneyLine(name: "Verzekering", amount: 100, isRecurring: true, day: 10,
                                     potShares: [PotShare(potID: pot.id, amount: 60)]), kind: .expense, in: aug2026)
        for m in [aug2026, sep2026, oct2026, recNov2026, recDec2026, YearMonth(year: 2028, month: 1)] {
            XCTAssertEqual(amount(d, "Verzekering", m), 100, m.key)
            XCTAssertEqual(d.expensesFromPots(in: m), 60, accuracy: 1e-9, m.key)
            XCTAssertEqual(d.expensesFromBank(in: m), 40, accuracy: 1e-9, m.key)
            XCTAssertEqual(d.remaining(in: m), 3_000 - 40, accuracy: 1e-9, m.key)
            XCTAssertTrue(d.monthLedger(m, asOf: day(oct2026, 12)).allReconciles, m.key)
        }
        XCTAssertEqual(d.potBalance(pot.id, at: aug2026), -60, accuracy: 1e-9)
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), -180, accuracy: 1e-9)
        XCTAssertEqual(d.potBalance(pot.id, at: recNov2026), 1_000 - 240, accuracy: 1e-9)
        XCTAssertEqual(d.potBalance(pot.id, at: recDec2026), 1_000 - 300, accuracy: 1e-9)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: day(oct2026, 12)), -180, accuracy: 1e-9)
        // De dagen: de uitgave staat elke maand op de 10e, het potdeel ook.
        let events = d.planEvents(in: recNov2026).filter { $0.title.hasPrefix("Verzekering") }
        XCTAssertEqual(events.map(\.day), [10, 10])
        XCTAssertEqual(events.map { CentsMath.int($0.bankAmount) }.sorted(), [-4_000, 0])
        XCTAssertEqual(events.map { CentsMath.int($0.potAmount) }.sorted(), [-6_000, 0])
    }

    // MARK: Oude gegevens

    /// Een oud bestand: huur (terugkerend, zonder reeks-id) in augustus, september en oktober met afgeleide id's, en een
    /// vastgelegde december waarin de huur ontbreekt (zo ontbrak een regel in de oude app als je hem een maand eerder
    /// toevoegde).
    private func legacyData() throws -> FinanceData {
        let rent1 = StableID.uuid("legacy|rent")
        let rent2 = StableID.uuid("line|\(rent1.uuidString)|2026-09")
        let rent3 = StableID.uuid("line|\(rent2.uuidString)|2026-10")
        let json = """
        {"startMonth":"2026-08","salary":{"mode":"fixed","fixedMonthly":3000,"hourlyRate":0,"hoursPerWeek":0},
         "months":{
          "2026-08":{"extraIncome":[],"expenses":[{"id":"\(rent1.uuidString)","name":"Huur","amount":1000,"isRecurring":true,"kind":"fixed","day":1,"potShares":[]}],"allocations":{}},
          "2026-09":{"extraIncome":[],"expenses":[{"id":"\(rent2.uuidString)","name":"Huur","amount":1000,"isRecurring":true,"kind":"fixed","day":1,"potShares":[]}],"allocations":{}},
          "2026-10":{"extraIncome":[],"expenses":[{"id":"\(rent3.uuidString)","name":"Huur","amount":1000,"isRecurring":true,"kind":"fixed","day":1,"potShares":[]}],"allocations":{}},
          "2026-12":{"extraIncome":[],"expenses":[],"allocations":{},"transferDay":4}}}
        """
        return try JSONDecoder().decode(FinanceData.self, from: Data(json.utf8))
    }

    func testOldDataWhereARecurringLineIsMissingInALaterStoredMonthGetsItBack() throws {
        let d = try legacyData()
        for m in [recNov2026, recDec2026, recJan2027, YearMonth(year: 2029, month: 3)] {
            XCTAssertEqual(amount(d, "Huur", m), 1_000, "huur ontbreekt in \(m.key)")
        }
        XCTAssertEqual(recExpenseDay(d, "Huur", in: recDec2026), 1)
        XCTAssertEqual(d.recurringSeries(kind: .expense).count, 1, "de drie regels zijn één reeks")
        XCTAssertEqual(d.recurringSeries(kind: .expense)[0].firstMonth, aug2026)
    }

    func testOldDataAnswersTheSameBeforeAndAfterMigration() throws {
        let d = try legacyData()
        var migrated = d
        XCTAssertGreaterThan(migrated.migrateRecurringSeries(), 0)
        XCTAssertEqual(migrated.migrateRecurringSeries(), 0, "tweede keer: niets te doen")
        XCTAssertNotNil(migrated.months[oct2026.key]?.expenses.first?.seriesID, "reeks-id's zijn weggeschreven")
        for m in aug2026.range(count: 40) {
            XCTAssertEqual(migrated.monthFigures(m), d.monthFigures(m), m.key)
            XCTAssertEqual(migrated.plan(for: m).expenses.map(\.amount), d.plan(for: m).expenses.map(\.amount), m.key)
            XCTAssertEqual(migrated.plan(for: m).expenses.map(\.id), d.plan(for: m).expenses.map(\.id), "id's in \(m.key)")
        }
        // materialize schrijft de reeks-id's ook weg.
        var materialized = d
        materialized.materialize(upTo: oct2026)
        XCTAssertNotNil(materialized.months[aug2026.key]?.expenses.first?.seriesID)
        XCTAssertEqual(materialized.monthFigures(recDec2026), d.monthFigures(recDec2026))
    }

    func testEditingOldDataThisAndFollowingReachesTheChainedMonths() throws {
        var d = try legacyData()
        var edited = try XCTUnwrap(recExpense(d, "Huur", in: aug2026))
        edited.amount = 900
        d.upsertLine(edited, kind: .expense, in: aug2026, scope: .thisAndFollowing)
        for m in [aug2026, sep2026, oct2026, recNov2026, recDec2026, recJan2027] {
            XCTAssertEqual(amount(d, "Huur", m), 900, m.key)
        }
    }

    func testDeletingARecurringLineAfterTheMigrationLeavesAGravestone() throws {
        var d = try legacyData()
        let line = try XCTUnwrap(recExpense(d, "Huur", in: recNov2026))
        d.deleteLine(id: line.id, kind: .expense, in: recNov2026)
        XCTAssertNil(amount(d, "Huur", recNov2026))
        XCTAssertNil(amount(d, "Huur", recDec2026), "ook niet in de vastgelegde december")
        XCTAssertNil(amount(d, "Huur", YearMonth(year: 2030, month: 1)))
        XCTAssertEqual(amount(d, "Huur", oct2026), 1_000)
        let gravestones = d.months.values.flatMap(\.endedSeries)
        XCTAssertEqual(gravestones.count, 1, "precies één einde")
        XCTAssertEqual(d.months[recNov2026.key]?.endedSeries, gravestones)
        // En na opslaan en inlezen blijft het gestopt.
        let back = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
        XCTAssertNil(amount(back, "Huur", recDec2026))
    }
}
