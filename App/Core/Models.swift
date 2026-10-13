import Foundation

// MARK: - Hulpjes

extension Double {
    /// Afgerond op hele centen.
    var cents: Double { (self * 100).rounded() / 100 }
}

// MARK: - Salaris en maandplan

enum SalaryMode: String, Codable, CaseIterable, Identifiable {
    case fixed, hourly
    var id: String { rawValue }
    var title: String { self == .fixed ? "Vast bedrag" : "Uurloon" }
}

struct SalarySettings: Codable, Equatable {
    var mode: SalaryMode = .fixed
    /// Netto bedrag per maand bij `.fixed`.
    var fixedMonthly: Double = 0
    /// Netto uurloon bij `.hourly`.
    var hourlyRate: Double = 0
    var hoursPerWeek: Double = 0
    /// Dag van de maand waarop het salaris binnenkomt (1...31; korte maanden gebruiken de laatste dag).
    var payDay: Int = 25

    enum CodingKeys: String, CodingKey { case mode, fixedMonthly, hourlyRate, hoursPerWeek, payDay }

    /// Gemiddeld aantal uren per maand: uren per week × 52 / 12.
    var defaultMonthlyHours: Double { hoursPerWeek * 52 / 12 }

    /// Maandsalaris. Bij uurloon: uurloon × (uren dit maand, of het gemiddelde).
    func monthlyAmount(hoursOverride: Double? = nil) -> Double {
        switch mode {
        case .fixed: return fixedMonthly.cents
        case .hourly: return (hourlyRate * (hoursOverride ?? defaultMonthlyHours)).cents
        }
    }
}

// decodeIfPresent: oude opslagbestanden zonder `payDay` blijven laden.
extension SalarySettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        mode = try c.decodeIfPresent(SalaryMode.self, forKey: .mode) ?? mode
        fixedMonthly = try c.decodeIfPresent(Double.self, forKey: .fixedMonthly) ?? fixedMonthly
        hourlyRate = try c.decodeIfPresent(Double.self, forKey: .hourlyRate) ?? hourlyRate
        hoursPerWeek = try c.decodeIfPresent(Double.self, forKey: .hoursPerWeek) ?? hoursPerWeek
        payDay = try c.decodeIfPresent(Int.self, forKey: .payDay) ?? payDay
    }
}

/// Vaste lasten (huur, verzekeringen) of variabele uitgaven (boodschappen, uit eten).
enum ExpenseKind: String, Codable, CaseIterable, Identifiable {
    case fixed, variable
    var id: String { rawValue }
    var title: String { self == .fixed ? "Vast" : "Variabel" }
}

/// Een deel van een uitgave dat uit een spaarpot betaald wordt.
struct PotShare: Identifiable, Codable, Equatable {
    var id = UUID()
    var potID: UUID
    var amount: Double
}

/// Een regel met een bedrag: extra inkomen of uitgave.
struct MoneyLine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double
    /// Terugkerende regels worden automatisch naar volgende maanden gekopieerd.
    var isRecurring: Bool = false
    /// Alleen van belang voor uitgaven.
    var kind: ExpenseKind = .fixed
    /// Dag van de maand waarop het bedrag binnenkomt of eraf gaat (1...31). nil = inkomsten op de
    /// salarisdag, uitgaven op de 1e.
    var day: Int?
    /// Uitgaven: welk deel uit welke spaarpot komt. Wat overblijft gaat van de bankrekening.
    var potShares: [PotShare] = []
    /// Reeks-id van een terugkerende regel: alle maanden van dezelfde terugkerende regel delen dit id (zie
    /// `RecurringSeries.swift`). nil bij eenmalige regels. Oude bestanden hebben dit niet; de rekenmotor leidt het dan af
    /// uit de keten van afgeleide regel-id's.
    var seriesID: UUID?
    /// Deze regel wijkt alleen in deze maand af van de reeks ("alleen deze maand" bewerkt). Zo'n regel bepaalt de
    /// volgende maanden niet.
    var isException: Bool = false

    enum CodingKeys: String, CodingKey { case id, name, amount, isRecurring, kind, day, potShares, seriesID, isException }
}

extension MoneyLine {
    /// Totaal dat uit spaarpotten komt (nooit meer dan het bedrag zelf, nooit negatief).
    var fromPots: Double {
        let total = potShares.reduce(0) { $0 + $1.amount }
        return min(max(0, total), max(0, amount)).cents
    }

    /// Wat van de bankrekening afgaat (of bij inkomsten: erbij komt).
    var fromBank: Double { (amount - fromPots).cents }
}

// decodeIfPresent: oude opslagbestanden zonder `kind` blijven laden.
extension MoneyLine {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  amount: try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0,
                  isRecurring: try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false,
                  kind: try c.decodeIfPresent(ExpenseKind.self, forKey: .kind) ?? .fixed,
                  day: try c.decodeIfPresent(Int.self, forKey: .day),
                  potShares: try c.decodeIfPresent([PotShare].self, forKey: .potShares) ?? [],
                  seriesID: try c.decodeIfPresent(UUID.self, forKey: .seriesID),
                  isException: try c.decodeIfPresent(Bool.self, forKey: .isException) ?? false)
    }

    /// De nieuwe velden worden alleen geschreven als ze iets zeggen: een bestand zonder reeksen blijft byte voor byte
    /// zoals het was (compact, en gelijk voor cloud, back-up en vergelijken).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(amount, forKey: .amount)
        try c.encode(isRecurring, forKey: .isRecurring)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(day, forKey: .day)
        try c.encode(potShares, forKey: .potShares)
        try c.encodeIfPresent(seriesID, forKey: .seriesID)
        if isException { try c.encode(isException, forKey: .isException) }
    }
}

extension Array where Element == MoneyLine {
    var total: Double { reduce(0) { $0 + $1.amount }.cents }
    func total(of kind: ExpenseKind) -> Double { filter { $0.kind == kind }.total }
    /// Het deel van de regels dat uit spaarpotten betaald wordt.
    var totalFromPots: Double { reduce(0) { $0 + $1.fromPots }.cents }
}

struct MonthPlan: Codable, Equatable {
    /// Afwijkend maandsalaris (vast bedrag) voor deze maand.
    var salaryOverride: Double?
    /// Gewerkte uren deze maand (bij uurloon).
    var hoursOverride: Double?
    var extraIncome: [MoneyLine] = []
    var expenses: [MoneyLine] = []
    /// Verdeling: id van spaarpot of belegging → bedrag deze maand.
    var allocations: [String: Double] = [:]
    /// Dag van de maand waarop de verdeling over spaarpotten en beleggingen wordt overgeboekt.
    /// nil = de dag van de pot of belegging zelf, anders de salarisdag.
    var transferDay: Int?
    /// Verdeling als percentage van het inkomen van deze maand: id van spaarpot of belegging → regel. Gaat voor op
    /// `allocations`; het bedrag wordt bij het lezen uitgerekend (zie `Allocation.swift`).
    var percentAllocations: [String: PercentRule] = [:]
    /// Reeksen (terugkerende regels) die in deze maand zijn overgeslagen: de regel komt in deze maand niet voor,
    /// in de maanden erna wel. Zie `RecurringSeries.swift`.
    var skippedSeries: [UUID] = []
    /// Reeksen die vanaf deze maand zijn gestopt: de regel komt in deze en alle volgende maanden niet meer terug.
    var endedSeries: [UUID] = []

    enum CodingKeys: String, CodingKey {
        case salaryOverride, hoursOverride, extraIncome, expenses, allocations, transferDay
        case percentAllocations, skippedSeries, endedSeries
    }
}

// decodeIfPresent: oude opslagbestanden zonder percentages en reeksen blijven laden. De nieuwe velden worden alleen
// geschreven als ze iets zeggen, zodat een bestand zonder die functies byte voor byte gelijk blijft.
extension MonthPlan {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        salaryOverride = try c.decodeIfPresent(Double.self, forKey: .salaryOverride)
        hoursOverride = try c.decodeIfPresent(Double.self, forKey: .hoursOverride)
        extraIncome = try c.decodeIfPresent([MoneyLine].self, forKey: .extraIncome) ?? []
        expenses = try c.decodeIfPresent([MoneyLine].self, forKey: .expenses) ?? []
        allocations = try c.decodeIfPresent([String: Double].self, forKey: .allocations) ?? [:]
        transferDay = try c.decodeIfPresent(Int.self, forKey: .transferDay)
        percentAllocations = try c.decodeIfPresent([String: PercentRule].self, forKey: .percentAllocations) ?? [:]
        skippedSeries = try c.decodeIfPresent([UUID].self, forKey: .skippedSeries) ?? []
        endedSeries = try c.decodeIfPresent([UUID].self, forKey: .endedSeries) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(salaryOverride, forKey: .salaryOverride)
        try c.encodeIfPresent(hoursOverride, forKey: .hoursOverride)
        try c.encode(extraIncome, forKey: .extraIncome)
        try c.encode(expenses, forKey: .expenses)
        try c.encode(allocations, forKey: .allocations)
        try c.encodeIfPresent(transferDay, forKey: .transferDay)
        if !percentAllocations.isEmpty { try c.encode(percentAllocations, forKey: .percentAllocations) }
        if !skippedSeries.isEmpty { try c.encode(skippedSeries, forKey: .skippedSeries) }
        if !endedSeries.isEmpty { try c.encode(endedSeries, forKey: .endedSeries) }
    }
}

// MARK: - Spaarpotten

enum PotEntryKind: String, Codable {
    case opening, deposit, withdrawal, adjustment, transferIn, transferOut, interest, expense

    var title: String {
        switch self {
        case .opening: return "Beginsaldo"
        case .deposit: return "Gestort"
        case .withdrawal: return "Opgenomen"
        case .adjustment: return "Saldo aangepast"
        case .transferIn: return "Overgeboekt naar deze pot"
        case .transferOut: return "Overgeboekt naar andere pot"
        case .interest: return "Rente"
        case .expense: return "Uitgave betaald"
        }
    }
}

/// Hoe vaak een spaarpot rente uitbetaalt.
enum InterestPayout: String, Codable, CaseIterable, Identifiable {
    case monthly, quarterly, halfYearly, yearly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "Elke maand"
        case .quarterly: return "Elk kwartaal"
        case .halfYearly: return "Elk half jaar"
        case .yearly: return "Elk jaar"
        }
    }

    /// Aantal maanden tussen twee uitbetalingen.
    var intervalMonths: Int {
        switch self {
        case .monthly: return 1
        case .quarterly: return 3
        case .halfYearly: return 6
        case .yearly: return 12
        }
    }
}

struct Pot: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// SF Symbol.
    var symbol: String = "banknote"
    var colorIndex: Int = 0
    var goalAmount: Double?
    var goalDate: Date?
    /// Standaard maandelijkse inleg.
    var monthlyContribution: Double = 0
    var startMonth: YearMonth
    var createdAt = Date()
    /// Rente per jaar als breuk (0,02 = 2%). 0 = geen rente.
    var interestRate: Double = 0
    var interestPayout: InterestPayout = .yearly
    /// Dag van de maand waarop de rente wordt bijgeschreven (1...31).
    var interestPayoutDay: Int = 1
    /// De maand (1...12) waarin de eerste uitbetaling van het jaar valt; de volgende volgen
    /// op `interestPayout.intervalMonths` afstand. Bij maandelijks is dit niet van belang.
    var interestPayoutMonth: Int = 1
    /// Dag van de maand waarop de maandelijkse inleg wordt overgeboekt. nil = salarisdag.
    var transferDay: Int?
    /// Inlegwijze: een vast bedrag (`monthlyContribution`) of een percentage van het inkomen van die maand.
    var contributionMode: ContributionMode = .fixed
    /// Het percentage van het inkomen (0...100, maximaal twee decimalen) bij `contributionMode == .percentage`.
    var contributionPercent: Double = 0
    /// Waarover het percentage wordt berekend: alleen salaris of alle inkomsten van die maand.
    var contributionBasis: IncomeBasis = .salary

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, colorIndex, goalAmount, goalDate, monthlyContribution, startMonth, createdAt
        case interestRate, interestPayout, interestPayoutDay, interestPayoutMonth, transferDay
        case contributionMode, contributionPercent, contributionBasis
    }
}

// decodeIfPresent: oude opslagbestanden zonder rente- en overboekvelden blijven laden.
extension Pot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  symbol: try c.decodeIfPresent(String.self, forKey: .symbol) ?? "banknote",
                  colorIndex: try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0,
                  goalAmount: try c.decodeIfPresent(Double.self, forKey: .goalAmount),
                  goalDate: try c.decodeIfPresent(Date.self, forKey: .goalDate),
                  monthlyContribution: try c.decodeIfPresent(Double.self, forKey: .monthlyContribution) ?? 0,
                  startMonth: try c.decodeIfPresent(YearMonth.self, forKey: .startMonth) ?? YearMonth.current(),
                  createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
                  interestRate: try c.decodeIfPresent(Double.self, forKey: .interestRate) ?? 0,
                  interestPayout: try c.decodeIfPresent(InterestPayout.self, forKey: .interestPayout) ?? .yearly,
                  interestPayoutDay: try c.decodeIfPresent(Int.self, forKey: .interestPayoutDay) ?? 1,
                  interestPayoutMonth: try c.decodeIfPresent(Int.self, forKey: .interestPayoutMonth) ?? 1,
                  transferDay: try c.decodeIfPresent(Int.self, forKey: .transferDay),
                  contributionMode: try c.decodeIfPresent(ContributionMode.self, forKey: .contributionMode) ?? .fixed,
                  contributionPercent: try c.decodeIfPresent(Double.self, forKey: .contributionPercent) ?? 0,
                  contributionBasis: try c.decodeIfPresent(IncomeBasis.self, forKey: .contributionBasis) ?? .salary)
    }

    /// De velden van de inlegwijze worden alleen geschreven als ze afwijken van een vast bedrag: een bestand zonder
    /// percentages blijft gelijk aan vroeger.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(colorIndex, forKey: .colorIndex)
        try c.encodeIfPresent(goalAmount, forKey: .goalAmount)
        try c.encodeIfPresent(goalDate, forKey: .goalDate)
        try c.encode(monthlyContribution, forKey: .monthlyContribution)
        try c.encode(startMonth, forKey: .startMonth)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(interestRate, forKey: .interestRate)
        try c.encode(interestPayout, forKey: .interestPayout)
        try c.encode(interestPayoutDay, forKey: .interestPayoutDay)
        try c.encode(interestPayoutMonth, forKey: .interestPayoutMonth)
        try c.encodeIfPresent(transferDay, forKey: .transferDay)
        if contributionMode != .fixed { try c.encode(contributionMode, forKey: .contributionMode) }
        if contributionPercent != 0 { try c.encode(contributionPercent, forKey: .contributionPercent) }
        if contributionBasis != .salary { try c.encode(contributionBasis, forKey: .contributionBasis) }
    }
}

struct PotEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var potID: UUID
    var date: Date
    /// Positief = erbij, negatief = eraf.
    var amount: Double
    var kind: PotEntryKind
    var note: String = ""
    /// Hoort bij een overboeking: de twee kanten (pot en bank, of pot en pot) delen dit id,
    /// zodat ze samen worden verwijderd en er nooit geld uit het niets ontstaat.
    var pairID: UUID?
}

// MARK: - Bankrekening

struct BankSnapshot: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var balance: Double
    var note: String = ""
}

/// Wat voor beweging het is op de bankrekening in de app.
enum BankEntryKind: String, Codable {
    case deposit, withdrawal, toPot, fromPot

    var title: String {
        switch self {
        case .deposit: return "Geld erbij"
        case .withdrawal: return "Geld eraf"
        case .toPot: return "Naar spaarpot"
        case .fromPot: return "Van spaarpot"
        }
    }
}

/// Handmatige beweging op de bankrekening in de app (geen echte bank).
struct BankEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    /// Positief = erbij, negatief = eraf.
    var amount: Double
    var kind: BankEntryKind
    var note: String = ""
    /// Bij overboekingen naar of van een spaarpot.
    var potID: UUID?
    /// Gedeeld met de bijbehorende `PotEntry` van dezelfde overboeking.
    var pairID: UUID?
}

// MARK: - Beleggingen

enum HoldingKind: String, Codable, CaseIterable, Identifiable {
    case etf, stocks, bonds, crypto, realEstate, commodities, savings, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .etf: return "Indexfonds / ETF"
        case .stocks: return "Aandelen"
        case .bonds: return "Obligaties"
        case .crypto: return "Crypto"
        case .realEstate: return "Vastgoed"
        case .commodities: return "Grondstoffen / goud"
        case .savings: return "Spaarrekening / deposito"
        case .other: return "Overig"
        }
    }

    var symbol: String {
        switch self {
        case .etf: return "chart.line.uptrend.xyaxis"
        case .stocks: return "building.columns"
        case .bonds: return "doc.text"
        case .crypto: return "bitcoinsign.circle"
        case .realEstate: return "house"
        case .commodities: return "circle.hexagongrid"
        case .savings: return "banknote"
        case .other: return "square.grid.2x2"
        }
    }

    /// Voorgesteld verwacht rendement per jaar (als breuk).
    var defaultReturn: Double {
        switch self {
        case .etf: return 0.06
        case .stocks: return 0.07
        case .bonds: return 0.025
        case .crypto: return 0.10
        case .realEstate: return 0.05
        case .commodities: return 0.03
        case .savings: return 0.02
        case .other: return 0.04
        }
    }

    /// Voorgestelde jaarlijkse kosten (als breuk).
    var defaultCost: Double {
        switch self {
        case .etf: return 0.002
        case .stocks: return 0.002
        case .bonds: return 0.003
        case .crypto: return 0.005
        case .realEstate: return 0.01
        case .commodities: return 0.004
        case .savings: return 0
        case .other: return 0.005
        }
    }
}

/// Meetpunt van de waarde van een belegging.
struct ValueSnapshot: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var value: Double
    /// Totaal ingelegd op dat moment (voor rendement).
    var invested: Double
}

struct Holding: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: HoldingKind = .etf
    /// Beursticker voor live koersen, bijv. "VWCE.DE" of "BTC-EUR".
    var ticker: String?
    /// Aantal stuks/eenheden (nodig voor live koersen).
    var units: Double?
    /// Totaal ingelegd (kostprijs) voor het rendement.
    var investedTotal: Double = 0
    /// Verwacht rendement per jaar (breuk, bijv. 0,06).
    var expectedReturn: Double = 0.06
    /// Jaarlijkse kosten (breuk, bijv. 0,002).
    var annualCost: Double = 0.002
    var monthlyContribution: Double = 0
    var startMonth: YearMonth
    /// Dag van de maand waarop de maandelijkse inleg wordt overgeboekt. nil = salarisdag.
    var transferDay: Int?
    var snapshots: [ValueSnapshot] = []
    var lastPrice: Double?
    var lastPriceDate: Date?
    var priceCurrency: String?
    /// Inlegwijze: een vast bedrag (`monthlyContribution`) of een percentage van het inkomen van die maand.
    var contributionMode: ContributionMode = .fixed
    /// Het percentage van het inkomen (0...100, maximaal twee decimalen) bij `contributionMode == .percentage`.
    var contributionPercent: Double = 0
    /// Waarover het percentage wordt berekend: alleen salaris of alle inkomsten van die maand.
    var contributionBasis: IncomeBasis = .salary

    enum CodingKeys: String, CodingKey {
        case id, name, kind, ticker, units, investedTotal, expectedReturn, annualCost, monthlyContribution, startMonth
        case transferDay, snapshots, lastPrice, lastPriceDate, priceCurrency
        case contributionMode, contributionPercent, contributionBasis
    }

    /// Heeft een ticker: de koers kan van internet gehaald worden.
    var hasTicker: Bool {
        guard let t = ticker else { return false }
        return !t.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Heeft een ticker én een aantal, dus de waarde volgt de live koers.
    var isTracked: Bool {
        guard hasTicker, let u = units, u > 0 else { return false }
        return true
    }

    /// Rendement na kosten per jaar.
    var netReturn: Double { expectedReturn - annualCost }
}

// De velden die er al waren blijven verplicht (zoals de automatische codering ze las); alleen de velden van de
// inlegwijze zijn optioneel, zodat oude opslagbestanden blijven laden. Die velden worden ook alleen geschreven als ze
// afwijken van een vast bedrag, zodat een bestand zonder percentages gelijk blijft aan vroeger.
extension Holding {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  kind: try c.decode(HoldingKind.self, forKey: .kind),
                  ticker: try c.decodeIfPresent(String.self, forKey: .ticker),
                  units: try c.decodeIfPresent(Double.self, forKey: .units),
                  investedTotal: try c.decode(Double.self, forKey: .investedTotal),
                  expectedReturn: try c.decode(Double.self, forKey: .expectedReturn),
                  annualCost: try c.decode(Double.self, forKey: .annualCost),
                  monthlyContribution: try c.decode(Double.self, forKey: .monthlyContribution),
                  startMonth: try c.decode(YearMonth.self, forKey: .startMonth),
                  transferDay: try c.decodeIfPresent(Int.self, forKey: .transferDay),
                  snapshots: try c.decode([ValueSnapshot].self, forKey: .snapshots),
                  lastPrice: try c.decodeIfPresent(Double.self, forKey: .lastPrice),
                  lastPriceDate: try c.decodeIfPresent(Date.self, forKey: .lastPriceDate),
                  priceCurrency: try c.decodeIfPresent(String.self, forKey: .priceCurrency),
                  contributionMode: try c.decodeIfPresent(ContributionMode.self, forKey: .contributionMode) ?? .fixed,
                  contributionPercent: try c.decodeIfPresent(Double.self, forKey: .contributionPercent) ?? 0,
                  contributionBasis: try c.decodeIfPresent(IncomeBasis.self, forKey: .contributionBasis) ?? .salary)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(ticker, forKey: .ticker)
        try c.encodeIfPresent(units, forKey: .units)
        try c.encode(investedTotal, forKey: .investedTotal)
        try c.encode(expectedReturn, forKey: .expectedReturn)
        try c.encode(annualCost, forKey: .annualCost)
        try c.encode(monthlyContribution, forKey: .monthlyContribution)
        try c.encode(startMonth, forKey: .startMonth)
        try c.encodeIfPresent(transferDay, forKey: .transferDay)
        try c.encode(snapshots, forKey: .snapshots)
        try c.encodeIfPresent(lastPrice, forKey: .lastPrice)
        try c.encodeIfPresent(lastPriceDate, forKey: .lastPriceDate)
        try c.encodeIfPresent(priceCurrency, forKey: .priceCurrency)
        if contributionMode != .fixed { try c.encode(contributionMode, forKey: .contributionMode) }
        if contributionPercent != 0 { try c.encode(contributionPercent, forKey: .contributionPercent) }
        if contributionBasis != .salary { try c.encode(contributionBasis, forKey: .contributionBasis) }
    }
}

// MARK: - Doelen

enum GoalKind: String, Codable, CaseIterable, Identifiable {
    case retirement, vacation, partTime, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .retirement: return "Met pensioen"
        case .vacation: return "Vakantie"
        case .partTime: return "Parttime werken"
        case .custom: return "Eigen doel"
        }
    }

    var symbol: String {
        switch self {
        case .retirement: return "figure.and.child.holdinghands"
        case .vacation: return "airplane"
        case .partTime: return "clock.badge.checkmark"
        case .custom: return "flag.checkered"
        }
    }
}

/// Waaruit het doel gefinancierd wordt.
enum GoalFunding: Codable, Equatable {
    case portfolio
    case pot(UUID)
    case custom(start: Double, monthly: Double, annualReturn: Double)
}

struct LifeGoal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: GoalKind
    /// Doelbedrag bij vakantie of eigen doel.
    var targetAmount: Double = 0
    var targetDate: Date?
    /// Pensioen: gewenst netto bedrag per maand, in euro's van vandaag.
    var monthlySpending: Double = 0
    /// Pensioen/parttime: andere inkomsten, zoals AOW of pensioen.
    var otherMonthlyIncome: Double = 0
    var withdrawalRate: Double = 0.04
    var currentAge: Int?
    /// Parttime: uren per week nu en straks.
    var hoursFrom: Double = 0
    var hoursTo: Double = 0
    /// Parttime: handmatig inkomensverlies per maand (anders uit je salaris).
    var monthlyGapOverride: Double?
    /// Parttime: hoeveel jaar je parttime wilt werken. nil = onbeperkt.
    var partTimeYears: Int?
    /// Rekenen in koopkracht van vandaag.
    var inflationAdjusted: Bool = true
    var funding: GoalFunding = .portfolio
}

// MARK: - Instellingen en hoofdstructuur

struct AppSettings: Codable, Equatable {
    var inflation: Double = 0.02
    var defaultWithdrawalRate: Double = 0.04
    /// Hoeveel maanden aan uitgaven je op de bankrekening wilt houden.
    var bankBufferMonths: Double = 2
    var autoRefreshPrices: Bool = true
    /// Rente van een spaarrekening, als richtpercentage (bijv. 0,02).
    var savingsRate: Double = 0.02
    /// Wanneer de marktgegevens (inflatie, rente) voor het laatst van internet zijn gehaald.
    var lastMarketUpdate: Date?
    /// Eigen volgorde van de blokken per pagina: "home", "savings", "tools" → lijst met blok-id's.
    /// Een ontbrekende pagina of onbekend blok betekent: standaardvolgorde.
    var blockOrder: [String: [String]] = [:]

    enum CodingKeys: String, CodingKey {
        case inflation, defaultWithdrawalRate, bankBufferMonths, autoRefreshPrices, savingsRate, lastMarketUpdate
        case blockOrder
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        inflation = try c.decodeIfPresent(Double.self, forKey: .inflation) ?? inflation
        defaultWithdrawalRate = try c.decodeIfPresent(Double.self, forKey: .defaultWithdrawalRate) ?? defaultWithdrawalRate
        bankBufferMonths = try c.decodeIfPresent(Double.self, forKey: .bankBufferMonths) ?? bankBufferMonths
        autoRefreshPrices = try c.decodeIfPresent(Bool.self, forKey: .autoRefreshPrices) ?? autoRefreshPrices
        savingsRate = try c.decodeIfPresent(Double.self, forKey: .savingsRate) ?? savingsRate
        lastMarketUpdate = try c.decodeIfPresent(Date.self, forKey: .lastMarketUpdate)
        blockOrder = try c.decodeIfPresent([String: [String]].self, forKey: .blockOrder) ?? [:]
    }
}

/// Een toegepaste versneller, met de oude toestand van alles wat hij aanpaste, zodat je hem kunt herstellen.
struct AppliedAccelerator: Identifiable, Codable, Equatable {
    var id = UUID()
    /// Id van de versneller (`Accelerator.id`) en van het doel waarvoor hij gold.
    var acceleratorID: String
    var goalID: UUID?
    var title: String
    var date: Date
    /// Samenvatting van wat er is aangepast, in gewone woorden (voor in de lijst).
    var summary: [String] = []
    /// Toestand vóór het toepassen van alleen de dingen die zijn aangepast; herstellen zet die terug op id.
    var before = AcceleratorBackup()
}

struct AcceleratorBackup: Codable, Equatable {
    var pots: [Pot] = []
    var holdings: [Holding] = []
    var goals: [LifeGoal] = []
    /// Maandplannen vóór de wijziging, per maandsleutel ("2026-10").
    var plans: [String: MonthPlan] = [:]
    /// Maandsleutels die vóór het toepassen nog niet bestonden (herstellen verwijdert ze weer).
    var newPlanKeys: [String] = []
    var settings: AppSettings?
    var salary: SalarySettings?

    var isEmpty: Bool {
        pots.isEmpty && holdings.isEmpty && goals.isEmpty && plans.isEmpty && newPlanKeys.isEmpty
            && settings == nil && salary == nil
    }
}

struct FinanceData: Codable, Equatable {
    var version: Int = 1
    var startMonth: YearMonth
    var salary = SalarySettings()
    var months: [String: MonthPlan] = [:] {
        // De tussenopslag hoort bij precies deze maandplannen: bij elke wijziging begint een nieuwe, lege opslag. Een kopie
        // van de gegevens deelt de opslag zolang de maandplannen gelijk zijn.
        didSet { derivedPlans = DerivedPlans() }
    }
    /// Tussenopslag van de opgeslagen plannen en reeksen (`StoredPlans`), alleen voor de snelheid. Wordt niet
    /// opgeslagen, telt niet mee bij `==` en wordt leeg zodra `months` verandert.
    var derivedPlans = DerivedPlans()
    var pots: [Pot] = []
    var potEntries: [PotEntry] = []
    var holdings: [Holding] = []
    var bankSnapshots: [BankSnapshot] = []
    var bankEntries: [BankEntry] = []
    var goals: [LifeGoal] = []
    /// Welke spaarpotten op Home staan (nil = de eerste drie).
    var homePotIDs: [UUID]?
    /// Welke beleggingen op Home staan (nil = de eerste vier).
    var homeHoldingIDs: [UUID]?
    var settings = AppSettings()
    /// Versnellers die zijn toegepast en nog hersteld kunnen worden (nieuwste laatst).
    var appliedAccelerators: [AppliedAccelerator] = []
    /// Laatste wijziging; de nieuwste kant wint bij synchroniseren tussen apparaten.
    var modifiedAt: Date?

    init(startMonth: YearMonth) {
        self.startMonth = startMonth
    }

    enum CodingKeys: String, CodingKey {
        case version, startMonth, salary, months, pots, potEntries, holdings
        case bankSnapshots, bankEntries, goals, homePotIDs, homeHoldingIDs, settings
        case appliedAccelerators, modifiedAt
    }
}

// Aparte extension, zodat de gewone init hierboven behouden blijft.
// decodeIfPresent: nieuwe velden in latere versies breken oude opslagbestanden niet.
extension FinanceData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(startMonth: try c.decodeIfPresent(YearMonth.self, forKey: .startMonth) ?? YearMonth.current())
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        salary = try c.decodeIfPresent(SalarySettings.self, forKey: .salary) ?? SalarySettings()
        months = try c.decodeIfPresent([String: MonthPlan].self, forKey: .months) ?? [:]
        pots = try c.decodeIfPresent([Pot].self, forKey: .pots) ?? []
        potEntries = try c.decodeIfPresent([PotEntry].self, forKey: .potEntries) ?? []
        holdings = try c.decodeIfPresent([Holding].self, forKey: .holdings) ?? []
        bankSnapshots = try c.decodeIfPresent([BankSnapshot].self, forKey: .bankSnapshots) ?? []
        bankEntries = try c.decodeIfPresent([BankEntry].self, forKey: .bankEntries) ?? []
        goals = try c.decodeIfPresent([LifeGoal].self, forKey: .goals) ?? []
        homePotIDs = try c.decodeIfPresent([UUID].self, forKey: .homePotIDs)
        homeHoldingIDs = try c.decodeIfPresent([UUID].self, forKey: .homeHoldingIDs)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        appliedAccelerators = try c.decodeIfPresent([AppliedAccelerator].self, forKey: .appliedAccelerators) ?? []
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }
}
