import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests; de tests staan in BlockOrderMigrationTests.swift. Het bevat de migratie van de
// opgeslagen volgorde, het uitrekenen van de volgorde (`order`) en de pagina's met hun blokken (`BlockPage`, `BlockInfo`).

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

    /// De blok-id's van een pagina in de volgorde van de gebruiker, uit de opgeslagen lijst en de standaardvolgorde.
    /// Onbekende id's (niet in `defaults`) en dubbele id's worden overgeslagen; blokken die nog niet in de opgeslagen lijst
    /// staan (nieuwe blokken) komen achteraan, in de standaardvolgorde. Zonder opgeslagen lijst is het de standaardvolgorde.
    static func order(stored: [String]?, defaults: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for id in stored ?? [] {
            guard !seen.contains(id), defaults.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
        }
        for id in defaults where !seen.contains(id) {
            result.append(id)
        }
        return result
    }
}

// MARK: - Welke blokken een pagina heeft

/// Eén blok van een pagina, met de naam en het icoon dat in het ordenen-blad staat.
struct BlockInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

/// De pagina's waarvan je de volgorde van de blokken zelf kunt kiezen. De blok-id's staan ook in `docs/v3-spec.md`.
/// De kern van een pagina (de hero op het Overzicht, de `MonthBar` op Maand) is geen blok en staat vast bovenaan.
enum BlockPage: String, CaseIterable, Identifiable {
    case overview, month, saving, planning
    // Overgangsvorm tot pakket G: de blokken van de drie oude tabroots.
    case home, savings, tools

    /// Alleen de vier pagina's van nu; de overgangsvormen doen niet mee in een lijst van alle pagina's.
    static var allCases: [BlockPage] { [.overview, .month, .saving, .planning] }

    var id: String { rawValue }

    /// Sleutel in `AppSettings.blockOrder`.
    var key: String { rawValue }

    /// Is dit een van de oude pagina's (tot pakket G)?
    var isLegacy: Bool {
        switch self {
        case .home, .savings, .tools: return true
        case .overview, .month, .saving, .planning: return false
        }
    }

    var title: String {
        switch self {
        case .overview, .home: return "Overzicht"
        case .month, .savings: return "Maand"
        case .saving: return "Sparen"
        case .planning, .tools: return "Plannen"
        }
    }

    /// Alleen een pagina met drie of meer blokken toont "Volgorde aanpassen": ordenen van twee blokken is zinloos.
    var allowsOrdering: Bool { blocks.count >= 3 }

    /// De blokken in de standaardvolgorde.
    var blocks: [BlockInfo] {
        switch self {
        case .overview:
            return [
                BlockInfo(id: "wealth", title: "Vermogen", symbol: "chart.pie"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full"),
                BlockInfo(id: "invest", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis"),
                BlockInfo(id: "upcoming", title: "Komende dagen", symbol: "calendar.badge.clock")
            ]
        case .month:
            return [
                BlockInfo(id: "flow", title: "Waar gaat je geld heen", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "income", title: "Inkomen", symbol: "eurosign.circle"),
                BlockInfo(id: "expenses", title: "Uitgaven", symbol: "creditcard"),
                BlockInfo(id: "distribute", title: "Verdelen", symbol: "square.split.2x2"),
                BlockInfo(id: "bank", title: "Bankrekening", symbol: "building.columns"),
                BlockInfo(id: "days", title: "Dag voor dag", symbol: "list.bullet.rectangle")
            ]
        case .saving:
            return [
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full"),
                BlockInfo(id: "portfolio", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis")
            ]
        case .planning:
            return [
                BlockInfo(id: "goals", title: "Doelen", symbol: "flag.checkered"),
                BlockInfo(id: "buffer", title: "Noodbuffer", symbol: "shield.lefthalf.filled"),
                BlockInfo(id: "accelerators", title: "Versnellers", symbol: "bolt"),
                BlockInfo(id: "projection", title: "Toekomstschatting", symbol: "calendar.badge.clock"),
                BlockInfo(id: "purchase", title: "Aankoopcheck", symbol: "cart")
            ]
        case .home:
            return [
                BlockInfo(id: "overview", title: "Overzicht", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full.fill"),
                BlockInfo(id: "invest", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis")
            ]
        case .savings:
            return [
                BlockInfo(id: "period", title: "Overzicht", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "income", title: "Inkomen", symbol: "eurosign.circle.fill"),
                BlockInfo(id: "bank", title: "Bankrekening", symbol: "building.columns.fill"),
                BlockInfo(id: "distribute", title: "Verdelen", symbol: "square.split.2x2.fill"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full.fill"),
                BlockInfo(id: "buffer", title: "Noodbuffer", symbol: "shield.lefthalf.filled"),
                BlockInfo(id: "portfolio", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis"),
                BlockInfo(id: "goals", title: "Doelen", symbol: "flag.checkered")
            ]
        case .tools:
            return [
                BlockInfo(id: "accelerators", title: "Versnellers", symbol: "bolt.fill"),
                BlockInfo(id: "projection", title: "Toekomstschatting", symbol: "calendar.badge.clock"),
                BlockInfo(id: "purchase", title: "Aankoopcheck", symbol: "cart")
            ]
        }
    }
}
