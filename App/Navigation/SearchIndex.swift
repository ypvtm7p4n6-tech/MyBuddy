import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de gegevens via `@testable import`; de tests staan in SearchIndexTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Zoeken in MyBuddy

/// De groepen waarin de resultaten van Zoeken staan (alleen groepen met een resultaat worden getoond).
enum SearchGroup: Int, CaseIterable, Identifiable {
    case pages, pots, holdings, goals, lines, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .pages: return "Pagina's"
        case .pots: return "Spaarpotten"
        case .holdings: return "Beleggingen"
        case .goals: return "Doelen"
        case .lines: return "Inkomen en uitgaven"
        case .settings: return "Instellingen"
        }
    }
}

/// Eén zoekresultaat: een pagina, een spaarpot, een belegging, een doel of een regel van inkomen of uitgaven.
struct SearchEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    /// Andere namen waarop je dit vindt (de zoekopdracht mag er een deel van zijn).
    let terms: [String]
    /// Waar een tik op het resultaat heen gaat (`router.go(_:)`).
    let destination: Destination
    /// De tint van de tegel bij dit resultaat: die van de pagina, de pot, de beleggingssoort of het doel.
    var hue: TileHue = .olive

    /// De groep waar dit resultaat in staat. Een regel van inkomen of uitgaven heeft de bestemming van de pagina maar een
    /// eigen id ("income-…", "expense-…").
    var group: SearchGroup {
        switch destination {
        case .pot:
            return .pots
        case .holding:
            return .holdings
        case .goal:
            return .goals
        case .settingsRoot, .settings:
            return .settings
        case .income, .expenses:
            if id.hasPrefix("income-") || id.hasPrefix("expense-") { return .lines }
            return .pages
        case .home, .library, .flow, .salary, .distribute, .bank, .cashflow, .pots, .portfolio,
             .goals, .savingsGoal, .accelerators, .buffer, .projection, .purchase, .tools:
            return .pages
        }
    }
}

/// De zoekfunctie van de app (par. 2.9). De pagina's komen uit `PageCatalog` en Instellingen; daarnaast zoekt `results(for:in:)` in de namen
/// van je spaarpotten, beleggingen, doelen en de regels van inkomen en uitgaven. Zo vind je een onderdeel ook als je de naam
/// niet meer weet.
enum SearchIndex {
    /// Het grootste aantal resultaten dat een zoekopdracht teruggeeft.
    static let maxResults = 50

    // MARK: Pagina's

    /// Een regel voor elke pagina van `PageCatalog` en voor elke pagina van Instellingen.
    static let pages: [SearchEntry] = catalogEntries() + settingsEntries()

    /// De pagina's uit de catalogus, in de volgorde van de catalogus.
    private static func catalogEntries() -> [SearchEntry] {
        var entries: [SearchEntry] = []
        for info in PageCatalog.all {
            entries.append(SearchEntry(id: info.id, title: info.title, symbol: info.symbol, terms: info.terms,
                                       destination: info.destination, hue: info.hue))
        }
        return entries
    }

    /// De tien pagina's van Instellingen (alleen met zoektermen die bij de pagina horen).
    private static func settingsEntries() -> [SearchEntry] {
        [
            settingsPage(.account, ["inloggen", "uitloggen", "synchronisatie", "cloud", "e-mail", "profiel"]),
            settingsPage(.password, ["wachtwoord", "beveiliging", "inloggen"]),
            settingsPage(.deleteAccount, ["verwijderen", "account", "wissen"]),
            settingsPage(.conflictBackups, ["back-up", "terugzetten", "conflict", "versie"]),
            settingsPage(.calculations, ["inflatie", "spaarrente", "rente", "opnamepercentage", "actuele cijfers"]),
            settingsPage(.prices, ["koers", "vernieuwen", "automatisch ophalen", "ticker", "geavanceerd"]),
            settingsPage(.data, ["back-up", "exporteren", "importeren", "excel", "csv", "voorbeelddata", "alles wissen"]),
            settingsPage(.layout, ["volgorde", "blokken", "volgorde aanpassen", "verplaatsen"]),
            settingsPage(.about, ["versie", "privacy", "bronnen", "disclaimer", "over"]),
            settingsPage(.importReview, ["importeren", "excel", "csv", "controleren"])
        ]
    }

    /// Een pagina van Instellingen: titel en symbool van de pagina zelf.
    private static func settingsPage(_ page: SettingsPage, _ terms: [String]) -> SearchEntry {
        SearchEntry(id: "settings-" + page.rawValue, title: page.title, symbol: page.symbol, terms: terms,
                    destination: .settings(page), hue: .sage)
    }

    // MARK: Zoeken

    /// De resultaten voor een zoekopdracht, het meest relevante eerst: eerst de titels die ermee beginnen, dan titels die
    /// het bevatten, dan andere namen die ermee beginnen en daarna de rest. Hoofdletters en accenten tellen niet mee.
    /// Een lege zoekopdracht geeft geen resultaten.
    static func results(for query: String, in data: FinanceData) -> [SearchEntry] {
        let tokens = fold(query).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if tokens.isEmpty { return [] }
        let whole = tokens.joined(separator: " ")

        let candidates = pages + dataEntries(in: data)
        var ranked: [RankedEntry] = []
        var index = 0
        for entry in candidates {
            if let score = relevance(of: entry, tokens: tokens, whole: whole) {
                ranked.append(RankedEntry(rank: score, index: index, entry: entry))
            }
            index += 1
        }
        ranked.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.index < rhs.index
        }
        return Array(ranked.prefix(maxResults)).map { $0.entry }
    }

    /// De resultaten per groep, in de volgorde van `SearchGroup` en binnen een groep op relevantie. Alleen groepen met
    /// een resultaat staan erin; een lege zoekopdracht geeft niets.
    static func grouped(for query: String, in data: FinanceData) -> [(group: SearchGroup, entries: [SearchEntry])] {
        let found = results(for: query, in: data)
        var groups: [(group: SearchGroup, entries: [SearchEntry])] = []
        for group in SearchGroup.allCases {
            let entries = found.filter { $0.group == group }
            if !entries.isEmpty {
                groups.append((group: group, entries: entries))
            }
        }
        return groups
    }

    private struct RankedEntry {
        let rank: Int
        let index: Int
        let entry: SearchEntry
    }

    /// Hoofdletters en accenten weg, en de randen opgeschoond.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// nil: het resultaat past niet; anders 0 (beste) tot 3.
    private static func relevance(of entry: SearchEntry, tokens: [String], whole: String) -> Int? {
        let title = fold(entry.title)
        var terms: [String] = []
        for term in entry.terms { terms.append(fold(term)) }
        let haystack = ([title] + terms).joined(separator: " ")
        for token in tokens {
            if !haystack.contains(token) { return nil }
        }
        if title.hasPrefix(whole) { return 0 }
        if title.contains(whole) { return 1 }
        for term in terms {
            if term.hasPrefix(whole) { return 2 }
        }
        return 3
    }

    // MARK: Gegevens van de gebruiker

    /// Spaarpotten, beleggingen, doelen en de regels van inkomen en uitgaven (elke naam een keer, ook als de regel
    /// elke maand terugkomt).
    private static func dataEntries(in data: FinanceData) -> [SearchEntry] {
        var entries: [SearchEntry] = []

        for pot in data.pots {
            let name = pot.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            entries.append(SearchEntry(id: "pot-" + pot.id.uuidString, title: name, symbol: pot.symbol,
                                       terms: ["spaarpot"], destination: .pot(pot.id),
                                       hue: TileHue.forIndex(pot.colorIndex)))
        }

        for holding in data.holdings {
            let name = holding.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            var terms: [String] = ["belegging"]
            if let ticker = holding.ticker, !ticker.isEmpty { terms.append(ticker) }
            entries.append(SearchEntry(id: "holding-" + holding.id.uuidString, title: name, symbol: holding.kind.symbol,
                                       terms: terms, destination: .holding(holding.id),
                                       hue: TileHue.forIndex(holding.kind.colorIndex)))
        }

        for goal in data.goals {
            let name = goal.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            entries.append(SearchEntry(id: "goal-" + goal.id.uuidString, title: name, symbol: goal.kind.symbol,
                                       terms: ["doel", goal.kind.title], destination: .goal(goal.id), hue: .mustard))
        }

        var incomeNames = Set<String>()
        var expenseNames = Set<String>()
        for key in data.months.keys.sorted() {
            guard let plan = data.months[key] else { continue }
            for line in plan.extraIncome {
                let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let folded = fold(name)
                if folded.isEmpty || incomeNames.contains(folded) { continue }
                incomeNames.insert(folded)
                entries.append(SearchEntry(id: "income-" + folded, title: name, symbol: "eurosign.circle",
                                           terms: ["inkomsten"], destination: .income, hue: .terracotta))
            }
            for line in plan.expenses {
                let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let folded = fold(name)
                if folded.isEmpty || expenseNames.contains(folded) { continue }
                expenseNames.insert(folded)
                entries.append(SearchEntry(id: "expense-" + folded, title: name, symbol: "creditcard",
                                           terms: ["uitgave"], destination: .expenses, hue: .terracotta))
            }
        }
        return entries
    }
}
