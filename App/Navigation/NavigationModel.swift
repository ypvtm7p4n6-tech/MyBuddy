import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests; de tests staan in NavigationRulesTests.swift.

// MARK: - Tabs

/// De tabs van de app. Op de iPhone en iPad zijn het er vijf; op de Mac staat Instellingen niet in de zijbalk maar in een
/// eigen venster (het `Settings`-venster), dus daar zijn het er vier.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case overview, month, saving, planning, settings

    var id: String { rawValue }

    /// Eén woord, zinshoofdletter (termenlijst).
    var title: String {
        switch self {
        case .overview: return "Overzicht"
        case .month: return "Maand"
        case .saving: return "Sparen"
        case .planning: return "Plannen"
        case .settings: return "Instellingen"
        }
    }

    /// SF Symbol van de tab. De gevulde variant van een geselecteerde tab kiest het systeem zelf.
    var symbol: String {
        switch self {
        case .overview: return "chart.pie"
        case .month: return "calendar"
        case .saving: return "banknote"
        case .planning: return "flag.checkered"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Pagina's van Instellingen

/// De pagina's van Instellingen. Account is de eerste rij; wachtwoord, account verwijderen en de back-ups van conflicten
/// zijn subpagina's van Account, het importoverzicht is een subpagina van Gegevens.
enum SettingsPage: String, CaseIterable, Hashable {
    case account, password, deleteAccount, conflictBackups,
         calculations, prices, data, layout, about, importReview

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
        }
    }

    /// De pagina waaronder deze pagina in een pad staat (nil: een hoofdpagina van Instellingen).
    var parent: SettingsPage? {
        switch self {
        case .password, .deleteAccount, .conflictBackups: return .account
        case .importReview: return .data
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

/// Alle pagina's die je bereikt door op een blok of rij te tikken (en die dus op de navigatiestapel van een tab komen).
enum Destination: Hashable {
    case overview
    case income, salary, expenses, distribute, bank, cashflow
    case pots, pot(UUID), portfolio, holding(UUID)
    case goals, goal(UUID), savingsGoal, accelerators, buffer, projection, purchase
    case settings(SettingsPage)
}

extension Destination {
    /// De tab waar deze bestemming thuishoort. Een tik op een link naar een pagina van een andere tab wisselt van tab.
    var tab: AppTab {
        switch self {
        case .overview:
            return .overview
        case .income, .salary, .expenses, .distribute, .bank, .cashflow:
            return .month
        case .pots, .pot, .portfolio, .holding:
            return .saving
        case .goals, .goal, .savingsGoal, .accelerators, .buffer, .projection, .purchase:
            return .planning
        case .settings:
            return .settings
        }
    }

    /// De bestemmingen waaronder deze pagina in een pad staat als je er rechtstreeks naartoe gaat (`NavigationRules.go`):
    /// een spaarpot onder Spaarpotten, een belegging onder Beleggingen, een doel onder Doelen, Salaris onder Inkomen,
    /// en de subpagina's van Account en Gegevens onder hun hoofdpagina.
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
            if let parent = page.parent { return [.settings(parent)] }
            return []
        case .overview, .income, .expenses, .distribute, .bank, .cashflow,
             .pots, .portfolio,
             .goals, .savingsGoal, .accelerators, .buffer, .projection, .purchase:
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

    /// Rechtstreeks naar een bestemming: de eigen tab en het pad (ouderpad plus de bestemming). Het Overzicht is een
    /// tabwortel en heeft een leeg pad.
    static func go(_ destination: Destination) -> (tab: AppTab, path: [Destination]) {
        if destination == .overview {
            return (tab: .overview, path: [])
        }
        return (tab: destination.tab, path: normalize(destination.parents + [destination]))
    }
}
