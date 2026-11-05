import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat dit
// bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in WorkDisplayTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - De teksten van de werkuren uit je agenda
//
// Alle teksten van de pagina Werkuren, van de kaart "Uren van de volgende uitbetalingen" op Salaris en van de plekken waar een
// salaris uit de agenda wordt uitgelegd (Inkomen, Dag voor dag, Home). Ze volgen de termenlijst (docs/design/plan.md par. 2.8):
// "diensten" voor wat uit de agenda komt, "toeslag", "pauze", "uit je gemiddelde" voor wat de agenda nog niet kent. Het aantal uren,
// het bedrag en de datum komen steeds uit de rekenmotor (`WorkHoursReport`, `PayoutHours`, `WorkSnapshot`); hier staan alleen woorden.

/// Eén regel van de uitleg bij een uitbetaling uit de agenda: wat en hoeveel.
struct WorkBreakdownLine: Equatable, Identifiable {
    let id: String
    let title: String
    let value: String
    /// Een korte toelichting onder de regel (bijvoorbeeld welke toeslag het is), of nil.
    var note: String? = nil
}

/// Wat de gebruiker te zien krijgt als de agenda niet gelezen mag worden, en wat hij daaraan kan doen.
enum WorkAccessAction: Equatable {
    /// De systeemvraag stellen (alleen na een tik van de gebruiker).
    case requestAccess
    /// Naar Instellingen van het systeem.
    case openSettings

    /// De titel van de knop.
    var title: String {
        switch self {
        case .requestAccess: return "Toegang geven"
        case .openSettings: return "Open Instellingen"
        }
    }
}

/// De melding bij de toestand van de toegang tot de agenda (`WorkText.accessText`).
struct WorkAccessText: Equatable {
    var title: String
    var message: String
    /// nil: er is niets te doen (de toegang is in orde).
    var action: WorkAccessAction?

    /// Moet de pagina een melding tonen?
    var needsAction: Bool { action != nil }
}

enum WorkText {
    // MARK: Vaste teksten

    static let pageTitle = "Werkuren"
    static let symbol = "clock"
    static let sourceTitle = "Uren uit je agenda"
    static let calendarTitle = "Agenda"
    static let periodTitle = "Uren van"
    static let combineTitle = "Bij meer toeslagen"
    static let refreshTitle = "Nu verversen"
    static let allDayTitle = "Hele-dag-afspraken tellen mee"
    static let allDayHoursTitle = "Uren per hele dag"
    static let addRuleTitle = "Toeslag toevoegen"
    static let addBreakTitle = "Pauzeregel toevoegen"
    static let addHolidayTitle = "Eigen feestdag toevoegen"
    static let fillAverageTitle = "Gemiddelde uit je agenda invullen"
    static let freezeTitle = "Eerdere maanden vastleggen"
    static let upcomingTitle = "Uren van de volgende uitbetalingen"
    static let previewTitle = "Voorbeeld"
    static let rulesTitle = "Toeslagen"
    static let breaksTitle = "Pauzes"
    static let holidaysTitle = "Feestdagen"
    static let managementTitle = "Beheer"
    static let manualHoursTitle = "Uren per week invullen"
    static let factorTitle = "Factor"
    static let breakFromTitle = "Vanaf"
    static let breakMinutesTitle = "Onbetaalde pauze"
    /// De keuzes van het menu "Toeslag toevoegen".
    static let addWeekdayTitle = "Weekdag"
    static let addHolidayRuleTitle = "Feestdag"
    static let addDateTitle = "Eigen datum"

    /// Voetnoot bij de keuze van de bron: ook het verleden volgt de agenda.
    static let sourceFooter = "Dit geldt ook voor eerdere maanden vanaf je startdatum. Maanden zonder diensten in je agenda krijgen geen salaris."
    /// Onder de pauzeregels.
    static let breakFooter = "De pauze is onbetaald en gaat van de dienst af."
    /// Onder de feestdagen.
    static let holidaysFooter = "Oudejaarsdag geldt de hele dag."
    /// Onder het Beheer.
    static let privacyFooter = "MyBuddy bewaart alleen begin en einde van je diensten, geen titels of notities."
    /// Bij de overschrijving van een maand: eigen uren rekenen anders dan uren uit de agenda.
    static let ownHoursNote = "Eigen uren rekenen uren × uurloon, zonder toeslagen."
    /// Het veld "uren per week" als de uren uit de agenda komen.
    static let averageHoursTitle = "Gemiddeld aantal uren per week"
    static let averageHoursNote = "Voor schattingen en voor wat nog niet in je agenda staat."
    /// De formule onder het uurloon.
    static let formula = "Uurloon × uren uit je agenda, met toeslagen en pauzes"
    /// Als een periode niets uit de agenda geeft.
    static let nothingInCalendarNote = "Nog geen diensten in je agenda voor deze periode: MyBuddy rekent met je gemiddelde uren."
    /// Bij de bron "agenda" terwijl het salaris een vast bedrag is: de agenda doet dan niets.
    static let fixedSalaryNote = "Uren uit je agenda gelden alleen bij een uurloon. Stel je salaris in als uurloon om ze te gebruiken."
    /// De bevestiging bij "Eerdere maanden vastleggen".
    static let freezeMessage = "Het salaris van de maanden voor deze maand blijft zoals het nu is, ook als je agenda of je regels later veranderen."

    // MARK: Uren, perioden en bedragen

    /// "38,5 uur", "1 uur", "0 uur": hele minuten als uren.
    static func hours(_ minutes: Int) -> String {
        Fmt.hours(minutes: minutes)
    }

    /// De zin bij een uitbetaling uit de agenda: "uit agenda: 38,5 uur"; gemengd "uit agenda: 24 uur, plus 14,5 uur uit je gemiddelde";
    /// helemaal verwacht "verwacht uit je gemiddelde: 38,5 uur". nil zonder uren (een uitbetaling die niet uit de agenda komt).
    static func payoutDetail(_ hours: PayoutHours?) -> String? {
        hours?.detailText
    }

    /// De dagen van een periode: "24 okt t/m 20 nov"; over een jaargrens heen met het jaar erbij ("28 dec 2026 t/m 24 jan 2027").
    static func periodText(_ range: ClosedRange<Int>) -> String {
        let first = CalendarDay(dayNumber: range.lowerBound)
        let last = CalendarDay(dayNumber: range.upperBound)
        func text(_ day: CalendarDay, withYear: Bool) -> String {
            "\(day.day) \(Fmt.shortMonthNames[min(max(day.month, 1), 12) - 1])" + (withYear ? " \(day.year)" : "")
        }
        let withYear = first.year != last.year
        return "\(text(first, withYear: withYear)) t/m \(text(last, withYear: withYear))"
    }

    /// "× 1,5", "× 2" en "× 1,25": een factor op het uurloon.
    static func factorText(_ factor: Double) -> String {
        "× \(Fmt.input(factor.isFinite ? factor : 1, maxDigits: 2))"
    }

    /// Zoals `factorText(_:)`, voor een factor in honderdsten (150 is "× 1,5").
    static func factorText(hundredths: Int) -> String {
        factorText(Double(hundredths) / 100)
    }

    /// De naam van een dag van de week met een hoofdletter (1 = zondag ... 7 = zaterdag).
    static func weekdayTitle(_ weekday: Int) -> String {
        let names = ["Zondag", "Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag"]
        return names[min(max(weekday, 1), 7) - 1]
    }

    /// De naam van een toeslag: "Zondag", "Feestdag" of "5 december 2026".
    static func ruleTitle(_ rule: PayRule) -> String {
        switch rule.kind {
        case .weekday(let n): return weekdayTitle(n)
        case .holiday: return "Feestdag"
        case .date(let day): return Fmt.longDate(day)
        }
    }

    /// De toeslag in één regel: "Zondag × 1,5".
    static func ruleLine(_ rule: PayRule) -> String {
        "\(ruleTitle(rule)) \(factorText(rule.factor))"
    }

    /// De pauzeregel in één regel: "Vanaf 5,5 uur: 30 min pauze".
    static func breakTitle(_ rule: BreakRule) -> String {
        "Vanaf \(Fmt.input(rule.fromHours)) uur: \(rule.minutes) min pauze"
    }

    /// De keuze "Uren van": deze periode of de vorige.
    static func periodBasisTitle(_ basis: HoursPeriodBasis) -> String {
        switch basis {
        case .current: return "Deze periode"
        case .previous: return "De vorige periode"
        }
    }

    /// De keuze "Bij meer toeslagen": de hoogste telt of optellen.
    static func combineTitle(_ combine: PayCombine) -> String {
        switch combine {
        case .highest: return "Hoogste telt"
        case .add: return "Optellen"
        }
    }

    // MARK: De uitleg bij een uitbetaling

    /// De regels onder een uitbetaling uit de agenda, in deze volgorde (alleen wat er is): Uren, Gewerkt, Gepland, Verwacht, een regel
    /// per toeslag, Pauze en Bedrag. `rules` zegt bij welke toeslag een factor hoort. Alle getallen komen uit het rapport.
    static func breakdown(_ report: WorkHoursReport, rules: WorkRules) -> [WorkBreakdownLine] {
        var lines: [WorkBreakdownLine] = [WorkBreakdownLine(id: "hours", title: "Uren", value: hours(report.paidMinutes))]
        if report.workedMinutes > 0 { lines.append(WorkBreakdownLine(id: "worked", title: "Gewerkt", value: hours(report.workedMinutes))) }
        if report.plannedMinutes > 0 { lines.append(WorkBreakdownLine(id: "planned", title: "Gepland", value: hours(report.plannedMinutes))) }
        if report.expectedMinutes > 0 {
            lines.append(WorkBreakdownLine(id: "expected", title: "Verwacht", value: hours(report.expectedMinutes), note: "uit je gemiddelde"))
        }
        for entry in report.byFactor where entry.factor != 100 && entry.minutes > 0 {
            let names = rules.payRules.filter { $0.isEnabled && $0.factorHundredths == entry.factor }.map { ruleTitle($0).lowercased() }
            var seen = Set<String>()
            let unique = names.filter { seen.insert($0).inserted }
            lines.append(WorkBreakdownLine(id: "factor-\(entry.factor)", title: "Toeslag \(factorText(hundredths: entry.factor))",
                                           value: hours(entry.minutes), note: unique.isEmpty ? nil : unique.joined(separator: ", ")))
        }
        if report.breakMinutes > 0 {
            lines.append(WorkBreakdownLine(id: "break", title: "Pauze", value: hours(report.breakMinutes), note: "onbetaald"))
        }
        lines.append(WorkBreakdownLine(id: "amount", title: "Bedrag", value: Fmt.euroExact(CentsMath.value(report.amountCents))))
        return lines
    }

    // MARK: De agenda en de toegang

    /// De melding bij de toestand van de toegang tot de agenda.
    static func accessText(_ access: CalendarAccess) -> WorkAccessText {
        switch access {
        case .notDetermined:
            return WorkAccessText(title: "MyBuddy mag je agenda nog niet lezen",
                                  message: "Geef toegang, dan haalt MyBuddy het begin en einde van je diensten op. Titels en notities worden niet gelezen.",
                                  action: .requestAccess)
        case .denied:
            return WorkAccessText(title: "MyBuddy mag je agenda niet lezen",
                                  message: "Zet de toegang aan bij Instellingen, dan kan MyBuddy je diensten ophalen.",
                                  action: .openSettings)
        case .restricted:
            return WorkAccessText(title: "Je agenda is niet beschikbaar voor MyBuddy",
                                  message: "Een profiel of ouderlijk toezicht houdt de toegang tot de agenda tegen. Wijzig dat bij Instellingen van je apparaat.",
                                  action: .openSettings)
        case .writeOnly:
            return WorkAccessText(title: "Zet de toegang op volledig",
                                  message: "MyBuddy mag nu alleen afspraken toevoegen, niet lezen. Kies bij Instellingen volledige toegang tot de agenda.",
                                  action: .openSettings)
        case .granted:
            return WorkAccessText(title: "MyBuddy mag je agenda lezen", message: "", action: nil)
        }
    }

    /// Welke agenda('s) er gevonden zijn: "Gevonden: 1 agenda (iCloud)", "2 agenda's met deze naam: beide tellen mee" of dat er geen is.
    static func matchedText(_ matched: [CalendarInfo], title: String) -> String {
        switch matched.count {
        case 0:
            return "Geen agenda met de naam \u{201C}\(title)\u{201D} gevonden."
        case 1:
            let source = matched[0].sourceTitle
            return source.isEmpty ? "Gevonden: 1 agenda" : "Gevonden: 1 agenda (\(source))"
        case 2:
            return "2 agenda's met deze naam: beide tellen mee"
        default:
            return "\(matched.count) agenda's met deze naam: alle tellen mee"
        }
    }

    /// Wat de laatste ronde heeft overgeslagen: "2 afgewezen, 1 hele dag, 1 langer dan 16 uur". nil als er niets is overgeslagen.
    static func skippedText(_ fetch: CalendarFetch) -> String? {
        var parts: [String] = []
        if fetch.skippedDeclined > 0 { parts.append("\(fetch.skippedDeclined) afgewezen") }
        if fetch.skippedCanceled > 0 { parts.append("\(fetch.skippedCanceled) geannuleerd") }
        if fetch.skippedAllDay > 0 { parts.append("\(fetch.skippedAllDay) hele dag") }
        if fetch.skippedTooLong > 0 { parts.append("\(fetch.skippedTooLong) langer dan \(WorkCalendarRules.maxShiftHours) uur") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "312 diensten", "1 dienst" of "geen diensten".
    static func shiftCountText(_ count: Int) -> String {
        switch count {
        case 0: return "geen diensten"
        case 1: return "1 dienst"
        default: return "\(count) diensten"
        }
    }

    /// "Laatst bijgewerkt: vandaag 14:02, 312 diensten". `refreshedAt` is het moment van de verversing als dat bekend is (de snapshot
    /// bewaart alleen de dag); `today` is "nu". Zonder snapshot: "Nog niet bijgewerkt".
    static func lastRefreshText(_ snapshot: WorkSnapshot?, refreshedAt: Date? = nil, today: Date = Date(),
                                calendar: Calendar = YearMonth.calendar) -> String {
        guard let snapshot else { return "Nog niet bijgewerkt" }
        let todayDay = CalendarDay(date: today, calendar: calendar)
        let diff = todayDay.dayNumber - snapshot.fetchedDay.dayNumber
        var when: String
        switch diff {
        case 0: when = "vandaag"
        case 1: when = "gisteren"
        default: when = snapshot.fetchedDay.year == todayDay.year ? Fmt.longDayMonth(snapshot.fetchedDay) : Fmt.longDate(snapshot.fetchedDay)
        }
        if let refreshedAt, CalendarDay(date: refreshedAt, calendar: calendar) == snapshot.fetchedDay {
            let c = calendar.dateComponents([.hour, .minute], from: refreshedAt)
            let hour = c.hour ?? 0, minute = c.minute ?? 0
            when += " \(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
        }
        return "Laatst bijgewerkt: \(when), \(shiftCountText(snapshot.shifts.count))"
    }

    /// De ondertitel van de rij Werkuren in Instellingen: waar de uren van je salaris vandaan komen.
    static func settingsSummary(_ data: FinanceData) -> String {
        if data.usesCalendarHours { return "Uit je agenda \u{201C}\(data.work.calendarTitle)\u{201D}" }
        if data.salary.mode == .hourly { return "Uren per week invullen" }
        return "Alleen bij een uurloon"
    }

    /// De eerstvolgende feestdagen vanaf `day` (de aangezette soorten en eigen dagen): "De eerstvolgende feestdagen: Eerste Kerstdag
    /// (25 december), Tweede Kerstdag (26 december) en Nieuwjaarsdag (1 januari)." nil als er geen enkele aanstaat.
    static func nextHolidaysText(_ settings: HolidaySettings, from day: CalendarDay, count: Int = 3) -> String? {
        let upcoming = (DutchHolidays.holidays(year: day.year, settings: settings) + DutchHolidays.holidays(year: day.year + 1, settings: settings))
            .filter { $0.day >= day }
            .prefix(max(count, 1))
            .map { "\($0.name) (\(Fmt.longDayMonth($0.day)))" }
        guard !upcoming.isEmpty else { return nil }
        let list = upcoming.count == 1 ? upcoming[0] : upcoming.dropLast().joined(separator: ", ") + " en " + upcoming[upcoming.count - 1]
        return "De eerstvolgende feestdagen: \(list)."
    }
}
