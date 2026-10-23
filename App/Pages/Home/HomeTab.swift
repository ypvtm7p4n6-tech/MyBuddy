import SwiftUI

/// TIJDELIJKE wortel van Home (pakket 1, tot pakket 2A hem vervangt door hero en planken). Hij toont de inhoud van het oude
/// Overzicht met de nieuwe schil: de meldingen, de kern "Nog te verdelen", het blok Vermogen en de planken-als-kaarten
/// Spaarpotten, Beleggingen, Komende dagen, Doelen en Hulpmiddelen in de volgorde van de gebruiker. Zo blijft elke functie en
/// elke pagina bereikbaar. Zoeken is de zoektab; de profielknop rechtsboven opent Instellingen. Home gaat altijd over de huidige
/// maand en leest `focusMonth` en `periodMode` niet (K17).
struct HomeTab: View {
    var body: some View {
        PageScaffold(title: "Home", large: true) {
            HomeTemporaryDashboard()
        }
        .profileToolbarItem()
    }
}

/// Meldingen, kern, Vermogen en de blokken. Zonder gegevens (`isEmptyStart`) komt het welkomstscherm in plaats van de blokken.
private struct HomeTemporaryDashboard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: Theme.pageSpacing) {
            if let notice = store.startupNotice {
                NoticeCard(text: notice, symbol: "exclamationmark.triangle.fill")
            }
            // Opslaan is mislukt: anders zie je dit pas veel later, terwijl wijzigingen verloren kunnen gaan.
            if store.saveFailed {
                NoticeCard(text: "Opslaan is mislukt. Je laatste wijzigingen zijn mogelijk niet bewaard.",
                           symbol: "exclamationmark.triangle.fill",
                           actionTitle: "Opnieuw proberen",
                           action: { store.retrySave() })
                    .transition(.opacity)
            }
            SyncAttentionBanner()
            OverviewCheckBanner()
            OverviewHero()
            if store.data.isEmptyStart {
                OverviewWelcome()
            } else {
                OverviewWealthCard()
                HomeTemporaryBlocks()
            }
        }
        .animated(by: store.saveFailed)
    }
}

/// De planken van Home als kaarten, in de volgorde van de gebruiker (`OrderedBlocks` met de id's van `BlockPage.overview`).
private struct HomeTemporaryBlocks: View {
    var body: some View {
        LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
            OrderedBlocks(page: .overview) { id in
                HomeTemporaryBlock(id: id)
            }
        }
    }
}

/// De kaart bij een blok-id van `BlockPage.overview`.
private struct HomeTemporaryBlock: View {
    let id: String

    var body: some View {
        switch id {
        case "upcoming": UpcomingDaysCard()
        case "pots": HomePotsCard()
        case "invest": HomeHoldingsCard()
        case "goals": GoalsSummaryCard()
        case "tools": HomeToolsLink()
        default: EmptyView()
        }
    }
}

/// De kaart Hulpmiddelen: een link naar de lijst van vier rekenpagina's.
private struct HomeToolsLink: View {
    var body: some View {
        LinkCard(title: "Hulpmiddelen", symbol: "wrench.and.screwdriver", domain: .tools,
                 subtitle: "Noodbuffer, Versnellers, Toekomstschatting en Aankoopcheck", destination: .tools) {
            EmptyView()
        }
    }
}
