import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests; de tests staan in ShelfMetricsTests.swift (met de tabel van docs/design2/patterns.md
// par. 3.4 als testgegevens). De views (`Shelf`, `HeroCarousel`) rekenen alle breedtes hiermee uit.

/// Maten voor hero-kaarten en planken. Zuivere functies met `Double`, zodat ze zonder SwiftUI te testen zijn.
enum ShelfMetrics {
    /// Extra zichtbare rand van de volgende hero-kaart, bovenop de paginamarge.
    static let heroPeek = 8.0

    /// Paginamarge: 16 punten op een iPhone (compact), 20 op iPad en Mac.
    static func margin(compact: Bool) -> Double {
        compact ? 16 : 20
    }

    /// Ruimte tussen tegels: 12 punten op een iPhone (compact), 16 op iPad en Mac.
    static func spacing(compact: Bool) -> Double {
        compact ? 12 : 16
    }

    /// De breedte van een tegel in een plank. `length` is de breedte binnen de marges, zoals `containerRelativeFrame` hem geeft.
    /// Er passen `whole` hele tegels (minstens twee) en 0,4 tegel van de volgende: zo zie je dat de plank doorloopt. Een
    /// ongeldige breedte (nul, negatief, oneindig of NaN) geeft 140.
    static func tileWidth(in length: Double, spacing: Double) -> Double {
        guard length.isFinite, length > 0, spacing.isFinite, spacing >= 0 else { return 140 }
        let fit = (length + spacing) / (150 + spacing)
        let whole = max(2, Int(min(fit, 1_000)))
        let count = Double(whole)
        return (length - count * spacing) / (count + 0.4)
    }

    /// De breedte van een brede kaart (Komende dagen): twee tegels plus de tussenruimte.
    static func wideTileWidth(in length: Double, spacing: Double) -> Double {
        2 * tileWidth(in: length, spacing: spacing) + spacing
    }

    /// De breedte van een hero-kaart: een kaart plus een rand van de volgende (hoogstens 480); vanaf 860 punten staan er drie
    /// naast elkaar. Een ongeldige breedte geeft 300.
    static func heroWidth(in length: Double, spacing: Double) -> Double {
        guard length.isFinite, length > 0, spacing.isFinite, spacing >= 0 else { return 300 }
        if length >= 860 { return (length - 2 * spacing) / 3 }
        return min(length - spacing - heroPeek, 480)
    }

    /// Is de breedte zo smal dat de hero-kaarten een carrousel zijn (met stippen)? Vanaf 860 punten staan ze naast elkaar.
    static func showsHeroCarousel(in length: Double) -> Bool {
        length < 860
    }
}
