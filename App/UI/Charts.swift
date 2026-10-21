import SwiftUI
import Charts
import Accessibility

// Dé grafieklaag van de app (docs/design/plan.md par. 5.3). Drie componenten tekenen alleen een model uit `ChartModels.swift`:
//
//   TrendChart        lijn en vlak, met een afgeleid en een verwacht deel, markeringen en een lege staat
//   StackedBarChart   gestapelde staven per maand met een inkomenslijn
//   DonutChart        een ring met een lijst met bedrag en percentage eronder
//
// Een pagina schrijft dus geen reeksen, assen, lege staten of VoiceOver-teksten meer zelf. De assen worden altijd zelf aangestuurd
// (vast domein, unieke labels), een grafiek zonder gegevens is een lege staat met een actie (nooit een lege `Chart`), elke
// reeks heeft naast kleur een lijnstijl en een symbool, en elk onderdeel heeft een beschrijving voor VoiceOver. De annotatie bij een
// gekozen punt is `Theme.card` met een rand: de eigen code tekent geen glas. Onderaan staan de oude grafiektypen als overgangsvorm
// tot de pagina's zijn aangesloten (golf 1c).

// MARK: - Kleur, lijnstijl en symbool

extension ChartRole {
    /// De kleur van een rol: alleen tokens uit `Theme` (par. 4.2), nooit een eigen kleur per grafiek.
    var color: Color {
        switch self {
        case .primary: return Theme.accent
        case .secondary: return Theme.textSecondary
        case .tertiary: return Theme.chartInvested
        case .warning: return Theme.warning
        case .negative: return Theme.negative
        case .expenses: return Theme.chartExpenses
        case .variable: return Theme.chartVariable
        case .saved: return Theme.chartSaved
        case .invested: return Theme.chartInvested
        case .free: return Theme.chartFree
        }
    }
}

/// De namen van de waarden in een mark. Als `String`-constanten (en niet als tekstliteralen) kiest de compiler direct de goede
/// `PlottableValue.value`, in plaats van uit vier soorten tekst te moeten kiezen bij elke waarde van elke mark.
private enum ChartLabel {
    static let date = "Datum"
    static let base = "Basis"
    static let value = "Waarde"
    static let area = "Vlak"
    static let piece = "Stuk"
    static let chosen = "Gekozen"
    static let month = "Maand"
    static let amount = "Bedrag"
    static let kind = "Soort"
    static let income = "Inkomen"
}

/// De vorm van de lijnen en de symbolen, voor alle lijngrafieken gelijk.
private enum ChartStyle {
    /// Werkelijk: een volle lijn (of de stijl van de reeks); afgeleid: dun met korte stippen; verwacht: gestreept.
    static func stroke(kind: ChartPointKind, line: ChartLine) -> StrokeStyle {
        let width: CGFloat = line.isThin ? 1.5 : 2.5
        switch kind {
        case .estimated:
            return StrokeStyle(lineWidth: line.isThin ? 1.5 : 2, lineCap: .round, dash: [1, 4])
        case .projected:
            return StrokeStyle(lineWidth: line.isThin ? 1.5 : 2, dash: [6, 4])
        case .actual:
            switch line.dash {
            case .solid:
                return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            case .dashed:
                return StrokeStyle(lineWidth: width, dash: [6, 4])
            case .dotted:
                return StrokeStyle(lineWidth: width, lineCap: .round, dash: [1, 5])
            }
        }
    }

    /// De vorm van een symbool in de grafiek; een reeks zonder symbool krijgt een cirkel.
    static func shape(_ symbol: ChartSymbol?) -> BasicChartSymbolShape {
        switch symbol ?? .circle {
        case .circle: return .circle
        case .square: return .square
        case .triangle: return .triangle
        case .diamond: return .diamond
        }
    }

    /// Hetzelfde symbool als afbeelding, voor de legenda.
    static func symbolName(_ symbol: ChartSymbol?) -> String {
        switch symbol ?? .circle {
        case .circle: return "circle.fill"
        case .square: return "square.fill"
        case .triangle: return "triangle.fill"
        case .diamond: return "diamond.fill"
        }
    }

    /// Het label van een symbool staat boven of onder het punt, om en om, zodat twee labels elkaar minder raken.
    static func labelPosition(_ index: Int) -> AnnotationPosition {
        index % 2 == 0 ? .top : .bottom
    }
}

// MARK: - Lege staat

/// De lege staat van een grafiek: waarom er niets te tekenen valt en wat je kunt doen. Even hoog als de grafiek zelf (de pagina
/// springt niet); in het klein (`.compact`, Overzicht en Sparen) een regel. De knop staat er alleen als de pagina de actie afhandelt
/// (`onAction`): een knop die niets doet is erger dan geen knop, de tekst legt al uit wat je kunt doen.
struct ChartEmptyView: View {
    let empty: ChartEmpty
    let size: ChartSize
    let onAction: ((ChartEmpty.Action) -> Void)?

    init(empty: ChartEmpty, size: ChartSize = .regular, onAction: ((ChartEmpty.Action) -> Void)? = nil) {
        self.empty = empty
        self.size = size
        self.onAction = onAction
    }

    var body: some View {
        if size == .compact {
            compactLine
        } else {
            fullState
        }
    }

    private var fullState: some View {
        ContentUnavailableView {
            if empty.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(empty.title)
                }
            } else {
                Label(empty.title, systemImage: empty.symbol)
            }
        } description: {
            Text(empty.message)
        } actions: {
            actionButton
        }
        .frame(maxWidth: .infinity, minHeight: size.height)
    }

    private var compactLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                compactLabel
                Spacer(minLength: 8)
                actionButton
            }
            VStack(alignment: .leading, spacing: 4) {
                compactLabel
                actionButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactLabel: some View {
        HStack(spacing: 6) {
            if empty.isLoading {
                ProgressView()
            } else {
                Image(systemName: empty.symbol)
                    .accessibilityHidden(true)
            }
            Text(empty.title)
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    /// De knop van de lege staat: alleen als er een actie is, een titel en een pagina die de actie afhandelt.
    @ViewBuilder
    private var actionButton: some View {
        if let action = empty.action, let title = empty.actionTitle, let handler = onAction {
            ActionButton(title: title) { handler(action) }
        }
    }
}

// MARK: - Annotatie bij een gekozen punt

private struct ChartInfoRow: Identifiable {
    let id: String
    let label: String
    let value: String
}

/// De annotatie bij een gekozen punt of staaf: `Theme.card` met een rand van 1 pt (geen glas), met een titel en per regel een
/// naam en een bedrag. Alles erin staat ook zonder interactie als tekst (de samenvatting en het onderschrift).
private struct ChartInfoCard: View {
    let title: String
    let rows: [ChartInfoRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.label)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 4)
                    Text(row.value)
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: - VoiceOver

/// De beschrijving van een grafiek voor VoiceOver en de Audiografiek: titel, samenvatting en elk punt. De tekst komt uit het model.
private enum ChartDescriptorFactory {
    static func make(title: String, summary: String, data: ChartAccessibility, domain: ClosedRange<Double>,
                     showsCents: Bool) -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: data.xTitle, categoryOrder: data.categories)
        let yAxis = AXNumericDataAxisDescriptor(title: "Bedrag in euro", range: domain, gridlinePositions: []) { value in
            showsCents ? ChartText.price(value) : ChartText.euro(value)
        }
        var series: [AXDataSeriesDescriptor] = []
        for item in data.series {
            var points: [AXDataPoint] = []
            for point in item.points {
                points.append(AXDataPoint(x: point.category, y: point.value, additionalValues: [], label: point.label))
            }
            series.append(AXDataSeriesDescriptor(name: item.name, isContinuous: item.isContinuous, dataPoints: points))
        }
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: series)
    }

    /// Zet de nieuwe gegevens in de bestaande beschrijving: een grafiek die verandert, verandert ook zijn samenvatting.
    static func update(_ descriptor: AXChartDescriptor, with fresh: AXChartDescriptor) {
        descriptor.title = fresh.title
        descriptor.summary = fresh.summary
        descriptor.xAxis = fresh.xAxis
        descriptor.yAxis = fresh.yAxis
        descriptor.series = fresh.series
    }
}

private struct TrendDescriptor: AXChartDescriptorRepresentable {
    let model: TrendModel
    let domain: ClosedRange<Double>

    func makeChartDescriptor() -> AXChartDescriptor {
        ChartDescriptorFactory.make(title: model.title, summary: model.summary, data: model.accessibilityData,
                                    domain: domain, showsCents: model.showsCents)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        ChartDescriptorFactory.update(descriptor, with: makeChartDescriptor())
    }
}

private struct StackedBarDescriptor: AXChartDescriptorRepresentable {
    let model: StackedBarModel
    let domain: ClosedRange<Double>

    func makeChartDescriptor() -> AXChartDescriptor {
        ChartDescriptorFactory.make(title: "Waar gaat je geld heen", summary: model.summary, data: model.accessibilityData,
                                    domain: domain, showsCents: false)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        ChartDescriptorFactory.update(descriptor, with: makeChartDescriptor())
    }
}

private struct DonutDescriptor: AXChartDescriptorRepresentable {
    let model: DonutModel

    func makeChartDescriptor() -> AXChartDescriptor {
        let data = model.accessibilityData
        return ChartDescriptorFactory.make(title: "Verdeling van je beleggingen", summary: model.summary, data: data,
                                           domain: data.domain(includesZero: true), showsCents: false)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        ChartDescriptorFactory.update(descriptor, with: makeChartDescriptor())
    }
}

// MARK: - Lijn en vlak

/// Lijn en vlak voor alles wat door de tijd loopt: beleggingen, vermogen, saldo, schatting, buffer, spaardoel, versnellers en de
/// koers. Werkelijk is een volle lijn met een vlak, afgeleid een dunne lijn met korte stippen (zonder vlak), verwacht een
/// gestreepte lijn; een enkel werkelijk punt is een stip. Meer dan een lijn: elke lijn heeft zijn eigen lijnstijl en symbool, en
/// bij "Onderscheid zonder kleur" een label bij het laatste punt. Een tik of aanwijzer toont de waarden als tekst in een annotatie.
struct TrendChart: View {
    let model: TrendModel
    let size: ChartSize
    let showsAxes: Bool
    let nonNegative: Bool
    /// De afhandeling van de knop in de lege staat; zonder (`nil`) toont de lege staat alleen zijn tekst (zie `ChartEmptyView`).
    let onAction: ((ChartEmpty.Action) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @State private var selectedDate: Date?

    init(model: TrendModel, size: ChartSize = .regular, showsAxes: Bool = true, nonNegative: Bool = false,
         onAction: ((ChartEmpty.Action) -> Void)? = nil) {
        self.model = model
        self.size = size
        self.showsAxes = showsAxes
        self.nonNegative = nonNegative
        self.onAction = onAction
    }

    /// Dezelfde grafiek zonder het label `model:`.
    init(_ model: TrendModel, size: ChartSize = .regular, showsAxes: Bool = true, nonNegative: Bool = false,
         onAction: ((ChartEmpty.Action) -> Void)? = nil) {
        self.init(model: model, size: size, showsAxes: showsAxes, nonNegative: nonNegative, onAction: onAction)
    }

    // MARK: Opbouw

    var body: some View {
        if let empty = model.empty {
            ChartEmptyView(empty: empty, size: size, onAction: onAction)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chartView
                if showsLegend {
                    TrendLegend(lines: model.lines)
                }
                if showsTexts, let caption = model.caption {
                    Text(caption)
                        .font(.subheadline)
                }
                if showsTexts, let footnote = model.footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var chartView: some View {
        if allowsSelection {
            chart.chartXSelection(value: $selectedDate)
        } else {
            chart
        }
    }

    private var chart: some View {
        let range = domain
        let ticks = ChartAxis.ticks(in: range, count: size == .compact ? 3 : 4)
        let labels = ChartAxis.yLabels(ticks)
        return Chart {
            areaMarks(baseline: range.lowerBound)
            lineMarks
            markerMarks
            endMarks
            selectionMarks
        }
        .chartLegend(.hidden)
        .chartYScale(domain: range)
        .chartXScale(domain: model.xDomain)
        .modifier(TrendAxes(model: model, shown: showsAxes, ticks: ticks, labels: labels))
        .frame(height: size.height)
        .animation(reduceMotion ? nil : Theme.motion, value: model)
        .accessibilityChartDescriptor(TrendDescriptor(model: model, domain: range))
    }

    // MARK: Eigenschappen

    private var isCompact: Bool { size == .compact }
    /// In het klein (sparkline) is er geen interactie, geen legenda en geen tekst: de pagina zet de kernwaarden zelf ernaast.
    private var allowsSelection: Bool { !isCompact }
    private var showsTexts: Bool { !isCompact }
    private var showsLegend: Bool { !isCompact && model.lines.count > 1 }
    private var showsEndLabels: Bool { differentiate && !isCompact && model.lines.count > 1 }
    private var endSymbolSize: CGFloat { isCompact ? 36 : 56 }
    private var interpolation: InterpolationMethod { model.xAxis == .days ? .linear : .monotone }

    /// Het y-domein van het model, met extra ruimte erboven als er markeringen met een tekst staan.
    private var domain: ClosedRange<Double> {
        let base = model.domain(nonNegative: nonNegative)
        if isCompact || model.markers.isEmpty { return base }
        let headroom = (base.upperBound - base.lowerBound) * 0.12
        return base.lowerBound...(base.upperBound + headroom)
    }

    private var selection: TrendSelection? {
        guard allowsSelection, let chosen = selectedDate else { return nil }
        return model.selection(near: chosen)
    }

    private struct LineEnd: Identifiable {
        let id: String
        let line: ChartLine
        let point: ChartPoint
        let position: Int
    }

    /// Per lijn het punt waar zijn symbool staat: het laatste werkelijke of afgeleide punt.
    private var lineEnds: [LineEnd] {
        var result: [LineEnd] = []
        for (index, line) in model.lines.enumerated() {
            if let point = line.markerPoint {
                result.append(LineEnd(id: line.id, line: line, point: point, position: index))
            }
        }
        return result
    }

    private func areaSegments(of line: ChartLine) -> [ChartSegment] {
        if !line.fillsArea { return [] }
        return line.segments.filter { $0.kind == .actual && $0.points.count > 1 }
    }

    private func lineSegments(of line: ChartLine) -> [ChartSegment] {
        line.segments.filter { $0.points.count > 1 }
    }

    private func areaStyle(for line: ChartLine) -> LinearGradient {
        let color = line.role.color
        return LinearGradient(colors: [color.opacity(0.30), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
    }

    private func markerColor(_ marker: ChartMarker) -> Color {
        switch marker.kind {
        case .goal: return Theme.textSecondary
        case .zero: return Theme.negative
        case .low: return marker.value < 0 ? Theme.negative : Theme.textSecondary
        case .reached: return Theme.accent
        }
    }

    private func markerTextColor(_ marker: ChartMarker) -> Color {
        switch marker.kind {
        case .zero: return Theme.negative
        case .low: return marker.value < 0 ? Theme.negative : Theme.textSecondary
        case .goal, .reached: return Theme.textSecondary
        }
    }

    // MARK: Onderdelen van de grafiek

    /// Het vlak onder het werkelijke deel van een lijn (alleen bij lijnen met `fillsArea`, nooit onder een afgeleid of verwacht deel).
    @ChartContentBuilder
    private func areaMarks(baseline: Double) -> some ChartContent {
        ForEach(model.lines) { line in
            ForEach(areaSegments(of: line)) { segment in
                ForEach(segment.points) { point in
                    AreaMark(x: .value(ChartLabel.date, point.date),
                             yStart: .value(ChartLabel.base, baseline),
                             yEnd: .value(ChartLabel.value, point.value),
                             series: .value(ChartLabel.area, segment.id))
                        .foregroundStyle(areaStyle(for: line))
                        .interpolationMethod(interpolation)
                }
            }
        }
    }

    /// De lijnen, per stuk van dezelfde soort (de stukken sluiten op elkaar aan); een stuk van een punt is een stip en staat bij de symbolen.
    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(model.lines) { line in
            ForEach(lineSegments(of: line)) { segment in
                ForEach(segment.points) { point in
                    LineMark(x: .value(ChartLabel.date, point.date),
                             y: .value(ChartLabel.value, point.value),
                             series: .value(ChartLabel.piece, segment.id))
                        .foregroundStyle(line.role.color)
                        .lineStyle(ChartStyle.stroke(kind: segment.kind, line: line))
                        .interpolationMethod(interpolation)
                }
            }
        }
    }

    /// Doel, nul, laagste punt en "doel bereikt": altijd met een tekst, nooit alleen een kleur.
    @ChartContentBuilder
    private var markerMarks: some ChartContent {
        if !isCompact {
            ForEach(model.markers) { marker in
                if marker.date == nil {
                    RuleMark(y: .value(marker.label, marker.value))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(markerColor(marker))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text(marker.label)
                                .font(.caption)
                                .foregroundStyle(markerTextColor(marker))
                        }
                }
                if let date = marker.date {
                    PointMark(x: .value(ChartLabel.date, date), y: .value(marker.label, marker.value))
                        .symbol(.diamond)
                        .symbolSize(64)
                        .foregroundStyle(markerColor(marker))
                        .annotation(position: .bottom, spacing: 2) {
                            Text(marker.label)
                                .font(.caption)
                                .foregroundStyle(markerTextColor(marker))
                        }
                }
            }
        }
    }

    /// Het symbool van elke lijn bij zijn laatste punt, met bij "Onderscheid zonder kleur" de naam van de lijn erbij.
    @ChartContentBuilder
    private var endMarks: some ChartContent {
        ForEach(lineEnds) { end in
            PointMark(x: .value(ChartLabel.date, end.point.date), y: .value(ChartLabel.value, end.point.value))
                .symbol(ChartStyle.shape(end.line.symbol))
                .symbolSize(endSymbolSize)
                .foregroundStyle(end.line.role.color)
                .annotation(position: ChartStyle.labelPosition(end.position), spacing: 2) {
                    if showsEndLabels {
                        Text(end.line.name)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
        }
    }

    /// Het gekozen punt: een streep, een stip per lijn en de annotatie met de waarden.
    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let current = selection {
            RuleMark(x: .value(ChartLabel.chosen, current.date))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.primary.opacity(0.3))
                .annotation(position: .top, spacing: 4) {
                    ChartInfoCard(title: current.title, rows: infoRows(current))
                }
            ForEach(current.rows) { row in
                PointMark(x: .value(ChartLabel.date, row.date), y: .value(ChartLabel.value, row.value))
                    .symbol(ChartStyle.shape(row.symbol))
                    .symbolSize(72)
                    .foregroundStyle(row.role.color)
            }
        }
    }

    private func infoRows(_ chosen: TrendSelection) -> [ChartInfoRow] {
        var rows: [ChartInfoRow] = []
        for row in chosen.rows {
            rows.append(ChartInfoRow(id: row.id, label: row.name, value: row.text))
        }
        return rows
    }
}

/// De assen van alle lijngrafieken: y met eigen ticks en unieke labels, x met eigen maand-, dag- of tijdlabels. Zonder assen
/// (sparkline) verdwijnen ze allebei.
private struct TrendAxes: ViewModifier {
    let model: TrendModel
    let shown: Bool
    let ticks: [Double]
    let labels: [String]

    func body(content: Content) -> some View {
        if !shown {
            content
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        } else if let title = model.xAxisTitle {
            axes(content)
                .chartXAxisLabel {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
        } else {
            axes(content)
        }
    }

    private func axes(_ content: Content) -> some View {
        content
            .chartYAxis {
                AxisMarks(position: .leading, values: ticks) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(yLabel(number))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: model.xTicks) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(model.xLabel(date))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
    }

    /// Het label van de tick die het dichtst bij `value` ligt.
    private func yLabel(_ value: Double) -> String {
        var best = 0
        var distance = Double.infinity
        for (index, tick) in ticks.enumerated() {
            let d = abs(tick - value)
            if d < distance {
                best = index
                distance = d
            }
        }
        return labels.indices.contains(best) ? labels[best] : Fmt.compact(value)
    }
}

/// De legenda onder een grafiek met meer dan een lijn: een stukje lijn in de stijl van de reeks, zijn symbool en zijn naam. De
/// beschrijving voor VoiceOver noemt de reeksen al, dus de legenda zelf is voor VoiceOver verborgen.
private struct TrendLegend: View {
    let lines: [ChartLine]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                items
            }
            VStack(alignment: .leading, spacing: 4) {
                items
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var items: some View {
        ForEach(lines) { line in
            TrendLegendItem(line: line)
        }
    }
}

private struct TrendLegendItem: View {
    let line: ChartLine

    var body: some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 22, y: 5))
            }
            .stroke(line.role.color, style: ChartStyle.stroke(kind: .actual, line: line))
            .frame(width: 22, height: 10)
            Image(systemName: ChartStyle.symbolName(line.symbol))
                .imageScale(.small)
                .foregroundStyle(line.role.color)
            Text(line.name)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Gestapelde staven per maand

/// "Waar gaat je geld heen": per maand een staaf met uitgaven, gespaard, belegd en wat over is, met je inkomen als streep. Bij een
/// tekort steekt de staaf boven de streep uit. De volgorde van de soorten is vast; een tik toont de bedragen als tekst.
struct StackedBarChart: View {
    let model: StackedBarModel
    let size: ChartSize
    let showsAxes: Bool
    /// De afhandeling van de knop in de lege staat ("Salaris instellen"); zonder (`nil`) toont de lege staat alleen zijn tekst.
    let onAction: ((ChartEmpty.Action) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?

    init(model: StackedBarModel, size: ChartSize = .regular, showsAxes: Bool = true,
         onAction: ((ChartEmpty.Action) -> Void)? = nil) {
        self.model = model
        self.size = size
        self.showsAxes = showsAxes
        self.onAction = onAction
    }

    /// Dezelfde grafiek zonder het label `model:`.
    init(_ model: StackedBarModel, size: ChartSize = .regular, showsAxes: Bool = true,
         onAction: ((ChartEmpty.Action) -> Void)? = nil) {
        self.init(model: model, size: size, showsAxes: showsAxes, onAction: onAction)
    }

    var body: some View {
        if let empty = model.empty {
            ChartEmptyView(empty: empty, size: size, onAction: onAction)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chartView
                if size != .compact {
                    BarLegend(kinds: model.kinds)
                }
            }
        }
    }

    @ViewBuilder
    private var chartView: some View {
        if size != .compact {
            chart.chartXSelection(value: $selectedID)
        } else {
            chart
        }
    }

    private var chart: some View {
        let range = model.domain()
        let ticks = ChartAxis.ticks(in: range, count: size == .compact ? 3 : 4)
        let labels = ChartAxis.yLabels(ticks)
        let thickness = (range.upperBound - range.lowerBound) * 0.016
        return Chart {
            barMarks
            incomeMarks(thickness: thickness)
            selectionMarks
        }
        .chartForegroundStyleScale(domain: model.kinds.map { $0.title }, range: model.kinds.map { $0.role.color })
        .chartLegend(.hidden)
        .chartXScale(domain: model.entries.map { $0.id })
        .chartYScale(domain: range)
        .modifier(BarAxes(model: model, shown: showsAxes, ticks: ticks, labels: labels))
        .frame(height: size.height)
        .animation(reduceMotion ? nil : Theme.motion, value: model)
        .accessibilityChartDescriptor(StackedBarDescriptor(model: model, domain: range))
    }

    private var selectedEntry: BarEntry? {
        guard size != .compact, let chosen = selectedID else { return nil }
        return model.entry(for: chosen)
    }

    /// De staven: een blok per soort, in de vaste volgorde van het model; een verwachte maand is lichter.
    @ChartContentBuilder
    private var barMarks: some ChartContent {
        ForEach(model.bars) { bar in
            BarMark(x: .value(ChartLabel.month, bar.monthID), y: .value(ChartLabel.amount, bar.amount))
                .foregroundStyle(by: .value(ChartLabel.kind, bar.kind.title))
                .opacity(bar.isProjected ? 0.55 : 1)
                .cornerRadius(2)
        }
    }

    private struct IncomeBand: Identifiable {
        let id: String
        let monthID: String
        let low: Double
        let high: Double
    }

    /// De streep van het inkomen als een dun vlak om het bedrag heen, zo breed als de staaf. Een maand zonder inkomen heeft er geen.
    private func incomeBands(thickness: Double) -> [IncomeBand] {
        let half = thickness / 2
        var bands: [IncomeBand] = []
        for mark in model.incomeMarks where mark.income > 0 {
            bands.append(IncomeBand(id: mark.id, monthID: mark.monthID, low: mark.income - half, high: mark.income + half))
        }
        return bands
    }

    /// Je inkomen als dunne streep over de staaf van de maand: een tekort steekt erboven uit.
    @ChartContentBuilder
    private func incomeMarks(thickness: Double) -> some ChartContent {
        ForEach(incomeBands(thickness: thickness)) { band in
            BarMark(x: .value(ChartLabel.month, band.monthID),
                    yStart: .value(ChartLabel.income, band.low),
                    yEnd: .value(ChartLabel.income, band.high))
                .foregroundStyle(Color.primary)
                .zIndex(1)
        }
    }

    /// De gekozen maand: een streep en een annotatie met alle bedragen als tekst.
    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let entry = selectedEntry {
            RuleMark(x: .value(ChartLabel.month, entry.id))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.primary.opacity(0.25))
                .zIndex(-1)
                .annotation(position: .top, spacing: 4) {
                    ChartInfoCard(title: entry.isProjected ? entry.title + " (verwacht)" : entry.title,
                                  rows: infoRows(entry))
                }
        }
    }

    private func infoRows(_ entry: BarEntry) -> [ChartInfoRow] {
        var rows: [ChartInfoRow] = []
        for row in entry.detailRows {
            rows.append(ChartInfoRow(id: row.id, label: row.label, value: Fmt.euroWhole(row.value)))
        }
        return rows
    }
}

/// De assen van de staafgrafiek: y met eigen ticks en unieke labels, x met een label om de zoveel maanden.
private struct BarAxes: ViewModifier {
    let model: StackedBarModel
    let shown: Bool
    let ticks: [Double]
    let labels: [String]

    func body(content: Content) -> some View {
        if shown {
            content
                .chartYAxis {
                    AxisMarks(position: .leading, values: ticks) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(yLabel(number))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: model.tickIDs) { value in
                        AxisValueLabel {
                            if let id = value.as(String.self) {
                                Text(model.entry(for: id)?.label ?? "")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
        } else {
            content
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        }
    }

    private func yLabel(_ value: Double) -> String {
        var best = 0
        var distance = Double.infinity
        for (index, tick) in ticks.enumerated() {
            let d = abs(tick - value)
            if d < distance {
                best = index
                distance = d
            }
        }
        return labels.indices.contains(best) ? labels[best] : Fmt.compact(value)
    }
}

/// De legenda onder de staven: een blokje per soort in de kleur en de vaste naam, en de streep van het inkomen.
private struct BarLegend: View {
    let kinds: [FlowKind]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                items
            }
            VStack(alignment: .leading, spacing: 4) {
                items
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var items: some View {
        ForEach(kinds, id: \.self) { kind in
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(kind.role.color)
                    .frame(width: 10, height: 10)
                Text(kind.title)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        HStack(spacing: 6) {
            Capsule()
                .fill(Color.primary)
                .frame(width: 14, height: 3)
            Text("Inkomen")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Verdeling

/// Een ring met het totaal in het midden en eronder een lijst met naam, bedrag en percentage per soort. Elke soort heeft overal
/// dezelfde kleur (`HoldingKind.colorIndex`); de lijst is het tweede kanaal naast de kleur. Ook één soort is een volle ring.
struct DonutChart: View {
    let model: DonutModel
    let size: ChartSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: DonutModel, size: ChartSize = .regular) {
        self.model = model
        self.size = size
    }

    /// Dezelfde grafiek zonder het label `model:`.
    init(_ model: DonutModel, size: ChartSize = .regular) {
        self.init(model: model, size: size)
    }

    var body: some View {
        if let empty = model.empty {
            ChartEmptyView(empty: empty, size: size)
        } else {
            VStack(spacing: 12) {
                ring
                VStack(spacing: 8) {
                    ForEach(model.slices) { slice in
                        DonutRow(slice: slice)
                    }
                }
            }
        }
    }

    private var ring: some View {
        Chart(model.slices) { slice in
            SectorMark(angle: .value(ChartLabel.value, slice.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(Theme.color(slice.colorIndex))
        }
        .chartLegend(.hidden)
        .frame(height: size.height)
        .overlay {
            VStack(spacing: 0) {
                Text("Totaal")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(Fmt.euroWhole(model.total))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .animation(reduceMotion ? nil : Theme.motion, value: model)
        .accessibilityChartDescriptor(DonutDescriptor(model: model))
    }
}

/// Een regel onder de ring: de kleur van de soort, de naam, het bedrag en het percentage. Een element voor VoiceOver.
private struct DonutRow: View {
    let slice: DonutSlice

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                swatch
                Text(slice.name)
                Spacer(minLength: 8)
                figures
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    swatch
                    Text(slice.name)
                }
                figures
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var swatch: some View {
        Circle()
            .fill(Theme.color(slice.colorIndex))
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }

    private var figures: some View {
        HStack(spacing: 8) {
            Text(Fmt.euroWhole(slice.value))
                .monospacedDigit()
            Text(Fmt.percent(slice.share, digits: 0))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Overgangsvormen (tot de pagina's zijn aangesloten, golf 1c; pakket G verwijdert ze)

/// Toont de y-as met compacte euro-bedragen, of verbergt beide assen (voor kleine grafieken op Home).
private struct ChartAxesModifier: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        if shown {
            content.chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Fmt.compact(v))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        } else {
            content.chartXAxis(.hidden).chartYAxis(.hidden)
        }
    }
}

extension View {
    func chartAxes(shown: Bool) -> some View {
        modifier(ChartAxesModifier(shown: shown))
    }
}

struct TimePoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let value: Double
    let projected: Bool
}

extension TimePoint {
    init(_ p: PortfolioPoint) {
        self.init(id: p.id, date: p.month.firstDay, value: p.value, projected: p.isProjected)
    }

    init(_ p: BankPoint) {
        self.init(id: p.id, date: p.month.firstDay, value: p.balance, projected: p.isProjected)
    }
}

/// Lijn met vlak eronder. Verwachte punten staan gestippeld.
struct TimeLineChart: View {
    let points: [TimePoint]
    var tint: Color = Theme.accent
    var showsAxes = true
    var height: CGFloat = 160

    var body: some View {
        let actual = points.filter { !$0.projected }
        let bridge: [TimePoint] = actual.last.map { [$0] } ?? []
        let future = bridge + points.filter { $0.projected }

        Chart {
            ForEach(actual) { p in
                AreaMark(x: .value("Maand", p.date), y: .value("Waarde", p.value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Maand", p.date), y: .value("Waarde", p.value),
                         series: .value("Soort", "Werkelijk"))
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
            }
            if future.count > 1 {
                ForEach(future) { p in
                    LineMark(x: .value("Maand", p.date), y: .value("Waarde", p.value),
                             series: .value("Soort", "Verwacht"))
                        .foregroundStyle(tint.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                }
            }
            if actual.count == 1, let only = actual.first {
                PointMark(x: .value("Maand", only.date), y: .value("Waarde", only.value))
                    .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartAxes(shown: showsAxes)
        .frame(height: height)
        .animated(by: points)
    }
}

/// Gestapelde staven per maand: uitgaven, gespaard, belegd en wat over is.
struct FlowChart: View {
    let months: [MonthSummary]
    var height: CGFloat = 150
    var showsAxes = true

    static let kinds = ["Uitgaven", "Gespaard", "Belegd", "Over"]
    static let colors: [Color] = [Theme.chartExpenses, Theme.chartSaved, Theme.chartInvested, Theme.chartFree]

    private struct Item: Identifiable {
        let id: String
        let date: Date
        let kind: String
        let amount: Double
        let projected: Bool
    }

    private var items: [Item] {
        months.flatMap { s -> [Item] in
            // Alleen het deel van de uitgaven dat van je inkomen gaat. Wat uit een spaarpot wordt betaald
            // staat al in de pot en zou de balk hoger maken dan je inkomen.
            let fromIncome = max(0, s.expenses - s.fromPots)
            return [
                Item(id: s.id + "-u", date: s.month.firstDay, kind: "Uitgaven", amount: fromIncome, projected: s.isProjected),
                Item(id: s.id + "-g", date: s.month.firstDay, kind: "Gespaard", amount: s.saved, projected: s.isProjected),
                Item(id: s.id + "-b", date: s.month.firstDay, kind: "Belegd", amount: s.invested, projected: s.isProjected),
                Item(id: s.id + "-o", date: s.month.firstDay, kind: "Over", amount: max(0, s.remaining), projected: s.isProjected)
            ]
        }
    }

    var body: some View {
        Chart(items) { item in
            BarMark(x: .value("Maand", item.date, unit: .month),
                    y: .value("Bedrag", item.amount))
                .foregroundStyle(by: .value("Soort", item.kind))
                .opacity(item.projected ? 0.55 : 1)
        }
        .chartForegroundStyleScale(domain: FlowChart.kinds, range: FlowChart.colors)
        .chartAxes(shown: showsAxes)
        .chartLegend(showsAxes ? .automatic : .hidden)
        .frame(height: height)
        .animated(by: months)
    }
}

/// Verdeling over soorten beleggingen.
struct AllocationDonut: View {
    let slices: [KindSlice]
    var height: CGFloat = 150

    var body: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("Waarde", slice.value),
                       innerRadius: .ratio(0.62),
                       angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value("Soort", slice.kind.title))
        }
        .chartForegroundStyleScale(domain: slices.map { $0.kind.title },
                                   range: slices.indices.map { Theme.color($0) })
        .chartLegend(position: .trailing, alignment: .center)
        .frame(height: height)
        .animated(by: slices)
    }
}

// MARK: - Voorbeelden (alleen in Xcode)

#if DEBUG
/// Voorbeelddata voor de previews: de voorbeelddata van de app, een belegging die alleen uit je inleg is afgeleid en een lege start.
private enum ChartPreviewData {
    static let now = Date()
    static var current: YearMonth { YearMonth(date: now) }
    static var sample: FinanceData { FinanceData.sample(now: now) }
    static var empty: FinanceData { FinanceData(startMonth: current) }

    /// "Totaal ingelegd" 3.000, inleg 200 per maand, 8 maanden geleden begonnen, geen meetpunt: de afgeleide lijn.
    static var derived: FinanceData {
        var data = FinanceData(startMonth: current.adding(-8))
        data.materialize(upTo: current)
        data.addHolding(Holding(name: "Demo", kind: .etf, ticker: nil, units: nil, investedTotal: 3_000, expectedReturn: 0,
                                annualCost: 0, monthlyContribution: 200, startMonth: current.adding(-8)))
        return data
    }

    static var potID: UUID? { sample.pots.first?.id }

    /// De uitgaven, het sparen en het beleggen van de laatste zes maanden van de voorbeelddata.
    static var barModel: StackedBarModel {
        let data = sample
        let summaries = data.summaries(from: current.adding(-4), count: 6, current: current)
        return StackedBarModel.months(summaries, startMonth: data.startMonth)
    }

    /// Een koers van ongeveer 250 dagen, voor de koersgrafiek.
    static var priceModel: TrendModel {
        var history: [PricePoint] = []
        for i in 0..<250 {
            let date = now.addingTimeInterval(-Double(250 - i) * 86_400)
            history.append(PricePoint(date: date, close: 100 + Double(i) * 0.12))
        }
        return PriceTrend.model(history: history, ticker: "VWCE.DE", state: .loaded)
    }
}

#Preview("Beleggingen, voorbeelddata") {
    ScrollView {
        TrendChart(model: PortfolioTrend.model(ChartPreviewData.sample, window: .all, current: ChartPreviewData.current,
                                               today: ChartPreviewData.now),
                   size: .tall, nonNegative: true)
            .padding()
    }
    .background(Theme.canvas)
}

#Preview("Beleggingen, geschat uit je inleg") {
    ScrollView {
        TrendChart(model: PortfolioTrend.model(ChartPreviewData.derived, window: .all, current: ChartPreviewData.current,
                                               today: ChartPreviewData.now),
                   size: .tall, nonNegative: true)
            .padding()
    }
    .background(Theme.canvas)
}

#Preview("Beleggingen, lege staat") {
    ScrollView {
        TrendChart(model: PortfolioTrend.model(ChartPreviewData.empty, window: .all, current: ChartPreviewData.current,
                                               today: ChartPreviewData.now),
                   size: .tall, nonNegative: true) { _ in }
            .padding()
    }
    .background(Theme.canvas)
}

#Preview("In het klein") {
    VStack(alignment: .leading, spacing: 16) {
        TrendChart(model: PortfolioTrend.model(ChartPreviewData.sample, window: .sixMonths, current: ChartPreviewData.current,
                                               today: ChartPreviewData.now),
                   size: .compact, showsAxes: false, nonNegative: true)
        TrendChart(model: PortfolioTrend.model(ChartPreviewData.empty, window: .all, current: ChartPreviewData.current,
                                               today: ChartPreviewData.now),
                   size: .compact, showsAxes: false, nonNegative: true)
    }
    .padding()
    .background(Theme.canvas)
}

#Preview("Toekomstschatting") {
    ScrollView {
        TrendChart(model: ProjectionTrend.model(start: 5_000, monthly: 250, annualReturn: 0.05, months: 240, unit: .years,
                                                target: 120_000, inflationAdjusted: false, inflation: 0.02),
                   size: .tall)
            .padding()
    }
    .background(Theme.canvas)
}

#Preview("Saldo van een spaarpot") {
    ScrollView {
        if let id = ChartPreviewData.potID {
            TrendChart(model: PotTrend.model(ChartPreviewData.sample, potID: id, current: ChartPreviewData.current,
                                             today: ChartPreviewData.now),
                       size: .regular, nonNegative: true)
                .padding()
        }
    }
    .background(Theme.canvas)
}

#Preview("Waar gaat je geld heen") {
    ScrollView {
        StackedBarChart(model: ChartPreviewData.barModel)
            .padding()
    }
    .background(Theme.canvas)
}

#Preview("Koers van een belegging") {
    ScrollView {
        TrendChart(model: ChartPreviewData.priceModel, size: .tall)
            .padding()
    }
    .background(Theme.canvas)
}

#Preview("Koers, laden en fout") {
    VStack(alignment: .leading, spacing: 24) {
        TrendChart(model: PriceTrend.model(history: [], ticker: "VWCE.DE", state: .loading), size: .regular)
        TrendChart(model: PriceTrend.model(history: [], ticker: "VWCE.DE", state: .failed("Geen verbinding.")), size: .regular) { _ in }
    }
    .padding()
    .background(Theme.canvas)
}

#Preview("Verdeling, donker, grote tekst") {
    ScrollView {
        DonutChart(model: DonutModel.holdingKinds(ChartPreviewData.sample, current: ChartPreviewData.current,
                                                  today: ChartPreviewData.now))
            .padding()
    }
    .background(Theme.canvas)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
#endif
