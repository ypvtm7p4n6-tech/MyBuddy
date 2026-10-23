#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): de vier tabroots met voorbeelddata, het Overzicht zonder gegevens
// (de lege start), in donker en bij grote tekst. Elke tabroot staat in een `TabStack`, zoals in de app.

/// Maakt een winkel (met voorbeelddata of leeg), een router en een inlogstatus voor de voorbeelden.
@MainActor
private struct TabPreviewHost<Content: View>: View {
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

#Preview("Overzicht") {
    TabPreviewHost {
        TabStack(.overview) { OverviewTab() }
    }
}

#Preview("Overzicht, donker") {
    TabPreviewHost {
        TabStack(.overview) { OverviewTab() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Overzicht, grote tekst") {
    TabPreviewHost {
        TabStack(.overview) { OverviewTab() }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Overzicht, lege start") {
    TabPreviewHost(sample: false) {
        TabStack(.overview) { OverviewTab() }
    }
}

#Preview("Maand") {
    TabPreviewHost {
        TabStack(.month) { MonthTab() }
    }
}

#Preview("Maand, donker") {
    TabPreviewHost {
        TabStack(.month) { MonthTab() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Sparen") {
    TabPreviewHost {
        TabStack(.saving) { SavingTab() }
    }
}

#Preview("Plannen") {
    TabPreviewHost {
        TabStack(.planning) { PlanningTab() }
    }
}

#Preview("Plannen, grote tekst") {
    TabPreviewHost {
        TabStack(.planning) { PlanningTab() }
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
