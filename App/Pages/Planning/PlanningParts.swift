import SwiftUI

// Gedeelde onderdelen van de Plannen-pagina's: doelen, noodbuffer, versnellers, toekomstschatting en aankoopcheck. Ze bouwen op
// het ontwerpsysteem (`Card`, `Theme`, `IconButton`): hier staat geen eigen kleur, geen glas en geen vaste lettergrootte.

// MARK: - Taal

enum PlanningText {
    /// Het werkwoord voor een aanraking: "Tik" op een touchscreen, "Klik" met de muis op de Mac (WRT-1).
    static var tap: String {
        #if os(macOS)
        return "Klik"
        #else
        return "Tik"
        #endif
    }
}

// MARK: - Uitleg

/// Een regel uitleg onder een veld of bedrag: voetnootgrootte in de tekstkleur voor bijschriften. De tekst wrapt en wordt
/// nooit afgekapt.
struct PlanningFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Drukstatus

/// Drukstatus voor een tegel of rij die naar een pagina leidt: de inhoud wordt iets doorzichtig zolang je drukt. Vervangt
/// `.buttonStyle(.plain)`, dat geen reactie geeft.
struct PlanningPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Bevestiging die blijft staan

/// Een bevestiging in een kaart ("Toegepast: ...") die blijft staan tot je hem zelf sluit. Een melding die vanzelf verdwijnt
/// is niet toegankelijk (ACC-8): wie VoiceOver gebruikt of traag leest, zou hem missen.
struct PlanningConfirmation: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.positive)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton("Sluit melding", symbol: "xmark", action: onClose)
        }
        .padding(.leading, 12)
        .padding(.vertical, 2)
        .tile(tint: Theme.positive)
    }
}
