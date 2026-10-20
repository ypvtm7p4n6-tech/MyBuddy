import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests; de tests staan in BlockOrderMigrationTests.swift.

/// Zet een opgeslagen blokvolgorde van de oude pagina's (`home`, `savings`, `tools`) om naar de nieuwe pagina's (`overview`,
/// `month`, `saving`, `planning`), met behoud van de onderlinge volgorde (par. 2.7 van docs/design/plan.md).
///
/// De functie leest alleen: ze draait bij het lezen van de volgorde (`AppSettings.orderedBlocks(for:)`) en schrijft niets
/// terug, tot de gebruiker zelf een volgorde kiest. Ze is idempotent: de uitkomst bevat geen oude sleutels meer, dus nog een keer
/// migreren verandert niets. Blokken die in de opgeslagen lijst ontbreken komen niet hier maar bij het lezen achteraan, in de
/// standaardvolgorde.
enum BlockOrderMigration {
    /// De sleutels van de oude pagina's.
    static let legacyKeys: [String] = ["home", "savings", "tools"]

    /// Waar een oud blok naartoe gaat: de nieuwe pagina en het nieuwe blok-id.
    private struct Target {
        let page: String
        let id: String
    }

    /// De volgorde waarin de oude pagina's worden gelezen. Pagina's die een blok delen (`home.overview` en `savings.period`
    /// worden beide `month.flow`) houden de plek van de eerste die wordt gelezen.
    private static let readingOrder: [String] = ["savings", "home", "tools"]

    /// Oude sleutel, oud blok-id, nieuw blok.
    private static let table: [String: [String: Target]] = [
        "home": [
            "overview": Target(page: "month", id: "flow"),
            "pots": Target(page: "overview", id: "pots"),
            "invest": Target(page: "overview", id: "invest")
        ],
        "savings": [
            "period": Target(page: "month", id: "flow"),
            "income": Target(page: "month", id: "income"),
            "bank": Target(page: "month", id: "bank"),
            "distribute": Target(page: "month", id: "distribute"),
            "pots": Target(page: "saving", id: "pots"),
            "portfolio": Target(page: "saving", id: "portfolio"),
            "buffer": Target(page: "planning", id: "buffer"),
            "goals": Target(page: "planning", id: "goals")
        ],
        "tools": [
            "accelerators": Target(page: "planning", id: "accelerators"),
            "projection": Target(page: "planning", id: "projection"),
            "purchase": Target(page: "planning", id: "purchase")
        ]
    ]

    /// Staat er in de opgeslagen volgorde nog een oude sleutel?
    static func hasLegacyKeys(_ stored: [String: [String]]) -> Bool {
        for key in legacyKeys where stored[key] != nil { return true }
        return false
    }

    /// De opgeslagen volgorde per pagina, in de nieuwe sleutels.
    /// - Een nieuwe sleutel (de gebruiker koos al een volgorde op de nieuwe pagina) blijft zoals hij is en wint van wat uit de
    ///   oude sleutels zou volgen.
    /// - Een oude sleutel gaat naar de nieuwe pagina's volgens par. 2.7; onbekende blok-id's worden genegeerd en dubbele
    ///   blok-id's tellen één keer.
    /// - Een lege invoer blijft leeg; een pagina zonder blokken krijgt geen sleutel.
    static func migrate(_ stored: [String: [String]]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (key, ids) in stored where !legacyKeys.contains(key) {
            result[key] = ids
        }

        var derived: [String: [String]] = [:]
        for oldKey in readingOrder {
            guard let ids = stored[oldKey], let targets = table[oldKey] else { continue }
            for oldID in ids {
                guard let target = targets[oldID] else { continue }
                var list = derived[target.page] ?? []
                if !list.contains(target.id) {
                    list.append(target.id)
                    derived[target.page] = list
                }
            }
        }
        for (page, ids) in derived where result[page] == nil && !ids.isEmpty {
            result[page] = ids
        }
        return result
    }
}
