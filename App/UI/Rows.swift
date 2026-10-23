import SwiftUI

// De lijstrij van ontwerp 2 (Apple Muziek: tracklijsten en de Bibliotheek): een klein artwork links, titel en ondertitel, een
// waarde rechts en een pijltje. Eén tikdoel per rij. De rij is een element voor VoiceOver; het artwork is versiering.

/// De inhoud van een rij: artwork (44 punten, schaalt mee), titel, ondertitel, waarde en eventueel een pijltje en een
/// voortgangsbalk. Gebruik dit binnen een eigen knop of link, of `MediaRow` voor een rij die naar een pagina leidt. Bij
/// toegankelijkheidsformaten staat de waarde onder de titel.
struct MediaRowLabel: View {
    let symbol: String
    let hue: TileHue
    let title: String
    let subtitle: String?
    let value: String?
    let valueColor: Color
    let progress: Double?
    let showsChevron: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, value: String? = nil,
         valueColor: Color = .primary, progress: Double? = nil, showsChevron: Bool = false) {
        self.symbol = symbol
        self.hue = hue
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.valueColor = valueColor
        self.progress = progress
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkTile(symbol: symbol, hue: hue, size: .row)
            textColumn
            Spacer(minLength: 8)
            trailingValue
            chevron
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Onderdelen

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            if typeSize.isAccessibilitySize {
                valueText
            }
            meter
        }
    }

    @ViewBuilder
    private var trailingValue: some View {
        if !typeSize.isAccessibilitySize {
            valueText
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if let value {
            Text(value)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var meter: some View {
        if let progress {
            ProgressMeter(value: progress, tint: Theme.color(hue.rawValue), style: .bar(height: 4),
                          label: "Voortgang", valueText: Fmt.percent(progress, digits: 0))
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if showsChevron {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
    }
}

/// Een rij in een `List` die naar een pagina leidt: `MediaRowLabel` in een `DestinationLink`. Met `showsCurrentMonth` zet een tik
/// eerst de maandpagina's op de huidige maand (Bibliotheek en Home). De link tekent zelf een pijltje in een lijst; als knop
/// (met `showsCurrentMonth`) doet het label dat.
struct MediaRow: View {
    let symbol: String
    let hue: TileHue
    let title: String
    let subtitle: String?
    let value: String?
    let valueColor: Color
    let progress: Double?
    let destination: Destination
    let showsCurrentMonth: Bool

    init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, value: String? = nil,
         valueColor: Color = .primary, progress: Double? = nil, destination: Destination,
         showsCurrentMonth: Bool = false) {
        self.symbol = symbol
        self.hue = hue
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.valueColor = valueColor
        self.progress = progress
        self.destination = destination
        self.showsCurrentMonth = showsCurrentMonth
    }

    var body: some View {
        DestinationLink(destination: destination, showsCurrentMonth: showsCurrentMonth) { isButton in
            MediaRowLabel(symbol: symbol, hue: hue, title: title, subtitle: subtitle, value: value,
                          valueColor: valueColor, progress: progress, showsChevron: isButton)
        }
    }
}
