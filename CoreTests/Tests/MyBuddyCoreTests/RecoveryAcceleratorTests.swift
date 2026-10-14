import XCTest
import Foundation
@testable import MyBuddyCore

// Herstelronde: versnellers op terugkerende regels (reeksen).
//
// - Herstellen zet het oude bedrag ook terug als de maand van het toepassen alleen een teken van een andere reeks had
//   (overgeslagen of gestopt), of als de regel in de toepassingsmaand daarna is overgeslagen.
// - Een reeks die later van bedrag verschilt (huurverhoging) gaat per maand terug naar zijn eigen oude bedrag, ook voor
//   maanden die na het toepassen zijn vastgelegd.
// - Een uitgave die in de maand alleen voor die maand is aangepast ("alleen deze maand") wordt niet verlaagd (en niet voorgesteld).
// - Tweeling-test: dezelfde gebruikersacties op twee kopieën, op één eerst toepassen en dan herstellen, geeft daarna in
//   elke maand precies dezelfde regels als de tweeling zonder versneller.

private let applyDay = day(oct2026, 12)

private func fixture(hourly: Bool = false) -> (data: FinanceData, pot: Pot, goal: LifeGoal) {
    var d = makeBaseData()
    if hourly { d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36) }
    var pot = Pot(name: "Vakantie", symbol: "airplane", monthlyContribution: 300, startMonth: aug2026)
    pot.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    pot.id = StableID.uuid("recovery-pot")
    d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
    var goal = LifeGoal(name: "Japan", kind: .vacation)
    goal.id = StableID.uuid("recovery-goal")
    goal.targetAmount = 6000
    goal.inflationAdjusted = false
    goal.funding = .pot(pot.id)
    d.addGoal(goal)
    return (d, pot, goal)
}

private func rent(_ d: FinanceData, _ month: YearMonth) -> Double {
    d.plan(for: month).expenses.first { $0.name == "Huur" }?.amount ?? -1
}

private func expenseAccelerator(_ d: FinanceData, goal: LifeGoal) -> Accelerator? {
    d.accelerators(for: goal, current: oct2026, today: applyDay).first { $0.id.hasPrefix("expense") }
}

final class RecoveryAcceleratorTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)
    private let dec = YearMonth(year: 2026, month: 12)
    private let jan = YearMonth(year: 2027, month: 1)

    /// Een andere reeks is gestopt: oktober heeft alleen het teken. Het bedrag van de huur moet toch terug.
    func testRestoreWhenApplyMonthOnlyHadAMarkerOfAnotherSeries() {
        var (d, _, goal) = fixture()
        d.addRecurringLine(MoneyLine(name: "Krant", amount: 20, isRecurring: true, day: 5), kind: .expense, in: aug2026)
        let krant = d.plan(for: oct2026).expenses.first { $0.name == "Krant" }!
        d.removeLine(id: krant.id, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        d.materialize(upTo: oct2026)
        guard let acc = expenseAccelerator(d, goal: goal), let record = d.apply(acc, for: goal, current: oct2026, now: applyDay) else {
            return XCTFail("versneller niet toegepast")
        }
        XCTAssertEqual(rent(d, oct2026), 900)
        XCTAssertEqual(rent(d, nov), 900)
        XCTAssertTrue(d.restoreAccelerator(record.id))
        for m in oct2026.range(count: 24) { XCTAssertEqual(rent(d, m), 1000, m.key) }
    }

    /// Huurverhoging vanaf december, versneller in oktober, januari wordt daarna vastgelegd: elke maand krijgt zijn eigen bedrag terug.
    func testRestoreWithRentRaiseAndMonthMaterializedAfterApply() {
        var (d, _, goal) = fixture()
        var line = d.plan(for: dec).expenses.first { $0.name == "Huur" }!
        line.amount = 1150
        d.updateLine(line, kind: .expense, in: dec, scope: .thisAndFollowing)
        d.materialize(upTo: oct2026)
        guard let acc = expenseAccelerator(d, goal: goal), let record = d.apply(acc, for: goal, current: oct2026, now: applyDay) else {
            return XCTFail("versneller niet toegepast")
        }
        XCTAssertEqual(rent(d, oct2026), 900)
        XCTAssertEqual(rent(d, dec), 1050)
        d.materialize(upTo: jan)   // de tijd gaat door: november en januari worden vastgelegd
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertEqual(rent(d, oct2026), 1000)
        XCTAssertEqual(rent(d, nov), 1000)
        XCTAssertEqual(rent(d, dec), 1150)
        XCTAssertEqual(rent(d, jan), 1150, "januari (vastgelegd na het toepassen) blijft niet op het verlaagde bedrag")
        XCTAssertEqual(rent(d, YearMonth(year: 2027, month: 6)), 1150)
    }

    /// De regel in de toepassingsmaand wordt daarna voor die maand overgeslagen: de maanden erna blijven niet verlaagd.
    func testRestoreWhenLineWasSkippedInApplyMonthAfterwards() {
        var (d, _, goal) = fixture()
        d.materialize(upTo: oct2026)
        guard let acc = expenseAccelerator(d, goal: goal), let record = d.apply(acc, for: goal, current: oct2026, now: applyDay) else {
            return XCTFail("versneller niet toegepast")
        }
        let line = d.plan(for: oct2026).expenses.first { $0.name == "Huur" }!
        d.removeLine(id: line.id, kind: .expense, in: oct2026, scope: .thisMonth)
        XCTAssertEqual(rent(d, oct2026), -1)
        XCTAssertEqual(rent(d, nov), 900)
        d.materialize(upTo: dec)
        XCTAssertTrue(d.restoreAccelerator(record.id))
        for m in nov.range(count: 24) { XCTAssertEqual(rent(d, m), 1000, m.key) }
        XCTAssertEqual(rent(d, oct2026), -1, "de maand die de gebruiker zelf oversloeg blijft overgeslagen")
    }

    /// Extra uren: de inkomstenregel van de toepassingsmaand wordt daarna overgeslagen (dat raadt de bevestiging zelf aan);
    /// herstellen haalt de reeks ook uit de maanden erna.
    func testRestoreHoursWhenLineWasSkippedInApplyMonthAfterwards() {
        var (d, _, goal) = fixture(hourly: true)
        d.materialize(upTo: oct2026)
        guard let acc = d.accelerators(for: goal, current: oct2026, today: applyDay).first(where: { $0.id == "hours" }),
              let record = d.apply(acc, for: goal, current: oct2026, now: applyDay) else {
            return XCTFail("versneller niet toegepast")
        }
        let name = "Extra uren (2 uur per week)"
        let line = d.plan(for: oct2026).extraIncome.first { $0.name == name }!
        d.removeLine(id: line.id, kind: .income, in: oct2026, scope: .thisMonth)
        d.materialize(upTo: dec)
        XCTAssertTrue(d.restoreAccelerator(record.id))
        for m in oct2026.range(count: 24) {
            XCTAssertTrue(d.plan(for: m).extraIncome.filter { $0.name == name }.isEmpty, "extra uren staan nog in \(m.key)")
        }
        XCTAssertTrue(d.recurringSeries(kind: .income).filter { $0.latest.name == name }.isEmpty)
    }

    /// Een uitgave die in deze maand alleen voor deze maand is aangepast, wordt niet voorgesteld en niet verlaagd.
    func testExpenseCutIsRefusedOnAnExceptionMonth() {
        var (d, _, goal) = fixture()
        d.materialize(upTo: oct2026)
        guard let acc = expenseAccelerator(d, goal: goal) else { return XCTFail("geen voorstel") }
        var line = d.plan(for: oct2026).expenses.first { $0.name == "Huur" }!
        line.amount = 1352
        d.updateLine(line, kind: .expense, in: oct2026, scope: .thisMonth)
        // De huur wordt niet meer voorgesteld...
        XCTAssertNil(d.accelerators(for: goal, current: oct2026, today: applyDay).first { $0.id == acc.id })
        // ...en een oud voorstel wordt met een duidelijke melding geweigerd, zonder iets te veranderen.
        let before = d
        XCTAssertNil(d.apply(acc, for: goal, current: oct2026, now: applyDay))
        XCTAssertEqual(d, before)
        let plan = d.applyPlan(acc, for: goal, current: oct2026, now: applyDay)
        XCTAssertTrue(plan.lines.isEmpty)
        XCTAssertTrue((plan.message ?? "").contains("alleen deze maand"), plan.message ?? "geen melding")
        // Na "deze en alle volgende maanden" aanpassen kan het wel weer.
        line = d.plan(for: oct2026).expenses.first { $0.name == "Huur" }!
        d.updateLine(line, kind: .expense, in: oct2026, scope: .thisAndFollowing)
        XCTAssertNotNil(expenseAccelerator(d, goal: goal))
    }

    // MARK: Tweeling-test

    private struct Rand {
        var state: UInt64
        mutating func next(_ k: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(k))
        }
    }

    private func normalized(_ d: FinanceData, months: Int) -> [String] {
        var out: [String] = []
        for m in aug2026.range(count: months) {
            let plan = d.plan(for: m)
            func describe(_ l: MoneyLine, _ tag: String) -> String {
                "\(m.key) \(tag) \(l.name) \(l.amount) d=\(l.day.map(String.init) ?? "-") \(l.kind) rec=\(l.isRecurring) shares=\(l.potShares.map { "\($0.amount)" })"
            }
            out += plan.expenses.map { describe($0, "E") }.sorted()
            out += plan.extraIncome.map { describe($0, "I") }.sorted()
        }
        return out
    }

    private func runTwin(hours: Bool, seeds: ClosedRange<Int>) {
        var failures: [String] = []
        var applied = 0
        for seed in seeds {
            var base = fixture(hourly: hours)
            let potID = base.pot.id

            /// Een willekeurige handeling van de gebruiker. De huur telt mee: bewerken, overslaan en stoppen ervan hoort
            /// bij wat herstellen moet overleven.
            /// `protected`: de naam van de verlaagde uitgave. Die bewerkt de gebruiker na het toepassen niet meer (daarna terug
            /// naar vóór de versneller is dan de bedoeling: zie `restoreAccelerator`); overslaan en stoppen mag wel.
            func userOp(_ d: inout FinanceData, _ r: inout Rand, log: inout [String], allowPercentage: Bool,
                        protected: String? = nil) {
                let m = aug2026.adding(r.next(14))
                var which = r.next(9)
                if which == 8 && !allowPercentage { which = 3 }
                func editable(_ l: MoneyLine) -> Bool { l.isRecurring && (l.name.hasPrefix("G") || l.name == "Huur") }
                switch which {
                case 0:
                    let counter = r.next(1_000_000)
                    let line = MoneyLine(id: StableID.uuid("recovery-line-\(seed)-\(counter)"), name: "G\(counter)",
                                         amount: Double(10 + r.next(200)), isRecurring: true, day: r.next(3) == 0 ? nil : 1 + r.next(31))
                    d.addRecurringLine(line, kind: .expense, in: m)
                    log.append("add G\(counter) \(m.key)")
                case 1:
                    let lines = d.plan(for: m).expenses.filter { editable($0) && $0.name != protected }.sorted { $0.name < $1.name }
                    guard !lines.isEmpty else { return }
                    var line = lines[r.next(lines.count)]
                    line.amount = Double(10 + r.next(300) + (line.name == "Huur" ? 800 : 0))
                    let scope: SeriesScope = r.next(2) == 0 ? .thisMonth : .thisAndFollowing
                    d.updateLine(line, kind: .expense, in: m, scope: scope)
                    log.append("update \(line.name) \(m.key) \(scope)")
                case 2:
                    let lines = d.plan(for: m).expenses.filter(editable).sorted { $0.name < $1.name }
                    guard !lines.isEmpty else { return }
                    let line = lines[r.next(lines.count)]
                    let scope: SeriesScope = r.next(2) == 0 ? .thisMonth : .thisAndFollowing
                    d.removeLine(id: line.id, kind: .expense, in: m, scope: scope)
                    log.append("remove \(line.name) \(m.key) \(scope)")
                case 3:
                    d.materialize(upTo: m)
                    log.append("materialize \(m.key)")
                case 4:
                    d.editPlan(m) { $0.transferDay = 1 + r.next(28) }
                    log.append("store \(m.key)")
                case 5:
                    let counter = r.next(1_000_000)
                    d.upsertLine(MoneyLine(id: StableID.uuid("recovery-one-\(seed)-\(counter)"), name: "O\(counter)",
                                           amount: Double(5 + r.next(90)), isRecurring: false), kind: .income, in: m)
                    log.append("oneoff \(m.key)")
                case 6:
                    let counter = r.next(1_000_000)
                    let line = MoneyLine(id: StableID.uuid("recovery-line-\(seed)-\(counter)"), name: "GI\(counter)",
                                         amount: Double(10 + r.next(200)), isRecurring: true, day: 1 + r.next(31))
                    d.addRecurringLine(line, kind: .income, in: m)
                    log.append("addIncome GI\(counter) \(m.key)")
                case 7:
                    let lines = d.plan(for: m).extraIncome.filter { $0.name.hasPrefix("GI") }.sorted { $0.name < $1.name }
                    guard !lines.isEmpty else { return }
                    let line = lines[r.next(lines.count)]
                    let scope: SeriesScope = r.next(2) == 0 ? .thisMonth : .thisAndFollowing
                    d.removeLine(id: line.id, kind: .income, in: m, scope: scope)
                    log.append("removeIncome \(line.name) \(m.key) \(scope)")
                default:
                    d.setAllocationPercent(potID, in: m, percent: Double(r.next(1500)) / 100)
                    log.append("pct \(m.key)")
                }
            }

            var preOps: [String] = []
            var pre = Rand(state: UInt64(seed) &* 31)
            for _ in 0..<pre.next(5) { userOp(&base.data, &pre, log: &preOps, allowPercentage: true) }
            base.data.materialize(upTo: oct2026)
            var twin = base.data
            var a = base.data
            let prefix = hours ? "hours" : "expense"
            guard let acc = a.accelerators(for: base.goal, current: oct2026, today: applyDay)
                .first(where: { $0.id == prefix || $0.id.hasPrefix(prefix + "-") }) else { continue }
            guard let record = a.apply(acc, for: base.goal, current: oct2026, now: applyDay) else { continue }
            applied += 1
            var ops: [String] = []
            var ra = Rand(state: UInt64(seed) &* 1_000_003)
            var rb = Rand(state: UInt64(seed) &* 1_000_003)
            var logB: [String] = []
            let steps = 1 + ra.next(8)
            _ = rb.next(8)   // zelfde stand als `ra`: beide kanten doen precies dezelfde handelingen
            var protectedName: String?
            if !hours, let lineID = UUID(uuidString: String(acc.id.dropFirst("expense-".count))) {
                protectedName = base.data.plan(for: oct2026).expenses.first { $0.id == lineID }?.name
            }
            for _ in 0..<steps {
                userOp(&a, &ra, log: &ops, allowPercentage: false, protected: protectedName)
                userOp(&twin, &rb, log: &logB, allowPercentage: false, protected: protectedName)
            }
            if !a.restoreAccelerator(record.id) {
                failures.append("seed \(seed) herstellen geweigerd, pre=\(preOps) ops=\(ops)")
                continue
            }
            let na = normalized(a, months: 48)
            let nb = normalized(twin, months: 48)
            if na != nb {
                let diff = zip(na, nb).first { $0 != $1 }
                failures.append("seed \(seed) \(prefix) na herstel: \(diff?.0 ?? "-") <> \(diff?.1 ?? "-") pre=\(preOps) ops=\(ops)")
            }
            for m in aug2026.range(count: 20) where a.monthFigures(m) != twin.monthFigures(m) {
                failures.append("seed \(seed) cijfers \(m.key) verschillen")
                break
            }
            if let raw = try? FinanceStorage.makeFileEncoder().encode(a),
               let back = try? FinanceStorage.makeDecoder().decode(FinanceData.self, from: raw),
               normalized(back, months: 48) != na {
                failures.append("seed \(seed) bestand-rondreis verschilt")
            }
        }
        XCTAssertGreaterThan(applied, seeds.count / 3, "te weinig toepassingen om iets te bewijzen: \(applied)")
        XCTAssertEqual(failures.count, 0, "\(failures.count) fouten, de eerste:\n" + failures.prefix(6).joined(separator: "\n"))
    }

    func testExpenseCutThenRestoreEqualsTwinWithoutAccelerator() {
        runTwin(hours: false, seeds: 1...(Int(ProcessInfo.processInfo.environment["ACCEL_SEEDS"] ?? "") ?? 300))
    }

    func testExtraHoursThenRestoreEqualsTwinWithoutAccelerator() {
        runTwin(hours: true, seeds: 1...(Int(ProcessInfo.processInfo.environment["ACCEL_SEEDS"] ?? "") ?? 300))
    }
}
