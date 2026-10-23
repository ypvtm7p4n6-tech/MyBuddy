import SwiftUI

// De kop van een albumpagina (Apple Muziek): een groot artwork, de titel, een ondertitel, het kerngetal, een paar feiten en de
// pillen. Hij is de eerste rij van de bestaande `List` van een spaarpot, belegging of doel (`albumHeaderRow()`), met de
// bestaande secties als tracklijst eronder. Breed (vanaf 560 punten) staat het artwork links en de tekst rechts.

/// De kop van een spaarpot-, beleggings- of doelpagina. Het kopartwork is versiering; de titel en het kerngetal zijn koppen voor
/// VoiceOver. Een prominente pil per pagina (de ene hoofdactie); verwijderen staat onderaan de pagina, niet hier.
struct AlbumHeader<Pills: View, Extra: View>: View {
    let symbol: String
    let hue: TileHue
    let title: String
    let subtitle: String?
    let figureLabel: String?
    let figure: Double?
    let figureColor: Color
    let progress: Double?
    let progressLabel: String?
    let facts: [String]
    private let pills: Pills
    private let extra: Extra

    init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, figureLabel: String? = nil,
         figure: Double? = nil, figureColor: Color = .primary, progress: Double? = nil, progressLabel: String? = nil,
         facts: [String] = [], @ViewBuilder pills: () -> Pills, @ViewBuilder extra: () -> Extra) {
        self.symbol = symbol
        self.hue = hue
        self.title = title
        self.subtitle = subtitle
        self.figureLabel = figureLabel
        self.figure = figure
        self.figureColor = figureColor
        self.progress = progress
        self.progressLabel = progressLabel
        self.facts = facts
        self.pills = pills()
        self.extra = extra()
    }

    var body: some View {
        // De marge van 16 aan beide kanten telt mee: de brede opstelling vraagt 528 punten, dus een rij van 560 of breder.
        ViewThatFits(in: .horizontal) {
            wideLayout
                .frame(minWidth: 528)
            compactLayout
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: Opstellingen

    /// Breed (iPad en Mac): artwork links, tekst rechts.
    private var wideLayout: some View {
        HStack(alignment: .bottom, spacing: 20) {
            ArtworkTile(symbol: symbol, hue: hue, size: .header)
            VStack(alignment: .leading, spacing: 8) {
                titleBlock(alignment: .leading)
                figureBlock(alignment: .leading)
                progressBar
                factsBlock(alignment: .leading)
                PillRow(alignment: .leading) { pills }
                extra
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Smal (iPhone): alles gecentreerd onder elkaar.
    private var compactLayout: some View {
        VStack(spacing: 14) {
            ArtworkTile(symbol: symbol, hue: hue, size: .header)
            VStack(spacing: 6) {
                titleBlock(alignment: .center)
                figureBlock(alignment: .center)
            }
            progressBar
            factsBlock(alignment: .center)
            PillRow(alignment: .center) { pills }
            extra
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Onderdelen

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(textAlignment(alignment))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(textAlignment(alignment))
            }
        }
    }

    @ViewBuilder
    private func figureBlock(alignment: HorizontalAlignment) -> some View {
        if let figure {
            VStack(alignment: alignment, spacing: 2) {
                if let figureLabel {
                    Text(figureLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                BigAmount(value: figure, font: Theme.heroAmount, color: figureColor, label: figureLabel)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress {
            ProgressMeter(value: progress, tint: Theme.color(hue.rawValue), style: .bar(height: 8),
                          label: progressLabel ?? "Voortgang", valueText: Fmt.percent(progress, digits: 0))
                .frame(maxWidth: 320)
        }
    }

    @ViewBuilder
    private func factsBlock(alignment: HorizontalAlignment) -> some View {
        if !facts.isEmpty {
            VStack(alignment: alignment, spacing: 2) {
                ForEach(facts, id: \.self) { fact in
                    Text(fact)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(textAlignment(alignment))
                }
            }
        }
    }

    private func textAlignment(_ alignment: HorizontalAlignment) -> TextAlignment {
        alignment == .center ? .center : .leading
    }
}

extension AlbumHeader where Extra == EmptyView {
    init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, figureLabel: String? = nil,
         figure: Double? = nil, figureColor: Color = .primary, progress: Double? = nil, progressLabel: String? = nil,
         facts: [String] = [], @ViewBuilder pills: () -> Pills) {
        self.init(symbol: symbol, hue: hue, title: title, subtitle: subtitle, figureLabel: figureLabel, figure: figure,
                  figureColor: figureColor, progress: progress, progressLabel: progressLabel, facts: facts,
                  pills: pills, extra: { EmptyView() })
    }
}

extension View {
    /// Maakt van de kop een rij zonder achtergrond, scheidingslijn en inspringing: de eerste rij van de `List` van een
    /// albumpagina. De kop heeft zijn eigen marge.
    func albumHeaderRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
