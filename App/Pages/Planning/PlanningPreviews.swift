#if DEBUG
import SwiftUI

// Voorbeelden van de pagina's en kaarten van Plannen met voorbeelddata, voor de Xcode-canvas (alleen in een debug-build).
// De kaarten staan ook in licht, donker en bij grote tekst (`.accessibility3`).

/// Maakt een winkel met voorbeelddata, een router en een inlogstatus voor de previews en geeft de winkel aan de inhoud.
@MainActor
private struct PlanningPreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    @State private var auth = AuthStore()
    private let content: Content

    /// Met `withSampleData: false` is de winkel leeg (de lege staat van een pagina).
    init(withSampleData: Bool = true, @ViewBuilder content: (AppStore) -> Content) {
        let sampleStore = AppStore(storage: nil)
        if withSampleData {
            sampleStore.loadSampleData()
        }
        _store = State(initialValue: sampleStore)
        self.content = content(sampleStore)
    }

    var body: some View {
        NavigationStack {
            content
        }
        .environment(store)
        .environment(router)
        .environment(auth)
    }
}

/// De vijf oude kaarten van het tabblad Plannen onder elkaar (tot de opruiming van pakket 3).
private struct PlanningCardsPreview: View {
    var body: some View {
        PageScaffold(title: "Plannen", large: true) {
            VStack(spacing: Theme.pageSpacing) {
                GoalsSummaryCard()
                BufferSummaryCard()
                AcceleratorsSummaryCard()
                ProjectionSummaryCard()
                PurchaseSummaryCard()
            }
        }
    }
}

#Preview("Kaarten op Plannen, licht") {
    PlanningPreviewHost { _ in PlanningCardsPreview() }
        .preferredColorScheme(.light)
}

#Preview("Kaarten op Plannen, donker") {
    PlanningPreviewHost { _ in PlanningCardsPreview() }
        .preferredColorScheme(.dark)
}

#Preview("Kaarten op Plannen, grote tekst") {
    PlanningPreviewHost { _ in PlanningCardsPreview() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Doelen") {
    PlanningPreviewHost { _ in GoalsPage() }
}

#Preview("Doelen, donker") {
    PlanningPreviewHost { _ in GoalsPage() }
        .preferredColorScheme(.dark)
}

#Preview("Doelen, grote tekst") {
    PlanningPreviewHost { _ in GoalsPage() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Doelen, leeg") {
    PlanningPreviewHost(withSampleData: false) { _ in GoalsPage() }
}

#Preview("Doel") {
    PlanningPreviewHost { store in GoalDetailPage(goalID: store.data.goals.first?.id ?? UUID()) }
}

#Preview("Doel, donker") {
    PlanningPreviewHost { store in GoalDetailPage(goalID: store.data.goals.first?.id ?? UUID()) }
        .preferredColorScheme(.dark)
}

#Preview("Doel, grote tekst") {
    PlanningPreviewHost { store in GoalDetailPage(goalID: store.data.goals.first?.id ?? UUID()) }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Doel bestaat niet meer") {
    PlanningPreviewHost(withSampleData: false) { _ in GoalDetailPage(goalID: UUID()) }
}

#Preview("Spaardoel berekenen") {
    PlanningPreviewHost { _ in SavingsGoalPage() }
}

#Preview("Noodbuffer") {
    PlanningPreviewHost { _ in BufferPage() }
}

#Preview("Versnellers") {
    PlanningPreviewHost { _ in AcceleratorsPage() }
}

#Preview("Toekomstschatting") {
    PlanningPreviewHost { _ in ProjectionPage() }
}

#Preview("Toekomstschatting, donker") {
    PlanningPreviewHost { _ in ProjectionPage() }
        .preferredColorScheme(.dark)
}

#Preview("Aankoopcheck") {
    PlanningPreviewHost { _ in PurchasePage() }
}
#endif
