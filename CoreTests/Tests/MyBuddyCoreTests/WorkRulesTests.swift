import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van de toeslagen, de pauzetabel en de opslag van de regels (App/Core/WorkRules.swift): de grenzen van een pauze, de factor van
/// een dag (hoogste telt of optellen), alleen afwijkingen worden geschreven en een onleesbare regel wordt overgeslagen
/// (docs/work/plan.md B13 en B14).
final class WorkRulesTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay { CalendarDay(year: year, month: month, day: day) }

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    // MARK: De pauze

    func testTheBreakBoundaryIsInclusive() {
        let rules = WorkRules()
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 329), 0, "5 uur 29 min: geen pauze")
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 330), 30, "5 uur 30 min: 30 minuten")
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 600), 30, "10 uur: nog steeds 30")
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 0), 0)
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: -5), 0)
    }

    func testAnExtraBreakRowTakesOverFromItsThreshold() {
        var rules = WorkRules()
        rules.breakRules.append(BreakRule(fromHours: 10, minutes: 45))
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 599), 30)
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 600), 45, "vanaf 10 uur de hoogste grens")
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 840), 45)
        // De volgorde van de rijen doet er niet toe.
        rules.breakRules.reverse()
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 599), 30)
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 600), 45)
    }

    func testABreakNeverExceedsTheShiftAndClearingTheRulesGivesNoBreak() {
        var rules = WorkRules()
        rules.breakRules = [BreakRule(fromHours: 0, minutes: 60)]
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 20), 20, "nooit meer dan de dienst")
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 90), 60)
        rules.breakRules = []
        XCTAssertEqual(rules.breakMinutes(forShiftMinutes: 600), 0)
    }

    func testBreakRuleBoundariesInHoursAndMinutesAreRoundedToWholeMinutes() {
        XCTAssertEqual(BreakRule(fromHours: 5.5, minutes: 30).thresholdMinutes, 330)
        XCTAssertEqual(BreakRule(fromHours: 4.25, minutes: 15).thresholdMinutes, 255)
        XCTAssertEqual(BreakRule(fromHours: .nan, minutes: 15).thresholdMinutes, 0)
        XCTAssertEqual(BreakRule(fromHours: 99, minutes: 15).thresholdMinutes, 1_440, "een dienst is hoogstens een dag")
    }

    // MARK: De factor van een dag

    func testTheHighestSurchargeWinsAndASundayHolidayIsDouble() {
        var rules = WorkRules()
        let sunday = day(2026, 11, 1)
        XCTAssertEqual(sunday.weekday, 1)
        XCTAssertEqual(rules.factorHundredths(on: sunday), 150, "zondag 1,5")
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 2)), 100, "maandag zonder toeslag")
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 12, 25)), 200, "Eerste Kerstdag op een vrijdag: feestdag 2,0")
        let christmasSunday = day(2022, 12, 25)
        XCTAssertEqual(christmasSunday.weekday, 1)
        XCTAssertEqual(rules.factorHundredths(on: christmasSunday), 200, "een zondag die feestdag is: de hoogste wint")
        rules.combine = .add
        XCTAssertEqual(rules.factorHundredths(on: christmasSunday), 250, "optellen: 1 + 0,5 + 1,0")
        XCTAssertEqual(rules.factorHundredths(on: sunday), 150)
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 2)), 100)
    }

    func testADateRuleAppliesToThatDateOnly() {
        var rules = WorkRules()
        rules.payRules.append(PayRule(kind: .date(day(2026, 11, 2)), factor: 1.25))
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 2)), 125)
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 3)), 100)
        XCTAssertEqual(rules.factorHundredths(on: day(2027, 11, 2)), 100, "een andere datum in een ander jaar")
    }

    func testAWeekdayRuleAppliesEveryWeek() {
        var rules = WorkRules()
        rules.payRules.append(PayRule(kind: .weekday(7), factor: 1.25))   // zaterdag
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 7)), 125)
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 14)), 125)
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 8)), 150, "zondag blijft 1,5")
    }

    func testADisabledSurchargeDoesNotCount() {
        var rules = WorkRules()
        rules.payRules[0].isEnabled = false
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 1)), 100, "zondag zonder toeslag")
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 12, 25)), 200, "de feestdagtoeslag blijft")
        rules.payRules[1].isEnabled = false
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 12, 25)), 100)
        rules.payRules.removeAll()
        XCTAssertEqual(rules.factorHundredths(on: day(2022, 12, 25)), 100, "zonder toeslagen is alles 1,0")
    }

    func testTheHolidaySurchargeFollowsTheSwitchesOfTheHolidays() {
        var rules = WorkRules()
        let goodFriday = day(2026, 4, 3)
        XCTAssertEqual(rules.factorHundredths(on: goodFriday), 100, "Goede Vrijdag staat standaard uit")
        rules.holidays.enabled.insert(.goodFriday)
        XCTAssertEqual(rules.factorHundredths(on: goodFriday), 200)
        rules.holidays.custom = [day(2026, 12, 5)]
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 12, 5)), 200, "een eigen feestdag")
        rules.holidays.enabled.remove(.christmas)
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 12, 25)), 100, "Eerste Kerstdag uitgezet")
    }

    func testCombiningNeverGoesBelowZeroAndAFactorBelowOneCounts() {
        var rules = WorkRules()
        rules.payRules = [PayRule(kind: .weekday(1), factor: 0), PayRule(kind: .holiday, factor: 0)]
        rules.combine = .add
        XCTAssertEqual(rules.factorHundredths(on: day(2022, 12, 25)), 0, "100 - 100 - 100 wordt 0, nooit negatief")
        rules.payRules = [PayRule(kind: .weekday(1), factor: 0.5)]
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 1)), 50, "een toeslag onder 1,0 telt als korting")
        rules.combine = .highest
        rules.payRules = [PayRule(kind: .weekday(1), factor: 0.5), PayRule(kind: .holiday, factor: 2)]
        XCTAssertEqual(rules.factorHundredths(on: day(2022, 12, 25)), 200)
        XCTAssertEqual(rules.factorHundredths(on: day(2026, 11, 1)), 50, "alleen de zondag geldt: de hoogste van een")
    }

    func testTheFactorInHundredthsIsClampedAndNeverCrashes() {
        XCTAssertEqual(PayRule(kind: .holiday, factor: 1.5).factorHundredths, 150)
        XCTAssertEqual(PayRule(kind: .holiday, factor: 1.256).factorHundredths, 126, "naar honderdsten afgerond")
        XCTAssertEqual(PayRule(kind: .holiday, factor: 1.254).factorHundredths, 125)
        XCTAssertEqual(PayRule(kind: .holiday, factor: 99).factorHundredths, 1_000)
        XCTAssertEqual(PayRule(kind: .holiday, factor: -3).factorHundredths, 0)
        XCTAssertEqual(PayRule(kind: .holiday, factor: .nan).factorHundredths, 100)
        XCTAssertEqual(PayRule(kind: .holiday, factor: .infinity).factorHundredths, 100)
    }

    func testCalendarDayWeekdayMatchesCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        var date = day(2019, 12, 1)
        for _ in 0..<2_500 {
            let expected = calendar.component(.weekday, from: calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))!)
            XCTAssertEqual(date.weekday, expected, date.key)
            date = date.adding(days: 1)
        }
        XCTAssertEqual(day(1970, 1, 1).weekday, 5, "1 januari 1970 was een donderdag")
        XCTAssertEqual(day(1969, 12, 31).weekday, 4, "en de dag ervoor een woensdag")
    }

    // MARK: Opslag

    func testTheDefaultRulesWriteNothingAndTwoNewOnesAreEqual() throws {
        XCTAssertEqual(try json(WorkRules()), "{}")
        XCTAssertEqual(try json(HolidaySettings()), "{}")
        XCTAssertEqual(WorkRules(), WorkRules(), "de vaste id's van de standaardregels")
        XCTAssertEqual(WorkRules().payRules.map { $0.id }, WorkRules.defaultPayRules.map { $0.id })
        XCTAssertEqual(WorkRules().payRules.count, 2)
        XCTAssertEqual(WorkRules().breakRules, [BreakRule(id: StableID.uuid("breakrule|5.5"), fromHours: 5.5, minutes: 30)])
        XCTAssertEqual(WorkRules().combine, .highest)
        let empty = try decode(WorkRules.self, "{}")
        XCTAssertEqual(empty, WorkRules(), "een bestand zonder regels geeft de standaard")
    }

    func testOnlyTheDeviationsAreWritten() throws {
        var rules = WorkRules()
        rules.combine = .add
        XCTAssertEqual(try json(rules), #"{"combine":"add"}"#)
        rules = WorkRules()
        rules.holidays.enabled.insert(.goodFriday)
        XCTAssertTrue(try json(rules).hasPrefix(#"{"holidays":{"enabled":["#))
        XCTAssertFalse(try json(rules).contains("payRules"))
        XCTAssertFalse(try json(rules).contains("breakRules"))
        rules = WorkRules()
        rules.breakRules = []
        XCTAssertEqual(try json(rules), #"{"breakRules":[]}"#, "alles wissen is ook een afwijking")
        rules = WorkRules()
        rules.payRules[0].factor = 2
        XCTAssertTrue(try json(rules).contains(#""payRules":"#))
        XCTAssertFalse(try json(rules).contains("breakRules"))
    }

    func testRulesRoundTripWithEveryDeviation() throws {
        var rules = WorkRules()
        rules.combine = .add
        rules.payRules.append(PayRule(kind: .date(day(2026, 12, 5)), factor: 1.25, isEnabled: false))
        rules.payRules.append(PayRule(kind: .weekday(7), factor: 1.2))
        rules.breakRules.append(BreakRule(fromHours: 10, minutes: 45))
        rules.holidays.enabled.formUnion([.goodFriday, .newYearsEve])
        rules.holidays.enabled.remove(.kingsDay)
        rules.holidays.custom = [day(2026, 12, 5), day(2026, 11, 20)]
        let back = try decode(WorkRules.self, try json(rules))
        XCTAssertEqual(back.combine, rules.combine)
        XCTAssertEqual(back.payRules, rules.payRules)
        XCTAssertEqual(back.breakRules, rules.breakRules)
        XCTAssertEqual(back.holidays.enabled, rules.holidays.enabled)
        XCTAssertEqual(back.holidays.custom, rules.holidays.custom.sorted(), "eigen dagen staan op datum")
    }

    func testAnUnreadableRuleIsSkippedAndTheRestStays() throws {
        let text = #"{"payRules":[{"kind":"weekday:3","factor":1.2},{"kind":"onzin","factor":9},{"factor":2},"kapot",{"kind":"date:2026-12-05","factor":"veel"}],"# +
            #""breakRules":[{"fromHours":4,"minutes":15},"kapot",{"fromHours":"x","minutes":10}],"combine":"onbekend","holidays":"kapot"}"#
        let rules = try decode(WorkRules.self, text)
        XCTAssertEqual(rules.payRules.count, 2, "de weekdagtoeslag en de datumtoeslag met een onleesbare factor")
        XCTAssertEqual(rules.payRules[0].kind, .weekday(3))
        XCTAssertEqual(rules.payRules[0].factor, 1.2)
        XCTAssertEqual(rules.payRules[1].kind, .date(day(2026, 12, 5)))
        XCTAssertEqual(rules.payRules[1].factor, 1, "een onleesbare factor is 1,0")
        XCTAssertEqual(rules.breakRules.count, 2)
        XCTAssertEqual(rules.breakRules[0].minutes, 15)
        XCTAssertEqual(rules.breakRules[0].fromHours, 4)
        XCTAssertEqual(rules.breakRules[1].fromHours, 0, "een onleesbaar veld is 0")
        XCTAssertEqual(rules.combine, .highest, "een onbekende keuze geeft de standaard")
        XCTAssertEqual(rules.holidays, HolidaySettings(), "onleesbare feestdagen geven de standaard")
    }

    func testTheKindOfARuleIsStoredAsReadableText() throws {
        XCTAssertEqual(try json(PayRuleKind.weekday(1)), #""weekday:1""#)
        XCTAssertEqual(try json(PayRuleKind.holiday), #""holiday""#)
        XCTAssertEqual(try json(PayRuleKind.date(day(2026, 12, 5))), #""date:2026-12-05""#)
        for kind in [PayRuleKind.weekday(7), .holiday, .date(day(2030, 1, 31))] {
            XCTAssertEqual(try decode(PayRuleKind.self, try json(kind)), kind)
        }
        for bad in [#""weekday:0""#, #""weekday:8""#, #""weekday:x""#, #""date:2026-13-01""#, #""date:""#, #""holiday:1""#, "12"] {
            XCTAssertThrowsError(try decode(PayRuleKind.self, bad), bad)
        }
    }

    func testAFactorOutsideZeroToTenIsClampedWhenRead() throws {
        XCTAssertEqual(try decode(PayRule.self, #"{"kind":"holiday","factor":99}"#).factor, 10)
        XCTAssertEqual(try decode(PayRule.self, #"{"kind":"holiday","factor":-4}"#).factor, 0)
        XCTAssertEqual(try decode(PayRule.self, #"{"kind":"holiday"}"#).factor, 1, "zonder factor 1,0")
        XCTAssertTrue(try decode(PayRule.self, #"{"kind":"holiday","factor":2}"#).isEnabled, "standaard aan")
        XCTAssertFalse(try decode(PayRule.self, #"{"kind":"holiday","factor":2,"isEnabled":false}"#).isEnabled)
        let minutes = try decode(BreakRule.self, #"{"fromHours":30,"minutes":9999}"#)
        XCTAssertEqual(minutes.fromHours, 24)
        XCTAssertEqual(minutes.minutes, 600)
        // Schrijven laat een onmogelijke waarde niet door (de JSON-encoder weigert NaN).
        XCTAssertNoThrow(try json(PayRule(kind: .holiday, factor: .nan)))
        XCTAssertNoThrow(try json(BreakRule(fromHours: .infinity, minutes: 5)))
    }

    func testHolidaySettingsReadMildlyAndKeepTheDeviationOnly() throws {
        var settings = try decode(HolidaySettings.self, #"{"enabled":["goodFriday","onbekend","christmas"],"custom":["2026-12-05","kapot","2026-11-20"]}"#)
        XCTAssertEqual(settings.enabled, [.goodFriday, .christmas])
        XCTAssertEqual(settings.custom, [day(2026, 11, 20), day(2026, 12, 5)], "de leesbare eigen dagen, op datum")
        settings = HolidaySettings()
        XCTAssertEqual(settings.enabled, HolidayKind.standard)
        settings.enabled = []
        XCTAssertEqual(try json(settings), #"{"enabled":[]}"#, "alles uitzetten is een afwijking")
        XCTAssertEqual(try decode(HolidaySettings.self, #"{"enabled":[]}"#).enabled, [])
        XCTAssertEqual(try decode(HolidaySettings.self, "{}").enabled, HolidayKind.standard)
    }
}
