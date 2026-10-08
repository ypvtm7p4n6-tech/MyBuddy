import Foundation

/// Samenvatting van één maand.
struct MonthSummary: Identifiable, Equatable {
    var month: YearMonth
    var income: Double
    var expenses: Double
    var saved: Double      // verdeeld over spaarpotten
    var invested: Double   // verdeeld over beleggingen
    var isProjected: Bool  // ligt na de huidige maand

    var id: String { month.key }
    /// Wat er nog te verdelen is (kan negatief zijn: je hebt meer verdeeld dan je hebt).
    var remaining: Double { (income - expenses - saved - invested).cents }
}

struct PeriodSummary: Equatable {
    var months: [MonthSummary]
    var income: Double { months.reduce(0) { $0 + $1.income }.cents }
    var expenses: Double { months.reduce(0) { $0 + $1.expenses }.cents }
    var saved: Double { months.reduce(0) { $0 + $1.saved }.cents }
    var invested: Double { months.reduce(0) { $0 + $1.invested }.cents }
    var remaining: Double { (income - expenses - saved - invested).cents }
    var count: Int { months.count }
    var hasProjected: Bool { months.contains { $0.isProjected } }
    var isFullyProjected: Bool { !months.isEmpty && months.allSatisfy { $0.isProjected } }
    func average(_ value: Double) -> Double { count == 0 ? 0 : (value / Double(count)).cents }
}

extension FinanceData {
    // MARK: Maandplannen

    /// Het laatst opgeslagen plan vóór `month`.
    private func latestStoredPlan(before month: YearMonth) -> MonthPlan? {
        var best: (YearMonth, MonthPlan)?
        for (key, plan) in months {
            guard let m = YearMonth(key: key), m < month else { continue }
            if best == nil || m > best!.0 { best = (m, plan) }
        }
        return best?.1
    }

    private func copiedRecurring(_ lines: [MoneyLine]) -> [MoneyLine] {
        lines.filter { $0.isRecurring }.map { line in
            var copy = line
            copy.id = UUID()
            return copy
        }
    }

    /// Standaardverdeling van een maand uit de instellingen van potten en beleggingen.
    func defaultAllocation(_ id: UUID, in month: YearMonth) -> Double {
        if let pot = pots.first(where: { $0.id == id }) {
            return month >= pot.startMonth ? pot.monthlyContribution : 0
        }
        if let h = holdings.first(where: { $0.id == id }) {
            return month >= h.startMonth ? h.monthlyContribution : 0
        }
        return 0
    }

    /// Plan afgeleid uit standaarden (voor maanden die nog niet zijn vastgelegd).
    func synthesizedPlan(for month: YearMonth) -> MonthPlan {
        var plan = MonthPlan()
        if let prev = latestStoredPlan(before: month) {
            plan.extraIncome = copiedRecurring(prev.extraIncome)
            plan.expenses = copiedRecurring(prev.expenses)
        }
        for pot in pots where month >= pot.startMonth {
            plan.allocations[pot.id.uuidString] = pot.monthlyContribution
        }
        for h in holdings where month >= h.startMonth {
            plan.allocations[h.id.uuidString] = h.monthlyContribution
        }
        return plan
    }

    /// Opgeslagen plan, of een afgeleid plan.
    func plan(for month: YearMonth) -> MonthPlan {
        months[month.key] ?? synthesizedPlan(for: month)
    }

    /// Past een maandplan aan en slaat het op.
    mutating func editPlan(_ month: YearMonth, _ body: (inout MonthPlan) -> Void) {
        var p = plan(for: month)
        body(&p)
        months[month.key] = p
    }

    /// Legt alle maanden t/m `current` vast, zodat latere wijzigingen van standaarden het verleden niet veranderen.
    mutating func materialize(upTo current: YearMonth) {
        var m = startMonth
        var guardCount = 0
        while m <= current && guardCount < 1200 {
            if var existing = months[m.key] {
                var changed = false
                for pot in pots where m >= pot.startMonth && existing.allocations[pot.id.uuidString] == nil {
                    existing.allocations[pot.id.uuidString] = pot.monthlyContribution
                    changed = true
                }
                for h in holdings where m >= h.startMonth && existing.allocations[h.id.uuidString] == nil {
                    existing.allocations[h.id.uuidString] = h.monthlyContribution
                    changed = true
                }
                if changed { months[m.key] = existing }
            } else {
                months[m.key] = synthesizedPlan(for: m)
            }
            m = m.adding(1)
            guardCount += 1
        }
    }

    // MARK: Bedragen per maand

    /// Verdeling voor één pot of belegging in een maand.
    func allocation(_ id: UUID, in month: YearMonth) -> Double {
        if let stored = months[month.key], let v = stored.allocations[id.uuidString] { return v }
        return defaultAllocation(id, in: month)
    }

    mutating func setAllocation(_ id: UUID, in month: YearMonth, amount: Double) {
        editPlan(month) { $0.allocations[id.uuidString] = amount.cents }
    }

    func salaryAmount(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        let p = plan(for: month)
        if let override = p.salaryOverride { return override.cents }
        return salary.monthlyAmount(hoursOverride: p.hoursOverride)
    }

    func extraIncomeTotal(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        return plan(for: month).extraIncome.total
    }

    func income(in month: YearMonth) -> Double {
        (salaryAmount(in: month) + extraIncomeTotal(in: month)).cents
    }

    func expensesTotal(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        return plan(for: month).expenses.total
    }

    func savedTotal(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        return pots.reduce(0) { $0 + allocation($1.id, in: month) }.cents
    }

    func investedTotal(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        return holdings.reduce(0) { $0 + allocation($1.id, in: month) }.cents
    }

    /// Wat er nog te verdelen is in een maand.
    func remaining(in month: YearMonth) -> Double {
        (income(in: month) - expensesTotal(in: month) - savedTotal(in: month) - investedTotal(in: month)).cents
    }

    func summary(of month: YearMonth, current: YearMonth) -> MonthSummary {
        MonthSummary(month: month,
                     income: income(in: month),
                     expenses: expensesTotal(in: month),
                     saved: savedTotal(in: month),
                     invested: investedTotal(in: month),
                     isProjected: month > current)
    }

    func periodSummary(_ mode: PeriodMode, containing focus: YearMonth, current: YearMonth) -> PeriodSummary {
        PeriodSummary(months: mode.months(containing: focus).map { summary(of: $0, current: current) })
    }

    func summaries(from start: YearMonth, count: Int, current: YearMonth) -> [MonthSummary] {
        start.range(count: count).map { summary(of: $0, current: current) }
    }

    // MARK: Regels (inkomsten en uitgaven)

    enum LineKind { case income, expense }

    mutating func upsertLine(_ line: MoneyLine, kind: LineKind, in month: YearMonth) {
        editPlan(month) { plan in
            switch kind {
            case .income:
                if let i = plan.extraIncome.firstIndex(where: { $0.id == line.id }) { plan.extraIncome[i] = line } else { plan.extraIncome.append(line) }
            case .expense:
                if let i = plan.expenses.firstIndex(where: { $0.id == line.id }) { plan.expenses[i] = line } else { plan.expenses.append(line) }
            }
        }
    }

    mutating func deleteLine(id: UUID, kind: LineKind, in month: YearMonth) {
        editPlan(month) { plan in
            switch kind {
            case .income: plan.extraIncome.removeAll { $0.id == id }
            case .expense: plan.expenses.removeAll { $0.id == id }
            }
        }
    }

    // MARK: Verdeelhulpjes

    /// Zet de verdeling van een maand terug naar de standaardinleg.
    mutating func applyDefaultAllocations(in month: YearMonth) {
        var fresh: [String: Double] = [:]
        for pot in pots { fresh[pot.id.uuidString] = month >= pot.startMonth ? pot.monthlyContribution : 0 }
        for h in holdings { fresh[h.id.uuidString] = month >= h.startMonth ? h.monthlyContribution : 0 }
        editPlan(month) { $0.allocations = fresh }
    }

    mutating func clearAllocations(in month: YearMonth) {
        let ids = pots.map(\.id) + holdings.map(\.id)
        editPlan(month) { plan in
            for id in ids { plan.allocations[id.uuidString] = 0 }
        }
    }

    /// Verdeelt wat er over is gelijk over alle spaarpotten (alleen als er iets over is).
    mutating func spreadRemainingOverPots(in month: YearMonth) {
        let left = remaining(in: month)
        guard left > 0, !pots.isEmpty else { return }
        let share = (left / Double(pots.count)).cents
        for pot in pots {
            setAllocation(pot.id, in: month, amount: allocation(pot.id, in: month) + share)
        }
    }
}
