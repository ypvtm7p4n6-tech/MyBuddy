import XCTest
import Foundation
@testable import MyBuddyCore

// Herstelronde: randgevallen van terugkerende reeksen die de eerste ronde miste.
//
// - Een gestopte reeks opnieuw toevoegen (zelfde regel, in elke maand) loopt vanaf die maand gewoon door.
// - "Niet meer terugkerend, alleen deze maand" gevolgd door een herstel van die maand geeft nooit twee regels met één id.
// - De invulhulp met standaardposten en het importeren starten geen tweede reeks naast een bestaande met dezelfde naam.

final class RecoverySeriesTests: XCTestCase {
    private func base(start: YearMonth = aug2026) -> FinanceData {
        var d = FinanceData(startMonth: start)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        return d
    }

    private func named(_ d: FinanceData, _ month: YearMonth, _ name: String, income: Bool = false) -> [MoneyLine] {
        let plan = d.plan(for: month)
        return (income ? plan.extraIncome : plan.expenses).filter { $0.name == name }
    }

    private func presence(_ d: FinanceData, _ name: String, from: YearMonth = aug2026, count: Int, income: Bool = false) -> [Int] {
        from.range(count: count).map { named(d, $0, name, income: income).count }
    }

    private func assertUniqueIDs(_ d: FinanceData, from: YearMonth = aug2026, count: Int,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for m in from.range(count: count) {
            let plan = d.plan(for: m)
            let ids = (plan.expenses + plan.extraIncome).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "dubbele regel-id's in \(m.key)", file: file, line: line)
        }
    }

    private func withGym(materializeUpTo: YearMonth = YearMonth(year: 2026, month: 12)) -> (FinanceData, MoneyLine) {
        var d = base()
        let gym = MoneyLine(name: "Gym", amount: 30, isRecurring: true, day: 15)
        d.addRecurringLine(gym, kind: .expense, in: aug2026)
        d.materialize(upTo: materializeUpTo)
        return (d, gym)
    }

    // MARK: Een gestopte reeks opnieuw toevoegen

    /// Stoppen in oktober en dezelfde regel in november opnieuw toevoegen: oktober blijft leeg, november loopt door.
    func testReAddStoppedLineInLaterMonthContinues() {
        for scenario in 0..<2 {
            var (d, gym) = withGym()
            let oct = named(d, oct2026, "Gym")[0]
            d.removeLine(id: oct.id, kind: .expense, in: oct2026, scope: .thisAndFollowing)
            XCTAssertEqual(presence(d, "Gym", count: 6), [1, 1, 0, 0, 0, 0])
            let nov = YearMonth(year: 2026, month: 11)
            if scenario == 0 {
                d.upsertLine(oct, kind: .expense, in: nov)            // de regel zoals hij was (eigen id en reeks)
            } else {
                d.addRecurringLine(gym, kind: .expense, in: nov)      // de oorspronkelijke regel (zonder reeks-id)
            }
            XCTAssertEqual(presence(d, "Gym", count: 40), [1, 1, 0] + Array(repeating: 1, count: 37), "scenario \(scenario)")
            assertUniqueIDs(d, count: 40)
            // Een nieuwe reeks vanaf november; de oude blijft gestopt.
            let list = d.recurringSeries(kind: .expense).filter { $0.latest.name == "Gym" }
            XCTAssertEqual(list.count, 2)
            XCTAssertEqual(list.map(\.firstMonth), [aug2026, nov])
            XCTAssertEqual(list.map(\.lastMonth), [sep2026, nil])
            // Alles blijft zo na vastleggen, opslaan en inlezen.
            d.materialize(upTo: YearMonth(year: 2027, month: 3))
            XCTAssertEqual(presence(d, "Gym", count: 40), [1, 1, 0] + Array(repeating: 1, count: 37))
        }
    }

    /// Opnieuw toevoegen in december (twee maanden na het einde) geeft een gat van twee maanden.
    func testReAddStoppedLineTwoMonthsLater() {
        var (d, gym) = withGym(materializeUpTo: YearMonth(year: 2027, month: 1))
        let oct = named(d, oct2026, "Gym")[0]
        d.removeLine(id: oct.id, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        d.addRecurringLine(gym, kind: .expense, in: YearMonth(year: 2026, month: 12))
        XCTAssertEqual(presence(d, "Gym", count: 40), [1, 1, 0, 0] + Array(repeating: 1, count: 36))
        assertUniqueIDs(d, count: 40)
    }

    /// In dezelfde maand als het einde werkt het ook (de regel is er dan gewoon nog).
    func testReAddInSameMonthKeepsSeriesRunning() {
        var (d, _) = withGym()
        let oct = named(d, oct2026, "Gym")[0]
        d.removeLine(id: oct.id, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        d.upsertLine(oct, kind: .expense, in: oct2026)
        XCTAssertEqual(presence(d, "Gym", count: 30), Array(repeating: 1, count: 30))
        assertUniqueIDs(d, count: 30)
        // Dezelfde reeks: stoppen en meteen weer toevoegen is een ongedaan maken, geen tweede reeks.
        let list = d.recurringSeries(kind: .expense).filter { $0.latest.name == "Gym" }
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.firstMonth, aug2026)
        XCTAssertNil(list.first?.lastMonth)
    }

    // MARK: Alleen deze maand eenmalig maken en dan herstellen

    func testUnrecurThisMonthThenRestoreHasDistinctIDs() {
        var (d, _) = withGym(materializeUpTo: oct2026)
        var oct = named(d, oct2026, "Gym")[0]
        let sid = oct.seriesID!
        oct.isRecurring = false
        d.updateLine(oct, kind: .expense, in: oct2026, scope: .thisMonth)
        XCTAssertEqual(named(d, oct2026, "Gym").count, 1)
        XCTAssertEqual(presence(d, "Gym", count: 6), [1, 1, 1, 1, 1, 1], "de reeks loopt daarna gewoon door")
        d.restoreSkippedLine(seriesID: sid, in: oct2026)
        let lines = named(d, oct2026, "Gym")
        XCTAssertEqual(lines.count, 2, "de eenmalige regel en de reeksregel")
        XCTAssertEqual(Set(lines.map(\.id)).count, 2, "twee regels met hetzelfde id: \(lines.map(\.id))")
        assertUniqueIDs(d, count: 30)
        // Alle dagboeken blijven sluiten en geven elke regel een eigen gebeurtenis.
        let events = d.dayEvents(in: oct2026, asOf: day(oct2026, 1)).filter { $0.title == "Gym" }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.id)).count, 2)
    }

    /// De eerste maand van een reeks overslaan en terugzetten: de regel is er daarna weer (er was niets om over te nemen).
    func testRestoreSkippedFirstMonthOfSeries() {
        var d = base()
        let gym = MoneyLine(name: "Gym", amount: 30, isRecurring: true, day: 15)
        d.addRecurringLine(gym, kind: .expense, in: aug2026)
        let sid = named(d, aug2026, "Gym")[0].seriesID!
        d.removeLine(id: named(d, aug2026, "Gym")[0].id, kind: .expense, in: aug2026, scope: .thisMonth)
        XCTAssertEqual(presence(d, "Gym", count: 4), [0, 1, 1, 1])
        d.restoreSkippedLine(seriesID: sid, in: aug2026)
        XCTAssertEqual(presence(d, "Gym", count: 12), Array(repeating: 1, count: 12))
        assertUniqueIDs(d, count: 12)
        XCTAssertEqual(d.recurringSeries(kind: .expense).count, 1)
    }

    // MARK: Invullen en importeren naast een bestaande reeks

    /// Een standaardpost die in deze maand is overgeslagen komt met "standaardposten invullen" terug in dezelfde reeks.
    func testFillStandardAfterSkipDoesNotStartSecondSeries() {
        var d = base()
        d.fillStandardExpenses(in: aug2026)
        d.materialize(upTo: oct2026)
        let target = named(d, oct2026, StandardExpenses.all[0].name)[0]
        d.removeLine(id: target.id, kind: .expense, in: oct2026, scope: .thisMonth)
        XCTAssertEqual(presence(d, target.name, count: 6), [1, 1, 0, 1, 1, 1])
        let added = d.fillStandardExpenses(in: oct2026)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(presence(d, target.name, count: 30), Array(repeating: 1, count: 30))
        XCTAssertEqual(d.recurringSeries(kind: .expense).filter { $0.latest.name == target.name }.count, 1)
        XCTAssertTrue(d.missingStandardExpenses(in: oct2026).isEmpty)
        assertUniqueIDs(d, count: 30)
    }

    /// Een standaardpost waarvan de reeks pas in een latere maand begint: de nieuwe regel wordt de eerste van diezelfde reeks.
    func testFillStandardBeforeExistingLaterSeriesJoinsIt() {
        var d = base()
        let name = StandardExpenses.all[0].name
        let dec = YearMonth(year: 2026, month: 12)
        d.addRecurringLine(MoneyLine(name: name, amount: 1234, isRecurring: true, kind: .fixed), kind: .expense, in: dec)
        d.fillStandardExpenses(in: oct2026)
        XCTAssertEqual(presence(d, name, from: oct2026, count: 24), Array(repeating: 1, count: 24))
        XCTAssertEqual(d.recurringSeries(kind: .expense).filter { $0.latest.name == name }.count, 1)
        // De eigen regel van december en alles daarna blijft zoals de gebruiker hem maakte.
        XCTAssertEqual(named(d, dec, name)[0].amount, 1234)
        XCTAssertEqual(named(d, YearMonth(year: 2027, month: 6), name)[0].amount, 1234)
        assertUniqueIDs(d, from: oct2026, count: 24)
    }

    /// Een reeks die al is gestopt telt niet: invullen begint dan een nieuwe reeks (zoals het hoort).
    func testFillStandardAfterStopStartsFreshSeries() {
        var d = base()
        d.fillStandardExpenses(in: aug2026)
        d.materialize(upTo: oct2026)
        let target = named(d, oct2026, StandardExpenses.all[0].name)[0]
        d.removeLine(id: target.id, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        XCTAssertEqual(presence(d, target.name, count: 6), [1, 1, 0, 0, 0, 0])
        d.fillStandardExpenses(in: YearMonth(year: 2026, month: 12))
        XCTAssertEqual(presence(d, target.name, count: 8), [1, 1, 0, 0, 1, 1, 1, 1])
        assertUniqueIDs(d, count: 12)
    }

    func testImportAfterSkipAndBeforeLaterSeriesDoNotDuplicate() {
        // Overgeslagen in oktober, geïmporteerd voor oktober.
        var d = base()
        d.addRecurringLine(MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 1), kind: .expense, in: aug2026)
        d.materialize(upTo: oct2026)
        d.removeLine(id: named(d, oct2026, "Huur")[0].id, kind: .expense, in: oct2026, scope: .thisMonth)
        let draft = ImportDraft(rows: [ImportRow(name: "Huur", amount: 950, category: .vasteLasten, day: 3)])
        let report = d.applyImport(draft, month: oct2026, now: day(oct2026, 12))
        XCTAssertEqual(report.lines.first?.outcome, .added)
        XCTAssertEqual(presence(d, "Huur", count: 24), Array(repeating: 1, count: 24))
        assertUniqueIDs(d, count: 24)

        // Een reeks met dezelfde naam begint pas in december; het bestand gaat naar september.
        var e = base()
        let dec = YearMonth(year: 2026, month: 12)
        e.addRecurringLine(MoneyLine(name: "Huur", amount: 1000, isRecurring: true, kind: .fixed, day: 1), kind: .expense, in: dec)
        e.applyImport(ImportDraft(rows: [ImportRow(name: "huur", amount: 900, category: .vasteLasten, day: 2)]),
                      month: sep2026, now: day(sep2026, 12))
        let counts = sep2026.range(count: 30).map { m in
            e.plan(for: m).expenses.filter { $0.name.lowercased() == "huur" }.count
        }
        XCTAssertEqual(counts, Array(repeating: 1, count: 30), "ook met andere hoofdletters in het bestand")
        XCTAssertEqual(e.recurringSeries(kind: .expense).count, 1)
        assertUniqueIDs(e, from: sep2026, count: 30)
        // De regel van december blijft zoals hij was.
        XCTAssertEqual(e.plan(for: dec).expenses.first { $0.name.lowercased() == "huur" }?.amount, 1000)
    }

    /// Inkomsten werken hetzelfde.
    func testIncomeResumeAfterSkip() {
        var d = base()
        d.addRecurringLine(MoneyLine(name: "Toeslag", amount: 100, isRecurring: true, day: 5), kind: .income, in: aug2026)
        d.materialize(upTo: oct2026)
        d.removeLine(id: named(d, oct2026, "Toeslag", income: true)[0].id, kind: .income, in: oct2026, scope: .thisMonth)
        d.applyImport(ImportDraft(rows: [ImportRow(name: "Toeslag", amount: 120, category: .inkomen)]), month: oct2026,
                      now: day(oct2026, 12))
        XCTAssertEqual(presence(d, "Toeslag", count: 20, income: true), Array(repeating: 1, count: 20))
    }

    // MARK: Bewerken met "deze en alle volgende maanden" laat bewuste latere keuzes staan

    /// Een geplande huurverhoging vanaf december blijft staan als je in oktober het bedrag wijzigt: alleen de maanden die
    /// nog het oude bedrag hadden gaan mee.
    func testEditingEarlierDoesNotResetAPlannedRaise() {
        var d = base()
        d.addRecurringLine(MoneyLine(name: "Huur", amount: 1_000, isRecurring: true, day: 1), kind: .expense, in: aug2026)
        d.materialize(upTo: YearMonth(year: 2027, month: 1))
        let dec = YearMonth(year: 2026, month: 12)
        var raise = named(d, dec, "Huur")[0]
        raise.amount = 1_150
        d.updateLine(raise, kind: .expense, in: dec, scope: .thisAndFollowing)
        XCTAssertEqual(named(d, YearMonth(year: 2027, month: 1), "Huur")[0].amount, 1_150)
        var edited = named(d, oct2026, "Huur")[0]
        edited.amount = 1_050
        d.updateLine(edited, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        func rent(_ m: YearMonth) -> Double { named(d, m, "Huur")[0].amount }
        XCTAssertEqual(rent(sep2026), 1_000)
        for m in [oct2026, YearMonth(year: 2026, month: 11)] { XCTAssertEqual(rent(m), 1_050, m.key) }
        for m in [dec, YearMonth(year: 2027, month: 1), YearMonth(year: 2027, month: 2), YearMonth(year: 2030, month: 6)] {
            XCTAssertEqual(rent(m), 1_150, "de verhoging blijft: \(m.key)")
        }
        assertUniqueIDs(d, count: 60)
    }

    /// Een maand die alleen in het bedrag afweek, volgt een latere wijziging van de dag van de reeks en houdt haar bedrag.
    func testExceptionMonthFollowsAChangeOfTheDayAndKeepsItsAmount() {
        var d = base()
        d.addRecurringLine(MoneyLine(name: "Gym", amount: 40, isRecurring: true, day: 31), kind: .expense, in: aug2026)
        d.materialize(upTo: YearMonth(year: 2027, month: 3))
        let jan = YearMonth(year: 2027, month: 1)
        var special = named(d, jan, "Gym")[0]
        special.amount = 99
        d.updateLine(special, kind: .expense, in: jan, scope: .thisMonth)
        var moved = named(d, oct2026, "Gym")[0]
        moved.day = 3
        d.updateLine(moved, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        let januaryLine = named(d, jan, "Gym")[0]
        XCTAssertEqual(januaryLine.day, 3, "de afwijkende maand volgt de nieuwe dag")
        XCTAssertEqual(januaryLine.amount, 99, "en houdt haar eigen bedrag")
        XCTAssertTrue(januaryLine.isException)
        XCTAssertEqual(named(d, YearMonth(year: 2027, month: 2), "Gym")[0].day, 3)
        XCTAssertEqual(named(d, YearMonth(year: 2027, month: 2), "Gym")[0].amount, 40)
        // De dagboeken vallen op de nieuwe dag.
        let events = d.dayEvents(in: jan, asOf: day(oct2026, 1)).filter { $0.title == "Gym" }
        XCTAssertEqual(events.map(\.day), [3])
    }
}
