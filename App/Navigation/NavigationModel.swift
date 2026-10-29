import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests; de tests staan in NavigationRulesTests.swift. `PageCatalog.swift` (ook Foundation-only)
// beschrijft elke bestemming met titel, symbool, tint en groep.

// MARK: - Tabs

/// De drie tabs van de app: Home, Bibliotheek en Zoeken (de zoektab staat los en rechts). Op iPhone, iPad en Mac zijn het
/// dezelfde drie; op iPad en Mac staan ze in de zijbalk. Instellingen is geen tab: op iPhone en iPad opent de profielknop
/// de pagina `Destination.settingsRoot`, op de Mac staat Instellingen in het `Settings`-venster.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, library, search

    var id: String { rawValue }

    /// Eén woord, zinshoofdletter (termenlijst).
    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Bibliotheek"
        case .search: return "Zoeken"
        }
    }

    /// SF Symbol van de tab. De gevulde variant van een geselecteerde tab kiest het systeem zelf.
    var symbol: String {
        switch self {
        case .home: return "house"
        case .library: return "books.vertical"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - Pagina's van Instellingen

/// De pagina's van Instellingen. Account is de eerste rij; wachtwoord, account verwijderen en de back-ups van conflicten
/// zijn subpagina's van Account, het importoverzicht en de startdatum zijn subpagina's van Gegevens.
enum SettingsPage: String, CaseIterable, Hashable {
    case account, password, deleteAccount, conflictBackups,
         calculations, prices, data, layout, about, importReview, startDate

    var title: String {
        switch self {
        case .account: return "Account"
        case .password: return "Wachtwoord wijzigen"
        case .deleteAccount: return "Account verwijderen"
        case .conflictBackups: return "Back-ups van conflicten"
        case .calculations: return "Rekenen"
        case .prices: return "Koersen"
        case .data: return "Gegevens"
        case .layout: return "Indeling"
        case .about: return "Over MyBuddy"
        case .importReview: return "Importoverzicht"
        case .startDate: return "Startdatum"
        }
    }

    var symbol: String {
        switch self {
        case .account: return "person.crop.circle"
        case .password: return "lock"
        case .deleteAccount: return "trash"
        case .conflictBackups: return "clock.arrow.circlepath"
        case .calculations: return "percent"
        case .prices: return "arrow.triangle.2.circlepath"
        case .data: return "externaldrive"
        case .layout: return "arrow.up.arrow.down"
        case .about: return "info.circle"
        case .importReview: return "square.and.arrow.down"
        case .startDate: return "calendar.badge.plus"
        }
    }

    /// De pagina waaronder deze pagina in een pad staat (nil: een hoofdpagina van Instellingen).
    var parent: SettingsPage? {
        switch self {
        case .password, .deleteAccount, .conflictBackups: return .account
        case .importReview, .startDate: return .data
        case .account, .calculations, .prices, .data, .layout, .about: return nil
        }
    }

    /// De pane van het `Settings`-venster op de Mac waar deze pagina in thuishoort (een subpagina is een push in de pane
    /// van haar ouder).
    var pane: SettingsPage { parent ?? self }

    /// De zes hoofdpagina's, in de volgorde van de lijst op de tab (iOS) en van de panes (Mac).
    static let panes: [SettingsPage] = [.account, .calculations, .prices, .data, .layout, .about]
}

// MARK: - Bestemmingen

/// Alle pagina's die je bereikt door op een tegel, rij of knop te tikken (en die dus op de navigatiestapel van een tab komen).
/// `PageCatalog` (PageCatalog.swift) is de tabel met titel, symbool, tint en groep van elke bestemming.
enum Destination: Hashable {
    /// De wortels van de tabs Home en Bibliotheek: alleen voor zoeken, sneltoetsen en diepe links.
    case home, library
    /// Maandoverzicht ("Waar gaat je geld heen").
    case flow
    case income, salary, expenses, distribute, bank, cashflow
    case pots, pot(UUID), portfolio, holding(UUID)
    case goals, goal(UUID), savingsGoal, accelerators, buffer, projection, purchase
    /// Hulpmiddelen (de lijst van vier rekenpagina's).
    case tools
    /// Instellingen (de lijst, Account eerst en los), een gepushte pagina op iPhone en iPad.
    case settingsRoot
    case settings(SettingsPage)
}

extension Destination {
    /// Is dit de wortel van een tab? Een wortel staat nooit op een pad.
    var isTabRoot: Bool {
        switch self {
        case .home, .library:
            return true
        case .flow, .income, .salary, .expenses, .distribute, .bank, .cashflow,
             .pots, .pot, .portfolio, .holding,
             .goals, .goal, .savingsGoal, .accelerators, .buffer, .projection, .purchase,
             .tools, .settingsRoot, .settings:
            return false
        }
    }

    /// De bestemmingen waaronder deze pagina in een pad staat als je er rechtstreeks naartoe gaat (`NavigationRules.go`):
    /// een spaarpot onder Spaarpotten, een belegging onder Beleggingen, een doel onder Doelen, Salaris onder Inkomen, en een
    /// instellingenpagina onder Instellingen (en een subpagina van Account of Gegevens ook onder haar hoofdpagina).
    var parents: [Destination] {
        switch self {
        case .pot:
            return [.pots]
        case .holding:
            return [.portfolio]
        case .goal:
            return [.goals]
        case .salary:
            return [.income]
        case .settings(let page):
            if let parent = page.parent { return [.settingsRoot, .settings(parent)] }
            return [.settingsRoot]
        case .home, .library, .flow, .income, .expenses, .distribute, .bank, .cashflow,
             .pots, .portfolio,
             .goals, .savingsGoal, .accelerators, .buffer, .projection, .purchase,
             .tools, .settingsRoot:
            return []
        }
    }
}

// MARK: - Regels voor een pad

/// De regels van de navigatiepaden, zonder SwiftUI zodat ze getest kunnen worden.
enum NavigationRules {
    /// Een pagina staat nooit twee keer in een pad: komt een bestemming een tweede keer voor, dan wordt het pad afgeknipt
    /// tot de eerste plek van die bestemming (Spaarpot, Dag voor dag, Spaarpot wordt Spaarpot). Een pad zonder herhaling
    /// blijft gelijk; het resultaat heeft nooit een herhaling, dus nogmaals normaliseren verandert niets.
    static func normalize(_ path: [Destination]) -> [Destination] {
        var firstIndex: [Destination: Int] = [:]
        var index = 0
        for destination in path {
            if let earlier = firstIndex[destination] {
                return Array(path[0...earlier])
            }
            firstIndex[destination] = index
            index += 1
        }
        return path
    }

    /// Het pad na het openen van `destination` boven op `path`.
    static func push(_ destination: Destination, onto path: [Destination]) -> [Destination] {
        normalize(path + [destination])
    }

    /// Rechtstreeks naar een bestemming, vanaf de tab `current` met het pad `path` (zoeken, sneltoetsen, diepe links):
    /// - `.home` en `.library` zijn tabwortels: die tab met een leeg pad.
    /// - `.settingsRoot` en `.settings(_)` blijven op de huidige stapel: het pad krijgt de ontbrekende `.settingsRoot` en
    ///   `.settings(hoofdpagina)` en daarna de bestemming. Staat `.settingsRoot` al in het pad, dan wordt het pad daar
    ///   teruggebracht, zodat je niet boven op een oude instellingenpagina uitkomt.
    /// - Al het andere opent in de Bibliotheek, met de ouders (`parents`) en de pagina zelf.
    /// Het pad heeft nooit een herhaling.
    static func go(_ destination: Destination, from current: AppTab, path: [Destination]) -> (tab: AppTab, path: [Destination]) {
        switch destination {
        case .home:
            return (tab: .home, path: [])
        case .library:
            return (tab: .library, path: [])
        case .settingsRoot, .settings:
            return (tab: current, path: settingsPath(to: destination, from: path))
        case .flow, .income, .salary, .expenses, .distribute, .bank, .cashflow,
             .pots, .pot, .portfolio, .holding,
             .goals, .goal, .savingsGoal, .accelerators, .buffer, .projection, .purchase,
             .tools:
            return (tab: .library, path: normalize(destination.parents + [destination]))
        }
    }

    /// Het pad naar een instellingenpagina op de stapel `path`.
    private static func settingsPath(to destination: Destination, from path: [Destination]) -> [Destination] {
        var result: [Destination] = path + [.settingsRoot]
        if let rootIndex = path.firstIndex(of: .settingsRoot) {
            result = Array(path[0...rootIndex])
        }
        for parent in destination.parents where parent != .settingsRoot {
            result.append(parent)
        }
        if destination != .settingsRoot {
            result.append(destination)
        }
        return normalize(result)
    }
}
