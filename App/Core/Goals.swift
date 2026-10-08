import Foundation

/// Uitgangspunten waarmee een doel wordt doorgerekend.
struct GoalInputs: Equatable {
    var start: Double
    var monthly: Double
    /// Verwacht rendement per jaar na kosten.
    var nominalReturn: Double
    /// Rendement dat in de berekening gebruikt wordt (na inflatiecorrectie als dat aanstaat).
    var effectiveReturn: Double
    /// Benodigd kapitaal.
    var target: Double
    var sourceName: String
}

struct GoalAnalysis: Equatable {
    var inputs: GoalInputs
    var progress: Double
    var monthsToGoal: Int?
    var reachMonth: YearMonth?
    var reachAge: Double?
    var monthsUntilDeadline: Int?
    var requiredMonthlyForDeadline: Double?
    var onTrack: Bool?

    var isReached: Bool { monthsToGoal == 0 }
}

extension FinanceData {
    func goal(_ id: UUID) -> LifeGoal? { goals.first { $0.id == id } }

    /// Inkomensverlies per maand als je minder uren werkt.
    func monthlyIncomeGap(for goal: LifeGoal) -> Double {
        if let o = goal.monthlyGapOverride { return max(0, o) }
        let from = goal.hoursFrom > 0 ? goal.hoursFrom : salary.hoursPerWeek
        let to = goal.hoursTo
        guard from > to, from > 0 else { return 0 }
        switch salary.mode {
        case .hourly: return (salary.hourlyRate * (from - to) * 52 / 12).cents
        case .fixed: return (salary.fixedMonthly * (1 - to / from)).cents
        }
    }

    /// Kapitaal dat nodig is voor het doel.
    func neededCapital(for goal: LifeGoal, drawdownReturn: Double) -> Double {
        switch goal.kind {
        case .retirement:
            let net = max(0, goal.monthlySpending - goal.otherMonthlyIncome)
            return Growth.capitalNeeded(monthlyAmount: net, withdrawalRate: goal.withdrawalRate)
        case .partTime:
            let gap = max(0, monthlyIncomeGap(for: goal) - goal.otherMonthlyIncome)
            if let years = goal.partTimeYears, years > 0 {
                return Growth.annuityCapital(monthlyAmount: gap, years: years, annualReturn: drawdownReturn)
            }
            return Growth.capitalNeeded(monthlyAmount: gap, withdrawalRate: goal.withdrawalRate)
        case .vacation, .custom:
            return goal.targetAmount
        }
    }

    func goalInputs(for goal: LifeGoal, current: YearMonth) -> GoalInputs {
        let inflation = settings.inflation
        let portfolioReturn = weightedNetReturn(current: current)
        var start = 0.0
        var monthly = 0.0
        var nominal = portfolioReturn
        var name = "Je beleggingen"

        switch goal.funding {
        case .portfolio:
            start = portfolioValue(current: current)
            monthly = monthlyInvestment(current: current)
        case .pot(let id):
            start = potBalance(id, at: current)
            monthly = allocation(id, in: current)
            nominal = 0
            name = pot(id)?.name ?? "Spaarpot"
        case .custom(let s, let m, let r):
            start = s
            monthly = m
            nominal = r
            name = "Eigen waarden"
        }

        let effective = goal.inflationAdjusted ? Growth.realReturn(nominal: nominal, inflation: inflation) : nominal
        let drawdown = goal.inflationAdjusted ? Growth.realReturn(nominal: portfolioReturn, inflation: inflation) : portfolioReturn
        let target = neededCapital(for: goal, drawdownReturn: drawdown)
        return GoalInputs(start: start.cents, monthly: monthly.cents, nominalReturn: nominal,
                          effectiveReturn: effective, target: target, sourceName: name)
    }

    func analyze(_ goal: LifeGoal, current: YearMonth) -> GoalAnalysis {
        let inputs = goalInputs(for: goal, current: current)
        let months = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                          monthly: inputs.monthly, annualReturn: inputs.effectiveReturn)
        var analysis = GoalAnalysis(inputs: inputs,
                                    progress: inputs.target > 0 ? max(0, inputs.start / inputs.target) : 1,
                                    monthsToGoal: months)
        if let n = months {
            analysis.reachMonth = current.adding(n)
            if let age = goal.currentAge { analysis.reachAge = Double(age) + Double(n) / 12 }
        }
        if let deadline = goal.targetDate {
            let n = current.months(to: YearMonth(date: deadline))
            analysis.monthsUntilDeadline = n
            if n > 0 {
                analysis.requiredMonthlyForDeadline = Growth.requiredMonthly(target: inputs.target, start: inputs.start,
                                                                             annualReturn: inputs.effectiveReturn, months: n)
            }
            if let reached = months { analysis.onTrack = reached <= max(0, n) }
            else { analysis.onTrack = false }
        }
        return analysis
    }

    // MARK: Wijzigen

    mutating func addGoal(_ goal: LifeGoal) { goals.append(goal) }

    mutating func updateGoal(_ goal: LifeGoal) {
        guard let i = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[i] = goal
    }

    mutating func deleteGoal(_ id: UUID) { goals.removeAll { $0.id == id } }

    /// Voorgevulde doelen met de gegevens die de app al heeft.
    func goalTemplate(_ kind: GoalKind) -> LifeGoal {
        var g = LifeGoal(name: kind.title, kind: kind)
        g.withdrawalRate = settings.defaultWithdrawalRate
        switch kind {
        case .retirement:
            g.monthlySpending = max(0, (averageMonthlyExpenses(current: YearMonth.current())).rounded())
            g.otherMonthlyIncome = 0
        case .partTime:
            g.hoursFrom = salary.hoursPerWeek
            g.hoursTo = max(0, salary.hoursPerWeek - 8)
        case .vacation:
            g.inflationAdjusted = false
            g.targetAmount = 3000
        case .custom:
            g.inflationAdjusted = false
        }
        return g
    }
}
