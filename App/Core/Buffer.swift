import Foundation

// MARK: - Situatie

/// Soort werk. Bepaalt het basisaantal maanden aan noodzakelijke uitgaven dat je als buffer houdt.
enum BufferEmployment: String, Codable, CaseIterable, Identifiable {
    case permanent, flexible, selfEmployed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .permanent: return "Vast contract"
        case .flexible: return "Flexibel of tijdelijk"
        case .selfEmployed: return "Zzp"
        }
    }

    /// Basis: 3 maanden bij een vast contract, 4 bij flexibel of tijdelijk werk (richtlijn 4 tot 5), 6 bij zzp.
    var baseMonths: Int {
        switch self {
        case .permanent: return 3
        case .flexible: return 4
        case .selfEmployed: return 6
        }
    }

    var explanation: String {
        switch self {
        case .permanent:
            return "Vast contract: \(baseMonths) maanden als basis."
        case .flexible:
            return "Flexibel of tijdelijk werk: \(baseMonths) maanden als basis, want je inkomen is minder zeker."
        case .selfEmployed:
            return "Zzp: \(baseMonths) maanden als basis, want je inkomen schommelt en je hebt geen WW."
        }
    }
}

/// Met wie je het huishouden deelt.
enum BufferHousehold: String, Codable, CaseIterable, Identifiable {
    case alone, partnerWithIncome, partnerWithoutIncome
    var id: String { rawValue }

    var title: String {
        switch self {
        case .alone: return "Alleen"
        case .partnerWithIncome: return "Met partner met inkomen"
        case .partnerWithoutIncome: return "Met partner zonder inkomen"
        }
    }

    /// Een partner zonder inkomen betekent één inkomen voor twee: een maand extra.
    var extraMonths: Int { self == .partnerWithoutIncome ? 1 : 0 }
}

/// Het advies: aantal maanden en de regels die uitleggen hoe het is opgebouwd.
struct BufferRecommendation: Equatable {
    var months: Int
    var lines: [String]
}

/// Persoonlijke situatie waaruit het aantal maanden buffer volgt (Nibud-achtige richtlijn).
///
/// Regels:
/// - basis: vast contract 3, flexibel of tijdelijk 4, zzp 6 maanden;
/// - partner zonder inkomen: +1; partner met inkomen of alleen: +0;
/// - één of meer kinderen: +1 (niet per kind);
/// - eigen woning: +1;
/// - het resultaat blijft tussen 3 en 9 maanden.
struct BufferSituation: Codable, Equatable {
    var employment: BufferEmployment = .permanent
    var household: BufferHousehold = .alone
    var children: Int = 0
    var isHomeowner: Bool = false

    static let minMonths = 3
    static let maxMonths = 9

    var recommendation: BufferRecommendation {
        var total = employment.baseMonths
        var lines: [String] = [employment.explanation]

        switch household {
        case .alone:
            break
        case .partnerWithIncome:
            lines.append("Partner met inkomen: geen extra maanden, jullie vangen een tegenvaller samen op.")
        case .partnerWithoutIncome:
            total += household.extraMonths
            lines.append("Partner zonder inkomen: +1 maand, want jullie leven van één inkomen.")
        }
        if children > 0 {
            total += 1
            lines.append("Kinderen: +1 maand, want hun kosten lopen gewoon door.")
        }
        if isHomeowner {
            total += 1
            lines.append("Eigen woning: +1 maand voor onderhoud en onverwachte reparaties.")
        }

        let clamped = min(BufferSituation.maxMonths, max(BufferSituation.minMonths, total))
        if clamped == total {
            lines.append("Samen: \(clamped) maanden aan noodzakelijke uitgaven.")
        } else {
            lines.append("Samen: \(clamped) maanden, want de richtlijn blijft tussen \(BufferSituation.minMonths) en \(BufferSituation.maxMonths) maanden.")
        }
        return BufferRecommendation(months: clamped, lines: lines)
    }

    var recommendedMonths: Int { recommendation.months }
}

// MARK: - Wat telt als huidige buffer

enum BufferSource: String, Codable, CaseIterable, Identifiable {
    case bank, pot, bankAndPot, manual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank: return "Bankrekening"
        case .pot: return "Eén spaarpot"
        case .bankAndPot: return "Bankrekening en spaarpot"
        case .manual: return "Zelf invullen"
        }
    }

    var usesBank: Bool { self == .bank || self == .bankAndPot }
    var usesPot: Bool { self == .pot || self == .bankAndPot }
}

// MARK: - Keuzes van de gebruiker (bewaard)

/// Alles wat de gebruiker in de calculator kiest. Wordt als JSON bewaard (UserDefaults),
/// zodat het blok op de Savings-pagina dezelfde cijfers toont als de calculator.
struct BufferSetup: Codable, Equatable {
    var situation = BufferSituation()
    /// Aandeel van de variabele uitgaven dat als noodzakelijk meetelt (0...1).
    var variableShare: Double = BufferCalc.defaultVariableShare
    /// Alleen gebruikt zolang er geen uitgaven zijn ingevuld.
    var manualEssential: Double = 0
    var source: BufferSource = .manual
    var potID: UUID?
    var manualCurrent: Double = 0
    /// Rente op de buffer meenemen in de berekening (met de spaarrente uit de instellingen).
    var useInterest: Bool = false

    static let storageKey = "buffer.setup.v1"

    var json: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// nil bij lege of onleesbare tekst.
    static func fromJSON(_ text: String) -> BufferSetup? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BufferSetup.self, from: data)
    }
}

// MARK: - Invoer en uitkomst

/// Alle getallen die de berekening nodig heeft.
struct BufferInputs: Equatable {
    var months: Int
    var fixedMonthly: Double
    var variableMonthly: Double = 0
    var variableShare: Double = BufferCalc.defaultVariableShare
    var current: Double
    var monthlySaving: Double
    var fillWithin: Int = 12
    var annualRate: Double = 0
}

struct BufferResult: Equatable {
    var months: Int
    /// Vaste uitgaven die meetellen.
    var fixedPart: Double
    /// Het meetellende deel van de variabele uitgaven.
    var variablePart: Double
    /// Noodzakelijke uitgaven per maand.
    var essentialMonthly: Double
    var target: Double
    var current: Double
    /// Wat er nog aan het doel ontbreekt (nooit negatief).
    var gap: Double
    /// 0...1
    var progress: Double
    /// Hoeveel maanden aan noodzakelijke uitgaven de huidige buffer dekt. nil zonder uitgaven.
    var coverageMonths: Double?
    var monthlySaving: Double
    var annualRate: Double
    /// Maanden tot het doel bij dit maandbedrag. 0 = al bereikt, nil = niet binnen 100 jaar.
    var monthsToFill: Int?
    var fillWithin: Int
    /// Maandbedrag dat nodig is om binnen `fillWithin` maanden het doel te halen.
    var monthlyNeeded: Double

    var hasTarget: Bool { target > 0 }
    var isFull: Bool { target > 0 && gap <= 0 }
}

/// Eén maand in de grafiek.
struct BufferPoint: Identifiable, Equatable {
    var month: YearMonth
    var target: Double
    var projected: Double
    var id: String { month.key }
}

// MARK: - Rekenregels

enum BufferCalc {
    static let defaultVariableShare = 0.7
    static let minFillMonths = 1
    static let maxFillMonths = 60
    static let minSeriesMonths = 12
    static let maxSeriesMonths = 120

    static func clampedShare(_ share: Double) -> Double {
        if share.isNaN { return defaultVariableShare }
        return min(1, max(0, share))
    }

    /// Noodzakelijke uitgaven per maand: vast + een deel van de variabele uitgaven.
    static func essentialPerMonth(fixed: Double, variable: Double, variableShare: Double) -> Double {
        (max(0, fixed) + max(0, variable) * clampedShare(variableShare)).cents
    }

    static func target(essentialMonthly: Double, months: Int) -> Double {
        (max(0, essentialMonthly) * Double(max(0, months))).cents
    }

    static func calculate(_ inputs: BufferInputs) -> BufferResult {
        let months = max(0, inputs.months)
        let fixedPart = max(0, inputs.fixedMonthly).cents
        let variablePart = (max(0, inputs.variableMonthly) * clampedShare(inputs.variableShare)).cents
        let essential = essentialPerMonth(fixed: inputs.fixedMonthly,
                                          variable: inputs.variableMonthly,
                                          variableShare: inputs.variableShare)
        let goal = target(essentialMonthly: essential, months: months)
        let have = max(0, inputs.current).cents
        let rawGap = (goal - have).cents
        let gap = rawGap > 0 ? rawGap : 0
        let progress = goal > 0 ? min(1, max(0, have / goal)) : 0
        let coverage: Double? = essential > 0 ? have / essential : nil
        let saving = max(0, inputs.monthlySaving).cents
        let within = min(maxFillMonths, max(minFillMonths, inputs.fillWithin))
        let toFill = Growth.monthsToReach(target: goal, start: have, monthly: saving, annualReturn: inputs.annualRate)
        let rawNeeded = Growth.requiredMonthly(target: goal, start: have, annualReturn: inputs.annualRate, months: within)
        let needed: Double = rawNeeded > 0 ? ((rawNeeded * 100) - 1e-6).rounded(.up) / 100 : 0
        return BufferResult(months: months,
                            fixedPart: fixedPart,
                            variablePart: variablePart,
                            essentialMonthly: essential,
                            target: goal,
                            current: have,
                            gap: gap,
                            progress: progress,
                            coverageMonths: coverage,
                            monthlySaving: saving,
                            annualRate: inputs.annualRate,
                            monthsToFill: toFill,
                            fillWithin: within,
                            monthlyNeeded: needed)
    }

    /// Aantal maanden in de grafiek: tot het doel gehaald is plus een half jaar, tussen 12 en 120.
    static func seriesHorizon(monthsToFill: Int?) -> Int {
        let base = monthsToFill ?? 18
        return min(maxSeriesMonths, max(minSeriesMonths, base + 6))
    }

    /// Doellijn en verwachte buffer per maand, vanaf `start` (punt 0 = nu).
    static func series(_ result: BufferResult, start: YearMonth) -> [BufferPoint] {
        let horizon = seriesHorizon(monthsToFill: result.monthsToFill)
        let values = Growth.monthlySeries(start: result.current, monthly: result.monthlySaving,
                                          annualReturn: result.annualRate, months: horizon)
        var points: [BufferPoint] = []
        for (offset, value) in values.enumerated() {
            points.append(BufferPoint(month: start.adding(offset), target: result.target, projected: value.cents))
        }
        return points
    }

    // MARK: Gegevens uit de app

    /// De eerste spaarpot die "Buffer" heet (hoofdletters en spaties maken niet uit).
    static func bufferPot(in data: FinanceData) -> Pot? {
        data.pots.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == "buffer" }
    }

    /// De gekozen pot, anders de pot "Buffer", anders de eerste pot.
    static func resolvedPot(in data: FinanceData, preferred: UUID?) -> Pot? {
        if let id = preferred, let pot = data.pot(id) { return pot }
        return bufferPot(in: data) ?? data.pots.first
    }

    /// Zijn er voor deze maand uitgaven ingevuld?
    static func hasExpenses(in data: FinanceData, current: YearMonth) -> Bool {
        let overview = data.forEstimates.expenseOverview(in: current)
        return overview.fixed + overview.variable > 0
    }

    /// Banksaldo van nu (`today`), maar nooit onder nul.
    static func bankAmount(in data: FinanceData, current: YearMonth, today: Date = Date()) -> Double {
        max(0, data.bankBalanceNow(current: current, today: today)).cents
    }

    /// Saldo van de gekozen pot van nu (`today`, zoals `potBalanceNow`: de inleg van de 25e telt pas vanaf de 25e),
    /// maar nooit onder nul. 0 zonder pot.
    static func potAmount(in data: FinanceData, setup: BufferSetup, current: YearMonth, today: Date = Date()) -> Double {
        guard let pot = resolvedPot(in: data, preferred: setup.potID) else { return 0 }
        return max(0, data.potBalanceNow(pot.id, current: current, today: today)).cents
    }

    /// De huidige buffer volgens de gekozen bron, zoals die er op het moment `today` voor staat.
    static func currentAmount(in data: FinanceData, setup: BufferSetup, current: YearMonth, today: Date = Date()) -> Double {
        switch setup.source {
        case .bank:
            return bankAmount(in: data, current: current, today: today)
        case .pot:
            return potAmount(in: data, setup: setup, current: current, today: today)
        case .bankAndPot:
            return (bankAmount(in: data, current: current, today: today)
                    + potAmount(in: data, setup: setup, current: current, today: today)).cents
        case .manual:
            return max(0, setup.manualCurrent).cents
        }
    }

    /// Standaard maandbedrag: de verdeling van de gekozen pot deze maand, anders wat er nog over is
    /// (nooit negatief), anders 0. Een schatting voor elke maand: bij een salaris om de zoveel weken of dagen rekent het
    /// met een gemiddelde maand (`estimatedAllocation`, `estimatedRemaining`); bij het maandelijkse schema is dat deze maand.
    static func defaultMonthlySaving(in data: FinanceData, setup: BufferSetup, current: YearMonth) -> Double {
        if setup.source.usesPot, let pot = resolvedPot(in: data, preferred: setup.potID) {
            let allocated = data.estimatedAllocation(pot.id, in: current)
            if allocated > 0 { return allocated.cents }
        }
        let left = data.estimatedRemaining(in: current)
        return left > 0 ? left.cents : 0
    }

    /// Eerste keuzes als de gebruiker de calculator nog nooit heeft gebruikt.
    static func initialSetup(for data: FinanceData, current: YearMonth) -> BufferSetup {
        var setup = BufferSetup()
        if let pot = bufferPot(in: data) {
            setup.source = .pot
            setup.potID = pot.id
        } else if data.hasBankBalance {
            setup.source = .bank
        } else {
            setup.source = .manual
        }
        return setup
    }

    /// Zet app-gegevens en keuzes om in de invoer van de berekening.
    /// Zonder ingevulde uitgaven telt het handmatige bedrag als vaste uitgaven. De huidige buffer is het saldo van
    /// nu (`today`).
    static func inputs(from data: FinanceData, setup: BufferSetup, current: YearMonth,
                       monthlySaving: Double, fillWithin: Int, today: Date = Date()) -> BufferInputs {
        let overview = data.forEstimates.expenseOverview(in: current)
        let known = overview.fixed + overview.variable > 0
        return BufferInputs(months: setup.situation.recommendation.months,
                            fixedMonthly: known ? overview.fixed : max(0, setup.manualEssential),
                            variableMonthly: known ? overview.variable : 0,
                            variableShare: setup.variableShare,
                            current: currentAmount(in: data, setup: setup, current: current, today: today),
                            monthlySaving: monthlySaving,
                            fillWithin: fillWithin,
                            annualRate: setup.useInterest ? data.settings.savingsRate : 0)
    }

    /// Korte uitkomst met het standaard maandbedrag (voor het blok op de Savings-pagina).
    static func summary(for data: FinanceData, setup: BufferSetup, current: YearMonth, today: Date = Date()) -> BufferResult {
        let saving = defaultMonthlySaving(in: data, setup: setup, current: current)
        return calculate(inputs(from: data, setup: setup, current: current, monthlySaving: saving, fillWithin: 12,
                                today: today))
    }
}
