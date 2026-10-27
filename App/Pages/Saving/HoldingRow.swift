import SwiftUI

// Een belegging in de lijst Beleggingen (`PortfolioPage` in Pages/PortfolioPages.swift): een rij met een tegel in de kleur van de soort.

/// Een belegging in de lijst: een tegel in de kleur van de soort, de naam, de waarde, en eronder de ticker met de koers of de soort,
/// de winst als percentage (of "Geschat") en de inleg als die een percentage is. Een tik opent de albumpagina van de belegging.
/// Swipe en contextmenu geven Bewerken en Verwijderen.
struct HoldingRow: View {
    let holding: Holding
    let onEdit: () -> Void
    @Environment(AppStore.self) private var store
    @State private var confirmDelete = false

    init(holding: Holding, onEdit: @escaping () -> Void) {
        self.holding = holding
        self.onEdit = onEdit
    }

    var body: some View {
        let state = store.data.holdingStateNow(holding, current: store.now, today: store.today)
        let figures = HoldingFigures(state)
        MediaRow(symbol: holding.kind.symbol, hue: Theme.hue(holding.kind.colorIndex), title: holding.name,
                 subtitle: subtitle(figures), value: Fmt.euro(figures.value), destination: .holding(holding.id))
            .rowActions(edit: { onEdit() }, delete: { confirmDelete = true })
            .modifier(HoldingDeleteDialog(holding: holding, isPresented: $confirmDelete))
    }

    /// "VWRL · € 112,40 · +3,1%", met de inleg op een tweede regel als die een percentage van je inkomen is (wat het deze maand is,
    /// zoals bij een spaarpot).
    private func subtitle(_ figures: HoldingFigures) -> String {
        var text = SavingAlbumText.holdingListSubtitle(base: baseLine, isEstimated: figures.isEstimated,
                                                       gainFraction: figures.gainFraction)
        if let line = ContributionInfo.listLine(store.data, id: holding.id, month: store.now) {
            text += "\n" + line
        }
        return text
    }

    private var baseLine: String {
        if holding.hasTicker, let ticker = holding.ticker {
            // De koers is een eenheidsprijs: met centen (een koers van 0,52 is geen "€ 1").
            if let price = holding.lastPrice { return "\(ticker) · \(Fmt.euroExact(price))" }
            return ticker
        }
        return holding.kind.title
    }
}
