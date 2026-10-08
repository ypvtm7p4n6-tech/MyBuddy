import Foundation

// MARK: - Keuzes voor de invoer

/// Voorgestelde rendementen voor de spaardoel-calculator.
enum SavingsRatePreset: String, CaseIterable, Identifiable {
    case savings, bonds, equities, custom
    var id: String { rawValue }

    /// Vaste richtpercentages (per jaar, als breuk).
    static let bondsRate = 0.03
    static let equitiesRate = 0.06

    var title: String {
        switch self {
        case .savings: return "Spaarrekening"
        case .bonds: return "Obligaties"
        case .equities: return "Aandelen / ETF"
        case .custom: return "Eigen percentage"
        }
    }

    /// Rendement per jaar. De spaarrekening volgt de rente uit de instellingen.
    func rate(savingsRate: Double, customRate: Double) -> Double {
        switch self {
        case .savings: return savingsRate
        case .bonds: return SavingsRatePreset.bondsRate
        case .equities: return SavingsRatePreset.equitiesRate
        case .custom: return customRate
        }
    }
}

/// Eenheid waarin je de termijn invult.
enum SavingsGoalPeriodUnit: String, CaseIterable, Identifiable {
    case months, years
    var id: String { rawValue }

    var title: String { self == .months ? "maanden" : "jaren" }

    /// Aantal hele maanden voor een ingevulde waarde (ongeldige of negatieve waarden worden 0).
    func monthCount(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let raw = self == .years ? value * 12 : value
        let clamped = min(max(raw, 0), 100_000)
        return Int(clamped.rounded())
    }
}

// MARK: - Uitkomsten

/// Stand aan het eind van een periode met een vaste maandelijkse inleg.
struct SavingsGoalOutcome: Equatable {
    var monthly: Double
    var months: Int
    /// Saldo na `months` maanden.
    var balance: Double
    /// Startbedrag plus alle inleg.
    var deposited: Double
    /// Saldo min wat je zelf hebt ingelegd (negatief als het rendement lager is dan de inflatie).
    var interest: Double
}

/// Eén rij van de tabel per jaar.
struct SavingsGoalYearRow: Identifiable, Equatable {
    /// Aantal maanden vanaf nu waarop deze rij betrekking heeft.
    var months: Int
    var balance: Double
    var deposited: Double
    var interest: Double

    var id: Int { months }
    /// Jaarnummer (1 = eerste jaar). Een laatste, onvolledig jaar telt ook mee.
    var year: Int { (months + 11) / 12 }
    var isFullYear: Bool { months % 12 == 0 }
}

/// Wat er gebeurt als je elke maand een bedrag extra inlegt.
struct SavingsGoalWhatIf: Identifiable, Equatable {
    var extra: Double
    /// Maanden tot het doel met de extra inleg. nil = niet binnen 100 jaar.
    var months: Int?
    /// Hoeveel maanden eerder dan nu. nil als dat niet te bepalen is.
    var monthsSaved: Int?
    /// Zonder extra inleg niet haalbaar, met wel.
    var becomesReachable: Bool

    var id: Double { extra }
}

// MARK: - De calculator

/// Rekenhart van de spaardoel-calculator: een los hulpmiddel, los van de grote levensdoelen.
/// Alle uitkomsten zijn berekend uit de invoer, zodat ze meteen meebewegen als iets verandert.
/// Inleg komt aan het eind van elke maand (net als in `Growth`).
struct SavingsGoalPlan: Equatable {
    /// Gewenst bedrag.
    var goal: Double
    /// Wat je al hebt.
    var start: Double
    /// Verwacht rendement per jaar (breuk, bijv. 0,02).
    var annualReturn: Double
    /// Termijn waarbinnen je het doel wilt halen, in maanden.
    var horizonMonths: Int
    /// Wat je zelf per maand kunt inleggen.
    var monthly: Double
    /// Inflatie per jaar (breuk), alleen van belang bij `realTerms`.
    var inflation: Double = 0.02
    /// Rekenen in koopkracht van vandaag.
    var realTerms: Bool = false

    /// Bedragen per maand die de what-if-knoppen extra inleggen.
    static let whatIfSteps: [Double] = [25, 50, 100]

    /// Beginwaarden van de calculator.
    static func example(savingsRate: Double, inflation: Double) -> SavingsGoalPlan {
        var plan = SavingsGoalPlan(goal: 5_000, start: 0, annualReturn: savingsRate, horizonMonths: 24, monthly: 0,
                                   inflation: inflation, realTerms: false)
        plan.monthly = plan.requiredMonthly
        return plan
    }

    /// Aantal maanden van de maand `now` tot de maand van `date` (minimaal 0).
    static func monthsUntil(_ date: Date, from now: YearMonth) -> Int {
        max(0, now.months(to: YearMonth(date: date)))
    }

    // MARK: Opgeschoonde invoer

    private static func clean(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    var cleanGoal: Double { SavingsGoalPlan.clean(goal).cents }
    var cleanStart: Double { SavingsGoalPlan.clean(start).cents }
    var cleanMonthly: Double { SavingsGoalPlan.clean(monthly).cents }

    /// Nominaal rendement, zonder rare waarden.
    var cleanRate: Double { annualReturn.isFinite ? annualReturn : 0 }

    /// Termijn in maanden: minimaal 1, maximaal 100 jaar.
    var months: Int { min(Growth.maxMonths, max(1, horizonMonths)) }

    /// Rendement waarmee gerekend wordt. In koopkracht van vandaag is dat het reële rendement.
    var effectiveReturn: Double {
        if realTerms, inflation.isFinite, inflation > -0.99 {
            return Growth.realReturn(nominal: cleanRate, inflation: inflation)
        }
        return cleanRate
    }

    // MARK: Antwoord 1: hoeveel per maand?

    /// Inleg per maand die nodig is om het doel binnen de termijn te halen (`Growth.requiredMonthly`).
    /// Afronden op centen kan net te weinig zijn; dan komt er een cent bij, zodat je het doel echt op tijd haalt.
    var requiredMonthly: Double {
        let target = cleanGoal
        let begin = cleanStart
        let rate = effectiveReturn
        var amount = Growth.requiredMonthly(target: target, start: begin, annualReturn: rate, months: months)
        for _ in 0..<3 {
            let reached = Growth.monthsToReach(target: target, start: begin, monthly: amount,
                                               annualReturn: rate, maxMonths: months)
            if reached != nil { break }
            amount = (amount + 0.01).cents
        }
        return amount
    }

    /// Je hebt het bedrag al.
    var isReached: Bool { cleanStart >= cleanGoal }

    /// Hoeveel je per maand tekortkomt om op tijd te zijn (0 als je genoeg inlegt).
    var shortfallMonthly: Double { max(0, (requiredMonthly - cleanMonthly).cents) }

    // MARK: Antwoord 2: wanneer klaar?

    /// Maanden tot het doel met je eigen inleg. 0 = al bereikt, nil = niet binnen 100 jaar.
    var monthsToGoal: Int? {
        Growth.monthsToReach(target: cleanGoal, start: cleanStart, monthly: cleanMonthly, annualReturn: effectiveReturn)
    }

    /// Kalendermaand waarin je het doel haalt, gerekend vanaf `now`.
    func reachMonth(from now: YearMonth) -> YearMonth? {
        guard let n = monthsToGoal else { return nil }
        return now.adding(n)
    }

    /// Kalendermaand van de streefdatum, gerekend vanaf `now`.
    func deadlineMonth(from now: YearMonth) -> YearMonth {
        now.adding(months)
    }

    /// Haal je het doel met je eigen inleg binnen de termijn?
    var isOnTrack: Bool {
        guard let n = monthsToGoal else { return false }
        return n <= months
    }

    /// Hoeveel van het doel je al hebt (0...1).
    var progress: Double {
        let g = cleanGoal
        guard g > 0 else { return 0 }
        return min(1, cleanStart / g)
    }

    // MARK: Verloop, ingelegd en rente

    /// Saldo per maand 0...`months` met een gekozen inleg.
    func series(monthly m: Double, months n: Int) -> [Double] {
        Growth.monthlySeries(start: cleanStart, monthly: SavingsGoalPlan.clean(m).cents,
                             annualReturn: effectiveReturn, months: max(0, n))
    }

    /// Stand na `n` maanden met inleg `m`: saldo, ingelegd en rente.
    func outcome(monthly m: Double, months n: Int) -> SavingsGoalOutcome {
        let deposit = SavingsGoalPlan.clean(m).cents
        let count = max(0, n)
        let balance = Growth.futureValue(start: cleanStart, monthly: deposit,
                                         annualReturn: effectiveReturn, months: Double(count)).cents
        let deposited = (cleanStart + deposit * Double(count)).cents
        return SavingsGoalOutcome(monthly: deposit, months: count, balance: balance,
                                  deposited: deposited, interest: (balance - deposited).cents)
    }

    /// Met je eigen inleg, tot je het doel haalt (of tot het einde van de termijn als dat niet lukt).
    var chosenOutcome: SavingsGoalOutcome {
        outcome(monthly: cleanMonthly, months: monthsToGoal ?? months)
    }

    /// Met de benodigde inleg, tot het einde van de termijn.
    var requiredOutcome: SavingsGoalOutcome {
        outcome(monthly: requiredMonthly, months: months)
    }

    /// Inleg die in een nieuwe spaarpot of een nieuw doel komt: je eigen inleg, of de benodigde inleg als je niets invulde.
    var savedMonthly: Double {
        cleanMonthly > 0 ? cleanMonthly : requiredMonthly
    }

    /// Tabel per jaar tot en met `total` maanden. Is `total` geen heel aantal jaren, dan staat er een laatste rij voor het restant.
    func yearRows(monthly m: Double, months total: Int) -> [SavingsGoalYearRow] {
        let count = max(0, total)
        guard count > 0 else { return [] }
        let deposit = SavingsGoalPlan.clean(m).cents
        let values = Growth.monthlySeries(start: cleanStart, monthly: deposit, annualReturn: effectiveReturn, months: count)
        var checkpoints: [Int] = Array(stride(from: 12, through: count, by: 12))
        if count % 12 != 0 { checkpoints.append(count) }
        var rows: [SavingsGoalYearRow] = []
        for n in checkpoints {
            let balance = values[n].cents
            let deposited = (cleanStart + deposit * Double(n)).cents
            rows.append(SavingsGoalYearRow(months: n, balance: balance, deposited: deposited,
                                           interest: (balance - deposited).cents))
        }
        return rows
    }

    // MARK: Wat als?

    /// Wat als je `extra` per maand meer inlegt dan nu?
    func whatIf(extra: Double) -> SavingsGoalWhatIf {
        let add = SavingsGoalPlan.clean(extra)
        let base = monthsToGoal
        let boosted = Growth.monthsToReach(target: cleanGoal, start: cleanStart, monthly: cleanMonthly + add,
                                           annualReturn: effectiveReturn)
        var saved: Int?
        if let b = base, let n = boosted { saved = max(0, b - n) }
        return SavingsGoalWhatIf(extra: add, months: boosted, monthsSaved: saved,
                                 becomesReachable: base == nil && boosted != nil)
    }

    /// De standaard what-if-knoppen (+25, +50, +100 per maand).
    var whatIfs: [SavingsGoalWhatIf] {
        SavingsGoalPlan.whatIfSteps.map { whatIf(extra: $0) }
    }

    // MARK: Omzetten naar een spaarpot of doel

    /// Een nieuwe spaarpot met dit doel. Het startbedrag boek je als beginsaldo (`openingBalance`).
    func makePot(name: String, colorIndex: Int, targetDate: Date?, now: YearMonth) -> Pot {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Pot(name: trimmed.isEmpty ? "Spaardoel" : trimmed, symbol: "banknote", colorIndex: colorIndex,
                   goalAmount: cleanGoal, goalDate: targetDate, monthlyContribution: savedMonthly, startMonth: now)
    }

    /// Beginsaldo voor de spaarpot.
    var openingBalance: Double { cleanStart }

    /// Een eigen doel met eigen waarden (start, inleg en rendement).
    func makeGoal(name: String, targetDate: Date?) -> LifeGoal {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var g = LifeGoal(name: trimmed.isEmpty ? "Spaardoel" : trimmed, kind: .custom)
        g.targetAmount = cleanGoal
        g.targetDate = targetDate
        g.inflationAdjusted = realTerms
        g.funding = .custom(start: cleanStart, monthly: savedMonthly, annualReturn: cleanRate)
        return g
    }
}
