import SwiftUI

/// TIJDELIJKE wortel van Zoeken (pakket 1, tot pakket 2B hem vervangt): het zoekveld, zonder tekst de tien bladertegels (zo
/// blijven Hulpmiddelen en Instellingen bereikbaar) en met tekst de resultaten van `SearchIndex` als platte lijst. Cmd+F opent het
/// veld (`router.requestSearch()`); een resultaat opent met `router.go`, dus in de Bibliotheek of, voor Instellingen, op deze
/// stapel.
struct SearchTab: View {
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var isSearching = false

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        PageScaffold(title: "Zoeken", large: true) {
            if hasQuery {
                SearchTemporaryResults(query: query, onOpen: openResult)
            } else {
                SearchTemporaryTiles()
            }
        }
        .searchable(text: $query, isPresented: $isSearching, prompt: "Zoek in MyBuddy")
        .onChange(of: router.searchRequest) { _, _ in
            isSearching = true
        }
        .profileToolbarItem()
    }

    /// Een resultaat opent met `router.go`; daarna sluit het zoekveld en is het leeg.
    private func openResult(_ entry: SearchEntry) {
        router.go(entry.destination)
        query = ""
        isSearching = false
    }
}

/// De tien bladertegels van `PageCatalog.browse`.
private struct SearchTemporaryTiles: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(PageCatalog.browsePages) { info in
                BrowseTile(title: info.title, symbol: info.symbol, hue: info.hue, destination: info.destination)
            }
        }
    }
}

/// De resultaten van `SearchIndex` voor wat er in het zoekveld staat. Geen treffers: de standaard lege staat van het systeem.
private struct SearchTemporaryResults: View {
    let query: String
    let onOpen: (SearchEntry) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let results = SearchIndex.results(for: query, in: store.data)
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Card {
                ForEach(results) { entry in
                    Button {
                        onOpen(entry)
                    } label: {
                        MediaRowLabel(symbol: entry.symbol, hue: entry.hue, title: entry.title, showsChevron: true)
                    }
                    .buttonStyle(TilePressStyle())
                }
            }
        }
    }
}
