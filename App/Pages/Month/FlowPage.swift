import SwiftUI

/// Het Maandoverzicht (`.flow`): "Waar gaat je geld heen" met de keuze Maand, Half jaar of Jaar, de tegel Nog te verdelen en de
/// uitklappers "Cijfers van deze periode" en "Maand voor maand". TIJDELIJK de oude kaart `MonthFlowCard` onder de `MonthBar`
/// (pakket 1, tot pakket 2B de inhoud overneemt). Alleen inhoud: de stapel komt van `TabStack`.
struct FlowPage: View {
    var body: some View {
        PageScaffold(title: "Maandoverzicht") {
            VStack(spacing: Theme.pageSpacing) {
                MonthBar()
                MonthFlowCard()
            }
        }
    }
}
