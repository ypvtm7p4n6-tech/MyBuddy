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

/// Vaste lasten (huur, verzekeringen) of variabele uitgaven (boodschappen, uit eten).
enum ExpenseKind: String, Codable, CaseIterable, Identifiable {
    case fixed, variable
    var id: String { rawValue }
    var title: String { self == .fixed ? "Vast" : "Variabel" }
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

    enum CodingKeys: String, CodingKey { case id, name, amount, isRecurring, kind }
}

// decodeIfPresent: oude opslagbestanden zonder `kind` blijven laden.
extension MoneyLine {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  amount: try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0,
                  isRecurring: try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false,
                  kind: try c.decodeIfPresent(ExpenseKind.self, forKey: .kind) ?? .fixed)
    }
}

extension Array where Element == MoneyLine {
    var total: Double { reduce(0) { $0 + $1.amount }.cents }
    func total(of kind: ExpenseKind) -> Double { filter { $0.kind == kind }.total }
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
}

// MARK: - Spaarpotten

enum PotEntryKind: String, Codable {
    case opening, deposit, withdrawal, adjustment, transferIn, transferOut

    var title: String {
        switch self {
        case .opening: return "Beginsaldo"
        case .deposit: return "Gestort"
        case .withdrawal: return "Opgenomen"
        case .adjustment: return "Saldo aangepast"
        case .transferIn: return "Overgeboekt naar deze pot"
        case .transferOut: return "Overgeboekt naar andere pot"
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
}

struct PotEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var potID: UUID
    var date: Date
    /// Positief = erbij, negatief = eraf.
    var amount: Double
    var kind: PotEntryKind
    var note: String = ""
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
    var snapshots: [ValueSnapshot] = []
    var lastPrice: Double?
    var lastPriceDate: Date?
    var priceCurrency: String?

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

    enum CodingKeys: String, CodingKey {
        case inflation, defaultWithdrawalRate, bankBufferMonths, autoRefreshPrices, savingsRate, lastMarketUpdate
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
    }
}

struct FinanceData: Codable, Equatable {
    var version: Int = 1
    var startMonth: YearMonth
    var salary = SalarySettings()
    var months: [String: MonthPlan] = [:]
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

    init(startMonth: YearMonth) {
        self.startMonth = startMonth
    }

    enum CodingKeys: String, CodingKey {
        case version, startMonth, salary, months, pots, potEntries, holdings
        case bankSnapshots, bankEntries, goals, homePotIDs, homeHoldingIDs, settings
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
    }
}
