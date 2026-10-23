import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests; de tests staan in PageCatalogTests.swift. De catalogus is de enige tabel met titel,
// symbool, tint, groep en "bereikbaar via" van elke pagina: de Bibliotheek, de bladertegels van Zoeken, de zoekregels en de
// plankkoppen lezen hem. Een test bewijst dat elke pagina bereikbaar blijft (par. 5.3 van docs/design2/plan.md).

// MARK: - De groepen van de Bibliotheek

/// De drie groepen van de Bibliotheek. "Deze maand" krijgt in de lijst de maandnaam erbij ("Deze maand · oktober").
enum LibrarySection: String, CaseIterable, Identifiable {
    case month, saving, planning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Deze maand"
        case .saving: return "Sparen en beleggen"
        case .planning: return "Plannen"
        }
    }
}

// MARK: - Eén pagina

/// Eén pagina van de app met alles wat een rij, tegel of zoekregel nodig heeft.
struct PageInfo: Identifiable, Hashable {
    let destination: Destination
    let title: String
    let symbol: String
    let hue: TileHue
    /// De groep in de Bibliotheek; nil: de pagina heeft geen eigen Bibliotheekrij.
    let section: LibrarySection?
    /// Waar je deze pagina vindt als hij geen Bibliotheekrij is, of de tab (`.library`) als hij er wel een heeft. Een
    /// tabwortel heeft niets (nil).
    let reachableFrom: Destination?
    /// Andere namen waarop je deze pagina zoekt.
    let terms: [String]

    var id: String { String(describing: destination) }
}

// MARK: - De catalogus

enum PageCatalog {
    /// Alle pagina's zonder id: de volgorde is die van de tabel (par. 1.2). Een spaarpot, belegging, doel of
    /// instellingenpagina staat er niet in: die zijn bereikbaar via Spaarpotten, Beleggingen, Doelen en Instellingen.
    static let all: [PageInfo] = [
        PageInfo(destination: .home, title: "Home", symbol: "house", hue: .olive,
                 section: nil, reachableFrom: nil,
                 terms: ["nu", "nog te verdelen", "vermogen", "komende dagen", "start"]),
        PageInfo(destination: .library, title: "Bibliotheek", symbol: "books.vertical", hue: .olive,
                 section: nil, reachableFrom: nil,
                 terms: ["alle pagina's", "blader", "recent"]),
        PageInfo(destination: .flow, title: "Maandoverzicht", symbol: "chart.bar.xaxis", hue: .terracotta,
                 section: .month, reachableFrom: .library,
                 terms: ["waar gaat je geld heen", "periode", "half jaar", "jaar", "maand voor maand", "cijfers van deze periode"]),
        PageInfo(destination: .income, title: "Inkomen", symbol: "eurosign.circle", hue: .terracotta,
                 section: .month, reachableFrom: .library,
                 terms: ["salaris", "overige inkomsten", "loon", "extra inkomsten"]),
        PageInfo(destination: .salary, title: "Salaris instellen", symbol: "eurosign.circle", hue: .terracotta,
                 section: nil, reachableFrom: .income,
                 terms: ["salaris", "uurloon", "uitbetaling", "salarisdag", "loon"]),
        PageInfo(destination: .expenses, title: "Uitgaven", symbol: "creditcard", hue: .terracotta,
                 section: .month, reachableFrom: .library,
                 terms: ["vast", "variabel", "kosten", "lasten", "standaard uitgaven invullen"]),
        PageInfo(destination: .distribute, title: "Verdelen", symbol: "square.split.2x2", hue: .terracotta,
                 section: .month, reachableFrom: .library,
                 terms: ["nog te verdelen", "inleg", "overschrijfdag", "percentage", "overgehouden"]),
        PageInfo(destination: .bank, title: "Bankrekening", symbol: "building.columns", hue: .terracotta,
                 section: .month, reachableFrom: .library,
                 terms: ["saldo", "saldo invullen", "minimumsaldo", "geld bewegen", "boekingen", "geschiedenis", "storten", "opnemen"]),
        PageInfo(destination: .cashflow, title: "Dag voor dag", symbol: "list.bullet.rectangle", hue: .terracotta,
                 section: .month, reachableFrom: .library,
                 terms: ["dagen", "saldo per dag", "zo komt je saldo tot stand", "agenda"]),
        PageInfo(destination: .pots, title: "Spaarpotten", symbol: "tray.full", hue: .teal,
                 section: .saving, reachableFrom: .library,
                 terms: ["spaarpot", "sparen", "rente", "inleg", "kies potten", "potten"]),
        PageInfo(destination: .portfolio, title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis", hue: .slate,
                 section: .saving, reachableFrom: .library,
                 terms: ["beleggen", "koersen", "belegd sinds", "winst", "aandelen", "etf", "crypto", "kies beleggingen"]),
        PageInfo(destination: .goals, title: "Doelen", symbol: "flag.checkered", hue: .mustard,
                 section: .planning, reachableFrom: .library,
                 terms: ["doel", "pensioen", "vakantie", "parttime", "spaardoel"]),
        PageInfo(destination: .savingsGoal, title: "Spaardoel berekenen", symbol: "function", hue: .mustard,
                 section: nil, reachableFrom: .goals,
                 terms: ["spaardoel", "calculator", "hoeveel sparen", "rekenen", "doel"]),
        PageInfo(destination: .buffer, title: "Noodbuffer", symbol: "shield.lefthalf.filled", hue: .mustard,
                 section: .planning, reachableFrom: .library,
                 terms: ["buffer", "noodgeld", "reserve"]),
        PageInfo(destination: .accelerators, title: "Versnellers", symbol: "bolt", hue: .mustard,
                 section: .planning, reachableFrom: .library,
                 terms: ["versnellen", "sneller", "eerder klaar"]),
        PageInfo(destination: .projection, title: "Toekomstschatting", symbol: "calendar.badge.clock", hue: .plum,
                 section: .planning, reachableFrom: .library,
                 terms: ["schatting", "looptijd", "hoe ver kijk je vooruit", "groei", "rendement per jaar", "scenario"]),
        PageInfo(destination: .purchase, title: "Aankoopcheck", symbol: "cart", hue: .plum,
                 section: .planning, reachableFrom: .library,
                 terms: ["aankoop", "kopen", "kan het", "goedkoper"]),
        PageInfo(destination: .tools, title: "Hulpmiddelen", symbol: "wrench.and.screwdriver", hue: .plum,
                 section: nil, reachableFrom: .home,
                 terms: ["rekenhulp", "calculators", "rekenen"]),
        PageInfo(destination: .settingsRoot, title: "Instellingen", symbol: "gearshape", hue: .sage,
                 section: nil, reachableFrom: .home,
                 terms: ["profiel", "voorkeuren", "opties"])
    ]

    /// De pagina's met een eigen rij in de Bibliotheek, in de volgorde van de tabel (13 rijen in 3 groepen).
    static var library: [PageInfo] {
        all.filter { $0.section != nil }
    }

    /// De rijen van een groep van de Bibliotheek.
    static func library(in section: LibrarySection) -> [PageInfo] {
        all.filter { $0.section == section }
    }

    /// De gegevens van een pagina uit de catalogus; nil voor een spaarpot, belegging, doel of instellingenpagina.
    static func info(_ destination: Destination) -> PageInfo? {
        all.first { $0.destination == destination }
    }

    /// De tien bladertegels van Zoeken.
    static let browse: [Destination] = [
        .income, .expenses, .distribute, .bank, .cashflow,
        .pots, .portfolio, .goals, .tools, .settingsRoot
    ]

    /// De bladertegels met hun gegevens, in dezelfde volgorde als `browse`.
    static var browsePages: [PageInfo] {
        browse.compactMap { info($0) }
    }
}
