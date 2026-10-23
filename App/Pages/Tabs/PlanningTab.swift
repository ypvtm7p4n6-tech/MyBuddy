import SwiftUI

/// Tab 4, Plannen: Doelen, Noodbuffer, Versnellers, Toekomstschatting en Aankoopcheck (par. 2.2 en 2.4 van
/// docs/design/plan.md). Vijf kaarten van pakket D, in de volgorde van de gebruiker (`OrderedBlocks`). De kaart Doelen heeft
/// altijd een rij "Spaardoel berekenen". Alleen inhoud: de `NavigationStack` komt van `TabStack`.
struct PlanningTab: View {
    var body: some View {
        PageScaffold(title: "Plannen", large: true) {
            LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                OrderedBlocks(page: .planning) { id in
                    PlanningBlockContent(id: id)
                }
            }
        }
        .blockOrderToolbar(page: .planning)
        .searchToolbarButton()
    }
}

/// Het blok bij een blok-id van `BlockPage.planning`.
private struct PlanningBlockContent: View {
    let id: String

    var body: some View {
        switch id {
        case "goals": GoalsSummaryCard()
        case "buffer": BufferSummaryCard()
        case "accelerators": AcceleratorsSummaryCard()
        case "projection": ProjectionSummaryCard()
        case "purchase": PurchaseSummaryCard()
        default: EmptyView()
        }
    }
}
