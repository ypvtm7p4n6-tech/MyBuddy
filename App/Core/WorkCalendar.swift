import Foundation

// MARK: - De agenda als bron van diensten (zonder EventKit)
//
// Foundation-only, dus testbaar op Linux met een nagemaakte agenda. De echte agenda leest `EventKitWorkCalendar` (App/Calendar), de enige
// plek die EventKit kent (docs/work/plan.md B16). Alleen begin en einde van afspraken komen hier binnen; titels, notities, plaatsen en
// deelnemers verlaten de adapter nooit. De adapter en de controller zijn van golf 3A; hier staan het protocol en de rekenregels eromheen.

/// Mag de app de agenda lezen?
enum CalendarAccess: Equatable, Sendable {
    /// Er is nog niet gevraagd.
    case notDetermined
    /// Volledige toegang (iOS 17 en macOS 14 en nieuwer: `EKAuthorizationStatus.fullAccess`).
    case granted
    /// Alleen toevoegen: MyBuddy kan zo niets lezen.
    case writeOnly
    case denied
    /// Door een profiel of ouderlijk toezicht uitgezet.
    case restricted

    var canRead: Bool { self == .granted }
}

/// Een agenda zoals de gebruiker hem ziet. Het id verschilt per apparaat en wordt nooit opgeslagen.
struct CalendarInfo: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// Waar de agenda woont ("iCloud", "Op mijn iPhone").
    var sourceTitle: String

    init(id: String, title: String, sourceTitle: String = "") {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

/// Wat een ophaalronde opleverde, met wat er is overgeslagen (voor de melding op het scherm).
struct CalendarFetch: Equatable, Sendable {
    var shifts: [WorkShift] = []
    /// De agenda's met de gevraagde naam (meestal één). Leeg: zo'n agenda bestaat niet (of is niet te lezen).
    var matched: [CalendarInfo] = []
    var skippedAllDay = 0
    var skippedDeclined = 0
    var skippedCanceled = 0
    /// Afspraken van meer dan `WorkCalendarRules.maxShiftHours` uur (zo lang is geen dienst).
    var skippedTooLong = 0

    init(shifts: [WorkShift] = [], matched: [CalendarInfo] = [], skippedAllDay: Int = 0, skippedDeclined: Int = 0,
         skippedCanceled: Int = 0, skippedTooLong: Int = 0) {
        self.shifts = shifts
        self.matched = matched
        self.skippedAllDay = skippedAllDay
        self.skippedDeclined = skippedDeclined
        self.skippedCanceled = skippedCanceled
        self.skippedTooLong = skippedTooLong
    }

    var skippedTotal: Int { skippedAllDay + skippedDeclined + skippedCanceled + skippedTooLong }
}

enum WorkCalendarRules {
    /// Een afspraak langer dan dit (in uren) telt niet als dienst.
    static let maxShiftHours = 16
}

/// De agenda zoals de rest van de app hem ziet. Een nagemaakte versie in de tests; `EventKitWorkCalendar` in de app.
protocol WorkCalendarSource: Sendable {
    func access() async -> CalendarAccess
    /// Vraagt toestemming (de systeemvraag) en geeft de nieuwe stand.
    func requestAccess() async -> CalendarAccess
    func calendars() async -> [CalendarInfo]
    /// De diensten van de agenda('s) met deze naam tussen `from` en `to`, zonder hele-dag-afspraken (bij `allDayShiftHours == nil`) en
    /// zonder afgewezen of geannuleerde afspraken. Overlappende diensten zijn samengevoegd.
    func fetch(calendarTitle: String, from: Date, to: Date, allDayShiftHours: Double?) async throws -> CalendarFetch
    /// Een bericht zodra de agenda in het systeem verandert.
    func changes() -> AsyncStream<Void>
}

enum CalendarTitle {
    /// Dezelfde naam? Hoofdletters, accenten en spaties aan de randen tellen niet ("Werken" is "werken").
    static func matches(_ a: String, _ b: String) -> Bool {
        fold(a) == fold(b)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Het venster en wanneer verversen nodig is

enum WorkCalendarWindow {
    /// Het venster dat nodig is: vanaf een marge vóór de eerste dag van de tijdlijn (de uren van een uitbetaling in de eerste maand komen
    /// uit de periode ervoor: twee cycli plus een week, bij een salaris per maand 69 dagen), maar niet later dan 62 dagen voor vandaag,
    /// tot een jaar (366 dagen) vooruit.
    static func window(for data: FinanceData, today: Date, calendar: Calendar = YearMonth.calendar) -> (from: CalendarDay, through: CalendarDay) {
        let todayDay = CalendarDay(date: today, calendar: calendar)
        let margin = (data.salary.cycleDays.map { 2 * $0 } ?? 62) + 7
        let first = data.firstDay.adding(days: -margin)
        let from = min(first, todayDay.adding(days: -62))
        return (from, todayDay.adding(days: 366))
    }

    /// Moet de agenda opnieuw gelezen worden? Zonder diensten ooit, bij een andere agendanaam, een venster dat niet meer past of een laatste
    /// verversing van vóór vandaag. Of de gegevens de agenda wel gebruiken (`FinanceData.usesCalendarHours`) beslist de aanroeper.
    static func needsRefresh(_ data: FinanceData, today: Date, calendar: Calendar = YearMonth.calendar) -> Bool {
        guard let snapshot = data.work.snapshot else { return true }
        let needed = window(for: data, today: today, calendar: calendar)
        return !CalendarTitle.matches(snapshot.calendarTitle, data.work.calendarTitle)
            || snapshot.fetchedDay != CalendarDay(date: today, calendar: calendar)
            || snapshot.from > needed.from
    }

    /// Het resultaat van een ophaalronde als opgeslagen toestand.
    static func snapshot(from fetch: CalendarFetch, data: FinanceData, today: Date,
                         calendar: Calendar = YearMonth.calendar) -> WorkSnapshot {
        let w = window(for: data, today: today, calendar: calendar)
        return WorkSnapshot(shifts: fetch.shifts, from: w.from, through: w.through,
                            fetchedDay: CalendarDay(date: today, calendar: calendar), calendarTitle: data.work.calendarTitle)
    }
}

extension FinanceData {
    /// Bewaart wat een ophaalronde opleverde als de afgeleide diensten (`work.snapshot`) en zegt of dat gebeurde. Bestaat er geen agenda met
    /// de gevraagde naam (`fetch.matched` is leeg), dan blijft alles zoals het was en is het antwoord false: de oude diensten blijven
    /// staan en de pagina Werkuren zegt waarom. Een agenda die wel bestaat maar leeg is, geeft een ververste snapshot zonder diensten
    /// (0 uur, geen terugval op je gemiddelde tot en met vandaag).
    @discardableResult
    mutating func applyCalendarFetch(_ fetch: CalendarFetch, today: Date) -> Bool {
        guard !fetch.matched.isEmpty else { return false }
        work.snapshot = WorkCalendarWindow.snapshot(from: fetch, data: self, today: today)
        return true
    }
}
