import XCTest
import Foundation
@testable import MyBuddyCore

// Reeksen en percentages in de rest van de rekenmotor: standaarduitgaven, import van Excel, voorbeelddata, vastleggen
// van maanden en de verdeelhulpjes.

final class SeriesIntegrationTests: XCTestCase {
    // MARK: Standaarduitgaven

    func testStandardExpensesReturnEveryMonthAndAreNotAddedTwice() {
        var d = recEmptyData()
        d.materialize(upTo: oct2026)
        d.editPlan(recDec2026) { $0.transferDay = 3 }   // december is al vastgelegd
        let added = d.fillStandardExpenses(in: oct2026)
        XCTAssertEqual(added, StandardExpenses.all.count)
        XCTAssertEqual(d.fillStandardExpenses(in: oct2026), 0, "tweede keer: niets nieuws")
        for m in [recNov2026, recDec2026, recJan2027, YearMonth(year: 2031, month: 6)] {
            XCTAssertEqual(d.plan(for: m).expenses.count, StandardExpenses.all.count, m.key)
            XCTAssertEqual(d.fillStandardExpenses(in: m), 0, "ze zijn er al in \(m.key)")
            XCTAssertEqual(d.expensesTotal(in: m), CentsMath.value(CentsMath.sum(StandardExpenses.all.map { CentsMath.int($0.amount) })),
                           accuracy: 1e-9, m.key)
        }
        // Een standaarduitgave voor één maand weghalen laat de andere maanden staan.
        let rent = d.plan(for: recNov2026).expenses.first { $0.name == "Huur of hypotheek" }!
        d.deleteLine(id: rent.id, kind: .expense, in: recNov2026, scope: .thisMonth)
        XCTAssertNil(recExpense(d, "Huur of hypotheek", in: recNov2026))
        XCTAssertNotNil(recExpense(d, "Huur of hypotheek", in: recDec2026))
        XCTAssertEqual(d.missingStandardExpenses(in: recNov2026).map(\.name), ["Huur of hypotheek"])
    }

    // MARK: Vastleggen van maanden

    func testMaterializeNeverBringsBackSkippedOrStoppedLines() throws {
        var d = recEmptyData()
        d.addRecurringLine(MoneyLine(name: "Sportschool", amount: 40, isRecurring: true, day: 5), kind: .expense, in: aug2026)
        d.addRecurringLine(MoneyLine(name: "Krant", amount: 15, isRecurring: true, day: 9), kind: .expense, in: aug2026)
        d.deleteLine(id: try XCTUnwrap(recExpense(d, "Sportschool", in: sep2026)).id, kind: .expense, in: sep2026, scope: .thisMonth)
        d.deleteLine(id: try XCTUnwrap(recExpense(d, "Krant", in: recDec2026)).id, kind: .expense, in: recDec2026, scope: .thisAndFollowing)
        for _ in 0..<2 {
            d.materialize(upTo: recFeb2027)
            XCTAssertNil(recExpense(d, "Sportschool", in: sep2026))
            XCTAssertNotNil(recExpense(d, "Sportschool", in: oct2026))
            XCTAssertNotNil(recExpense(d, "Krant", in: recNov2026))
            for m in [recDec2026, recJan2027, recFeb2027, YearMonth(year: 2030, month: 1)] {
                XCTAssertNil(recExpense(d, "Krant", in: m), m.key)
                XCTAssertNotNil(recExpense(d, "Sportschool", in: m), m.key)
            }
        }
        XCTAssertEqual(d.plan(for: recJan2027).expenses.filter { $0.name == "Sportschool" }.count, 1)
    }

    func testMaterializeKeepsTheLineIdsStable() {
        var d = recEmptyData()
        d.addRecurringLine(MoneyLine(name: "Sportschool", amount: 40, isRecurring: true, day: 5), kind: .expense, in: aug2026)
        let before = aug2026.range(count: 12).map { d.plan(for: $0).expenses.map(\.id) }
        d.materialize(upTo: oct2026)
        let after = aug2026.range(count: 12).map { d.plan(for: $0).expenses.map(\.id) }
        XCTAssertEqual(before, after, "dezelfde regel-id's voor en na vastleggen, dus ook dezelfde gebeurtenis-id's")
        let events = aug2026.range(count: 12).flatMap { d.planEvents(in: $0).map(\.id) }
        XCTAssertEqual(Set(events).count, events.count)
    }

    // MARK: Import

    func testImportUpdateReachesStoredLaterMonthsAndPercentagePotsBecomeFixed() {
        var d = recEmptyData()
        d.materialize(upTo: oct2026)
        d.editPlan(recDec2026) { $0.transferDay = 3 }
        var pot = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: aug2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.addPot(pot)
        d.applyImport(ImportDraft(rows: [ImportRow(name: "Huur", amount: 900, category: .vasteLasten, day: 1)]), month: oct2026,
                      now: day(oct2026, 12))
        XCTAssertEqual(recExpense(d, "Huur", in: recDec2026)?.amount, 900)
        // Opnieuw met een nieuw bedrag: bijwerken geldt vanaf deze maand ook voor de vastgelegde december.
        let report = d.applyImport(ImportDraft(rows: [
            ImportRow(name: "Huur", amount: 950, category: .vasteLasten, day: 2),
            ImportRow(name: "Vakantie", amount: 125, category: .spaarpot, meaning: .perMaand)
        ]), month: oct2026, existing: .update, now: day(oct2026, 12))
        XCTAssertEqual(report.lines.map(\.outcome), [.updated, .updated])
        for m in [oct2026, recNov2026, recDec2026, recJan2027, YearMonth(year: 2029, month: 2)] {
            XCTAssertEqual(recExpense(d, "Huur", in: m)?.amount, 950, m.key)
            XCTAssertEqual(recExpenseDay(d, "Huur", in: m), 2, m.key)
        }
        // De inleg per maand uit het bestand is een vast bedrag, en geldt meteen voor deze maand.
        XCTAssertEqual(d.pot(pot.id)?.contributionMode, .fixed)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 125)
        XCTAssertEqual(d.allocation(pot.id, in: recNov2026), 125)
        XCTAssertNil(d.months[oct2026.key]?.percentAllocations[pot.id.uuidString])
    }

    func testImportSkipsExistingLinesWithoutChangingFollowingMonths() {
        var d = recEmptyData()
        d.materialize(upTo: oct2026)
        d.applyImport(ImportDraft(rows: [ImportRow(name: "Huur", amount: 900, category: .vasteLasten, day: 1)]), month: oct2026,
                      now: day(oct2026, 12))
        let report = d.applyImport(ImportDraft(rows: [ImportRow(name: "huur", amount: 1_500, category: .vasteLasten, day: 9)]),
                                   month: recNov2026, now: day(oct2026, 12))
        XCTAssertEqual(report.lines.map(\.outcome), [.skippedExisting])
        XCTAssertEqual(recExpense(d, "Huur", in: recNov2026)?.amount, 900)
        XCTAssertEqual(d.plan(for: recNov2026).expenses.count, 1)
    }

    // MARK: Voorbeelddata

    func testSampleDataRecurringLinesAreOnTheirDayForFiveYears() {
        let now = day(oct2026, 10)
        let d = FinanceData.sample(now: now)
        let expected: [(String, Int)] = [("Huur", 1), ("Boodschappen", 5), ("Zorgverzekering", 1), ("Energie en water", 18),
                                         ("Vervoer (brandstof of OV)", 3), ("Abonnementen", 8)]
        for m in d.startMonth.range(count: 5 + 12 * 5) {
            for (name, dayNumber) in expected {
                XCTAssertEqual(d.planEvents(in: m).first { $0.kind == .expense && $0.title == name }?.day, dayNumber, "\(name) \(m.key)")
            }
            XCTAssertEqual(d.planEvents(in: m).first { $0.kind == .income && $0.title == "Zorgtoeslag" }?.day, 20, m.key)
        }
        // De recente uitgave uit een pot is een eenmalige regel en komt niet terug.
        XCTAssertNotNil(recExpense(d, "Tandarts", in: oct2026))
        XCTAssertNil(recExpense(d, "Tandarts", in: oct2026.adding(1)))
    }

    func testSampleDataHolidayPotInvestsAPercentageOfTheSalary() throws {
        let now = day(oct2026, 10)
        let d = FinanceData.sample(now: now)
        let holiday = try XCTUnwrap(d.pots.first { $0.name == "Vakantie" })
        XCTAssertEqual(holiday.contributionMode, .percentage)
        XCTAssertEqual(holiday.contributionPercent, 3.5)
        // Uurloon 21,50 x 156 uur = 3354,00; 3,5% daarvan = 117,39.
        XCTAssertEqual(d.salaryAmount(in: oct2026), 3_354, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(holiday.id, in: oct2026), 117.39, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(holiday.id, in: oct2026.adding(7)), 117.39, accuracy: 1e-9)
        // Een maand met overuren: het percentage volgt het salaris.
        var more = d
        more.editPlan(oct2026.adding(1)) { $0.hoursOverride = 180 }   // 21,50 x 180 = 3870 -> 135,45
        XCTAssertEqual(more.allocation(holiday.id, in: oct2026.adding(1)), 135.45, accuracy: 1e-9)
        XCTAssertEqual(more.monthLedger(oct2026.adding(1), asOf: now).allReconciles, true)
    }

    // MARK: Verdeelhulpjes met percentages

    func testDefaultClearAndSpreadHelpersWithPercentages() {
        var d = recEmptyData()
        var pot = Pot(name: "A", monthlyContribution: 0, startMonth: aug2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        let other = Pot(name: "B", monthlyContribution: 100, startMonth: aug2026)
        d.addPot(pot)
        d.addPot(other)
        // Een eigen verdeling voor oktober, dan terug naar de standaard.
        d.setAllocationPercent(pot.id, in: oct2026, percent: 50)
        d.setAllocation(other.id, in: oct2026, amount: 999)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 1_500, accuracy: 1e-9)
        d.applyDefaultAllocations(in: oct2026)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 300, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(other.id, in: oct2026), 100)
        XCTAssertNotNil(d.months[oct2026.key]?.percentAllocations[pot.id.uuidString], "het percentage blijft een percentage")
        XCTAssertNil(d.months[oct2026.key]?.allocations[pot.id.uuidString])
        d.editPlan(oct2026) { $0.salaryOverride = 4_000 }
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 400, accuracy: 1e-9, "volgt het salaris van die maand")

        // Alles op nul: ook een percentage.
        d.clearAllocations(in: oct2026)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 0)
        XCTAssertEqual(d.allocation(other.id, in: oct2026), 0)
        XCTAssertEqual(d.remaining(in: oct2026), 4_000, accuracy: 1e-9)

        // Wat er over is gelijk verdelen: komt bij het bedrag van elke pot erbij (een percentage wordt daarbij een bedrag).
        d.spreadRemainingOverPots(in: oct2026)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 2_000, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(other.id, in: oct2026), 2_000, accuracy: 1e-9)
        XCTAssertEqual(d.remaining(in: oct2026), 0, accuracy: 1e-9)
        XCTAssertNil(d.months[oct2026.key]?.percentAllocations[pot.id.uuidString])
    }

    func testSpreadingWhatIsLeftKeepsEveryCentWithPercentagePots() {
        var d = recEmptyData()
        d.salary.fixedMonthly = 2_999.99
        for (i, p) in [12.34, 7.5, 3.0].enumerated() {
            var pot = Pot(name: "P\(i)", monthlyContribution: 0, startMonth: aug2026)
            pot.contributionMode = .percentage
            pot.contributionPercent = p
            d.addPot(pot)
        }
        let before = d.monthFigures(oct2026)
        d.spreadRemainingOverPots(in: oct2026)
        let after = d.monthFigures(oct2026)
        XCTAssertGreaterThan(before.remaining, 0)
        XCTAssertEqual(after.remaining, 0, "er blijft geen cent liggen")
        XCTAssertEqual(after.saved, before.saved + before.remaining)
    }
}
