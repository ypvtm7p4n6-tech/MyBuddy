import SwiftUI

// Kleine gedeelde onderdelen van Sparen (spaarpotten en beleggingen): een link naar een pagina voor rijen en tegels met eigen
// inhoud, een drukstatus, en het menu van een kaart.

/// Een rij of tegel met eigen inhoud die naar een pagina leidt. Het gaat via `router.open`: hoort de pagina bij de tab waar je
/// nu bent, dan komt ze op het pad van die tab, anders wisselt de app van tab (K16, zoals `DestinationLink` in `Components.swift`).
/// De inhoud tekent zelf een pijltje (`chevron.right`) als het een rij is. Nodig omdat `NavigationRow` alleen een titel, een waarde en
/// een regel uitleg kent en `DestinationLink` privé is (zie WIRING in het rapport van pakket C).
struct SavingLink<Inner: View>: View {
    let destination: Destination
    private let inner: Inner
    @Environment(Router.self) private var router

    init(_ destination: Destination, @ViewBuilder content: () -> Inner) {
        self.destination = destination
        self.inner = content()
    }

    var body: some View {
        Button {
            router.open(destination)
        } label: {
            inner
        }
        .accessibilityAddTraits(.isLink)
    }
}

/// Knopstijl met een drukstatus voor een tegel die naar een pagina leidt (de inhoud wordt iets doorzichtig zolang je drukt).
struct SavingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Het pijltje aan het eind van een rij die naar een pagina leidt.
struct SavingChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
    }
}

/// Het menu van een kaart ("Kies potten…", "Nieuwe spaarpot"): een pictogramknop met label en een raakdoel van `Theme.minTapTarget`.
struct SavingCardMenu<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Label(title, systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }
}
