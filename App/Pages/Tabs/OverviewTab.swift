import SwiftUI

/// Tab 1, Overzicht: wat er nu is (par. 2.2 en 2.4 van docs/design/plan.md). Bovenaan de meldingen, dan de kern ("Nog te
/// verdelen in oktober") en daaronder de blokken in de volgorde van de gebruiker: Vermogen, Spaarpotten, Beleggingen en Komende
/// dagen. Het Overzicht gaat altijd over de huidige maand en leest `focusMonth` en `periodMode` niet (K17). Zonder gegevens staat
/// er een welkomstscherm in plaats van de blokken. Alleen inhoud: de `NavigationStack` komt van `TabStack`.
struct OverviewTab: View {
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var isSearching = false

    var body: some View {
        PageScaffold(title: "Overzicht", large: true) {
            pageContent
        }
        .searchable(text: $query, isPresented: $isSearching, prompt: "Zoek in MyBuddy")
        .onChange(of: router.searchRequest) { _, _ in
            isSearching = true
        }
        .blockOrderToolbar(page: .overview)
    }

    /// Het dashboard, of de zoekresultaten zodra er iets in het zoekveld staat.
    @ViewBuilder
    private var pageContent: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            OverviewDashboard()
        } else {
            OverviewSearchResults(query: query, onOpen: openResult)
        }
    }

    /// Een resultaat opent met `router.go`; daarna sluit het zoekveld en is het leeg.
    private func openResult(_ entry: SearchEntry) {
        router.go(entry.destination)
        query = ""
        isSearching = false
    }
}

// MARK: - Dashboard

/// Meldingen, kern en blokken. Zonder gegevens (`isEmptyStart`) komt het welkomstscherm in plaats van de blokken.
private struct OverviewDashboard: View {
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
                OverviewBlocks()
            }
        }
        .animated(by: store.saveFailed)
    }
}

/// De blokken van het Overzicht in de volgorde van de gebruiker (`OrderedBlocks` met de id's uit par. 2.7).
private struct OverviewBlocks: View {
    var body: some View {
        LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
            OrderedBlocks(page: .overview) { id in
                OverviewBlockContent(id: id)
            }
        }
    }
}

/// Het blok bij een blok-id van `BlockPage.overview`.
private struct OverviewBlockContent: View {
    let id: String

    var body: some View {
        switch id {
        case "wealth": OverviewWealthCard()
        case "pots": HomePotsCard()
        case "invest": HomeHoldingsCard()
        case "upcoming": UpcomingDaysCard()
        default: EmptyView()
        }
    }
}

// MARK: - Zoeken

/// De resultaten van `SearchIndex` voor wat er in het zoekveld staat. Geen treffers: de standaard lege staat van het systeem.
private struct OverviewSearchResults: View {
    let query: String
    let onOpen: (SearchEntry) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let results = SearchIndex.results(for: query, in: store.data)
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Card(title: "Zoekresultaten", symbol: "magnifyingglass") {
                ForEach(results) { entry in
                    OverviewSearchRow(entry: entry) { onOpen(entry) }
                }
            }
        }
    }
}

/// Eén resultaat: pictogram, naam en een pijltje.
private struct OverviewSearchRow: View {
    let entry: SearchEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: entry.symbol, color: Theme.textSecondary, size: 32)
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
    }
}
