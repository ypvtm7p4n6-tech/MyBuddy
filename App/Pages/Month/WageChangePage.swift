import SwiftUI

// Loon wijzigen: de pagina waar je kiest vanaf welke maand je uurloon of salaris anders is (docs/work/plan2.md par. 4.6). Dit is de
// plaatshouder van de loon-Core (`G2V2`): de pagina zelf bouwt `G3BV3C` met `WageEdit` en `WageText` (App/UI/WageText.swift). Het
// bereikt Loon wijzigen via `Destination.wageChange(maand)` onder Inkomen en Salaris; het is een pagina, geen blad.

struct WageChangePage: View {
    let month: YearMonth

    var body: some View {
        PageScaffold(title: WageText.pageTitle) {
            Text(WageText.fromTitle(month))
                .font(.headline)
                .frame(maxWidth: Theme.readableWidth, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview("Loon wijzigen") {
    NavigationStack {
        WageChangePage(month: YearMonth(year: 2026, month: 12))
    }
}

#Preview("Loon wijzigen, donker") {
    NavigationStack {
        WageChangePage(month: YearMonth(year: 2026, month: 12))
    }
    .preferredColorScheme(.dark)
}
#endif
