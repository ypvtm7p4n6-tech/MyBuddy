import XCTest
import EventKit
@testable import MyBuddy

/// De echte agenda van het systeem (EventKit), geen nagemaakte: de test maakt in de agenda van de simulator een agenda met afspraken,
/// en MyBuddy leest die via `EventKitWorkCalendar` en `WorkCalendarController` in de gegevens, zoals op een toestel. CI geeft de app
/// vooraf toegang (`xcrun simctl privacy ... grant calendar nl.mybuddy.app`); zonder toegang wordt de test overgeslagen.
@MainActor
final class EventKitCalendarTests: XCTestCase {
    func testTheRealCalendarFeedsTheSalaryOfAPayout() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else { throw XCTSkip("geen volledige agendatoegang in deze simulator (status \(status.rawValue))") }
        let eventStore = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        let title = "Werken \(UUID().uuidString.prefix(6))"
        calendar.title = title
        guard let source = eventStore.defaultCalendarForNewEvents?.source
                ?? eventStore.sources.first(where: { $0.sourceType == .local }) else {
            throw XCTSkip("de simulator heeft geen agendabron")
        }
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        defer { try? eventStore.removeCalendar(calendar, commit: true) }

        // Tien diensten van 8 uur rond vandaag, twee die elkaar overlappen (worden samengevoegd) en een hele-dag-afspraak (telt niet).
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in -5..<5 {
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            event.title = "dienst"
            event.startDate = day.addingTimeInterval(9 * 3600)
            event.endDate = day.addingTimeInterval(17 * 3600)
            try eventStore.save(event, span: .thisEvent, commit: false)
        }
        let overlap = EKEvent(eventStore: eventStore)
        overlap.calendar = calendar
        overlap.title = "overwerk"
        overlap.startDate = today.addingTimeInterval(16 * 3600)
        overlap.endDate = today.addingTimeInterval(19 * 3600)
        try eventStore.save(overlap, span: .thisEvent, commit: false)
        let allDay = EKEvent(eventStore: eventStore)
        allDay.calendar = calendar
        allDay.title = "vrij"
        allDay.isAllDay = true
        allDay.startDate = cal.date(byAdding: .day, value: 1, to: today)!
        allDay.endDate = cal.date(byAdding: .day, value: 2, to: today)!
        try eventStore.save(allDay, span: .thisEvent, commit: true)

        // De adapter zelf: alleen begin en einde, op naam (hoofdletters tellen niet), samengevoegd, hele dag overgeslagen.
        let adapter = EventKitWorkCalendar()
        let access = await adapter.access()
        XCTAssertEqual(access, .granted)
        let found = await adapter.calendars()
        XCTAssertTrue(found.contains { $0.title == title }, "de nieuwe agenda staat in de lijst")
        let fetch = try await adapter.fetch(calendarTitle: title.lowercased(),
                                            from: cal.date(byAdding: .day, value: -10, to: today)!,
                                            to: cal.date(byAdding: .day, value: 10, to: today)!, allDayShiftHours: nil)
        XCTAssertEqual(fetch.matched.count, 1)
        XCTAssertEqual(fetch.shifts.count, 10, "tien diensten; de overlap is samengevoegd")
        XCTAssertEqual(fetch.skippedAllDay, 1)
        XCTAssertTrue(fetch.shifts.contains { $0.durationMinutes == 10 * 60 }, "vandaag 9:00 tot 19:00 na samenvoegen")

        // De hele keten: controller → gegevens → uitbetaling.
        let store = AppStore(storage: nil)
        store.mutate { data in
            data.salary.mode = .hourly
            data.salary.hourlyRate = 20
            data.work.hoursSource = .calendar
            data.work.calendarTitle = title
        }
        let controller = WorkCalendarController(source: adapter)
        await controller.prepare()
        await controller.refresh(into: store, force: true)
        XCTAssertNil(controller.lastError)
        XCTAssertEqual(store.data.work.snapshot?.shifts.count, 10, "de diensten uit de echte agenda staan in de gegevens")
        let payouts = store.data.upcomingPayoutDays(count: 4, after: cal.date(byAdding: .day, value: -40, to: today)!)
        let reports = payouts.compactMap { store.data.workReport(forPayoutOn: $0) }
        XCTAssertTrue(reports.contains { $0.agendaMinutes > 0 }, "een uitbetaling rekent met de uren uit de agenda")
    }
}
