#if DEBUG
import SwiftUI

// De tegels, planken, hero, bladertegels, pillen en tinten van ontwerp 2 op een pagina, voor de Xcode-canvas (alleen in een
// debug-build). `ComponentGallery` toont dit onder de kaarten; de previews staan in `DesignPreviews.swift`. Alle voorbeeldtekst is
// verzonnen en niet uit de gegevens van een gebruiker.

/// Een voorbeeldtegel voor een plank.
struct GalleryTile: Identifiable {
    let id: Int
    let title: String
    let symbol: String
    let hue: TileHue
    let subtitle: String?
    let value: String
    let progress: Double?
}

enum GalleryData {
    static let pots: [GalleryTile] = [
        GalleryTile(id: 0, title: "Buffer", symbol: "shield.lefthalf.filled", hue: .olive, subtitle: "Spaarpot", value: "€ 4.200,00", progress: 0.7),
        GalleryTile(id: 1, title: "Vakantie", symbol: "airplane", hue: .terracotta, subtitle: "Spaarpot", value: "€ 1.250,00", progress: 0.42),
        GalleryTile(id: 2, title: "Nieuwe laptop met een heel lange naam", symbol: "laptopcomputer", hue: .slate,
                    subtitle: "Spaarpot", value: "€ 640,00", progress: 0.1),
        GalleryTile(id: 3, title: "Cadeaus", symbol: "gift.fill", hue: .plum, subtitle: "Spaarpot", value: "€ 150,00", progress: nil)
    ]

    static let days: [GalleryTile] = [
        GalleryTile(id: 0, title: "Vandaag", symbol: "calendar", hue: .terracotta, subtitle: "Huur, min € 850,00", value: "Saldo € 2.310,00", progress: nil),
        GalleryTile(id: 1, title: "Do 30 okt", symbol: "calendar", hue: .terracotta, subtitle: "Salaris, plus € 3.200,00", value: "Saldo € 5.510,00", progress: nil),
        GalleryTile(id: 2, title: "Za 1 nov", symbol: "calendar", hue: .terracotta, subtitle: "Verzekering, min € 95,00", value: "Saldo € 5.415,00", progress: nil)
    ]
}

/// De nieuwe onderdelen van ontwerp 2 onder elkaar.
struct TileGallery: View {
    @State private var hero: String? = nil
    private let margin = CGFloat(ShelfMetrics.margin(compact: true))

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            heroSection
            potsShelf
            daysShelf
            emptyShelf
            browseSection
            pillsSection
            huesSection
            backdropSection
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        HeroCarousel(ids: ["distribute", "wealth", "balance"], selection: $hero) { id in
            heroCard(id)
        }
    }

    @ViewBuilder
    private func heroCard(_ id: String) -> some View {
        switch id {
        case "distribute":
            HeroCard(hue: .olive, eyebrow: "Nog te verdelen in oktober", symbol: "square.split.2x2") {
                BigAmount(value: 1_250, font: Theme.heroAmount, color: Theme.onTile, label: "Nog te verdelen")
            } pills: {
                PillRow {
                    PillLink("Verdelen", style: .onTile, destination: .distribute, showsCurrentMonth: true)
                }
            }
        case "wealth":
            HeroCard(hue: .slate, eyebrow: "Vermogen eind oktober", symbol: "chart.pie") {
                BigAmount(value: 18_940, font: Theme.heroAmount, color: Theme.onTile, label: "Vermogen")
                ProgressMeter(value: 0.6, tint: Theme.onTile, style: .bar(height: 8), label: "Verloop", valueText: "60%")
                    .heroPanel()
            } pills: {
                PillRow {
                    PillLink("Bank € 4.200", style: .onTile, destination: .bank)
                    PillLink("Potten € 6.240", style: .onTile, destination: .pots)
                }
            }
        default:
            HeroCard(hue: .terracotta, eyebrow: "Saldo vandaag", symbol: "building.columns") {
                BigAmount(value: 2_310, font: Theme.heroAmount, color: Theme.onTile, label: "Saldo vandaag")
                Text("Volgende betaling: Huur, vr 31 okt, min € 850,00")
                    .font(.subheadline)
                    .foregroundStyle(Theme.onTileSecondary)
            } pills: {
                PillRow {
                    PillButton("Saldo bijwerken", style: .onTile, action: {})
                }
            }
        }
    }

    // MARK: Planken

    private var potsShelf: some View {
        Shelf("Spaarpotten", subtitle: "Totaal € 6.240,00", showAll: .pots, showAllLabel: "Toon alle spaarpotten",
              actions: [ShelfAction("Kies potten…", symbol: "slider.horizontal.3", action: {}),
                        ShelfAction("Nieuwe spaarpot", symbol: "plus", action: {})],
              orderID: "pots", items: GalleryData.pots) { pot in
            PosterCard(symbol: pot.symbol, hue: pot.hue, title: pot.title, subtitle: pot.subtitle, value: pot.value,
                       progress: pot.progress, progressLabel: "Voortgang naar je doel", destination: .pots)
        }
    }

    private var daysShelf: some View {
        Shelf("Komende dagen", subtitle: "27 okt t/m 9 nov", showAll: .cashflow, showAllLabel: "Toon dag voor dag",
              orderID: "upcoming", wide: true, items: GalleryData.days) { day in
            ShelfCard(destination: .cashflow, showsCurrentMonth: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.title).font(.subheadline.weight(.semibold))
                    Text(day.subtitle ?? "").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    Text(day.value).font(.subheadline).monospacedDigit()
                }
            }
        }
    }

    /// Een plank zonder inhoud: een kaart met de lege staat, zodat de plank nooit leeg staat.
    private var emptyShelf: some View {
        Shelf("Doelen", showAll: .goals, showAllLabel: "Toon alle doelen",
              items: [GalleryTile(id: 0, title: "", symbol: "flag.checkered", hue: .mustard, subtitle: nil, value: "", progress: nil)]) { _ in
            ShelfCard(hue: .mustard, destination: .savingsGoal) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text("Maak je eerste doel")
                        .font(.subheadline.weight(.semibold))
                    Text("Zie hoe ver je bent.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.onTileSecondary)
                }
            }
        }
    }

    // MARK: Zoeken, pillen en kleuren

    private var browseSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(PageCatalog.browsePages.prefix(4)) { info in
                BrowseTile(title: info.title, symbol: info.symbol, hue: info.hue, destination: info.destination)
            }
        }
        .padding(.horizontal, margin)
    }

    private var pillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PillRow {
                PillButton("Storten", symbol: "plus", style: .prominent, action: {})
                PillButton("Opnemen", symbol: "minus", action: {})
                PillButton("Bewerken", action: {})
            }
            PillRow {
                PillButton("Verwijderen", symbol: "trash", role: .destructive, action: {})
                PillLink("Naar Inkomen", destination: .income)
            }
        }
        .padding(.horizontal, margin)
    }

    private var huesSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
            ForEach(TileHue.allCases) { hue in
                ArtworkTile(symbol: "tray.full", hue: hue, size: .fill, progress: 0.5)
            }
        }
        .padding(.horizontal, margin)
    }

    private var backdropSection: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TileHue.allCases) { hue in
                    BackdropGradient(hue: hue)
                        .frame(width: 96, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                }
            }
            .padding(.horizontal, margin)
        }
        .scrollIndicators(.hidden)
    }
}
#endif
