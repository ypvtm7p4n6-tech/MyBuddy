import Foundation
import Observation

// MARK: - De agenda voor de schermen
//
// Houdt bij of MyBuddy de agenda mag lezen, welke agenda's er zijn en wat de laatste ophaalronde opleverde, en schrijft de diensten
// in de gegevens (`FinanceData.applyCalendarFetch`). Eén controller voor de hele app (op `MyBuddyApp`), ook in het Instellingen-venster
// van de Mac. Verversen gebeurt bij het openen van de app, als de app weer actief wordt, kort na een wijziging in de agenda en met de
// knop "Nu verversen" op Werkuren; alleen als de uren van je salaris uit de agenda komen (of met `force`) en alleen met toegang.

@MainActor
@Observable
final class WorkCalendarController {
    private(set) var access: CalendarAccess = .notDetermined
    private(set) var calendars: [CalendarInfo] = []
    private(set) var isRefreshing = false
    /// Wat de laatste ophaalronde van deze sessie opleverde (nil: nog niet opgehaald sinds de app opende).
    private(set) var lastFetch: CalendarFetch?
    /// Het moment van de laatste geslaagde verversing in deze sessie (de opgeslagen snapshot kent alleen de dag).
    private(set) var refreshedAt: Date?
    private(set) var lastError: String?
    /// Loopt op bij elke wijziging in de agenda van het systeem; `RootView` ververst er kort daarna op.
    private(set) var changeCount = 0

    @ObservationIgnored private let source: any WorkCalendarSource
    @ObservationIgnored private var watcher: Task<Void, Never>?

    init(source: any WorkCalendarSource = EventKitWorkCalendar()) {
        self.source = source
    }

    /// Leest de toestemming (zonder te vragen) en de agenda's, en begint te luisteren naar wijzigingen.
    func prepare() async {
        access = await source.access()
        calendars = access.canRead ? await source.calendars() : []
        startWatching()
    }

    /// Stelt de systeemvraag (alleen na een tik van de gebruiker) en geeft de nieuwe stand.
    @discardableResult
    func requestAccess() async -> CalendarAccess {
        access = await source.requestAccess()
        calendars = access.canRead ? await source.calendars() : []
        startWatching()
        return access
    }

    /// Haalt de diensten op en schrijft ze in de gegevens. Zonder `force` alleen als de uren uit de agenda komen en de opgeslagen diensten
    /// verouderd zijn (`WorkCalendarWindow.needsRefresh`). Zonder toegang verandert er niets: de oude diensten blijven staan.
    func refresh(into store: AppStore, force: Bool = false, today: Date = Date()) async {
        guard !isRefreshing else { return }
        if !access.canRead { access = await source.access() }
        guard access.canRead else { return }
        let data = store.data
        guard force || (data.usesCalendarHours && WorkCalendarWindow.needsRefresh(data, today: today)) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let window = WorkCalendarWindow.window(for: data, today: today)
        let calendar = YearMonth.calendar
        let from = calendar.startOfDay(for: window.from.date(calendar: calendar))
        let through = calendar.startOfDay(for: window.through.date(calendar: calendar))
        let to = calendar.date(byAdding: .day, value: 1, to: through) ?? through
        do {
            let fetch = try await source.fetch(calendarTitle: data.work.calendarTitle, from: from, to: to,
                                               allDayShiftHours: data.work.allDayShiftHours)
            lastFetch = fetch
            lastError = nil
            calendars = await source.calendars()
            var applied = false
            store.mutate { applied = $0.applyCalendarFetch(fetch, today: today) }
            // Gelijke diensten van dezelfde dag veranderen niets aan de gegevens; ook dan is de agenda net gelezen.
            if applied || !fetch.matched.isEmpty { refreshedAt = today }
        } catch {
            lastError = "De agenda kon niet worden gelezen. Probeer het later opnieuw."
        }
    }

    private func startWatching() {
        guard watcher == nil, access.canRead else { return }
        let stream = source.changes()
        watcher = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                self.changeCount += 1
            }
        }
    }
}

#if DEBUG
// MARK: - Een vaste agenda voor screenshots en previews

/// Een agenda "werken" met vaste diensten rond vandaag: doordeweeks 9:00 tot 17:30, om de week een zondag 10:00 tot 16:00. Voor
/// `-mybuddy-demo` en de previews; geen EventKit.
struct DemoWorkCalendar: WorkCalendarSource {
    var state: CalendarAccess = .granted
    var calendarTitle = "werken"

    func access() async -> CalendarAccess { state }
    func requestAccess() async -> CalendarAccess { state }

    func calendars() async -> [CalendarInfo] {
        guard state.canRead else { return [] }
        return [CalendarInfo(id: "demo-werken", title: calendarTitle, sourceTitle: "iCloud"),
                CalendarInfo(id: "demo-thuis", title: "Thuis", sourceTitle: "iCloud")]
    }

    func fetch(calendarTitle: String, from: Date, to: Date, allDayShiftHours: Double?) async throws -> CalendarFetch {
        guard state.canRead, CalendarTitle.matches(calendarTitle, self.calendarTitle) else {
            return CalendarFetch(matched: [])
        }
        let matched = [CalendarInfo(id: "demo-werken", title: self.calendarTitle, sourceTitle: "iCloud")]
        return WorkCalendarRules.collect(Self.samples(from: from, to: to), matched: matched, allDayShiftHours: allDayShiftHours)
    }

    func changes() -> AsyncStream<Void> { AsyncStream { _ in } }

    static func samples(from: Date, to: Date, calendar: Calendar = YearMonth.calendar) -> [CalendarEventSample] {
        var result: [CalendarEventSample] = []
        var day = calendar.startOfDay(for: from)
        var guardCount = 0
        while day < to && guardCount < 800 {
            let weekday = calendar.component(.weekday, from: day)
            let week = calendar.component(.weekOfYear, from: day)
            func at(_ hour: Int, _ minute: Int = 0) -> Date? {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            }
            if (2...6).contains(weekday), let start = at(9), let end = at(17, 30) {
                result.append(CalendarEventSample(start: start, end: end))
            } else if weekday == 1, week % 2 == 0, let start = at(10), let end = at(16) {
                result.append(CalendarEventSample(start: start, end: end))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            guardCount += 1
        }
        return result
    }
}
#endif
