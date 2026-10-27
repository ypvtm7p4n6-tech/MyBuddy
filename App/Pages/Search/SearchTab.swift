import SwiftUI

// Zoeken (B9 en par. 3 van docs/design2/plan.md). Zonder tekst: de tien bladertegels van `PageCatalog.browse`, zodat elke pagina
// een vaste plek heeft. Met tekst: de resultaten van `SearchIndex` per groep (Pagina's, Spaarpotten, Beleggingen, Doelen, Inkomen
// en uitgaven, Instellingen). Er is geen zoekgeschiedenis. Cmd+F selecteert deze tab en opent het zoekveld
// (`router.requestSearch()`). De wortel is alleen inhoud: de stapel komt van `TabStack`.

/// De wortel van de tab Zoeken: het zoekveld van het systeem met daaronder de bladertegels of de resultaten.
struct SearchTab: View {
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var isSearching = false
    /// Het laatste verzoek van Cmd+F dat het zoekveld al heeft geopend. De tab kan pas na het verzoek bestaan.
    @State private var handledRequest = 0

    var body: some View {
        PageScaffold(title: "Zoeken", large: true) {
            SearchTabContent(query: query, onOpen: open)
        }
        .searchable(text: $query, isPresented: $isSearching, prompt: "Zoek in MyBuddy")
        .onChange(of: router.searchRequest) { _, _ in
            showField()
        }
        .onAppear {
            if handledRequest != router.searchRequest {
                showField()
            }
        }
        .profileToolbarItem()
    }

    /// Opent het zoekveld (Cmd+F).
    private func showField() {
        handledRequest = router.searchRequest
        isSearching = true
    }

    /// Een resultaat opent op de stapel van deze tab, dus terug brengt je bij de resultaten. De wortels van Home en de Bibliotheek
    /// selecteren hun tab, en Instellingen opent met zijn ouders (op de Mac in het `Settings`-venster).
    private func open(_ entry: SearchEntry) {
        if entry.destination.isTabRoot || entry.group == .settings {
            router.go(entry.destination)
        } else {
            router.open(entry.destination)
        }
    }
}

/// De inhoud onder het zoekveld: de bladertegels zolang er niets staat, anders de resultaten.
struct SearchTabContent: View {
    let query: String
    let onOpen: (SearchEntry) -> Void

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if hasQuery {
            SearchResults(query: query, onOpen: onOpen)
        } else {
            SearchBrowseGrid()
        }
    }
}

// MARK: - Bladeren

/// De tien bladertegels onder de kop "Blader": twee kolommen op een iPhone, meer op een iPad of Mac.
struct SearchBrowseGrid: View {
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Blader")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(PageCatalog.browsePages) { info in
                    BrowseTile(title: info.title, symbol: info.symbol, hue: info.hue, destination: info.destination)
                }
            }
        }
    }
}

// MARK: - Resultaten

/// Een groep resultaten: Identifiable, zodat `ForEach` er geen tuple in hoeft te lezen.
private struct SearchResultGroup: Identifiable {
    let group: SearchGroup
    let entries: [SearchEntry]

    var id: Int { group.rawValue }
}

/// De resultaten per groep, elke groep in een kaart onder zijn kop. Geen treffers: de standaard lege staat van het systeem.
struct SearchResults: View {
    let query: String
    let onOpen: (SearchEntry) -> Void
    @Environment(AppStore.self) private var store

    private var groups: [SearchResultGroup] {
        var result: [SearchResultGroup] = []
        for found in SearchIndex.grouped(for: query, in: store.data) {
            result.append(SearchResultGroup(group: found.group, entries: found.entries))
        }
        return result
    }

    var body: some View {
        let found = groups
        if found.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                ForEach(found) { group in
                    SearchResultSection(group: group, onOpen: onOpen)
                }
            }
        }
    }
}

/// Eén groep: de kop (een kop voor VoiceOver) en de rijen in een kaart.
private struct SearchResultSection: View {
    let group: SearchResultGroup
    let onOpen: (SearchEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text(group.group.title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Card {
                ForEach(group.entries) { entry in
                    SearchResultRow(entry: entry, onOpen: onOpen)
                }
            }
        }
    }
}

/// Eén resultaat: tegel, naam en een pijltje. Bij een regel van inkomen of uitgaven staat erbij welke van de twee het is.
private struct SearchResultRow: View {
    let entry: SearchEntry
    let onOpen: (SearchEntry) -> Void

    private var subtitle: String? {
        guard entry.group == .lines else { return nil }
        return entry.destination == .income ? "Inkomen" : "Uitgave"
    }

    var body: some View {
        Button {
            onOpen(entry)
        } label: {
            MediaRowLabel(symbol: entry.symbol, hue: entry.hue, title: entry.title, subtitle: subtitle, showsChevron: true)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityAddTraits(.isLink)
    }
}
