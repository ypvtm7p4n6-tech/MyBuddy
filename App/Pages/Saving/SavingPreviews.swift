#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): de pagina's, kaarten en bladen van Sparen met voorbeelddata, en de
// drie gemelde gevallen bij Beleggingen (`-mybuddy-demo-holding`): een belegging zonder waarde-updates.

/// Maakt een winkel met voorbeelddata (en eventueel een belegging zonder waarde-updates) en een router voor de voorbeelden.
@MainActor
private struct SavingPreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    private let content: Content

    init(scenario: DemoHoldingScenario? = nil, @ViewBuilder content: () -> Content) {
        let sampleStore = AppStore(storage: nil)
        sampleStore.loadSampleData()
        if let scenario { scenario.apply(to: sampleStore) }
        _store = State(initialValue: sampleStore)
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
        }
        .environment(store)
        .environment(router)
    }
}

/// De pagina van de eerste spaarpot uit de voorbeelddata.
private struct FirstPotPreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let pot = store.data.pots.first {
            PotDetailPage(potID: pot.id)
        }
    }
}

/// De pagina van de eerste belegging uit de voorbeelddata.
private struct FirstHoldingPreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let holding = store.data.holdings.first {
            HoldingDetailPage(holdingID: holding.id)
        }
    }
}

/// De vier kaarten onder elkaar, zoals ze op het Overzicht en bij Sparen staan.
private struct SavingCardsPreview: View {
    var body: some View {
        PageScaffold(title: "Sparen", large: true) {
            VStack(spacing: Theme.pageSpacing) {
                HomePotsCard()
                HomeHoldingsCard()
                PotsSummaryCard()
                PortfolioSummaryCard()
            }
        }
    }
}

#Preview("Spaarpotten") {
    SavingPreviewHost { PotsPage() }
}

#Preview("Spaarpot") {
    SavingPreviewHost { FirstPotPreview() }
}

#Preview("Beleggingen") {
    SavingPreviewHost { PortfolioPage() }
}

#Preview("Belegging") {
    SavingPreviewHost { FirstHoldingPreview() }
}

#Preview("Kaarten") {
    SavingPreviewHost { SavingCardsPreview() }
}

#Preview("Kaarten, donker") {
    SavingPreviewHost { SavingCardsPreview() }
        .preferredColorScheme(.dark)
}

#Preview("Kaarten, grote tekst") {
    SavingPreviewHost { SavingCardsPreview() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Beleggingen, alleen ingelegd") {
    SavingPreviewHost(scenario: .onlyInvested) { PortfolioPage() }
}

#Preview("Belegging, alleen ingelegd") {
    SavingPreviewHost(scenario: .onlyInvested) { FirstHoldingPreview() }
}

#Preview("Beleggingen, ticker zonder aantal") {
    SavingPreviewHost(scenario: .tickerNoUnits) { PortfolioPage() }
}

#Preview("Beleggingen, gevolgd zonder koers") {
    SavingPreviewHost(scenario: .trackedOffline) { PortfolioPage() }
}

#Preview("Kaarten, alleen ingelegd") {
    SavingPreviewHost(scenario: .onlyInvested) { SavingCardsPreview() }
}

#Preview("Belegging toevoegen") {
    SavingPreviewHost { HoldingEditSheet(holding: nil) }
}

#Preview("Spaarpot maken") {
    SavingPreviewHost { PotEditSheet(pot: nil) }
}

#Preview("Potten kiezen") {
    SavingPreviewHost { FavoritePotsSheet() }
}

#Preview("Beleggingen kiezen") {
    SavingPreviewHost { FavoriteHoldingsSheet() }
}
#endif
