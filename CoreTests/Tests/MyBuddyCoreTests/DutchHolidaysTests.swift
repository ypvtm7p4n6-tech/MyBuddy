import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van de Nederlandse feestdagen (App/Core/WorkRules.swift): uitgerekend, geen tabel. Pasen volgens Meeus/Jones/Butcher, de rest
/// als verschil in dagen; elke feestdag heeft een schakelaar en er zijn eigen datums (docs/work/plan.md B14).
final class DutchHolidaysTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay { CalendarDay(year: year, month: month, day: day) }

    func testEasterOf2024To2035() {
        let expected: [Int: (Int, Int)] = [2024: (3, 31), 2025: (4, 20), 2026: (4, 5), 2027: (3, 28), 2028: (4, 16), 2029: (4, 1),
                                           2030: (4, 21), 2031: (4, 13), 2032: (3, 28), 2033: (4, 17), 2034: (4, 9), 2035: (3, 25)]
        XCTAssertEqual(expected.count, 12)
        for (year, date) in expected {
            XCTAssertEqual(DutchHolidays.easter(year: year), day(year, date.0, date.1), "Pasen \(year)")
        }
    }

    func testEasterOf2000To2023AndTheExtremes() {
        let expected: [Int: (Int, Int)] = [2000: (4, 23), 2001: (4, 15), 2002: (3, 31), 2003: (4, 20), 2004: (4, 11), 2005: (3, 27),
                                           2006: (4, 16), 2007: (4, 8), 2008: (3, 23), 2009: (4, 12), 2010: (4, 4), 2011: (4, 24),
                                           2012: (4, 8), 2013: (3, 31), 2014: (4, 20), 2015: (4, 5), 2016: (3, 27), 2017: (4, 16),
                                           2018: (4, 1), 2019: (4, 21), 2020: (4, 12), 2021: (4, 4), 2022: (4, 17), 2023: (4, 9)]
        for (year, date) in expected { XCTAssertEqual(DutchHolidays.easter(year: year), day(year, date.0, date.1), "Pasen \(year)") }
        // De vroegste en de laatste mogelijke datum.
        XCTAssertEqual(DutchHolidays.easter(year: 1818), day(1818, 3, 22))
        XCTAssertEqual(DutchHolidays.easter(year: 2285), day(2285, 3, 22))
        XCTAssertEqual(DutchHolidays.easter(year: 1943), day(1943, 4, 25))
        XCTAssertEqual(DutchHolidays.easter(year: 2038), day(2038, 4, 25))
    }

    func testEasterIsAlwaysASundayBetween22MarchAnd25April() {
        for year in 1900...2200 {
            let easter = DutchHolidays.easter(year: year)
            XCTAssertEqual(easter.weekday, 1, "Pasen \(year) is een zondag")
            XCTAssertTrue(easter >= day(year, 3, 22) && easter <= day(year, 4, 25), "Pasen \(year): \(easter.key)")
        }
    }

    func testTheNineStandardHolidaysOfEveryYear() {
        for year in 2024...2035 {
            let list = DutchHolidays.holidays(year: year)
            XCTAssertEqual(list.count, 9, "negen feestdagen in \(year)")
            XCTAssertEqual(list.map { $0.day }, list.map { $0.day }.sorted(), "op datum")
            XCTAssertEqual(Set(list.map { $0.day }).count, 9, "negen verschillende dagen")
            XCTAssertEqual(Set(list.map { $0.name }).count, 9)
        }
    }

    func testIsHolidayAgreesWithTheListOnEveryDayOfTheYear() {
        var settings = HolidaySettings()
        settings.enabled.formUnion([.goodFriday, .liberationDay, .newYearsEve])
        settings.custom = [day(2026, 12, 5), day(2027, 2, 14)]
        for year in 2024...2035 {
            for (label, current) in [("standaard", HolidaySettings()), ("met extra's", settings)] {
                let listed = Set(DutchHolidays.holidays(year: year, settings: current).map { $0.day })
                var date = day(year, 1, 1)
                var count = 0
                while date.year == year {
                    let flagged = DutchHolidays.isHoliday(date, settings: current)
                    XCTAssertEqual(flagged, listed.contains(date), "\(date.key) (\(label))")
                    if flagged { count += 1 }
                    date = date.adding(days: 1)
                }
                XCTAssertEqual(count, listed.count, "\(year) (\(label))")
            }
        }
    }

    func testAscensionAndPentecostOf2025And2026() {
        let h25 = DutchHolidays.holidays(year: 2025).map { "\($0.name) \($0.day.key)" }
        XCTAssertTrue(h25.contains("Hemelvaartsdag 2025-05-29"), "\(h25)")
        XCTAssertTrue(h25.contains("Eerste Pinksterdag 2025-06-08"))
        XCTAssertTrue(h25.contains("Tweede Pinksterdag 2025-06-09"))
        XCTAssertTrue(h25.contains("Tweede Paasdag 2025-04-21"))
        let h26 = DutchHolidays.holidays(year: 2026).map { "\($0.name) \($0.day.key)" }
        XCTAssertTrue(h26.contains("Hemelvaartsdag 2026-05-14"), "\(h26)")
        XCTAssertTrue(h26.contains("Eerste Pinksterdag 2026-05-24"))
        XCTAssertTrue(h26.contains("Tweede Pinksterdag 2026-05-25"))
        XCTAssertTrue(h26.contains("Eerste Kerstdag 2026-12-25"))
        XCTAssertTrue(h26.contains("Tweede Kerstdag 2026-12-26"))
        XCTAssertTrue(h26.contains("Nieuwjaarsdag 2026-01-01"))
    }

    func testKingsDayMovesToTheSaturdayWhenItIsASundayAndWasKoninginnedagBefore2014() {
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2025), day(2025, 4, 26), "27 april 2025 is een zondag")
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2031), day(2031, 4, 26))
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2026), day(2026, 4, 27))
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2014), day(2014, 4, 26), "27 april 2014 was een zondag")
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2013), day(2013, 4, 30), "Koninginnedag")
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2008), day(2008, 4, 30))
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2009), day(2009, 4, 30))
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2010), day(2010, 4, 30))
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2008).weekday, 4, "30 april 2008 was een woensdag")
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2004), day(2004, 4, 30))
        XCTAssertEqual(DutchHolidays.kingsDay(year: 1999), day(1999, 4, 30))
        XCTAssertEqual(DutchHolidays.kingsDay(year: 2000), day(2000, 4, 29), "30 april 2000 was een zondag")
        XCTAssertEqual(DutchHolidays.holidays(year: 2013).first { $0.day == day(2013, 4, 30) }?.name, "Koninginnedag")
        XCTAssertEqual(DutchHolidays.holidays(year: 2014).first { $0.day == day(2014, 4, 26) }?.name, "Koningsdag")
    }

    func testAStandardHolidayCanBeSwitchedOff() {
        var settings = HolidaySettings()
        settings.enabled.remove(.easterSunday)
        let easter = DutchHolidays.easter(year: 2026)
        XCTAssertFalse(DutchHolidays.isHoliday(easter, settings: settings))
        XCTAssertTrue(DutchHolidays.isHoliday(easter.adding(days: 1), settings: settings), "Tweede Paasdag blijft")
        XCTAssertEqual(DutchHolidays.holidays(year: 2026, settings: settings).count, 8)
        var none = HolidaySettings()
        none.enabled = []
        XCTAssertTrue(DutchHolidays.holidays(year: 2026, settings: none).isEmpty)
        XCTAssertFalse(DutchHolidays.isHoliday(day(2026, 12, 25), settings: none))
    }

    func testTheThreeOptionalHolidaysAreOffByDefault() {
        XCTAssertFalse(DutchHolidays.isHoliday(day(2026, 4, 3)), "Goede Vrijdag 2026 is 3 april")
        XCTAssertFalse(DutchHolidays.isHoliday(day(2026, 5, 5)), "Bevrijdingsdag")
        XCTAssertFalse(DutchHolidays.isHoliday(day(2026, 12, 31)), "Oudejaarsdag")
        var on = HolidaySettings()
        on.enabled.formUnion([.goodFriday, .liberationDay, .newYearsEve])
        XCTAssertTrue(DutchHolidays.isHoliday(day(2026, 4, 3), settings: on))
        XCTAssertTrue(DutchHolidays.isHoliday(day(2026, 5, 5), settings: on))
        XCTAssertTrue(DutchHolidays.isHoliday(day(2026, 12, 31), settings: on))
        XCTAssertEqual(DutchHolidays.holidays(year: 2026, settings: on).count, 12)
        XCTAssertEqual(DutchHolidays.day(of: .goodFriday, year: 2026), day(2026, 4, 3))
    }

    func testBevrijdingsdagThatIsAlsoAscensionStaysAHolidayWhileLiberationDayIsOff() {
        // Hemelvaart (39 dagen na Pasen) kan op 5 mei vallen. Zoek zo'n jaar en controleer dat die dag een feestdag blijft terwijl
        // Bevrijdingsdag (dezelfde datum) uitstaat: de datum van Bevrijdingsdag mag Hemelvaart niet verdringen.
        for year in 2024...2400 where DutchHolidays.day(of: .ascension, year: year) == day(year, 5, 5) {
            XCTAssertTrue(DutchHolidays.isHoliday(day(year, 5, 5)), "Hemelvaart op 5 mei in \(year)")
            return
        }
        XCTFail("geen jaar gevonden waarin Hemelvaart op 5 mei valt")
    }

    func testCustomHolidaysAreHolidaysToo() {
        var settings = HolidaySettings()
        settings.custom = [day(2026, 12, 5)]
        XCTAssertTrue(DutchHolidays.isHoliday(day(2026, 12, 5), settings: settings))
        XCTAssertFalse(DutchHolidays.isHoliday(day(2027, 12, 5), settings: settings), "alleen dat jaar")
        let list = DutchHolidays.holidays(year: 2026, settings: settings)
        XCTAssertEqual(list.count, 10)
        XCTAssertEqual(list.first { $0.day == day(2026, 12, 5) }?.name, "Eigen feestdag")
        XCTAssertEqual(DutchHolidays.holidays(year: 2027, settings: settings).count, 9)
    }

    func testTheTwelveKindsHaveTitlesAndACalendarOrder() {
        XCTAssertEqual(HolidayKind.allCases.count, 12)
        XCTAssertEqual(HolidayKind.standard.count, 9)
        XCTAssertEqual(Set(HolidayKind.calendarOrder), Set(HolidayKind.allCases))
        XCTAssertEqual(HolidayKind.calendarOrder.count, 12)
        let year = 2026
        let dates = HolidayKind.calendarOrder.map { DutchHolidays.day(of: $0, year: year) }
        XCTAssertEqual(dates, dates.sorted(), "de lijst op het scherm loopt door het jaar")
        XCTAssertEqual(Set(HolidayKind.allCases.map { $0.title }).count, 12)
        XCTAssertEqual(HolidayKind.newYearsEve.title, "Oudejaarsdag")
        XCTAssertEqual(HolidayKind.pentecostMonday.title, "Tweede Pinksterdag")
        XCTAssertFalse(HolidayKind.standard.contains(.newYearsEve))
    }
}
