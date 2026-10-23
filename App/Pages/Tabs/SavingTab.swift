import SwiftUI

/// Tab 3, Sparen: Spaarpotten en Beleggingen (par. 2.2 en 2.4 van docs/design/plan.md). Twee kaarten van pakket C, in de volgorde
/// van de gebruiker (`OrderedBlocks`). Met twee blokken valt er niets te ordenen, dus er is geen menu "Volgorde aanpassen".
/// Alleen inhoud: de `NavigationStack` komt van `TabStack`.
struct SavingTab: View {
    var body: some View {
        PageScaffold(title: "Sparen", large: true) {
            LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                OrderedBlocks(page: .saving) { id in
                    SavingBlockContent(id: id)
                }
            }
        }
        .searchToolbarButton()
    }
}

/// Het blok bij een blok-id van `BlockPage.saving`.
private struct SavingBlockContent: View {
    let id: String

    var body: some View {
        switch id {
        case "pots": PotsSummaryCard()
        case "portfolio": PortfolioSummaryCard()
        default: EmptyView()
        }
    }
}
