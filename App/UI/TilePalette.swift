import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests; de tests staan in TilePaletteTests.swift en herberekenen elk contrast hieronder.
// `Theme.swift` leest deze waarden (ook `canvas` en `textSecondary`), zodat de test en het scherm dezelfde bron hebben.

// MARK: - De acht tegelkleuren

/// De acht kleuren van een tegel, hero-kaart of albumtegel. De volgorde is die van `Theme.palette` (0...7), dus een
/// `colorIndex` van een spaarpot of beleggingssoort wijst met `forIndex` rechtstreeks naar een tint. Een tint hangt niet af van
/// licht of donker: witte tekst staat er altijd op (`TilePalette.colors`).
enum TileHue: Int, CaseIterable, Identifiable, Hashable {
    case olive, teal, mustard, terracotta, slate, plum, sage, brown

    var id: Int { rawValue }

    /// De tint bij een index uit de gegevens: cyclisch, ook voor een negatief getal.
    static func forIndex(_ index: Int) -> TileHue {
        let wrapped = ((index % 8) + 8) % 8
        return TileHue(rawValue: wrapped) ?? .olive
    }
}

/// De vier kleurwaarden (sRGB, 0xRRGGBB) van een tint: het verloop loopt van `top` naar `bottom`; de hoog-contrastvarianten
/// zijn donkerder en gelden bij "Verhoog contrast".
struct TileColors: Equatable {
    let top: UInt32
    let bottom: UInt32
    let topHC: UInt32
    let bottomHC: UInt32
}

// MARK: - Waarden en contrastberekening

enum TilePalette {
    /// De waarden van tabel 2.1 van docs/design2/plan.md. Wit op `top`: 6,37 tot 6,42; op `bottom` minimaal 11,7; met
    /// hoog contrast minimaal 9,55 (WCAG 2.x, `TilePaletteTests` herberekent ze). Wie een waarde aanpast laat de test slagen,
    /// versoepelt hem niet.
    static func colors(_ hue: TileHue) -> TileColors {
        switch hue {
        case .olive: return TileColors(top: 0x566529, bottom: 0x333B18, topHC: 0x3F491E, bottomHC: 0x232911)
        case .teal: return TileColors(top: 0x2D6863, bottom: 0x1B3E3B, topHC: 0x214C48, bottomHC: 0x122A28)
        case .mustard: return TileColors(top: 0x755C0C, bottom: 0x453607, topHC: 0x554308, bottomHC: 0x2F2505)
        case .terracotta: return TileColors(top: 0x924C2E, bottom: 0x572D1C, topHC: 0x6B3722, bottomHC: 0x3C1F13)
        case .slate: return TileColors(top: 0x406281, bottom: 0x263A4D, topHC: 0x2E475E, bottomHC: 0x1A2835)
        case .plum: return TileColors(top: 0x934276, bottom: 0x582746, topHC: 0x6C3056, bottomHC: 0x3D1B31)
        case .sage: return TileColors(top: 0x57634B, bottom: 0x343A2C, topHC: 0x404836, bottomHC: 0x24281F)
        case .brown: return TileColors(top: 0x735B3E, bottom: 0x443525, topHC: 0x54422D, bottomHC: 0x2F2519)
        }
    }

    // MARK: Achtergrond en bijschriften (Theme.canvas en Theme.textSecondary lezen deze waarden)

    static let canvasLight: UInt32 = 0xEEF1E2
    static let canvasDark: UInt32 = 0x0E1209
    static let textSecondaryLight: UInt32 = 0x566049
    static let textSecondaryDark: UInt32 = 0xB3BAA3
    static let textSecondaryLightHC: UInt32 = 0x3A4230
    static let textSecondaryDarkHC: UInt32 = 0xD3D9C4

    /// Wit (`Theme.onTile`) en de doorzichtigheid van `Theme.onTileSecondary` op een tegel: 82% (minimaal 4,88:1; 4,5:1
    /// vanaf 77%), bij Verhoog contrast 92% (minimaal 8,3:1).
    static let onTile: UInt32 = 0xFFFFFF
    static let onTileSecondaryAlpha = 0.82
    static let onTileSecondaryAlphaHC = 0.92

    /// Hoe sterk de tint van het kleurverloop achter een pagina is: hoogstens 55% in donker en 14% in licht.
    static let backdropAlphaDark = 0.55
    static let backdropAlphaLight = 0.14

    // MARK: WCAG 2.x

    /// De relatieve luminantie van een sRGB-kleur (0xRRGGBB).
    static func luminance(_ hex: UInt32) -> Double {
        let red = channel(hex >> 16)
        let green = channel(hex >> 8)
        let blue = channel(hex)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func channel(_ shifted: UInt32) -> Double {
        let value = Double(shifted & 0xFF) / 255
        if value <= 0.03928 { return value / 12.92 }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    /// De contrastverhouding van twee kleuren (1 tot 21), in welke volgorde je ze ook geeft.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let first = luminance(a)
        let second = luminance(b)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// De kleur die ontstaat als `fg` met doorzichtigheid `alpha` (0...1) over `bg` ligt: per kanaal in sRGB, zoals SwiftUI
    /// het tekent, afgerond op een geheel getal.
    static func blend(_ fg: UInt32, over bg: UInt32, alpha: Double) -> UInt32 {
        let weight = min(1, max(0, alpha))
        var result: UInt32 = 0
        for shift in [UInt32(16), UInt32(8), UInt32(0)] {
            let front = Double((fg >> shift) & 0xFF)
            let back = Double((bg >> shift) & 0xFF)
            let mixed = (front * weight + back * (1 - weight)).rounded()
            let clamped = UInt32(min(255, max(0, mixed)))
            result |= clamped << shift
        }
        return result
    }

    /// De bovenstop van het kleurverloop achter een pagina op de volle sterkte: de bovenkleur van de tint over het canvas.
    static func backdropTop(_ hue: TileHue, dark: Bool) -> UInt32 {
        let canvas = dark ? canvasDark : canvasLight
        let alpha = dark ? backdropAlphaDark : backdropAlphaLight
        return blend(colors(hue).top, over: canvas, alpha: alpha)
    }
}
