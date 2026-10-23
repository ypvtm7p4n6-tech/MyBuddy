import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Het ontwerpsysteem op een plek: kleuren, maten en lettertokens. Dit is het enige bestand met `Color(hex:)`.
// De waarden komen uit docs/design/plan.md par. 4.1 en 4.2 en uit docs/design2/plan.md par. 2.1 (de acht tegelkleuren, het
// canvas en de bijschriftkleur staan in `TilePalette`, Foundation-only en getest); het contrast is berekend tegen de kaartkleur
// (licht wit, donker #1C1C1E) en tegen het canvas. Elke hoog-contrastvariant is strikt sterker dan de gewone kleur
// (donkerder in licht, lichter in donker).

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Kleur die meebeweegt met lichte en donkere modus.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        }))
        #endif
    }

    /// Kleur die meebeweegt met licht, donker en "Verhoog contrast" (aparte waarden voor licht en donker).
    init(light: Color, dark: Color, lightContrast: Color, darkContrast: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let isHigh = trait.accessibilityContrast == .high
            if isDark { return isHigh ? UIColor(darkContrast) : UIColor(dark) }
            return isHigh ? UIColor(lightContrast) : UIColor(light)
        })
        #else
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let names: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
            let match = appearance.bestMatch(from: names)
            if match == .accessibilityHighContrastDarkAqua { return NSColor(darkContrast) }
            if match == .accessibilityHighContrastAqua { return NSColor(lightContrast) }
            if match == .darkAqua { return NSColor(dark) }
            return NSColor(light)
        }))
        #endif
    }
}

// MARK: - Domeinen

/// Een onderdeel van de app met een eigen kleur en symbool. De kleur is alleen voor het pictogram (in een `SymbolBadge`) en
/// het kaartsymbool, nooit voor tekst, en draagt nooit alleen de betekenis: titel en symbool staan er altijd bij.
enum AppDomain: String, CaseIterable, Identifiable {
    case overview, money, saving, investing, goals, tools, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Home"
        case .money: return "Inkomen en uitgaven"
        case .saving: return "Sparen"
        case .investing: return "Beleggen"
        case .goals: return "Doelen"
        case .tools: return "Hulpmiddelen"
        case .settings: return "Instellingen"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "chart.pie"
        case .money: return "calendar"
        case .saving: return "tray.full"
        case .investing: return "chart.line.uptrend.xyaxis"
        case .goals: return "flag.checkered"
        case .tools: return "calendar.badge.clock"
        case .settings: return "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .overview: return Color(light: Color(hex: 0x3F5220), dark: Color(hex: 0xA9C06B))
        case .money: return Color(light: Color(hex: 0x9A4B26), dark: Color(hex: 0xE39A74))
        case .saving: return Color(light: Color(hex: 0x2A6F66), dark: Color(hex: 0x6FC2B4))
        case .investing: return Color(light: Color(hex: 0x3F5F8C), dark: Color(hex: 0x8FB0E0))
        case .goals: return Color(light: Color(hex: 0x8A6A00), dark: Color(hex: 0xE3C25A))
        case .tools: return Color(light: Color(hex: 0x74476A), dark: Color(hex: 0xCF9BC3))
        case .settings: return Color(light: Color(hex: 0x5B6150), dark: Color(hex: 0xB3BAA3))
        }
    }
}

extension AppDomain {
    /// De tegelkleur van dit onderdeel (tabel 2.1 van docs/design2/plan.md): olijf, terracotta, saliegroenblauw, leiblauw,
    /// mosterd, pruim en saliegrijs.
    var hue: TileHue {
        switch self {
        case .overview: return .olive
        case .money: return .terracotta
        case .saving: return .teal
        case .investing: return .slate
        case .goals: return .mustard
        case .tools: return .plum
        case .settings: return .sage
        }
    }
}

// MARK: - Tegelkleuren

extension TileHue {
    /// De bovenkleur van het verloop. Niet afhankelijk van licht of donker (witte tekst staat er altijd op); bij Verhoog
    /// contrast de donkerdere variant.
    var top: Color {
        let colors = TilePalette.colors(self)
        return Color(light: Color(hex: colors.top), dark: Color(hex: colors.top),
                     lightContrast: Color(hex: colors.topHC), darkContrast: Color(hex: colors.topHC))
    }

    /// De onderkleur van het verloop (zie `top`).
    var bottom: Color {
        let colors = TilePalette.colors(self)
        return Color(light: Color(hex: colors.bottom), dark: Color(hex: colors.bottom),
                     lightContrast: Color(hex: colors.bottomHC), darkContrast: Color(hex: colors.bottomHC))
    }

    /// Het tegelverloop: van linksboven naar rechtsonder, zonder schaduw of glans (elke overlay verlaagt het contrast).
    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct BackdropHueKey: EnvironmentKey {
    static let defaultValue: TileHue = .olive
}

private struct TileHueKey: EnvironmentKey {
    static let defaultValue: TileHue = .olive
}

extension EnvironmentValues {
    /// De tint van het kleurverloop achter de pagina (`BackdropGradient`). `DestinationView` zet hem per pagina, een
    /// albumpagina zet hem op de kleur van de pot, belegging of het doel.
    var backdropHue: TileHue {
        get { self[BackdropHueKey.self] }
        set { self[BackdropHueKey.self] = newValue }
    }

    /// De tint van de tegel waar je in zit: `GradientSurface` zet hem, `PillStyle.onTile` leest hem.
    var tileHue: TileHue {
        get { self[TileHueKey.self] }
        set { self[TileHueKey.self] = newValue }
    }
}

// MARK: - Thema

/// Eén plek voor vormen en kleuren, zodat alle schermen dezelfde taal spreken.
enum Theme {
    // MARK: Oppervlakken

    /// De achtergrond van een pagina: een vlak, een lichte olijftint in licht en bijna zwart olijfgroen in donker.
    static let canvas = Color(light: Color(hex: TilePalette.canvasLight), dark: Color(hex: TilePalette.canvasDark))

    /// Een kaart of lijstrij: de systeemkleur voor gegroepeerde inhoud (op macOS de kleur van een bedieningsvlak).
    #if os(macOS)
    static let card = Color(nsColor: .controlBackgroundColor)
    #else
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    #endif

    /// Een tegel binnen een kaart: de voorgrondkleur op 6% (10% bij "Verhoog contrast").
    static let tileFill = Color(light: Color(hex: 0x000000, opacity: 0.06), dark: Color(hex: 0xFFFFFF, opacity: 0.06),
                                lightContrast: Color(hex: 0x000000, opacity: 0.10), darkContrast: Color(hex: 0xFFFFFF, opacity: 0.10))

    // MARK: Tekst en accent

    /// Uitleg en bijschriften. Vervangt `.secondary` (dat te weinig contrast gaf).
    static let textSecondary = Color(light: Color(hex: TilePalette.textSecondaryLight), dark: Color(hex: TilePalette.textSecondaryDark),
                                     lightContrast: Color(hex: TilePalette.textSecondaryLightHC),
                                     darkContrast: Color(hex: TilePalette.textSecondaryDarkHC))
    /// Tint, knoptekst en interactieve pictogrammen.
    static let accent = Color(light: Color(hex: 0x3F5220), dark: Color(hex: 0xA9C06B),
                              lightContrast: Color(hex: 0x2C3A14), darkContrast: Color(hex: 0xC4D68C))
    /// De vulling van een gevulde knop; de tekst erop is `onAccent`.
    static let accentFill = Color(light: Color(hex: 0x3F5220), dark: Color(hex: 0xA9C06B))
    static let onAccent = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x10140B))

    // MARK: Tekst op een tegel of hero-kaart (het tegelverloop is altijd donker, dus de tekst altijd wit)

    /// Tekst en symbolen op een tegel: wit (minimaal 6,37:1 op de bovenkleur, 9,5:1 bij Verhoog contrast).
    static let onTile = Color(hex: TilePalette.onTile)
    /// Bijschriften op een tegel: wit op 82% (minimaal 4,88:1), bij Verhoog contrast op 92%.
    static let onTileSecondary = Color(light: Color(hex: TilePalette.onTile, opacity: TilePalette.onTileSecondaryAlpha),
                                       dark: Color(hex: TilePalette.onTile, opacity: TilePalette.onTileSecondaryAlpha),
                                       lightContrast: Color(hex: TilePalette.onTile, opacity: TilePalette.onTileSecondaryAlphaHC),
                                       darkContrast: Color(hex: TilePalette.onTile, opacity: TilePalette.onTileSecondaryAlphaHC))
    /// Het donkere paneel voor een grafiek in een hero-kaart of tegel (zwart op 22%, `heroPanel()`).
    static let heroPanelFill = Color(hex: 0x000000, opacity: 0.22)

    // MARK: Betekenis (altijd met een teken, symbool of woord erbij)

    static let positive = Color(light: Color(hex: 0x2F5E1A), dark: Color(hex: 0xB7D96F),
                                lightContrast: Color(hex: 0x1F4510), darkContrast: Color(hex: 0xCBE88D))
    static let negative = Color(light: Color(hex: 0xA12F18), dark: Color(hex: 0xF29A7C),
                                lightContrast: Color(hex: 0x7E2210), darkContrast: Color(hex: 0xFFB8A0))
    static let warning = Color(light: Color(hex: 0x7A5800), dark: Color(hex: 0xE3C25A),
                               lightContrast: Color(hex: 0x5C4200), darkContrast: Color(hex: 0xF0D885))

    // MARK: Grafiekkleuren (vlakken, tegen de kaart minstens 3:1; altijd met een tweede kanaal naast kleur)

    /// Uitgaven.
    static let chartExpenses = Color(light: Color(hex: 0xA24427), dark: Color(hex: 0xE48A5E))
    /// Variabele uitgaven, naast `chartExpenses` in de verdeelbalk.
    static let chartVariable = Color(light: Color(hex: 0xC9835F), dark: Color(hex: 0xF0B08E))
    /// Gespaard.
    static let chartSaved = Color(light: Color(hex: 0x2B7F72), dark: Color(hex: 0x5FBFAE))
    /// Belegd.
    static let chartInvested = Color(light: Color(hex: 0x3C5A99), dark: Color(hex: 0x8FAEE6))
    /// Over of overgehouden.
    static let chartFree = Color(light: Color(hex: 0xA38F30), dark: Color(hex: 0xEDE3A6))

    // MARK: Palet voor spaarpotten en beleggingssoorten (alleen pictogram en ring, nooit tekst; altijd met symbool en naam)

    static let palette: [Color] = [
        Color(hex: 0x7C9440),                                              // 0 olijf
        Color(hex: 0x4E8F86),                                              // 1 saliegroenblauw
        Color(light: Color(hex: 0xB08E21), dark: Color(hex: 0xC9A227)),    // 2 mosterd
        Color(hex: 0xC4704A),                                              // 3 terracotta
        Color(hex: 0x5B7C99),                                              // 4 leiblauw
        Color(hex: 0x8E5A7B),                                              // 5 pruim
        Color(light: Color(hex: 0x959575), dark: Color(hex: 0xA3A380)),    // 6 salie
        Color(light: Color(hex: 0x6B5B3E), dark: Color(hex: 0x796748))     // 7 bruin
    ]

    static func color(_ index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    /// De tegelkleur bij een `colorIndex` van een spaarpot of beleggingssoort (dezelfde index als `color(_:)`).
    static func hue(_ paletteIndex: Int) -> TileHue {
        TileHue.forIndex(paletteIndex)
    }

    static let potSymbols = [
        "banknote", "shield.lefthalf.filled", "airplane", "laptopcomputer", "house.fill", "car.fill",
        "gift.fill", "graduationcap.fill", "heart.fill", "pawprint.fill", "bicycle", "camera.fill",
        "gamecontroller.fill", "cart.fill", "wrench.and.screwdriver.fill", "star.fill"
    ]

    // MARK: Lettertokens (alleen tekststijlen, zodat Dynamic Type werkt)

    /// Het kerngetal van een pagina.
    static let heroAmount: Font = .largeTitle.weight(.bold)
    /// Een groot bedrag in een kaart.
    static let titleAmount: Font = .title2.weight(.bold)

    // MARK: Maten

    /// Buitenste radius van een kaart.
    static let cardRadius: CGFloat = 20
    /// Radius van een hero-kaart.
    static let heroRadius: CGFloat = 28
    /// Ruimte tussen de rand van een kaart en zijn inhoud.
    static let cardInset: CGFloat = 16
    /// Radius van een binnentegel in een kaart (`tile()`, `GradientSurface` zonder eigen radius).
    static let tileRadius: CGFloat = 12
    /// Radius van een tegel op een plank, een brede kaart en een bladertegel.
    static let posterRadius: CGFloat = 16
    /// Radius van het artwork in een lijstrij (44 punten) en van het kopartwork van een albumpagina.
    static let rowArtworkRadius: CGFloat = 8
    static let headerArtworkRadius: CGFloat = 24
    /// Breedste inhoud van Home (hero en planken).
    static let shelfMaxWidth: CGFloat = 1120
    /// Hoogte van het kleurverloop achter een pagina.
    static let backdropHeight: CGFloat = 420
    static let pageSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 12
    /// Breedste inhoud van een kaartenpagina.
    static let pageMaxWidth: CGFloat = 960
    /// Breedste inhoud van een lijst of formulier.
    static let readableWidth: CGFloat = 720
    /// Smalste breedte van één blok. Op een iPhone past er één kolom, op iPad en Mac twee.
    static let blockColumnMinimum: CGFloat = 340

    /// Kleinste raakdoel: 44 punten op iPhone en iPad, 28 op de Mac (de aanwijzer is nauwkeuriger).
    static var minTapTarget: CGFloat {
        #if os(macOS)
        return 28
        #else
        return 44
        #endif
    }

    /// Kolommen voor de blokken op een pagina met kaarten.
    static var blockColumns: [GridItem] {
        [GridItem(.adaptive(minimum: blockColumnMinimum), spacing: pageSpacing, alignment: .top)]
    }

    // MARK: Beweging (overal dezelfde, kort en zacht)

    /// Standaard voor veranderende bedragen, blokken en lijsten. Gebruik `.animated(by:)`, dat Verlaag beweging respecteert.
    static let motion: Animation = .smooth(duration: 0.3)
    /// Voor kleine, snelle reacties: tabwissel, indrukken van een knop.
    static let quickMotion: Animation = .snappy(duration: 0.25)

    // MARK: Overgangsvormen (tot pakket G; nieuwe code gebruikt deze niet)

    static let olive = accentFill
    static let oliveDeep = Color(hex: 0x2B3418)
    static let oliveLight = Color(hex: 0xA9C06B)
    static let flowExpenses = chartExpenses
    static let flowVariable = chartVariable
    static let flowSaved = chartSaved
    static let flowInvested = chartInvested
    static let flowFree = chartFree
    static let chipRadius: CGFloat = 10
    /// Was 42; nu de minimale maat van een raakdoel.
    static var buttonHeight: CGFloat { minTapTarget }
}

/// Overgangsvorm: de oude mesh-achtergrond tekent nu het vlakke canvas.
struct MeshBackground: View {
    var body: some View {
        Theme.canvas.ignoresSafeArea()
    }
}
