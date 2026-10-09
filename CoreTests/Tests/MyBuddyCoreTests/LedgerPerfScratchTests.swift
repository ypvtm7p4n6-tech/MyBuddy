import XCTest
@testable import MyBuddyCore

final class LedgerPerfScratchTests: XCTestCase {
    static func perfData() -> (FinanceData, YearMonth) {
        let start = YearMonth(year: 2021, month: 11)
        var d = FinanceData(startMonth: start)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3200, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var plan = MonthPlan()
        for i in 0..<30 {
            plan.expenses.append(MoneyLine(name: "Uitgave \(i)", amount: Double(10 + i * 7), isRecurring: true,
                                           kind: i % 2 == 0 ? .fixed : .variable, day: 1 + (i * 3) % 28))
        }
        plan.extraIncome = [MoneyLine(name: "Toeslag", amount: 120, isRecurring: true, day: 20)]
        d.months[start.key] = plan
        var potIDs: [UUID] = []
        for i in 0..<10 {
            var pot = Pot(name: "Pot \(i)", monthlyContribution: Double(20 + i * 10), startMonth: start)
            if i % 2 == 0 { pot.interestRate = 0.02; pot.interestPayout = .monthly; pot.interestPayoutDay = 1 }
            if i % 3 == 0 { pot.transferDay = 1 + i }
            d.addPot(pot, openingBalance: 500, now: day(start, 1))
            potIDs.append(pot.id)
        }
        for i in 0..<8 {
            let h = Holding(name: "Belegging \(i)", kind: .etf, monthlyContribution: Double(25 + i * 5), startMonth: start)
            d.holdings.append(h)
        }
        // een uitgave deels uit een pot
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 100, day: 10, potShares: [PotShare(potID: potIDs[0], amount: 40)]),
                     kind: .expense, in: start)
        d.addBankSnapshot(balance: 2_500, note: "Begin", date: start.firstDay.addingTimeInterval(7_200))
        let current = start.adding(59)
        d.materialize(upTo: current)
        d.applyDueInterest(upTo: current.firstDay)
        for i in 0..<20 {
            d.addBankEntry(amount: Double(i % 2 == 0 ? 50 : -30), note: "x", date: start.adding(i * 2).date(day: 14))
        }
        return (d, current)
    }

    func testPerf() {
        let (d, current) = LedgerPerfScratchTests.perfData()
        let months = [current, current.adding(-30), current.adding(-58), current.adding(3)]
        for m in months {
            let t0 = Date()
            let l = d.monthLedger(m, asOf: current.date(day: 10))
            let t1 = Date()
            let b = d.bankBalance(on: m.date(day: 15))
            let t2 = Date()
            let ev = d.dayEvents(in: m, asOf: current.date(day: 10))
            let t3 = Date()
            _ = d.potBalance(d.pots[0].id, asOf: m.date(day: 15))
            let t4 = Date()
            _ = d.remaining(in: m)
            let t5 = Date()
            print("PERF \(m.key): monthLedger \(Int(t1.timeIntervalSince(t0) * 1000)) ms, bankBalance(on:) \(Int(t2.timeIntervalSince(t1) * 1000)) ms, dayEvents \(Int(t3.timeIntervalSince(t2) * 1000)) ms, potBalance \(Int(t4.timeIntervalSince(t3) * 1000)) ms, remaining \(Int(t5.timeIntervalSince(t4)*1000e0)) ms  reconcile \(l.bankReconciles) \(l.potsReconciles) \(l.overviewReconciles) \(b ?? -1) \(ev.count)")
        }
    }
}

extension LedgerPerfScratchTests {
    func ms(_ a: Date, _ b: Date) -> String { String(format: "%.1f", b.timeIntervalSince(a) * 1000) }

    func testBreakdown() {
        let (d, current) = LedgerPerfScratchTests.perfData()
        let m = current
        let today = current.date(day: 10)
        var t = Date()
        var flows: [UUID: PotFlows] = [:]
        for pot in d.pots { flows[pot.id] = d.potFlows(pot, throughMonth: m) }
        var t2 = Date(); print("PERF potFlows x10:", ms(t, t2)); t = t2
        var interestPots = 0
        for pot in d.pots where InterestRules.isActive(pot) {
            let a = Date(); _ = d.potFlows(pot, throughMonth: m); let b = Date(); print("PERF  interest pot", ms(a, b)); interestPots += 1; break
        }
        for pot in d.pots where !InterestRules.isActive(pot) {
            let a = Date(); _ = d.potFlows(pot, throughMonth: m); let b = Date(); print("PERF  plain pot", ms(a, b)); break
        }
        t = Date()
        _ = d.dayEventsByMonth(from: m, to: m, asOf: today, flows: flows)
        t2 = Date(); print("PERF dayEventsByMonth(flows):", ms(t, t2)); t = t2
        _ = d.bankFlowEvents(in: m)
        t2 = Date(); print("PERF bankFlowEvents(one month):", ms(t, t2)); t = t2
        _ = d.planEvents(in: m)
        t2 = Date(); print("PERF planEvents(one month):", ms(t, t2)); t = t2
        _ = d.plan(for: m)
        t2 = Date(); print("PERF plan(for:):", ms(t, t2)); t = t2
        _ = d.monthFigures(m)
        t2 = Date(); print("PERF monthFigures:", ms(t, t2)); t = t2
        let cal = YearMonth.calendar
        for _ in 0..<1000 { _ = m.date(day: 12, calendar: cal) }
        t2 = Date(); print("PERF 1000x date(day:):", ms(t, t2)); t = t2
        for _ in 0..<1000 { _ = DayMath.nextDayStart(after: Date(), calendar: cal) }
        t2 = Date(); print("PERF 1000x nextDayStart:", ms(t, t2)); t = t2
        for _ in 0..<1000 { _ = UUID().uuidString }
        t2 = Date(); print("PERF 1000x uuidString:", ms(t, t2)); t = t2
        for _ in 0..<1000 { _ = StableID.uuid("line|ABCDEFGH-ABCD-ABCD-ABCD-ABCDEFGHIJKL|2026-10") }
        t2 = Date(); print("PERF 1000x StableID:", ms(t, t2)); t = t2
        for _ in 0..<1000 { _ = YearMonth(date: Date(), calendar: cal) }
        t2 = Date(); print("PERF 1000x YearMonth(date:):", ms(t, t2)); t = t2
        _ = BankTimeline(d, firstLimit: m.firstDay, lastLimit: m.endExclusive, events: { d.bankFlowEvents(in: $0) })
        t2 = Date(); print("PERF BankTimeline init:", ms(t, t2)); t = t2
        _ = d.planEvents(in: m.adding(-1)); _ = d.synthesizedPlan(for: m)
        t2 = Date(); print("PERF synthesizedPlan:", ms(t, t2)); t = t2
    }
}

extension LedgerPerfScratchTests {
    func testBreakdown2() {
        let (d, current) = LedgerPerfScratchTests.perfData()
        for m in [current, current.adding(3)] {
            let today = current.date(day: 10)
            var t = Date()
            var t2 = Date()
            func lap(_ name: String) { t2 = Date(); print("PERF2 \(m.key) \(name): \(ms(t, t2))"); t = t2 }
            t = Date()
            let flows = d.allPotFlows(throughMonth: m)
            lap("allPotFlows")
            let events = d.dayEventsByMonth(from: m, to: m, asOf: today, flows: flows)[m] ?? []
            lap("dayEventsByMonth")
            let tl = BankTimeline(d, firstLimit: m.firstDay, lastLimit: m.endExclusive, events: { $0 == m ? events : d.bankFlowEvents(in: $0) })
            lap("BankTimeline init")
            _ = tl.balanceCents(entriesBefore: m.endExclusive, planBefore: m.endExclusive)
            lap("1 balance")
            _ = d.monthFigures(m)
            lap("monthFigures")
            let l = d.monthLedger(m, asOf: today)
            lap("monthLedger total")
            _ = l
        }
    }
}
