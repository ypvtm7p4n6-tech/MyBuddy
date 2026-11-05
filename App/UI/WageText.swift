import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat dit
// bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in WageTextTests.swift en
// WageEditTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - De teksten van het loon per maand (docs/work/plan2.md D6)
//
// Alle teksten van de kaart "Loon per maand" op Salaris en van de pagina "Loon wijzigen" (`WageChangePage`). Ze volgen de termenlijst
// ("Loon per maand", "Loon wijzigen"). Het bedrag, de maand en het loon komen steeds uit de rekenmotor (`salarySettings(in:)`,
// `SalarySettings.payoutAmount()`); hier staan alleen woorden.

enum WageText {
    static let sectionTitle = "Loon per maand"
    static let pageTitle = "Loon wijzigen"
    static let addTitle = "Loon wijzigen vanaf een maand"

    /// Onder de lijst met wijzigingen: welk loon voor welke uitbetaling geldt.
    static let footer = "Een wijziging geldt voor het salaris dat vanaf die maand op je rekening komt, ook als je een deel van de uren in de maand ervoor werkte. Eerdere maanden blijven zoals ze waren."

    /// Op de kaart "Loon per maand" zolang er geen wijziging is.
    static let emptyHint = "Je loon is elke maand hetzelfde. Gaat je uurloon of salaris vanaf een bepaalde maand omhoog of omlaag, voeg dan een wijziging toe."

    /// Op de pagina "Loon wijzigen" als de gekozen maand al voorbij is.
    static let pastMonthWarning = "Deze maand is al voorbij: ook de maanden vanaf dan tot de volgende wijziging rekenen met dit loon, en maanden die al voorbij zijn veranderen mee. Wil je maar één maand aanpassen, vul dan bij Inkomen een eigen salaris voor die maand in."

    /// Onder de velden van de standaardkaart op Salaris zodra er wijzigingen zijn: de velden tonen het loon van deze maand.
    static let currentMonthNote = "Dit is het loon van deze maand. Wijzigingen per maand staan hieronder bij Loon per maand."

    /// Bij het loon van een maand waarin de uren uit de agenda komen: het bedrag van een uitbetaling volgt je agenda, niet het uurloon alleen.
    static let calendarNote = "Je uren komen uit je agenda: het nieuwe uurloon geldt voor de uren van de uitbetalingen vanaf die maand."

    /// De rij "Nu" in de lijst.
    static let nowBadge = "Nu"

    /// "Vanaf november 2026".
    static func fromTitle(_ month: YearMonth) -> String {
        "Vanaf \(Fmt.month(month))"
    }

    /// De waarde van een wijziging: "€ 15,20 per uur", "€ 3.200 per maand" of "€ 800 per uitbetaling", plus "32 uur per week". Een veld dat
    /// niet verandert staat er niet in. `isMonthly` bepaalt of een vast bedrag "per maand" of "per uitbetaling" heet.
    static func valueText(_ change: SalaryChange, mode: SalaryMode, isMonthly: Bool) -> String {
        var parts: [String] = []
        if mode == .hourly, let rate = change.hourlyRate { parts.append("\(Fmt.euroExact(rate)) per uur") }
        if mode == .fixed, let amount = change.fixedMonthly {
            parts.append("\(Fmt.euro(amount)) \(isMonthly ? "per maand" : "per uitbetaling")")
        }
        if let hours = change.hoursPerWeek { parts.append("\(Fmt.input(hours)) uur per week") }
        return parts.isEmpty ? "Geen verandering" : parts.joined(separator: " · ")
    }

    /// De rij in de lijst: "Vanaf november 2026: € 15,20 per uur".
    static func rowLine(_ change: SalaryChange, mode: SalaryMode, isMonthly: Bool) -> String {
        "\(fromTitle(change.from)): \(valueText(change, mode: mode, isMonthly: isMonthly))"
    }

    /// De rij voor het loon van het begin zodra er een wijziging is: "Tot november 2026: € 14,35 per uur · 32 uur per week".
    static func baseLine(settings: SalarySettings, until first: YearMonth) -> String {
        let base = SalaryChange(from: first, hourlyRate: settings.hourlyRate, fixedMonthly: settings.fixedMonthly,
                                hoursPerWeek: settings.hoursPerWeek > 0 ? settings.hoursPerWeek : nil)
        return "Tot \(Fmt.month(first)): \(valueText(base, mode: settings.mode, isMonthly: settings.isMonthly))"
    }

    /// Wat de wijziging doet met een uitbetaling: "Een uitbetaling gaat van € 1.990 naar € 2.108 per maand." nil als niets verandert.
    static func effectNote(old: Double, new: Double, isMonthly: Bool) -> String? {
        guard CentsMath.int(old) != CentsMath.int(new) else { return nil }
        return "Een uitbetaling gaat van \(Fmt.euro(old)) naar \(Fmt.euro(new))\(isMonthly ? " per maand" : "")."
    }

    /// De vraag bij verwijderen.
    static func deleteMessage(month: YearMonth) -> String {
        "Vanaf \(Fmt.month(month)) geldt weer het loon van daarvoor."
    }

    /// De label van een rij voor VoiceOver: de rij en of het de wijziging is die nu geldt.
    static func accessibilityLine(_ change: SalaryChange, mode: SalaryMode, isMonthly: Bool, isCurrent: Bool) -> String {
        let line = rowLine(change, mode: mode, isMonthly: isMonthly)
        return isCurrent ? "\(line), geldt nu" : line
    }
}

// MARK: - De logica van de pagina "Loon wijzigen"

/// De logica van de pagina "Loon wijzigen" zonder SwiftUI: waarmee het formulier begint, welke velden een wijziging bewaart en wat een
/// uitbetaling ervan verandert. Alle bedragen komen uit de rekenmotor (`salarySettings(in:)`, `payoutAmount()`).
enum WageEdit {
    /// De waarden waar het formulier voor `month` mee begint: het loon dat in die maand geldt.
    static func start(_ data: FinanceData, month: YearMonth) -> SalarySettings {
        data.salarySettings(in: month)
    }

    /// De wijziging voor `month` uit de ingevulde waarden. Een veld dat gelijk is aan het loon van de maand ervoor (bedragen op
    /// centen, uren op 0,001) blijft nil: het volgt dat loon. Een lege wijziging (`SalaryChange.isEmpty`) is er een die niets verandert.
    static func change(_ data: FinanceData, month: YearMonth, hourlyRate: Double, fixedMonthly: Double, hoursPerWeek: Double) -> SalaryChange {
        let before = data.salarySettings(in: month.adding(-1))
        var change = SalaryChange(from: month)
        if CentsMath.int(hourlyRate) != CentsMath.int(before.hourlyRate) { change.hourlyRate = hourlyRate }
        if CentsMath.int(fixedMonthly) != CentsMath.int(before.fixedMonthly) { change.fixedMonthly = fixedMonthly }
        if abs(hoursPerWeek - before.hoursPerWeek) > 0.0005 { change.hoursPerWeek = hoursPerWeek }
        return change
    }

    /// Het bedrag van één uitbetaling in `month` zonder en met de wijziging (`SalarySettings.payoutAmount()` van het loon van de maand
    /// ervoor en van dat loon met de wijziging erover).
    static func payoutPreview(_ data: FinanceData, month: YearMonth, change: SalaryChange) -> (old: Double, new: Double) {
        let before = data.salarySettings(in: month.adding(-1))
        var after = before
        if let value = change.hourlyRate { after.hourlyRate = value }
        if let value = change.fixedMonthly { after.fixedMonthly = value }
        if let value = change.hoursPerWeek { after.hoursPerWeek = value }
        return (before.payoutAmount(), after.payoutAmount())
    }

    /// De maanden die de kiezer op de pagina aanbiedt: van de lopende maand tot 24 maanden vooruit, plus de maand van een bestaande
    /// wijziging als die daarbuiten valt (zodat je haar kunt bewerken of verwijderen).
    static func monthChoices(_ data: FinanceData, current: YearMonth, including month: YearMonth? = nil) -> [YearMonth] {
        var months = current.range(count: 25)
        for extra in (data.salaryChanges.map { $0.from } + (month.map { [$0] } ?? [])) where !months.contains(extra) {
            months.append(extra)
        }
        return months.sorted()
    }
}
