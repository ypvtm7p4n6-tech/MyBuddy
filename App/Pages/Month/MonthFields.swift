import SwiftUI

// Kleine bouwstenen die de pagina's van de Maand-tab delen: Inkomen, Salaris, Uitgaven en Verdelen, en het blad voor een regel.

// MARK: - Dag van de maand kiezen

/// Keuze van een dag van de maand (1...31). Met `defaultText` komt er een optie "standaard" bij (de waarde nil).
struct DayPickerRow: View {
    let title: String
    @Binding var day: Int?
    var defaultText: String? = nil

    var body: some View {
        Picker(title, selection: $day) {
            if let defaultText {
                Text(defaultText).tag(Int?.none)
            }
            ForEach(1...31, id: \.self) { n in
                Text(DayText.ordinal(n)).tag(Int?.some(n))
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: Theme.minTapTarget)
    }
}

// MARK: - Het kerngetal en uitleg

/// Het kerngetal van een pagina op de Maand-tab: een korte titel en het bedrag groot eronder. Eén element voor VoiceOver
/// ("Inkomen in oktober 2026: € 3.000").
struct MonthFigureHero: View {
    let title: String
    let value: Double
    var color: Color = Color.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            BigAmount(value: value, color: color, label: title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Een regel uitleg in een kaart of sectie: klein, in de gedempte tekstkleur, en nooit afgekapt.
struct MonthExplanation: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Een waarschuwing of fout in een kaart of sectie: symbool en tekst in dezelfde kleur (de kleur is nooit het enige teken).
struct MonthWarningLine: View {
    let text: String
    var symbol: String = "exclamationmark.triangle.fill"
    var color: Color = Theme.warning

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
