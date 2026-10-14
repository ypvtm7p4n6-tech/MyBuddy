import XCTest
import Foundation
@testable import MyBuddyCore

/// Het salarisschema: maandelijks, elke N weken of elke N dagen (`SalarySchedule.swift`). Alle verwachte waarden zijn met
/// de hand uitgerekend (data door op te tellen vanaf de ankerdatum, bedragen met de hand), niet met de motor.
/// Niets hangt van de klok af.
final class SalaryScheduleTests: XCTestCase {
    // MARK: Hulpjes

    private func ym(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month) }
    private func cd(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay { CalendarDay(year: year, month: month, day: day) }
    private func cents(_ value: Double) -> Int { engCents(value) }

    /// Gegevens met een vast bedrag per uitbetaling.
    private func data(start: YearMonth = YearMonth(year: 2026, month: 1), _ schedule: SalarySchedule, _ interval: Int,
                      anchor: CalendarDay?, amount: Double = 1_000, payDay: Int = 25) -> FinanceData {
        var d = FinanceData(startMonth: start)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: amount, hourlyRate: 0, hoursPerWeek: 0, payDay: payDay)
        d.salary.setSchedule(schedule, interval: interval, anchor: anchor)
        return d
    }

    /// Gegevens met een uurloon van 20 en 36 uur per week.
    private func hourly(start: YearMonth = YearMonth(year: 2026, month: 1), _ schedule: SalarySchedule, _ interval: Int,
                        anchor: CalendarDay?, rate: Double = 20, hours: Double = 36, payDay: Int = 25) -> FinanceData {
        var d = FinanceData(startMonth: start)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: rate, hoursPerWeek: hours, payDay: payDay)
        d.salary.setSchedule(schedule, interval: interval, anchor: anchor)
        return d
    }

    private func days(_ d: FinanceData, _ year: Int, _ month: Int) -> [Int] { d.salaryPayDays(in: ym(year, month)) }

    // MARK: Kalenderdagen

    func testDayNumbersMatchKnownDates() {
        XCTAssertEqual(cd(1970, 1, 1).dayNumber, 0)
        XCTAssertEqual(cd(1969, 12, 31).dayNumber, -1)
        XCTAssertEqual(cd(2000, 3, 1).dayNumber, 11_017)       // 2000-01-01 is 10957, plus 31 en 29 dagen
        XCTAssertEqual(cd(2026, 10, 23).dayNumber, 20_749)     // 56 jaar (14 schrikkeldagen) is 20454, plus 295
        XCTAssertEqual(CalendarDay(dayNumber: 20_749), cd(2026, 10, 23))
        XCTAssertEqual(CalendarDay(dayNumber: 0), cd(1970, 1, 1))
        XCTAssertEqual(CalendarDay(dayNumber: -1), cd(1969, 12, 31))
    }

    func testDayNumbersAgreeWithTheCalendarForThreeCenturies() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var date = utc.date(from: DateComponents(year: 1900, month: 1, day: 1, hour: 12))!
        var expected = -25_567   // 1970 - 1900 = 70 jaar: 70 x 365 + 17 schrikkeldagen
        var mismatches = 0
        for _ in 0..<(301 * 366) {
            let c = utc.dateComponents([.year, .month, .day], from: date)
            let day = CalendarDay(year: c.year!, month: c.month!, day: c.day!)
            if day.dayNumber != expected || CalendarDay(dayNumber: expected) != day { mismatches += 1 }
            if c.year! > 2200 { break }
            date = date.addingTimeInterval(86_400)
            expected += 1
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testDaysOutsideTheMonthAreClamped() {
        XCTAssertEqual(cd(2027, 2, 31).day, 28)
        XCTAssertEqual(cd(2028, 2, 31).day, 29)
        XCTAssertEqual(cd(1900, 2, 29).day, 28)       // 1900 is geen schrikkeljaar
        XCTAssertEqual(cd(2000, 2, 29).day, 29)
        XCTAssertEqual(cd(2100, 2, 29).day, 28)
        XCTAssertEqual(cd(2026, 13, 5).month, 12)
        XCTAssertEqual(cd(2026, 0, 5).month, 1)
        XCTAssertEqual(cd(2026, 4, 0).day, 1)
    }

    func testCalendarDayKeyAndCoding() throws {
        XCTAssertEqual(cd(2026, 10, 23).key, "2026-10-23")
        XCTAssertEqual(cd(2026, 1, 5).key, "2026-01-05")
        XCTAssertEqual(cd(5, 3, 9).key, "0005-03-09")
        XCTAssertEqual(CalendarDay(key: "2026-10-23"), cd(2026, 10, 23))
        XCTAssertNil(CalendarDay(key: "2026-02-30"))
        XCTAssertNil(CalendarDay(key: "2026-13-01"))
        XCTAssertNil(CalendarDay(key: "26-10-23"))
        XCTAssertNil(CalendarDay(key: "iets anders"))
        let json = try JSONEncoder().encode([cd(2026, 10, 23)])
        XCTAssertEqual(String(data: json, encoding: .utf8), "[\"2026-10-23\"]")
        XCTAssertEqual(try JSONDecoder().decode([CalendarDay].self, from: json), [cd(2026, 10, 23)])
        XCTAssertThrowsError(try JSONDecoder().decode([CalendarDay].self, from: Data("[\"morgen\"]".utf8)))
    }

    func testCalendarDayFromADateUsesTheLocalDay() {
        let cal = YearMonth.calendar
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 59))!
        let early = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 0, minute: 1))!
        XCTAssertEqual(CalendarDay(date: late), cd(2026, 10, 23))
        XCTAssertEqual(CalendarDay(date: early), cd(2026, 10, 23))
        XCTAssertEqual(cd(2026, 10, 23).date(), ym(2026, 10).date(day: 23))
        XCTAssertEqual(cd(2026, 10, 23).adding(days: 9), cd(2026, 11, 1))
        XCTAssertEqual(cd(2026, 3, 1).adding(days: -1), cd(2026, 2, 28))
    }

    func testFloorAndCeilingDivisionWithNegativeNumbers() {
        XCTAssertEqual(CivilDays.floorDiv(7, 3), 2)
        XCTAssertEqual(CivilDays.floorDiv(-7, 3), -3)
        XCTAssertEqual(CivilDays.floorDiv(-6, 3), -2)
        XCTAssertEqual(CivilDays.ceilDiv(7, 3), 3)
        XCTAssertEqual(CivilDays.ceilDiv(-7, 3), -2)
        XCTAssertEqual(CivilDays.ceilDiv(-6, 3), -2)
        XCTAssertEqual(CivilDays.ceilDiv(0, 28), 0)
    }

    // MARK: De dagen van een schema

    /// Elke 4 weken vanaf vrijdag 23 oktober 2026: 13 uitbetalingen per jaar, in juli twee.
    private let fourWeeklyOf2026: [[Int]] = [[16], [13], [13], [10], [8], [5], [3, 31], [28], [25], [23], [20], [18]]
    private let fourWeeklyOf2027: [[Int]] = [[15], [12], [12], [9], [7], [4], [2, 30], [27], [24], [22], [19], [17]]

    func testEveryFourWeeksHasThirteenPayoutsAPerYearAndOneMonthWithTwo() {
        let d = data(.weeks, 4, anchor: cd(2026, 10, 23))
        for month in 1...12 {
            XCTAssertEqual(days(d, 2026, month), fourWeeklyOf2026[month - 1], "2026-\(month)")
            XCTAssertEqual(days(d, 2027, month), fourWeeklyOf2027[month - 1], "2027-\(month)")
        }
        XCTAssertEqual(fourWeeklyOf2026.flatMap { $0 }.count, 13)
        XCTAssertEqual(fourWeeklyOf2027.flatMap { $0 }.count, 13)
        // Het bedrag per jaar: 13 x 1000, en een maand met twee uitbetalingen heeft er 2000.
        var total2026 = 0.0
        for month in 1...12 { total2026 += d.salaryAmount(in: ym(2026, month)) }
        XCTAssertEqual(total2026, 13_000)
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 7)), 2_000)
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 8)), 1_000)
        XCTAssertEqual(d.income(in: ym(2026, 7)), 2_000)
    }

    func testTheAnchorMayLieInThePastOrInTheFuture() {
        // 364 dagen (13 cycli van 28) voor en na 23 oktober 2026, en 728 dagen ervoor: dezelfde uitbetalingen.
        for anchor in [cd(2025, 10, 24), cd(2026, 10, 23), cd(2027, 10, 22), cd(2024, 10, 25), cd(2026, 1, 16), cd(2027, 12, 17)] {
            let d = data(.weeks, 4, anchor: anchor)
            for month in 1...12 {
                XCTAssertEqual(days(d, 2026, month), fourWeeklyOf2026[month - 1], "anker \(anchor.key), 2026-\(month)")
                XCTAssertEqual(days(d, 2027, month), fourWeeklyOf2027[month - 1], "anker \(anchor.key), 2027-\(month)")
            }
        }
        // Een anker dat 7 dagen later valt (zelfde cyclus verschoven): 30 oktober 2026, 7 dagen na 23 oktober.
        XCTAssertEqual(days(data(.weeks, 4, anchor: cd(2026, 10, 30)), 2026, 10), [2, 30])
        XCTAssertEqual(days(data(.weeks, 4, anchor: cd(2026, 10, 30)), 2026, 7), [10])
        // Een anker ver in de toekomst (2030-01-04 ligt 1169 dagen = 41 x 28 + 21 na 23 oktober 2026, dus de cyclus valt
        // 21 dagen later of, wat hetzelfde is, 7 dagen eerder): 16 oktober 2026.
        XCTAssertEqual(days(data(.weeks, 4, anchor: cd(2030, 1, 4)), 2026, 10), [16])
    }

    /// De uitbetalingen van `schedule` in `month`, op een andere manier uitgerekend dan de motor: stap voor stap met
    /// `Calendar` vanaf de ankerdatum, in beide richtingen.
    private func bruteForceDays(_ anchor: CalendarDay, cycle: Int, in month: YearMonth) -> [Int] {
        let cal = YearMonth.calendar
        let origin = anchor.date(calendar: cal)
        var result: [Int] = []
        let span = cal.dateComponents([.day], from: origin, to: month.firstDay).day ?? 0
        let around = span / cycle
        for k in (around - 3)...(around + 3 + 31 / cycle) {
            guard let date = cal.date(byAdding: .day, value: k * cycle, to: origin) else { continue }
            if YearMonth(date: date, calendar: cal) == month { result.append(cal.component(.day, from: date)) }
        }
        return result.sorted()
    }

    func testPayDaysAgreeWithAStepByStepCalendarCalculation() {
        var r = EngRandom(seed: 4_242)
        var checked = 0
        for _ in 0..<300 {
            let weeks = r.chance(50)
            let interval = weeks ? r.int(1...52) : r.int(1...366)
            let anchor = CalendarDay(dayNumber: cd(2026, 6, 15).dayNumber + r.int(-2_000...2_000))
            let d = data(start: ym(2000, 1), weeks ? .weeks : .days, interval, anchor: anchor)
            let cycle = weeks ? interval * 7 : interval
            for _ in 0..<6 {
                let month = ym(2026, 6).adding(r.int(-70...70))
                XCTAssertEqual(d.salaryPayDays(in: month), bruteForceDays(anchor, cycle: cycle, in: month),
                               "anker \(anchor.key), elke \(cycle) dagen, \(month.key)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 1_800)
    }

    func testEveryTwoWeeks() {
        // Vrijdag 2 oktober 2026, daarna 16 en 30 oktober: drie in één maand.
        let d = data(start: ym(2026, 9), .weeks, 2, anchor: cd(2026, 10, 2))
        XCTAssertEqual(days(d, 2026, 9), [4, 18])
        XCTAssertEqual(days(d, 2026, 10), [2, 16, 30])
        XCTAssertEqual(days(d, 2026, 11), [13, 27])
        XCTAssertEqual(days(d, 2026, 12), [11, 25])
        XCTAssertEqual(days(d, 2027, 1), [8, 22])
        XCTAssertEqual(days(d, 2027, 2), [5, 19])
        XCTAssertEqual(days(d, 2027, 3), [5, 19])
        // 26 uitbetalingen in 2027.
        var count = 0
        for month in 1...12 { count += days(d, 2027, month).count }
        XCTAssertEqual(count, 26)
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 10)), 3_000)
    }

    func testEveryWeek() {
        let d = data(start: ym(2026, 10), .weeks, 1, anchor: cd(2026, 10, 2))
        XCTAssertEqual(days(d, 2026, 10), [2, 9, 16, 23, 30])
        XCTAssertEqual(days(d, 2026, 11), [6, 13, 20, 27])
        XCTAssertEqual(days(d, 2026, 12), [4, 11, 18, 25])
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 10)), 5_000)
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 11)), 4_000)
    }

    func testEveryTenDays() {
        let d = data(start: ym(2026, 7), .days, 10, anchor: cd(2026, 10, 5))
        XCTAssertEqual(days(d, 2026, 7), [7, 17, 27])
        XCTAssertEqual(days(d, 2026, 8), [6, 16, 26])
        XCTAssertEqual(days(d, 2026, 9), [5, 15, 25])
        XCTAssertEqual(days(d, 2026, 10), [5, 15, 25])
        XCTAssertEqual(days(d, 2026, 11), [4, 14, 24])
        XCTAssertEqual(days(d, 2026, 12), [4, 14, 24])
        XCTAssertEqual(days(d, 2027, 1), [3, 13, 23])
        XCTAssertEqual(days(d, 2027, 2), [2, 12, 22])
        XCTAssertEqual(days(d, 2027, 3), [4, 14, 24])
    }

    func testAThirtyOneDayCycleHasMonthsWithoutAnyPayout() {
        let d = data(start: ym(2026, 9), .days, 31, anchor: cd(2026, 10, 31))
        XCTAssertEqual(days(d, 2026, 9), [30])
        XCTAssertEqual(days(d, 2026, 10), [31])
        XCTAssertEqual(days(d, 2026, 11), [])
        XCTAssertEqual(days(d, 2026, 12), [1])
        XCTAssertEqual(days(d, 2027, 1), [1])
        XCTAssertEqual(days(d, 2027, 2), [1])
        XCTAssertEqual(days(d, 2027, 3), [4])
        XCTAssertEqual(days(d, 2027, 4), [4])
        XCTAssertEqual(days(d, 2027, 5), [5])
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 11)), 0)
        XCTAssertEqual(d.income(in: ym(2026, 11)), 0)
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 12)), 1_000)
    }

    func testAnAnchorInAShortMonth() {
        // 28 februari 2027 (geen schrikkeljaar), elke 4 weken: 3 en 31 januari, 6 december ervoor.
        let d = data(start: ym(2026, 12), .weeks, 4, anchor: cd(2027, 2, 28))
        XCTAssertEqual(days(d, 2026, 12), [6])
        XCTAssertEqual(days(d, 2027, 1), [3, 31])
        XCTAssertEqual(days(d, 2027, 2), [28])
        XCTAssertEqual(days(d, 2027, 3), [28])
        XCTAssertEqual(days(d, 2027, 4), [25])
        // De lege dag van de anker valt ook goed als het anker via een niet bestaande dag is ingevuld.
        XCTAssertEqual(data(.weeks, 4, anchor: CalendarDay(year: 2027, month: 2, day: 31)).salary.anchor, cd(2027, 2, 28))
    }

    func testLeapYear() {
        // 29 februari 2028, elke 4 weken: 1 februari, 4 januari ervoor, 28 maart erna.
        let a = data(start: ym(2028, 1), .weeks, 4, anchor: cd(2028, 2, 29))
        XCTAssertEqual(days(a, 2028, 1), [4])
        XCTAssertEqual(days(a, 2028, 2), [1, 29])
        XCTAssertEqual(days(a, 2028, 3), [28])
        // Elke 14 dagen vanaf 15 februari 2028: 1, 15 en 29 februari, drie in één maand.
        let b = data(start: ym(2028, 1), .days, 14, anchor: cd(2028, 2, 15))
        XCTAssertEqual(days(b, 2028, 1), [4, 18])
        XCTAssertEqual(days(b, 2028, 2), [1, 15, 29])
        XCTAssertEqual(days(b, 2028, 3), [14, 28])
        // Het jaar daarna: 15 februari 2028 + 14 x 26 = 364 dagen. Van 15 februari 2028 tot 15 februari 2029 zijn het 366
        // dagen (de schrikkeldag zit ertussen), dus 364 dagen is twee dagen eerder: 13 februari 2029, daarna 27 februari.
        XCTAssertEqual(days(b, 2029, 2), [13, 27])
    }

    func testTheNewYearAndTheStartMonthInTheMiddleOfACycle() {
        // De startmaand is november 2026; 23 oktober is een uitbetaaldatum maar ligt voor de startmaand: telt niet.
        let d = data(start: ym(2026, 11), .weeks, 4, anchor: cd(2026, 10, 23))
        XCTAssertEqual(days(d, 2026, 10), [])
        XCTAssertEqual(d.salaryPayDates(in: ym(2026, 10)), [])
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 10)), 0)
        XCTAssertEqual(days(d, 2026, 11), [20])
        XCTAssertEqual(days(d, 2026, 12), [18])
        XCTAssertEqual(days(d, 2027, 1), [15])
        XCTAssertEqual(d.salaryPayDates(in: ym(2027, 1)), [ym(2027, 1).date(day: 15)])
        // Dezelfde cyclus in een andere startmaand: de uitbetalingen liggen vast, ongeacht wanneer de gegevens beginnen.
        XCTAssertEqual(days(data(start: ym(2026, 1), .weeks, 4, anchor: cd(2026, 10, 23)), 2026, 12), [18])
        XCTAssertEqual(days(data(start: ym(2026, 12), .weeks, 4, anchor: cd(2026, 10, 23)), 2026, 12), [18])
    }

    func testTheDefaultAnchorIsThePayDayOfTheStartMonth() {
        var d = data(start: ym(2026, 10), .weeks, 1, anchor: nil)
        XCTAssertNil(d.salary.anchor)
        XCTAssertEqual(d.salaryAnchor(), cd(2026, 10, 25))
        XCTAssertEqual(days(d, 2026, 10), [4, 11, 18, 25])
        XCTAssertEqual(days(d, 2026, 11), [1, 8, 15, 22, 29])
        // Elke 4 weken vanaf de 25e van de startmaand: 25 oktober, 22 november, 20 december, 17 januari.
        d.salary.setSchedule(.weeks, interval: 4)
        XCTAssertEqual(days(d, 2026, 10), [25])
        XCTAssertEqual(days(d, 2026, 11), [22])
        XCTAssertEqual(days(d, 2026, 12), [20])
        XCTAssertEqual(days(d, 2027, 1), [17])
        // De salarisdag 31 in een startmaand van 28 dagen: het anker is de laatste dag van die maand.
        let short = data(start: ym(2027, 2), .weeks, 4, anchor: nil, payDay: 31)
        XCTAssertEqual(short.salaryAnchor(), cd(2027, 2, 28))
        XCTAssertEqual(days(short, 2027, 2), [28])
    }

    func testTheMonthlyScheduleKeepsItsPayDayAndShortMonths() {
        let d = data(.monthly, 1, anchor: nil, payDay: 31)
        XCTAssertEqual(days(d, 2026, 1), [31])
        XCTAssertEqual(days(d, 2026, 2), [28])
        XCTAssertEqual(days(d, 2026, 4), [30])
        XCTAssertEqual(days(d, 2028, 2), [29])
        XCTAssertEqual(d.salaryDay(), 31)
        XCTAssertEqual(d.salaryDay(in: ym(2026, 2)), 31)   // klemt pas bij het plaatsen op de maand
        // Een kapotte dag wordt netjes geklemd.
        let broken = data(.monthly, 1, anchor: nil, payDay: 99)
        XCTAssertEqual(days(broken, 2026, 6), [30])
        XCTAssertEqual(days(data(.monthly, 1, anchor: nil, payDay: -4), 2026, 6), [1])
    }

    func testTheIntervalIsClamped() {
        var s = SalarySettings()
        s.setSchedule(.weeks, interval: 0)
        XCTAssertEqual(s.interval, 1)
        s.setSchedule(.weeks, interval: 99)
        XCTAssertEqual(s.interval, 52)
        s.setSchedule(.days, interval: 999)
        XCTAssertEqual(s.interval, 366)
        s.setSchedule(.days, interval: -3)
        XCTAssertEqual(s.interval, 1)
        s.setSchedule(.monthly, interval: 14)
        XCTAssertEqual(s.interval, 1)
        // Ook een kapotte waarde die rechtstreeks is ingevuld wordt bij het lezen geklemd.
        s.schedule = .weeks
        s.interval = 400
        XCTAssertEqual(s.cycleInterval, 52)
        XCTAssertEqual(s.cycleDays, 364)
        s.schedule = .days
        s.interval = 0
        XCTAssertEqual(s.cycleInterval, 1)
        XCTAssertEqual(s.cycleDays, 1)
        s.schedule = .monthly
        XCTAssertNil(s.cycleDays)
    }

    func testEveryDayAndTheLongestCycle() {
        let daily = data(start: ym(2026, 2), .days, 1, anchor: cd(2026, 2, 10))
        XCTAssertEqual(days(daily, 2026, 2), Array(1...28))
        XCTAssertEqual(days(daily, 2028, 2), Array(1...29))
        XCTAssertEqual(daily.salaryAmount(in: ym(2026, 2)), 28_000)
        // Elke 366 dagen: één keer per jaar, hooguit. 15 maart 2026 + 366 dagen = 16 maart 2027.
        let yearly = data(start: ym(2026, 1), .days, 366, anchor: cd(2026, 3, 15))
        var count = 0
        for month in 1...12 { count += days(yearly, 2026, month).count }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(days(yearly, 2026, 3), [15])
        XCTAssertEqual(days(yearly, 2027, 3), [16])
        XCTAssertEqual(CalendarDay(dayNumber: cd(2026, 3, 15).dayNumber + 366), cd(2027, 3, 16))
    }

    // MARK: Bedragen

    func testAFixedAmountIsPerPayout() {
        let d = data(.weeks, 4, anchor: cd(2026, 10, 23), amount: 1_234.56)
        XCTAssertEqual(d.salary.payoutAmount(), 1_234.56)
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 7)), 2_469.12)
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 8)), 1_234.56)
    }

    func testHourlyPayoutsArePaidPerCycleAndRoundedPerPayout() {
        // 20 per uur, 36 uur per week.
        XCTAssertEqual(hourly(.weeks, 4, anchor: cd(2026, 10, 23)).salary.payoutAmount(), 2_880)   // 20 x 36 x 4
        XCTAssertEqual(hourly(.weeks, 2, anchor: cd(2026, 10, 23)).salary.payoutAmount(), 1_440)
        XCTAssertEqual(hourly(.weeks, 1, anchor: cd(2026, 10, 23)).salary.payoutAmount(), 720)
        XCTAssertEqual(hourly(.days, 14, anchor: cd(2026, 10, 23)).salary.payoutAmount(), 1_440)
        // Elke 10 dagen: 20 x 36 x 10 / 7 = 1028,5714... en dus 1028,57 per uitbetaling.
        let tenDays = hourly(start: ym(2026, 7), .days, 10, anchor: cd(2026, 10, 5))
        XCTAssertEqual(tenDays.salary.payoutAmount(), 1_028.57)
        // Drie uitbetalingen in december (4, 14 en 24): de som van de afgeronde bedragen, 3 x 1028,57 = 3085,71.
        XCTAssertEqual(tenDays.salaryAmount(in: ym(2026, 12)), 3_085.71)
        XCTAssertEqual(tenDays.income(in: ym(2026, 12)), 3_085.71)
        // Een uurloon met centen: 21,55 x 37,5 x 10 / 7 = 1154,4642... en dus 1154,46.
        let odd = hourly(start: ym(2026, 7), .days, 10, anchor: cd(2026, 10, 5), rate: 21.55, hours: 37.5)
        XCTAssertEqual(odd.salary.payoutAmount(), 1_154.46)
        XCTAssertEqual(odd.salaryAmount(in: ym(2026, 12)), 3_463.38)   // 3 x 1154,46
        // Het maandelijkse uurloon blijft zoals het was: 20 x 36 x 52 / 12 = 3120.
        XCTAssertEqual(hourly(.monthly, 1, anchor: nil).salary.payoutAmount(), 3_120)
    }

    func testMonthlyTotalsAreTheSumOfTheRoundedPayouts() {
        // 10 dagen, uurloon 17,33 en 33 uur: 17,33 x 33 = 571,89 per week, x 10 / 7 = 816,9857... Elke uitbetaling wordt
        // afgerond (816,99), dan opgeteld.
        let d = hourly(start: ym(2026, 7), .days, 10, anchor: cd(2026, 10, 5), rate: 17.33, hours: 33)
        let each = d.salary.payoutAmount()
        XCTAssertEqual(each, 816.99)
        XCTAssertEqual(cents(d.salaryAmount(in: ym(2026, 12))), 3 * cents(each))
        let payouts = d.salaryPayouts(in: ym(2026, 12), plan: d.plan(for: ym(2026, 12)))
        XCTAssertEqual(payouts.map(\.cents), [81_699, 81_699, 81_699])
        XCTAssertEqual(payouts.map(\.day), [4, 14, 24])
        XCTAssertEqual(payouts.reduce(0) { $0 + $1.cents }, cents(d.salaryAmount(in: ym(2026, 12))))
    }

    // MARK: Overschrijvingen per maand

    func testASalaryOverrideIsTheTotalOfTheMonthSpreadOverThePayouts() {
        var d = data(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23))
        // Juli heeft twee uitbetalingen: 3000 wordt 1500 + 1500.
        d.editPlan(ym(2026, 7)) { $0.salaryOverride = 3_000 }
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 7)), 3_000)
        XCTAssertEqual(d.salaryPayouts(in: ym(2026, 7), plan: d.plan(for: ym(2026, 7))).map(\.cents), [150_000, 150_000])
        // 1000,01 over twee: de restcent gaat naar de eerste uitbetaling.
        d.editPlan(ym(2026, 7)) { $0.salaryOverride = 1_000.01 }
        XCTAssertEqual(d.salaryPayouts(in: ym(2026, 7), plan: d.plan(for: ym(2026, 7))).map(\.cents), [50_001, 50_000])
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 7)), 1_000.01)
        // Een maand met één uitbetaling: het totaal is de uitbetaling.
        d.editPlan(ym(2026, 8)) { $0.salaryOverride = 777.77 }
        XCTAssertEqual(d.salaryPayouts(in: ym(2026, 8), plan: d.plan(for: ym(2026, 8))).map(\.cents), [77_777])
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 8)), 777.77)
        // Nul: geen salaris in die maand.
        d.editPlan(ym(2026, 9)) { $0.salaryOverride = 0 }
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 9)), 0)
        XCTAssertEqual(d.dayEvents(in: ym(2026, 9), asOf: day(ym(2026, 9), 1)).filter { $0.kind == .salary }.count, 0)
        // Drie uitbetalingen (elke 14 dagen in oktober 2026: 2, 16, 30): 1000,01 is 33333 + 33333 + 33333 + 2 centen.
        var e = data(start: ym(2026, 9), .weeks, 2, anchor: cd(2026, 10, 2))
        e.editPlan(ym(2026, 10)) { $0.salaryOverride = 1_000.01 }
        XCTAssertEqual(e.salaryPayouts(in: ym(2026, 10), plan: e.plan(for: ym(2026, 10))).map(\.cents), [33_334, 33_334, 33_333])
        XCTAssertEqual(e.salaryAmount(in: ym(2026, 10)), 1_000.01)
    }

    func testHoursOverrideIsTheTotalOfTheMonthSpreadOverThePayouts() {
        var d = hourly(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23))
        // Zonder overschrijving: twee uitbetalingen van 2880 in juli.
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 7)), 5_760)
        XCTAssertEqual(d.salaryHours(in: ym(2026, 7)), 288)     // 2 x 36 x 4
        XCTAssertEqual(d.salaryHours(in: ym(2026, 8)), 144)
        XCTAssertEqual(d.scheduledSalary(in: ym(2026, 7)), 5_760)
        // 100 uur in juli: 20 x 100 = 2000, dus twee keer 1000.
        d.editPlan(ym(2026, 7)) { $0.hoursOverride = 100 }
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 7)), 2_000)
        XCTAssertEqual(d.salaryPayouts(in: ym(2026, 7), plan: d.plan(for: ym(2026, 7))).map(\.cents), [100_000, 100_000])
        XCTAssertEqual(d.salaryHours(in: ym(2026, 7)), 100)
        XCTAssertEqual(d.scheduledSalary(in: ym(2026, 7)), 5_760, "zonder overschrijving, voor de beginwaarde")
        // 101 uur: 2020 over twee is 1010 + 1010; 20,01 per uur x 101 voor restcenten: 2021,01 is 1010,51 + 1010,50.
        var odd = hourly(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23), rate: 20.01)
        odd.editPlan(ym(2026, 7)) { $0.hoursOverride = 101 }
        XCTAssertEqual(odd.salaryAmount(in: ym(2026, 7)), 2_021.01)
        XCTAssertEqual(odd.salaryPayouts(in: ym(2026, 7), plan: odd.plan(for: ym(2026, 7))).map(\.cents), [101_051, 101_050])
        // Bij een vast bedrag doen de uren niets (zoals altijd).
        var fixed = data(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23))
        fixed.editPlan(ym(2026, 7)) { $0.hoursOverride = 5 }
        XCTAssertEqual(fixed.salaryAmount(in: ym(2026, 7)), 2_000)
        // Het maandelijkse schema: uren x uurloon, zoals altijd.
        var monthly = hourly(start: ym(2026, 7), .monthly, 1, anchor: nil)
        monthly.editPlan(ym(2026, 7)) { $0.hoursOverride = 100 }
        XCTAssertEqual(monthly.salaryAmount(in: ym(2026, 7)), 2_000)
        XCTAssertEqual(monthly.salaryHours(in: ym(2026, 8)), 156)    // 36 x 52 / 12
    }

    func testAMonthWithoutAPayoutKeepsAnOverrideOnThePayDay() {
        // Elke 6 weken vanaf 23 oktober 2026: november heeft geen uitbetaling (23 oktober, dan 4 december).
        var d = data(start: ym(2026, 9), .weeks, 6, anchor: cd(2026, 10, 23), payDay: 25)
        XCTAssertEqual(days(d, 2026, 11), [])
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 11)), 0)
        // De gebruiker zet er zelf een salaris neer: dat komt op de salarisdag-terugval (de 25e) binnen.
        d.editPlan(ym(2026, 11)) { $0.salaryOverride = 500 }
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 11)), 500)
        let payouts = d.salaryPayouts(in: ym(2026, 11), plan: d.plan(for: ym(2026, 11)))
        XCTAssertEqual(payouts.map(\.day), [25])
        XCTAssertEqual(payouts.map(\.cents), [50_000])
        XCTAssertEqual(payouts.map(\.id), ["salary-2026-11-25"])
        XCTAssertEqual(d.dayEvents(in: ym(2026, 11), asOf: day(ym(2026, 11), 1)).filter { $0.kind == .salary }.map(\.day), [25])
        XCTAssertEqual(d.monthLedger(ym(2026, 11), asOf: day(ym(2026, 11), 1)).income, 500)
        XCTAssertTrue(d.monthLedger(ym(2026, 11), asOf: day(ym(2026, 11), 1)).overviewReconciles)
        // Uren zonder uitbetaling betalen niets.
        var h = hourly(start: ym(2026, 9), .weeks, 6, anchor: cd(2026, 10, 23))
        h.editPlan(ym(2026, 11)) { $0.hoursOverride = 100 }
        XCTAssertEqual(h.salaryAmount(in: ym(2026, 11)), 0)
    }

    // MARK: Gebeurtenissen en de dagboekhouding

    /// Start juli 2026, elke 4 weken 1000 (3 en 31 juli, 28 augustus, 25 september), huur 900 op de 1e, een pot die 10% van
    /// het salaris inlegt, banksaldo 500 aan het eind van 30 juni.
    private func ledgerData() -> (data: FinanceData, pot: Pot) {
        var d = data(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23))
        var pot = Pot(name: "Sparen", monthlyContribution: 0, startMonth: ym(2026, 7))
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        pot.contributionBasis = .salary
        d.addPot(pot, openingBalance: 0, now: day(ym(2026, 7), 1))
        d.addRecurringLine(MoneyLine(name: "Huur", amount: 900, day: 1), kind: .expense, in: ym(2026, 7))
        d.addBankSnapshot(balance: 500, note: "Begin", date: engTime(ym(2026, 6), 30, hour: 20))
        return (d, pot)
    }

    func testEachPayoutIsItsOwnEventWithAStableIdPerDate() {
        let (d, _) = ledgerData()
        let july = d.dayEvents(in: ym(2026, 7), asOf: day(ym(2026, 7), 15)).filter { $0.kind == .salary }
        XCTAssertEqual(july.map(\.id), ["salary-2026-07-03", "salary-2026-07-31"])
        XCTAssertEqual(july.map(\.day), [3, 31])
        XCTAssertEqual(july.map(\.bankAmount), [1_000, 1_000])
        XCTAssertEqual(july.map(\.isPlanned), [false, true])
        XCTAssertEqual(july.map(\.title), ["Salaris", "Salaris"])
        // Dezelfde id's bij een ander moment en na een nieuwe berekening.
        XCTAssertEqual(d.dayEvents(in: ym(2026, 7), asOf: day(ym(2026, 12), 1)).filter { $0.kind == .salary }.map(\.id),
                       ["salary-2026-07-03", "salary-2026-07-31"])
        XCTAssertEqual(d.eventsOnDay(day(ym(2026, 7), 31), asOf: day(ym(2026, 7), 15)).filter { $0.kind == .salary }.map(\.id),
                       ["salary-2026-07-31"])
        // Het maandelijkse schema houdt het oude id per maand.
        var monthly = d
        monthly.salary.setSchedule(.monthly)
        XCTAssertEqual(monthly.dayEvents(in: ym(2026, 7), asOf: day(ym(2026, 7), 15)).filter { $0.kind == .salary }.map(\.id),
                       ["salary-2026-07"])
        XCTAssertEqual(monthly.salaryPayouts(in: ym(2026, 7), plan: monthly.plan(for: ym(2026, 7))).map(\.day), [25])
    }

    func testTheLedgerOfAMonthWithTwoPayoutsReconcilesDayByDay() {
        let (d, pot) = ledgerData()
        let ledger = d.monthLedger(ym(2026, 7), asOf: day(ym(2026, 7), 31))
        // Salaris 2 x 1000, huur 900 op de 1e, 10% van het salaris (200) naar de pot op de eerste uitbetaling (de 3e).
        XCTAssertEqual(ledger.income, 2_000)
        XCTAssertEqual(ledger.planInflow, 2_000)
        XCTAssertEqual(ledger.inflow, 2_000)
        XCTAssertEqual(ledger.expensesTotal, 900)
        XCTAssertEqual(ledger.planToPots, 200)
        XCTAssertEqual(ledger.saved, 200)
        XCTAssertEqual(ledger.remaining, 900)       // 2000 - 900 - 200
        XCTAssertEqual(ledger.openingBank, 500)
        XCTAssertEqual(ledger.closingBank, 1_400)   // 500 - 900 + 1000 - 200 + 1000
        XCTAssertEqual(ledger.closingPots, 200)
        XCTAssertTrue(ledger.allReconciles)
        let byDay = ledger.days
        XCTAssertEqual(byDay[0].outflow, 900)
        XCTAssertEqual(byDay[0].bankBalance, -400)
        XCTAssertEqual(byDay[0].remainingSoFar, -900)
        XCTAssertEqual(byDay[2].inflow, 1_000)
        XCTAssertEqual(byDay[2].toPots, 200)
        XCTAssertEqual(byDay[2].bankBalance, 400)
        XCTAssertEqual(byDay[2].potsTotal, 200)
        XCTAssertEqual(byDay[2].remainingSoFar, -100)
        XCTAssertEqual(byDay[29].bankBalance, 400)
        XCTAssertEqual(byDay[30].inflow, 1_000)
        XCTAssertEqual(byDay[30].bankBalance, 1_400)
        XCTAssertEqual(byDay[30].remainingSoFar, 900)
        XCTAssertEqual(byDay.filter { $0.planInflow > 0 }.map(\.day), [3, 31])
        // De pot krijgt zijn inleg op de overschrijfdag, hetzelfde bedrag als de verdeling.
        XCTAssertEqual(d.allocation(pot.id, in: ym(2026, 7)), 200)
        XCTAssertEqual(d.transferDay(for: pot.id, in: ym(2026, 7)), 3)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(ym(2026, 7), 2)), 0)
        XCTAssertEqual(d.potBalance(pot.id, asOf: day(ym(2026, 7), 3)), 200)
        // Augustus: één uitbetaling op de 28e, 10% = 100 op dezelfde dag.
        let august = d.monthLedger(ym(2026, 8), asOf: day(ym(2026, 7), 31))
        XCTAssertEqual(august.income, 1_000)
        XCTAssertEqual(august.days.filter { $0.planInflow > 0 }.map(\.day), [28])
        XCTAssertEqual(august.days.filter { $0.planToPots > 0 }.map(\.day), [28])
        XCTAssertEqual(august.planToPots, 100)
        XCTAssertEqual(august.remaining, 0)         // 1000 - 900 - 100
        XCTAssertEqual(august.openingBank, 1_400)
        XCTAssertEqual(august.closingBank, 1_400 - 900 + 1_000 - 100)
        XCTAssertTrue(august.allReconciles)
        // November 2026 (20 november) en een maand zonder uitbetaling in het schema.
        let november = d.monthLedger(ym(2026, 11), asOf: day(ym(2026, 7), 31))
        XCTAssertEqual(november.days.filter { $0.planInflow > 0 }.map(\.day), [20])
        XCTAssertTrue(november.allReconciles)
    }

    func testAMonthWithoutPayoutsStillCloses() {
        var d = data(start: ym(2026, 9), .weeks, 6, anchor: cd(2026, 10, 23))
        d.addRecurringLine(MoneyLine(name: "Huur", amount: 900, day: 1), kind: .expense, in: ym(2026, 9))
        d.addBankSnapshot(balance: 3_000, note: "Begin", date: engTime(ym(2026, 8), 31, hour: 20))
        let november = d.monthLedger(ym(2026, 11), asOf: day(ym(2026, 9), 1))
        XCTAssertEqual(november.income, 0)
        XCTAssertEqual(november.inflow, 0)
        XCTAssertEqual(november.remaining, -900)
        XCTAssertTrue(november.allReconciles)
        XCTAssertEqual(november.days.filter { $0.planInflow > 0 }.count, 0)
        // De volgende maand (december) heeft de uitbetaling van de 4e.
        let december = d.monthLedger(ym(2026, 12), asOf: day(ym(2026, 9), 1))
        XCTAssertEqual(december.days.filter { $0.planInflow > 0 }.map(\.day), [4])
        XCTAssertEqual(december.income, 1_000)
        XCTAssertTrue(december.allReconciles)
        // Het banksaldo sluit over de hele reeks: elke dag een saldo, en eind november is het saldo gedaald.
        // 3000 - 900 + 1000 (11 sep), - 900 + 1000 (23 okt): 3200 aan het eind van oktober.
        XCTAssertEqual(d.bankBalance(at: ym(2026, 10)), 3_200)
        XCTAssertEqual(d.bankBalance(at: ym(2026, 11)), 2_300)
    }

    func testEverythingAgreesOnTheSameSalary() {
        let (d, _) = ledgerData()
        for month in ym(2026, 7).range(count: 14) {
            let ledger = d.monthLedger(month, asOf: day(ym(2026, 7), 1))
            let salary = d.salaryAmount(in: month)
            let events = d.dayEvents(in: month, asOf: day(ym(2026, 7), 1)).filter { $0.kind == .salary }
            XCTAssertEqual(cents(events.reduce(0) { $0 + $1.bankAmount }), cents(salary), month.key)
            XCTAssertEqual(cents(ledger.income), cents(salary), month.key)
            XCTAssertEqual(cents(d.income(in: month)), cents(salary), month.key)
            XCTAssertEqual(d.summary(of: month, current: ym(2026, 7)).income, salary, month.key)
            XCTAssertEqual(d.salaryPayDays(in: month), events.map(\.day), month.key)
            XCTAssertEqual(d.salaryPayDates(in: month).map { CalendarDay(date: $0).day }, events.map(\.day), month.key)
            XCTAssertTrue(ledger.allReconciles, month.key)
        }
        // Het hele jaar tegenover het aantal uitbetalingen (13 x 1000).
        var total = 0.0
        for month in ym(2026, 11).range(count: 12) { total += d.income(in: month) }
        XCTAssertEqual(total, 13_000)   // november 2026 t/m oktober 2027: 20 nov, 18 dec, 15 jan, ... 22 okt
    }

    // MARK: De salarisdag voor wat geen eigen dag heeft

    func testIncomeWithoutADayAndTransferDaysFollowTheFirstPayoutOfTheMonth() {
        var d = data(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23), payDay: 25)
        var pot = Pot(name: "Eigen dag", monthlyContribution: 50, startMonth: ym(2026, 7))
        pot.transferDay = 10
        let other = Pot(name: "Zonder dag", monthlyContribution: 60, startMonth: ym(2026, 7))
        d.addPot(pot, openingBalance: 0, now: day(ym(2026, 7), 1))
        d.addPot(other, openingBalance: 0, now: day(ym(2026, 7), 1))
        d.addRecurringLine(MoneyLine(name: "Bonus", amount: 250), kind: .income, in: ym(2026, 7))
        let bonus = d.plan(for: ym(2026, 7)).extraIncome[0]
        // Juli: eerste uitbetaling op de 3e. Augustus: de 28e.
        XCTAssertEqual(d.salaryDay(in: ym(2026, 7)), 3)
        XCTAssertEqual(d.salaryDay(in: ym(2026, 8)), 28)
        XCTAssertEqual(d.incomeDay(of: bonus, in: ym(2026, 7)), 3)
        XCTAssertEqual(d.incomeDay(of: d.plan(for: ym(2026, 8)).extraIncome[0], in: ym(2026, 8)), 28)
        XCTAssertEqual(d.incomeDay(of: bonus), 25, "zonder maand: de payDay-terugval")
        XCTAssertEqual(d.transferDay(for: other.id, in: ym(2026, 7)), 3)
        XCTAssertEqual(d.transferDay(for: other.id, in: ym(2026, 8)), 28)
        XCTAssertEqual(d.transferDay(for: pot.id, in: ym(2026, 7)), 10, "een eigen dag gaat voor")
        // Een eigen dag van de hele maandverdeling gaat voor.
        d.editPlan(ym(2026, 8)) { $0.transferDay = 12 }
        XCTAssertEqual(d.transferDay(for: other.id, in: ym(2026, 8)), 12)
        // Het inkomen komt in de gebeurtenissen op de eerste uitbetaling.
        let events = d.dayEvents(in: ym(2026, 7), asOf: day(ym(2026, 7), 1))
        XCTAssertEqual(events.first { $0.kind == .income }?.day, 3)
        XCTAssertEqual(events.first { $0.kind == .toPot && $0.potID == other.id }?.day, 3)
        // Een eigen dag van de regel zelf gaat voor.
        var withDay = bonus
        withDay.day = 15
        XCTAssertEqual(d.incomeDay(of: withDay, in: ym(2026, 7)), 15)
    }

    func testAMonthWithoutPayoutFallsBackToThePayDay() {
        var d = data(start: ym(2026, 9), .weeks, 6, anchor: cd(2026, 10, 23), payDay: 25)
        XCTAssertEqual(d.salaryDay(in: ym(2026, 11)), 25)
        XCTAssertEqual(d.salaryDay(in: ym(2026, 12)), 4)
        let pot = Pot(name: "Sparen", monthlyContribution: 40, startMonth: ym(2026, 9))
        d.addPot(pot, openingBalance: 0, now: day(ym(2026, 9), 1))
        XCTAssertEqual(d.transferDay(for: pot.id, in: ym(2026, 11)), 25)
        // De terugval klemt op de lengte van de maand.
        var short = data(start: ym(2027, 1), .days, 60, anchor: cd(2027, 1, 10), payDay: 31)
        XCTAssertEqual(short.salaryPayDays(in: ym(2027, 2)), [])    // 10 jan, 11 mrt
        XCTAssertEqual(short.salaryDay(in: ym(2027, 2)), 31)
        let p = Pot(name: "P", monthlyContribution: 10, startMonth: ym(2027, 1))
        short.addPot(p, openingBalance: 0, now: day(ym(2027, 1), 1))
        XCTAssertEqual(short.transferDay(for: p.id, in: ym(2027, 2)), 28)
    }

    func testPercentageOfSalaryUsesTheSumOfThePayoutsAndTheOtherBasisAddsExtraIncome() {
        var d = data(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23))
        var salaryPot = Pot(name: "Salaris", monthlyContribution: 0, startMonth: ym(2026, 7))
        salaryPot.contributionMode = .percentage
        salaryPot.contributionPercent = 10
        salaryPot.contributionBasis = .salary
        var allPot = Pot(name: "Alles", monthlyContribution: 0, startMonth: ym(2026, 7))
        allPot.contributionMode = .percentage
        allPot.contributionPercent = 10
        allPot.contributionBasis = .allIncome
        d.addPot(salaryPot, openingBalance: 0, now: day(ym(2026, 7), 1))
        d.addPot(allPot, openingBalance: 0, now: day(ym(2026, 7), 1))
        d.addRecurringLine(MoneyLine(name: "Extra", amount: 250, day: 12), kind: .income, in: ym(2026, 7))
        // Juli: salaris 2000, alles 2250. Augustus: 1000 en 1250.
        XCTAssertEqual(d.allocation(salaryPot.id, in: ym(2026, 7)), 200)
        XCTAssertEqual(d.allocation(allPot.id, in: ym(2026, 7)), 225)
        XCTAssertEqual(d.allocation(salaryPot.id, in: ym(2026, 8)), 100)
        XCTAssertEqual(d.allocation(allPot.id, in: ym(2026, 8)), 125)
        XCTAssertEqual(d.savedTotal(in: ym(2026, 7)), 425)
        XCTAssertEqual(d.remaining(in: ym(2026, 7)), 2_250 - 425)
        let ledger = d.monthLedger(ym(2026, 7), asOf: day(ym(2026, 7), 1))
        XCTAssertEqual(ledger.planToPots, 425)
        XCTAssertTrue(ledger.allReconciles)
        // De overschrijving op de overschrijfdag (de 3e) is dezelfde som.
        let transfers = d.dayEvents(in: ym(2026, 7), asOf: day(ym(2026, 7), 1)).filter { $0.kind == .toPot }
        XCTAssertEqual(transfers.map(\.day), [3, 3])
        XCTAssertEqual(transfers.reduce(0) { $0 + $1.potAmount }, 425)
        // Een ander schema verandert het inkomen en het percentage gaat mee.
        d.salary.setSchedule(.monthly)
        XCTAssertEqual(d.allocation(salaryPot.id, in: ym(2026, 7)), 100)
        XCTAssertEqual(d.allocation(allPot.id, in: ym(2026, 7)), 125)
    }

    // MARK: Volgende uitbetaling en omschrijving

    /// De dag van de eerstvolgende uitbetaling (de dag zelf, zonder tijdstip: de klok kan op die dag verzetten).
    private func next(_ d: FinanceData, _ date: Date) -> CalendarDay? {
        d.nextPayDate(after: date).map { CalendarDay(date: $0) }
    }

    func testNextPayDate() {
        let d = data(start: ym(2026, 1), .weeks, 4, anchor: cd(2026, 10, 23))
        // Strikt na de dag zelf: wat vandaag valt is al gebeurd.
        XCTAssertEqual(next(d, day(ym(2026, 10), 13)), cd(2026, 10, 23))
        XCTAssertEqual(next(d, day(ym(2026, 10), 22)), cd(2026, 10, 23))
        XCTAssertEqual(next(d, day(ym(2026, 10), 23)), cd(2026, 11, 20))
        XCTAssertEqual(next(d, engTime(ym(2026, 10), 23, hour: 0.5)), cd(2026, 11, 20))
        XCTAssertEqual(next(d, engTime(ym(2026, 10), 22, hour: 23.9)), cd(2026, 10, 23))
        XCTAssertEqual(next(d, day(ym(2026, 12), 18)), cd(2027, 1, 15))
        XCTAssertEqual(next(d, day(ym(2026, 12), 31)), cd(2027, 1, 15))
        // Voor de startmaand: de eerste uitbetaling vanaf de startmaand.
        let later = data(start: ym(2026, 11), .weeks, 4, anchor: cd(2026, 10, 23))
        XCTAssertEqual(next(later, day(ym(2026, 9), 1)), cd(2026, 11, 20))
        XCTAssertEqual(next(later, day(ym(2026, 10), 23)), cd(2026, 11, 20))
        // Maandelijks.
        let monthly = data(start: ym(2026, 1), .monthly, 1, anchor: nil, payDay: 25)
        XCTAssertEqual(next(monthly, day(ym(2026, 10), 24)), cd(2026, 10, 25))
        XCTAssertEqual(next(monthly, day(ym(2026, 10), 25)), cd(2026, 11, 25))
        XCTAssertEqual(next(monthly, day(ym(2026, 12), 31)), cd(2027, 1, 25))
        let last = data(start: ym(2026, 1), .monthly, 1, anchor: nil, payDay: 31)
        XCTAssertEqual(next(last, day(ym(2027, 1), 31)), cd(2027, 2, 28))
        XCTAssertEqual(next(last, day(ym(2027, 2), 28)), cd(2027, 3, 31))
        XCTAssertEqual(next(monthly, day(ym(2025, 3), 3)), cd(2026, 1, 25), "niet voor de startmaand")
        // Een cyclus van 366 dagen: de volgende ligt bijna een jaar verder.
        let yearly = data(start: ym(2026, 1), .days, 366, anchor: cd(2026, 3, 15))
        XCTAssertEqual(next(yearly, day(ym(2026, 3), 15)), cd(2027, 3, 16))
    }

    func testThePayoutDaysAsText() {
        let d = data(start: ym(2026, 1), .weeks, 2, anchor: cd(2026, 10, 2))
        XCTAssertEqual(d.salaryPayoutDaysText(in: ym(2026, 10)), "de 2e, de 16e en de 30e")
        XCTAssertEqual(d.salaryPayoutDaysText(in: ym(2026, 11)), "de 13e en de 27e")
        let one = data(start: ym(2026, 1), .monthly, 1, anchor: nil, payDay: 25)
        XCTAssertEqual(one.salaryPayoutDaysText(in: ym(2026, 11)), "de 25e")
        XCTAssertEqual(one.salaryPayoutDaysText(in: ym(2025, 11)), "", "voor de startmaand komt er niets binnen")
        let none = data(start: ym(2026, 9), .weeks, 6, anchor: cd(2026, 10, 23))
        XCTAssertEqual(none.salaryPayoutDaysText(in: ym(2026, 11)), "")
        var zero = d
        zero.salary.fixedMonthly = 0
        XCTAssertEqual(zero.salaryPayoutDaysText(in: ym(2026, 10)), "", "zonder bedrag komt er niets binnen")
    }

    func testTheScheduleDescription() {
        let today = day(ym(2026, 10), 13)
        let four = data(.weeks, 4, anchor: cd(2026, 10, 23))
        XCTAssertEqual(four.salaryScheduleSummary(asOf: today), "elke 4 weken, volgende op 23 oktober")
        XCTAssertEqual(four.salary.cycleDescription, "elke 4 weken")
        XCTAssertEqual(data(.weeks, 1, anchor: cd(2026, 10, 23)).salary.cycleDescription, "elke week")
        XCTAssertEqual(data(.days, 1, anchor: cd(2026, 10, 23)).salary.cycleDescription, "elke dag")
        XCTAssertEqual(data(.days, 10, anchor: cd(2026, 10, 15)).salaryScheduleSummary(asOf: today),
                       "elke 10 dagen, volgende op 15 oktober")
        XCTAssertEqual(data(.monthly, 1, anchor: nil, payDay: 25).salaryScheduleSummary(asOf: today),
                       "elke maand op de 25e, volgende op 25 oktober")
        XCTAssertEqual(data(.monthly, 1, anchor: nil, payDay: 31).salary.cycleDescription, "elke maand op de laatste dag")
        XCTAssertEqual(data(.monthly, 1, anchor: nil, payDay: 1).salary.cycleDescription, "elke maand op de 1e")
        // Het jaar staat erbij als de volgende uitbetaling niet dit jaar is.
        XCTAssertEqual(four.salaryScheduleSummary(asOf: day(ym(2026, 12), 20)), "elke 4 weken, volgende op 15 januari 2027")
        // Een datum midden in de nacht rekent met de dag zelf.
        XCTAssertEqual(four.salaryScheduleSummary(asOf: engTime(ym(2026, 10), 23, hour: 0.1)), "elke 4 weken, volgende op 20 november")
    }

    // MARK: Gemiddelde per maand (voor schattingen)

    func testAverageMonthlyAmounts() {
        // Vast 1000 per uitbetaling x 365,25 / 12 / dagen per cyclus.
        XCTAssertEqual(data(.monthly, 1, anchor: nil).salary.averageMonthlyAmount(), 1_000)
        XCTAssertEqual(data(.weeks, 4, anchor: nil).salary.averageMonthlyAmount(), 1_087.05)     // 1000 x 30,4375 / 28
        XCTAssertEqual(data(.weeks, 1, anchor: nil).salary.averageMonthlyAmount(), 4_348.21)     // 1000 x 30,4375 / 7
        XCTAssertEqual(data(.weeks, 2, anchor: nil).salary.averageMonthlyAmount(), 2_174.11)     // 1000 x 30,4375 / 14
        XCTAssertEqual(data(.days, 10, anchor: nil).salary.averageMonthlyAmount(), 3_043.75)     // 1000 x 30,4375 / 10
        XCTAssertEqual(data(.days, 31, anchor: nil).salary.averageMonthlyAmount(), 981.85)       // 1000 x 30,4375 / 31
        XCTAssertEqual(data(.days, 1, anchor: nil).salary.averageMonthlyAmount(), 30_437.5)
        // Uurloon: de uitbetaling is al afgerond; 4 weken is 2880, dus 2880 x 30,4375 / 28.
        XCTAssertEqual(hourly(.weeks, 4, anchor: nil).salary.averageMonthlyAmount(), 3_130.71)
        // Het maandelijkse uurloon blijft op 52 / 12 weken: 20 x 36 x 52 / 12.
        XCTAssertEqual(hourly(.monthly, 1, anchor: nil).salary.averageMonthlyAmount(), 3_120)
        XCTAssertEqual(hourly(.monthly, 1, anchor: nil).salary.monthlyAmount(), 3_120)
        // Een gemiddelde per week, en de gemiddelde uren per maand.
        XCTAssertEqual(data(.monthly, 1, anchor: nil).salary.averageMonthly(perWeek: 100), 100 * 52 / 12, accuracy: 1e-9)
        XCTAssertEqual(data(.weeks, 4, anchor: nil).salary.averageMonthly(perWeek: 100), 100 * 365.25 / 7 / 12, accuracy: 1e-9)
        XCTAssertEqual(hourly(.weeks, 4, anchor: nil).salary.defaultMonthlyHours, 36 * 365.25 / 7 / 12, accuracy: 1e-9)
        XCTAssertEqual(hourly(.monthly, 1, anchor: nil).salary.defaultMonthlyHours, 156, accuracy: 1e-9)
        XCTAssertEqual(data(.weeks, 4, anchor: nil).salary.averagePayoutsPerYear, 365.25 / 28, accuracy: 1e-9)
        XCTAssertEqual(data(.monthly, 1, anchor: nil).salary.averagePayoutsPerYear, 12)
        // Uren van een maand (uurloon): dat is gewoon uurloon x uren.
        XCTAssertEqual(hourly(.weeks, 4, anchor: nil).salary.averageMonthlyAmount(hoursOverride: 100), 2_000)
    }

    func testEstimatesUseAnAverageMonthButTheLedgerUsesTheRealOne() {
        var d = data(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23))
        var pot = Pot(name: "Sparen", monthlyContribution: 0, startMonth: ym(2026, 7))
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        pot.contributionBasis = .salary
        d.addPot(pot, openingBalance: 0, now: day(ym(2026, 7), 1))
        d.addRecurringLine(MoneyLine(name: "Huur", amount: 900, day: 1), kind: .expense, in: ym(2026, 7))
        // Juli heeft twee uitbetalingen, augustus één.
        XCTAssertEqual(d.income(in: ym(2026, 7)), 2_000)
        XCTAssertEqual(d.income(in: ym(2026, 8)), 1_000)
        // Een gemiddelde maand is 1087,05 in beide maanden.
        XCTAssertEqual(d.estimatedMonthlyIncome(in: ym(2026, 7)), 1_087.05)
        XCTAssertEqual(d.estimatedMonthlyIncome(in: ym(2026, 8)), 1_087.05)
        // 10% van 1087,05 is 108,705 en dus 108,71 (half omhoog).
        XCTAssertEqual(d.estimatedAllocation(pot.id, in: ym(2026, 7)), 108.71)
        XCTAssertEqual(d.estimatedAllocation(pot.id, in: ym(2026, 8)), 108.71)
        XCTAssertEqual(d.allocation(pot.id, in: ym(2026, 7)), 200)
        XCTAssertEqual(d.allocation(pot.id, in: ym(2026, 8)), 100)
        XCTAssertEqual(d.estimatedRemaining(in: ym(2026, 7)), 1_087.05 - 900 - 108.71, accuracy: 0.0001)
        XCTAssertEqual(d.estimatedFigures(ym(2026, 7)).saved, 10_871)
        XCTAssertEqual(d.estimatedFigures(ym(2026, 7)).income, 108_705)
        XCTAssertEqual(d.estimatedIncomeBases(in: ym(2026, 7)), IncomeBases(salary: 108_705, all: 108_705))
        // Een extra inkomen telt in de gemiddelde maand mee voor "alle inkomsten".
        d.addRecurringLine(MoneyLine(name: "Toeslag", amount: 100, day: 20), kind: .income, in: ym(2026, 7))
        XCTAssertEqual(d.estimatedIncomeBases(in: ym(2026, 7)), IncomeBases(salary: 108_705, all: 118_705))
        XCTAssertEqual(d.estimatedMonthlyIncome(in: ym(2026, 7)), 1_187.05)
        // De toekomstschatting en de doelen gebruiken de gemiddelde maand.
        var holding = Holding(name: "ETF", kind: .etf, monthlyContribution: 0, startMonth: ym(2026, 7))
        holding.contributionMode = .percentage
        holding.contributionPercent = 5
        holding.contributionBasis = .salary
        d.addHolding(holding)
        XCTAssertEqual(d.monthlyInvestment(current: ym(2026, 7)), 54.35)    // 5% van 1087,05 = 54,3525
        XCTAssertEqual(d.investedTotal(in: ym(2026, 7)), 100)               // de echte maand: 5% van 2000
        // Bij het maandelijkse schema is alles gelijk aan de echte maand.
        var monthly = d
        monthly.salary.setSchedule(.monthly)
        XCTAssertEqual(monthly.estimatedMonthlyIncome(in: ym(2026, 7)), monthly.income(in: ym(2026, 7)))
        XCTAssertEqual(monthly.estimatedRemaining(in: ym(2026, 7)), monthly.remaining(in: ym(2026, 7)))
        XCTAssertEqual(monthly.estimatedAllocation(pot.id, in: ym(2026, 7)), monthly.allocation(pot.id, in: ym(2026, 7)))
        XCTAssertEqual(monthly.monthlyInvestment(current: ym(2026, 7)), monthly.investedTotal(in: ym(2026, 7)))
        XCTAssertEqual(monthly.estimatedFigures(ym(2026, 7)), monthly.monthFigures(ym(2026, 7)))
    }

    func testEffectiveHourlyWageAndTheIncomeGapUseTheAverage() {
        // Vast 1000 per 4 weken bij 36 uur per week: 1000 / (36 x 4) = 6,94 per uur.
        var fixed = data(.weeks, 4, anchor: nil)
        fixed.salary.hoursPerWeek = 36
        XCTAssertEqual(fixed.effectiveHourlyWage(), 6.94)
        // Maandelijks 3000 bij 36 uur: 3000 / 156 = 19,23, zoals altijd.
        var monthly = data(.monthly, 1, anchor: nil, amount: 3_000)
        monthly.salary.hoursPerWeek = 36
        XCTAssertEqual(monthly.effectiveHourlyWage(), 19.23)
        // Een uurloon blijft het uurloon bij elk schema.
        XCTAssertEqual(hourly(.weeks, 4, anchor: nil).effectiveHourlyWage(), 20)
        XCTAssertEqual(hourly(.days, 10, anchor: nil).effectiveHourlyWage(), 20)
        // Minder uren werken (36 naar 28): het inkomensgat per maand.
        var goal = LifeGoal(name: "Parttime", kind: .partTime)
        goal.hoursFrom = 36
        goal.hoursTo = 28
        XCTAssertEqual(hourly(.monthly, 1, anchor: nil).monthlyIncomeGap(for: goal), 693.33)   // 20 x 8 x 52 / 12
        XCTAssertEqual(hourly(.weeks, 4, anchor: nil).monthlyIncomeGap(for: goal), 695.71)     // 160 x 365,25 / 7 / 12
        // Vast: 1000 per 4 weken is 1087,05 per maand, en 8 van 36 uur minder is 2/9 van 1087,0536 = 241,55.
        XCTAssertEqual(data(.weeks, 4, anchor: nil).monthlyIncomeGap(for: goal), 241.57, accuracy: 0.011)
        XCTAssertEqual(data(.monthly, 1, anchor: nil, amount: 3_000).monthlyIncomeGap(for: goal), 666.67)
    }

    func testTheExtraHoursAcceleratorUsesTheAverageMonth() throws {
        var d = hourly(start: aug2026, .weeks, 4, anchor: cd(2026, 10, 23))
        let pot = Pot(name: "Vakantie", symbol: "airplane", monthlyContribution: 300, startMonth: aug2026)
        d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
        var goal = LifeGoal(name: "Japan", kind: .vacation)
        goal.targetAmount = 6_000
        goal.inflationAdjusted = false
        goal.funding = .pot(pot.id)
        d.addGoal(goal)
        d.materialize(upTo: oct2026)
        let hours = try XCTUnwrap(d.accelerators(for: goal, current: oct2026, today: day(oct2026, 12)).first { $0.id == "hours" })
        // 2 uur x 20 per uur x 365,25 / 7 / 12 = 173,93 per gemiddelde maand (maandelijks was het 173,33).
        XCTAssertEqual(hours.change.extraMonthly, 173.93, accuracy: 0.001)
        var monthly = d
        monthly.salary.setSchedule(.monthly)
        let usual = try XCTUnwrap(monthly.accelerators(for: goal, current: oct2026, today: day(oct2026, 12)).first { $0.id == "hours" })
        XCTAssertEqual(usual.change.extraMonthly, 173.33, accuracy: 0.001)
    }

    func testAnAcceleratorOnAPercentageContributionUsesTheAverageMonth() throws {
        // Elke 4 weken 1000 vanaf 23 oktober 2026: oktober heeft één uitbetaling, een gemiddelde maand is 1087,05.
        var d = data(start: aug2026, .weeks, 4, anchor: cd(2026, 10, 23))
        var pot = Pot(name: "Vakantie", symbol: "airplane", monthlyContribution: 0, startMonth: aug2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        pot.contributionBasis = .salary
        d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
        var goal = LifeGoal(name: "Japan", kind: .vacation)
        goal.targetAmount = 60_000
        goal.inflationAdjusted = false
        goal.funding = .pot(pot.id)
        d.addGoal(goal)
        d.materialize(upTo: oct2026)
        let original = d
        let now = day(oct2026, 12)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 100, "de echte maand: 10% van 1000")
        // 5% van een gemiddelde maand: 54,3525 en dus 54,35 (en niet 5% van de 1000 van oktober).
        let acc = try XCTUnwrap(d.accelerators(for: goal, current: oct2026, today: now).first { $0.id == "income5" })
        XCTAssertEqual(acc.change.extraMonthly, 54.35, accuracy: 1e-9)
        let record = try XCTUnwrap(d.apply(acc, for: goal, current: oct2026, now: now))
        // Het vaste bedrag dat blijft geldt voor elke maand: 10% van een gemiddelde maand (108,71) plus 54,35.
        XCTAssertEqual(d.pots[0].contributionMode, .fixed)
        XCTAssertEqual(d.pots[0].monthlyContribution, 163.06, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(pot.id, in: ym(2026, 11)), 163.06, accuracy: 1e-9)
        // De lopende maand is echt: 100 + 54,35.
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 154.35, accuracy: 1e-9)
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertEqual(d, original)
    }

    func testTheBufferAndPurchaseChecksUseTheAverageMonth() {
        var d = data(start: aug2026, .weeks, 4, anchor: cd(2026, 10, 23))
        let pot = Pot(name: "Buffer", goalAmount: 2_000, monthlyContribution: 0, startMonth: aug2026)
        var percentPot = pot
        percentPot.contributionMode = .percentage
        percentPot.contributionPercent = 10
        percentPot.contributionBasis = .salary
        d.addPot(percentPot, openingBalance: 0, now: day(aug2026, 2))
        // Oktober heeft één uitbetaling van 1000 (de 23e), maar een gemiddelde maand is 1087,05.
        XCTAssertEqual(d.income(in: oct2026), 1_000)
        XCTAssertEqual(BufferCalc.defaultMonthlySaving(in: d, setup: BufferSetup(source: .pot, potID: percentPot.id), current: oct2026), 108.71)
        let context = PurchaseContext.make(from: d, current: oct2026, today: day(oct2026, 12))
        XCTAssertEqual(context.monthlyIncome, 1_087.05)
        XCTAssertEqual(context.pots.first?.monthlyContribution, 108.71)
        // Het maandelijkse schema: precies de echte maand.
        var monthly = d
        monthly.salary.setSchedule(.monthly)
        let usual = PurchaseContext.make(from: monthly, current: oct2026, today: day(oct2026, 12))
        XCTAssertEqual(usual.monthlyIncome, 1_000)
        XCTAssertEqual(usual.pots.first?.monthlyContribution, 100)
    }

    // MARK: Opslaan en inlezen

    func testOldSalaryJSONLoadsAsMonthly() throws {
        let old = #"{"mode":"fixed","fixedMonthly":3000,"hourlyRate":0,"hoursPerWeek":0}"#
        let s = try JSONDecoder().decode(SalarySettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.schedule, .monthly)
        XCTAssertEqual(s.interval, 1)
        XCTAssertNil(s.anchor)
        XCTAssertEqual(s.payDay, 25)
        XCTAssertEqual(s, SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25))
        let withDay = #"{"mode":"hourly","fixedMonthly":0,"hourlyRate":21.5,"hoursPerWeek":36,"payDay":28}"#
        let t = try JSONDecoder().decode(SalarySettings.self, from: Data(withDay.utf8))
        XCTAssertEqual(t.schedule, .monthly)
        XCTAssertEqual(t.payDay, 28)
        XCTAssertEqual(t.monthlyAmount(), (21.5 * (36.0 * 52 / 12)).cents)
        XCTAssertEqual(try JSONDecoder().decode(SalarySettings.self, from: Data("{}".utf8)), SalarySettings())
    }

    func testTheMonthlyScheduleIsWrittenExactlyAsBefore() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(data: try encoder.encode(SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)),
                          encoding: .utf8)
        XCTAssertEqual(text, #"{"fixedMonthly":3000,"hourlyRate":0,"hoursPerWeek":0,"mode":"fixed","payDay":25}"#)
        // Een leeg bestand blijft byte voor byte gelijk: geen schema, interval of anker erin.
        let empty = String(data: try encoder.encode(FinanceData(startMonth: aug2026)), encoding: .utf8) ?? ""
        XCTAssertFalse(empty.contains("schedule"))
        XCTAssertFalse(empty.contains("anchor"))
        XCTAssertFalse(empty.contains("interval"))
    }

    func testTheScheduleSurvivesAFileAndABackup() throws {
        var d = data(start: ym(2026, 7), .weeks, 4, anchor: cd(2026, 10, 23))
        d.editPlan(ym(2026, 7)) { $0.salaryOverride = 3_000 }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(d)
        let text = String(data: json, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"schedule\":\"weeks\""), text)
        XCTAssertTrue(text.contains("\"interval\":4"), text)
        XCTAssertTrue(text.contains("\"anchor\":\"2026-10-23\""), text)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(FinanceData.self, from: json)
        XCTAssertEqual(back.salary, d.salary)
        XCTAssertEqual(back.salaryAmount(in: ym(2026, 7)), 3_000)
        XCTAssertEqual(back.salaryPayDays(in: ym(2026, 8)), [28])
        // Cloud: de inhoud van een apparaat met alleen een schema telt als gevuld.
        var onlySchedule = FinanceData(startMonth: aug2026)
        XCTAssertFalse(CloudSync.hasContent(onlySchedule))
        onlySchedule.salary.setSchedule(.weeks, interval: 2)
        XCTAssertTrue(CloudSync.hasContent(onlySchedule))
        XCTAssertFalse(onlySchedule.isEmptyStart)
        XCTAssertFalse(CloudSync.contentEqual(onlySchedule, FinanceData(startMonth: aug2026)))
    }

    func testTheScheduleSurvivesEveryWayOfStoring() throws {
        var d = hourly(start: ym(2026, 7), .days, 10, anchor: cd(2026, 10, 5))
        d.addRecurringLine(MoneyLine(name: "Huur", amount: 900, day: 1), kind: .expense, in: ym(2026, 7))
        d.editPlan(ym(2026, 8)) { $0.hoursOverride = 90 }
        d.editPlan(ym(2026, 9)) { $0.salaryOverride = 2_500 }
        let months = ym(2026, 7).range(count: 24)
        let incomes = months.map { d.income(in: $0) }
        let days = months.map { d.salaryPayDays(in: $0) }
        func check(_ back: FinanceData, _ label: String) {
            XCTAssertEqual(back, d, label)
            XCTAssertEqual(back.salary.schedule, .days, label)
            XCTAssertEqual(back.salary.interval, 10, label)
            XCTAssertEqual(back.salary.anchor, cd(2026, 10, 5), label)
            XCTAssertEqual(months.map { back.income(in: $0) }, incomes, label)
            XCTAssertEqual(months.map { back.salaryPayDays(in: $0) }, days, label)
        }
        check(try FinanceStorage.makeDecoder().decode(FinanceData.self, from: FinanceStorage.makeFileEncoder().encode(d)), "bestand")
        check(try FinanceStorage.makeDecoder().decode(FinanceData.self, from: FinanceStorage.makeEncoder().encode(d)), "opgemaakt")
        check(try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(d)), "gewoon")
        let backup = try BackupService.export(d, now: Date(timeIntervalSince1970: 1_790_000_000))
        check(try BackupService.importBackup(backup), "back-up")
        let snapshot = try RemoteSnapshot(finance: d, modifiedAt: Date(timeIntervalSince1970: 1_790_000_000), device: "test")
        check(try snapshot.decodeFinance(), "cloud")
        // Een ander schema is een ander bestand voor de synchronisatie.
        var other = d
        other.salary.interval = 11
        XCTAssertFalse(CloudSync.contentEqual(d, other))
        XCTAssertNotEqual(CloudSync.contentDigest(d), CloudSync.contentDigest(other))
        var otherAnchor = d
        otherAnchor.salary.anchor = cd(2026, 10, 6)
        XCTAssertNotEqual(CloudSync.contentDigest(d), CloudSync.contentDigest(otherAnchor))
        // Een bestand van vóór het schema: het maandelijkse schema, niets nieuws erin.
        let old = FinanceData(startMonth: aug2026)
        let text = String(data: try FinanceStorage.makeFileEncoder().encode(old), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("\"schedule\""))
        XCTAssertFalse(text.contains("\"anchor\""))
        XCTAssertFalse(text.contains("\"interval\""))
    }

    func testTheAnchorAsADateForADatePicker() {
        var s = SalarySettings()
        XCTAssertNil(s.anchorDate)
        s.anchorDate = engTime(ym(2026, 10), 23, hour: 22.5)
        XCTAssertEqual(s.anchor, cd(2026, 10, 23))
        XCTAssertEqual(s.anchorDate, ym(2026, 10).date(day: 23))
        s.anchorDate = nil
        XCTAssertNil(s.anchor)
    }

    func testAbsurdYearsNeverCrash() {
        let d = data(.weeks, 4, anchor: cd(2026, 10, 23))
        XCTAssertEqual(d.salaryPayDays(in: YearMonth(year: 12_000, month: 5)), [])
        XCTAssertEqual(d.salaryAmount(in: YearMonth(year: 12_000, month: 5)), 0)
        XCTAssertNotNil(d.nextPayDate(after: Date.distantPast))
        _ = d.nextPayDate(after: Date.distantFuture)
        XCTAssertEqual(cd(9_999, 12, 31).adding(days: 400), cd(9_999, 12, 31))
        XCTAssertEqual(cd(0, 1, 1).adding(days: -400), cd(0, 1, 1))
        XCTAssertEqual(CalendarDay(dayNumber: Int.max), cd(9_999, 12, 31))
        XCTAssertEqual(CalendarDay(dayNumber: Int.min), cd(0, 1, 1))
        XCTAssertEqual(CalendarDay(year: Int.max, month: Int.max, day: Int.max), cd(9_999, 12, 31))
        // Een kapot interval wordt geklemd en rekent gewoon door.
        var broken = d
        broken.salary.interval = Int.max
        XCTAssertEqual(broken.salaryPayDays(in: ym(2026, 11)).count <= 1, true)
        broken.salary.interval = Int.min
        XCTAssertFalse(broken.salaryPayDays(in: ym(2026, 11)).isEmpty)
    }

    func testUnknownOrBrokenScheduleValuesFallBackInsteadOfFailing() throws {
        let unknown = #"{"mode":"fixed","fixedMonthly":1000,"payDay":3,"schedule":"fortnightly","interval":2,"anchor":"morgen"}"#
        let s = try JSONDecoder().decode(SalarySettings.self, from: Data(unknown.utf8))
        XCTAssertEqual(s.schedule, .monthly)
        XCTAssertNil(s.anchor)
        XCTAssertEqual(s.payDay, 3)
        XCTAssertEqual(s.fixedMonthly, 1_000)
        let odd = #"{"schedule":"days","interval":"veel"}"#
        let t = try JSONDecoder().decode(SalarySettings.self, from: Data(odd.utf8))
        XCTAssertEqual(t.schedule, .days)
        XCTAssertEqual(t.interval, 1)
        // De rest van het bestand laadt gewoon.
        let file = #"{"startMonth":"2026-08","salary":{"schedule":"zomaar","anchor":"2026-02-30"},"months":{}}"#
        let d = try JSONDecoder().decode(FinanceData.self, from: Data(file.utf8))
        XCTAssertEqual(d.startMonth, aug2026)
        XCTAssertEqual(d.salary.schedule, .monthly)
    }

    // MARK: Oude data

    func testMonthlyDataKeepsRoundingAndAmountsExactlyLikeBefore() {
        // De oude formules naast de nieuwe, voor veel instellingen en overschrijvingen.
        var r = EngRandom(seed: 777)
        for i in 0..<400 {
            var d = FinanceData(startMonth: ym(2026, 3))
            let fixed = r.chance(50)
            d.salary = fixed
                ? SalarySettings(mode: .fixed, fixedMonthly: r.amount(0, 5_000) + (r.chance(30) ? 0.004 : 0), hourlyRate: 0,
                                 hoursPerWeek: Double(r.int(0...40)), payDay: r.int(1...31))
                : SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: r.amount(5, 60), hoursPerWeek: Double(r.int(0...45)) + (r.chance(30) ? 0.5 : 0),
                                 payDay: r.int(1...31))
            let month = ym(2026, 3).adding(r.int(0...30))
            var plan = MonthPlan()
            if r.chance(25) { plan.salaryOverride = r.amount(0, 6_000) + (r.chance(30) ? 0.006 : 0) }
            if r.chance(25) { plan.hoursOverride = Double(r.int(0...200)) + (r.chance(50) ? 0.25 : 0) }
            // Het oude antwoord.
            let expected: Double
            if let override = plan.salaryOverride {
                expected = override.cents
            } else if d.salary.mode == .fixed {
                expected = d.salary.fixedMonthly.cents
            } else {
                expected = (d.salary.hourlyRate * (plan.hoursOverride ?? d.salary.hoursPerWeek * 52 / 12)).cents
            }
            XCTAssertEqual(d.salaryAmount(in: month, plan: plan), expected, "geval \(i)")
            XCTAssertEqual(d.salaryCents(in: month, plan: plan), CentsMath.int(expected), "geval \(i)")
            XCTAssertEqual(d.salary.monthlyAmount(hoursOverride: plan.hoursOverride),
                           d.salary.mode == .fixed ? d.salary.fixedMonthly.cents
                               : (d.salary.hourlyRate * (plan.hoursOverride ?? d.salary.hoursPerWeek * 52 / 12)).cents, "geval \(i)")
            XCTAssertEqual(d.salary.defaultMonthlyHours, d.salary.hoursPerWeek * 52 / 12, "geval \(i)")
            XCTAssertEqual(d.salary.averageMonthly(perWeek: 17.3), 17.3 * 52 / 12)
            // Een uitbetaling op de salarisdag, het oude id, de oude dag.
            let payouts = d.salaryPayouts(in: month, plan: plan)
            XCTAssertEqual(payouts, [SalaryPayout(id: "salary-\(month.key)", day: min(d.salaryDay(), month.dayCount),
                                                  cents: CentsMath.int(expected))], "geval \(i)")
            XCTAssertEqual(d.salaryPayDays(in: month), [min(d.salaryDay(), month.dayCount)])
            XCTAssertEqual(d.salaryDay(in: month), d.salaryDay())
            XCTAssertEqual(d.estimatedFigures(month), d.monthFigures(month))
        }
    }

    func testOldMonthlyDataKeepsTheSameNumbersEverywhere() {
        // Salaris 3000 op de 25e, huur 1000, pot 200 (zoals de basisgegevens van de andere tests).
        var d = makeBaseData()
        _ = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        XCTAssertEqual(d.income(in: oct2026), 3_100)                // 3000 + toeslag 100
        XCTAssertEqual(d.remaining(in: oct2026), 3_100 - 1_000 - 200)
        XCTAssertEqual(d.salaryDay(), 25)
        XCTAssertEqual(d.salaryDay(in: oct2026), 25)
        let events = d.dayEvents(in: oct2026, asOf: day(oct2026, 12))
        XCTAssertEqual(events.filter { $0.kind == .salary }.map(\.id), ["salary-2026-10"])
        XCTAssertEqual(events.filter { $0.kind == .salary }.map(\.day), [25])
        XCTAssertEqual(events.first { $0.kind == .toPot }?.day, 25)
        XCTAssertEqual(events.first { $0.kind == .income }?.day, 25)
        XCTAssertTrue(d.monthLedger(oct2026, asOf: day(oct2026, 12)).allReconciles)
        XCTAssertEqual(d.salaryScheduleSummary(asOf: day(oct2026, 12)), "elke maand op de 25e, volgende op 25 oktober")
    }
}
