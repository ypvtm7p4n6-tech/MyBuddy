import SwiftUI

// Kleine bouwstenen die de vier tabroots delen (Overzicht, Maand, Sparen, Plannen). Een tabroot is alleen inhoud: de
// `NavigationStack` komt van `TabStack`. Alle cijfers komen uit de bronnen die ook de pagina's gebruiken (`MonthBoard`,
// `periodSummary`, `netWorth`, `expenseOverview`, `LedgerBook`); hier wordt niets zelf uitgerekend.

/// Een regel uitleg in een kaart: klein, in de gedempte tekstkleur en nooit afgekapt.
struct TabNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Een waarschuwing in een kaart: symbool en tekst in dezelfde kleur, zodat de kleur nooit het enige teken is.
struct TabWarning: View {
    let text: String
    var color: Color = Theme.negative

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Drukstatus voor een rij die een link is: de rij wordt iets doorzichtig zolang je drukt.
struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Een `AmountRow` die naar een pagina leidt, met een pijltje. `router.open` kiest zelf: hoort de pagina bij een andere tab, dan
/// wisselt de rij van tab (`go`), anders komt de pagina op het pad van deze tab.
struct TabAmountLink: View {
    let title: String
    let value: String
    let symbol: String
    let destination: Destination
    var color: Color = Color.primary
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.open(destination)
        } label: {
            HStack(spacing: 8) {
                AmountRow(title: title, value: value, color: color, symbol: symbol)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .accessibilityAddTraits(.isLink)
    }
}
