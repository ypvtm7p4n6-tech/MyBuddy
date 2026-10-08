import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
}

/// Eén plek voor vormen en kleuren, zodat alle schermen dezelfde taal spreken.
enum Theme {
    // MARK: Vormen (concentrisch: binnenste radius = buitenste radius - tussenruimte)
    static let cardRadius: CGFloat = 30
    static let cardInset: CGFloat = 16
    static var tileRadius: CGFloat { cardRadius - cardInset }   // 14
    static let chipRadius: CGFloat = 10
    static let pageSpacing: CGFloat = 16
    static let pageMaxWidth: CGFloat = 960

    // MARK: Kleuren (donker olijfgroen)
    static let olive = Color(hex: 0x556B2F)           // darkolivegreen
    static let oliveDeep = Color(hex: 0x2B3418)
    static let oliveLight = Color(hex: 0xA9C06B)
    static let accent = Color(light: Color(hex: 0x556B2F), dark: Color(hex: 0xA9C06B))
    static let positive = Color(light: Color(hex: 0x4A6B1C), dark: Color(hex: 0xB7D272))
    static let negative = Color(light: Color(hex: 0xB5482A), dark: Color(hex: 0xF29A7C))
    static let warning = Color(light: Color(hex: 0x9A7A12), dark: Color(hex: 0xE3C25A))

    // Kleuren van de grafiek "waar gaat je geld heen"
    static let flowExpenses = Color(hex: 0xC4704A)
    static let flowSaved = Color(hex: 0x8FA84F)
    static let flowInvested = Color(hex: 0x4E8F86)
    static let flowFree = Color(hex: 0xC9BE8E)

    /// Kleuren voor spaarpotten en beleggingen, in de buurt van olijf.
    static let palette: [Color] = [
        Color(hex: 0x7C9440), // olijf
        Color(hex: 0x4E8F86), // saliegroen-blauw
        Color(hex: 0xC9A227), // mosterd
        Color(hex: 0xC4704A), // terracotta
        Color(hex: 0x5B7C99), // leiblauw
        Color(hex: 0x8E5A7B), // pruim
        Color(hex: 0xA3A380), // salie
        Color(hex: 0x6B5B3E)  // bruin
    ]

    static func color(_ index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    static let potSymbols = [
        "banknote", "shield.lefthalf.filled", "airplane", "laptopcomputer", "house.fill", "car.fill",
        "gift.fill", "graduationcap.fill", "heart.fill", "pawprint.fill", "bicycle", "camera.fill",
        "gamecontroller.fill", "cart.fill", "wrench.and.screwdriver.fill", "star.fill"
    ]

    // MARK: Achtergrond
    static let meshDark: [Color] = [
        Color(hex: 0x0F140A), Color(hex: 0x1B2410), Color(hex: 0x131A0C),
        Color(hex: 0x1F2A12), Color(hex: 0x2E3C1A), Color(hex: 0x1A2310),
        Color(hex: 0x151C0D), Color(hex: 0x25301A), Color(hex: 0x0D1108)
    ]
    static let meshLight: [Color] = [
        Color(hex: 0xE7ECD2), Color(hex: 0xD9E2B8), Color(hex: 0xE4EAC9),
        Color(hex: 0xD2DDB0), Color(hex: 0xC4D197), Color(hex: 0xDCE5BD),
        Color(hex: 0xE9EDD6), Color(hex: 0xCFDAA9), Color(hex: 0xE2E8C8)
    ]
}

/// Zachte olijfgroene achtergrond waar het glas overheen ligt.
struct MeshBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MeshGradient(width: 3, height: 3,
                     points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.55, 0.45], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                     ],
                     colors: scheme == .dark ? Theme.meshDark : Theme.meshLight)
            .ignoresSafeArea()
    }
}
