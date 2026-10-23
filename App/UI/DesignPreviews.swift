#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas van de onderdelen van ontwerp 2: hero, planken, tegels, rijen, albumkop, pillen, profielknop en
// kleurverloop. Elk onderdeel staat gevuld in licht, in donker, bij grote tekst (`.accessibility3`) en, waar dat kan, leeg.
// "Verhoog contrast" laat zich niet in code instellen: zet het in de canvas aan bij Environment Overrides (dan krijgt een tegel
// een rand, worden de kleuren donkerder en verdwijnt de tint van de achtergrond).

private struct HeroPreviewPage: View {
    var body: some View {
        PageScaffold(title: "Home", large: true, fullBleed: true) {
            HeroCarouselPreviewContent()
        }
    }
}

private struct HeroCarouselPreviewContent: View {
    @State private var hero: String? = nil

    var body: some View {
        HeroCarousel(ids: ["a", "b", "c"], selection: $hero) { id in
            HeroCard(hue: TileHue.forIndex(id == "a" ? 0 : (id == "b" ? 4 : 3)), eyebrow: "Nog te verdelen in oktober",
                     symbol: "square.split.2x2") {
                BigAmount(value: 1_250, font: Theme.heroAmount, color: Theme.onTile, label: "Nog te verdelen")
            } pills: {
                PillRow {
                    PillButton("Verdelen", style: .onTile, action: {})
                }
            }
        }
    }
}

private struct ShelfPreviewPage: View {
    let tiles: [GalleryTile]

    var body: some View {
        PageScaffold(title: "Home", large: true, fullBleed: true) {
            Shelf("Spaarpotten", subtitle: "Totaal € 6.240,00", showAll: .pots, showAllLabel: "Toon alle spaarpotten",
                  actions: [ShelfAction("Kies potten…", symbol: "slider.horizontal.3", action: {})],
                  orderID: "pots", items: tiles) { pot in
                PosterCard(symbol: pot.symbol, hue: pot.hue, title: pot.title, subtitle: pot.subtitle, value: pot.value,
                           progress: pot.progress, destination: .pots)
            }
        }
    }
}

private struct EmptyShelfPreviewPage: View {
    var body: some View {
        PageScaffold(title: "Home", large: true, fullBleed: true) {
            Shelf("Spaarpotten", showAll: .pots, showAllLabel: "Toon alle spaarpotten",
                  items: [GalleryTile(id: 0, title: "", symbol: "tray.full", hue: .teal, subtitle: nil, value: "", progress: nil)]) { _ in
                ShelfCard(destination: .pots) {
                    EmptyHint(symbol: "tray", title: "Nog geen spaarpotten", message: "Maak een pot voor iets waar je voor spaart.")
                }
            }
        }
    }
}

private struct RowsPreviewPage: View {
    var body: some View {
        ListScaffold(title: "Bibliotheek", large: true) {
            Section {
                MediaRow(symbol: "chart.bar.xaxis", hue: .terracotta, title: "Maandoverzicht", destination: .flow,
                         showsCurrentMonth: true)
                MediaRow(symbol: "eurosign.circle", hue: .terracotta, title: "Inkomen", subtitle: "Salaris en overige inkomsten",
                         value: "€ 3.350,00", destination: .income)
                MediaRow(symbol: "tray.full", hue: .teal, title: "Spaarpotten", subtitle: "3 potten", value: "€ 6.240,00",
                         progress: 0.55, destination: .pots)
            } header: {
                SectionHeader("Deze maand")
            }
        }
        .profileToolbarItem()
    }
}

private struct AlbumPreviewPage: View {
    let hasFigure: Bool

    var body: some View {
        ListScaffold(title: "Vakantie") {
            Section {
                AlbumHeader(symbol: "airplane", hue: .terracotta, title: "Vakantie", subtitle: "Spaarpot, doel € 5.000,00",
                            figureLabel: hasFigure ? "Saldo vandaag" : nil, figure: hasFigure ? 1_250 : nil,
                            progress: hasFigure ? 0.25 : nil, progressLabel: "Voortgang naar je doel",
                            facts: hasFigure ? ["Rente 2,0% per jaar", "Inleg € 100,00 per maand"] : []) {
                    PillRow(alignment: .center) {
                        PillButton("Storten", symbol: "plus", style: .prominent, action: {})
                        PillButton("Opnemen", symbol: "minus", action: {})
                        PillButton("Bewerken", action: {})
                    }
                }
                .albumHeaderRow()
            }
            Section {
                MediaRowLabel(symbol: "plus", hue: .terracotta, title: "Storting", subtitle: "1 okt", value: "€ 100,00")
            } header: {
                SectionHeader("Geschiedenis")
            }
        }
        .environment(\.backdropHue, .terracotta)
    }
}

private struct BrowsePreviewPage: View {
    var body: some View {
        PageScaffold(title: "Zoeken", large: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(PageCatalog.browsePages) { info in
                    BrowseTile(title: info.title, symbol: info.symbol, hue: info.hue, destination: info.destination)
                }
            }
        }
        .profileToolbarItem()
    }
}

// MARK: - Hero

#Preview("Hero, licht") {
    GalleryHost { HeroPreviewPage() }
        .preferredColorScheme(.light)
}

#Preview("Hero, donker") {
    GalleryHost { HeroPreviewPage() }
        .preferredColorScheme(.dark)
}

#Preview("Hero, grote tekst") {
    GalleryHost { HeroPreviewPage() }
        .dynamicTypeSize(.accessibility3)
}

// MARK: - Planken

#Preview("Plank, licht") {
    GalleryHost { ShelfPreviewPage(tiles: GalleryData.pots) }
        .preferredColorScheme(.light)
}

#Preview("Plank, donker") {
    GalleryHost { ShelfPreviewPage(tiles: GalleryData.pots) }
        .preferredColorScheme(.dark)
}

#Preview("Plank, grote tekst") {
    GalleryHost { ShelfPreviewPage(tiles: GalleryData.pots) }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Plank, leeg") {
    GalleryHost { EmptyShelfPreviewPage() }
}

// MARK: - Rijen, album en zoeken

#Preview("Rijen, licht") {
    GalleryHost { RowsPreviewPage() }
        .preferredColorScheme(.light)
}

#Preview("Rijen, donker") {
    GalleryHost { RowsPreviewPage() }
        .preferredColorScheme(.dark)
}

#Preview("Rijen, grote tekst") {
    GalleryHost { RowsPreviewPage() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Album, licht") {
    GalleryHost { AlbumPreviewPage(hasFigure: true) }
        .preferredColorScheme(.light)
}

#Preview("Album, donker") {
    GalleryHost { AlbumPreviewPage(hasFigure: true) }
        .preferredColorScheme(.dark)
}

#Preview("Album, grote tekst") {
    GalleryHost { AlbumPreviewPage(hasFigure: true) }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Album, leeg (zonder kerngetal)") {
    GalleryHost { AlbumPreviewPage(hasFigure: false) }
}

#Preview("Zoeken, licht") {
    GalleryHost { BrowsePreviewPage() }
        .preferredColorScheme(.light)
}

#Preview("Zoeken, donker") {
    GalleryHost { BrowsePreviewPage() }
        .preferredColorScheme(.dark)
}

#Preview("Zoeken, grote tekst") {
    GalleryHost { BrowsePreviewPage() }
        .dynamicTypeSize(.accessibility3)
}
#endif
