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
    /// Zelfde bedrag, naar boven afgerond op hele euro's. Dit is wat je in de app ziet: met dit bedrag haal je de streefdatum zeker.
    var requiredMonthlyForDeadlineWhole: Double?
    var onTrack: Bool?

    var isReached: Bool { monthsToGoal == 0 }

    /// Hoe het ervoor staat, in één woord. Voor de samenvatting in het doelenblok en op de doelenpagina.
    var outlook: GoalOutlook {
        // Zonder doelbedrag valt er niets te halen: dat is geen "bereikt".
        if inputs.target <= 0 { return .notSet }
        guard let months = monthsToGoal else { return .unreachable }
        if months == 0 { return .reached }
        if let onTrack { return onTrack ? .onTrack(months: months) : .behind(months: months) }
        return .reachable(months: months)
    }
}

/// Haalbaarheid van een levensdoel.
enum GoalOutlook: Equatable {
    /// Er is nog geen doelbedrag (bijvoorbeeld een nieuw eigen doel of een pensioen zonder uitgaven).
    case notSet
    /// Het benodigde bedrag heb je al.
    case reached
    /// Er is een streefdatum en je ligt op schema.
    case onTrack(months: Int)
    /// Er is een streefdatum en je loopt achter, maar je haalt het wel (later).
    case behind(months: Int)
    /// Er is geen streefdatum; zo lang duurt het.
    case reachable(months: Int)
    /// Niet binnen 100 jaar.
    case unreachable

    /// Aantal maanden tot het doel, als dat te bepalen is.
    var months: Int? {
        switch self {
        case .reached: return 0
        case .onTrack(let m), .behind(let m), .reachable(let m): return m
        case .notSet, .unreachable: return nil
        }
    }

    /// Is dit goed nieuws (bereikt of op schema)?
    var isPositive: Bool {
        switch self {
        case .reached, .onTrack: return true
        case .notSet, .behind, .reachable, .unreachable: return false
        }
    }
}

/// Afronden voor weergave: een benodigd maandbedrag toon je in hele euro's en altijd naar boven,
/// want een bedrag dat naar beneden is afgerond haalt het doel net niet.
enum GoalMath {
    /// Kleinste aantal hele euro's per maand waarmee je `target` binnen `months` maanden haalt
    /// (inleg aan het eind van de maand, zoals in `Growth`). 0 als je het bedrag al hebt.
    static func wholeMonthlyToReach(target: Double, start: Double, annualReturn: Double, months: Int) -> Double {
        guard target.isFinite, start.isFinite, annualReturn.isFinite else { return 0 }
        guard months > 0 else { return max(0, target - start).rounded(.up) }
        let exact = Growth.requiredMonthly(target: target, start: start, annualReturn: annualReturn, months: months)
        var amount = max(0, exact).rounded(.up)
        // Het bedrag op centen kan net te weinig zijn geweest (ook een klein tekort kan op 0,00 afronden);
        // controleer en tel zo nodig een euro bij. Heb je het bedrag al, dan blijft het 0.
        for _ in 0..<3 {
            let reached = Growth.monthsToReach(target: target, start: start, monthly: amount,
                                               annualReturn: annualReturn, maxMonths: months)
            if reached != nil { break }
            amount += 1
        }
        return amount
    }

    /// Tekst onder de titel van het doelenblok: hoeveel doelen er zijn en of er een spaardoel is.
    static func hubSubtitle(goalCount: Int, hasSavingsGoal: Bool) -> String {
        switch (goalCount, hasSavingsGoal) {
        case (0, false): return "Levensdoelen en spaardoel"
        case (0, true): return "Spaardoel"
        case (1, false): return "1 doel"
        case (1, true): return "1 doel en een spaardoel"
        case (let n, false): return "\(n) doelen"
        case (let n, true): return "\(n) doelen en een spaardoel"
        }
    }
}

extension FinanceData {
    func goal(_ id: UUID) -> LifeGoal? { goals.first { $0.id == id } }

    /// Inkomensverlies per maand als je minder uren werkt. Een schatting: het GEMIDDELDE per maand (bij een salaris om de
    /// zoveel weken of dagen telt een maand met twee uitbetalingen niet dubbel), zie `SalarySettings.averageMonthly(perWeek:)`.
    func monthlyIncomeGap(for goal: LifeGoal) -> Double {
        if let o = goal.monthlyGapOverride { return max(0, o) }
        let from = goal.hoursFrom > 0 ? goal.hoursFrom : salary.hoursPerWeek
        let to = goal.hoursTo
        guard from > to, from > 0 else { return 0 }
        switch salary.mode {
        case .hourly: return salary.averageMonthly(perWeek: salary.hourlyRate * (from - to)).cents
        case .fixed: return (salary.averageMonthlyFixedAmount * (1 - to / from)).cents
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

    /// Uitgangspunten van een doel. Bij financiering uit een spaarpot is `start` het saldo van nu (`today`, zoals
    /// `potBalanceNow`): de inleg van de 25e telt pas vanaf de 25e mee, en niet al op de 9e. Bij financiering uit de
    /// beleggingen is dat de waarde van nu per kalenderdag (`portfolioValue(current:today:)`), dezelfde als op Home en bij
    /// Beleggingen; de inleg van deze maand die nog moet komen zit dan in de maandinleg. De maandinleg is die van een
    /// GEMIDDELDE maand (`estimatedAllocation`): bij een salaris om de zoveel weken of dagen en een inleg als percentage van
    /// het inkomen is een maand met twee uitbetalingen geen maat voor "elke maand".
    func goalInputs(for goal: LifeGoal, current: YearMonth, today: Date = Date()) -> GoalInputs {
        let inflation = settings.inflation
        let portfolioReturn = weightedNetReturn(current: current)
        var start = 0.0
        var monthly = 0.0
        var nominal = portfolioReturn
        var name = "Je beleggingen"

        switch goal.funding {
        case .portfolio:
            start = portfolioValue(current: current, today: today)
            monthly = monthlyInvestment(current: current)
        case .pot(let id):
            start = potBalanceNow(id, current: current, today: today)
            monthly = estimatedAllocation(id, in: current)
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

    func analyze(_ goal: LifeGoal, current: YearMonth, today: Date = Date()) -> GoalAnalysis {
        let inputs = goalInputs(for: goal, current: current, today: today)
        let months = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                          monthly: inputs.monthly, annualReturn: inputs.effectiveReturn)
        var analysis = GoalAnalysis(inputs: inputs,
                                    progress: inputs.target > 0 ? max(0, inputs.start / inputs.target) : 0,
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
                analysis.requiredMonthlyForDeadlineWhole = GoalMath.wholeMonthlyToReach(
                    target: inputs.target, start: inputs.start, annualReturn: inputs.effectiveReturn, months: n)
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
