import XCTest
import Foundation
@testable import MyBuddyCore

/// `WorkCalendarRules.collect`: welke afspraken uit de agenda een dienst worden (de regels die `EventKitWorkCalendar` zonder eigen logica
/// gebruikt). Alles in de tijdzone van de app (`YearMonth.calendar`).
final class WorkCalendarCollectTests: XCTestCase {
    private let calendar = YearMonth.calendar
    private let werken = [CalendarInfo(id: "w", title: "werken", sourceTitle: "iCloud")]

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(_ day: Int, _ from: Int, _ to: Int, allDay: Bool = false, canceled: Bool = false,
                       declined: Bool = false) -> CalendarEventSample {
        CalendarEventSample(start: at(2026, 11, day, from), end: at(2026, 11, day, to), isAllDay: allDay,
                            isCanceled: canceled, isDeclined: declined)
    }

    func testOrdinaryEventsBecomeShiftsInOrder() {
        let fetch = WorkCalendarRules.collect([event(3, 13, 17), event(2, 9, 17)], matched: werken, allDayShiftHours: nil)
        XCTAssertEqual(fetch.shifts.count, 2)
        XCTAssertEqual(fetch.shifts.first?.start, at(2026, 11, 2, 9))
        XCTAssertEqual(fetch.shifts.last?.durationMinutes, 240)
        XCTAssertEqual(fetch.matched, werken)
        XCTAssertEqual(fetch.skippedTotal, 0)
    }

    func testCanceledAndDeclinedEventsAreSkippedAndCounted() {
        let fetch = WorkCalendarRules.collect([event(2, 9, 17, canceled: true), event(3, 9, 17, declined: true), event(4, 9, 12)],
                                              matched: werken, allDayShiftHours: nil)
        XCTAssertEqual(fetch.shifts.count, 1)
        XCTAssertEqual(fetch.skippedCanceled, 1)
        XCTAssertEqual(fetch.skippedDeclined, 1)
    }

    func testAllDayEventsOnlyCountWithHoursPerDay() {
        let allDay = CalendarEventSample(start: at(2026, 11, 5, 0), end: at(2026, 11, 7, 0), isAllDay: true)
        let skipped = WorkCalendarRules.collect([allDay], matched: werken, allDayShiftHours: nil)
        XCTAssertTrue(skipped.shifts.isEmpty)
        XCTAssertEqual(skipped.skippedAllDay, 1)

        let counted = WorkCalendarRules.collect([allDay], matched: werken, allDayShiftHours: 7.5)
        XCTAssertEqual(counted.shifts.count, 2, "twee dagen, twee diensten")
        XCTAssertEqual(counted.shifts.first?.start, at(2026, 11, 5, WorkCalendarRules.allDayStartHour))
        XCTAssertEqual(counted.shifts.first?.durationMinutes, 450)
        XCTAssertEqual(counted.skippedAllDay, 0)
    }

    func testEventsLongerThanTheMaximumAreSkipped() {
        let long = CalendarEventSample(start: at(2026, 11, 2, 6), end: at(2026, 11, 3, 6))
        let fetch = WorkCalendarRules.collect([long, event(4, 9, 17)], matched: werken, allDayShiftHours: nil)
        XCTAssertEqual(fetch.shifts.count, 1)
        XCTAssertEqual(fetch.skippedTooLong, 1)
    }

    func testOverlappingEventsAreMergedIntoOneShift() {
        let fetch = WorkCalendarRules.collect([event(2, 9, 13), event(2, 12, 17), event(2, 9, 10)], matched: werken, allDayShiftHours: nil)
        XCTAssertEqual(fetch.shifts.count, 1)
        XCTAssertEqual(fetch.shifts.first?.durationMinutes, 8 * 60)
    }

    func testAnEventThatEndsBeforeItStartsIsIgnored() {
        let backwards = CalendarEventSample(start: at(2026, 11, 2, 17), end: at(2026, 11, 2, 9))
        let fetch = WorkCalendarRules.collect([backwards], matched: werken, allDayShiftHours: nil)
        XCTAssertTrue(fetch.shifts.isEmpty)
        XCTAssertEqual(fetch.skippedTotal, 0)
    }

    func testTheResultFeedsTheSnapshotOfTheData() {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        data.salary.mode = .hourly
        data.work.hoursSource = .calendar
        let fetch = WorkCalendarRules.collect([event(2, 9, 17), event(3, 9, 17)], matched: werken, allDayShiftHours: nil)
        XCTAssertTrue(data.applyCalendarFetch(fetch, today: at(2026, 11, 4, 12)))
        XCTAssertEqual(data.work.snapshot?.shifts.count, 2)
        // Geen agenda met die naam: de oude diensten blijven staan.
        XCTAssertFalse(data.applyCalendarFetch(WorkCalendarRules.collect([], matched: [], allDayShiftHours: nil), today: at(2026, 11, 5, 12)))
        XCTAssertEqual(data.work.snapshot?.shifts.count, 2)
    }
}
