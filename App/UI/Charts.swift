import SwiftUI
import Charts


// MARK: - Assen

/// Toont de y-as met compacte euro-bedragen, of verbergt beide assen (voor kleine grafieken op Home).
private struct ChartAxesModifier: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        if shown {
            content.chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Fmt.compact(v)).font(.caption2) }
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

// MARK: - Lijn per maand (vermogen, beleggingen, bankrekening)

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
        .animation(Theme.motion, value: points)
    }
}

// MARK: - Waar gaat je geld heen

/// Gestapelde staven per maand: uitgaven, gespaard, belegd en wat over is.
struct FlowChart: View {
    let months: [MonthSummary]
    var height: CGFloat = 150
    var showsAxes = true

    static let kinds = ["Uitgaven", "Gespaard", "Belegd", "Over"]
    static let colors: [Color] = [Theme.flowExpenses, Theme.flowSaved, Theme.flowInvested, Theme.flowFree]

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
        .animation(Theme.motion, value: months)
    }
}

// MARK: - Verdeling over soorten beleggingen

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
        .animation(Theme.motion, value: slices)
    }
}
