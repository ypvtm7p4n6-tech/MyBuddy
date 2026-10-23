import XCTest
import Foundation

// Tests van de tegelkleuren (App/UI/TilePalette.swift, Foundation-only): de waarden van tabel 2.1 van docs/design2/plan.md, het
// WCAG-contrast van witte tekst op elke tint (normaal en hoog contrast), van `Theme.onTileSecondary`, van de bijschriften op het
// kleurverloop achter een pagina (licht en donker) en `forIndex`. Wie een kleur aanpast laat deze test slagen, versoepelt hem niet.

final class TilePaletteTests: XCTestCase {
    private let white = TilePalette.onTile

    // MARK: De tinten

    func testThereAreEightHuesInTheOrderOfThePalette() {
        XCTAssertEqual(TileHue.allCases, [.olive, .teal, .mustard, .terracotta, .slate, .plum, .sage, .brown])
        XCTAssertEqual(TileHue.allCases.map { $0.rawValue }, Array(0..<8))
        XCTAssertEqual(TileHue.allCases.map { $0.id }, Array(0..<8))
    }

    func testForIndexWrapsAroundAndHandlesNegativeNumbers() {
        for index in 0..<8 {
            XCTAssertEqual(TileHue.forIndex(index).rawValue, index)
            XCTAssertEqual(TileHue.forIndex(index + 8), TileHue.forIndex(index))
            XCTAssertEqual(TileHue.forIndex(index + 800), TileHue.forIndex(index))
        }
        XCTAssertEqual(TileHue.forIndex(-1), .brown)
        XCTAssertEqual(TileHue.forIndex(-8), .olive)
        XCTAssertEqual(TileHue.forIndex(-9), .brown)
        XCTAssertEqual(TileHue.forIndex(Int.max), TileHue.forIndex(Int.max % 8))
        XCTAssertEqual(TileHue.forIndex(Int.min), .olive)
    }

    // MARK: De waarden van tabel 2.1

    func testEveryValueOfTheTable() {
        let table: [(TileHue, UInt32, UInt32, UInt32, UInt32)] = [
            (.olive, 0x566529, 0x333B18, 0x3F491E, 0x232911),
            (.teal, 0x2D6863, 0x1B3E3B, 0x214C48, 0x122A28),
            (.mustard, 0x755C0C, 0x453607, 0x554308, 0x2F2505),
            (.terracotta, 0x924C2E, 0x572D1C, 0x6B3722, 0x3C1F13),
            (.slate, 0x406281, 0x263A4D, 0x2E475E, 0x1A2835),
            (.plum, 0x934276, 0x582746, 0x6C3056, 0x3D1B31),
            (.sage, 0x57634B, 0x343A2C, 0x404836, 0x24281F),
            (.brown, 0x735B3E, 0x443525, 0x54422D, 0x2F2519)
        ]
        XCTAssertEqual(table.count, TileHue.allCases.count)
        for row in table {
            let colors = TilePalette.colors(row.0)
            XCTAssertEqual(colors, TileColors(top: row.1, bottom: row.2, topHC: row.3, bottomHC: row.4), "\(row.0)")
        }
    }

    func testEveryHueHasItsOwnColors() {
        let tops = TileHue.allCases.map { TilePalette.colors($0).top }
        XCTAssertEqual(Set(tops).count, 8)
    }

    func testHighContrastColorsAreDarkerThanTheNormalOnes() {
        for hue in TileHue.allCases {
            let colors = TilePalette.colors(hue)
            XCTAssertLessThan(TilePalette.luminance(colors.topHC), TilePalette.luminance(colors.top), "\(hue)")
            XCTAssertLessThan(TilePalette.luminance(colors.bottomHC), TilePalette.luminance(colors.bottom), "\(hue)")
            XCTAssertLessThan(TilePalette.luminance(colors.bottom), TilePalette.luminance(colors.top), "\(hue)")
        }
    }

    // MARK: De rekenhulp zelf

    func testLuminanceAndContrastOfBlackAndWhite() {
        XCTAssertEqual(TilePalette.luminance(0x000000), 0, accuracy: 1e-9)
        XCTAssertEqual(TilePalette.luminance(0xFFFFFF), 1, accuracy: 1e-9)
        XCTAssertEqual(TilePalette.contrast(0xFFFFFF, 0x000000), 21, accuracy: 1e-9)
        XCTAssertEqual(TilePalette.contrast(0x000000, 0xFFFFFF), 21, accuracy: 1e-9)
        XCTAssertEqual(TilePalette.contrast(0x777777, 0x777777), 1, accuracy: 1e-9)
        // Bekende waarde: #767676 op wit is de grens van 4,5:1 (4,54).
        XCTAssertEqual(TilePalette.contrast(0x767676, 0xFFFFFF), 4.54, accuracy: 0.01)
    }

    func testBlendMixesPerChannelAndRounds() {
        XCTAssertEqual(TilePalette.blend(0xFFFFFF, over: 0x000000, alpha: 1), 0xFFFFFF)
        XCTAssertEqual(TilePalette.blend(0xFFFFFF, over: 0x000000, alpha: 0), 0x000000)
        // 50% rood over blauw: rood 127,5 en blauw 127,5 ronden af naar 128 (0x80).
        XCTAssertEqual(TilePalette.blend(0xFF0000, over: 0x0000FF, alpha: 0.5), 0x800080)
        XCTAssertEqual(TilePalette.blend(0x102030, over: 0x102030, alpha: 0.37), 0x102030)
        // Buiten 0...1 wordt begrensd.
        XCTAssertEqual(TilePalette.blend(0xFFFFFF, over: 0x000000, alpha: 3), 0xFFFFFF)
        XCTAssertEqual(TilePalette.blend(0xFFFFFF, over: 0x000000, alpha: -1), 0x000000)
    }

    // MARK: Witte tekst op de tegel

    func testWhiteOnTheTopStopIsBetween6And6Point5() {
        for hue in TileHue.allCases {
            let ratio = TilePalette.contrast(white, TilePalette.colors(hue).top)
            XCTAssertGreaterThanOrEqual(ratio, 6.37, "\(hue)")
            XCTAssertLessThanOrEqual(ratio, 6.43, "\(hue)")
        }
    }

    func testWhiteOnTheBottomStopIsAtLeast11Point7() {
        for hue in TileHue.allCases {
            XCTAssertGreaterThanOrEqual(TilePalette.contrast(white, TilePalette.colors(hue).bottom), 11.67, "\(hue)")
        }
    }

    func testWhiteWithIncreasedContrastIsAtLeast9Point5() {
        for hue in TileHue.allCases {
            let colors = TilePalette.colors(hue)
            XCTAssertGreaterThanOrEqual(TilePalette.contrast(white, colors.topHC), 9.55, "\(hue)")
            XCTAssertGreaterThanOrEqual(TilePalette.contrast(white, colors.bottomHC), 9.55, "\(hue)")
        }
    }

    func testEveryTilePassesAAForNormalTextEvenWithoutTheMargin() {
        for hue in TileHue.allCases {
            let colors = TilePalette.colors(hue)
            for color in [colors.top, colors.bottom, colors.topHC, colors.bottomHC] {
                XCTAssertGreaterThanOrEqual(TilePalette.contrast(white, color), 4.5, "\(hue)")
            }
        }
    }

    // MARK: onTileSecondary

    private func worstSecondaryContrast(alpha: Double, highContrast: Bool) -> Double {
        var worst = Double.greatestFiniteMagnitude
        for hue in TileHue.allCases {
            let colors = TilePalette.colors(hue)
            let stops = highContrast ? [colors.topHC, colors.bottomHC] : [colors.top, colors.bottom]
            for stop in stops {
                let text = TilePalette.blend(white, over: stop, alpha: alpha)
                worst = min(worst, TilePalette.contrast(text, stop))
            }
        }
        return worst
    }

    func testOnTileSecondaryAt82PercentIsAtLeast4Point88() {
        XCTAssertEqual(TilePalette.onTileSecondaryAlpha, 0.82)
        XCTAssertGreaterThanOrEqual(worstSecondaryContrast(alpha: TilePalette.onTileSecondaryAlpha, highContrast: false), 4.88)
    }

    func testOnTileSecondaryWithIncreasedContrastIsAtLeast8Point3() {
        XCTAssertEqual(TilePalette.onTileSecondaryAlphaHC, 0.92)
        XCTAssertGreaterThanOrEqual(worstSecondaryContrast(alpha: TilePalette.onTileSecondaryAlphaHC, highContrast: true), 8.3)
    }

    func testOnTileSecondaryNeedsAtLeast77PercentForAA() {
        XCTAssertGreaterThanOrEqual(worstSecondaryContrast(alpha: 0.77, highContrast: false), 4.5)
        XCTAssertLessThan(worstSecondaryContrast(alpha: 0.70, highContrast: false), 4.5)
        XCTAssertGreaterThan(TilePalette.onTileSecondaryAlpha, 0.77)
        XCTAssertGreaterThan(TilePalette.onTileSecondaryAlphaHC, TilePalette.onTileSecondaryAlpha)
    }

    // MARK: Het kleurverloop achter een pagina

    func testBackdropStrengthIs55PercentDarkAnd14PercentLight() {
        XCTAssertEqual(TilePalette.backdropAlphaDark, 0.55)
        XCTAssertEqual(TilePalette.backdropAlphaLight, 0.14)
    }

    func testCaptionsOnTheBackdropKeepTheirContrastInDarkMode() {
        var worst = Double.greatestFiniteMagnitude
        for hue in TileHue.allCases {
            let top = TilePalette.backdropTop(hue, dark: true)
            worst = min(worst, TilePalette.contrast(TilePalette.textSecondaryDark, top))
            XCTAssertGreaterThanOrEqual(TilePalette.contrast(white, top), 11, "\(hue): primaire tekst")
        }
        XCTAssertGreaterThanOrEqual(worst, 5.49)
    }

    func testCaptionsOnTheBackdropKeepTheirContrastInLightMode() {
        var worst = Double.greatestFiniteMagnitude
        for hue in TileHue.allCases {
            let top = TilePalette.backdropTop(hue, dark: false)
            worst = min(worst, TilePalette.contrast(TilePalette.textSecondaryLight, top))
            XCTAssertGreaterThanOrEqual(TilePalette.contrast(0x000000, top), 14.9, "\(hue): primaire tekst")
        }
        XCTAssertGreaterThanOrEqual(worst, 4.72)
    }

    func testCaptionsOnThePlainCanvasKeepTheirContrast() {
        XCTAssertGreaterThanOrEqual(TilePalette.contrast(TilePalette.textSecondaryLight, TilePalette.canvasLight), 5.78)
        XCTAssertGreaterThanOrEqual(TilePalette.contrast(TilePalette.textSecondaryDark, TilePalette.canvasDark), 9.4)
        XCTAssertGreaterThanOrEqual(TilePalette.contrast(TilePalette.textSecondaryLightHC, TilePalette.canvasLight), 8)
        XCTAssertGreaterThanOrEqual(TilePalette.contrast(TilePalette.textSecondaryDarkHC, TilePalette.canvasDark), 12)
    }

    func testIncreasedContrastCaptionsAreStrongerThanTheNormalOnes() {
        XCTAssertGreaterThan(TilePalette.contrast(TilePalette.textSecondaryLightHC, TilePalette.canvasLight),
                             TilePalette.contrast(TilePalette.textSecondaryLight, TilePalette.canvasLight))
        XCTAssertGreaterThan(TilePalette.contrast(TilePalette.textSecondaryDarkHC, TilePalette.canvasDark),
                             TilePalette.contrast(TilePalette.textSecondaryDark, TilePalette.canvasDark))
    }

    func testTheBackdropMovesAwayFromTheCanvasButNeverBeyondTheTile() {
        for hue in TileHue.allCases {
            let colors = TilePalette.colors(hue)
            let dark = TilePalette.backdropTop(hue, dark: true)
            let light = TilePalette.backdropTop(hue, dark: false)
            XCTAssertNotEqual(dark, TilePalette.canvasDark)
            XCTAssertNotEqual(light, TilePalette.canvasLight)
            // Donker: donkerder dan de tegel zelf; licht: lichter dan de tegel zelf.
            XCTAssertLessThan(TilePalette.luminance(dark), TilePalette.luminance(colors.top), "\(hue)")
            XCTAssertGreaterThan(TilePalette.luminance(light), TilePalette.luminance(colors.top), "\(hue)")
        }
    }
}
