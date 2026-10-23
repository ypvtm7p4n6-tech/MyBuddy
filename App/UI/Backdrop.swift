import SwiftUI

// Het kleurverloop achter een pagina: de achtergrond van elke pagina in de stijl van Apple Muziek en Apple TV. Een tint
// loopt van bovenaan lineair uit naar het vlakke canvas. De sterkte is berekend zodat de bijschriften leesbaar blijven
// (`TilePalette`, `TilePaletteTests`): hoogstens 55% in donker en 14% in licht. Bij Verhoog contrast of Verlaag transparantie
// is er geen tint, alleen het canvas.

/// Canvas met bovenaan een uitlopende tint. De tint is de bovenkleur van een tegelkleur (`TileHue.top`); op Home volgt hij de
/// zichtbare hero-kaart, op een albumpagina de kleur van de pot, belegging of het doel.
struct BackdropGradient: View {
    let hue: TileHue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(hue: TileHue = .olive) {
        self.hue = hue
    }

    /// De dekking van de tint bovenaan: 0 bij Verhoog contrast of Verlaag transparantie.
    private var strength: Double {
        if reduceTransparency || contrast == .increased { return 0 }
        return colorScheme == .dark ? TilePalette.backdropAlphaDark : TilePalette.backdropAlphaLight
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas
            LinearGradient(colors: [hue.top.opacity(strength), hue.top.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Theme.backdropHeight)
        }
        .animated(by: hue)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
