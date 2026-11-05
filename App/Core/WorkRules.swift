import Foundation

// MARK: - Toeslagen, pauzes en feestdagen
//
// De regels waarmee de uren uit de agenda worden uitgerekend (docs/work/plan.md B13 en B14): een factor op het uurloon voor een
// soort dag (zondag 1,5, feestdag 2,0), een onbetaalde pauze naar de duur van een dienst en de Nederlandse feestdagen, uitgerekend
// en met een schakelaar per soort. Foundation-only. Alles wordt mild gelezen (een onleesbare regel wordt overgeslagen) en alleen
// geschreven als het afwijkt van de standaard: een bestand zonder werkuren blijft byte voor byte gelijk.

extension CalendarDay {
    /// 1 = zondag ... 7 = zaterdag (zoals `Calendar.weekday`). 1970-01-01 was een donderdag.
    var weekday: Int { ((dayNumber % 7) + 7 + 4) % 7 + 1 }
}

/// Waar een toeslag voor geldt.
enum PayRuleKind: Hashable, Sendable {
    /// Een dag van de week (1 = zondag ... 7 = zaterdag).
    case weekday(Int)
    /// Elke feestdag uit `HolidaySettings` (de standaard feestdagen, de aangezette extra dagen en de eigen feestdagen).
    case holiday
    /// Eén bepaalde datum.
    case date(CalendarDay)
}

extension PayRuleKind: Codable {
    // "weekday:1", "holiday", "date:2026-12-05": leesbaar en makkelijk mild te lezen.
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        if text == "holiday" {
            self = .holiday
        } else if text.hasPrefix("weekday:"), let n = Int(text.dropFirst(8)), (1...7).contains(n) {
            self = .weekday(n)
        } else if text.hasPrefix("date:"), let day = CalendarDay(key: String(text.dropFirst(5))) {
            self = .date(day)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Onbekende toeslag: \(text)"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .holiday: try c.encode("holiday")
        case .weekday(let n): try c.encode("weekday:\(n)")
        case .date(let day): try c.encode("date:\(day.key)")
        }
    }
}

/// Een toeslag: een factor op het uurloon voor een soort dag. 1,5 = anderhalf keer het uurloon.
struct PayRule: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var kind: PayRuleKind
    /// 0...10, op honderdsten gerekend.
    var factor: Double
    var isEnabled: Bool

    init(id: UUID = UUID(), kind: PayRuleKind, factor: Double, isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.factor = factor
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey { case id, kind, factor, isEnabled }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = try c.decode(PayRuleKind.self, forKey: .kind)
        let raw = (try? c.decodeIfPresent(Double.self, forKey: .factor)) ?? 1
        factor = raw.isFinite ? min(max(raw, 0), 10) : 1
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(factor.isFinite ? factor : 1, forKey: .factor)
        if !isEnabled { try c.encode(false, forKey: .isEnabled) }
    }

    /// De factor in honderdsten (1,5 is 150), begrensd op 0...1000.
    var factorHundredths: Int {
        guard factor.isFinite else { return 100 }
        return Int((min(max(factor, 0), 10) * 100).rounded())
    }
}

/// Onbetaalde pauze: vanaf zoveel uur dienst gaan er zoveel minuten af.
struct BreakRule: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    /// Een dienst van minstens zoveel uur (5,5 = 5 uur 30).
    var fromHours: Double
    /// Onbetaalde minuten.
    var minutes: Int

    init(id: UUID = UUID(), fromHours: Double, minutes: Int) {
        self.id = id
        self.fromHours = fromHours
        self.minutes = minutes
    }

    enum CodingKeys: String, CodingKey { case id, fromHours, minutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        let hours = (try? c.decodeIfPresent(Double.self, forKey: .fromHours)) ?? 0
        fromHours = hours.isFinite ? min(max(hours, 0), 24) : 0
        minutes = min(max((try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 0, 0), 600)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(fromHours.isFinite ? fromHours : 0, forKey: .fromHours)
        try c.encode(minutes, forKey: .minutes)
    }

    /// De grens in hele minuten.
    var thresholdMinutes: Int {
        guard fromHours.isFinite else { return 0 }
        return Int((min(max(fromHours, 0), 24) * 60).rounded())
    }
}

/// Meer toeslagen op dezelfde dag (bijvoorbeeld een zondag die ook een feestdag is).
enum PayCombine: String, Codable, CaseIterable, Identifiable, Sendable {
    /// De hoogste factor telt (standaard).
    case highest
    /// De toeslagen worden bij elkaar opgeteld: zondag 1,5 en feestdag 2,0 geven 2,5 (1 + 0,5 + 1,0).
    case add

    var id: String { rawValue }
}

/// Een feestdag die aan of uit kan. De eerste negen staan standaard aan; de laatste drie zijn optioneel.
enum HolidayKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case newYear, easterSunday, easterMonday, kingsDay, ascension, pentecostSunday, pentecostMonday, christmas, boxingDay
    case goodFriday, liberationDay, newYearsEve

    var id: String { rawValue }

    /// De negen die standaard aanstaan (Nieuwjaarsdag, Eerste en Tweede Paasdag, Koningsdag, Hemelvaartsdag, Eerste en Tweede
    /// Pinksterdag, Eerste en Tweede Kerstdag).
    static let standard: Set<HolidayKind> = [.newYear, .easterSunday, .easterMonday, .kingsDay, .ascension, .pentecostSunday,
                                             .pentecostMonday, .christmas, .boxingDay]

    /// Alle twaalf in kalendervolgorde van een gewoon jaar, voor de lijsten op het scherm.
    static let calendarOrder: [HolidayKind] = [.newYear, .goodFriday, .easterSunday, .easterMonday, .kingsDay, .liberationDay,
                                               .ascension, .pentecostSunday, .pentecostMonday, .christmas, .boxingDay, .newYearsEve]

    var title: String {
        switch self {
        case .newYear: return "Nieuwjaarsdag"
        case .goodFriday: return "Goede Vrijdag"
        case .easterSunday: return "Eerste Paasdag"
        case .easterMonday: return "Tweede Paasdag"
        case .kingsDay: return "Koningsdag"
        case .liberationDay: return "Bevrijdingsdag"
        case .ascension: return "Hemelvaartsdag"
        case .pentecostSunday: return "Eerste Pinksterdag"
        case .pentecostMonday: return "Tweede Pinksterdag"
        case .christmas: return "Eerste Kerstdag"
        case .boxingDay: return "Tweede Kerstdag"
        case .newYearsEve: return "Oudejaarsdag"
        }
    }
}

/// Welke feestdagen meetellen: de aangezette soorten en eigen datums.
struct HolidaySettings: Codable, Equatable, Sendable {
    var enabled: Set<HolidayKind> = HolidayKind.standard
    var custom: [CalendarDay] = []

    init() {}

    enum CodingKeys: String, CodingKey { case enabled, custom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decodeIfPresent(LossyArray<HolidayKind>.self, forKey: .enabled) { enabled = Set(list.elements) }
        custom = ((try? c.decodeIfPresent(LossyArray<CalendarDay>.self, forKey: .custom))?.elements ?? []).sorted()
    }

    /// Alleen wat afwijkt: een gewone lijst (de negen standaard) en geen eigen dagen schrijven niets.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if enabled != HolidayKind.standard { try c.encode(enabled.map { $0.rawValue }.sorted(), forKey: .enabled) }
        if !custom.isEmpty { try c.encode(custom, forKey: .custom) }
    }
}

/// Alle regels voor het uitrekenen van uren uit de agenda.
struct WorkRules: Codable, Equatable, Sendable {
    var payRules: [PayRule] = WorkRules.defaultPayRules
    var breakRules: [BreakRule] = WorkRules.defaultBreakRules
    var combine: PayCombine = .highest
    var holidays = HolidaySettings()

    init() {}

    /// Zondag 1,5 en feestdag 2,0, met vaste id's (twee nieuwe `WorkRules()` zijn gelijk).
    static let defaultPayRules: [PayRule] = [
        PayRule(id: StableID.uuid("payrule|sunday"), kind: .weekday(1), factor: 1.5),
        PayRule(id: StableID.uuid("payrule|holiday"), kind: .holiday, factor: 2.0)
    ]

    /// Vanaf 5,5 uur 30 minuten pauze.
    static let defaultBreakRules: [BreakRule] = [
        BreakRule(id: StableID.uuid("breakrule|5.5"), fromHours: 5.5, minutes: 30)
    ]

    enum CodingKeys: String, CodingKey { case payRules, breakRules, combine, holidays }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decodeIfPresent(LossyArray<PayRule>.self, forKey: .payRules) { payRules = list.elements }
        if let list = try? c.decodeIfPresent(LossyArray<BreakRule>.self, forKey: .breakRules) { breakRules = list.elements }
        combine = (try? c.decodeIfPresent(PayCombine.self, forKey: .combine)) ?? .highest
        holidays = (try? c.decodeIfPresent(HolidaySettings.self, forKey: .holidays)) ?? HolidaySettings()
    }

    /// Alleen de afwijkingen van de standaard.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if payRules != WorkRules.defaultPayRules { try c.encode(payRules, forKey: .payRules) }
        if breakRules != WorkRules.defaultBreakRules { try c.encode(breakRules, forKey: .breakRules) }
        if combine != .highest { try c.encode(combine, forKey: .combine) }
        if holidays != HolidaySettings() { try c.encode(holidays, forKey: .holidays) }
    }
}

extension WorkRules {
    /// De onbetaalde pauze voor een dienst van `minutes` minuten: de regel met de hoogste grens die niet boven de dienst ligt (de
    /// grens telt mee: 5 uur 30 krijgt 30 minuten, 5 uur 29 niets). Nooit meer dan de dienst zelf.
    func breakMinutes(forShiftMinutes minutes: Int) -> Int {
        var best: BreakRule?
        for rule in breakRules where rule.thresholdMinutes <= minutes {
            if best == nil || rule.thresholdMinutes >= best!.thresholdMinutes { best = rule }
        }
        return min(max(best?.minutes ?? 0, 0), max(minutes, 0))
    }

    /// De factor van een dag in honderdsten (150 = 1,5): `.highest` pakt de hoogste van de toeslagen die voor die dag gelden (zonder
    /// toeslag 100), `.add` telt de toeslagen boven of onder 1,0 bij elkaar op (nooit onder 0). Een uitgezette toeslag telt niet.
    func factorHundredths(on day: CalendarDay) -> Int {
        var matching: [Int] = []
        var holiday: Bool?
        for rule in payRules where rule.isEnabled {
            switch rule.kind {
            case .weekday(let n):
                if day.weekday == n { matching.append(rule.factorHundredths) }
            case .holiday:
                if holiday == nil { holiday = DutchHolidays.isHoliday(day, settings: holidays) }
                if holiday == true { matching.append(rule.factorHundredths) }
            case .date(let date):
                if date == day { matching.append(rule.factorHundredths) }
            }
        }
        guard !matching.isEmpty else { return 100 }
        switch combine {
        case .highest: return matching.max() ?? 100
        case .add: return max(0, 100 + matching.reduce(0) { $0 + ($1 - 100) })
        }
    }
}

// MARK: - Feestdagen

/// De Nederlandse feestdagen, uitgerekend (geen tabel): Pasen volgens het Meeus/Jones/Butcher-algoritme (de Gregoriaanse vorm van
/// Gauss), de rest als verschil in dagen. Geldig vanaf 1583.
enum DutchHolidays {
    struct Holiday: Equatable {
        var name: String
        var day: CalendarDay
    }

    /// Eerste Paasdag.
    static func easter(year: Int) -> CalendarDay {
        let a = year % 19
        let b = year / 100, c = year % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return CalendarDay(year: year, month: month, day: day)
    }

    /// Koningsdag: 27 april, of 26 april als dat een zondag is (vanaf 2014). Daarvoor Koninginnedag: 30 april, of 29 april als dat een
    /// zondag is.
    static func kingsDay(year: Int) -> CalendarDay {
        let base = CalendarDay(year: year, month: 4, day: year >= 2014 ? 27 : 30)
        return base.weekday == 1 ? base.adding(days: -1) : base
    }

    /// De datum van een feestdag in `year`.
    static func day(of kind: HolidayKind, year: Int) -> CalendarDay {
        let easter = easter(year: year)
        switch kind {
        case .newYear: return CalendarDay(year: year, month: 1, day: 1)
        case .goodFriday: return easter.adding(days: -2)
        case .easterSunday: return easter
        case .easterMonday: return easter.adding(days: 1)
        case .kingsDay: return kingsDay(year: year)
        case .liberationDay: return CalendarDay(year: year, month: 5, day: 5)
        case .ascension: return easter.adding(days: 39)
        case .pentecostSunday: return easter.adding(days: 49)
        case .pentecostMonday: return easter.adding(days: 50)
        case .christmas: return CalendarDay(year: year, month: 12, day: 25)
        case .boxingDay: return CalendarDay(year: year, month: 12, day: 26)
        case .newYearsEve: return CalendarDay(year: year, month: 12, day: 31)
        }
    }

    /// De feestdagen van een jaar, oplopend: de aangezette soorten en de eigen feestdagen van dat jaar.
    static func holidays(year: Int, settings: HolidaySettings = HolidaySettings()) -> [Holiday] {
        var list: [Holiday] = []
        for kind in HolidayKind.allCases where settings.enabled.contains(kind) {
            let name = kind == .kingsDay && year < 2014 ? "Koninginnedag" : kind.title
            list.append(Holiday(name: name, day: day(of: kind, year: year)))
        }
        for day in settings.custom where day.year == year { list.append(Holiday(name: "Eigen feestdag", day: day)) }
        return list.sorted { $0.day < $1.day }
    }

    /// Is `day` een feestdag? Zonder de lijst van het jaar op te bouwen (dit wordt voor elke dag van elke dienst gevraagd): vaste
    /// datums plus `dag − Pasen` in {−2, 0, 1, 39, 49, 50}.
    static func isHoliday(_ day: CalendarDay, settings: HolidaySettings = HolidaySettings()) -> Bool {
        if settings.custom.contains(day) { return true }
        func on(_ kind: HolidayKind) -> Bool { settings.enabled.contains(kind) }
        switch (day.month, day.day) {
        case (1, 1): return on(.newYear)
        case (12, 25): return on(.christmas)
        case (12, 26): return on(.boxingDay)
        case (12, 31): return on(.newYearsEve)
        case (5, 5): if on(.liberationDay) { return true }
        case (4, 26), (4, 27), (4, 29), (4, 30): if on(.kingsDay), day == kingsDay(year: day.year) { return true }
        default: break
        }
        // Rond Pasen (alleen maart ... juni kan een verschuiving van Pasen vallen).
        guard (3...6).contains(day.month) else { return false }
        switch day.dayNumber - easter(year: day.year).dayNumber {
        case -2: return on(.goodFriday)
        case 0: return on(.easterSunday)
        case 1: return on(.easterMonday)
        case 39: return on(.ascension)
        case 49: return on(.pentecostSunday)
        case 50: return on(.pentecostMonday)
        default: return false
        }
    }
}
