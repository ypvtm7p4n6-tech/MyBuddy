import XCTest
import Foundation
@testable import MyBuddyCore

// Hulpjes voor de eigenschapstests van het salarisschema: een onafhankelijke berekening van de uitbetalingen van een maand
// (stap voor stap met `Calendar`, bedragen in hele centen met gehele getallen), waartegen de motor wordt gelegd.

/// Een uitbetaling zoals de onafhankelijke berekening haar ziet.
struct ReferencePayout: Equatable {
    var day: Int
    var cents: Int
}

/// De dagen van `month` waarop het schema uitbetaalt, stap voor stap met `Calendar` vanaf de ankerdatum (in beide richtingen).
/// Maandelijks: de salarisdag, op de lengte van de maand gebracht. Nooit in een maand vóór de startmaand.
func referencePayDays(_ salary: SalarySettings, start: YearMonth, month: YearMonth) -> [Int] {
    guard month >= start else { return [] }
    if salary.schedule == .monthly { return [min(min(max(salary.payDay, 1), 31), month.dayCount)] }
    let cal = YearMonth.calendar
    let cycle = salary.schedule == .weeks ? 7 * min(max(salary.interval, 1), 52) : min(max(salary.interval, 1), 366)
    // Het anker: de ingestelde dag, anders de salarisdag van de startmaand.
    let origin: Date
    if let anchor = salary.anchor {
        origin = cal.date(from: DateComponents(year: anchor.year, month: anchor.month, day: anchor.day, hour: 12)) ?? start.firstDay
    } else {
        let day = min(min(max(salary.payDay, 1), 31), start.dayCount)
        origin = cal.date(from: DateComponents(year: start.year, month: start.month, day: day, hour: 12)) ?? start.firstDay
    }
    let span = cal.dateComponents([.day], from: origin, to: month.firstDay).day ?? 0
    let around = span / cycle
    var days: [Int] = []
    for k in (around - 2)...(around + 2 + 31 / cycle) {
        guard let date = cal.date(byAdding: .day, value: k * cycle, to: origin) else { continue }
        if YearMonth(date: date, calendar: cal) == month { days.append(cal.component(.day, from: date)) }
    }
    return days.sorted()
}

/// Het bedrag van één uitbetaling in hele centen, met gehele getallen uitgerekend. Alleen voor uurlonen met hele centen
/// en een geheel aantal uren per week (daar komen geen halve centen voor): vast = het bedrag; uurloon = uurloon x uren per
/// week x weken per cyclus (maandelijks 52 / 12 weken; N dagen is N / 7 weken), half omhoog afgerond.
func referencePayoutCents(_ salary: SalarySettings) -> Int {
    if salary.mode == .fixed { return engCents(salary.fixedMonthly) }
    let weekly = engCents(salary.hourlyRate) * Int(salary.hoursPerWeek)
    switch salary.schedule {
    case .monthly: return (weekly * 13 * 2 + 3) / 6                      // weekly x 52 / 12, half omhoog
    case .weeks: return weekly * min(max(salary.interval, 1), 52)
    case .days: return (weekly * min(max(salary.interval, 1), 366) * 2 + 7) / 14   // weekly x N / 7, half omhoog
    }
}

/// De uitbetalingen van `month` zoals ze horen te zijn, met een eventuele overschrijving van de maand (salaris: het totaal;
/// uren: de uren van de maand, bij uurloon). Het totaal wordt gelijk verdeeld, de restcenten naar de eerste uitbetalingen;
/// zonder uitbetaling in de maand komt een overschreven salaris op de salarisdag-terugval binnen.
func referenceSalaryPayouts(_ salary: SalarySettings, start: YearMonth, month: YearMonth, startDay: CalendarDay? = nil,
                            salaryOverride: Double? = nil, hoursOverride: Double? = nil) -> [ReferencePayout] {
    guard month >= start else { return [] }
    // Met een startdatum (golf 1, docs/work/plan.md) tellen in de startmaand alleen de uitbetalingen op of na de startdag. Een
    // eigen salaris of eigen uren is het totaal dat telt, verdeeld over die uitbetalingen. Zonder startdatum telt alles.
    var firstCounted = 1
    if let startDay, startDay.yearMonth == month { firstCounted = startDay.day }
    let days = referencePayDays(salary, start: start, month: month).filter { $0 >= firstCounted }
    func spread(_ total: Int, fallback: Bool) -> [ReferencePayout] {
        if days.isEmpty {
            let day = min(min(max(salary.payDay, 1), 31), month.dayCount)
            return fallback && total != 0 && day >= firstCounted ? [ReferencePayout(day: day, cents: total)] : []
        }
        // Gelijk verdelen: eerst het hele deel, dan de rest één cent per uitbetaling vanaf de eerste.
        var shares = [Int](repeating: total / days.count, count: days.count)   // alleen voor bedragen vanaf nul
        var left = total - shares.reduce(0, +)
        var i = 0
        while left > 0 { shares[i] += 1; left -= 1; i += 1 }
        return zip(days, shares).map { ReferencePayout(day: $0, cents: $1) }
    }
    if let override = salaryOverride { return spread(engCents(override), fallback: true) }
    if salary.mode == .hourly, let hours = hoursOverride {
        // Uren van een maand (ook met een kwartier of tiende uur): uurloon x uren, op hele centen half omhoog, met gehele
        // getallen uitgerekend (uurloon in centen x uren in honderdsten, zonder kommagetallen).
        return spread((engCents(salary.hourlyRate) * Int((hours * 100).rounded()) + 50) / 100, fallback: false)
    }
    return days.map { ReferencePayout(day: $0, cents: referencePayoutCents(salary)) }
}
