#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): de Bibliotheek, het Maandoverzicht en Hulpmiddelen met
// voorbeelddata, in donker, bij grote tekst en zonder gegevens (de lege start). De Bibliotheek staat in een `TabStack`, zoals in
// de app; de andere twee zijn pagina's en staan in een `NavigationStack`.

/// Maakt een winkel (met voorbeelddata of leeg), een router en een inlogstatus voor de voorbeelden.
@MainActor
private struct LibraryPreviewHost<Content: View>: View {
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

// MARK: - Bibliotheek

#Preview("Bibliotheek") {
    LibraryPreviewHost {
        TabStack(.library) { LibraryTab() }
    }
}

#Preview("Bibliotheek, donker") {
    LibraryPreviewHost {
        TabStack(.library) { LibraryTab() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Bibliotheek, grote tekst") {
    LibraryPreviewHost {
        TabStack(.library) { LibraryTab() }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Bibliotheek, lege start") {
    LibraryPreviewHost(sample: false) {
        TabStack(.library) { LibraryTab() }
    }
}

// MARK: - Maandoverzicht

#Preview("Maandoverzicht") {
    LibraryPreviewHost {
        NavigationStack { FlowPage() }
    }
}

#Preview("Maandoverzicht, donker") {
    LibraryPreviewHost {
        NavigationStack { FlowPage() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Maandoverzicht, grote tekst") {
    LibraryPreviewHost {
        NavigationStack { FlowPage() }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Maandoverzicht, lege start") {
    LibraryPreviewHost(sample: false) {
        NavigationStack { FlowPage() }
    }
}

// MARK: - Hulpmiddelen

#Preview("Hulpmiddelen") {
    LibraryPreviewHost {
        NavigationStack { ToolsPage() }
    }
}

#Preview("Hulpmiddelen, donker") {
    LibraryPreviewHost {
        NavigationStack { ToolsPage() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Hulpmiddelen, grote tekst") {
    LibraryPreviewHost {
        NavigationStack { ToolsPage() }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Hulpmiddelen, lege start") {
    LibraryPreviewHost(sample: false) {
        NavigationStack { ToolsPage() }
    }
}
#endif
