#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): de lijsten en albumpagina's van Sparen (gevuld, donker, grote tekst,
// breed en leeg), de kaarten voor Home en de bladen, met voorbeelddata, en de drie gemelde gevallen bij Beleggingen
// (`-mybuddy-demo-holding`): een belegging zonder waarde-updates.

/// Maakt een winkel met voorbeelddata (en eventueel een belegging zonder waarde-updates, of juist helemaal leeg) en een router voor
/// de voorbeelden.
@MainActor
private struct SavingPreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    private let content: Content

    init(scenario: DemoHoldingScenario? = nil, isEmpty: Bool = false, @ViewBuilder content: () -> Content) {
        let sampleStore = AppStore(storage: nil)
        if !isEmpty { sampleStore.loadSampleData() }
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

/// De vier kaarten onder elkaar, zoals ze nu nog op Home en bij Sparen staan (pakket 3 ruimt ze op).
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

#Preview("Spaarpotten, donker") {
    SavingPreviewHost { PotsPage() }
        .preferredColorScheme(.dark)
}

#Preview("Spaarpotten, grote tekst") {
    SavingPreviewHost { PotsPage() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Spaarpotten, leeg") {
    SavingPreviewHost(isEmpty: true) { PotsPage() }
}

#Preview("Spaarpot") {
    SavingPreviewHost { FirstPotPreview() }
}

#Preview("Spaarpot, donker") {
    SavingPreviewHost { FirstPotPreview() }
        .preferredColorScheme(.dark)
}

#Preview("Spaarpot, grote tekst") {
    SavingPreviewHost { FirstPotPreview() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Spaarpot, breed") {
    SavingPreviewHost { FirstPotPreview() }
        .frame(width: 720, height: 900)
}

#Preview("Spaarpot, bestaat niet meer") {
    SavingPreviewHost(isEmpty: true) { PotDetailPage(potID: UUID()) }
}

#Preview("Beleggingen") {
    SavingPreviewHost { PortfolioPage() }
}

#Preview("Beleggingen, donker") {
    SavingPreviewHost { PortfolioPage() }
        .preferredColorScheme(.dark)
}

#Preview("Beleggingen, grote tekst") {
    SavingPreviewHost { PortfolioPage() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Beleggingen, leeg") {
    SavingPreviewHost(isEmpty: true) { PortfolioPage() }
}

#Preview("Belegging") {
    SavingPreviewHost { FirstHoldingPreview() }
}

#Preview("Belegging, donker") {
    SavingPreviewHost { FirstHoldingPreview() }
        .preferredColorScheme(.dark)
}

#Preview("Belegging, grote tekst") {
    SavingPreviewHost { FirstHoldingPreview() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Belegging, breed") {
    SavingPreviewHost { FirstHoldingPreview() }
        .frame(width: 720, height: 900)
}

#Preview("Belegging, bestaat niet meer") {
    SavingPreviewHost(isEmpty: true) { HoldingDetailPage(holdingID: UUID()) }
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
