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
        basis = c.decodeLenient(IncomeBasis.self, forKey: .basis, default: .salary)
    }

    /// Een percentage dat geen getal is (NaN of oneindig) wordt als 0 bewaard: de JSON-encoder weigert zulke waarden, en dan
    /// zouden opslaan, back-up en synchroniseren allemaal falen.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(percent.isFinite ? percent : 0, forKey: .percent)
        try c.encode(basis, forKey: .basis)
    }
}

extension KeyedDecodingContainer {
    /// Leest een waarde die ontbreekt of die deze versie van de app niet kent (bijvoorbeeld een nieuwe keuze uit een nieuwere
    /// versie) als `fallback`, in plaats van het hele bestand te laten falen.
    func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? fallback
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

    /// Korte tekst voor in de UI: "€ 300" voor een vast bedrag, "10% van je salaris" of "12,5% van al je inkomsten" voor
    /// een percentage.
    var summary: String {
        switch self {
        case .amount(let value):
            return Fmt.euro(value)
        case .percent(let rule):
            let base = rule.basis == .salary ? "je salaris" : "al je inkomsten"
            return "\(Fmt.percent(rule.percent / 100, digits: 2)) van \(base)"
        }
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

/// Onthoudt het inkomen per maand van één `FinanceData` zolang een berekening duurt. Niet bewaren: bij een wijziging van
/// de gegevens klopt hij niet meer; maak voor elke berekening een nieuwe (`FinanceData.incomeBasesCache()`).
final class IncomeBasesCache {
    private let data: FinanceData
    private let stored: StoredPlans
    private var values: [YearMonth: IncomeBases] = [:]

    fileprivate init(_ data: FinanceData) {
        self.data = data
        self.stored = data.storedPlans
    }

    /// Het inkomen van `month` per grondslag: hetzelfde als `FinanceData.incomeBases(in:)`.
    func bases(in month: YearMonth) -> IncomeBases {
        if let known = values[month] { return known }
        let computed = data.incomeBases(in: month, using: stored)
        values[month] = computed
        return computed
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
    /// De inlegwijze zoals ingesteld, los van een maand: het vaste bedrag of het percentage met zijn grondslag. Het
    /// percentage staat hier al op twee decimalen (zoals het wordt uitgerekend).
    var contributionRule: AllocationRule {
        switch contributionMode {
        case .fixed: return .amount(monthlyContribution)
        case .percentage: return .percent(PercentRule(percent: AllocationMath.cleanPercent(contributionPercent), basis: contributionBasis))
        }
    }

    /// De standaardregel voor een maand (zonder overschrijving): vanaf de startmaand de inlegwijze, ervoor niets.
    func defaultRule(in month: YearMonth) -> AllocationRule {
        guard month >= startMonth else { return .amount(0) }
        return contributionRule
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
    ///
    /// Maanden vóór de startmaand van de gegevens tellen nergens mee (`monthFigures`, `savedTotal(in:)`): ook de verdeling
    /// van een pot of belegging daarin is dan niets (een bedrag van nul), ook als de pot zelf al eerder begon (import,
    /// synchroniseren).
    func defaultAllocationRule(_ id: UUID, in month: YearMonth) -> AllocationRule? {
        let before = month < startMonth
        if let pot = pots.first(where: { $0.id == id }) { return before ? .amount(0) : pot.defaultRule(in: month) }
        if let holding = holdings.first(where: { $0.id == id }) { return before ? .amount(0) : holding.defaultRule(in: month) }
        return nil
    }

    /// De regel die in een maand voor een pot of belegging geldt: de overschrijving van die maand (een percentage gaat
    /// voor een bedrag), anders de standaardregel.
    func allocationRule(_ id: UUID, in month: YearMonth) -> AllocationRule {
        guard month >= startMonth else { return .amount(0) }
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
        // Op hele centen, zoals `allocationCents` en de sommen (een bedrag met meer dan twee decimalen komt uit import of oude bestanden).
        case .amount(let value): return CentsMath.value(CentsMath.int(value))
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

    /// Een nieuwe tussenopslag van het inkomen per maand, voor een lus over veel maanden (zie `IncomeBasesCache`).
    func incomeBasesCache() -> IncomeBasesCache {
        IncomeBasesCache(self)
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
        let salary = salaryCents(in: month, plan: plan)
        return IncomeBases(salary: salary, all: CentsMath.add(salary, extra))
    }

    // MARK: Het bedrag, op één plek uitgerekend
    //
    // Wie veel maanden achter elkaar leest (de waarde van een belegging door de tijd, een reeks voor een grafiek) maakt één
    // `IncomeBasesCache` en geeft die door: het inkomen van een maand wordt dan één keer uitgerekend, niet bij elke
    // pot, belegging of tussenstap opnieuw (dat bouwt telkens het hele maandplan).

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

    /// Zoals `allocation(_:in:)`, met het inkomen van de maand uit `cache`: precies hetzelfde getal, maar zonder het
    /// maandplan bij elke aanroep opnieuw te bouwen (voor lussen over veel maanden).
    func allocation(_ id: UUID, in month: YearMonth, cache: IncomeBasesCache) -> Double {
        switch allocationRule(id, in: month) {
        case .amount(let value): return CentsMath.value(CentsMath.int(value))
        case .percent(let rule): return CentsMath.value(AllocationMath.cents(of: rule, bases: cache.bases(in: month)))
        }
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

    /// Overschrijft de verdeling van één maand met een regel (bedrag of percentage). Een eerdere overschrijving van die
    /// maand voor deze pot of belegging vervalt.
    mutating func setAllocationRule(_ id: UUID, in month: YearMonth, rule: AllocationRule) {
        switch rule {
        case .amount(let value): setAllocation(id, in: month, amount: value)
        case .percent(let percent): setAllocationPercent(id, in: month, percent: percent.percent, basis: percent.basis)
        }
    }

    /// De inlegwijze van een pot of belegging (vast bedrag of percentage), los van een maand. nil als het id niet bestaat.
    func contributionRule(of id: UUID) -> AllocationRule? {
        if let pot = pot(id) { return pot.contributionRule }
        return holdings.first(where: { $0.id == id })?.contributionRule
    }

    /// Zet de standaardinleg van een pot of belegging op een percentage van het inkomen (vast percentage: elke maand
    /// hetzelfde). Voor de lopende maand geldt het ook meteen, zoals bij een nieuwe standaardinleg met een bedrag.
    mutating func setContributionPercent(_ id: UUID, percent: Double, basis: IncomeBasis, current: YearMonth) {
        let clean = AllocationMath.cleanPercent(percent)
        let before = contributionRule(of: id)
        if let i = pots.firstIndex(where: { $0.id == id }) {
            pots[i].contributionMode = .percentage
            pots[i].contributionPercent = clean
            pots[i].contributionBasis = basis
        } else if let i = holdings.firstIndex(where: { $0.id == id }) {
            holdings[i].contributionMode = .percentage
            holdings[i].contributionPercent = clean
            holdings[i].contributionBasis = basis
        } else {
            return
        }
        syncCurrentMonth(id, with: before, current: current)
    }

    /// Zet de standaardinleg van een pot of belegging op een vast bedrag per maand (zoals voor de percentages bestond).
    /// Voor de lopende maand geldt het ook meteen.
    mutating func setContributionAmount(_ id: UUID, amount: Double, current: YearMonth) {
        let before = contributionRule(of: id)
        if let i = pots.firstIndex(where: { $0.id == id }) {
            pots[i].contributionMode = .fixed
            pots[i].monthlyContribution = amount.cents
        } else if let i = holdings.firstIndex(where: { $0.id == id }) {
            holdings[i].contributionMode = .fixed
            holdings[i].monthlyContribution = amount.cents
        } else {
            return
        }
        syncCurrentMonth(id, with: before, current: current)
    }

    /// Na een wijziging van de standaardinleg (`before` was de oude): de lopende maand krijgt de nieuwe standaard,
    /// maar alleen als de inlegwijze echt veranderde en de pot of belegging al bestaat. Eerdere maanden blijven
    /// zoals ze waren: die zijn vastgelegd (`materialize`) of volgen de standaard van hun tijd niet meer.
    ///
    /// Maanden NA de lopende maand die al zijn vastgelegd (door een eenmalige uitgave, een eigen salaris, een overschrijfdag:
    /// elke bewerking legt de standaardinleg van dat moment vast) krijgen de nieuwe standaard ook, maar alleen als ze nog de
    /// OUDE standaard hadden. Een eigen afwijking van de gebruiker voor zo'n maand (een ander bedrag of percentage) blijft.
    /// Zonder dit zou "elke maand 10%" in een bewerkte toekomstige maand bij het oude bedrag blijven staan, als "Afwijkend".
    ///
    /// Wie een pot of belegging zelf wijzigt (`updatePot`, `updateHolding`) en daarbij de inlegwijze verandert, roept
    /// dit aan om de lopende maand mee te laten gaan.
    mutating func syncCurrentMonth(_ id: UUID, with before: AllocationRule?, current: YearMonth) {
        guard let after = contributionRule(of: id), after != before else { return }
        let start = pot(id)?.startMonth ?? holdings.first(where: { $0.id == id })?.startMonth
        guard let start, current >= start else { return }
        editPlan(current) { plan in
            plan.allocations.removeValue(forKey: id.uuidString)
            plan.percentAllocations.removeValue(forKey: id.uuidString)
            switch after {
            case .amount(let value): plan.allocations[id.uuidString] = value.cents
            case .percent(let rule): plan.percentAllocations[id.uuidString] = rule
            }
        }
        guard let before else { return }
        let key = id.uuidString
        for monthKey in Array(months.keys) {
            guard let month = YearMonth(key: monthKey), month > current, month >= start, var plan = months[monthKey] else { continue }
            let stored: AllocationRule? = plan.percentAllocations[key].map { AllocationRule.percent($0) }
                ?? plan.allocations[key].map { AllocationRule.amount($0) }
            // Vergelijk een vast bedrag op hele centen: een vastgelegd bedrag staat op centen, het oude bedrag kan er meer hebben.
            guard let stored, FinanceData.sameRule(stored, before) else { continue }
            plan.allocations.removeValue(forKey: key)
            plan.percentAllocations.removeValue(forKey: key)
            switch after {
            case .amount(let value): plan.allocations[key] = value.cents
            case .percent(let rule): plan.percentAllocations[key] = rule
            }
            months[monthKey] = plan
        }
    }

    /// Zijn twee regels dezelfde inleg? Een vast bedrag telt op hele centen, een percentage op twee decimalen.
    private static func sameRule(_ a: AllocationRule, _ b: AllocationRule) -> Bool {
        switch (a, b) {
        case (.amount(let x), .amount(let y)):
            return CentsMath.int(x) == CentsMath.int(y)
        case (.percent(let x), .percent(let y)):
            return x.basis == y.basis && AllocationMath.hundredths(x.percent) == AllocationMath.hundredths(y.percent)
        default:
            return false
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

    /// De percentages van alle potten en beleggingen die in `month` een percentage hebben, per grondslag opgeteld in
    /// honderdsten van een procent (12,5% is 1250).
    private func percentHundredths(in month: YearMonth) -> (salary: Int, allIncome: Int) {
        guard month >= startMonth else { return (0, 0) }
        var salary = 0
        var allIncome = 0
        for id in pots.map(\.id) + holdings.map(\.id) {
            guard case .percent(let rule) = allocationRule(id, in: month) else { continue }
            if rule.basis == .salary { salary += AllocationMath.hundredths(rule.percent) } else { allIncome += AllocationMath.hundredths(rule.percent) }
        }
        return (salary, allIncome)
    }

    /// De percentages van alle potten en beleggingen die in `month` een percentage hebben, bij elkaar (in procenten), zoals
    /// ze zijn ingesteld: los van hun grondslag. Of ze samen te veel zijn zegt `allocationWarnings(in:)`.
    func percentTotal(in month: YearMonth) -> Double {
        let (salary, allIncome) = percentHundredths(in: month)
        return Double(salary + allIncome) / 100
    }

    /// Zijn de percentages van `month` samen meer dan 100%, dan het totaal in procenten (anders nil).
    ///
    /// - Allemaal op dezelfde grondslag (alleen salaris, of alle inkomsten): de som van de ingestelde percentages.
    /// - Een mengeling van beide grondslagen: de optelling van de percentages zou niets zeggen (60% van het salaris en 50% van
    ///   alle inkomsten is geen 110% als er ook een bonus is). Dan telt wat de percentages van het inkomen van die maand
    ///   werkelijk vragen, als percentage van alle inkomsten (zonder inkomen: de som van de percentages).
    private func percentOverrun(in month: YearMonth) -> Double? {
        let (salary, allIncome) = percentHundredths(in: month)
        let raw = salary + allIncome
        if salary == 0 || allIncome == 0 { return raw > 10_000 ? Double(raw) / 100 : nil }
        let bases = incomeBases(in: month)
        let all = bases.cents(for: .allIncome)
        guard all > 0 else { return raw > 10_000 ? Double(raw) / 100 : nil }
        let weighted = (Double(salary) * Double(bases.cents(for: .salary)) + Double(allIncome) * Double(all)) / Double(all)
        guard weighted > 10_000 else { return nil }
        return weighted.rounded(.up) / 100
    }

    /// Waar de verdeling van `month` niet klopt: de percentages samen zijn meer dan 100%, of er wordt meer verdeeld dan er
    /// te verdelen is (inkomen min uitgaven van de bank). Leeg als alles in orde is. Geen crash: de bedragen worden gewoon
    /// uitgerekend, de UI toont deze waarschuwing erbij.
    func allocationWarnings(in month: YearMonth) -> [AllocationWarning] {
        guard month >= startMonth else { return [] }
        var warnings: [AllocationWarning] = []
        if let total = percentOverrun(in: month) { warnings.append(.percentagesOver100(total: total)) }
        let over = monthFigures(month).overAllocated
        if over > 0 { warnings.append(.overAllocated(by: CentsMath.value(over))) }
        return warnings
    }

    /// De eerste waarschuwing als tekst (voor één regel in de UI), of nil.
    func allocationWarning(in month: YearMonth) -> String? {
        allocationWarnings(in: month).first?.message
    }
}
