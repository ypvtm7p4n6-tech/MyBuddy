import XCTest
import Foundation

// Tests van de maten voor hero en planken (App/UI/ShelfMetrics.swift, Foundation-only). De tabel van docs/design2/patterns.md
// par. 3.4 (negen breedtes van iPhone 16e tot iPad 13 liggend) staat hieronder als testgegevens.

final class ShelfMetricsTests: XCTestCase {
    /// Breedte binnen de marges, tussenruimte, hero-kaart, tegel, brede kaart, hele tegels zichtbaar (patterns.md par. 3.4).
    private struct Row {
        let name: String
        let length: Double
        let spacing: Double
        let hero: Double
        let tile: Double
        let wide: Double
        let whole: Int
        let carousel: Bool
    }

    private let table: [Row] = [
        Row(name: "iPhone 16e", length: 343, spacing: 12, hero: 323, tile: 133, wide: 278, whole: 2, carousel: true),
        Row(name: "iPhone 16", length: 361, spacing: 12, hero: 341, tile: 140, wide: 293, whole: 2, carousel: true),
        Row(name: "iPhone 16 Pro Max", length: 408, spacing: 12, hero: 388, tile: 160, wide: 332, whole: 2, carousel: true),
        Row(name: "Mac 640", length: 600, spacing: 16, hero: 480, tile: 162, wide: 341, whole: 3, carousel: true),
        Row(name: "iPad mini staand", length: 704, spacing: 16, hero: 480, tile: 145, wide: 307, whole: 4, carousel: true),
        Row(name: "iPad 11 staand", length: 794, spacing: 16, hero: 480, tile: 166, wide: 348, whole: 4, carousel: true),
        Row(name: "Mac 900", length: 860, spacing: 16, hero: 276, tile: 144, wide: 305, whole: 5, carousel: false),
        Row(name: "iPad 13 staand", length: 992, spacing: 16, hero: 320, tile: 140, wide: 296, whole: 6, carousel: false),
        Row(name: "iPad 13 liggend, Mac 1366", length: 1326, spacing: 16, hero: 431, tile: 143, wide: 301, whole: 8, carousel: false)
    ]

    func testHeroWidthMatchesTheTable() {
        for row in table {
            XCTAssertEqual(ShelfMetrics.heroWidth(in: row.length, spacing: row.spacing), row.hero, accuracy: 0.5, row.name)
        }
    }

    func testTileWidthMatchesTheTable() {
        for row in table {
            XCTAssertEqual(ShelfMetrics.tileWidth(in: row.length, spacing: row.spacing), row.tile, accuracy: 0.5, row.name)
        }
    }

    func testWideTileWidthMatchesTheTable() {
        for row in table {
            XCTAssertEqual(ShelfMetrics.wideTileWidth(in: row.length, spacing: row.spacing), row.wide, accuracy: 0.5, row.name)
        }
    }

    func testCarouselOnlyBelow860() {
        for row in table {
            XCTAssertEqual(ShelfMetrics.showsHeroCarousel(in: row.length), row.carousel, row.name)
        }
        XCTAssertTrue(ShelfMetrics.showsHeroCarousel(in: 859.9))
        XCTAssertFalse(ShelfMetrics.showsHeroCarousel(in: 860))
    }

    func testAWholeNumberOfTilesAndAFortyPercentPeekFill() {
        for row in table {
            let tile = ShelfMetrics.tileWidth(in: row.length, spacing: row.spacing)
            let used = Double(row.whole) * (tile + row.spacing) + 0.4 * tile
            // `whole` tegels met tussenruimte plus 0,4 tegel zijn samen precies de breedte binnen de marges.
            XCTAssertEqual(used, row.length, accuracy: 0.001, row.name)
        }
    }

    func testATileStaysBetween133And166Points() {
        for row in table {
            let tile = ShelfMetrics.tileWidth(in: row.length, spacing: row.spacing)
            XCTAssertGreaterThanOrEqual(tile, 132.9, row.name)
            XCTAssertLessThanOrEqual(tile, 166, row.name)
        }
        // Tussen de rijen van de tabel in loopt de tegel net voor een nieuwe hele tegel op tot ongeveer 187 pt en zakt daarna
        // terug naar ongeveer 128 pt: nooit daarbuiten.
        var length = 343.0
        while length <= 1_600 {
            for spacing in [12.0, 16.0] {
                let tile = ShelfMetrics.tileWidth(in: length, spacing: spacing)
                XCTAssertGreaterThanOrEqual(tile, 127, "breedte \(length)")
                XCTAssertLessThanOrEqual(tile, 188, "breedte \(length)")
            }
            length += 7
        }
    }

    func testAtLeastTwoTilesAreAlwaysWhole() {
        // Zelfs op een heel smal scherm blijven er twee hele tegels (kleiner dan 133 pt).
        let narrow = ShelfMetrics.tileWidth(in: 250, spacing: 12)
        XCTAssertEqual(narrow, (250 - 24) / 2.4, accuracy: 1e-9)
        XCTAssertLessThan(narrow, 133)
        XCTAssertEqual(ShelfMetrics.tileWidth(in: 1, spacing: 12), (1.0 - 24) / 2.4, accuracy: 1e-9)
    }

    func testMarginAndSpacingFollowTheSizeClass() {
        XCTAssertEqual(ShelfMetrics.margin(compact: true), 16)
        XCTAssertEqual(ShelfMetrics.margin(compact: false), 20)
        XCTAssertEqual(ShelfMetrics.spacing(compact: true), 12)
        XCTAssertEqual(ShelfMetrics.spacing(compact: false), 16)
        XCTAssertEqual(ShelfMetrics.heroPeek, 8)
    }

    func testHeroIsAtMost480InTheCarousel() {
        for length in stride(from: 300.0, to: 860.0, by: 10) {
            let hero = ShelfMetrics.heroWidth(in: length, spacing: 16)
            XCTAssertLessThanOrEqual(hero, 480, "breedte \(length)")
            XCTAssertEqual(hero, min(length - 16 - 8, 480), accuracy: 1e-9)
        }
    }

    func testThreeHeroCardsFillTheWidthFromThe860Threshold() {
        for length in [860.0, 900, 1_024, 1_326, 1_920] {
            let hero = ShelfMetrics.heroWidth(in: length, spacing: 16)
            XCTAssertEqual(hero * 3 + 2 * 16, length, accuracy: 1e-9, "breedte \(length)")
        }
    }

    func testInvalidLengthsGiveSafeDefaults() {
        let invalid: [Double] = [0, -1, -300, .nan, .infinity, -.infinity]
        for length in invalid {
            XCTAssertEqual(ShelfMetrics.tileWidth(in: length, spacing: 12), 140, "\(length)")
            XCTAssertEqual(ShelfMetrics.heroWidth(in: length, spacing: 12), 300, "\(length)")
            XCTAssertEqual(ShelfMetrics.wideTileWidth(in: length, spacing: 12), 2 * 140 + 12, "\(length)")
        }
    }

    func testInvalidSpacingGivesSafeDefaultsToo() {
        XCTAssertEqual(ShelfMetrics.tileWidth(in: 400, spacing: .nan), 140)
        XCTAssertEqual(ShelfMetrics.tileWidth(in: 400, spacing: -4), 140)
        XCTAssertEqual(ShelfMetrics.heroWidth(in: 400, spacing: .infinity), 300)
    }

    func testAHugeWidthDoesNotCrash() {
        let tile = ShelfMetrics.tileWidth(in: 1e12, spacing: 16)
        XCTAssertTrue(tile.isFinite)
        XCTAssertGreaterThan(tile, 0)
        XCTAssertTrue(ShelfMetrics.heroWidth(in: 1e12, spacing: 16).isFinite)
    }
}
