import SwiftUI

// De pillen (capsule-knoppen) van ontwerp 2: de acties op een hero-kaart en op een albumpagina. Vlak, zonder glas (B15): glas
// komt alleen van het systeem. Hoogstens een `.prominent` pil per scherm.

/// De drie uiterlijken van een pil: `prominent` (gevuld, de ene hoofdactie), `secondary` (een vlak met accenttekst) en `onTile`
/// (een wit vlak met tekst in de kleur van de tegel waar de pil op staat, voor een pil op een hero-kaart).
enum PillStyle {
    case prominent, secondary, onTile
}

/// Het uiterlijk van een pil: capsule, minstens `Theme.minTapTarget` hoog, `.subheadline.weight(.semibold)`, de tekst wrapt.
private struct PillLabel: View {
    let title: String
    let symbol: String?
    let style: PillStyle
    let isDestructive: Bool
    @Environment(\.tileHue) private var tileHue

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(title)
                .multilineTextAlignment(.center)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: Theme.minTapTarget)
        .background(fill, in: Capsule())
        .contentShape(Capsule())
    }

    private var textColor: Color {
        if isDestructive { return Theme.negative }
        switch style {
        case .prominent: return Theme.onAccent
        case .secondary: return Theme.accent
        case .onTile: return tileHue.top
        }
    }

    private var fill: Color {
        switch style {
        case .prominent: return Theme.accentFill
        case .secondary: return Theme.tileFill
        case .onTile: return Theme.onTile
        }
    }
}

/// Een pil die iets doet. Een destructieve pil heeft tekst in `Theme.negative` en is nooit `.prominent`.
struct PillButton: View {
    let title: String
    let symbol: String?
    let style: PillStyle
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, symbol: String? = nil, style: PillStyle = .secondary, role: ButtonRole? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            PillLabel(title: title, symbol: symbol, style: style, isDestructive: role == .destructive)
        }
        .buttonStyle(TilePressStyle())
        .help(title)
    }
}

/// Een pil die naar een pagina leidt. Met `showsCurrentMonth` zet een tik eerst de maandpagina's op de huidige maand.
struct PillLink: View {
    let title: String
    let symbol: String?
    let style: PillStyle
    let destination: Destination
    let showsCurrentMonth: Bool

    init(_ title: String, symbol: String? = nil, style: PillStyle = .secondary, destination: Destination,
         showsCurrentMonth: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.destination = destination
        self.showsCurrentMonth = showsCurrentMonth
    }

    var body: some View {
        DestinationLink(destination: destination, showsCurrentMonth: showsCurrentMonth) { _ in
            PillLabel(title: title, symbol: symbol, style: style, isDestructive: false)
        }
        .buttonStyle(TilePressStyle())
        .help(title)
    }
}

/// Pillen naast elkaar als ze passen en anders onder elkaar (grote tekst, smal scherm). Links uitgelijnd, of gecentreerd
/// (`alignment: .center`, de kop van een albumpagina op een iPhone).
struct PillRow<Content: View>: View {
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    private let content: Content

    init(spacing: CGFloat = 8, alignment: HorizontalAlignment = .leading, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: alignment, spacing: spacing) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}
