import XCTest
import Foundation
@testable import MyBuddyCore

// Herstelronde: oude opgeslagen data (van vóór de reeksen) krijgt zijn reeksen goed gekoppeld.
//
// De oude motor (commit a5bda43) maakte een niet-opgeslagen maand door de terugkerende regels van het LAATST OPGESLAGEN
// plan vóór die maand te kopiëren, met het id `line|<id van die regel>|<maand>` (`MoneyLine.seriesLineID`). Wordt een
// toekomstige maand eerder opgeslagen dan de maanden ertussen, dan is zijn regel dus afgeleid van een regel die niet zijn
// directe voorganger is. Die keten moet bij het lezen van oude data nog steeds één reeks geven, niet twee.

/// De oude motor, nagebouwd: alleen wat voor terugkerende regels nodig is.
private struct LegacyEngine {
    var start: YearMonth
    var months: [String: [MoneyLine]] = [:]   // opgeslagen uitgaven per maand

    func latestStored(before month: YearMonth) -> [MoneyLine]? {
        var best: (YearMonth, [MoneyLine])?
        for (key, lines) in months {
            guard let m = YearMonth(key: key), m < month else { continue }
            if best == nil || m > best!.0 { best = (m, lines) }
        }
        return best?.1
    }

    /// Het plan van een maand zoals de oude motor het gaf.
    func lines(for month: YearMonth) -> [MoneyLine] {
        if let stored = months[month.key] { return stored }
        guard let previous = latestStored(before: month) else { return [] }
        return previous.filter { $0.isRecurring }.map { line in
            var copy = line
            copy.id = MoneyLine.seriesLineID(line.id, in: month)
            return copy
        }
    }

    mutating func upsert(_ line: MoneyLine, in month: YearMonth) {
        var lines = self.lines(for: month)
        if let i = lines.firstIndex(where: { $0.id == line.id }) { lines[i] = line } else { lines.append(line) }
        months[month.key] = lines
    }

    mutating func delete(id: UUID, in month: YearMonth) {
        var lines = self.lines(for: month)
        lines.removeAll { $0.id == id }
        months[month.key] = lines
    }

    mutating func materialize(upTo current: YearMonth) {
        var m = start
        while m <= current {
            if months[m.key] == nil { months[m.key] = lines(for: m) }
            m = m.adding(1)
        }
    }
}

final class RecoveryLegacySeriesTests: XCTestCase {
    private func financeData(from legacy: LegacyEngine) -> FinanceData {
        var d = FinanceData(startMonth: legacy.start)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        for (key, lines) in legacy.months {
            var plan = MonthPlan()
            plan.expenses = lines
            d.months[key] = plan
        }
        return d
    }

    // MARK: Handgemaakte gevallen

    /// December werd in oktober al opgeslagen (afgeleid van oktober), november daarna: één reeks, geen dubbele huur.
    func testFutureMonthStoredBeforeIntermediateMonth() {
        let nov = YearMonth(year: 2026, month: 11)
        let dec = YearMonth(year: 2026, month: 12)
        func derive(_ l: MoneyLine, _ m: YearMonth) -> MoneyLine {
            var c = l
            c.id = MoneyLine.seriesLineID(l.id, in: m)
            return c
        }
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        let x = MoneyLine(name: "Huur", amount: 1000, isRecurring: true)
        let sepLine = derive(x, sep2026)
        let octLine = derive(sepLine, oct2026)
        let novLine = derive(octLine, nov)
        let decLine = derive(octLine, dec)   // december stond al opgeslagen toen oktober het laatste plan was
        for (m, line) in [(aug2026, x), (sep2026, sepLine), (oct2026, octLine), (nov, novLine), (dec, decLine)] {
            var plan = MonthPlan()
            plan.expenses = [line]
            d.months[m.key] = plan
        }
        for m in aug2026.range(count: 12) {
            XCTAssertEqual(d.plan(for: m).expenses.filter { $0.name == "Huur" }.count, 1, "Huur in \(m.key)")
        }
        XCTAssertEqual(d.expensesTotal(in: dec), 1000)
        XCTAssertEqual(d.expensesTotal(in: YearMonth(year: 2027, month: 6)), 1000)
        // Eén reeks, ook na wegschrijven van de afleiding en na opnieuw inlezen.
        XCTAssertEqual(d.recurringSeries(kind: .expense).count, 1)
        d.migrateRecurringSeries()
        XCTAssertEqual(d.recurringSeries(kind: .expense).count, 1)
        XCTAssertEqual(d.expensesTotal(in: dec), 1000)
    }

    /// De allereerste versie gaf elke vastgelegde maand een willekeurig nieuw id: dezelfde naam, soort en dag horen bij elkaar.
    func testRandomIDsPerStoredMonthStillOneSeries() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        for m in [aug2026, sep2026, oct2026] {
            var plan = MonthPlan()
            plan.expenses = [MoneyLine(name: "Huur", amount: 1000, isRecurring: true, day: 1)]   // elke maand een eigen id
            d.months[m.key] = plan
        }
        for m in aug2026.range(count: 8) {
            XCTAssertEqual(d.plan(for: m).expenses.filter { $0.name == "Huur" }.count, 1, "Huur in \(m.key)")
        }
        XCTAssertEqual(d.expensesTotal(in: YearMonth(year: 2027, month: 3)), 1000)
        XCTAssertEqual(d.recurringSeries(kind: .expense).count, 1)
    }

    /// Twee echt verschillende regels met dezelfde naam in dezelfde maand blijven twee reeksen.
    func testTwoSeriesWithSameNameStayTwo() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        for m in [aug2026, sep2026] {
            var plan = MonthPlan()
            plan.expenses = [MoneyLine(name: "Abonnement", amount: 10, isRecurring: true),
                             MoneyLine(name: "Abonnement", amount: 20, isRecurring: true)]
            d.months[m.key] = plan
        }
        XCTAssertEqual(d.recurringSeries(kind: .expense).count, 2, "twee reeksen, geen vier")
        XCTAssertEqual(d.plan(for: oct2026).expenses.filter { $0.name == "Abonnement" }.count, 2)
        XCTAssertEqual(d.expensesTotal(in: oct2026), 30)
    }

    // MARK: Eigenschapstest tegen de oude motor

    /// Willekeurige bewerkingen volgens de oude motor (toevoegen, bewerken, verwijderen, vastleggen, ook in toekomstige
    /// maanden) geven oude data. De nieuwe motor mag daar nooit een regel dubbel van maken en mag het bedrag en de dag van
    /// een regel die de oude motor toonde niet veranderen. (Een regel die in de oude data ontbrak komt terug: bedoeld.)
    func testLegacyDataNeverDuplicatesAndKeepsWhatWasShown() {
        let seeds = Int(ProcessInfo.processInfo.environment["LEGACY_SEEDS"] ?? "") ?? 300
        let collector = Collector()
        for seed in 1...seeds {
            var r = EngRandom(seed: UInt64(seed) &+ 710_000)
            var legacy = LegacyEngine(start: aug2026)
            let horizon = 14
            var names: [String] = []
            var log: [String] = []
            let steps = r.int(4...16)
            for step in 0..<steps {
                let month = aug2026.adding(r.int(0...horizon - 1))
                switch r.int(0...9) {
                case 0...3:
                    // Een nieuwe terugkerende regel (of een eenmalige) toevoegen.
                    let name = "S\(names.count)"
                    names.append(name)
                    let line = MoneyLine(name: name, amount: Double(r.int(10...900)), isRecurring: r.chance(85), day: r.chance(70) ? r.int(1...31) : nil)
                    legacy.upsert(line, in: month)
                    log.append("\(step): voeg \(name) toe in \(month.key)")
                case 4...5:
                    // Bewerken: bedrag en dag van een bestaande regel in die maand.
                    let lines = legacy.lines(for: month)
                    guard !lines.isEmpty else { continue }
                    var line = lines[r.int(0...lines.count - 1)]
                    line.amount = Double(r.int(10...900))
                    if r.chance(40) { line.day = r.int(1...31) }
                    legacy.upsert(line, in: month)
                    log.append("\(step): bewerk \(line.name) in \(month.key)")
                case 6:
                    let lines = legacy.lines(for: month)
                    guard !lines.isEmpty else { continue }
                    let line = lines[r.int(0...lines.count - 1)]
                    legacy.delete(id: line.id, in: month)
                    log.append("\(step): verwijder \(line.name) in \(month.key)")
                default:
                    let upTo = aug2026.adding(r.int(0...horizon - 1))
                    legacy.materialize(upTo: upTo)
                    log.append("\(step): leg vast t/m \(upTo.key)")
                }
            }
            var d = financeData(from: legacy)
            // De oude afleiding blijft hetzelfde na het wegschrijven.
            var migrated = d
            migrated.migrateRecurringSeries()
            for m in aug2026.range(count: 36) {
                let old = legacy.lines(for: m)
                for variant in [d, migrated] {
                    let new = variant.plan(for: m).expenses
                    var counts: [String: Int] = [:]
                    for line in new where line.isRecurring { counts[line.name, default: 0] += 1 }
                    for line in old where line.isRecurring {
                        collector.eq(counts[line.name] ?? 0, 1, "seed \(seed) \(m.key): \(line.name) komt niet precies één keer voor; \(log)")
                    }
                    for line in old {
                        guard let match = new.first(where: { $0.name == line.name }) else {
                            collector.ok(false, "seed \(seed) \(m.key): \(line.name) ontbreekt; \(log)")
                            continue
                        }
                        collector.eq(match.amount, line.amount, "seed \(seed) \(m.key): bedrag van \(line.name); \(log)")
                        collector.eq(match.day, line.day, "seed \(seed) \(m.key): dag van \(line.name); \(log)")
                    }
                    // Nergens een naam dubbel (alle namen zijn uniek in deze test).
                    var all: [String: Int] = [:]
                    for line in new { all[line.name, default: 0] += 1 }
                    for (name, n) in all { collector.eq(n, 1, "seed \(seed) \(m.key): \(name) staat \(n) keer; \(log)") }
                }
            }
            d.materialize(upTo: aug2026.adding(horizon))
        }
        collector.report()
    }
}
