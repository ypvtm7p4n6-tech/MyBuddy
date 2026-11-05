import XCTest
import Foundation
@testable import MyBuddyCore

/// Een nagemaakte agenda achter het protocol van de Core (`WorkCalendarSource`): de echte (EventKit) staat in App/Calendar en wordt in
/// de tests nooit aangeraakt.
final class FakeWorkCalendar: WorkCalendarSource, @unchecked Sendable {
    var accessState: CalendarAccess
    /// Wat `requestAccess()` als nieuwe toestand geeft.
    var grantedAfterRequest: CalendarAccess
    var calendarList: [CalendarInfo]
    /// De diensten per agenda-id.
    var shiftsByCalendar: [String: [WorkShift]]
    var skipped = (declined: 0, canceled: 0, allDay: 0, tooLong: 0)
    var failure: Error?
    private(set) var fetchCount = 0
    private(set) var lastWindow: (from: Date, to: Date)?
    private var continuation: AsyncStream<Void>.Continuation?

    init(access: CalendarAccess = .granted, grantedAfterRequest: CalendarAccess = .granted, calendars: [CalendarInfo] = [],
         shifts: [String: [WorkShift]] = [:]) {
        self.accessState = access
        self.grantedAfterRequest = grantedAfterRequest
        self.calendarList = calendars
        self.shiftsByCalendar = shifts
    }

    func access() async -> CalendarAccess { accessState }

    func requestAccess() async -> CalendarAccess {
        if accessState == .notDetermined { accessState = grantedAfterRequest }
        return accessState
    }

    func calendars() async -> [CalendarInfo] { accessState.canRead ? calendarList : [] }

    func fetch(calendarTitle: String, from: Date, to: Date, allDayShiftHours: Double?) async throws -> CalendarFetch {
        fetchCount += 1
        lastWindow = (from, to)
        if let failure { throw failure }
        guard accessState.canRead else { return CalendarFetch() }
        let matched = calendarList.filter { CalendarTitle.matches($0.title, calendarTitle) }
        var shifts: [WorkShift] = []
        for info in matched { shifts += shiftsByCalendar[info.id] ?? [] }
        shifts = shifts.filter { $0.end > from && $0.start < to }
        return CalendarFetch(shifts: WorkShift.normalized(shifts), matched: matched, skippedAllDay: skipped.allDay,
                             skippedDeclined: skipped.declined, skippedCanceled: skipped.canceled, skippedTooLong: skipped.tooLong)
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    /// Doet alsof de agenda in het systeem veranderde.
    func announceChange() { continuation?.yield() }
}

/// De ronde die de controller van golf 3A doet, in de tests nagebootst met alleen de Core: toegang lezen, kijken of verversen nodig is,
/// de agenda ophalen en de snapshot bewaren.
func engRefresh(_ data: inout FinanceData, from source: WorkCalendarSource, today: Date, force: Bool = false) async throws -> Bool {
    guard await source.access().canRead else { return false }
    guard force || WorkCalendarWindow.needsRefresh(data, today: today) else { return false }
    let window = WorkCalendarWindow.window(for: data, today: today)
    let fetch = try await source.fetch(calendarTitle: data.work.calendarTitle, from: window.from.date(), to: window.through.date(),
                                       allDayShiftHours: data.work.allDayShiftHours)
    return data.applyCalendarFetch(fetch, today: today)
}

/// Tests van het deel van de agendakoppeling dat in de Core staat (App/Core/WorkCalendar.swift): de naam van een agenda vergelijken, het
/// venster dat nodig is, wanneer verversen nodig is en het bewaren van het resultaat (docs/work/plan.md par. 3.1 en 4.1).
final class WorkCalendarCoreTests: XCTestCase {
    private let cal = YearMonth.calendar
    private let oct = YearMonth(year: 2026, month: 10)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }
    private func noon(_ y: Int, _ m: Int, _ d: Int) -> Date { engDate(cal, y, m, d, 12) }
    private func shift(_ y: Int, _ m: Int, _ d: Int, from: Int, to: Int) -> WorkShift { engShift(engDate(cal, y, m, d, from), engDate(cal, y, m, d, to)) }

    private func hourlyData() -> FinanceData {
        var d = FinanceData(startMonth: oct)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 15, hoursPerWeek: 24, payDay: 25)
        d.work.hoursSource = .calendar
        return d
    }

    // MARK: De naam van een agenda

    func testTitleMatchingIgnoresCaseAccentsAndEdges() {
        XCTAssertTrue(CalendarTitle.matches("Werken", "werken"))
        XCTAssertTrue(CalendarTitle.matches("WERKEN", "werken"))
        XCTAssertTrue(CalendarTitle.matches(" werken\n", "werken"), "spaties en regelovergangen aan de randen")
        XCTAssertTrue(CalendarTitle.matches("Wérkèn", "werken"), "accenten tellen niet")
        XCTAssertFalse(CalendarTitle.matches("werk", "werken"))
        XCTAssertFalse(CalendarTitle.matches("mijn werken", "werken"), "alleen de hele naam")
        XCTAssertTrue(CalendarTitle.matches("", "   "))
        XCTAssertEqual(CalendarTitle.fold("  Île  "), "ile")
    }

    func testCalendarAccessOnlyReadsWhenFullAccessIsGranted() {
        XCTAssertTrue(CalendarAccess.granted.canRead)
        for access in [CalendarAccess.notDetermined, .writeOnly, .denied, .restricted] { XCTAssertFalse(access.canRead, "\(access)") }
    }

    func testAFetchCountsWhatItSkippedAndAnInfoIsIdentifiable() {
        var fetch = CalendarFetch()
        XCTAssertEqual(fetch.skippedTotal, 0)
        XCTAssertTrue(fetch.shifts.isEmpty)
        XCTAssertTrue(fetch.matched.isEmpty)
        fetch.skippedAllDay = 1
        fetch.skippedDeclined = 2
        fetch.skippedCanceled = 3
        fetch.skippedTooLong = 4
        XCTAssertEqual(fetch.skippedTotal, 10)
        XCTAssertEqual(CalendarFetch(matched: [CalendarInfo(id: "a", title: "werken", sourceTitle: "iCloud")]).matched.first?.id, "a")
        let info = CalendarInfo(id: "abc", title: "werken")
        XCTAssertEqual(info.id, "abc")
        XCTAssertEqual(info.sourceTitle, "")
        XCTAssertEqual(Set([info, info]).count, 1)
        XCTAssertEqual(WorkCalendarRules.maxShiftHours, 16)
    }

    // MARK: Het venster

    func testTheWindowForAMonthlySalaryStartsSixtyNineDaysBeforeTheFirstDay() {
        let d = hourlyData()
        let window = WorkCalendarWindow.window(for: d, today: noon(2026, 11, 4))
        XCTAssertEqual(window.from, day(2026, 10, 1).adding(days: -69), "2 maanden (62 dagen) plus een week voor de eerste dag")
        XCTAssertEqual(window.from, day(2026, 7, 24))
        XCTAssertEqual(window.through, day(2027, 11, 5), "een jaar (366 dagen) vooruit")
    }

    func testTheWindowForACycleUsesTwoCyclesAndAWeek() {
        var d = hourlyData()
        d.salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 10, 2))
        XCTAssertEqual(WorkCalendarWindow.window(for: d, today: noon(2026, 11, 4)).from, day(2026, 10, 1).adding(days: -63), "2 keer 28 dagen plus 7")
        d.salary.setSchedule(.days, interval: 10, anchor: day(2026, 10, 2))
        XCTAssertEqual(WorkCalendarWindow.window(for: d, today: noon(2026, 12, 20)).from, day(2026, 10, 1).adding(days: -27), "2 keer 10 dagen plus 7")
        XCTAssertEqual(WorkCalendarWindow.window(for: d, today: noon(2026, 11, 4)).from, day(2026, 11, 4).adding(days: -62),
                       "vandaag min 62 dagen is eerder dan de marge van een korte cyclus")
    }

    func testTheWindowNeverStartsLaterThan62DaysBeforeToday() {
        var d = hourlyData()
        d.setStart(day(2026, 12, 20))   // een startdatum in de toekomst
        let window = WorkCalendarWindow.window(for: d, today: noon(2026, 11, 4))
        XCTAssertEqual(window.from, day(2026, 11, 4).adding(days: -62), "de vorige periode moet in elk geval binnen het venster vallen")
        // Met een startdatum in het verleden wint de marge voor de startdag.
        d.setStart(day(2026, 8, 3))
        XCTAssertEqual(WorkCalendarWindow.window(for: d, today: noon(2026, 11, 4)).from, day(2026, 8, 3).adding(days: -69))
    }

    func testTheWindowStartsAtTheStartDayNotTheStartMonth() {
        var d = hourlyData()
        d.setStart(day(2026, 10, 20))
        XCTAssertEqual(WorkCalendarWindow.window(for: d, today: noon(2026, 11, 4)).from, day(2026, 10, 20).adding(days: -69))
    }

    // MARK: Wanneer verversen

    func testRefreshIsNeededWithoutASnapshotAndNotWhenItIsFresh() {
        var d = hourlyData()
        let today = noon(2026, 11, 4)
        XCTAssertTrue(WorkCalendarWindow.needsRefresh(d, today: today), "nog nooit gelezen")
        XCTAssertTrue(d.applyCalendarFetch(CalendarFetch(shifts: [shift(2026, 10, 5, from: 9, to: 17)], matched: [CalendarInfo(id: "1", title: "werken")]), today: today))
        XCTAssertFalse(WorkCalendarWindow.needsRefresh(d, today: today), "vandaag al ververst")
        XCTAssertFalse(WorkCalendarWindow.needsRefresh(d, today: noon(2026, 11, 4).addingTimeInterval(3 * 3_600)), "later op dezelfde dag")
    }

    func testRefreshIsNeededOnANewDay() {
        var d = hourlyData()
        d.applyCalendarFetch(CalendarFetch(matched: [CalendarInfo(id: "1", title: "werken")]), today: noon(2026, 11, 4))
        XCTAssertTrue(WorkCalendarWindow.needsRefresh(d, today: noon(2026, 11, 5)))
        XCTAssertTrue(WorkCalendarWindow.needsRefresh(d, today: noon(2026, 11, 3)), "ook een dag terug: de dag van verversen is niet vandaag")
    }

    func testRefreshIsNeededForAnotherCalendarName() {
        var d = hourlyData()
        let today = noon(2026, 11, 4)
        d.applyCalendarFetch(CalendarFetch(matched: [CalendarInfo(id: "1", title: "werken")]), today: today)
        d.work.calendarTitle = "Rooster"
        XCTAssertTrue(WorkCalendarWindow.needsRefresh(d, today: today))
        d.work.calendarTitle = "WERKEN"
        XCTAssertFalse(WorkCalendarWindow.needsRefresh(d, today: today), "dezelfde naam met andere hoofdletters")
    }

    func testRefreshIsNeededWhenTheWindowNoLongerFits() {
        var d = hourlyData()
        let today = noon(2026, 11, 4)
        d.applyCalendarFetch(CalendarFetch(matched: [CalendarInfo(id: "1", title: "werken")]), today: today)
        XCTAssertFalse(WorkCalendarWindow.needsRefresh(d, today: today))
        d.setStart(day(2026, 5, 1))   // de tijdlijn begint veel eerder: het gelezen venster begint te laat
        XCTAssertTrue(WorkCalendarWindow.needsRefresh(d, today: today))
        d.applyCalendarFetch(CalendarFetch(matched: [CalendarInfo(id: "1", title: "werken")]), today: today)
        XCTAssertFalse(WorkCalendarWindow.needsRefresh(d, today: today))
    }

    // MARK: Bewaren

    func testApplyingAFetchStoresTheSnapshotWithTheWindowAndTheName() {
        var d = hourlyData()
        d.work.calendarTitle = "Rooster"
        let today = noon(2026, 11, 4)
        let shifts = [shift(2026, 10, 6, from: 9, to: 17), shift(2026, 10, 5, from: 9, to: 17), shift(2026, 10, 5, from: 16, to: 18)]
        XCTAssertTrue(d.applyCalendarFetch(CalendarFetch(shifts: shifts, matched: [CalendarInfo(id: "1", title: "rooster")]), today: today))
        let snapshot = d.work.snapshot
        XCTAssertEqual(snapshot?.calendarTitle, "Rooster")
        XCTAssertEqual(snapshot?.fetchedDay, day(2026, 11, 4))
        XCTAssertEqual(snapshot?.from, WorkCalendarWindow.window(for: d, today: today).from)
        XCTAssertEqual(snapshot?.through, day(2027, 11, 5))
        XCTAssertEqual(snapshot?.shifts.count, 2, "sorteren en samenvoegen: de twee diensten van 5 oktober zijn er één")
        XCTAssertEqual(snapshot?.shifts.first?.durationMinutes, 9 * 60)
    }

    func testAnUnknownCalendarLeavesTheOldShiftsAlone() {
        var d = hourlyData()
        let today = noon(2026, 11, 4)
        d.applyCalendarFetch(CalendarFetch(shifts: [shift(2026, 10, 5, from: 9, to: 17)], matched: [CalendarInfo(id: "1", title: "werken")]), today: today)
        let before = d.work
        // Een agenda met die naam bestaat niet (meer): geen enkele agenda gevonden, de oude diensten blijven staan.
        XCTAssertFalse(d.applyCalendarFetch(CalendarFetch(skippedDeclined: 2), today: noon(2026, 11, 5)))
        XCTAssertEqual(d.work, before)
        XCTAssertEqual(d.work.snapshot?.shifts.count, 1)
        XCTAssertEqual(d.work.snapshot?.fetchedDay, day(2026, 11, 4), "de dag van verversen blijft die van de laatste echte verversing")
    }

    func testAnEmptyCalendarThatExistsGivesAFreshSnapshotAndZeroHours() {
        var d = hourlyData()
        let today = noon(2026, 11, 4)
        XCTAssertTrue(d.applyCalendarFetch(CalendarFetch(matched: [CalendarInfo(id: "1", title: "werken")]), today: today))
        XCTAssertEqual(d.work.snapshot?.shifts, [])
        XCTAssertEqual(d.salaryAmount(in: oct), 0, "een agenda zonder diensten: geen uren, dus geen salaris")
        XCTAssertEqual(d.workReport(forPayoutOn: day(2026, 10, 25))?.isAllExpected, false)
    }

    func testApplyingAFetchReplacesTheSnapshotAndDoesNotKeepAnythingElse() {
        var d = hourlyData()
        d.applyCalendarFetch(CalendarFetch(shifts: [shift(2026, 10, 5, from: 9, to: 17)], matched: [CalendarInfo(id: "1", title: "werken")]), today: noon(2026, 11, 3))
        d.applyCalendarFetch(CalendarFetch(shifts: [shift(2026, 10, 7, from: 9, to: 17)], matched: [CalendarInfo(id: "1", title: "werken")]), today: noon(2026, 11, 4))
        XCTAssertEqual(d.work.snapshot?.shifts.map { $0.startMinute }, [WorkShift.minute(of: engDate(cal, 2026, 10, 7, 9))], "de nieuwe ronde vervangt de oude")
        XCTAssertEqual(d.work.snapshot?.fetchedDay, day(2026, 11, 4))
    }

    // MARK: Met een nagemaakte agenda

    func testTheFlowFromPermissionToHoursWithAFakeCalendar() async throws {
        let source = FakeWorkCalendar(access: .notDetermined, grantedAfterRequest: .granted,
                                      calendars: [CalendarInfo(id: "a", title: "Werken", sourceTitle: "iCloud"), CalendarInfo(id: "b", title: "Privé", sourceTitle: "iCloud")],
                                      shifts: ["a": [shift(2026, 10, 5, from: 9, to: 17), shift(2026, 10, 6, from: 9, to: 17)],
                                               "b": [shift(2026, 10, 7, from: 9, to: 17)]])
        var d = hourlyData()
        let today = noon(2026, 11, 4)
        // Zonder toestemming gebeurt er niets, en er wordt niet gevraagd.
        var refreshed = try await engRefresh(&d, from: source, today: today)
        XCTAssertFalse(refreshed)
        XCTAssertEqual(source.fetchCount, 0)
        let listed = await source.calendars()
        XCTAssertTrue(listed.isEmpty, "zonder toegang ook geen lijst")
        // Na de tik van de gebruiker: toegang, dan verversen.
        let access = await source.requestAccess()
        XCTAssertEqual(access, .granted)
        refreshed = try await engRefresh(&d, from: source, today: today)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(source.fetchCount, 1)
        XCTAssertEqual(d.work.snapshot?.shifts.count, 2, "alleen de agenda 'Werken', niet 'Privé'")
        XCTAssertEqual(d.salaryAmount(in: oct), ((2 * 7.5) * 15).cents, "twee diensten van 7,5 uur betaald tegen 15 euro: 225")
        // Dezelfde dag nogmaals: niet nodig. Met geweld wel.
        refreshed = try await engRefresh(&d, from: source, today: today)
        XCTAssertFalse(refreshed)
        XCTAssertEqual(source.fetchCount, 1)
        refreshed = try await engRefresh(&d, from: source, today: today, force: true)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(source.fetchCount, 2)
        // De aanvraag gebruikte het venster van de Core.
        let window = WorkCalendarWindow.window(for: d, today: today)
        XCTAssertEqual(source.lastWindow?.from, window.from.date())
        XCTAssertEqual(source.lastWindow?.to, window.through.date())
    }

    func testDeniedAccessLeavesTheOldShiftsAndTheSalaryAlone() async throws {
        let source = FakeWorkCalendar(access: .denied, calendars: [CalendarInfo(id: "a", title: "werken")], shifts: ["a": []])
        var d = hourlyData()
        d.work.snapshot = engSnapshot([shift(2026, 10, 5, from: 9, to: 17)], fetched: day(2026, 11, 3))
        let before = d.work
        let refreshed = try await engRefresh(&d, from: source, today: noon(2026, 11, 4), force: true)
        XCTAssertFalse(refreshed)
        XCTAssertEqual(d.work, before)
        XCTAssertEqual(source.fetchCount, 0)
        for access in [CalendarAccess.writeOnly, .restricted, .notDetermined] {
            source.accessState = access
            let result = try await engRefresh(&d, from: source, today: noon(2026, 11, 4), force: true)
            XCTAssertFalse(result, "\(access)")
        }
    }

    func testAFailingFetchThrowsAndChangesNothing() async {
        struct Boom: Error {}
        let source = FakeWorkCalendar(calendars: [CalendarInfo(id: "a", title: "werken")])
        source.failure = Boom()
        var d = hourlyData()
        let before = d.work
        do {
            _ = try await engRefresh(&d, from: source, today: noon(2026, 11, 4))
            XCTFail("hoort te falen")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        XCTAssertEqual(d.work, before)
    }

    func testTwoCalendarsWithTheSameNameBothCountAndOverlapIsMerged() async throws {
        let source = FakeWorkCalendar(calendars: [CalendarInfo(id: "a", title: "werken", sourceTitle: "iCloud"), CalendarInfo(id: "b", title: "Werken", sourceTitle: "Op mijn iPhone")],
                                      shifts: ["a": [shift(2026, 10, 5, from: 9, to: 13)], "b": [shift(2026, 10, 5, from: 12, to: 17), shift(2026, 10, 6, from: 9, to: 17)]])
        var d = hourlyData()
        let refreshed = try await engRefresh(&d, from: source, today: noon(2026, 11, 4))
        XCTAssertTrue(refreshed)
        XCTAssertEqual(d.work.snapshot?.shifts.count, 2, "9-13 en 12-17 worden één dienst van 9-17")
        XCTAssertEqual(d.work.snapshot?.shifts.first?.durationMinutes, 8 * 60)
    }

    func testTheChangesStreamDeliversEachAnnouncement() async {
        let source = FakeWorkCalendar()
        let stream = source.changes()
        source.announceChange()
        source.announceChange()
        var received = 0
        for await _ in stream {
            received += 1
            if received == 2 { break }
        }
        XCTAssertEqual(received, 2)
    }
}
