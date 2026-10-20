import SwiftUI
import Observation

/// De navigatie van de app: welke tab is open, het pad (de stapel pagina's) van elke tab en de maand waar je naar kijkt.
/// `AppTab`, `Destination` en de regels voor een pad staan in `App/Navigation/NavigationModel.swift`.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .overview
    /// Het pad van elke tab. Van tab wisselen wist niets; een tik op de actieve tab brengt je terug naar de wortel.
    var paths: [AppTab: [Destination]] = [.overview: [], .month: [], .saving: [], .planning: [], .settings: []]
    /// De pagina waarvan de blokvolgorde wordt aangepast (laat het blad "Volgorde aanpassen" zien).
    var orderPage: BlockPage?

    /// De maand waar je naar kijkt op de Maand-tab en de pagina's eronder. Het Overzicht leest dit niet: dat gaat altijd over
    /// de huidige maand.
    var focusMonth: YearMonth = YearMonth.current()
    var periodMode: PeriodMode = .month

    /// Het Overzicht opent zijn zoekveld zodra dit getal oploopt.
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

    /// Opent een pagina. Hoort die bij de tab waar je nu bent, dan komt hij op het pad van die tab (staat hij er al, dan ga je
    /// terug naar die plek); anders ga je naar de tab van de pagina (`go`).
    func open(_ destination: Destination) {
        if destination.tab == tab {
            paths[tab] = NavigationRules.push(destination, onto: paths[tab] ?? [])
        } else {
            go(destination)
        }
    }

    /// Gaat rechtstreeks naar een pagina: de eigen tab van de pagina, met als pad het ouderpad plus de pagina (een spaarpot
    /// onder Spaarpotten). Gebruik dit voor zoeken, sneltoetsen, meldingen en links naar een andere tab.
    /// Op de Mac is Instellingen een eigen venster: daar wordt het een verzoek aan de wortel om dat venster te openen.
    func go(_ destination: Destination) {
        #if os(macOS)
        if case .settings(let page) = destination {
            settingsRequest = page
            return
        }
        #endif
        let target = NavigationRules.go(destination)
        paths[target.tab] = target.path
        tab = target.tab
    }

    /// Gaat naar het Overzicht en laat het zoekveld openen.
    func requestSearch() {
        go(.overview)
        searchRequest += 1
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

    /// Zet de Maand-tab op de huidige maand en de periode "Maand". Een kaart op het Overzicht gaat altijd over deze maand;
    /// zonder dit kon de pagina nog op een andere maand of periode staan en een ander getal tonen.
    func showCurrentMonth(_ current: YearMonth) {
        focusMonth = current
        periodMode = .month
    }

    // MARK: Overgangsvorm (tot pakket G)

    /// De oude paden van de drie oude tabroots verwijzen door naar `paths`.
    var homePath: [Destination] {
        get { paths[.overview] ?? [] }
        set { paths[.overview] = NavigationRules.normalize(newValue) }
    }

    var savingsPath: [Destination] {
        get { paths[.month] ?? [] }
        set { paths[.month] = NavigationRules.normalize(newValue) }
    }

    var toolsPath: [Destination] {
        get { paths[.planning] ?? [] }
        set { paths[.planning] = NavigationRules.normalize(newValue) }
    }

    /// Instellingen is geen blad meer. Het oude tandwiel in `PageScaffold` gaat nu naar Account.
    var showSettings: Bool {
        get { false }
        set { if newValue { go(.settings(.account)) } }
    }
}
