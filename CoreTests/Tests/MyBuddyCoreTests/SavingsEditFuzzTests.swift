import XCTest
@testable import MyBuddyCore

/// Willekeurige reeksen bewerkingen op de logica van de schermen: de cijfers blijven overal gelijk en sluiten.
final class SavingsEditFuzzTests: XCTestCase {
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
    }

    private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }
    private let now = YearMonth(year: 2026, month: 10)

    private func makeData(_ g: inout Generator) -> (FinanceData, [UUID]) {
        var d = FinanceData(startMonth: ym(2026, 8))
        d.salary.fixedMonthly = Double(g.int(0...6000))
        d.salary.payDay = g.int(1...31)
        if g.int(0...2) == 0 {
            let schedule: SalarySchedule = g.int(0...1) == 0 ? .weeks : .days
            let interval = schedule == .weeks ? g.int(1...6) : g.int(1...45)
            d.salary.setSchedule(schedule, interval: interval,
                                 anchor: CalendarDay(year: 2026, month: g.int(7...11), day: g.int(1...28)))
        }
        var ids: [UUID] = []
        for i in 0..<g.int(1...3) {
            let pot = Pot(name: "Pot \(i)", monthlyContribution: Double(g.int(0...500)), startMonth: ym(2026, g.int(8...10)))
            d.pots.append(pot)
            ids.append(pot.id)
        }
        for i in 0..<g.int(0...2) {
            let holding = Holding(name: "Belegging \(i)", monthlyContribution: Double(g.int(0...400)), startMonth: ym(2026, 8))
            d.holdings.append(holding)
            ids.append(holding.id)
        }
        if g.int(0...1) == 0 {
            d.bankSnapshots.append(BankSnapshot(date: ym(2026, 8).date(day: 20), balance: Double(g.int(-500...5000))))
        }
        d.materialize(upTo: now)
        for _ in 0..<g.int(0...3) {
            let month = ym(2026, g.int(9...12))
            d.editPlan(month) {
                $0.extraIncome.append(MoneyLine(name: "Extra", amount: Double(g.int(1...900)), day: g.int(1...31)))
            }
        }
        return (d, ids)
    }

    func testAllocationEditsKeepEverythingConsistent() throws {
        for seed in 0..<250 {
            var g = Generator(state: UInt64(seed) &* 7919 &+ 17)
            var (d, ids) = makeData(&g)
            let months = [ym(2026, 9), ym(2026, 10), ym(2026, 11), ym(2026, 12), ym(2027, 1)]
            for step in 0..<25 {
                let id = g.pick(ids)
                let month = g.pick(months)
                let before = CentsMath.int(d.allocation(id, in: month))
                switch g.int(0...7) {
                case 0:
                    AllocationEdit.setMode(&d, id: id, month: month, to: .percentage)
                    // De afronding op twee decimalen van het percentage: hoogstens 0,005 procentpunt van het inkomen.
                    if month >= d.startMonth, case .percent(let rule) = d.allocationRule(id, in: month), rule.percent > 0 {
                        let income = d.incomeBases(in: month).cents(for: rule.basis)
                        let after = CentsMath.int(d.allocation(id, in: month))
                        if before >= 0, case .percent(let standard)? = d.defaultAllocationRule(id, in: month), standard.percent > 0 {
                            _ = standard // de standaard komt terug: het bedrag mag verspringen
                        } else if income > 0 && before <= income {
                            // Een bedrag boven het inkomen past niet in 100%: dan wordt het begrensd.
                            XCTAssertLessThanOrEqual(abs(after - before), income / 20_000 + 2, "seed \(seed) stap \(step)")
                        }
                    }
                case 1:
                    AllocationEdit.setMode(&d, id: id, month: month, to: .fixed)
                    XCTAssertEqual(CentsMath.int(d.allocation(id, in: month)), before, "seed \(seed) stap \(step)")
                case 2:
                    AllocationEdit.setPercent(&d, id: id, month: month, percent: Double(g.int(0...12_000)) / 100)
                case 3:
                    AllocationEdit.setBasis(&d, id: id, month: month, to: g.int(0...1) == 0 ? .salary : .allIncome)
                case 4:
                    AllocationEdit.setAmount(&d, id: id, month: month, amount: Double(g.int(-100...900)))
                case 5:
                    AllocationEdit.resetToStandard(&d, id: id, month: month)
                    XCTAssertFalse(d.effectiveAllocation(id, in: month).isOverride, "seed \(seed) stap \(step)")
                case 6:
                    AllocationEdit.makeStandard(&d, id: id, month: month, current: now)
                    if month >= now {
                        XCTAssertFalse(d.effectiveAllocation(id, in: month).isOverride, "seed \(seed) stap \(step)")
                    }
                default:
                    AllocationEdit.setPercent(&d, id: id, month: month, percent: .nan)
                }

                // Overal hetzelfde bedrag: rij, overzicht en dagen.
                for m in months {
                    let figures = d.monthFigures(m)
                    var saved = 0
                    var invested = 0
                    for pot in d.pots { saved = CentsMath.add(saved, CentsMath.int(d.allocation(pot.id, in: m))) }
                    for holding in d.holdings { invested = CentsMath.add(invested, CentsMath.int(d.allocation(holding.id, in: m))) }
                    XCTAssertEqual(figures.saved, saved, "seed \(seed) stap \(step) maand \(m.key)")
                    XCTAssertEqual(figures.invested, invested, "seed \(seed) stap \(step) maand \(m.key)")
                    for itemID in ids {
                        let effective = d.effectiveAllocation(itemID, in: m)
                        XCTAssertEqual(effective.amount, d.allocation(itemID, in: m), "seed \(seed) stap \(step)")
                        XCTAssertGreaterThanOrEqual(effective.amount, m >= d.startMonth && effective.rule.isPercent ? 0 : -1e12)
                    }
                }
                let ledger = d.monthLedger(month, asOf: ym(2026, 10).date(day: 14))
                XCTAssertTrue(ledger.allReconciles, "seed \(seed) stap \(step) maand \(month.key)")
                XCTAssertEqual(ledger.saved, d.savedTotal(in: month))
                XCTAssertEqual(ledger.invested, d.investedTotal(in: month))
                // Een waarschuwing heeft altijd een tekst; geen crash bij meer dan 100%.
                for warning in d.allocationWarnings(in: month) { XCTAssertFalse(warning.message.isEmpty) }
            }
        }
    }

    func testSalarySchedulesNeverBreakTheOverview() {
        for seed in 0..<250 {
            var g = Generator(state: UInt64(seed) &* 104_729 &+ 3)
            var (d, _) = makeData(&g)
            // Wissel een paar keer van schema, zoals het scherm dat doet.
            for _ in 0..<6 {
                let schedule = g.pick(SalarySchedule.allCases)
                SalaryScheduleEdit.change(&d, to: schedule, today: ym(2026, 10).date(day: g.int(1...28)))
                if schedule != .monthly {
                    d.salary.setSchedule(schedule, interval: g.int(1...(schedule == .weeks ? 52 : 366)))
                }
            }
            for offset in 0..<14 {
                let month = ym(2026, 8).adding(offset)
                let plan = d.plan(for: month)
                let payouts = d.salaryPayouts(in: month, plan: plan)
                let total = CentsMath.sum(payouts.map { $0.cents })
                XCTAssertEqual(CentsMath.value(total), d.salaryAmount(in: month), "seed \(seed) maand \(month.key)")
                XCTAssertLessThanOrEqual(CentsMath.int(d.salaryAmount(in: month)), Int.max / 4)
                let ledger = d.monthLedger(month, asOf: ym(2026, 10).date(day: 14))
                XCTAssertTrue(ledger.allReconciles, "seed \(seed) maand \(month.key)")
                // De uitbetalingen op hun eigen dag, binnen de maand.
                for payout in payouts { XCTAssertTrue((1...month.dayCount).contains(payout.day)) }
            }
        }
    }
}

/// Willekeurige reeksen bewerkingen op regels (toevoegen, wijzigen met reikwijdte, verwijderen).
final class LineSaveFuzzTests: XCTestCase {
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
    }

    private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

    func testLineOperationsKeepMonthsConsistent() throws {
        let names = ["Huur", "huur", "Sportschool", "Streaming", "Zorgtoeslag"]
        for seed in 0..<300 {
            var g = Generator(state: UInt64(seed) &* 6364136223846793005 &+ 11)
            var d = FinanceData(startMonth: ym(2026, 8))
            d.salary.fixedMonthly = 2500
            d.pots = [Pot(name: "Spaar", monthlyContribution: 100, startMonth: ym(2026, 8))]
            d.materialize(upTo: ym(2026, 10))
            let months = (0..<8).map { ym(2026, 8).adding($0) }
            for step in 0..<30 {
                let month = g.pick(months)
                let kind: FinanceData.LineKind = g.int(0...3) == 0 ? .income : .expense
                let plan = d.plan(for: month)
                let existing = kind == .income ? plan.extraIncome : plan.expenses
                switch g.int(0...4) {
                case 0, 1:
                    // Nieuwe regel, vaak terugkerend, soms met dezelfde naam als een eerdere.
                    var line = MoneyLine(name: g.pick(names), amount: Double(g.int(1...900)), isRecurring: g.int(0...2) > 0,
                                         kind: g.int(0...1) == 0 ? .fixed : .variable, day: g.int(0...1) == 0 ? nil : g.int(1...31))
                    if kind == .income { line.kind = .fixed }
                    LineSave.apply(&d, edited: line, isNew: true, kind: kind, month: month, scope: .thisAndFollowing)
                case 2:
                    guard let target = existing.first else { continue }
                    var edited = target
                    edited.amount = Double(g.int(1...900))
                    if g.int(0...3) == 0 { edited.isRecurring.toggle() }
                    if g.int(0...3) == 0 { edited.day = g.int(1...31) }
                    guard edited != target else { continue }
                    let scope: SeriesScope = g.int(0...1) == 0 ? .thisMonth : .thisAndFollowing
                    LineSave.apply(&d, edited: edited, isNew: false, kind: kind, month: month, scope: scope)
                case 3:
                    guard let target = existing.last else { continue }
                    let scope: SeriesScope = g.int(0...1) == 0 ? .thisMonth : .thisAndFollowing
                    d.removeLine(id: target.id, kind: kind, in: month, scope: scope)
                default:
                    // Een maand bekijken bewaart niets; bewerk de verdeling zoals het scherm Verdelen.
                    AllocationEdit.setAmount(&d, id: d.pots[0].id, month: month, amount: Double(g.int(0...300)))
                }

                for m in months {
                    let p = d.plan(for: m)
                    for lines in [p.extraIncome, p.expenses] {
                        XCTAssertEqual(Set(lines.map { $0.id }).count, lines.count, "dubbel id: seed \(seed) stap \(step) maand \(m.key)")
                        let series = lines.compactMap { $0.isRecurring ? $0.seriesID : nil }
                        XCTAssertEqual(Set(series).count, series.count, "dubbele reeks: seed \(seed) stap \(step) maand \(m.key)")
                    }
                }
                let ledger = d.monthLedger(month, asOf: ym(2026, 10).date(day: 14))
                XCTAssertTrue(ledger.allReconciles, "seed \(seed) stap \(step) maand \(month.key)")
            }
        }
    }
}
