import SwiftUI

// Gedeelde onderdelen van de Plannen-pagina's en -kaarten (pakket D): doelen, noodbuffer, versnellers, toekomstschatting
// en aankoopcheck. Ze zijn alleen bedoeld voor de bestanden van dit pakket en bouwen op het ontwerpsysteem (`Card`,
// `Theme`, `IconButton`): hier staat geen eigen kleur, geen glas en geen vaste lettergrootte.

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

// MARK: - Links in een kaart

/// Drukstatus voor een tegel die naar een pagina leidt: de inhoud wordt iets doorzichtig zolang je drukt. Vervangt
/// `.buttonStyle(.plain)`, dat geen reactie geeft.
struct PlanningPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Een tegel in een kaart die naar een pagina leidt (bijvoorbeeld een doel of de rij "Spaardoel berekenen"): de inhoud links
/// en rechts een pijltje. Hij opent met `router.open`: hoort de pagina bij de tab waar je bent, dan komt ze op het pad van die
/// tab, anders wisselt de app van tab (K16). Voor VoiceOver is het een link.
struct PlanningLinkTile<Content: View>: View {
    let destination: Destination
    private let content: Content
    @Environment(Router.self) private var router

    init(destination: Destination, @ViewBuilder content: () -> Content) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        Button {
            router.open(destination)
        } label: {
            HStack(spacing: 8) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
            .tile()
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        }
        .buttonStyle(PlanningPressStyle())
        .accessibilityAddTraits(.isLink)
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
