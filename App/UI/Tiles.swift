import SwiftUI

// De tegels van ontwerp 2 (par. 2.4 van docs/design2/plan.md): het gekleurde vlak (`GradientSurface`), het artwork met een
// symbool (`ArtworkTile`), de tegel op een plank (`PosterCard`), de tekst- of brede kaart (`ShelfCard`) en de bladertegel van
// Zoeken (`BrowseTile`). Elke tegel is een donker kleurverloop met witte tekst (`Theme.onTile`, 6,4:1); de kleur draagt nooit
// alleen de betekenis: titel, symbool en cijfers staan er altijd bij.

// MARK: - Het gekleurde vlak

/// Een vlak met het tegelverloop van een tint, witte tekst en een afgeronde hoek. Zet `\.tileHue` voor de inhoud (een pil in de
/// tegel leest die). Bij Verhoog contrast krijgt het vlak de donkerdere kleuren en een rand van 1 punt.
struct GradientSurface<Content: View>: View {
    let hue: TileHue
    let radius: CGFloat
    private let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    init(hue: TileHue, radius: CGFloat = Theme.tileRadius, @ViewBuilder content: () -> Content) {
        self.hue = hue
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .foregroundStyle(Theme.onTile)
            .environment(\.tileHue, hue)
            .background(hue.gradient, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                }
            }
    }
}

// MARK: - Drukstatus

/// Drukstatus voor een tegel die een link of knop is (`.buttonStyle(.plain)` heeft er geen): iets doorzichtig en iets kleiner
/// zolang je drukt; bij Verlaag beweging alleen doorzichtig.
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TilePressBody(configuration: configuration)
    }
}

private struct TilePressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .opacity(pressed ? 0.7 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animated(by: pressed, quick: true)
    }
}

// MARK: - Artwork

/// De drie maten van het artwork: een lijstrij (44 punten), een tegel op een plank (vult de breedte) en de kop van een
/// albumpagina (220 of 200 punten).
enum ArtworkSize: Equatable {
    case row, fill, header
}

/// Een gekleurd vlak met een symbool (nooit `.system(size:)`: het symbool is `resizable` en `scaledToFit`). `fill` is vierkant
/// en vult de breedte, met het symbool linksboven en een voortgangsbalk onderin; `header` heeft het symbool in het midden.
/// Het artwork is versiering: voor VoiceOver is het verborgen, de titel draagt de betekenis.
struct ArtworkTile: View {
    let symbol: String
    let hue: TileHue
    let size: ArtworkSize
    let progress: Double?
    let progressLabel: String?
    @ScaledMetric(relativeTo: .body) private var rowBase: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var glyphBase: CGFloat = 26
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(symbol: String, hue: TileHue, size: ArtworkSize = .fill, progress: Double? = nil, progressLabel: String? = nil) {
        self.symbol = symbol
        self.hue = hue
        self.size = size
        self.progress = progress
        self.progressLabel = progressLabel
    }

    var body: some View {
        Group {
            switch size {
            case .row:
                rowTile
            case .fill:
                fillTile
            case .header:
                headerTile
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Maten

    /// De zijde van het artwork in een rij: 44 punten, schaalt met Dynamic Type mee tot 1,5 keer.
    private var rowSide: CGFloat { min(rowBase, 66) }
    /// De zijde van het kopartwork: 220 punten op een iPhone, 200 op iPad en Mac.
    private var headerSide: CGFloat { sizeClass == .compact ? 220 : 200 }
    private var glyphSide: CGFloat { min(glyphBase, 39) }

    // MARK: Varianten

    private var rowTile: some View {
        let side = rowSide
        return GradientSurface(hue: hue, radius: Theme.rowArtworkRadius) {
            symbolImage
                .padding(side * 0.25)
                .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
    }

    private var fillTile: some View {
        GradientSurface(hue: hue, radius: Theme.posterRadius) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    symbolImage
                        .frame(width: glyphSide, height: glyphSide)
                        .padding(12)
                }
                .overlay(alignment: .bottom) {
                    progressBar
                }
        }
    }

    private var headerTile: some View {
        let side = headerSide
        return GradientSurface(hue: hue, radius: Theme.headerArtworkRadius) {
            symbolImage
                .padding(side * 0.3)
                .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
    }

    private var symbolImage: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress {
            ProgressMeter(value: progress, tint: Theme.onTile, style: .bar(height: 6),
                          label: progressLabel ?? "Voortgang", valueText: Fmt.percent(progress, digits: 0))
                .padding(12)
        }
    }
}

// MARK: - Tegel op een plank

/// Een tegel op een plank: het artwork, daaronder de titel (hoogstens twee regels), een ondertitel en een waarde. De breedte
/// komt van `Shelf`. Met `destination` is het een link, met `action` een knop, met geen van beide staat hij vast. Voor
/// VoiceOver is het een element met het label "titel, ondertitel, waarde".
struct PosterCard: View {
    let symbol: String
    let hue: TileHue
    let title: String
    let subtitle: String?
    let value: String?
    let progress: Double?
    let progressLabel: String?
    let destination: Destination?
    let showsCurrentMonth: Bool
    let action: (() -> Void)?

    init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, value: String? = nil,
         progress: Double? = nil, progressLabel: String? = nil, destination: Destination? = nil,
         showsCurrentMonth: Bool = false, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.hue = hue
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.progress = progress
        self.progressLabel = progressLabel
        self.destination = destination
        self.showsCurrentMonth = showsCurrentMonth
        self.action = action
    }

    var body: some View {
        if let destination {
            DestinationLink(destination: destination, showsCurrentMonth: showsCurrentMonth) { _ in
                tile
            }
            .buttonStyle(TilePressStyle())
        } else if let action {
            Button(action: action) {
                tile
            }
            .buttonStyle(TilePressStyle())
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkTile(symbol: symbol, hue: hue, size: .fill, progress: progress, progressLabel: progressLabel)
            texts
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if let value {
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    /// "titel, ondertitel, waarde", met de voortgang erachter als die er is.
    private var spokenLabel: String {
        var parts: [String] = [title]
        if let subtitle { parts.append(subtitle) }
        if let value { parts.append(value) }
        if let progress {
            let text = progressLabel ?? "Voortgang"
            parts.append(text + " " + Fmt.percent(progress, digits: 0))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Tekst- of brede kaart

/// Een kaart op een plank met eigen inhoud: een brede kaart voor Komende dagen, de samenvattingstegel van Beleggingen of een
/// lege staat. Zonder `hue` is het een gewone kaart (`Theme.card`), met een tint een tegel met witte tekst. Met `destination`
/// is de hele kaart een link.
struct ShelfCard<Content: View>: View {
    let hue: TileHue?
    let destination: Destination?
    let showsCurrentMonth: Bool
    private let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    init(hue: TileHue? = nil, destination: Destination? = nil, showsCurrentMonth: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.hue = hue
        self.destination = destination
        self.showsCurrentMonth = showsCurrentMonth
        self.content = content()
    }

    var body: some View {
        if let destination {
            DestinationLink(destination: destination, showsCurrentMonth: showsCurrentMonth) { _ in
                surface
            }
            .buttonStyle(TilePressStyle())
        } else {
            surface
        }
    }

    @ViewBuilder
    private var surface: some View {
        if let hue {
            GradientSurface(hue: hue, radius: Theme.posterRadius) {
                padded
            }
        } else {
            let shape = RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous)
            padded
                .background(Theme.card, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                    }
                }
        }
    }

    private var padded: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous))
    }
}

// MARK: - Bladertegel

/// Een bladertegel van Zoeken: minimaal 96 punten hoog, de titel linksonder en een decoratief symbool rechtsboven. Een tik
/// opent de pagina. De kleur is nooit het enige teken: titel en symbool staan erbij.
struct BrowseTile: View {
    let title: String
    let symbol: String
    let hue: TileHue
    let destination: Destination
    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = 96

    init(title: String, symbol: String, hue: TileHue, destination: Destination) {
        self.title = title
        self.symbol = symbol
        self.hue = hue
        self.destination = destination
    }

    var body: some View {
        DestinationLink(destination: destination) { _ in
            tile
        }
        .buttonStyle(TilePressStyle())
    }

    private var tile: some View {
        GradientSurface(hue: hue, radius: Theme.posterRadius) {
            ZStack {
                Color.clear
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.onTileSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(minHeight: minHeight)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isLink)
    }
}
