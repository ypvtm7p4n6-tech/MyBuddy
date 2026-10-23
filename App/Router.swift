import SwiftUI
import Observation

/// De navigatie van de app: welke tab is open, het pad (de stapel pagina's) van elke tab en de maand waar je naar kijkt.
/// `AppTab`, `Destination` en de regels voor een pad staan in `App/Navigation/NavigationModel.swift`.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .home
    /// Het pad van elke tab. Van tab wisselen wist niets; een tik op de actieve tab brengt je terug naar de wortel.
    var paths: [AppTab: [Destination]] = [.home: [], .library: [], .search: []]
    /// De pagina waarvan de blokvolgorde wordt aangepast (laat het blad "Volgorde aanpassen" zien).
    var orderPage: BlockPage?

    /// De maand waar je naar kijkt op de maandpagina's (Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag, Maandoverzicht).
    /// Home en de Bibliotheek lezen dit niet: die gaan altijd over de huidige maand (K17).
    var focusMonth: YearMonth = YearMonth.current()
    var periodMode: PeriodMode = .month

    /// De zoektab opent zijn zoekveld zodra dit getal oploopt.
    var searchRequest = 0
    /// macOS: de wortel opent het `Settings`-venster op deze pane en het venster wist het verzoek weer.
    var settingsRequest: SettingsPage?

    // MARK: Paden

    /// De binding voor de `NavigationStack` van een tab. Elke schrijfactie, ook die van een `NavigationLink(value:)`, gaat
    /// door `NavigationRules.normalize`: een pagina staat nooit twee keer in een pad.
    func pathBinding(for tab: AppTab) -> Binding<[Destination]> {
        Binding(
            get: { self.paths[tab] ?? [] },
            set: { newPath in self.paths[tab] = NavigationRules.normalize(newPath) }
        )
    }

    /// Wisselt alleen van tab; het pad van die tab blijft zoals het was.
    func select(_ newTab: AppTab) {
        tab = newTab
    }

    /// Maakt het pad van een tab leeg: je ziet weer de wortel.
    func popToRoot(_ target: AppTab) {
        paths[target] = []
    }

    /// Opent een pagina op de stapel waar je nu bent (B5): geen tabwissel. Staat de pagina al in het pad, dan ga je terug naar
    /// die plek; dezelfde pagina mag wel op het pad van een andere tab staan. Een tabwortel gaat via `go`. Op de Mac is
    /// Instellingen een eigen venster: daar wordt het een verzoek aan de wortel om dat venster te openen (`go`).
    func open(_ destination: Destination) {
        if destination.isTabRoot || opensMacSettings(destination) {
            go(destination)
            return
        }
        paths[tab] = NavigationRules.push(destination, onto: paths[tab] ?? [])
    }

    /// Gaat rechtstreeks naar een pagina (zoeken, sneltoetsen, meldingen, diepe links): een tabwortel selecteert die tab, een
    /// instellingenpagina blijft op de huidige stapel, al het andere opent in de Bibliotheek met het ouderpad (een spaarpot
    /// onder Spaarpotten). Op de Mac zet Instellingen een verzoek voor het `Settings`-venster (`.settingsRoot` wordt Account).
    func go(_ destination: Destination) {
        #if os(macOS)
        switch destination {
        case .settingsRoot:
            settingsRequest = .account
            return
        case .settings(let page):
            settingsRequest = page
            return
        default:
            break
        }
        #endif
        let target = NavigationRules.go(destination, from: tab, path: paths[tab] ?? [])
        paths[target.tab] = target.path
        tab = target.tab
    }

    /// Selecteert de zoektab en laat het zoekveld openen.
    func requestSearch() {
        select(.search)
        searchRequest += 1
    }

    /// Is dit op de Mac een pagina van Instellingen? (Daar bestaat geen pad voor: het `Settings`-venster opent.)
    private func opensMacSettings(_ destination: Destination) -> Bool {
        #if os(macOS)
        switch destination {
        case .settingsRoot, .settings:
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: Periode

    /// Schuift de periode op: richting -1 = terug, +1 = vooruit.
    func shiftPeriod(_ direction: Int) {
        focusMonth = focusMonth.adding(direction * periodMode.stepMonths)
    }

    /// Springt naar de huidige maand.
    func resetFocus(to current: YearMonth) {
        focusMonth = current
    }

    /// Zet de maandpagina's op de huidige maand en de periode "Maand". Een tegel op Home of een rij in de Bibliotheek gaat altijd
    /// over deze maand; zonder dit kon de pagina nog op een andere maand of periode staan en een ander getal tonen.
    func showCurrentMonth(_ current: YearMonth) {
        focusMonth = current
        periodMode = .month
    }
}
