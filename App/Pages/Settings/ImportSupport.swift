import Foundation
import Observation
// Foundation-only: geen SwiftUI, zodat de logica zonder scherm te testen is.

/// De maanden waaruit je bij het importeren kunt kiezen: vanaf je startmaand (hooguit 3 jaar terug) tot een jaar vooruit.
enum ImportMonths {
    static func options(start: YearMonth, current: YearMonth) -> [YearMonth] {
        let lowest = max(start, current.adding(-36))
        let first = min(lowest, current)
        return first.range(count: first.months(to: current.adding(12)) + 1)
    }
}

/// De ingelezen gegevens van een Excel- of CSV-bestand die wachten op controle in het importoverzicht
/// (`SettingsPage.importReview`). De pagina Gegevens vult de coordinator voordat hij het overzicht opent; het overzicht
/// leest hem en maakt hem weer leeg. Zo staat het overzicht als echte bestemming op het pad (geen blad in een blad).
@MainActor
@Observable
final class ImportCoordinator {
    static let shared = ImportCoordinator()

    /// Wat er uit het bestand is gehaald. `nil`: er is niets om te controleren.
    private(set) var draft: ImportDraft?
    private(set) var initialMonth: YearMonth = YearMonth.current()
    private(set) var monthOptions: [YearMonth] = []

    init() {}

    var hasDraft: Bool { draft != nil }

    func prepare(draft: ImportDraft, initialMonth: YearMonth, monthOptions: [YearMonth]) {
        self.draft = draft
        self.initialMonth = initialMonth
        self.monthOptions = monthOptions
    }

    func reset() {
        draft = nil
        monthOptions = []
    }
}
