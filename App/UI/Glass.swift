import SwiftUI

/// Liquid Glass vanaf iOS 26 / macOS 26, met een materiaal als terugval op oudere systemen.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5) }
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
    /// Glazen vlak in een willekeurige vorm.
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// Glazen kaart met de vaste kaartradius.
    func glassCard(radius: CGFloat = Theme.cardRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, interactive: interactive)
    }

    /// Glazen knop (of een bordered knop op oudere systemen).
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// Subtiele binnentegel op een kaart, concentrisch met de kaart.
    func tile(tint: Color? = nil) -> some View {
        background((tint ?? Color.primary).opacity(tint == nil ? 0.07 : 0.16),
                   in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
    }
}
