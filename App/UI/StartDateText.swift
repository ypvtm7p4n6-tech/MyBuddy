import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in StartDateTextTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - De teksten van de startdatum
//
// Alle teksten van de pagina Startdatum (`StartDatePage`) en van de plekken waar de startdatum zichtbaar wordt (Gegevens, Home, de
// maandpagina's, de lijsten met boekingen). Ze volgen de termenlijst (docs/design/plan.md par. 2.8): "ingevulde saldi", nooit
// "meetpunt". Het getal of de datum komt steeds uit de rekenmotor (`FinanceData`, `StartDate.swift`); hier staan alleen woorden.

/// Wat er vóór een gekozen startdatum ligt, voor "Wat verandert er?" op de pagina Startdatum. Alles blijft bewaard; het telt alleen
/// niet meer mee.
struct StartDateCounts: Equatable {
    /// Bankboekingen vóór de gekozen dag.
    var bankEntries = 0
    /// Potboekingen vóór de gekozen dag.
    var potEntries = 0
    /// Ingevulde banksaldi vóór de gekozen dag.
    var balances = 0
    /// Maanden die niet meer meetellen: van de huidige eerste dag tot de maand van de gekozen dag.
    var months = 0

    init() {}

    init(bankEntries: Int, potEntries: Int, balances: Int, months: Int) {
        self.bankEntries = bankEntries
        self.potEntries = potEntries
        self.balances = balances
        self.months = months
    }

    /// De aantallen voor `day` in `data`.
    init(_ data: FinanceData, before day: CalendarDay) {
        let hidden = data.entriesBefore(day)
        bankEntries = hidden.bank
        potEntries = hidden.pots
        balances = hidden.balances
        months = data.monthsDropped(by: day)
    }

    /// Valt er niets vóór de gekozen dag?
    var isEmpty: Bool { bankEntries + potEntries + balances + months == 0 }

    /// Het aantal boekingen en ingevulde saldi samen (zonder maanden).
    var entryTotal: Int { bankEntries + potEntries + balances }
}

/// Eén regel van "Wat verandert er?": wat en hoeveel.
struct StartDateCountLine: Equatable, Identifiable {
    let title: String
    let count: Int
    var id: String { title }
}

/// Wat een uitleg bij een maand vóór de start zegt dat je daar niet kunt doen.
enum StartDateAction: Equatable {
    /// "daar vul je niets in" (Inkomen, Uitgaven).
    case fillIn
    /// "daar verdeel je niets" (Verdelen).
    case distribute
}

enum StartDateText {
    // MARK: Pagina Startdatum

    static let pageTitle = "Startdatum"

    /// Uitleg onder de datumkiezer.
    static let explanation = "Alles begint op deze dag. Wat je daarvoor invulde telt niet mee, ook al blijft het bewaard."

    static let pickerTitle = "Begin op"

    static let keepChoice = "Alleen de startdatum instellen"
    static let eraseChoice = "Alles wissen en opnieuw beginnen vanaf deze datum"

    /// Wat de gekozen manier doet, onder de keuze.
    static func choiceFootnote(erases: Bool) -> String {
        if erases {
            return "Dit wist al je gegevens en begint met een lege start op de gekozen dag."
        }
        return "Je gegevens blijven bewaard. Wat vóór de startdatum valt telt niet meer mee; kies je later een eerdere datum, dan telt het weer mee."
    }

    /// De titel van de knop: instellen, of (rood, met bevestiging) wissen en opnieuw beginnen.
    static func actionTitle(erases: Bool) -> String {
        erases ? "Wissen en opnieuw beginnen" : "Startdatum instellen"
    }

    /// De huidige stand in een zin, bovenaan de pagina.
    static func summary(for data: FinanceData) -> String {
        if let start = data.effectiveStartDay {
            return "Je begint op \(Fmt.longDate(start)). Wat daarvoor valt telt niet mee."
        }
        return "Je hebt geen startdatum ingesteld. Alles telt vanaf \(Fmt.longDate(data.firstDay)), het begin van je startmaand."
    }

    /// Wat er onder "Startdatum" staat in de lijst van Gegevens.
    static func rowSubtitle(for data: FinanceData) -> String {
        if let start = data.effectiveStartDay { return Fmt.longDate(start) }
        return "Niet ingesteld"
    }

    // MARK: Wat verandert er?

    /// De regels van "Wat verandert er?", in vaste volgorde. Een regel zonder aantal staat er niet.
    static func countLines(_ counts: StartDateCounts) -> [StartDateCountLine] {
        var lines: [StartDateCountLine] = []
        if counts.bankEntries > 0 { lines.append(StartDateCountLine(title: "Boekingen op je bankrekening", count: counts.bankEntries)) }
        if counts.potEntries > 0 { lines.append(StartDateCountLine(title: "Boekingen in spaarpotten", count: counts.potEntries)) }
        if counts.balances > 0 { lines.append(StartDateCountLine(title: "Ingevulde saldi", count: counts.balances)) }
        if counts.months > 0 { lines.append(StartDateCountLine(title: "Maanden die niet meer meetellen", count: counts.months)) }
        return lines
    }

    /// De uitleg bij "Wat verandert er?": wat er met de aantallen gebeurt.
    static func warning(_ counts: StartDateCounts, day: CalendarDay) -> String {
        if counts.isEmpty {
            return "Er valt niets vóór \(Fmt.longDate(day)): er verandert niets aan wat meetelt."
        }
        return "Dit telt niet meer mee vanaf \(Fmt.longDate(day)), maar blijft bewaard. Kies je later een eerdere startdatum, dan telt het weer mee."
    }

    /// De uitleg bij de huidige startdatum als je dezelfde dag kiest.
    static let sameDayNote = "Dit is je huidige startdatum."

    // MARK: Wissen en opnieuw beginnen

    static func eraseTitle(day: CalendarDay) -> String {
        "Alles wissen en beginnen op \(Fmt.longDate(day))?"
    }

    /// De bevestiging bij "Alles wissen en opnieuw beginnen": met de cloud gaat het ook weg op je andere apparaten.
    static func eraseMessage(day: CalendarDay, cloud: Bool) -> String {
        let start = "je begint opnieuw op \(Fmt.longDate(day))"
        if cloud {
            return "Dit wist ook je gegevens in de cloud en op je andere apparaten, en \(start). Het kan niet ongedaan worden gemaakt."
        }
        return "Dit wist al je gegevens en \(start). Het kan niet ongedaan worden gemaakt."
    }

    static let eraseConfirm = "Wis alles en begin opnieuw"

    // MARK: Beginsaldo

    /// De kop van de sectie met het beginsaldo.
    static func openingTitle(day: CalendarDay) -> String {
        "Beginsaldo op \(Fmt.longDate(day))"
    }

    static let openingFootnote = "Het saldo op deze dag, met alles wat die dag al gebeurd is."

    static let openingSave = "Beginsaldo bewaren"

    static let bankRowTitle = "Bankrekening"

    static let openingSaved = "Beginsaldo bewaard."

    // MARK: Meldingen

    static func startSaved(day: CalendarDay) -> String {
        "Startdatum ingesteld op \(Fmt.longDate(day))."
    }

    static func restarted(day: CalendarDay) -> String {
        "Alles is gewist. Je begint opnieuw op \(Fmt.longDate(day))."
    }

    // MARK: Home

    /// "Je begint op 3 november." (met het jaar als het niet het jaar van `today` is). nil zonder startdatum.
    static func welcomeLine(for data: FinanceData, today: Date) -> String? {
        guard let start = data.effectiveStartDay else { return nil }
        let thisYear = CalendarDay(date: today).year
        let text = start.year == thisYear ? Fmt.longDayMonth(start) : Fmt.longDate(start)
        return "Je begint op \(text)."
    }

    // MARK: Maandpagina's

    /// Bij een maand vóór de start: "Maanden vóór je startdatum (3 november 2026) tellen niet mee: daar vul je niets in." Zonder
    /// startdatum is het de startmaand: "Maanden vóór je startmaand (november 2026) tellen niet mee: daar vul je niets in."
    static func beforeStartNote(_ data: FinanceData, _ action: StartDateAction) -> String {
        let what = action == .fillIn ? "vul je niets in" : "verdeel je niets"
        if let start = data.effectiveStartDay {
            return "Maanden vóór je startdatum (\(Fmt.longDate(start))) tellen niet mee: daar \(what)."
        }
        return "Maanden vóór je startmaand (\(Fmt.month(data.startMonth))) tellen niet mee: daar \(what)."
    }

    /// Bij een maand vóór de start, zonder werkwoord: "Voor je startdatum telt er geen salaris mee".
    static func beforeStartSalaryNote(_ data: FinanceData) -> String {
        data.effectiveStartDay == nil ? "Voor je startmaand telt er geen salaris mee" : "Voor je startdatum telt er geen salaris mee"
    }

    /// Wat een lijstrij van Bibliotheek zegt over de start: "Telt mee vanaf 3 november 2026" (of vanaf de startmaand).
    static func countsFromNote(_ data: FinanceData) -> String {
        if let start = data.effectiveStartDay { return "Telt mee vanaf \(Fmt.longDate(start))" }
        return "Telt mee vanaf je startmaand (\(Fmt.month(data.startMonth)))"
    }

    /// In de startmaand zelf, als de startdatum niet de eerste is: wat er van de maand meetelt. nil in elke andere maand.
    static func partialMonthNote(_ data: FinanceData, month: YearMonth) -> String? {
        guard let start = data.effectiveStartDay, start.day > 1, start.yearMonth == month else { return nil }
        return "Je begint op \(Fmt.longDayMonth(start)). In deze maand telt alleen mee wat op of na die dag valt; wat daarvoor valt zit al in je beginsaldo."
    }

    /// Bij een regel van de startmaand die vóór de startdag valt.
    static let lineBeforeStart = "Telt niet mee (vóór je startdatum)"

    /// Bij een inleg waarvan de overschrijfdag vóór de startdatum valt: "Telt niet mee: de overschrijfdag (de 3e) valt vóór je startdatum."
    static func transferBeforeStart(day: Int) -> String {
        "Telt niet mee: de overschrijfdag (de \(day)e) valt vóór je startdatum."
    }

    /// Bij het salaris van de startmaand als de uitbetalingen vóór de startdatum vallen.
    static let payoutsBeforeStart = "De uitbetalingen van deze maand vallen vóór je startdatum en tellen niet mee."

    /// Bij een eigen salaris of eigen uren in de startmaand (niet de eerste): dat totaal is wat telt, verdeeld over de uitbetalingen
    /// vanaf de startdatum. nil in elke andere maand.
    static func overrideStartNote(_ data: FinanceData, month: YearMonth) -> String? {
        guard let start = data.effectiveStartDay, start.day > 1, start.yearMonth == month else { return nil }
        return "In je startmaand is dit het totaal dat meetelt, verdeeld over de uitbetalingen vanaf \(Fmt.longDayMonth(start))."
    }

    // MARK: Lijsten met boekingen

    /// Onderaan een lijst met boekingen: "2 boekingen van vóór je startdatum (3 november 2026) tellen niet mee." nil bij 0.
    static func hiddenEntriesNote(count: Int, startDay: CalendarDay) -> String? {
        guard count > 0 else { return nil }
        let date = Fmt.longDate(startDay)
        if count == 1 { return "1 boeking van vóór je startdatum (\(date)) telt niet mee." }
        return "\(count) boekingen van vóór je startdatum (\(date)) tellen niet mee."
    }

    /// De voetnoot onder de lijst met boekingen van de bankrekening (boekingen en ingevulde saldi).
    static func hiddenBankNote(_ data: FinanceData) -> String? {
        guard let start = data.effectiveStartDay else { return nil }
        return hiddenEntriesNote(count: data.hiddenBankCount, startDay: start)
    }

    /// De voetnoot onder de lijst met boekingen van een spaarpot, of van alle potten zonder pot.
    static func hiddenPotNote(_ data: FinanceData, potID: UUID?) -> String? {
        guard let start = data.effectiveStartDay else { return nil }
        return hiddenEntriesNote(count: data.hiddenPotCount(for: potID), startDay: start)
    }

    /// De voetnoot onder een lijst met de boekingen van alles samen, zoals Recent in de Bibliotheek: de bankrekening en alle
    /// spaarpotten bij elkaar.
    static func hiddenRecentNote(_ data: FinanceData) -> String? {
        guard let start = data.effectiveStartDay else { return nil }
        return hiddenEntriesNote(count: data.hiddenBankCount + data.hiddenPotCount(for: nil), startDay: start)
    }

    /// De waarschuwing in het blad voor een bankboeking of potboeking als de boeking van vóór de startdatum zou zijn: nu invullen
    /// terwijl de startdatum nog moet komen. nil als de boeking meetelt.
    static func entryBeforeStartWarning(_ data: FinanceData, at moment: Date) -> String? {
        guard let start = data.effectiveStartDay, let cutoff = data.startCutoff, moment < cutoff else { return nil }
        return "Je startdatum is \(Fmt.longDate(start)). Wat je nu invult valt daarvoor en telt niet mee."
    }

    // MARK: Datumkiezer

    /// Het bereik van de datumkiezer: van 1 januari 2000 tot een jaar na vandaag.
    static func pickerRange(today: Date) -> ClosedRange<Date> {
        let calendar = YearMonth.calendar
        let lower = CalendarDay(year: 2_000, month: 1, day: 1).date(calendar: calendar)
        let upper = calendar.date(byAdding: .year, value: 1, to: today) ?? today
        return lower...max(lower, upper)
    }
}
