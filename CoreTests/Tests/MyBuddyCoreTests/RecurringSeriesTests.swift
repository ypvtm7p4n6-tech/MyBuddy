import XCTest
import Foundation
@testable import MyBuddyCore

// Terugkerende regels (wens 4): een terugkerende uitgave of extra inkomst moet elke volgende maand terugkomen op zijn
// eigen dag, ook in maanden die al zijn vastgelegd of bewerkt en ook ver in de toekomst.
//
// Deze tests staan eerst op het gemelde gedrag (een regel die in maand M terugkerend is, ontbreekt in M+1), en daarna
// op het reeksmodel (`RecurringSeries.swift`) met overslaan, stoppen en de twee reikwijdtes.

let recNov2026 = YearMonth(year: 2026, month: 11)
let recDec2026 = YearMonth(year: 2026, month: 12)
let recJan2027 = YearMonth(year: 2027, month: 1)
let recFeb2027 = YearMonth(year: 2027, month: 2)
let recMar2027 = YearMonth(year: 2027, month: 3)

/// Salaris 3000 op de 25e, geen potten, geen regels, startmaand augustus 2026.
func recEmptyData() -> FinanceData {
    var d = FinanceData(startMonth: aug2026)
    d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
    return d
}

/// De dag waarop de uitgave `name` in `month` van de rekening gaat (uit de gebeurtenissen), nil als hij er niet is.
func recExpenseDay(_ d: FinanceData, _ name: String, in month: YearMonth) -> Int? {
    d.planEvents(in: month).first { $0.kind == .expense && $0.title == name }?.day
}

func recIncomeDay(_ d: FinanceData, _ name: String, in month: YearMonth) -> Int? {
    d.planEvents(in: month).first { $0.kind == .income && $0.title == name }?.day
}

func recExpense(_ d: FinanceData, _ name: String, in month: YearMonth) -> MoneyLine? {
    d.plan(for: month).expenses.first { $0.name == name }
}

func recIncome(_ d: FinanceData, _ name: String, in month: YearMonth) -> MoneyLine? {
    d.plan(for: month).extraIncome.first { $0.name == name }
}

// MARK: - De gemelde fout, nagebootst

/// Elk van deze tests faalde op de oude rekenmotor. De oorzaak: een maand die is vastgelegd (opgeslagen) krijgt zijn
/// regels alleen uit zichzelf; een terugkerende regel die later in een eerdere maand wordt toegevoegd, bereikt hem nooit.
/// Een maand die niet is vastgelegd haalt zijn regels uit het laatst opgeslagen plan vóór hem, dus een vastgelegde maand
/// in het midden blokkeert ook alle maanden erna. Afwezigheid betekende bovendien twee dingen (verwijderd of nooit
/// doorgegeven), dus er was geen veilige manier om de regel terug te zetten.
final class RecurringRootCauseTests: XCTestCase {
    /// Oktober is de huidige maand: alles t/m oktober is vastgelegd (zoals `AppStore` doet).
    private func current() -> FinanceData {
        var d = recEmptyData()
        d.materialize(upTo: oct2026)
        return d
    }

    private func subscription(day: Int? = 31, amount: Double = 40) -> MoneyLine {
        MoneyLine(name: "Sportschool", amount: amount, isRecurring: true, day: day)
    }

    func testAddedInTheCurrentMonthWhileTheNextMonthWasAlreadyEdited() {
        var d = current()
        d.editPlan(recNov2026) { $0.transferDay = 3 }          // de volgende maand is al bewerkt (vastgelegd)
        d.upsertLine(subscription(), kind: .expense, in: oct2026)
        for m in [oct2026, recNov2026, recDec2026, recJan2027, recFeb2027, recMar2027] {
            XCTAssertNotNil(recExpense(d, "Sportschool", in: m), "ontbreekt in \(m.key)")
        }
    }

    func testNextMonthEditedFirstAllocationThenRecurringLineAddedThisMonth() {
        var d = current()
        let pot = Pot(name: "Spaar", monthlyContribution: 100, startMonth: aug2026)
        d.addPot(pot)
        d.setAllocation(pot.id, in: recNov2026, amount: 250)   // november bewerkt: de verdeling is nu vastgelegd
        d.upsertLine(subscription(), kind: .expense, in: oct2026)
        XCTAssertEqual(d.expensesTotal(in: recNov2026), 40, "november mist de terugkerende uitgave")
        XCTAssertEqual(d.expensesTotal(in: recDec2026), 40, "december haalt zijn regels uit het (te lege) plan van november")
        XCTAssertEqual(d.expensesTotal(in: recMar2027), 40)
    }

    func testAddedInAPastMonthReachesTheStoredMonthsAfterIt() {
        var d = current()
        d.upsertLine(subscription(day: 12), kind: .expense, in: aug2026)
        for m in aug2026.range(count: 8) {
            XCTAssertNotNil(recExpense(d, "Sportschool", in: m), "ontbreekt in \(m.key)")
        }
    }

    func testRecurringIncomeBehavesTheSame() {
        var d = current()
        d.editPlan(recNov2026) { $0.salaryOverride = 3100 }
        d.upsertLine(MoneyLine(name: "Toeslag", amount: 120, isRecurring: true, day: 20), kind: .income, in: oct2026)
        for m in [recNov2026, recDec2026, recFeb2027] {
            XCTAssertEqual(recIncomeDay(d, "Toeslag", in: m), 20, "ontbreekt in \(m.key)")
        }
    }

    func testStoredMonthInTheMiddleDoesNotBlockTheMonthsAfterIt() {
        var d = current()
        d.upsertLine(subscription(), kind: .expense, in: oct2026)
        d.editPlan(recJan2027) { $0.transferDay = 5 }          // januari vastleggen mag de regel niet kwijtraken
        d.upsertLine(MoneyLine(name: "Krant", amount: 20, isRecurring: true, day: 2), kind: .expense, in: oct2026)
        for m in [recNov2026, recDec2026, recJan2027, recFeb2027, recMar2027] {
            XCTAssertNotNil(recExpense(d, "Krant", in: m), "ontbreekt in \(m.key)")
        }
    }

    func testDay31FallsOnTheLastDayOfShortMonths() {
        var d = current()
        d.upsertLine(subscription(day: 31), kind: .expense, in: oct2026)
        let expected: [(YearMonth, Int)] = [
            (recNov2026, 30), (recDec2026, 31), (recJan2027, 31), (recFeb2027, 28), (recMar2027, 31),
            (YearMonth(year: 2027, month: 4), 30), (YearMonth(year: 2028, month: 2), 29)
        ]
        for (m, last) in expected {
            XCTAssertEqual(recExpenseDay(d, "Sportschool", in: m), last, "dag in \(m.key)")
        }
    }

    func testImportedRecurringLinesReachStoredLaterMonths() {
        var d = current()
        d.editPlan(recNov2026) { $0.transferDay = 3 }
        let draft = ImportDraft(rows: [
            ImportRow(name: "Huur", amount: 950, category: .vasteLasten, day: 1),
            ImportRow(name: "Kinderbijslag", amount: 250, category: .inkomen, day: 8)
        ])
        d.applyImport(draft, month: oct2026, now: day(oct2026, 12))
        for m in [recNov2026, recDec2026, recFeb2027] {
            XCTAssertEqual(recExpense(d, "Huur", in: m)?.amount, 950, "huur ontbreekt in \(m.key)")
            XCTAssertEqual(recIncomeDay(d, "Kinderbijslag", in: m), 8, "kinderbijslag ontbreekt in \(m.key)")
        }
    }

    func testExpensePartlyFromAPotReturnsEveryMonthAndMovesThePotBalance() {
        var d = current()
        let pot = Pot(name: "Auto", monthlyContribution: 0, startMonth: aug2026)
        d.addPot(pot, openingBalance: 1_000, now: day(aug2026, 1))
        d.editPlan(recNov2026) { $0.transferDay = 3 }
        d.upsertLine(MoneyLine(name: "Verzekering", amount: 100, isRecurring: true, day: 10,
                               potShares: [PotShare(potID: pot.id, amount: 60)]), kind: .expense, in: oct2026)
        // Eind oktober 940, november 880, december 820.
        XCTAssertEqual(d.potBalance(pot.id, at: oct2026), 940, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: recNov2026), 880, accuracy: 0.001)
        XCTAssertEqual(d.potBalance(pot.id, at: recDec2026), 820, accuracy: 0.001)
        XCTAssertEqual(d.expensesFromPots(in: recNov2026), 60, accuracy: 0.001)
    }

    func testAcceleratorLinesAlsoReturnInStoredMonths() {
        // Een versneller zet een terugkerende inkomstenregel in de huidige maand; een vastgelegde maand erna moet hem ook krijgen.
        var d = current()
        d.editPlan(recDec2026) { $0.transferDay = 4 }
        d.upsertLine(MoneyLine(name: "Extra uren", amount: 80, isRecurring: true), kind: .income, in: oct2026)
        for m in [recNov2026, recDec2026, recJan2027] {
            XCTAssertNotNil(recIncome(d, "Extra uren", in: m), "ontbreekt in \(m.key)")
        }
    }
}
