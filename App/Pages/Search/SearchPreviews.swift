#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): Zoeken met de bladertegels, met resultaten voor "spaar" (pagina's,
// spaarpotten en instellingen), zonder treffers, in donker en bij grote tekst. De wortel staat in een `TabStack`; de inhoud
// onder het zoekveld staat er los, zodat een voorbeeld een zoekopdracht kan meegeven.

/// Maakt een winkel (met voorbeelddata of leeg), een router en een inlogstatus voor de voorbeelden.
@MainActor
private struct SearchPreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    @State private var auth = AuthStore()
    private let content: Content

    init(sample: Bool = true, @ViewBuilder content: () -> Content) {
        let previewStore = AppStore(storage: nil)
        if sample { previewStore.loadSampleData() }
        _store = State(initialValue: previewStore)
        self.content = content()
    }

    var body: some View {
        content
            .environment(store)
            .environment(router)
            .environment(auth)
    }
}

/// De resultaten voor een zoekopdracht op een pagina, zoals onder het zoekveld.
private struct SearchResultsPreview: View {
    let query: String

    var body: some View {
        NavigationStack {
            PageScaffold(title: "Zoeken", large: true) {
                SearchTabContent(query: query, onOpen: { _ in })
            }
        }
    }
}

#Preview("Zoeken, bladeren") {
    SearchPreviewHost {
        TabStack(.search) { SearchTab() }
    }
}

#Preview("Zoeken, bladeren, donker") {
    SearchPreviewHost {
        TabStack(.search) { SearchTab() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Zoeken, bladeren, grote tekst") {
    SearchPreviewHost {
        TabStack(.search) { SearchTab() }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Zoeken, resultaten") {
    SearchPreviewHost {
        SearchResultsPreview(query: "spaar")
    }
}

#Preview("Zoeken, resultaten, donker") {
    SearchPreviewHost {
        SearchResultsPreview(query: "spaar")
    }
    .preferredColorScheme(.dark)
}

#Preview("Zoeken, resultaten, grote tekst") {
    SearchPreviewHost {
        SearchResultsPreview(query: "spaar")
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Zoeken, geen treffers") {
    SearchPreviewHost {
        SearchResultsPreview(query: "zzzzzz")
    }
}

#Preview("Zoeken, lege start") {
    SearchPreviewHost(sample: false) {
        TabStack(.search) { SearchTab() }
    }
}
#endif
