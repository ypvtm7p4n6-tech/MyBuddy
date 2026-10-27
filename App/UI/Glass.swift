import SwiftUI

// Glas in de eigen code is er alleen voor zwevende bediening boven scrollende inhoud (`glassSurface`); de inhoud zelf is
// geen glas (K5). Tabbalk, werkbalk, bladen en menu's krijgen hun glas van het systeem.

/// Liquid Glass vanaf iOS 26 / macOS 26, met een materiaal als terugval op oudere systemen. Bij "Verlaag transparantie" is
/// het vlak dekkend (`Theme.card` met een rand).
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.card, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// Glazen vlak in een willekeurige vorm: alleen voor zwevende bediening boven scrollende inhoud.
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// Subtiele binnentegel op een kaart, concentrisch met de kaart (`Theme.tileRadius`). Zonder kleur is het `Theme.tileFill`
    /// (de voorgrondkleur op 6%, 10% bij "Verhoog contrast").
    func tile(tint: Color? = nil) -> some View {
        background(tint?.opacity(0.16) ?? Theme.tileFill,
                   in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
    }
}
