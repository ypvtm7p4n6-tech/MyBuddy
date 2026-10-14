import Foundation

// MARK: - Het salarisschema
//
// Het salaris komt binnen volgens een schema (`SalarySettings.schedule`):
//
//   - maandelijks op dag X (`payDay`): zoals altijd, de standaard; oude bestanden blijven exact hetzelfde rekenen;
//   - elke N weken (N = 1...52), vanaf een bekende uitbetaaldatum (`SalarySettings.anchor`);
//   - elke N dagen (N = 1...366), vanaf een bekende uitbetaaldatum.
//
// Rekenregels, op één plek vastgelegd:
//
// 1. UITBETALINGEN vallen op hun eigen dag. In een maand vallen er dus 0, 1, 2 of meer. Elke uitbetaling is een eigen
//    `DayEvent` met een stabiel id per datum (`salary-2026-10-23`; bij het maandelijkse schema `salary-2026-10`, zoals
//    altijd). Uitbetalingen vallen nooit vóór de startmaand van de gegevens (ook niet als de cyclus daar al liep).
// 2. BEDRAG per uitbetaling: vast = `fixedMonthly` ("per uitbetaling"); uurloon = uurloon × uren per week × weken per
//    cyclus (N weken, of N / 7 weken bij dagen), afgerond op hele centen PER UITBETALING. Het maandsalaris is de SOM van de
//    afgeronde bedragen van de uitbetalingen in die maand, en dat totaal voedt `income(in:)`, `remaining`, het overzicht,
//    de projectie en de dagboekhouding precies hetzelfde (`salaryCents(in:plan:)` is de enige bron).
// 3. OVERSCHRIJVINGEN per maand (`MonthPlan.salaryOverride` en `hoursOverride`) gelden voor het TOTAAL van de maand en
//    worden gelijk over de uitbetalingen van die maand verdeeld, in hele centen; de restcenten gaan naar de eerste
//    uitbetalingen. Bij het maandelijkse schema is er één uitbetaling, dus het is gewoon dat bedrag. Valt er in de maand
//    geen uitbetaling, dan komt een overschreven salaris (dat de gebruiker er dan zelf neerzet) op de salarisdag-terugval
//    binnen (`payDay`); uren zonder uitbetaling betalen niets.
// 4. "DE SALARISDAG" voor wat geen eigen dag heeft (extra inkomsten, overschrijfdagen): de EERSTE uitbetaling van de maand,
//    en als die er niet is (of bij het maandelijkse schema) de `payDay`-terugval. Zie `salaryDay(in:)`.
// 5. GEMIDDELDE per maand, voor SCHATTINGEN (toekomstschatting, aankoopcheck, versnellers, buffer, doelen): bedrag per
//    uitbetaling × 365,25 / 12 / dagen per cyclus (`averageMonthlyAmount`). Het maandelijkse schema blijft op
//    maandbedrag en op 52 / 12 weken (zoals altijd). Een BEPAALDE maand gebruikt nooit het gemiddelde: die gebruikt de som
//    van zijn uitbetalingen. Het verschil heet in de code steeds "gemiddeld" of "geschat" (`estimated...`).

// MARK: - Kalenderdagen

/// Een dag in de kalender (jaar, maand, dag), zonder tijdstip en zonder tijdzone. Een uitbetaaldatum is een dag, geen
/// moment: zo verschuift hij nooit door een tijdzone of de zomertijd. Opgeslagen als "2026-10-23".
struct CalendarDay: Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int

    /// Een dag; maand en dag worden geklemd (31 februari is de laatste dag van februari), het jaar op 0...9999.
    init(year: Int, month: Int, day: Int) {
        let y = min(max(year, 0), 9_999)
        let m = min(max(month, 1), 12)
        self.year = y
        self.month = m
        self.day = min(max(day, 1), YearMonth(year: y, month: m).dayCount)
    }

    init(month: YearMonth, day: Int) {
        self.init(year: month.year, month: month.month, day: day)
    }

    /// De dag waarop `date` valt in de kalender van de gebruiker.
    init(date: Date, calendar: Calendar = YearMonth.calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// De dag met dit volgnummer (zie `dayNumber`), begrensd op 0000-01-01 ... 9999-12-31.
    init(dayNumber: Int) {
        let number = min(max(dayNumber, CalendarDay.firstNumber), CalendarDay.lastNumber)
        let civil = CivilDays.civil(from: number)
        self.init(year: civil.year, month: civil.month, day: civil.day)
    }

    /// "2026-10-23".
    init?(key: String) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (0...9_999).contains(y), (1...12).contains(m),
              (1...YearMonth(year: y, month: m).dayCount).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    private static let firstNumber = CivilDays.number(year: 0, month: 1, day: 1)
    private static let lastNumber = CivilDays.number(year: 9_999, month: 12, day: 31)

    /// Aantal dagen sinds 1 januari 1970 (negatief ervoor). Rekenen met dagen is hiermee gewoon optellen en aftrekken,
    /// zonder tijdzone of zomertijd.
    var dayNumber: Int { CivilDays.number(year: year, month: month, day: day) }

    var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    /// "2026-10-23".
    var key: String {
        let y = year < 10 ? "000\(year)" : year < 100 ? "00\(year)" : year < 1_000 ? "0\(year)" : "\(year)"
        return "\(y)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
    }

    /// Deze dag om 12:00 lokale tijd (zoals `YearMonth.date(day:)`).
    func date(calendar: Calendar = YearMonth.calendar) -> Date {
        yearMonth.date(day: day, calendar: calendar)
    }

    func adding(days: Int) -> CalendarDay { CalendarDay(dayNumber: dayNumber + days) }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool { lhs.dayNumber < rhs.dayNumber }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = CalendarDay(key: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ongeldige dag: \(text)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// Rekenen met dagnummers in de gregoriaanse kalender (zonder `Calendar`: snel en onafhankelijk van tijdzone).
enum CivilDays {
    /// Deling naar beneden (ook voor negatieve getallen). `b` is positief.
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }

    /// Deling naar boven (ook voor negatieve getallen). `b` is positief.
    static func ceilDiv(_ a: Int, _ b: Int) -> Int {
        -floorDiv(-a, b)
    }

    /// Dagen sinds 1970-01-01 van een datum.
    static func number(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = floorDiv(y, 400)
        let yearOfEra = y - era * 400
        let shifted = (month + 9) % 12           // maart = 0 ... februari = 11
        let dayOfYear = (153 * shifted + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// De datum bij een aantal dagen sinds 1970-01-01.
    static func civil(from number: Int) -> (year: Int, month: Int, day: Int) {
        let z = number + 719_468
        let era = floorDiv(z, 146_097)
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shifted = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shifted + 2) / 5 + 1
        let month = shifted < 10 ? shifted + 3 : shifted - 9
        let year = yearOfEra + era * 400
        return (month <= 2 ? year + 1 : year, month, day)
    }
}

extension YearMonth {
    /// Dagnummer (zie `CalendarDay.dayNumber`) van de eerste dag van deze maand. Een jaar buiten 0...9999 (komt alleen uit
    /// onleesbare bestanden) wordt begrensd, zodat het rekenen met dagnummers nooit overloopt.
    var firstDayNumber: Int { CivilDays.number(year: min(max(year, 0), 9_999), month: month, day: 1) }
}

// MARK: - Het schema zelf (zonder gegevens)

extension SalarySettings {
    var isMonthly: Bool { schedule == .monthly }

    /// Om de hoeveel weken of dagen, geklemd op 1...52 (weken) of 1...366 (dagen). Bij maandelijks 1.
    var cycleInterval: Int {
        switch schedule {
        case .monthly: return 1
        case .weeks: return min(max(interval, 1), 52)
        case .days: return min(max(interval, 1), 366)
        }
    }

    /// Lengte van één cyclus in dagen; nil bij het maandelijkse schema (een maand heeft geen vaste lengte).
    var cycleDays: Int? {
        switch schedule {
        case .monthly: return nil
        case .weeks: return cycleInterval * 7
        case .days: return cycleInterval
        }
    }

    /// Een aantal uitbetalingen per jaar, gemiddeld (12 bij maandelijks; om de 4 weken 365,25 / 28 = 13,04).
    var averagePayoutsPerYear: Double {
        guard let days = cycleDays else { return 12 }
        return 365.25 / Double(days)
    }

    // MARK: Bedragen

    /// Het gemiddelde per maand van een bedrag per WEEK, voor schattingen: 52 / 12 weken bij het maandelijkse schema (zoals
    /// altijd), anders 365,25 / 7 / 12 (= 4,348) weken. Dit is een gemiddelde: een bepaalde maand heeft er 4, 5 of
    /// (met een cyclus om de zoveel weken) soms meer of minder.
    func averageMonthly(perWeek amount: Double) -> Double {
        isMonthly ? amount * 52 / 12 : amount * 365.25 / 7 / 12
    }

    /// Uren die één cyclus betaalt: gemiddeld per maand (maandelijks), N weken × uren per week, of N / 7 weken.
    var hoursPerCycle: Double {
        switch schedule {
        case .monthly: return defaultMonthlyHours
        case .weeks: return hoursPerWeek * Double(cycleInterval)
        case .days: return hoursPerWeek * Double(cycleInterval) / 7
        }
    }

    /// Uurloon × uren, op hele centen (half omhoog), exact in decimalen: uurloon en uren worden gerekend zoals de gebruiker
    /// ze typte (55,94 × 10,75 × 3 is 1804,065 en dus 1804,07, niet 1804,06 doordat de kommagetallen in de computer net onder
    /// de helft uitkomen). `multiplier` en `divisor` zijn gehele getallen (het aantal weken, en 7 bij een cyclus in dagen).
    /// Bij onleesbare of absurde getallen valt het terug op gewoon rekenen met afronden. Alleen voor een salaris om de zoveel
    /// weken of dagen: het maandelijkse schema rekent zoals het altijd deed.
    static func exactHourlyPay(rate: Double, hours: Double, multiplier: Int = 1, divisor: Int = 1) -> Double {
        func decimal(_ value: Double) -> Decimal? {
            guard value.isFinite else { return nil }
            let text = "\(value)"
            guard !text.contains("e"), !text.contains("E") else { return nil }
            return Decimal(string: text)
        }
        if divisor > 0, let r = decimal(rate), let h = decimal(hours), abs(rate) < 1e6, abs(hours) < 1e6 {
            var exact = r * h * Decimal(multiplier)
            if divisor != 1 { exact = exact / Decimal(divisor) }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &exact, 2, .plain)
            // Via hele centen naar een Double: `NSDecimalNumber.doubleValue` geeft op sommige platforms 1804,0700000000002.
            let cents = NSDecimalNumber(decimal: rounded * 100).int64Value
            return Double(cents) / 100
        }
        return (rate * hours * Double(multiplier) / Double(max(divisor, 1))).cents
    }

    /// Wat één uitbetaling oplevert, in euro's op hele centen, zonder overschrijving van een maand. Vast: het bedrag
    /// "per uitbetaling". Uurloon: uurloon × uren van één cyclus.
    func payoutAmount() -> Double {
        switch mode {
        case .fixed: return fixedMonthly.cents
        case .hourly:
            switch schedule {
            case .monthly: return (hourlyRate * hoursPerCycle).cents
            case .weeks: return Self.exactHourlyPay(rate: hourlyRate, hours: hoursPerWeek, multiplier: cycleInterval)
            case .days: return Self.exactHourlyPay(rate: hourlyRate, hours: hoursPerWeek, multiplier: cycleInterval, divisor: 7)
            }
        }
    }

    /// Het GEMIDDELDE salaris per maand, voor schattingen (zie het begin van dit bestand): bij het maandelijkse schema het
    /// maandsalaris (zoals altijd); anders het bedrag per uitbetaling × 365,25 / 12 / dagen per cyclus. Bij uurloon met
    /// `hoursOverride` (uren van een maand) is het uurloon × die uren.
    func averageMonthlyAmount(hoursOverride: Double? = nil) -> Double {
        guard let days = cycleDays else {
            switch mode {
            case .fixed: return fixedMonthly.cents
            case .hourly: return (hourlyRate * (hoursOverride ?? defaultMonthlyHours)).cents
            }
        }
        if mode == .hourly, let hours = hoursOverride { return (hourlyRate * hours).cents }
        return (payoutAmount() * 365.25 / 12 / Double(days)).cents
    }

    /// Zoals `averageMonthlyAmount` voor een vast bedrag, maar niet op centen afgerond (voor tussenstappen in berekeningen).
    var averageMonthlyFixedAmount: Double {
        guard let days = cycleDays else { return fixedMonthly }
        return fixedMonthly * 365.25 / 12 / Double(days)
    }

    // MARK: Datums

    /// De dagen van `month` waarop het salaris binnenkomt volgens het schema, oplopend (zonder overschrijvingen en zonder
    /// rekening te houden met de startmaand van de gegevens). `anchor` is een bekende uitbetaaldatum.
    /// Maandelijks: één dag (`payDay`, in een korte maand de laatste dag). Anders: elke `cycleDays` dagen voor en na `anchor`.
    func payDays(in month: YearMonth, anchor: CalendarDay) -> [Int] {
        guard let cycle = cycleDays else {
            return [min(YearMonth.clampedDay(payDay), month.dayCount)]
        }
        guard (0...9_999).contains(month.year) else { return [] }
        let first = month.firstDayNumber
        let last = first + month.dayCount - 1
        let origin = anchor.dayNumber
        var number = origin + CivilDays.ceilDiv(first - origin, cycle) * cycle
        var days: [Int] = []
        while number <= last {
            days.append(number - first + 1)
            number += cycle
        }
        return days
    }

    /// De eerste uitbetaling op of na `from` (een dag) en niet vóór de maand `first`.
    func nextPayDay(onOrAfter from: CalendarDay, notBefore first: YearMonth, anchor: CalendarDay) -> CalendarDay {
        let floor = max(from.dayNumber, first.firstDayNumber)
        guard let cycle = cycleDays else {
            var month = CalendarDay(dayNumber: floor).yearMonth
            for _ in 0..<3 {
                let candidate = CalendarDay(month: month, day: YearMonth.clampedDay(payDay))
                if candidate.dayNumber >= floor { return candidate }
                month = month.adding(1)
            }
            return CalendarDay(dayNumber: floor)
        }
        let origin = anchor.dayNumber
        return CalendarDay(dayNumber: origin + CivilDays.ceilDiv(floor - origin, cycle) * cycle)
    }

    // MARK: Omschrijving

    /// Korte omschrijving van het schema: "elke maand op de 25e", "elke week", "elke 4 weken", "elke dag", "elke 10 dagen".
    var cycleDescription: String {
        let n = cycleInterval
        switch schedule {
        case .monthly:
            let day = YearMonth.clampedDay(payDay)
            return day >= 31 ? "elke maand op de laatste dag" : "elke maand op de \(day)e"
        case .weeks:
            return n == 1 ? "elke week" : "elke \(n) weken"
        case .days:
            return n == 1 ? "elke dag" : "elke \(n) dagen"
        }
    }

    /// De ankerdatum als `Date` (12:00 van die dag) voor een datumkiezer; nil als er geen is ingesteld. Een datum erin zetten
    /// bewaart alleen de dag.
    var anchorDate: Date? {
        get { anchor?.date() }
        set { anchor = newValue.map { CalendarDay(date: $0) } }
    }

    /// Stelt het schema in met geldige waarden: het interval geklemd (1...52 weken, 1...366 dagen) en de ankerdatum erbij.
    mutating func setSchedule(_ schedule: SalarySchedule, interval: Int = 1, anchor: CalendarDay? = nil) {
        self.schedule = schedule
        self.interval = schedule == .monthly ? 1 : min(max(interval, 1), schedule == .weeks ? 52 : 366)
        if let anchor { self.anchor = anchor }
    }
}

// MARK: - Het schema met gegevens

extension FinanceData {
    // MARK: Datums

    /// De bekende uitbetaaldatum waar het schema vanaf telt: de ingestelde ankerdatum, anders de salarisdag (`payDay`) van
    /// de startmaand van de gegevens. Alleen van belang bij een schema om de zoveel weken of dagen.
    func salaryAnchor() -> CalendarDay {
        salary.anchor ?? CalendarDay(month: startMonth, day: salaryDay())
    }

    /// De dagen (1...31) van `month` waarop het salaris binnenkomt volgens het schema. Nooit in een maand vóór de startmaand.
    /// Bij het maandelijkse schema één dag. Dit zijn de uitbetalingen volgens het schema; een overschreven salaris van een
    /// maand zonder uitbetaling komt via `salaryPayouts(in:plan:)` op de salarisdag-terugval binnen.
    func salaryPayDays(in month: YearMonth) -> [Int] {
        guard month >= startMonth else { return [] }
        return salary.payDays(in: month, anchor: salaryAnchor())
    }

    /// De uitbetaaldata van `month` (elk om 12:00 op de dag zelf), oplopend. Zie `salaryPayDays(in:)`.
    func salaryPayDates(in month: YearMonth) -> [Date] {
        let cal = YearMonth.calendar
        return salaryPayDays(in: month).map { month.date(day: $0, calendar: cal) }
    }

    /// "De salarisdag" van een maand voor wat geen eigen dag heeft (extra inkomsten, overschrijfdagen): de eerste uitbetaling
    /// van de maand, en als er geen is (of bij het maandelijkse schema) de `payDay`-terugval (`salaryDay()`).
    /// 1...31; een korte maand gebruikt zijn laatste dag.
    func salaryDay(in month: YearMonth) -> Int {
        guard !salary.isMonthly, let first = salaryPayDays(in: month).first else { return salaryDay() }
        return first
    }

    /// De dagen waarop het salaris in `month` binnenkomt, als korte tekst voor onder een bedrag: "de 25e", "de 3e en de 31e",
    /// "de 2e, de 16e en de 30e". Leeg als er die maand geen salaris binnenkomt. Rekent met de echte uitbetalingen van de
    /// maand (`salaryPayouts(in:plan:)`), dus ook met een eigen salaris van die maand.
    func salaryPayoutDaysText(in month: YearMonth) -> String {
        let days = salaryPayouts(in: month, plan: plan(for: month)).filter { $0.cents != 0 }.map { "de \($0.day)e" }
        switch days.count {
        case 0: return ""
        case 1: return days[0]
        default: return days.dropLast().joined(separator: ", ") + " en " + days[days.count - 1]
        }
    }

    /// De eerstvolgende uitbetaling NA de dag van `date` (strikt later: wat vandaag valt is al gebeurd, zoals overal per
    /// kalenderdag), om 12:00 op de dag zelf. Nooit vóór de startmaand. nil kan alleen bij een onleesbaar jaartal.
    func nextPayDate(after date: Date) -> Date? {
        let cal = YearMonth.calendar
        let today = CalendarDay(date: date, calendar: cal)
        let next = salary.nextPayDay(onOrAfter: today.adding(days: 1), notBefore: startMonth, anchor: salaryAnchor())
        guard next > today else { return nil }
        return next.date(calendar: cal)
    }

    /// Korte omschrijving van het schema met de volgende uitbetaling, bijvoorbeeld "elke 4 weken, volgende op 23 oktober"
    /// of "elke maand op de 25e, volgende op 25 oktober 2027" (met het jaar als het niet dit jaar is). `today` is "nu".
    func salaryScheduleSummary(asOf today: Date = Date()) -> String {
        let cycle = salary.cycleDescription
        let cal = YearMonth.calendar
        guard let next = nextPayDate(after: today) else { return cycle }
        let day = CalendarDay(date: next, calendar: cal)
        let sameYear = day.year == CalendarDay(date: today, calendar: cal).year
        let name = Fmt.monthNames[day.month - 1]
        return "\(cycle), volgende op \(day.day) \(name)\(sameYear ? "" : " \(day.year)")"
    }

    // MARK: Bedragen

    /// De uitbetalingen van `month` in hele centen: dag (1...31, op de lengte van de maand gebracht) en bedrag, oplopend.
    /// Dit is DE bron voor het salaris van een maand; `salaryCents(in:plan:)`, `salaryAmount`, de maandcijfers, de
    /// dagboekhouding en de gebeurtenissen lezen allemaal hieruit.
    ///
    /// - Zonder overschrijving: elke uitbetaling is `salary.payoutAmount()` (hele centen).
    /// - Met `plan.salaryOverride` (totaal van de maand) of, bij uurloon, `plan.hoursOverride` (uren van de maand × uurloon):
    ///   dat totaal wordt gelijk over de uitbetalingen verdeeld in hele centen, de restcenten naar de eerste uitbetalingen.
    ///   Zonder uitbetaling in de maand komt een overschreven salaris op de salarisdag-terugval binnen.
    func salaryPayoutCents(in month: YearMonth, plan p: MonthPlan) -> [(day: Int, cents: Int)] {
        guard month >= startMonth else { return [] }
        if salary.isMonthly {
            // Het maandelijkse schema, precies zoals het altijd rekende: één uitbetaling op de salarisdag.
            let amount = p.salaryOverride.map { $0.cents } ?? salary.monthlyAmount(hoursOverride: p.hoursOverride)
            return [(min(salaryDay(), month.dayCount), CentsMath.int(amount))]
        }
        let days = salary.payDays(in: month, anchor: salaryAnchor())
        // Het totaal van de maand gelijk over de uitbetalingen: de restcenten gaan naar de eerste. Zonder uitbetaling in de
        // maand komt alleen een overschreven SALARIS (een bedrag dat de gebruiker er zelf neerzet) op de terugvaldag
        // binnen; uren zonder uitbetaling betalen niets.
        func spread(_ total: Int, fallbackDay: Bool) -> [(day: Int, cents: Int)] {
            guard !days.isEmpty else {
                return fallbackDay && total != 0 ? [(min(salaryDay(), month.dayCount), total)] : []
            }
            let share = CivilDays.floorDiv(total, days.count)
            let rest = total - share * days.count
            return days.indices.map { (days[$0], share + ($0 < rest ? 1 : 0)) }
        }
        if let override = p.salaryOverride { return spread(CentsMath.int(override.cents), fallbackDay: true) }
        if salary.mode == .hourly, let hours = p.hoursOverride {
            return spread(CentsMath.int(SalarySettings.exactHourlyPay(rate: salary.hourlyRate, hours: hours)), fallbackDay: false)
        }
        let each = CentsMath.int(salary.payoutAmount())
        return days.map { ($0, each) }
    }

    /// Het salaris van `month` in hele centen: de som van de uitbetalingen. Eén bron voor `salaryAmount`, `income`,
    /// `remaining`, het overzicht, de projectie en de dagboekhouding.
    func salaryCents(in month: YearMonth, plan p: MonthPlan) -> Int {
        guard month >= startMonth else { return 0 }
        if salary.isMonthly {
            let amount = p.salaryOverride.map { $0.cents } ?? salary.monthlyAmount(hoursOverride: p.hoursOverride)
            return CentsMath.int(amount)
        }
        return CentsMath.sum(salaryPayoutCents(in: month, plan: p).map { $0.cents })
    }

    /// Het salaris dat het schema voor `month` oplevert zonder overschrijving van de maand: het aantal uitbetalingen maal het
    /// bedrag per uitbetaling. Een goede beginwaarde voor "ander bedrag in deze maand".
    func scheduledSalary(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        if salary.isMonthly { return salary.payoutAmount() }
        let each = CentsMath.int(salary.payoutAmount())
        return CentsMath.value(CentsMath.sum(salaryPayDays(in: month).map { _ in each }))
    }

    /// Het aantal uren dat `month` betaalt: de overschreven uren van de maand, anders de uren van het schema (het gemiddelde
    /// per maand bij het maandelijkse schema; anders het aantal uitbetalingen van de maand × uren per cyclus). Een goede
    /// beginwaarde voor "andere uren in deze maand".
    func salaryHours(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        if let hours = months[month.key]?.hoursOverride { return hours }
        if salary.isMonthly { return salary.defaultMonthlyHours }
        return Double(salaryPayDays(in: month).count) * salary.hoursPerCycle
    }

    // MARK: Gemiddelde maand (voor schattingen)

    /// Het inkomen van een GEMIDDELDE maand per grondslag, in hele centen, voor schattingen. Bij het maandelijkse schema is
    /// dat het inkomen van `month` zelf (`incomeBases(in:)`). Anders is het salaris het gemiddelde per maand
    /// (`SalarySettings.averageMonthlyAmount`, zonder overschrijvingen) en komen de extra inkomsten van `month` erbij.
    func estimatedIncomeBases(in month: YearMonth) -> IncomeBases {
        guard !salary.isMonthly else { return incomeBases(in: month) }
        guard month >= startMonth else { return IncomeBases() }
        var extra = 0
        for line in plan(for: month).extraIncome { extra = CentsMath.add(extra, CentsMath.int(line.amount)) }
        let average = CentsMath.int(salary.averageMonthlyAmount())
        return IncomeBases(salary: average, all: CentsMath.add(average, extra))
    }

    /// De cijfers van een GEMIDDELDE maand, voor schattingen: zoals `monthFigures(_:)`, maar met het gemiddelde salaris per
    /// maand in plaats van de uitbetalingen van die ene maand (een maand met twee uitbetalingen is geen maat voor "elke
    /// maand"). Het percentage-inkomen volgt mee. Bij het maandelijkse schema precies `monthFigures(_:)`.
    func estimatedFigures(_ month: YearMonth) -> MonthFigures {
        guard !salary.isMonthly else { return monthFigures(month) }
        guard month >= startMonth else { return MonthFigures() }
        let stored = storedPlans
        return monthFigures(of: plan(for: month, using: stored), in: month, storedPlan: months[month.key],
                            potKeys: pots.map { $0.id.uuidString }, holdingKeys: holdings.map { $0.id.uuidString },
                            salaryCents: CentsMath.int(salary.averageMonthlyAmount()))
    }

    /// Het inkomen van een gemiddelde maand (zie `estimatedFigures`).
    func estimatedMonthlyIncome(in month: YearMonth) -> Double {
        CentsMath.value(estimatedFigures(month).income)
    }

    /// Wat er in een gemiddelde maand nog te verdelen is (zie `estimatedFigures`).
    func estimatedRemaining(in month: YearMonth) -> Double {
        CentsMath.value(estimatedFigures(month).remaining)
    }

    /// Het bedrag van een inlegregel in een gemiddelde maand: een vast bedrag is dat bedrag; een percentage rekent over het
    /// gemiddelde inkomen (`estimatedIncomeBases`). Bij het maandelijkse schema precies `amount(of:in:)`.
    func estimatedAmount(of rule: AllocationRule, in month: YearMonth) -> Double {
        guard !salary.isMonthly else { return amount(of: rule, in: month) }
        switch rule {
        case .amount(let value): return value
        case .percent(let percent):
            return CentsMath.value(AllocationMath.cents(of: percent, bases: estimatedIncomeBases(in: month)))
        }
    }

    /// De inleg van een pot of belegging in een gemiddelde maand (met de overschrijving van die maand, als die er is). Bij
    /// het maandelijkse schema precies `allocation(_:in:)`.
    func estimatedAllocation(_ id: UUID, in month: YearMonth) -> Double {
        guard !salary.isMonthly else { return allocation(id, in: month) }
        return estimatedAmount(of: allocationRule(id, in: month), in: month)
    }

    /// De standaardinleg van een pot of belegging in een gemiddelde maand (zonder overschrijving van die maand). Bij het
    /// maandelijkse schema precies `defaultAllocation(_:in:)`.
    func estimatedDefaultAllocation(_ id: UUID, in month: YearMonth) -> Double {
        guard !salary.isMonthly else { return defaultAllocation(id, in: month) }
        guard let rule = defaultAllocationRule(id, in: month) else { return 0 }
        return estimatedAmount(of: rule, in: month)
    }
}
