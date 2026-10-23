#if DEBUG
import SwiftUI

// Alle onderdelen van het ontwerpsysteem op een pagina, voor de Xcode-canvas (alleen in een debug-build). De previews staan
// in licht, donker en bij grote tekst (`.accessibility3`); "Verhoog contrast" laat zich niet in code instellen: zet het in
// de canvas aan bij Environment Overrides (daar krijgt een kaart zijn rand en worden de kleuren sterker). De tegels, planken,
// hero, bladertegels, pillen en tinten van ontwerp 2 staan in `TileGallery` (onderaan deze pagina); de rijen en de albumkop in
// `ComponentListGallery`. Aparte previews van die onderdelen staan in `DesignPreviews.swift`.

/// Een kleurvlak met naam, voor het overzicht van de tokens.
private struct Swatch: View {
    let name: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .fill(color)
                .aspectRatio(2, contentMode: .fit)
            Text(name)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// De kaarten van het ontwerpsysteem op een pagina van kaarten (`PageScaffold`).
struct ComponentGallery: View {
    @State private var month = YearMonth.current()
    @State private var amount = 1250.0
    @State private var showsSheet = false

    var body: some View {
        PageScaffold(title: "Componenten", large: true, fullBleed: true) {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                cards
                TileGallery()
            }
        }
        .sheet(isPresented: $showsSheet) {
            SheetScaffold(title: "Voorbeeldblad", hasChanges: amount != 1250, onSave: {}) {
                NumberRow(title: "Bedrag", value: $amount)
                ChoiceRow(title: "Keuze", detail: "Een uitleg bij de keuze", isSelected: true, action: {})
            }
        }
    }

    /// De kaarten van het oorspronkelijke ontwerpsysteem, met de paginamarge (de pagina is hier `fullBleed`).
    private var cards: some View {
        VStack(spacing: Theme.pageSpacing) {
            colorsCard
            numbersCard
            metersCard
            buttonsCard
            linkCard
            hintsCard
            periodCard
        }
        .padding(.horizontal, CGFloat(ShelfMetrics.margin(compact: true)))
    }

    private var colorsCard: some View {
        Card(title: "Kleuren", symbol: "paintpalette", domain: .overview) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                Swatch(name: "accent", color: Theme.accent)
                Swatch(name: "positief", color: Theme.positive)
                Swatch(name: "negatief", color: Theme.negative)
                Swatch(name: "waarschuwing", color: Theme.warning)
                Swatch(name: "uitgaven", color: Theme.chartExpenses)
                Swatch(name: "variabel", color: Theme.chartVariable)
                Swatch(name: "gespaard", color: Theme.chartSaved)
                Swatch(name: "belegd", color: Theme.chartInvested)
                Swatch(name: "over", color: Theme.chartFree)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(AppDomain.allCases) { domain in
                    VStack(spacing: 4) {
                        SymbolBadge(symbol: domain.symbol, color: domain.color)
                        Text(domain.title)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var numbersCard: some View {
        Card(title: "Cijfers", symbol: "number", domain: .money, subtitle: "Bedragen, tegels en rijen") {
            BigAmount(value: 1234.5, label: "Nog te verdelen")
            FigureRow {
                StatTile(title: "Inkomen", value: Fmt.euro(3200))
                StatTile(title: "Uitgaven", value: Fmt.euro(1850), caption: "Vast en variabel")
                StatTile(title: "Overgehouden", value: Fmt.euro(1350), color: Theme.positive)
            }
            AmountRow(title: "Bankrekening", value: Fmt.euro(4200), symbol: "building.columns")
            AmountRow(title: "Tekort", value: "-" + Fmt.euro(80), detail: "Dit gaat van je saldo af", color: Theme.negative, bold: true)
        }
    }

    private var metersCard: some View {
        Card(title: "Voortgang", symbol: "chart.bar", domain: .saving) {
            ProgressMeter(value: 0.4, tint: Theme.chartSaved, style: .bar(), label: "Voortgang", valueText: "40%")
            ProgressMeter(value: 0.005, tint: Theme.chartSaved, style: .bar(height: 12), label: "Voortgang", valueText: "0,5%")
            HStack(spacing: Theme.rowSpacing) {
                ProgressMeter(value: 0.72, tint: Theme.chartInvested, style: .ring(), label: "Doel", valueText: "72%")
                    .frame(width: 64, height: 64)
                ProgressMeter(value: nil, tint: Theme.chartInvested, style: .ring(), label: "Doel", valueText: "geen doel")
                    .frame(width: 64, height: 64)
            }
            SegmentedMeter(
                segments: [
                    SegmentedMeter.Segment(id: "e", title: "Uitgaven", value: 1850, color: Theme.chartExpenses),
                    SegmentedMeter.Segment(id: "s", title: "Gespaard", value: 600, color: Theme.chartSaved),
                    SegmentedMeter.Segment(id: "i", title: "Belegd", value: 400, color: Theme.chartInvested),
                    SegmentedMeter.Segment(id: "f", title: "Over", value: 350, color: Theme.chartFree)
                ],
                label: "Waar gaat je geld heen", valueText: "Uitgaven 58%, gespaard 19%, belegd 12%, over 11%")
        }
    }

    private var buttonsCard: some View {
        Card(title: "Knoppen", symbol: "hand.tap", domain: .tools) {
            ActionGroup {
                ActionButton(title: "Bewaar", symbol: "checkmark", prominent: true, action: {})
                ActionButton(title: "Annuleer", action: {})
            }
            ActionButton(title: "Verwijderen", symbol: "trash", role: .destructive, action: {})
            ActionLink(title: "Naar Inkomen", symbol: "eurosign.circle", destination: .income)
            HStack {
                IconButton("Zoeken", symbol: "magnifyingglass", action: {})
                IconButton("Verwijderen", symbol: "trash", role: .destructive, action: {})
                ActionButton(title: "Toon een blad", action: { showsSheet = true })
            }
        }
    }

    private var linkCard: some View {
        LinkCard(title: "Inkomen", symbol: "eurosign.circle", domain: .money, subtitle: "Deze maand", destination: .income) {
            AmountRow(title: "Salaris", value: Fmt.euro(3200))
        }
    }

    private var hintsCard: some View {
        Card(title: "Meldingen en lege staten", symbol: "exclamationmark.bubble", domain: .settings) {
            NoticeCard(text: "Opslaan is mislukt. Je laatste wijzigingen zijn mogelijk niet bewaard.",
                       symbol: "exclamationmark.triangle.fill", actionTitle: "Opnieuw proberen", action: {})
            EmptyHint(symbol: "tray", title: "Nog geen spaarpotten", message: "Maak een pot voor iets waar je voor spaart.",
                      actionTitle: "Spaarpot maken", action: {})
        }
    }

    private var periodCard: some View {
        VStack(spacing: Theme.rowSpacing) {
            MonthBar(month: $month)
            PeriodPicker()
        }
    }
}

/// De rijen van het ontwerpsysteem in een lijstpagina (`ListScaffold`).
struct ComponentListGallery: View {
    var body: some View {
        ListScaffold(title: "Lijsten") {
            Section {
                AmountRow(title: "Salaris", value: Fmt.euro(3200))
                    .rowActions(edit: {}, delete: {}, extra: [RowAction("Kopieer", symbol: "doc.on.doc", action: {})])
                AmountRow(title: "Overige inkomsten", value: Fmt.euro(150), detail: "Eenmalig")
                    .rowActions(edit: {}, delete: {})
            } header: {
                SectionHeader("Rijen", domain: .money)
            }
            Section {
                AlbumHeader(symbol: "airplane", hue: .terracotta, title: "Vakantie", subtitle: "Spaarpot, doel € 5.000,00",
                            figureLabel: "Saldo vandaag", figure: 1_250, progress: 0.25,
                            facts: ["Rente 2,0% per jaar", "Inleg € 100,00 per maand"]) {
                    PillRow(alignment: .center) {
                        PillButton("Storten", symbol: "plus", style: .prominent, action: {})
                        PillButton("Opnemen", symbol: "minus", action: {})
                    }
                }
                .albumHeaderRow()
            }
            Section {
                AlbumHeader(symbol: "chart.line.uptrend.xyaxis", hue: .slate, title: "Wereldfonds", subtitle: "ETF, VWCE.DE",
                            figureLabel: "Waarde", figure: 12_480, facts: ["Belegd sinds maart 2024"],
                            pills: {
                    PillRow(alignment: .center) {
                        PillButton("Waarde bijwerken", style: .prominent, action: {})
                        PillButton("Bewerken", action: {})
                    }
                }, extra: {
                    Label("Winst € 1.480,00 (+13,5%)", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.positive)
                })
                .albumHeaderRow()
            }
            Section {
                MediaRow(symbol: "tray.full", hue: .teal, title: "Spaarpotten", subtitle: "3 potten", value: "€ 6.240,00",
                         destination: .pots)
                MediaRow(symbol: "flag.checkered", hue: .mustard, title: "Doelen", subtitle: "2 van 3 haalbaar",
                         progress: 0.4, destination: .goals)
                MediaRow(symbol: "building.columns", hue: .terracotta, title: "Bankrekening",
                         value: "-€ 120,00", valueColor: Theme.negative, destination: .bank, showsCurrentMonth: true)
            } header: {
                SectionHeader("Bibliotheek")
            }
            Section {
                NavigationRow(title: "Account", symbol: "person.crop.circle", domain: .settings,
                              value: "Aan", subtitle: "Gesynchroniseerd om 14:02", destination: .settings(.account))
                NavigationRow(title: "Rekenen", symbol: "percent", domain: .settings, destination: .settings(.calculations))
            } header: {
                SectionHeader("Instellingen", domain: .settings)
            }
        }
    }
}

/// Maakt een winkel met voorbeelddata en een router voor de previews (ook die van `DesignPreviews.swift`).
@MainActor
struct GalleryHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        let sampleStore = AppStore(storage: nil)
        sampleStore.loadSampleData()
        _store = State(initialValue: sampleStore)
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
        }
        .environment(store)
        .environment(router)
    }
}

#Preview("Componenten, licht") {
    GalleryHost { ComponentGallery() }
        .preferredColorScheme(.light)
}

#Preview("Componenten, donker") {
    GalleryHost { ComponentGallery() }
        .preferredColorScheme(.dark)
}

#Preview("Componenten, grote tekst") {
    GalleryHost { ComponentGallery() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Componenten, hoog contrast (zet Verhoog contrast aan in de canvas)") {
    GalleryHost { ComponentGallery() }
}

#Preview("Lijsten, licht") {
    GalleryHost { ComponentListGallery() }
        .preferredColorScheme(.light)
}

#Preview("Lijsten, donker") {
    GalleryHost { ComponentListGallery() }
        .preferredColorScheme(.dark)
}

#Preview("Lijsten, grote tekst") {
    GalleryHost { ComponentListGallery() }
        .dynamicTypeSize(.accessibility3)
}
#endif
