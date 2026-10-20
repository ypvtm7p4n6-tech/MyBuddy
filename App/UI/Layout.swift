import SwiftUI

// Indelingen van het ontwerpsysteem: even grote blokken, rijen met tegels en rijen met een label en een bedrag.
// Alles hier stapelt bij toegankelijkheidsformaten van Dynamic Type en krimpt nooit tekst.

// MARK: - Even grote blokken

/// Legt blokken in kolommen. Elk blok is even breed én even hoog (zo hoog als het hoogste blok).
/// Het aantal kolommen volgt de beschikbare breedte: één op een iPhone, meer op iPad en Mac.
struct EqualSizeGrid: Layout {
    var minimumColumnWidth: CGFloat = 340
    var spacing: CGFloat = Theme.pageSpacing

    private func columns(for width: CGFloat, items: Int) -> Int {
        guard items > 0 else { return 1 }
        let fit = SafeInt.clamped(Double(((width + spacing) / (minimumColumnWidth + spacing)).rounded(.down)), to: 1...64)
        return max(1, min(items, fit))
    }

    private func usableWidth(_ proposal: ProposedViewSize) -> CGFloat {
        guard let w = proposal.width, w.isFinite, w > 0 else { return minimumColumnWidth }
        return w
    }

    private func cellSize(width: CGFloat, subviews: Subviews) -> (columns: Int, cellWidth: CGFloat, cellHeight: CGFloat) {
        let cols = columns(for: width, items: subviews.count)
        let cellWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let tallest = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }
            .max() ?? 0
        return (cols, cellWidth, tallest)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = usableWidth(proposal)
        let cell = cellSize(width: width, subviews: subviews)
        let rows = Int((Double(subviews.count) / Double(cell.columns)).rounded(.up))
        let height = CGFloat(rows) * cell.cellHeight + CGFloat(max(0, rows - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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

/// Een rij tegels (`StatTile`) die even groot zijn. Ze staan naast elkaar zolang ze passen en komen onder elkaar bij grote
/// tekst of op een smal scherm: de kolombreedte schaalt mee met Dynamic Type.
struct FigureRow<Content: View>: View {
    let spacing: CGFloat
    private let content: Content
    @ScaledMetric(relativeTo: .body) private var columnMinimum: CGFloat = 104

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        EqualSizeGrid(minimumColumnWidth: columnMinimum, spacing: spacing) {
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
