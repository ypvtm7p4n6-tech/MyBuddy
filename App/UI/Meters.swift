import SwiftUI

// Voortgangsmeters van het ontwerpsysteem. Elke meter heeft een label en een waardetekst voor VoiceOver, zodat de
// voortgang nooit alleen uit kleur en lengte bestaat. De waarde komt van de aanroeper (rekenmotor): hier wordt niets
// uitgerekend, alleen getekend.

/// Een balk of ring die laat zien hoever iets is. `value` is een breuk (0...1); `nil` betekent "geen doel" en tekent niets.
struct ProgressMeter: View {
    enum Style {
        case bar(height: CGFloat = 8)
        case ring(lineWidth: CGFloat = 7)
    }

    let value: Double?
    let tint: Color
    let style: Style
    let label: String
    let valueText: String

    init(value: Double?, tint: Color, style: Style, label: String, valueText: String) {
        self.value = value
        self.tint = tint
        self.style = style
        self.label = label
        self.valueText = valueText
    }

    var body: some View {
        if let value {
            meter(progress: Self.clamped(value))
                .animated(by: value)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
        }
    }

    /// De breuk binnen 0...1; NaN telt als 0 en oneindig als 0 of 1.
    private static func clamped(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        if value.isInfinite { return value > 0 ? 1 : 0 }
        return min(1, max(0, value))
    }

    @ViewBuilder
    private func meter(progress: Double) -> some View {
        switch style {
        case .bar(let height):
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.22))
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(height: height)
        case .ring(let lineWidth):
            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(tint.opacity(0.22), lineWidth: lineWidth)
                if progress > 0 {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }
}

/// Eén balk die in stukken is verdeeld, bijvoorbeeld hoe je inkomen over uitgaven, sparen en overgehouden geld gaat. De
/// stukken staan met een tussenruimte naast elkaar (geen kleur alleen); de titels en bedragen horen in de rijen eronder.
struct SegmentedMeter: View {
    struct Segment: Identifiable {
        let id: String
        let title: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let label: String
    let valueText: String

    init(segments: [Segment], label: String, valueText: String) {
        self.segments = segments
        self.label = label
        self.valueText = valueText
    }

    var body: some View {
        let positive = segments.filter { $0.value > 0 && $0.value.isFinite }
        let total = max(positive.reduce(0) { $0 + $1.value }, 0.0001)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(positive) { segment in
                    Capsule()
                        .fill(segment.color)
                        .frame(width: segmentWidth(segment.value, total: total, count: positive.count, width: geo.size.width))
                }
                if positive.isEmpty {
                    Capsule().fill(Theme.tileFill)
                }
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
        .animated(by: positive.map { $0.value })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
    }

    private func segmentWidth(_ value: Double, total: Double, count: Int, width: CGFloat) -> CGFloat {
        let gaps = CGFloat(max(0, count - 1)) * 2
        let share = CGFloat(value / total)
        return max(4, (width - gaps) * share)
    }
}
