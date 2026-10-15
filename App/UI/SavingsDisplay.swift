import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in SavingsDisplayTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Het salarisschema: teksten en wijzigingen

/// Korte teksten voor het salarisschema. Alleen tekst: alle bedragen en data komen uit de rekenmotor.
enum SalaryScheduleText {
    /// "Elke 4 weken, volgende op 23 oktober": de eerste letter een hoofdletter.
    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    /// Het aantal weken van een cyclus zoals het in een rekensom staat: "4 weken", "1 week", "10 ÷ 7 weken" (bij dagen).
    static func weeksText(schedule: SalarySchedule, interval: Int) -> String {
        switch schedule {
        case .monthly: return "52 ÷ 12 weken"
        case .weeks: return interval == 1 ? "1 week" : "\(interval) weken"
        case .days: return "\(interval) ÷ 7 weken"
        }
    }

    /// "1 uitbetaling", "2 uitbetalingen".
    static func payoutCount(_ count: Int) -> String {
        count == 1 ? "1 uitbetaling" : "\(count) uitbetalingen"
    }

    /// De eenheid achter het interval: "week" of "weken", "dag" of "dagen".
    static func unit(schedule: SalarySchedule, interval: Int) -> String {
        switch schedule {
        case .monthly: return ""
        case .weeks: return interval == 1 ? "week" : "weken"
        case .days: return interval == 1 ? "dag" : "dagen"
        }
    }

    /// Het schema dat bij het omschakelen als beginwaarde hoort: elke 4 weken of elke 14 dagen (gangbaar voor een
    /// salaris om de zoveel weken of dagen).
    static func startInterval(for schedule: SalarySchedule) -> Int {
        switch schedule {
        case .monthly: return 1
        case .weeks: return 4
        case .days: return 14
        }
    }
}

/// Wijzigingen aan het salarisschema, los van het scherm. De rekenmotor doet het rekenwerk.
enum SalaryScheduleEdit {
    /// Schakelt het schema om. Een schema om de zoveel weken of dagen heeft een bekende uitbetaaldatum nodig: dat is de
    /// volgende uitbetaling van het huidige schema (je weet meestal wanneer je het eerstvolgende salaris krijgt). Is er al
    /// een datum ingesteld, dan blijft die. Het interval begint op een gangbare waarde (zie `startInterval`).
    static func change(_ data: inout FinanceData, to schedule: SalarySchedule, today: Date) {
        guard data.salary.schedule != schedule else { return }
        var anchor: CalendarDay?
        if schedule != .monthly, data.salary.anchor == nil {
            let next = data.nextPayDate(after: today) ?? today
            anchor = CalendarDay(date: next)
        }
        // Eerst het verleden vastleggen: het nieuwe schema geldt vanaf de lopende maand (zie `edit`).
        data.freezeSalaryHistory(before: YearMonth(date: today))
        data.salary.setSchedule(schedule, interval: SalaryScheduleText.startInterval(for: schedule), anchor: anchor)
    }

    /// Wijzigt de salarisinstellingen (bedrag, uurloon, uren, interval, ankerdatum, salarisdag, soort) zo dat alleen de
    /// lopende en de komende maanden veranderen: de maanden ervoor houden hun salaris (`freezeSalaryHistory`). Doet niets
    /// als de wijziging niets verandert (dan wordt er ook niets vastgelegd).
    static func edit(_ data: inout FinanceData, today: Date, _ change: (inout SalarySettings) -> Void) {
        var changed = data.salary
        change(&changed)
        guard changed != data.salary else { return }
        data.freezeSalaryHistory(before: YearMonth(date: today))
        data.salary = changed
    }
}

// MARK: - Terugkerende regels: teksten en opslaan

/// De korte aantekening onder een terugkerende regel in de lijst.
struct RecurringRowNote: Equatable {
    var text: String
    /// Valt op (oranje): de regel wijkt af van de reeks.
    var isWarning: Bool
}

/// Teksten rond terugkerende regels. Alleen tekst: wat er over de reeks bekend is komt uit de rekenmotor (`SeriesInfo`).
enum RecurringText {
    static let skipTitle = "Alleen deze maand overslaan"
    static let stopTitle = "Stoppen vanaf deze maand"
    static let deleteTitle = "Terugkerende regel verwijderen?"

    /// "de 25e" bij een eigen dag; zonder eigen dag de standaard (bijvoorbeeld "je salarisdag, de 25e").
    static func dayPhrase(day: Int?, defaultPhrase: String) -> String {
        guard let day else { return defaultPhrase }
        return DayText.ordinal(YearMonth.clampedDay(day))
    }

    /// Een dag vanaf de 29e bestaat niet in elke maand: dan geldt de laatste dag van die maand.
    static func shortMonthNote(day: Int) -> String {
        day >= 29 ? " Is een maand korter, dan geldt de laatste dag van die maand." : ""
    }

    /// Onder de schakelaar "Terugkerend" bij een regel die nog niet terugkeert: wat het betekent.
    /// `resumes`: er is al een terugkerende regel met deze naam die in de maand ontbreekt (die loopt dan door).
    static func newRecurring(dayPhrase: String, day: Int, month: YearMonth, resumes: Bool) -> String {
        var text = "Komt elke maand terug op \(dayPhrase), vanaf \(Fmt.month(month)). Je ziet de regel vanzelf in de maanden erna, ook in maanden die je al hebt ingevuld."
        text += shortMonthNote(day: day)
        if resumes {
            text += " Er is al een terugkerende regel met deze naam die in \(Fmt.month(month)) ontbreekt: die loopt dan weer door, er komt geen tweede naast."
        }
        return text
    }

    /// Onder de schakelaar bij een regel die al terugkeert, met wat de reeks weet: sinds wanneer, tot wanneer.
    static func existingRecurring(dayPhrase: String, day: Int, info: SeriesInfo?, month: YearMonth) -> String {
        var text = "Komt elke maand terug op \(dayPhrase)."
        text += shortMonthNote(day: day)
        if let info {
            if info.isException {
                text += " In \(Fmt.month(month)) wijkt deze regel af van de reeks; de maanden erna volgen de reeks."
            } else if let last = info.lastMonth {
                text += " Loopt tot en met \(Fmt.month(last))."
            } else if info.firstMonth == month {
                text += " Begint in \(Fmt.month(month)) en gaat door tot je hem stopt."
            } else {
                text += " Loopt sinds \(Fmt.month(info.firstMonth)) en gaat door tot je hem stopt."
            }
        }
        text += " Bij Bewaar kies je of een wijziging alleen voor deze maand geldt of ook voor de maanden erna."
        return text
    }

    /// Onder de schakelaar als de regel niet terugkeert (of niet meer wordt).
    static func oneOff(month: YearMonth, wasRecurring: Bool) -> String {
        if wasRecurring {
            return "Zet je Terugkerend uit, dan kies je bij Bewaar of de regel alleen in \(Fmt.month(month)) eenmalig wordt of vanaf deze maand niet meer terugkomt."
        }
        return "Zonder Terugkerend telt deze regel alleen in \(Fmt.month(month))."
    }

    /// Titel en uitleg van de vraag bij Bewaar van een terugkerende regel die terugkerend blijft.
    static let scopeTitle = "Voor welke maanden geldt dit?"

    static func scopeMessage(name: String, month: YearMonth, current: YearMonth) -> String {
        "\(quoted(name)) komt elke maand terug. Je wijziging geldt alleen voor \(Fmt.month(month)), of ook voor alle maanden erna. Eerdere maanden blijven zoals ze zijn." + pastNote(month: month, current: current)
    }

    /// Ligt de maand al achter ons, dan veranderen bij "alle maanden erna" ook de maanden tussen die maand en nu mee, en
    /// dus ook de saldo's van toen. Dat zegt de vraag erbij.
    static func pastNote(month: YearMonth, current: YearMonth) -> String {
        month < current
            ? " Let op: \(Fmt.month(month)) is al voorbij, dus ook de maanden daarna die al voorbij zijn veranderen mee."
            : ""
    }

    /// Titel en uitleg van de vraag bij Bewaar als je Terugkerend uitzet.
    static let stopRecurringTitle = "Niet meer terugkerend"

    static func stopRecurringMessage(name: String, month: YearMonth, current: YearMonth) -> String {
        "Alleen deze maand: \(quoted(name)) staat in \(Fmt.month(month)) nog als eenmalige regel en komt in de maand erna gewoon terug. Stoppen: de regel komt vanaf \(Fmt.month(month)) niet meer terug, ook niet in maanden die je al hebt ingevuld." + pastNote(month: month, current: current)
    }

    /// Uitleg bij het verwijderen van een terugkerende regel.
    static func deleteMessage(name: String, month: YearMonth, current: YearMonth) -> String {
        "\(quoted(name)) komt elke maand terug. Overslaan haalt de regel alleen uit \(Fmt.month(month)): in de maand erna komt hij gewoon terug. Stoppen haalt hem uit \(Fmt.month(month)) en alle maanden erna; eerdere maanden blijven zoals ze zijn." + pastNote(month: month, current: current)
    }

    private static func quoted(_ name: String) -> String {
        name.isEmpty ? "Deze regel" : "\"\(name)\""
    }

    /// De aantekening onder een terugkerende regel in de lijst van `month`. nil als er niets te melden is.
    /// - een afwijkende maand wijkt af van de reeks (oranje);
    /// - een gestopte reeks zegt tot wanneer hij loopt;
    /// - in een maand die nog komt staat de regel er vanzelf (komt uit de reeks, hoeft niet te worden ingevuld).
    static func rowNote(info: SeriesInfo?, month: YearMonth, current: YearMonth) -> RecurringRowNote? {
        guard let info else { return nil }
        if info.isException {
            return RecurringRowNote(text: "Alleen deze maand anders. De maanden erna volgen de reeks.", isWarning: true)
        }
        if let last = info.lastMonth {
            let text = last == month ? "Laatste keer: daarna stopt deze regel" : "Loopt tot en met \(Fmt.month(last))"
            return RecurringRowNote(text: text, isWarning: false)
        }
        if month > current && info.firstMonth < month {
            return RecurringRowNote(text: "Staat er vanzelf: komt elke maand terug", isWarning: false)
        }
        return nil
    }
}

/// Wat "Bewaar" met een regel doet, los van het scherm.
enum LineSave {
    /// Moet er eerst gevraagd worden voor welke maanden een wijziging geldt? Alleen bij een regel die al terugkeert en die
    /// echt is gewijzigd.
    static func needsScopeQuestion(existing: MoneyLine?, edited: MoneyLine) -> Bool {
        guard let existing, existing.isRecurring else { return false }
        return existing != edited
    }

    /// Slaat de regel op in `month`. De motor doet het werk (`updateLine`, `addOrResumeRecurringLine`): `scope` zegt bij een
    /// terugkerende regel of alleen deze maand verandert of ook alle maanden erna.
    ///
    /// Een nieuwe terugkerende regel loopt door in een reeks met dezelfde naam die in deze maand ontbreekt (overgeslagen, of
    /// pas later begonnen), zodat er vanaf de maand erna geen tweede reeks naast komt. Typte je andere waarden dan die reeks
    /// heeft, dan krijgt de reeks vanaf deze maand die waarden.
    static func apply(_ data: inout FinanceData, edited: MoneyLine, isNew: Bool, kind: FinanceData.LineKind,
                      month: YearMonth, scope: SeriesScope) {
        guard isNew, edited.isRecurring else {
            data.updateLine(edited, kind: kind, in: month, scope: scope)
            return
        }
        let saved = data.addOrResumeRecurringLine(edited, kind: kind, in: month)
        var typed = edited
        typed.id = saved.id
        typed.seriesID = saved.seriesID
        if !saved.sameBaseline(as: typed) {
            data.updateLine(typed, kind: kind, in: month, scope: .thisAndFollowing)
        }
    }
}

// MARK: - De verdeling van een maand: wijzigen

/// Wijzigingen aan de verdeling van één spaarpot of belegging in één maand, los van het scherm. Alle bedragen en regels
/// komen uit de rekenmotor (`FinanceData`); hier wordt niets zelf uitgerekend.
///
/// De verdeling van een maand is een vast bedrag of een percentage van het inkomen van díe maand (de motor rekent het bij
/// het lezen uit). Een wijziging hier geldt alleen voor die maand (een overschrijving, bij een percentage "variabel");
/// `makeStandard` zet hem als standaard voor elke maand.
enum AllocationEdit {
    /// Het percentage waarmee een maand begint als je van "Bedrag" naar "Percentage" schakelt: de standaard van de pot of
    /// belegging als die een percentage is (en niet 0), anders het percentage van het salaris dat het huidige bedrag is.
    /// Zo springt het bedrag niet (op de afronding na). Zonder inkomen begint het op 0%.
    static func startingPercent(_ data: FinanceData, id: UUID, month: YearMonth) -> PercentRule {
        if case .percent(let standard)? = data.defaultAllocationRule(id, in: month), standard.percent > 0 {
            return standard
        }
        let amount = data.allocation(id, in: month)
        let percent = data.percent(forAmount: amount, of: .salary, in: month) ?? 0
        return PercentRule(percent: percent, basis: .salary)
    }

    /// Schakelt de inlegwijze van een maand om. Naar een vast bedrag: het bedrag van nu blijft staan. Naar een
    /// percentage: zie `startingPercent`. Staat de maand al zo, dan gebeurt er niets.
    static func setMode(_ data: inout FinanceData, id: UUID, month: YearMonth, to mode: ContributionMode) {
        let current = data.allocationRule(id, in: month)
        switch mode {
        case .fixed:
            guard current.isPercent else { return }
            data.setAllocation(id, in: month, amount: data.allocation(id, in: month))
        case .percentage:
            guard !current.isPercent else { return }
            let start = startingPercent(data, id: id, month: month)
            data.setAllocationPercent(id, in: month, percent: start.percent, basis: start.basis)
        }
    }

    static func setAmount(_ data: inout FinanceData, id: UUID, month: YearMonth, amount: Double) {
        data.setAllocation(id, in: month, amount: amount)
    }

    /// Een ander percentage voor deze maand; de grondslag van de maand blijft.
    static func setPercent(_ data: inout FinanceData, id: UUID, month: YearMonth, percent: Double) {
        var basis: IncomeBasis?
        if case .percent(let rule) = data.allocationRule(id, in: month) { basis = rule.basis }
        data.setAllocationPercent(id, in: month, percent: percent, basis: basis)
    }

    /// Een andere grondslag (alleen salaris of alle inkomsten) voor het percentage van deze maand.
    static func setBasis(_ data: inout FinanceData, id: UUID, month: YearMonth, to basis: IncomeBasis) {
        guard case .percent(let rule) = data.allocationRule(id, in: month) else { return }
        data.setAllocationPercent(id, in: month, percent: rule.percent, basis: basis)
    }

    /// Haalt de afwijking van deze maand weg: de standaard van de pot of belegging geldt weer.
    static func resetToStandard(_ data: inout FinanceData, id: UUID, month: YearMonth) {
        data.clearAllocationOverride(id, in: month)
    }

    /// Maakt de regel van deze maand (bedrag of percentage) de standaard voor elke maand. De lopende maand krijgt hem
    /// meteen (de motor doet dat zelf); een maand die nog komt volgt daarna de standaard in plaats van zijn eigen
    /// afwijking. Een maand in het verleden blijft zoals hij was.
    static func makeStandard(_ data: inout FinanceData, id: UUID, month: YearMonth, current: YearMonth) {
        switch data.allocationRule(id, in: month) {
        case .amount(let value):
            data.setContributionAmount(id, amount: value, current: current)
        case .percent(let rule):
            data.setContributionPercent(id, percent: rule.percent, basis: rule.basis, current: current)
        }
        if month > current { data.clearAllocationOverride(id, in: month) }
    }
}
