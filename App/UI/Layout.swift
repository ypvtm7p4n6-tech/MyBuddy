import SwiftUI

// Indelingen van het ontwerpsysteem: rijen met tegels en rijen met een label en een bedrag.
// Alles hier stapelt bij toegankelijkheidsformaten van Dynamic Type en krimpt nooit tekst.

// MARK: - Tegels naast elkaar

private struct TileFillsHeightKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Tegels in een `FigureRow` vullen de hoogte van hun cel, zodat ze even hoog zijn. Elders (in een `HStack`, in een kaart
    /// in een raster) vult een tegel alleen zijn eigen inhoud en rekt hij niet mee.
    var tileFillsHeight: Bool {
        get { self[TileFillsHeightKey.self] }
        set { self[TileFillsHeightKey.self] = newValue }
    }
}

/// Legt tegels in kolommen die even breed en even hoog zijn. Een tegel is minstens zo breed als hij nodig heeft om zijn bedrag
/// op één regel te zetten (een bedrag breekt nooit midden in het getal af); een lange tekst, zoals een bijschrift, telt
/// maar tot 1,4 keer de kleinste breedte mee en mag wrappen. Het aantal kolommen is het grootste aantal dat past en
/// het aantal tegels zonder rest deelt: drie tegels staan naast elkaar of onder elkaar, niet twee plus één.
private struct TileGridLayout: Layout {
    var spacing: CGFloat
    /// De kleinste kolombreedte; schaalt mee met Dynamic Type.
    var minimumWidth: CGFloat

    /// De breedte die een tegel nodig heeft: de ideale breedte van de breedste tegel, begrensd.
    private func neededWidth(_ subviews: Subviews) -> CGFloat {
        var widest: CGFloat = 0
        for subview in subviews {
            widest = max(widest, subview.sizeThatFits(.unspecified).width)
        }
        return max(minimumWidth, min(widest, minimumWidth * 1.4))
    }

    private func columns(width: CGFloat, count: Int, needed: CGFloat) -> Int {
        guard count > 1 else { return 1 }
        var candidate = SafeInt.clamped(Double(((width + spacing) / (needed + spacing)).rounded(.down)), to: 1...count)
        while candidate > 1 {
            if count % candidate == 0 { return candidate }
            candidate -= 1
        }
        return 1
    }

    private func cellSize(width: CGFloat, subviews: Subviews) -> (columns: Int, cellWidth: CGFloat, cellHeight: CGFloat) {
        let cols = columns(width: width, count: subviews.count, needed: neededWidth(subviews))
        let cellWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        var tallest: CGFloat = 0
        for subview in subviews {
            tallest = max(tallest, subview.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height)
        }
        return (cols, cellWidth, tallest)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        // Zonder breedte (bijvoorbeeld bij het meten door `ViewThatFits`) staan alle tegels op een rij.
        var width = neededWidth(subviews) * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1)
        if let proposed = proposal.width, proposed.isFinite, proposed > 0 { width = proposed }
        let cell = cellSize(width: width, subviews: subviews)
        let rows = (subviews.count + cell.columns - 1) / cell.columns
        let height = CGFloat(rows) * cell.cellHeight + CGFloat(max(0, rows - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let cell = cellSize(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let row = index / cell.columns
            let column = index % cell.columns
            let origin = CGPoint(x: bounds.minX + CGFloat(column) * (cell.cellWidth + spacing),
                                 y: bounds.minY + CGFloat(row) * (cell.cellHeight + spacing))
            subview.place(at: origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: cell.cellWidth, height: cell.cellHeight))
        }
    }
}

/// Een rij tegels (`StatTile`) die even groot zijn. Ze staan naast elkaar zolang ze passen en komen onder elkaar bij grote
/// tekst, een smal scherm of een bedrag dat niet op een regel past: de kolombreedte schaalt mee met Dynamic Type.
struct FigureRow<Content: View>: View {
    let spacing: CGFloat
    private let content: Content
    @ScaledMetric(relativeTo: .body) private var columnMinimum: CGFloat = 104

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        TileGridLayout(spacing: spacing, minimumWidth: columnMinimum) {
            content
        }
        .environment(\.tileFillsHeight, true)
    }
}

// MARK: - Een rij met label en bedrag

/// Een rij met een label links en een bedrag rechts, eventueel met een regel uitleg eronder. Past het niet naast elkaar
/// (of staat Dynamic Type op een toegankelijkheidsformaat), dan staat het bedrag onder het label. Eén element voor VoiceOver.
struct AmountRow: View {
    let title: String
    let value: String
    var detail: String? = nil
    var color: Color = .primary
    var symbol: String? = nil
    var bold: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    labelColumn
                    valueText
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        labelColumn
                        Spacer(minLength: 8)
                        valueText
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        labelColumn
                        valueText
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.body)
            }
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var valueText: some View {
        Text(value)
            .font(.body.weight(bold ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .contentTransition(.numericText())
            .animated(by: value)
    }
}
