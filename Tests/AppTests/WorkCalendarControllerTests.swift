import XCTest
@testable import MyBuddy

/// `WorkCalendarController` met een nagemaakte agenda: toegang, verversen en wat er in de gegevens komt. EventKit wordt niet geraakt.
@MainActor
final class WorkCalendarControllerTests: XCTestCase {
    private final class Source: WorkCalendarSource, @unchecked Sendable {
        var state: CalendarAccess
        var afterRequest: CalendarAccess
        var list: [CalendarInfo]
        var samples: [CalendarEventSample]
        var failing = false
        private(set) var fetches = 0

        init(state: CalendarAccess = .granted, afterRequest: CalendarAccess = .granted,
             list: [CalendarInfo] = [CalendarInfo(id: "w", title: "werken", sourceTitle: "iCloud")],
             samples: [CalendarEventSample] = []) {
            self.state = state
            self.afterRequest = afterRequest
            self.list = list
            self.samples = samples
        }

        func access() async -> CalendarAccess { state }
        func requestAccess() async -> CalendarAccess {
            if state == .notDetermined { state = afterRequest }
            return state
        }
        func calendars() async -> [CalendarInfo] { state.canRead ? list : [] }
        func fetch(calendarTitle: String, from: Date, to: Date, allDayShiftHours: Double?) async throws -> CalendarFetch {
            fetches += 1
            if failing { throw URLError(.cannotOpenFile) }
            let matched = list.filter { CalendarTitle.matches($0.title, calendarTitle) }
            guard !matched.isEmpty else { return CalendarFetch(matched: []) }
            return WorkCalendarRules.collect(samples.filter { $0.start >= from && $0.start < to }, matched: matched,
                                             allDayShiftHours: allDayShiftHours)
        }
        func changes() -> AsyncStream<Void> { AsyncStream { _ in } }
    }

    private func hourlyStore() -> AppStore {
        let store = AppStore(storage: nil)
        store.mutate { data in
            data.salary.mode = .hourly
            data.salary.hourlyRate = 20
            data.work.hoursSource = .calendar
        }
        return store
    }

    private func shift(daysFromNow days: Int, hours: Double = 8) -> CalendarEventSample {
        let start = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))!
            .addingTimeInterval(9 * 3600)
        return CalendarEventSample(start: start, end: start.addingTimeInterval(hours * 3600))
    }

    func testRefreshWritesTheShiftsIntoTheData() async {
        let source = Source(samples: [shift(daysFromNow: -3), shift(daysFromNow: -2), shift(daysFromNow: 4)])
        let controller = WorkCalendarController(source: source)
        let store = hourlyStore()
        await controller.prepare()
        await controller.refresh(into: store)
        XCTAssertEqual(store.data.work.snapshot?.shifts.count, 3)
        XCTAssertEqual(controller.lastFetch?.matched.count, 1)
        XCTAssertNotNil(controller.refreshedAt)
        XCTAssertNil(controller.lastError)
    }

    func testWithoutAccessTheOldShiftsStay() async {
        let source = Source(samples: [shift(daysFromNow: -1)])
        let controller = WorkCalendarController(source: source)
        let store = hourlyStore()
        await controller.refresh(into: store, force: true)
        XCTAssertEqual(store.data.work.snapshot?.shifts.count, 1)

        source.state = .denied
        source.samples = []
        let denied = WorkCalendarController(source: source)
        await denied.prepare()
        await denied.refresh(into: store, force: true)
        XCTAssertEqual(store.data.work.snapshot?.shifts.count, 1, "geen toegang: de oude diensten blijven staan")
        XCTAssertEqual(denied.access, .denied)
    }

    func testNoCalendarWithThatNameKeepsTheOldShifts() async {
        let source = Source(samples: [shift(daysFromNow: -1)])
        let controller = WorkCalendarController(source: source)
        let store = hourlyStore()
        await controller.refresh(into: store, force: true)
        store.mutate { $0.work.calendarTitle = "dienst" }
        await controller.refresh(into: store, force: true)
        XCTAssertEqual(controller.lastFetch?.matched.isEmpty, true)
        XCTAssertEqual(store.data.work.snapshot?.shifts.count, 1)
        XCTAssertEqual(store.data.work.snapshot?.calendarTitle, "werken")
    }

    func testWithoutCalendarHoursNothingIsFetchedUnlessForced() async {
        let source = Source(samples: [shift(daysFromNow: -1)])
        let controller = WorkCalendarController(source: source)
        let store = hourlyStore()
        store.mutate { $0.work.hoursSource = .manual }
        await controller.refresh(into: store)
        XCTAssertEqual(source.fetches, 0)
        await controller.refresh(into: store, force: true)
        XCTAssertEqual(source.fetches, 1)
    }

    func testRequestingAccessAsksOnceAndReadsTheCalendars() async {
        let source = Source(state: .notDetermined)
        let controller = WorkCalendarController(source: source)
        await controller.prepare()
        XCTAssertEqual(controller.access, .notDetermined)
        XCTAssertTrue(controller.calendars.isEmpty)
        let result = await controller.requestAccess()
        XCTAssertEqual(result, .granted)
        XCTAssertEqual(controller.calendars.map(\.title), ["werken"])
    }

    func testAFailingFetchShowsAnErrorAndChangesNothing() async {
        let source = Source(samples: [shift(daysFromNow: -1)])
        source.failing = true
        let controller = WorkCalendarController(source: source)
        let store = hourlyStore()
        await controller.refresh(into: store, force: true)
        XCTAssertNotNil(controller.lastError)
        XCTAssertNil(store.data.work.snapshot)
    }

    func testTheSalaryOfAPayoutFollowsTheCalendar() async {
        let source = Source(samples: (-40...40).map { shift(daysFromNow: $0) })
        let controller = WorkCalendarController(source: source)
        let store = hourlyStore()
        await controller.refresh(into: store, force: true)
        guard let next = store.data.upcomingPayoutDays(count: 1, after: Date()).first,
              let report = store.data.workReport(forPayoutOn: next) else {
            return XCTFail("er hoort een volgende uitbetaling met uren te zijn")
        }
        XCTAssertGreaterThan(report.agendaMinutes, 0)
        XCTAssertEqual(store.data.workPayoutCents(on: next), report.amountCents)
    }
}
