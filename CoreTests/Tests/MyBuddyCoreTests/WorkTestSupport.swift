import XCTest
import Foundation
@testable import MyBuddyCore

// Hulpjes voor de tests van de werkuren uit de agenda (docs/work/plan.md par. 3.5): willekeurige diensten voor `ledgerScenario` en de
// eigenschapstests, en twee ONAFHANKELIJKE berekeningen van wat een uitbetaling uit de agenda betaalt, waartegen de motor wordt gelegd:
//
//  - `referenceAgendaPayout`: per kalenderdag van de periode met `Calendar` (de overlap van elke dienst met die dag), snel genoeg voor
//    honderden datasets;
//  - `referencePerMinute`: per MINUUT met `Calendar` (elke minuut van elke dienst krijgt zijn dag), traag maar zonder enige aanname over
//    dagen van 23 of 25 uur; voor de handgemaakte gevallen.
//
// Beide gebruiken niets van `WorkLedger`, `WorkPeriods`, `WorkShift.pieces`, `workReport` of `exactPayCents`: de bedragen rekenen met
// gehele centen (uurloon in centen × gewogen minuten, half omhoog).

// MARK: - Een Amsterdamse kalender (zomertijd)

/// De Gregoriaanse kalender van Europe/Amsterdam, of nil als de tijdzone ontbreekt (de test slaat dan over).
func engAmsterdamCalendar() -> Calendar? {
    guard let zone = TimeZone(identifier: "Europe/Amsterdam") else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// Een moment op een dag in een kalender.
func engDate(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date(timeIntervalSince1970: 0)
}

/// Een dienst van `start` tot `end` (nooit nil in de tests).
func engShift(_ start: Date, _ end: Date) -> WorkShift {
    WorkShift(start: start, end: end)!
}

/// Een snapshot met de gegeven diensten: de agenda is bekend tot en met `fetched` en het venster loopt van een jaar ervoor tot een jaar
/// erna.
func engSnapshot(_ shifts: [WorkShift], fetched: CalendarDay, from: CalendarDay? = nil, through: CalendarDay? = nil,
                 title: String = "werken") -> WorkSnapshot {
    WorkSnapshot(shifts: shifts, from: from ?? fetched.adding(days: -400), through: through ?? fetched.adding(days: 366),
                 fetchedDay: fetched, calendarTitle: title)
}

// MARK: - Willekeurige diensten

/// Zet `d` om naar een uurloon met de uren uit de agenda en vult de agenda met willekeurige diensten: het uurloon (hele centen) en de
/// uren per week (heel), de periode (deze of de vorige), toeslagen en pauzeregels, diensten van drie maanden voor `start` tot twee
/// maanden na de laatste maand (ook over middernacht en op feestdagen) tot een horizon waarna de agenda niets meer weet, en de dag van de
/// laatste verversing. Het schema van het salaris blijft zoals het is.
func engApplyRandomAgenda(_ d: inout FinanceData, _ r: inout EngRandom, around start: YearMonth, months: Int) {
    let cal = YearMonth.calendar
    d.salary.mode = .hourly
    d.salary.hourlyRate = r.amount(10, 45)
    d.salary.hoursPerWeek = Double(r.int(8...40))
    d.work.hoursSource = .calendar
    d.work.periodBasis = r.chance(40) ? .previous : .current
    if r.chance(40) { d.work.rules.combine = .add }
    if r.chance(50) { d.work.rules.holidays.enabled.insert(.goodFriday) }
    if r.chance(50) { d.work.rules.payRules.append(PayRule(kind: .weekday(r.int(1...7)), factor: Double(r.int(100...250)) / 100)) }
    if r.chance(50) { d.work.rules.breakRules.append(BreakRule(fromHours: Double(r.int(6...11)), minutes: r.int(15...60))) }
    if r.chance(20) { d.work.rules.breakRules = [] }
    // Diensten rond de tijdlijn; de agenda loopt maar tot een horizon (zoals een rooster dat een paar weken vooruit bekend is).
    let first = CalendarDay(month: start.adding(-3), day: 1)
    let last = CalendarDay(month: start.adding(months + 2), day: 1)
    let horizon = first.adding(days: r.int(20...(30 * months)))
    var shifts: [WorkShift] = []
    var day = first
    while day < min(last, horizon) {
        if r.chance(55) {
            let begin = cal.startOfDay(for: day.date(calendar: cal)).addingTimeInterval(Double(r.int(5...22)) * 3_600 + Double(r.int(0...3)) * 900)
            let hours = Double(r.int(2...13)) + Double(r.int(0...3)) * 0.25
            if let shift = WorkShift(start: begin, end: begin.addingTimeInterval(hours * 3_600)) { shifts.append(shift) }
        }
        day = day.adding(days: 1)
    }
    let fetched = first.adding(days: r.int(10...(30 * months)))
    d.work.snapshot = WorkSnapshot(shifts: shifts, from: first, through: last, fetchedDay: fetched, calendarTitle: d.work.calendarTitle)
}

// MARK: - De onafhankelijke berekening, per dag

/// Wat de onafhankelijke berekening van een uitbetaling uit de agenda geeft.
struct ReferenceAgendaPayout: Equatable {
    /// De dagnummers (`CalendarDay.dayNumber`) van de periode.
    var firstDay = 0
    var lastDay = 0
    /// Betaalde minuten uit de agenda (na pauze) in de periode.
    var agendaMinutes = 0
    var breakMinutes = 0
    /// Het aantal diensten dat op een dag van de periode begint (op een dag die de agenda kent).
    var shiftCount = 0
    /// Minuten uit het gemiddelde voor de dagen die de agenda niet kent.
    var expectedMinutes = 0
    /// Betaalde minuten × factor in honderdsten, inclusief de verwachte minuten × 100.
    var weighted100 = 0
    /// De periode ligt helemaal voorbij wat de agenda kent: het bedrag is het handmatige bedrag.
    var isAllExpected = false
    var cents = 0
}

/// Het jaar, de maand en de dag van een moment in `calendar` als één getal (jjjjmmdd), om dagen te vergelijken.
private func engDayKey(_ date: Date, _ calendar: Calendar) -> Int {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
}

/// De factor van een dag in honderdsten volgens de regels, met de lijst van feestdagen van het jaar (`DutchHolidays.holidays`, niet de
/// formule van `isHoliday`) en `Calendar.weekday` (niet `CalendarDay.weekday`).
func referenceFactorHundredths(on date: Date, rules: WorkRules, calendar: Calendar) -> Int {
    let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
    let (year, month, day, weekday) = (c.year ?? 0, c.month ?? 0, c.day ?? 0, c.weekday ?? 0)
    let isHoliday = DutchHolidays.holidays(year: year, settings: rules.holidays).contains {
        $0.day.year == year && $0.day.month == month && $0.day.day == day
    }
    var factors: [Int] = []
    for rule in rules.payRules where rule.isEnabled {
        let hundredths = Int((min(max(rule.factor, 0), 10) * 100).rounded())
        switch rule.kind {
        case .weekday(let n): if n == weekday { factors.append(hundredths) }
        case .holiday: if isHoliday { factors.append(hundredths) }
        case .date(let other): if other.year == year && other.month == month && other.day == day { factors.append(hundredths) }
        }
    }
    if factors.isEmpty { return 100 }
    switch rules.combine {
    case .highest: return factors.max() ?? 100
    case .add: return max(0, 100 + factors.reduce(0) { $0 + $1 - 100 })
    }
}

/// De onbetaalde pauze voor een dienst van `minutes` minuten: de regel met de hoogste grens die niet boven de dienst ligt.
func referenceBreakMinutes(forShiftMinutes minutes: Int, rules: WorkRules) -> Int {
    var best: (threshold: Int, minutes: Int)?
    for rule in rules.breakRules {
        let threshold = Int((min(max(rule.fromHours, 0), 24) * 60).rounded())
        if threshold <= minutes, best == nil || threshold >= best!.threshold { best = (threshold, rule.minutes) }
    }
    return min(max(best?.minutes ?? 0, 0), minutes)
}

/// Verdeelt `total` over `weights` evenredig met de grootste rest; bij gelijke rest gaat de eerste voor.
func referenceShare(_ total: Int, over weights: [Int]) -> [Int] {
    let sum = weights.reduce(0, +)
    guard total > 0, sum > 0 else { return weights.map { _ in 0 } }
    var result = weights.map { total * $0 / sum }
    var left = total - result.reduce(0, +)
    var order = Array(weights.indices)
    order.sort { a, b in
        let ra = total * weights[a] % sum, rb = total * weights[b] % sum
        return ra == rb ? a < b : ra > rb
    }
    for index in order where left > 0 {
        result[index] += 1
        left -= 1
    }
    return result
}

/// Per kalenderdag (jjjjmmdd) wat de diensten opleveren: betaalde minuten, pauzeminuten en gewogen minuten. Elke dienst wordt in stukken
/// per dag gesneden met de overlap van `[begin, einde)` met `[begin van de dag, begin van de volgende dag)`.
private func referenceDayTotals(_ shifts: [WorkShift], rules: WorkRules, calendar: Calendar)
    -> [Int: (paid: Int, breaks: Int, weighted: Int)] {
    var totals: [Int: (paid: Int, breaks: Int, weighted: Int)] = [:]
    for shift in shifts {
        var dayStart = calendar.startOfDay(for: shift.start)
        var pieces: [(key: Int, date: Date, minutes: Int)] = []
        while dayStart < shift.end {
            let next = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            let from = max(shift.start, dayStart), to = min(shift.end, next)
            let minutes = Int((to.timeIntervalSince(from) / 60).rounded())
            if minutes > 0 { pieces.append((engDayKey(dayStart, calendar), dayStart, minutes)) }
            dayStart = next
        }
        let breaks = referenceShare(referenceBreakMinutes(forShiftMinutes: shift.durationMinutes, rules: rules), over: pieces.map { $0.minutes })
        for (index, piece) in pieces.enumerated() {
            let paid = max(0, piece.minutes - breaks[index])
            let factor = referenceFactorHundredths(on: piece.date, rules: rules, calendar: calendar)
            var entry = totals[piece.key] ?? (0, 0, 0)
            entry.paid += paid
            entry.breaks += min(breaks[index], piece.minutes)
            entry.weighted += paid * factor
            totals[piece.key] = entry
        }
    }
    return totals
}

/// De uitbetaling op `payoutDay` volgens de regels van par. 3.2 van docs/work/plan.md, onafhankelijk van de motor: de periode (deze of de
/// vorige, per maand of per cyclus), de uren uit de agenda per dag, het gemiddelde voor de dagen die de agenda niet kent, en het bedrag
/// met het uurloon van de maand van de uitbetaling (`referenceSalarySettings`), op gehele centen.
func referenceAgendaPayout(_ d: FinanceData, payoutDay: CalendarDay) -> ReferenceAgendaPayout {
    let cal = YearMonth.calendar
    let month = payoutDay.yearMonth
    let wage = referenceSalarySettings(d, month: month)
    let payoutNoon = cal.date(from: DateComponents(year: payoutDay.year, month: payoutDay.month, day: payoutDay.day, hour: 12)) ?? Date()
    let previous = d.work.periodBasis == .previous

    // De dagen van de periode, elk om 12:00, en het aantal uren dat een cyclus betaalt.
    var days: [Date] = []
    let hoursPerCycle: Double
    switch d.salary.schedule {
    case .monthly:
        let target = previous ? (cal.date(byAdding: .month, value: -1, to: payoutNoon) ?? payoutNoon) : payoutNoon
        let c = cal.dateComponents([.year, .month], from: target)
        let first = cal.date(from: DateComponents(year: c.year, month: c.month, day: 1, hour: 12)) ?? target
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
        hoursPerCycle = wage.hoursPerWeek * 52 / 12
    case .weeks, .days:
        let n = d.salary.schedule == .weeks ? min(max(d.salary.interval, 1), 52) : min(max(d.salary.interval, 1), 366)
        let cycle = d.salary.schedule == .weeks ? 7 * n : n
        let end = previous ? (cal.date(byAdding: .day, value: -cycle, to: payoutNoon) ?? payoutNoon) : payoutNoon
        days = (0..<cycle).compactMap { cal.date(byAdding: .day, value: $0 - (cycle - 1), to: end) }
        hoursPerCycle = d.salary.schedule == .weeks ? wage.hoursPerWeek * Double(n) : wage.hoursPerWeek * Double(n) / 7
    }

    var result = ReferenceAgendaPayout()
    result.firstDay = CalendarDay(date: days.first ?? payoutNoon, calendar: cal).dayNumber
    result.lastDay = CalendarDay(date: days.last ?? payoutNoon, calendar: cal).dayNumber

    // Tot en met welke dag kent de agenda alles: de dag van de laatste verversing of de dag van de laatste dienst.
    var known = Int.min
    let shifts = d.work.snapshot?.shifts ?? []
    if let snapshot = d.work.snapshot {
        known = snapshot.fetchedDay.year * 10_000 + snapshot.fetchedDay.month * 100 + snapshot.fetchedDay.day
        for shift in shifts { known = max(known, engDayKey(shift.end.addingTimeInterval(-60), cal)) }
    }
    let perDay = referenceDayTotals(shifts, rules: d.work.rules, calendar: cal)
    var startsPerDay: [Int: Int] = [:]
    for shift in shifts { startsPerDay[engDayKey(shift.start, cal), default: 0] += 1 }
    var unknownDays = 0
    var knownDays = 0
    for day in days {
        let key = engDayKey(day, cal)
        if key > known {
            unknownDays += 1
            continue
        }
        knownDays += 1
        result.shiftCount += startsPerDay[key] ?? 0
        if let entry = perDay[key] {
            result.agendaMinutes += entry.paid
            result.breakMinutes += entry.breaks
            result.weighted100 += entry.weighted
        }
    }

    let rateCents = engCents(wage.hourlyRate)
    if knownDays == 0 {
        // De hele periode ligt voorbij wat de agenda weet: precies het handmatige bedrag.
        result.isAllExpected = true
        result.expectedMinutes = Int((hoursPerCycle * 60).rounded())
        result.cents = referencePayoutCents(wage)
        return result
    }
    if unknownDays > 0 {
        result.expectedMinutes = Int((hoursPerCycle * 60 * Double(unknownDays) / Double(days.count)).rounded())
        result.weighted100 += result.expectedMinutes * 100
    }
    result.cents = (rateCents * result.weighted100 + 3_000) / 6_000
    return result
}

// MARK: - De onafhankelijke berekening, per minuut

/// Elke minuut van elke dienst telt met zijn eigen dag: het resultaat is wat een uitbetaling zou betalen als ALLE dagen van de dienst uit
/// de agenda komen (zonder terugval op het gemiddelde). Traag (een `Calendar`-vraag per minuut), dus alleen voor een paar handgemaakte
/// diensten. Geeft per dag (jjjjmmdd) de betaalde minuten, de pauzeminuten en de gewogen minuten.
func referencePerMinute(_ shifts: [WorkShift], rules: WorkRules, calendar: Calendar) -> [Int: (paid: Int, breaks: Int, weighted: Int)] {
    var totals: [Int: (paid: Int, breaks: Int, weighted: Int)] = [:]
    for shift in shifts {
        var perDay: [Int: Int] = [:]
        var order: [Int] = []
        var minute = shift.startMinute
        while minute < shift.endMinute {
            let key = engDayKey(Date(timeIntervalSince1970: Double(minute) * 60 + 30), calendar)
            if perDay[key] == nil { order.append(key) }
            perDay[key, default: 0] += 1
            minute += 1
        }
        let weights = order.map { perDay[$0] ?? 0 }
        let breaks = referenceShare(referenceBreakMinutes(forShiftMinutes: shift.durationMinutes, rules: rules), over: weights)
        for (index, key) in order.enumerated() {
            // De factor van de dag: neem een moment om 12:00 van die dag.
            let year = key / 10_000, month = key / 100 % 100, day = key % 100
            let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
            let factor = referenceFactorHundredths(on: noon, rules: rules, calendar: calendar)
            let paid = max(0, weights[index] - breaks[index])
            var entry = totals[key] ?? (0, 0, 0)
            entry.paid += paid
            entry.breaks += min(breaks[index], weights[index])
            entry.weighted += paid * factor
            totals[key] = entry
        }
    }
    return totals
}

// MARK: - Mislukte vergelijkingen verzamelen

/// Verzamelt mislukte vergelijkingen zonder per vergelijking de XCTest-machinerie aan te roepen (dat is in een debug-build zo traag dat
/// een eigenschapstest er minuten over zou doen) en meldt ze aan het eind.
final class EngFailures {
    private(set) var list: [String] = []
    private(set) var count = 0

    func eq<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String) {
        count += 1
        if a != b { list.append("\(message()): \(a) is niet gelijk aan \(b)") }
    }

    func ok(_ condition: Bool, _ message: @autoclosure () -> String) {
        count += 1
        if !condition { list.append(message()) }
    }

    func report(file: StaticString = #filePath, line: UInt = #line) {
        if !list.isEmpty {
            XCTFail("\(list.count) van \(count) vergelijkingen mislukt, de eerste:\n" + list.prefix(12).joined(separator: "\n"), file: file, line: line)
        }
    }
}
