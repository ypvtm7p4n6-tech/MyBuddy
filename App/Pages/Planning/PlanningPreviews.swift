#if DEBUG
import SwiftUI

// Voorbeelden van de pagina's van Plannen met voorbeelddata, voor de Xcode-canvas (alleen in een debug-build): gevuld, donker,
// bij grote tekst (`.accessibility3`) en leeg.

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
