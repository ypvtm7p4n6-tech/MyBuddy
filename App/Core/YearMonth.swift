import Foundation

/// Een kalendermaand (bijv. oktober 2026). Wordt overal gebruikt als "periode".
struct YearMonth: Hashable, Comparable, Codable {
    let year: Int
    let month: Int // 1...12

    init(index: Int) {
        self.year = index / 12
        self.month = index % 12 + 1
    }

    init(year: Int, month: Int) {
        self.init(index: year * 12 + (month - 1))
    }

    init(date: Date, calendar: Calendar = YearMonth.calendar) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1)
    }

    static func current(now: Date = Date()) -> YearMonth {
        YearMonth(date: now)
    }

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    /// Doorlopend maandnummer: handig voor rekenen en vergelijken.
    var index: Int { year * 12 + (month - 1) }

    func adding(_ months: Int) -> YearMonth { YearMonth(index: index + months) }

    /// Aantal maanden van deze maand naar `other` (negatief als `other` eerder is).
    func months(to other: YearMonth) -> Int { other.index - index }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool { lhs.index < rhs.index }

    /// Sleutel zoals "2026-10", gebruikt voor opslag.
    var key: String {
        let m = month < 10 ? "0\(month)" : "\(month)"
        var y = "\(year)"
        while y.count < 4 { y = "0" + y }
        return "\(y)-\(m)"
    }

    init?(key: String) {
        let parts = key.split(separator: "-")
        // Jaren buiten 0...9999 komen alleen uit onleesbare of kwaadwillige bestanden; `year * 12` zou daarop crashen.
        guard parts.count == 2, let y = Int(parts[0]), (0...9_999).contains(y),
              let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        self.init(year: y, month: m)
    }

    var firstDay: Date {
        let comps = DateComponents(year: year, month: month, day: 1, hour: 0, minute: 0, second: 0)
        return YearMonth.calendar.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// Eerste moment van de volgende maand (exclusief grens).
    var endExclusive: Date { adding(1).firstDay }

    /// Midden van de maand, handig als punt op een grafiek.
    var midDate: Date { firstDay.addingTimeInterval(14 * 86_400) }

    func contains(_ date: Date) -> Bool { date >= firstDay && date < endExclusive }

    /// 1 voor januari-juni, 2 voor juli-december.
    var half: Int { month <= 6 ? 1 : 2 }

    var halfYearStart: YearMonth { YearMonth(year: year, month: half == 1 ? 1 : 7) }
    var yearStart: YearMonth { YearMonth(year: year, month: 1) }

    /// De maanden `self ... self+count-1`.
    func range(count: Int) -> [YearMonth] {
        guard count > 0 else { return [] }
        return (0..<count).map { adding($0) }
    }

    // Codable als "2026-10", zodat het ook als dictionary-waarde leesbaar blijft.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = YearMonth(key: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ongeldige maand: \(text)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// Periode waarover je cijfers bekijkt.
enum PeriodMode: String, CaseIterable, Codable, Identifiable {
    case month, halfYear, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Maand"
        case .halfYear: return "Half jaar"
        case .year: return "Jaar"
        }
    }

    /// Alle maanden van de periode waar `focus` in valt.
    func months(containing focus: YearMonth) -> [YearMonth] {
        switch self {
        case .month: return [focus]
        case .halfYear: return focus.halfYearStart.range(count: 6)
        case .year: return focus.yearStart.range(count: 12)
        }
    }

    /// Hoeveel maanden "volgende/vorige" opschuift.
    var stepMonths: Int {
        switch self {
        case .month: return 1
        case .halfYear: return 6
        case .year: return 12
        }
    }
}

// MARK: - Dagen in de maand

extension YearMonth {
    /// Aantal dagen in de maand (28...31).
    var dayCount: Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    /// De gekozen dag van deze maand om 12:00 lokale tijd. De dag wordt geklemd op 1...`dayCount`,
    /// dus dag 31 in februari is de laatste dag van februari.
    func date(day: Int) -> Date {
        date(day: day, calendar: YearMonth.calendar)
    }

    /// Zoals `date(day:)`, maar met een kalender die je zelf meegeeft (sneller in lussen).
    func date(day: Int, calendar: Calendar) -> Date {
        let d = min(max(day, 1), dayCount)
        let comps = DateComponents(year: year, month: month, day: d, hour: 12, minute: 0, second: 0)
        return calendar.date(from: comps)
            ?? firstDay.addingTimeInterval(Double(d - 1) * 86_400 + 12 * 3_600)
    }

    /// Een ingevulde dag begrenzen op 1...31 (de lengte van de maand wordt pas bij het plaatsen toegepast).
    static func clampedDay(_ day: Int) -> Int {
        min(max(day, 1), 31)
    }
}

/// Kleine hulpjes om op dagniveau te rekenen. Intern voor de rekenmotor.
enum DayMath {
    /// Begin van de dag na `date`. Dit is de (exclusieve) bovengrens voor "t/m die dag".
    static func nextDayStart(after date: Date, calendar: Calendar = YearMonth.calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Dag van de maand (1...31) van een datum.
    static func dayNumber(of date: Date, calendar: Calendar = YearMonth.calendar) -> Int {
        calendar.component(.day, from: date)
    }

    /// Exclusieve bovengrens voor "alles t/m dit moment": de kleinste datum die net na `moment` ligt.
    /// Een boeking op exact `moment` telt mee, een boeking een fractie later niet. Zo is "nu" precies het
    /// omgekeerde van `DayEvent.isPlanned` (gepland = datum na `moment`).
    static func limit(including moment: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: moment.timeIntervalSinceReferenceDate.nextUp)
    }

    /// Het laatste moment vóór een exclusieve bovengrens (omgekeerde van `limit(including:)`).
    static func lastMoment(before limit: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: limit.timeIntervalSinceReferenceDate.nextDown)
    }
}
