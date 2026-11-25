import Foundation
// Foundation-only: geen SwiftUI. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat dit bestand als symlink tussen de tests;
// de tests staan in BreadcrumbTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Waar ben je? (zoals het kruimelpad van apple.com)
//
// Op apple.com zie je altijd waar je bent en spring je met één tik naar elk niveau erboven ("Apple › iPhone › iPhone 16 Pro"). In de app:
// tik op de titel van een pagina en je krijgt een menu met elk niveau boven die pagina, tot de wortel van de tab. Het systeem tekent het
// menu (`toolbarTitleMenu`); hier staat welke niveaus er zijn en hoe ze heten.

struct Breadcrumb: Equatable, Identifiable {
    /// Hoeveel pagina's er na de keuze op het pad blijven staan (0: terug naar de wortel van de tab).
    let depth: Int
    let title: String
    let symbol: String

    var id: Int { depth }
}

enum Breadcrumbs {
    /// De niveaus boven de pagina op plaats `index` van `path`, van de wortel van de tab tot de pagina erboven. Leeg als de pagina niet
    /// (meer) op het pad staat.
    static func crumbs(above index: Int, in path: [Destination], tab: AppTab, data: FinanceData) -> [Breadcrumb] {
        guard path.indices.contains(index) else { return [] }
        let rootDestination = tab.rootDestination
        var result = [Breadcrumb(depth: 0, title: rootDestination.map { title(of: $0, data: data) } ?? tab.title,
                                 symbol: tab.symbol)]
        for (offset, destination) in path.prefix(index).enumerated() {
            result.append(Breadcrumb(depth: offset + 1, title: title(of: destination, data: data), symbol: symbol(of: destination)))
        }
        return result
    }

    /// De naam van een pagina zoals de pagina zelf heet: uit de catalogus, of de naam van de spaarpot, belegging of het doel.
    static func title(of destination: Destination, data: FinanceData) -> String {
        switch destination {
        case .pot(let id): return data.pot(id)?.name ?? "Spaarpot"
        case .holding(let id): return data.holding(id)?.name ?? "Belegging"
        case .goal(let id): return data.goal(id)?.name ?? "Doel"
        case .wageChange: return "Loon wijzigen"
        // De catalogus zegt "Salaris instellen" (voor zoeken); de pagina zelf heet "Salaris".
        case .salary: return "Salaris"
        case .settingsRoot: return "Instellingen"
        case .settings(let page): return page.title
        case .home: return AppTab.home.title
        case .library: return AppTab.library.title
        default: return PageCatalog.info(destination)?.title ?? ""
        }
    }

    static func symbol(of destination: Destination) -> String {
        switch destination {
        case .pot: return "tray"
        case .holding: return "chart.line.uptrend.xyaxis"
        case .goal: return "flag"
        case .wageChange: return "eurosign.arrow.circlepath"
        case .settingsRoot: return "gearshape"
        case .settings(let page): return page.symbol
        default: return PageCatalog.info(destination)?.symbol ?? "doc"
        }
    }
}
