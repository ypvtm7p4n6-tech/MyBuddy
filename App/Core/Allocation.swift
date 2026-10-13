import Foundation

// MARK: - Inleg als percentage van het inkomen
//
// Een spaarpot of belegging legt maandelijks in als een vast bedrag (zoals altijd) of als een percentage van het inkomen.
//
// - Vast percentage: elke maand hetzelfde percentage (`Pot.contributionPercent`).
// - Variabel percentage: een maand kan een eigen percentage krijgen (`MonthPlan.percentAllocations`), naast de
//   bestaande overschrijving met een vast bedrag (`MonthPlan.allocations`).
// - Het bedrag wordt bij het lezen uitgerekend uit het inkomen van DIE maand, afgerond op hele centen (half omhoog), nooit
//   negatief. Zo gaan wijzigingen aan het inkomen vanzelf mee en komt overal exact hetzelfde bedrag terug: in
//   `allocation(_:in:)`, `savedTotal`, `investedTotal`, `remaining`, de dagboekhouding, de overschrijving op de
//   overschrijfdag, de spaarpotten en de projectie. Alle paden rekenen via `FinanceData.allocationCents`.
// - Het inkomen hangt nooit van de verdeling af (salaris + extra inkomsten), dus er is geen kringverwijzing.

/// Hoe de maandelijkse inleg van een spaarpot of belegging wordt bepaald.
enum ContributionMode: String, Codable, CaseIterable, Identifiable {
    case fixed, percentage
    var id: String { rawValue }
    var title: String { self == .fixed ? "Vast bedrag" : "Percentage van je inkomen" }
}

/// Waarover het percentage wordt berekend.
enum IncomeBasis: String, Codable, CaseIterable, Identifiable {
    /// Alleen het salaris van die maand.
    case salary
    /// Alle inkomsten van die maand: salaris en extra inkomsten.
    case allIncome
    var id: String { rawValue }
    var title: String { self == .salary ? "Alleen salaris" : "Alle inkomsten" }
}

/// Een percentage van het inkomen van een maand, met zijn grondslag. Staat in `MonthPlan.percentAllocations` als
/// overschrijving van één maand (variabel percentage).
struct PercentRule: Codable, Equatable {
    /// 0...100, maximaal twee decimalen (zie `AllocationMath.cleanPercent`).
    var percent: Double
    var basis: IncomeBasis = .salary

    init(percent: Double, basis: IncomeBasis = .salary) {
        self.percent = percent
        self.basis = basis
    }

    enum CodingKeys: String, CodingKey { case percent, basis }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 0
        basis = try c.decodeIfPresent(IncomeBasis.self, forKey: .basis) ?? .salary
    }
}

/// De inleg van een pot of belegging in een maand: een bedrag, of een percentage dat bij het lezen wordt uitgerekend.
enum AllocationRule: Equatable {
    case amount(Double)
    case percent(PercentRule)

    var isPercent: Bool {
        if case .percent = self { return true }
        return false
    }
}

/// Het inkomen van een maand in hele centen, per grondslag.
struct IncomeBases: Equatable {
    var salary = 0
    var all = 0

    func cents(for basis: IncomeBasis) -> Int {
        max(0, basis == .salary ? salary : all)
    }
}

/// Alles wat een spaarpot of belegging gemeen heeft voor de inleg per maand.
protocol ContributionSource {
    var id: UUID { get }
    var startMonth: YearMonth { get }
    var monthlyContribution: Double { get }
    var contributionMode: ContributionMode { get }
    var contributionPercent: Double { get }
    var contributionBasis: IncomeBasis { get }
}

extension Pot: ContributionSource {}
extension Holding: ContributionSource {}

extension ContributionSource {
    /// De standaardregel voor een maand (zonder overschrijving): vanaf de startmaand het vaste bedrag of het percentage,
    /// ervoor niets.
    func defaultRule(in month: YearMonth) -> AllocationRule {
        guard month >= startMonth else { return .amount(0) }
        switch contributionMode {
        case .fixed: return .amount(monthlyContribution)
        case .percentage: return .percent(PercentRule(percent: contributionPercent, basis: contributionBasis))
        }
    }
}

enum AllocationMath {
    /// Een percentage zoals het wordt gebruikt: 0...100, op twee decimalen. Onzin (NaN, oneindig, negatief) wordt 0.
    static func cleanPercent(_ percent: Double) -> Double {
        guard percent.isFinite else { return 0 }
        return Double(hundredths(percent)) / 100
    }

    /// Een percentage in honderdsten van een procent (12,5% is 1250), 0...10000.
    static func hundredths(_ percent: Double) -> Int {
        guard percent.isFinite else { return 0 }
        let scaled = (min(max(percent, 0), 100) * 100).rounded()
        return Int(scaled)
    }

    /// Het bedrag in centen: `incomeCents` × percentage, op hele centen (half omhoog). Een negatief inkomen geeft 0.
    /// Rekent met gehele getallen en kan niet overlopen: eerst het deel in tienduizenden, dan de rest.
    static func percentCents(of incomeCents: Int, hundredths p: Int) -> Int {
        let income = min(max(0, incomeCents), CentsMath.limit)
        let share = min(max(0, p), 10_000)
        let q = income / 10_000
        let r = income % 10_000
        return q * share + (r * share + 5_000) / 10_000
    }

    /// Het bedrag in centen van een regel bij dit inkomen.
    static func cents(of rule: PercentRule, bases: IncomeBases) -> Int {
        percentCents(of: bases.cents(for: rule.basis), hundredths: hundredths(rule.percent))
    }
}

/// Een waarschuwing over de verdeling van een maand. De tekst staat klaar voor de UI.
enum AllocationWarning: Equatable {
    /// De percentages samen zijn meer dan 100% van het inkomen.
    case percentagesOver100(total: Double)
    /// Er wordt meer verdeeld dan er te verdelen is (inkomen min uitgaven van de bank).
    case overAllocated(by: Double)

    var message: String {
        switch self {
        case .percentagesOver100(let total):
            return "De percentages samen zijn \(Fmt.percent(total / 100, digits: 2)) van je inkomen. Dat is meer dan 100%."
        case .overAllocated(let amount):
            return "Je verdeelt \(Fmt.euro(amount)) meer dan je hebt om te verdelen."
        }
    }
}

/// De verdeling van een pot of belegging in een maand, voor de UI.
struct EffectiveAllocation: Equatable {
    /// De regel die in de maand geldt: een bedrag, of een percentage met zijn grondslag.
    var rule: AllocationRule
    /// Het bedrag in euro's dat daaruit volgt (hetzelfde getal als `FinanceData.allocation(_:in:)`).
    var amount: Double
    /// De regel wijkt in deze maand af van de standaardinleg van de pot of belegging.
    var isOverride: Bool
}

extension FinanceData {
    // MARK: Regels per maand

    /// De standaardregel van een pot of belegging in een maand (zonder overschrijving). nil als het id niet bestaat.
    func defaultAllocationRule(_ id: UUID, in month: YearMonth) -> AllocationRule? {
        if let pot = pots.first(where: { $0.id == id }) { return pot.defaultRule(in: month) }
        if let holding = holdings.first(where: { $0.id == id }) { return holding.defaultRule(in: month) }
        return nil
    }

    /// De regel die in een maand voor een pot of belegging geldt: de overschrijving van die maand (een percentage gaat
    /// voor een bedrag), anders de standaardregel.
    func allocationRule(_ id: UUID, in month: YearMonth) -> AllocationRule {
        if let stored = months[month.key] {
            if let rule = stored.percentAllocations[id.uuidString] { return .percent(rule) }
            if let value = stored.allocations[id.uuidString] { return .amount(value) }
        }
        return defaultAllocationRule(id, in: month) ?? .amount(0)
    }

    /// De regel van de maand met het bedrag dat eruit volgt, en of de maand afwijkt van de standaardinleg.
    func effectiveAllocation(_ id: UUID, in month: YearMonth) -> EffectiveAllocation {
        let rule = allocationRule(id, in: month)
        let standard = defaultAllocationRule(id, in: month) ?? .amount(0)
        return EffectiveAllocation(rule: rule, amount: amount(of: rule, in: month), isOverride: rule != standard)
    }

    /// Het bedrag in euro's van een regel in een maand.
    func amount(of rule: AllocationRule, in month: YearMonth) -> Double {
        switch rule {
        case .amount(let value): return value
        case .percent(let percent): return CentsMath.value(AllocationMath.cents(of: percent, bases: incomeBases(in: month)))
        }
    }

    // MARK: Inkomen als grondslag

    /// Het inkomen van een maand in hele centen per grondslag: alleen het salaris, en alle inkomsten (salaris en extra
    /// inkomsten). Hangt nooit van de verdeling af. Vóór de startmaand is het 0.
    func incomeBases(in month: YearMonth) -> IncomeBases {
        guard month >= startMonth else { return IncomeBases() }
        return incomeBases(of: plan(for: month), in: month)
    }

    /// Zoals `incomeBases(in:)`, met vooraf bepaalde opgeslagen plannen en reeksen (sneller in lussen).
    func incomeBases(in month: YearMonth, using stored: StoredPlans) -> IncomeBases {
        guard month >= startMonth else { return IncomeBases() }
        return incomeBases(of: plan(for: month, using: stored), in: month)
    }

    /// Het inkomen van een maand uit een plan. Dezelfde som als in `monthFigures`.
    func incomeBases(of plan: MonthPlan, in month: YearMonth) -> IncomeBases {
        var extra = 0
        for line in plan.extraIncome { extra = CentsMath.add(extra, CentsMath.int(line.amount)) }
        let salary = CentsMath.int(salaryAmount(in: month, plan: plan))
        return IncomeBases(salary: salary, all: CentsMath.add(salary, extra))
    }

    // MARK: Het bedrag, op één plek uitgerekend

    /// De verdeling van een pot of belegging in een maand in hele centen. Dit is DE som: `allocation(_:in:)`, de maandcijfers,
    /// de dagboekhouding, de saldi van de spaarpotten en de overschrijving op de overschrijfdag rekenen allemaal zo.
    /// `storedPlan` is het opgeslagen plan van de maand (of nil); `key` is `e.id.uuidString`. `bases` wordt alleen
    /// uitgerekend als de regel een percentage is.
    func allocationCents<E: ContributionSource>(_ e: E, key: String, in month: YearMonth, storedPlan: MonthPlan?,
                                                basesFor bases: () -> IncomeBases) -> Int {
        if let storedPlan {
            if let rule = storedPlan.percentAllocations[key] { return AllocationMath.cents(of: rule, bases: bases()) }
            if let value = storedPlan.allocations[key] { return CentsMath.int(value) }
        }
        switch e.defaultRule(in: month) {
        case .amount(let value): return CentsMath.int(value)
        case .percent(let rule): return AllocationMath.cents(of: rule, bases: bases())
        }
    }

    /// Zoals hierboven, met de inkomsten van de maand al bekend.
    func allocationCents<E: ContributionSource>(_ e: E, key: String, in month: YearMonth, storedPlan: MonthPlan?,
                                                bases: IncomeBases) -> Int {
        allocationCents(e, key: key, in: month, storedPlan: storedPlan, basesFor: { bases })
    }

    /// De verdeling van een pot of belegging (op id) in een maand in hele centen.
    func allocationCents(_ id: UUID, in month: YearMonth) -> Int {
        switch allocationRule(id, in: month) {
        case .amount(let value): return CentsMath.int(value)
        case .percent(let rule): return AllocationMath.cents(of: rule, bases: incomeBases(in: month))
        }
    }

    // MARK: Plannen vullen

    /// Zet de standaardregel van een pot of belegging in een plan: een vast bedrag in `allocations`, een percentage in
    /// `percentAllocations`. Vóór de startmaand schrijft dit niets, tenzij `zeroBeforeStart` (dan een bedrag van nul).
    func putDefault<E: ContributionSource>(_ e: E, in month: YearMonth, into plan: inout MonthPlan,
                                           zeroBeforeStart: Bool = false) {
        let key = e.id.uuidString
        switch e.defaultRule(in: month) {
        case .amount(let value):
            if month >= e.startMonth || zeroBeforeStart { plan.allocations[key] = value }
        case .percent(let rule):
            plan.percentAllocations[key] = rule
        }
    }

    /// Heeft het plan een overschrijving (bedrag of percentage) voor deze pot of belegging?
    func hasAllocation(_ id: UUID, in plan: MonthPlan) -> Bool {
        plan.allocations[id.uuidString] != nil || plan.percentAllocations[id.uuidString] != nil
    }

    // MARK: Wijzigen

    /// Overschrijft de verdeling van één maand met een percentage van het inkomen (variabel percentage). Zonder `basis`
    /// geldt de grondslag van de pot of belegging. Een eventuele overschrijving met een bedrag vervalt. Het percentage
    /// wordt 0...100 op twee decimalen.
    mutating func setAllocationPercent(_ id: UUID, in month: YearMonth, percent: Double, basis: IncomeBasis? = nil) {
        let chosen = basis ?? pot(id)?.contributionBasis ?? holdings.first(where: { $0.id == id })?.contributionBasis ?? .salary
        let rule = PercentRule(percent: AllocationMath.cleanPercent(percent), basis: chosen)
        editPlan(month) {
            $0.percentAllocations[id.uuidString] = rule
            $0.allocations.removeValue(forKey: id.uuidString)
        }
    }

    /// Haalt de overschrijving van een maand weg (bedrag en percentage): de standaardinleg van de pot of belegging geldt
    /// weer.
    mutating func clearAllocationOverride(_ id: UUID, in month: YearMonth) {
        editPlan(month) {
            $0.allocations.removeValue(forKey: id.uuidString)
            $0.percentAllocations.removeValue(forKey: id.uuidString)
        }
    }

    /// Zet de standaardinleg van een pot of belegging op een percentage van het inkomen (vast percentage: elke maand
    /// hetzelfde). Voor de lopende maand geldt het ook meteen, zoals bij een nieuwe standaardinleg met een bedrag.
    mutating func setContributionPercent(_ id: UUID, percent: Double, basis: IncomeBasis, current: YearMonth) {
        let clean = AllocationMath.cleanPercent(percent)
        if var updated = pot(id) {
            updated.contributionMode = .percentage
            updated.contributionPercent = clean
            updated.contributionBasis = basis
            updatePot(updated, current: current)
        } else if var updated = holdings.first(where: { $0.id == id }) {
            updated.contributionMode = .percentage
            updated.contributionPercent = clean
            updated.contributionBasis = basis
            updateHolding(updated, current: current)
        }
    }

    // MARK: Rekenhulp

    /// Wat `percent` van het inkomen van `month` is in euro's, precies zoals de verdeling het uitrekent ("dit percentage
    /// is nu X euro").
    func percentAmount(_ percent: Double, of basis: IncomeBasis = .salary, in month: YearMonth) -> Double {
        let rule = PercentRule(percent: percent, basis: basis)
        return CentsMath.value(AllocationMath.cents(of: rule, bases: incomeBases(in: month)))
    }

    /// Het percentage (op twee decimalen, 0...100) van het inkomen van `month` dat bij `amount` hoort. nil zonder inkomen.
    func percent(forAmount amount: Double, of basis: IncomeBasis = .salary, in month: YearMonth) -> Double? {
        let income = incomeBases(in: month).cents(for: basis)
        guard income > 0 else { return nil }
        let share = Double(CentsMath.int(amount)) / Double(income) * 100
        return AllocationMath.cleanPercent(share)
    }

    // MARK: Waarschuwingen

    /// De percentages van alle potten en beleggingen die in `month` een percentage hebben, bij elkaar (in procenten).
    func percentTotal(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        var hundredths = 0
        for id in pots.map(\.id) + holdings.map(\.id) {
            if case .percent(let rule) = allocationRule(id, in: month) { hundredths += AllocationMath.hundredths(rule.percent) }
        }
        return Double(hundredths) / 100
    }

    /// Waar de verdeling van `month` niet klopt: de percentages samen zijn meer dan 100%, of er wordt meer verdeeld dan er
    /// te verdelen is (inkomen min uitgaven van de bank). Leeg als alles in orde is. Geen crash: de bedragen worden gewoon
    /// uitgerekend, de UI toont deze waarschuwing erbij.
    func allocationWarnings(in month: YearMonth) -> [AllocationWarning] {
        guard month >= startMonth else { return [] }
        var warnings: [AllocationWarning] = []
        let total = percentTotal(in: month)
        if total > 100 { warnings.append(.percentagesOver100(total: total)) }
        let over = monthFigures(month).overAllocated
        if over > 0 { warnings.append(.overAllocated(by: CentsMath.value(over))) }
        return warnings
    }

    /// De eerste waarschuwing als tekst (voor één regel in de UI), of nil.
    func allocationWarning(in month: YearMonth) -> String? {
        allocationWarnings(in: month).first?.message
    }
}
