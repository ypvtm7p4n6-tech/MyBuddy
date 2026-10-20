import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de gegevens via `@testable import`; de tests staan in SearchIndexTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Zoeken in MyBuddy

/// Eén zoekresultaat: een pagina, een spaarpot, een belegging, een doel of een regel van inkomen of uitgaven.
struct SearchEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    /// Andere namen waarop je dit vindt (de zoekopdracht mag er een deel van zijn).
    let terms: [String]
    /// Waar een tik op het resultaat heen gaat (`router.go(_:)`).
    let destination: Destination
}

/// De zoekfunctie van de app (par. 2.9). De pagina's staan in een vaste lijst; daarnaast zoekt `results(for:in:)` in de namen
/// van je spaarpotten, beleggingen, doelen en de regels van inkomen en uitgaven. Zo vind je een onderdeel ook als je de naam
/// niet meer weet.
enum SearchIndex {
    /// Het grootste aantal resultaten dat een zoekopdracht teruggeeft.
    static let maxResults = 50

    // MARK: Pagina's

    /// Een regel voor elke bestemming zonder id en voor elke pagina van Instellingen.
    static let pages: [SearchEntry] = [
        page("overview", "Overzicht", "chart.pie",
             ["nu", "nog te verdelen", "vermogen", "komende dagen"], .overview),
        page("income", "Inkomen", "eurosign.circle",
             ["salaris", "overige inkomsten", "loon", "extra inkomsten"], .income),
        page("salary", "Salaris instellen", "eurosign.circle",
             ["salaris", "uurloon", "uitbetaling", "salarisdag", "loon"], .salary),
        page("expenses", "Uitgaven", "creditcard",
             ["vast", "variabel", "kosten", "lasten", "standaard uitgaven invullen"], .expenses),
        page("distribute", "Verdelen", "square.split.2x2",
             ["nog te verdelen", "inleg", "overschrijfdag", "percentage", "overgehouden"], .distribute),
        page("bank", "Bankrekening", "building.columns",
             ["saldo", "saldo invullen", "minimumsaldo", "geld bewegen", "boekingen", "geschiedenis", "storten", "opnemen"], .bank),
        page("cashflow", "Dag voor dag", "list.bullet.rectangle",
             ["dagen", "saldo per dag", "zo komt je saldo tot stand", "agenda"], .cashflow),
        page("pots", "Spaarpotten", "tray.full",
             ["spaarpot", "sparen", "rente", "inleg", "kies potten", "potten"], .pots),
        page("portfolio", "Beleggingen", "chart.line.uptrend.xyaxis",
             ["beleggen", "koersen", "belegd sinds", "winst", "aandelen", "etf", "crypto", "kies beleggingen"], .portfolio),
        page("goals", "Doelen", "flag.checkered",
             ["doel", "pensioen", "vakantie", "parttime", "spaardoel"], .goals),
        page("savingsGoal", "Spaardoel berekenen", "function",
             ["spaardoel", "calculator", "hoeveel sparen", "rekenen", "doel"], .savingsGoal),
        page("accelerators", "Versnellers", "bolt",
             ["versnellen", "sneller", "eerder klaar"], .accelerators),
        page("buffer", "Noodbuffer", "shield.lefthalf.filled",
             ["buffer", "noodgeld", "reserve"], .buffer),
        page("projection", "Toekomstschatting", "calendar.badge.clock",
             ["schatting", "looptijd", "hoe ver kijk je vooruit", "groei", "rendement per jaar", "scenario"], .projection),
        page("purchase", "Aankoopcheck", "cart",
             ["aankoop", "kopen", "kan het", "goedkoper"], .purchase),
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

    private static func page(_ id: String, _ title: String, _ symbol: String, _ terms: [String],
                             _ destination: Destination) -> SearchEntry {
        SearchEntry(id: id, title: title, symbol: symbol, terms: terms, destination: destination)
    }

    /// Een pagina van Instellingen: titel en symbool van de pagina zelf.
    private static func settingsPage(_ page: SettingsPage, _ terms: [String]) -> SearchEntry {
        SearchEntry(id: "settings-" + page.rawValue, title: page.title, symbol: page.symbol, terms: terms,
                    destination: .settings(page))
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
                                       terms: ["spaarpot"], destination: .pot(pot.id)))
        }

        for holding in data.holdings {
            let name = holding.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            var terms: [String] = ["belegging"]
            if let ticker = holding.ticker, !ticker.isEmpty { terms.append(ticker) }
            entries.append(SearchEntry(id: "holding-" + holding.id.uuidString, title: name, symbol: holding.kind.symbol,
                                       terms: terms, destination: .holding(holding.id)))
        }

        for goal in data.goals {
            let name = goal.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            entries.append(SearchEntry(id: "goal-" + goal.id.uuidString, title: name, symbol: goal.kind.symbol,
                                       terms: ["doel", goal.kind.title], destination: .goal(goal.id)))
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
                                           terms: ["inkomsten"], destination: .income))
            }
            for line in plan.expenses {
                let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let folded = fold(name)
                if folded.isEmpty || expenseNames.contains(folded) { continue }
                expenseNames.insert(folded)
                entries.append(SearchEntry(id: "expense-" + folded, title: name, symbol: "creditcard",
                                           terms: ["uitgave"], destination: .expenses))
            }
        }
        return entries
    }
}
