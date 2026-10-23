import SwiftUI

/// Tab 2, Maand: door de tijd, per maand (par. 2.2 en 2.4 van docs/design/plan.md). De kern is de `MonthBar` (stapt per maand,
/// `focusMonth`). Daaronder de blokken in de volgorde van de gebruiker: "Waar gaat je geld heen" (met de keuze Maand, Half jaar,
/// Jaar) en vijf kaarten met het kerncijfer die naar Inkomen, Uitgaven, Verdelen, Bankrekening en Dag voor dag leiden. Alleen
/// inhoud: de `NavigationStack` komt van `TabStack`.
struct MonthTab: View {
    var body: some View {
        PageScaffold(title: "Maand", large: true) {
            VStack(spacing: Theme.pageSpacing) {
                MonthBar()
                MonthBlocks()
            }
        }
        .blockOrderToolbar(page: .month)
        .searchToolbarButton()
    }
}

/// De blokken van de Maand-tab in de volgorde van de gebruiker (`OrderedBlocks` met de id's uit par. 2.7).
private struct MonthBlocks: View {
    var body: some View {
        LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
            OrderedBlocks(page: .month) { id in
                MonthBlockContent(id: id)
            }
        }
    }
}

/// Het blok bij een blok-id van `BlockPage.month`.
private struct MonthBlockContent: View {
    let id: String

    var body: some View {
        switch id {
        case "flow": MonthFlowCard()
        case "income": MonthIncomeCard()
        case "expenses": MonthExpensesCard()
        case "distribute": MonthDistributeCard()
        case "bank": MonthBankCard()
        case "days": MonthDaysCard()
        default: EmptyView()
        }
    }
}
