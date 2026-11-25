import Foundation
import EventKit

// MARK: - De echte agenda (EventKit)
//
// De enige plek in de app die EventKit kent (docs/work/plan.md par. 4.1). Alleen begin, einde en drie kenmerken (hele dag, geannuleerd,
// afgewezen) verlaten deze actor; titels, notities, plaatsen en deelnemers niet. Welke afspraken meetellen en hoe ze diensten worden,
// beslist de rekenmotor (`WorkCalendarRules.collect`), zodat die regels zonder agenda getest worden.

actor EventKitWorkCalendar: WorkCalendarSource {
    private let store = EKEventStore()

    func access() async -> CalendarAccess {
        Self.access(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async -> CalendarAccess {
        _ = try? await store.requestFullAccessToEvents()
        // Zonder `reset()` ziet een eerder gemaakte winkel de agenda's na de toestemming nog niet.
        store.reset()
        return Self.access(EKEventStore.authorizationStatus(for: .event))
    }

    func calendars() async -> [CalendarInfo] {
        guard Self.access(EKEventStore.authorizationStatus(for: .event)).canRead else { return [] }
        return store.calendars(for: .event)
            .filter { $0.type != .birthday }
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "") }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func fetch(calendarTitle: String, from: Date, to: Date, allDayShiftHours: Double?) async throws -> CalendarFetch {
        guard Self.access(EKEventStore.authorizationStatus(for: .event)).canRead else { return CalendarFetch() }
        let matching = store.calendars(for: .event).filter { CalendarTitle.matches($0.title, calendarTitle) }
        let matched = matching.map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "") }
        guard !matching.isEmpty, to > from else { return CalendarFetch(matched: matched) }
        var samples: [CalendarEventSample] = []
        // EventKit zoekt hooguit vier jaar per vraag: daarom per jaar. Terugkerende afspraken komen als losse voorkomens.
        var cursor = from
        var seen = Set<String>()
        while cursor < to {
            let end = min(to, cursor.addingTimeInterval(365 * 86_400))
            let predicate = store.predicateForEvents(withStart: cursor, end: end, calendars: matching)
            for event in store.events(matching: predicate) {
                guard let start = event.startDate, let finish = event.endDate else { continue }
                // Een afspraak over de grens van twee vragen komt twee keer terug: één keer tellen.
                let key = "\(event.calendarItemIdentifier)|\(start.timeIntervalSince1970)"
                guard seen.insert(key).inserted else { continue }
                samples.append(CalendarEventSample(start: start, end: finish, isAllDay: event.isAllDay,
                                                   isCanceled: event.status == .canceled,
                                                   isDeclined: Self.isDeclined(event)))
            }
            cursor = end
        }
        return WorkCalendarRules.collect(samples, matched: matched, allDayShiftHours: allDayShiftHours)
    }

    nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: nil) { _ in
                continuation.yield()
            }
            let box = ObserverBox(token)
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(box.token) }
        }
    }

    // MARK: Hulpen

    static func access(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Ben jij uitgenodigd en heb je nee gezegd?
    private static func isDeclined(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees else { return false }
        return attendees.contains { $0.isCurrentUser && $0.participantStatus == .declined }
    }
}

/// Bewaart het token van een waarnemer voor `onTermination` (anders een Swift 6-waarschuwing over een niet-`Sendable` waarde).
private final class ObserverBox: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
}
