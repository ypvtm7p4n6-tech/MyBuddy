import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in ChartAxisTests,
// PortfolioTrendTests, TrendBuilderTests, DonutModelTests, StackedBarModelTests en ChartSegmentTests.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - De modellaag van alle grafieken (plan par. 5.3)
//
// Elke grafiek in de app is een zuivere functie van zijn invoer: een modelbouwer in dit bestand maakt uit de gegevens van de
// rekenmotor een model (de reeksen, de markeringen, de lege staat, de tekst voor VoiceOver en het onderschrift), en
// `Charts.swift` (SwiftUI) tekent alleen dat model. Een pagina schrijft daarom geen reeksen, assen, lege staten of
// VoiceOver-teksten meer zelf. Alle bedragen komen uit dezelfde bronnen als de rest van de app (`portfolioSeries`,
// `netWorthSeries`, `bankSeries`, `potSeries`, `Growth`, `BufferCalc`, `SavingsGoalPlan`, `goalCurves`, `summaries`); hier wordt
// niets zelf uitgerekend behalve optellingen en verschillen op hele centen.

// MARK: - Basistypen

/// De hoogte van een grafiek. Overal dezelfde drie maten (CHT-11): `compact` voor het Overzicht en Sparen, `regular`, en `tall`
/// voor de hoofdgrafiek van een pagina.
enum ChartSize: Equatable {
    case compact, regular, tall

    var height: CGFloat {
        switch self {
        case .compact: return 96
        case .regular: return 180
        case .tall: return 240
        }
    }
}

enum ChartPointKind: String, Equatable {
    /// Gemeten of ingevulde waarde, of een berekende lijn die als geheel een uitkomst is (Toekomstschatting).
    case actual
    /// Afgeleid uit je inleg (nog geen meetpunt): een dunne lijn met korte stippen, zonder vlak.
    case estimated
    /// Verwacht (na vandaag): een gestreepte lijn.
    case projected
}

struct ChartPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let value: Double
    let kind: ChartPointKind
}

enum ChartDash: Hashable { case solid, dashed, dotted }

/// Een vorm naast de kleur (CHT-5): bij "Onderscheid zonder kleur" krijgt elke reeks zijn symbool en een label aan het laatste punt.
enum ChartSymbol: Hashable { case circle, square, triangle, diamond }

/// De view vertaalt een rol naar een kleur uit `Theme`; zo blijft dit bestand Foundation-only en kiest geen grafiek zijn eigen kleur.
enum ChartRole: Hashable {
    /// Waarde, saldo, "mijn" lijn: het accent.
    case primary
    /// Een verwijzing of hulplijn (ingelegd, nu): `textSecondary`.
    case secondary
    /// Een tweede, even belangrijke reeks (optimistisch, benodigde inleg): `chartInvested`.
    case tertiary
    case warning, negative
    case expenses, variable, saved, invested, free
}

struct ChartLine: Identifiable, Equatable {
    let id: String
    let name: String
    var points: [ChartPoint]
    var dash: ChartDash = .solid
    var role: ChartRole = .primary
    var symbol: ChartSymbol? = nil
    var fillsArea = false
    var isThin = false
}

/// Een aaneengesloten stuk van een lijn met dezelfde soort punten (werkelijk, afgeleid of verwacht).
struct ChartSegment: Identifiable, Equatable {
    let id: String
    let kind: ChartPointKind
    let points: [ChartPoint]
}

extension ChartLine {
    /// Stukken van dezelfde soort; elk stuk begint met het laatste punt van het vorige, zodat de lijn aansluit. Een stuk van
    /// een punt (een enkel werkelijk punt) is een stip, geen lijn.
    var segments: [ChartSegment] {
        var result: [ChartSegment] = []
        var current: [ChartPoint] = []
        for p in points {
            if let last = current.last, last.kind != p.kind {
                result.append(ChartSegment(id: "\(id)-\(result.count)", kind: last.kind, points: current))
                current = [last]
            }
            current.append(p)
        }
        if let last = current.last {
            result.append(ChartSegment(id: "\(id)-\(result.count)", kind: last.kind, points: current))
        }
        return result
    }
}

/// Een markering in de grafiek, altijd met een tekst. Zonder `date` is het een horizontale lijn (doel, nul); met `date` een punt
/// ("Laagste", "Doel bereikt in augustus 2027").
struct ChartMarker: Identifiable, Equatable {
    enum Kind: Hashable { case goal, zero, low, reached }
    let id: String
    let value: Double
    let label: String
    let kind: Kind
    var date: Date? = nil
}

/// Lege staat: waarom er niets te tekenen valt en wat je kunt doen. Nul punten is nooit een lege `Chart`.
struct ChartEmpty: Equatable {
    enum Action: Equatable {
        case refreshPrices, enterValue(UUID), enterUnits(UUID), addHolding, enterBankBalance, openSalary, retry
    }
    var symbol: String
    var title: String
    var message: String
    var action: Action? = nil
    var actionTitle: String? = nil
    /// Een laadstaat: de view toont een voortgangsindicator in plaats van het symbool.
    var isLoading = false
}

enum ChartXAxis: Equatable {
    case months
    case days
    /// Verstreken tijd sinds het begin, in `unit` (Toekomstschatting). De punten dragen die tijd als pseudo-datum
    /// (`ChartAxis.elapsedDate`), zodat alle lijngrafieken dezelfde datum-as gebruiken.
    case elapsed(HorizonUnit)
}

struct TrendModel: Equatable {
    var title: String
    var lines: [ChartLine]
    var markers: [ChartMarker] = []
    var xAxis: ChartXAxis = .months
    /// De samenvatting voor VoiceOver: titel, kernwaarde, verloop.
    var summary: String
    /// Een korte, zichtbare regel met de kernwaarde onder de grafiek (CHT-6): "Nu € 8.966 · sinds mei 2026 +€ 1.616".
    var caption: String? = nil
    /// Uitleg bij een afgeleide of beperkte reeks ("Geschat uit je inleg, zonder rendement.").
    var footnote: String? = nil
    var empty: ChartEmpty? = nil
    /// Het y-domein bevat altijd 0 (spaardoel, buffer, toekomstschatting).
    var includesZero = false

    var allPoints: [ChartPoint] { lines.flatMap { $0.points } }

    /// Aantal maanden dat de grafiek beslaat (voor de afstand tussen de x-labels).
    var monthSpan: Int {
        let dates = allPoints.map { $0.date }
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        return YearMonth(date: first).months(to: YearMonth(date: last)) + 1
    }

    /// Het y-domein: altijd eindig en altijd `lo < hi`, ook bij een vlakke reeks of een lege lijst (`ChartAxis.domain`).
    func domain(nonNegative: Bool = false) -> ClosedRange<Double> {
        let values: [Double] = allPoints.map { $0.value } + markers.map { $0.value }
        return ChartAxis.domain(values, includeZero: includesZero, nonNegative: nonNegative)
    }

    /// Het x-domein: van het eerste tot het laatste punt, ook bij een enkel punt breed genoeg om een stip te tekenen.
    var xDomain: ClosedRange<Date> {
        var dates: [Date] = allPoints.map { $0.date }
        for marker in markers { if let d = marker.date { dates.append(d) } }
        guard let lo = dates.min(), let hi = dates.max() else {
            let now = Date()
            return now...now.addingTimeInterval(86_400)
        }
        if hi > lo { return lo...hi }
        let pad: TimeInterval
        switch xAxis {
        case .months: pad = 15 * 86_400
        case .days: pad = 86_400
        case .elapsed: pad = 0.5 * 86_400
        }
        return lo.addingTimeInterval(-pad)...hi.addingTimeInterval(pad)
    }

    /// De plekken van de x-labels: eigen keuze per soort as (`ChartAxis`), nooit de standaard van Swift Charts.
    var xTicks: [Date] {
        let range = xDomain
        switch xAxis {
        case .months:
            return ChartAxis.monthTicks(from: range.lowerBound, to: range.upperBound)
        case .days:
            return ChartAxis.dayTicks(from: range.lowerBound, to: range.upperBound)
        case .elapsed:
            let top = max(ChartAxis.elapsedValue(range.upperBound), ChartAxis.elapsedValue(range.lowerBound) + 1e-6)
            let values = ChartAxis.ticks(in: 0...top, count: 4)
            return values.map { ChartAxis.elapsedDate($0) }
        }
    }

    /// Het x-label bij een datum.
    func xLabel(_ date: Date) -> String {
        switch xAxis {
        case .months: return ChartAxis.monthLabel(date)
        case .days: return DayText.short(date)
        case .elapsed: return Fmt.input(ChartAxis.elapsedValue(date), maxDigits: 1)
        }
    }

    /// Een model zonder lijnen met alleen een lege staat.
    static func placeholder(title: String, empty: ChartEmpty) -> TrendModel {
        TrendModel(title: title, lines: [], summary: "\(title). Geen gegevens. \(empty.title).", empty: empty)
    }
}

// MARK: - As-logica

enum ChartAxis {
    /// Domein met lo < hi gegarandeerd; niet-eindige waarden tellen niet mee. `includeZero` voor staven, voortgang en doelen;
    /// `nonNegative` voor beleggingen en potten (een waarde onder 0 bestaat niet). Het domein staat altijd vast en hangt dus
    /// niet af van hoe Swift Charts een vlakke reeks opvangt.
    static func domain(_ values: [Double], includeZero: Bool = false, nonNegative: Bool = false) -> ClosedRange<Double> {
        let finite = values.filter { $0.isFinite }
        guard var lo = finite.min(), var hi = finite.max() else { return 0...1 }
        let dataMin = lo
        if includeZero { lo = min(lo, 0); hi = max(hi, 0) }
        let spread = hi - lo
        let pad = spread > 0 ? spread * 0.08 : max(abs(hi) * 0.05, 1)
        lo -= pad
        hi += pad
        if nonNegative || (includeZero && dataMin >= 0) { lo = max(lo, 0) }
        // Alleen negatieve waarden met `nonNegative` kunnen het domein omkeren; een omgekeerd bereik laat Swift crashen.
        if !(lo < hi) { hi = lo + max(abs(lo) * 0.05, 1) }
        if !lo.isFinite || !hi.isFinite { return 0...1 }
        return lo...hi
    }

    /// Nette tickwaarden binnen `domain` (1, 2 of 5 maal een tientallige macht); voor `AxisMarks(values:)`.
    static func ticks(in domain: ClosedRange<Double>, count: Int = 4) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, span.isFinite else { return [domain.lowerBound] }
        let raw = span / Double(max(1, count))
        let magnitude = pow(10, floor(log10(raw)))
        let norm = raw / magnitude
        let factor: Double = norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10))
        let step = factor * magnitude
        var tick = (domain.lowerBound / step).rounded(.up) * step
        var out: [Double] = []
        while tick <= domain.upperBound + step * 1e-9, out.count < 12 {
            out.append(abs(tick) < step * 1e-9 ? 0 : tick)
            tick += step
        }
        return out
    }

    /// y-labels: zo kort mogelijk (`€8k`), maar twee naburige ticks houden nooit hetzelfde label. Onder 10.000 liever `€1.050` dan
    /// `€1,1k`; bij een tickafstand onder 1 euro komen er centen bij, en bij nog kleinere afstanden drie decimalen.
    static func yLabels(_ ticks: [Double]) -> [String] {
        let step: Double = ticks.count > 1 ? abs(ticks[1] - ticks[0]) : 1
        func fixed(_ x: Double, _ digits: Int) -> String {
            String(format: "%.\(digits)f", x).replacingOccurrences(of: ".", with: ",")
        }
        func short(_ v: Double, _ digits: Int) -> String {
            let a = abs(v)
            let sign = v < 0 ? "-" : ""
            if a >= 1_000_000 { return sign + "€" + fixed(a / 1_000_000, digits) + " mln" }
            if a >= 1_000 { return sign + "€" + fixed(a / 1_000, digits) + "k" }
            return sign + "€" + fixed(a, step < 1 ? 2 : 0)
        }
        func unique(_ labels: [String]) -> Bool { Set(labels).count == labels.count }
        func compacted(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        }
        let biggest: Double = ticks.map { abs($0) }.max() ?? 0
        let short0: [String] = ticks.map { short($0, 0) }
        if unique(short0) { return short0 }
        let whole: [String] = ticks.map { compacted(Fmt.euroWhole($0)) }
        if biggest < 10_000, unique(whole) { return whole }
        let short1: [String] = ticks.map { short($0, 1) }
        if unique(short1) { return short1 }
        if unique(whole) { return whole }
        let cents: [String] = ticks.map { compacted(Fmt.euroExact($0)) }
        if unique(cents) { return cents }
        return ticks.map { "€" + fixed($0, 3) }
    }

    /// x-label van een maand: "okt", en met jaartal bij januari ("jan '27") zodat 36 maanden leesbaar blijven.
    static func monthLabel(_ date: Date) -> String {
        let m = YearMonth(date: date)
        return m.month == 1 ? Fmt.shortMonthYear(m) : Fmt.shortMonth(m)
    }

    /// Om de hoeveel maanden een x-label: hooguit ongeveer 6 labels op een smalle iPhone.
    static func monthStride(span months: Int) -> Int {
        switch months {
        case ...7: return 1
        case ...14: return 2
        case ...26: return 3
        case ...50: return 6
        default: return 12
        }
    }

    /// De plekken van de maandlabels tussen twee datums: op de eerste van de maand, vast uitgelijnd op de kalender (bij een stap van
    /// 3 januari, april, juli en oktober) zodat de labels niet verspringen als het venster opschuift. Altijd minstens een label.
    static func monthTicks(from lower: Date, to upper: Date) -> [Date] {
        let first = YearMonth(date: lower)
        let last = YearMonth(date: upper)
        let span = first.months(to: last) + 1
        let stride = monthStride(span: span)
        var ticks: [Date] = []
        var m = first
        while m <= last {
            if stride == 1 || (m.month - 1) % stride == 0 { ticks.append(m.firstDay) }
            m = m.adding(1)
        }
        if ticks.isEmpty { ticks.append(first.firstDay) }
        return ticks
    }

    /// Om de hoeveel dagen een x-label bij een grafiek per dag.
    static func dayStride(span days: Int) -> Int {
        switch days {
        case ...8: return 1
        case ...16: return 2
        case ...35: return 5
        case ...70: return 10
        default: return 30
        }
    }

    /// De plekken van de daglabels tussen twee datums, vanaf de eerste dag.
    static func dayTicks(from lower: Date, to upper: Date) -> [Date] {
        let cal = YearMonth.calendar
        let start = cal.startOfDay(for: lower)
        let end = cal.startOfDay(for: upper)
        let span = (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let stride = dayStride(span: span)
        var ticks: [Date] = []
        var offset = 0
        while offset < span, ticks.count < 12 {
            if let d = cal.date(byAdding: .day, value: offset, to: start) { ticks.append(d) }
            offset += stride
        }
        if ticks.isEmpty { ticks.append(start) }
        return ticks
    }

    /// Verstreken tijd (in de eenheid van de as) als pseudo-datum en terug. Zo gebruiken alle lijngrafieken een datum-as.
    static func elapsedDate(_ x: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: (x.isFinite ? x : 0) * 86_400)
    }

    static func elapsedValue(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate / 86_400
    }

    /// Dunt een reeks uit tot hooguit `limit` punten en houdt ALTIJD het eerste en het laatste punt (de oude doelcurve verloor het
    /// laatste punt, waar het doel gehaald wordt).
    static func downsample<T>(_ items: [T], limit: Int) -> [T] {
        guard items.count > limit, limit > 1 else { return items }
        let last = items.count - 1
        let step = Int((Double(last) / Double(limit - 1)).rounded(.up))
        var indices: [Int] = Array(stride(from: 0, through: last, by: max(1, step)))
        if indices.last != last { indices.append(last) }
        return indices.map { items[$0] }
    }
}

// MARK: - Teksten (VoiceOver en onderschrift)

enum ChartText {
    private static func formatted(_ value: Double, maxDigits: Int) -> String {
        let nf = NumberFormatter()
        nf.locale = Fmt.locale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = maxDigits
        let safe: Double = value == 0 ? 0 : value
        return nf.string(from: NSNumber(value: safe)) ?? "\(safe)"
    }

    /// "8.966" (zonder eenheid), voor een opsomming als "bank 10.830, spaarpotten 5.504".
    static func number(_ value: Double) -> String {
        formatted(value, maxDigits: abs(value) < 100 && value != value.rounded() ? 2 : 0)
    }

    /// "8.966 euro" (zonder valutateken, zoals VoiceOver het goed leest).
    static func euro(_ value: Double) -> String {
        number(value) + " euro"
    }

    /// "105,36 euro": een koers met centen.
    static func price(_ value: Double) -> String {
        formatted(value, maxDigits: 2) + " euro"
    }

    /// "plus 1.616 euro" of "min 120 euro".
    static func signedEuro(_ value: Double) -> String {
        (value >= 0 ? "plus " : "min ") + euro(abs(value))
    }

    /// "+€ 1.616" of "−€ 120": een bedrag met teken voor het zichtbare onderschrift.
    static func signedWhole(_ value: Double) -> String {
        (value >= 0 ? "+" : "−") + Fmt.euroWhole(abs(value))
    }

    /// "Oktober 2026": een maand aan het begin van een zin.
    static func monthTitle(_ month: YearMonth) -> String {
        capitalized(Fmt.month(month))
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).lowercased() + String(text.dropFirst())
    }
}

/// Een punt zonder eindige waarde zou de grafiek breken (CHT-8): de modelbouwers laten het weg.
private func finitePoints(_ points: [ChartPoint]) -> [ChartPoint] {
    points.filter { $0.value.isFinite }
}

// MARK: - Beleggingssoorten

extension HoldingKind {
    /// De kleur van een beleggingssoort, overal dezelfde: de plek in `HoldingKind.allCases` wijst `Theme.color(_:)` aan (de donut,
    /// de rijen en de tegels). Niet de plek in een rangorde, want die wisselt als de waarden veranderen.
    var colorIndex: Int { HoldingKind.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Beleggingen: Groei en Waarde

/// Hoe ver de grafiek terugkijkt. `all` = vanaf het eerste gegeven.
enum PortfolioWindow: Int, CaseIterable, Identifiable {
    case sixMonths = 6, year = 12, threeYears = 36, all = 0
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sixMonths: return "6 mnd"
        case .year: return "1 jaar"
        case .threeYears: return "3 jaar"
        case .all: return "Alles"
        }
    }

    /// Alleen de keuzes die een ander beeld geven. `availableMonths` = aantal maanden gegevens t/m de huidige maand. Een venster
    /// van n maanden terug toont n + 1 maanden; het verschilt van "Alles" pas bij meer dan n + 1 maanden gegevens. Een keuzebalk met
    /// alleen "Alles" kiest niets: dan geen balk (lege lijst).
    static func options(availableMonths: Int) -> [PortfolioWindow] {
        let shorter: [PortfolioWindow] = [.sixMonths, .year, .threeYears].filter { $0.rawValue + 1 < availableMonths }
        return shorter.isEmpty ? [] : shorter + [.all]
    }
}

enum PortfolioTrend {
    /// Voorwaartse horizon in maanden (verwachting).
    static let forwardMonths = 12

    /// Hoeveel maanden gegevens er zijn t/m `current` (eerste meetpunt of "Belegd sinds" tot nu), voor
    /// `PortfolioWindow.options(availableMonths:)`. 0 zonder gegevens.
    static func availableMonths(_ data: FinanceData, current: YearMonth, today: Date, only: Set<UUID>? = nil) -> Int {
        guard let start = data.portfolioDataStart(current: current, today: today, only: only) else { return 0 }
        return max(0, start.months(to: current) + 1)
    }

    /// De grafiek van de waarde van (een deel van) de beleggingen. Zonder meetpunt tekent hij de afgeleide lijn uit "Totaal ingelegd",
    /// "Belegd sinds" en de inleg (`isEstimated`), met het onderschrift "Geschat uit je inleg, zonder rendement." Zonder iets
    /// invullens een lege staat met een actie. `only` = één belegging (de detailpagina).
    static func model(_ data: FinanceData, window: PortfolioWindow, current: YearMonth, today: Date,
                      only: Set<UUID>? = nil) -> TrendModel {
        let title = only == nil ? "Waarde van je beleggingen" : "Waarde van deze belegging"
        // Eerst alles vanaf tien jaar terug: het eerste gegeven bepaalt het begin, het venster knipt daarna.
        let all = data.portfolioSeries(from: current.adding(-120), count: 121 + forwardMonths, current: current,
                                       only: only, today: today)
        guard let first = all.first else { return empty(data, current: current, only: only, title: title) }
        let from: YearMonth = window == .all ? first.month : max(first.month, current.adding(-window.rawValue))
        let pts = all.filter { $0.month >= from }
        let history = pts.filter { !$0.isProjected }
        let isEstimated = !history.isEmpty && history.allSatisfy { $0.isEstimated }

        var valuePoints: [ChartPoint] = []
        var investedPoints: [ChartPoint] = []
        for p in pts {
            let kind: ChartPointKind = p.isProjected ? .projected : (p.isEstimated ? .estimated : .actual)
            valuePoints.append(ChartPoint(id: "waarde-\(p.id)", date: p.month.firstDay, value: p.value, kind: kind))
            investedPoints.append(ChartPoint(id: "ingelegd-\(p.id)", date: p.month.firstDay, value: p.invested, kind: kind))
        }
        var lines: [ChartLine] = [
            ChartLine(id: "waarde", name: "Waarde", points: finitePoints(valuePoints), role: .primary, symbol: .circle, fillsArea: true)
        ]
        // Afgeleid is de waarde gelijk aan wat je inlegde: een tweede lijn zou er precies bovenop liggen.
        if !isEstimated {
            lines.append(ChartLine(id: "ingelegd", name: "Ingelegd", points: finitePoints(investedPoints), role: .secondary,
                                   symbol: .square, isThin: true))
        }

        var parts: [String] = ["\(title)."]
        var caption: String?
        if let now = history.last {
            let estimateNote: String = isEstimated ? ", geschat uit je inleg" : ""
            parts.append("Nu \(ChartText.euro(now.value))\(estimateNote).")
            var cap = "Nu \(Fmt.euroWhole(now.value))"
            if isEstimated {
                cap += " (geschat)"
            } else {
                if let a = history.first, history.count > 1 {
                    parts.append("Sinds \(Fmt.month(a.month)) \(ChartText.signedEuro(now.value - a.value)).")
                    cap += " · sinds \(Fmt.shortMonthYear(a.month)) \(ChartText.signedWhole(now.value - a.value))"
                }
                parts.append("Ingelegd \(ChartText.euro(now.invested)).")
            }
            caption = cap
        }
        if let end = pts.last, end.isProjected {
            parts.append("Verwacht in \(Fmt.month(end.month)): \(ChartText.euro(end.value)).")
        }
        var footnote: String?
        if isEstimated {
            footnote = "Geschat uit je inleg, zonder rendement."
            parts.append("Geschat uit je inleg, zonder rendement.")
        } else if history.count < 2 {
            footnote = "Je echte verloop begint op \(Fmt.date(today)). Het gestippelde deel is verwacht."
        }
        return TrendModel(title: title, lines: lines, summary: parts.joined(separator: " "), caption: caption, footnote: footnote)
    }

    /// De lege staat: waarom er niets te tekenen valt en welke ene actie dat oplost.
    static func empty(_ data: FinanceData, current: YearMonth, only: Set<UUID>? = nil, title: String? = nil) -> TrendModel {
        let heading = title ?? (only == nil ? "Waarde van je beleggingen" : "Waarde van deze belegging")
        let scoped: [Holding] = only == nil ? data.holdings : data.holdings.filter { only!.contains($0.id) }
        let e: ChartEmpty
        if scoped.isEmpty {
            e = ChartEmpty(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                           message: "Voeg een ETF, aandeel, crypto of spaarrekening toe.",
                           action: .addHolding, actionTitle: "Belegging toevoegen")
        } else if scoped.allSatisfy({ $0.startMonth > current }) {
            let start = scoped.map { $0.startMonth }.min() ?? current
            e = ChartEmpty(symbol: "calendar", title: "Nog niet begonnen",
                           message: "Belegd sinds \(Fmt.month(start)). Vanaf die maand zie je hier je groei.")
        } else if let h = scoped.first(where: { $0.hasTicker && !$0.isTracked }) {
            e = ChartEmpty(symbol: "number", title: "Vul het aantal stuks in",
                           message: "Met een ticker en een aantal rekent de app de waarde van \(h.name) uit.",
                           action: .enterUnits(h.id), actionTitle: "Aantal invullen")
        } else if scoped.contains(where: { $0.isTracked }) {
            e = ChartEmpty(symbol: "arrow.clockwise", title: "Wachten op de koers",
                           message: "Zodra de koers binnen is, zie je hier je waarde. Controleer anders je internet en de ticker.",
                           action: .refreshPrices, actionTitle: "Koersen vernieuwen")
        } else {
            e = ChartEmpty(symbol: "pencil.and.list.clipboard", title: "Nog geen waarde",
                           message: "Vul de huidige waarde of het ingelegde bedrag in, dan tekent de app je groei.",
                           action: .enterValue(scoped[0].id), actionTitle: "Waarde invullen")
        }
        return TrendModel.placeholder(title: heading, empty: e)
    }
}

// MARK: - Koers van een belegging

enum PriceTrend {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// De koers van het afgelopen jaar. `loading` en `failed` zijn lege staten (met "Probeer opnieuw"); een lege `history` na
    /// `loaded` ook. Eén koers is een stip met tekst; pas vanaf twee koersen een lijn. De y-labels zijn uniek (centen waar nodig).
    static func model(history: [PricePoint], ticker: String, state: LoadState) -> TrendModel {
        let title = "Koers van \(ticker)"
        switch state {
        case .loading:
            let e = ChartEmpty(symbol: "clock", title: "Koershistorie ophalen", message: "Een moment geduld.", isLoading: true)
            return TrendModel.placeholder(title: title, empty: e)
        case .failed(let reason):
            let e = ChartEmpty(symbol: "exclamationmark.triangle", title: "Koershistorie niet beschikbaar",
                               message: "\(reason) Controleer je internet en de ticker.",
                               action: .retry, actionTitle: "Probeer opnieuw")
            return TrendModel.placeholder(title: title, empty: e)
        case .loaded:
            break
        }
        let sorted = history.filter { $0.close.isFinite }.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else {
            let e = ChartEmpty(symbol: "chart.xyaxis.line", title: "Geen koersen gevonden",
                               message: "Voor \(ticker) kwam geen koershistorie binnen. Controleer de ticker.",
                               action: .retry, actionTitle: "Probeer opnieuw")
            return TrendModel.placeholder(title: title, empty: e)
        }
        let thinned = ChartAxis.downsample(sorted, limit: 160)
        var points: [ChartPoint] = []
        for (i, p) in thinned.enumerated() {
            points.append(ChartPoint(id: "koers-\(i)", date: p.date, value: p.close, kind: .actual))
        }
        let closes = sorted.map { $0.close }
        let now = sorted[sorted.count - 1].close
        let low = closes.min() ?? now
        let high = closes.max() ?? now
        let line = ChartLine(id: "koers", name: "Koers", points: points, role: .primary, symbol: .circle)
        let summary = "Koers van \(ticker) het afgelopen jaar. Nu \(ChartText.price(now)). Laagste \(ChartText.price(low)), hoogste \(ChartText.price(high))."
        let caption = "Nu \(Fmt.euroExact(now)) · laagste \(Fmt.euroExact(low)) · hoogste \(Fmt.euroExact(high))"
        let footnote: String? = sorted.count < 2 ? "Er is nog maar één koers bekend." : nil
        return TrendModel(title: title, lines: [line], summary: summary, caption: caption, footnote: footnote)
    }
}

// MARK: - Vermogen

enum NetWorthTrend {
    /// Het vermogen aan het eind van de maanden in `months` (bank, spaarpotten en beleggingen). Maanden vóór de startmaand van de
    /// gegevens zijn er niet (daar was alleen een sprong van 0); een onbekend banksaldo telt als 0 en krijgt een noot.
    static func model(_ data: FinanceData, months: [YearMonth], current: YearMonth, today: Date) -> TrendModel {
        let title = "Vermogen"
        guard let first = months.min(), let last = months.max() else {
            return TrendModel.placeholder(title: title, empty: emptyState())
        }
        let series = data.netWorthSeries(from: first, count: first.months(to: last) + 1, current: current)
        let wanted = Set(months.map { $0.key })
        let shown = series.filter { $0.month >= data.startMonth && wanted.contains($0.month.key) }
        guard shown.contains(where: { $0.total != 0 }) else {
            return TrendModel.placeholder(title: title, empty: emptyState())
        }
        var points: [ChartPoint] = []
        for p in shown {
            points.append(ChartPoint(id: "vermogen-\(p.id)", date: p.month.firstDay, value: p.total,
                                     kind: p.isProjected ? .projected : .actual))
        }
        let line = ChartLine(id: "vermogen", name: "Vermogen", points: finitePoints(points), role: .primary, symbol: .circle,
                             fillsArea: true)
        let history = shown.filter { !$0.isProjected }
        var parts: [String] = ["Vermogen aan het eind van de maand."]
        if let nowPoint = history.last {
            parts.append("\(ChartText.monthTitle(nowPoint.month)): \(ChartText.euro(nowPoint.total)) (bank \(ChartText.number(nowPoint.bank)), spaarpotten \(ChartText.number(nowPoint.pots)), beleggingen \(ChartText.number(nowPoint.investments))).")
            if let a = history.first, history.count > 1 {
                parts.append("Sinds \(Fmt.month(a.month)) \(ChartText.signedEuro(nowPoint.total - a.total)).")
            }
        }
        if let end = shown.last, end.isProjected {
            parts.append("Verwacht in \(Fmt.month(end.month)): \(ChartText.euro(end.total)).")
        }
        let missingBank = shown.contains { !$0.bankKnown }
        if missingBank { parts.append("Zonder banksaldo voor een deel van de maanden.") }
        let nowTotal = data.netWorthNow(current: current, today: today).total
        let caption = "Nu \(Fmt.euroWhole(nowTotal))"
        let footnote: String? = missingBank ? "Zonder banksaldo: de bank telt voor maanden zonder saldo als € 0 mee." : nil
        return TrendModel(title: title, lines: [line], summary: parts.joined(separator: " "), caption: caption, footnote: footnote)
    }

    private static func emptyState() -> ChartEmpty {
        ChartEmpty(symbol: "banknote", title: "Nog geen vermogen",
                   message: "Vul een banksaldo, een spaarpot of een belegging in.",
                   action: .enterBankBalance, actionTitle: "Banksaldo invullen")
    }
}

// MARK: - Bankrekening: Verwacht verloop

enum BankTrend {
    /// Het saldo aan het eind van elke maand: drie maanden terug en een jaar vooruit. Zonder banksaldo een lege staat met de
    /// actie "Saldo invullen" in plaats van een verdwenen blok.
    static func model(_ data: FinanceData, current: YearMonth, today: Date) -> TrendModel {
        let title = "Verwacht banksaldo"
        let series = data.bankSeries(from: current.adding(-3), count: 16, current: current)
        guard !series.isEmpty else {
            let e = ChartEmpty(symbol: "building.columns", title: "Banksaldo onbekend",
                               message: "Vul je saldo van vandaag in, dan zie je hier het verwachte verloop.",
                               action: .enterBankBalance, actionTitle: "Saldo invullen")
            return TrendModel.placeholder(title: title, empty: e)
        }
        var points: [ChartPoint] = []
        for p in series {
            points.append(ChartPoint(id: "saldo-\(p.id)", date: p.month.firstDay, value: p.balance,
                                     kind: p.isProjected ? .projected : .actual))
        }
        let line = ChartLine(id: "saldo", name: "Saldo", points: finitePoints(points), role: .primary, symbol: .circle,
                             fillsArea: true)
        var markers: [ChartMarker] = []
        if series.contains(where: { $0.balance < 0 }) {
            markers.append(ChartMarker(id: "nul", value: 0, label: "Nul", kind: .zero))
        }
        var parts: [String] = ["Verwacht banksaldo per maand-einde."]
        let history = series.filter { !$0.isProjected }
        if let nowPoint = history.last { parts.append("\(ChartText.monthTitle(nowPoint.month)): \(ChartText.euro(nowPoint.balance)).") }
        if let end = series.last, end.isProjected {
            parts.append("Verwacht in \(Fmt.month(end.month)): \(ChartText.euro(end.balance)).")
        }
        var caption: String?
        if let known = data.bankBalanceNowIfKnown(current: current, today: today) {
            caption = "Saldo vandaag \(Fmt.euroWhole(known))"
        }
        return TrendModel(title: title, lines: [line], markers: markers, summary: parts.joined(separator: " "), caption: caption)
    }
}

// MARK: - Bankrekening: Saldo per dag

enum DayBalanceTrend {
    /// Het saldo per dag voor de dagen van `items` (de dagen met een bekend saldo). Een dag is een stip met tekst, pas vanaf twee
    /// dagen een lijn; "Nul" en "Laagste" zijn markeringen met tekst. Een geplande dag (na vandaag) is gestreept.
    static func model(items: [DayChartItem], range: DayChartRange, focus: YearMonth, today: Date) -> TrendModel {
        let title = "Saldo per dag"
        let usable = items.filter { $0.value.isFinite }.sorted { $0.date < $1.date }
        guard !usable.isEmpty else {
            let e = ChartEmpty(symbol: "calendar", title: "Saldo nog niet bekend",
                               message: "Voor deze periode is je saldo nog niet bekend. Vul je saldo van vandaag in.",
                               action: .enterBankBalance, actionTitle: "Saldo invullen")
            return TrendModel.placeholder(title: title, empty: e)
        }
        var points: [ChartPoint] = []
        for item in usable {
            let id = "dag-\(Int(item.date.timeIntervalSince1970))"
            points.append(ChartPoint(id: id, date: item.date, value: item.value, kind: item.planned ? .projected : .actual))
        }
        let line = ChartLine(id: "dag", name: "Saldo", points: points, role: .primary, symbol: .circle, fillsArea: true)
        let lowest = usable.min { $0.value < $1.value } ?? usable[0]
        let last = usable[usable.count - 1]
        var markers: [ChartMarker] = []
        if lowest.value < 0 {
            markers.append(ChartMarker(id: "nul", value: 0, label: "Nul", kind: .zero))
        }
        if usable.count > 1 {
            markers.append(ChartMarker(id: "laagste", value: lowest.value,
                                       label: "Laagste: \(Fmt.euroWhole(lowest.value))", kind: .low, date: lowest.date))
        }
        let from = usable[0].date
        let period = "\(DayText.short(from)) tot \(DayText.short(last.date))"
        var parts: [String] = ["Banksaldo per dag, \(period)."]
        if usable.count == 1 {
            parts.append("Saldo op \(DayText.short(last.date)) \(ChartText.euro(last.value)).")
        } else {
            parts.append("Laagste saldo \(ChartText.euro(lowest.value)) op \(DayText.short(lowest.date)), saldo op het eind \(ChartText.euro(last.value)).")
        }
        let caption: String = usable.count == 1
            ? "Saldo op \(DayText.short(last.date)): \(Fmt.euroWhole(last.value))"
            : "Laagste \(Fmt.euroWhole(lowest.value)) op \(DayText.short(lowest.date)) · eind \(Fmt.euroWhole(last.value))"
        return TrendModel(title: title, lines: [line], markers: markers, xAxis: .days, summary: parts.joined(separator: " "),
                          caption: caption)
    }
}

// MARK: - Toekomstschatting

enum ProjectionTrend {
    /// Drie scenario's (voorzichtig, verwacht, optimistisch) over de gekozen tijd, op een as in de gekozen eenheid. Elk scenario
    /// heeft zijn eigen lijnstijl en symbool (niet alleen een kleur). `months` is de looptijd in maanden (de pagina rekent
    /// `unit.months(horizon)`); een doel is een markering als het binnen de grafiek valt. Zonder startbedrag en zonder inleg een
    /// lege staat in plaats van drie vlakke nullijnen.
    static func model(start: Double, monthly: Double, annualReturn: Double, months: Double, unit: HorizonUnit,
                      target: Double, inflationAdjusted: Bool, inflation: Double) -> TrendModel {
        let title = "Toekomstschatting"
        let usable = start.isFinite && monthly.isFinite && annualReturn.isFinite && months.isFinite
        guard usable, start > 0 || monthly > 0 else {
            let e = ChartEmpty(symbol: "chart.line.uptrend.xyaxis", title: "Nog niets om te berekenen",
                               message: "Vul een startbedrag of een inleg in, dan zie je drie mogelijke verlopen.")
            return TrendModel.placeholder(title: title, empty: e)
        }
        let totalMonths = max(months, 0.1)
        let safeInflation: Double = inflation.isFinite ? inflation : 0
        var lines: [ChartLine] = []
        var results: [(title: String, value: Double)] = []
        var contributed = 0.0
        var topValue = 0.0
        for scenario in ReturnScenario.allCases {
            let rate = annualReturn + scenario.delta
            let curve = Growth.curve(start: start, monthly: monthly, annualReturn: rate, totalMonths: totalMonths, unit: unit,
                                     steps: 36)
            var points: [ChartPoint] = []
            for (i, p) in curve.enumerated() {
                var value = p.value
                if inflationAdjusted {
                    value = Growth.deflate(value, years: unit.months(p.t) / 12, inflation: safeInflation)
                }
                points.append(ChartPoint(id: "\(scenario.rawValue)-\(i)", date: ChartAxis.elapsedDate(p.t), value: value, kind: .actual))
                if value.isFinite { topValue = max(topValue, value) }
            }
            let role: ChartRole
            let dash: ChartDash
            let symbol: ChartSymbol
            switch scenario {
            case .cautious: role = .secondary; dash = .dotted; symbol = .square
            case .expected: role = .primary; dash = .solid; symbol = .circle
            case .optimistic: role = .tertiary; dash = .dashed; symbol = .triangle
            }
            lines.append(ChartLine(id: scenario.rawValue, name: scenario.title, points: finitePoints(points), dash: dash,
                                   role: role, symbol: symbol))
            let result = Growth.projection(start: start, monthly: monthly, annualReturn: rate, months: max(0, months),
                                           inflation: safeInflation)
            results.append((title: scenario.title, value: inflationAdjusted ? result.real : result.total))
            contributed = result.contributed
        }
        var markers: [ChartMarker] = []
        var footnote: String?
        if target.isFinite, target > 0 {
            if target <= topValue * 2 {
                markers.append(ChartMarker(id: "doel", value: target, label: "Doel \(Fmt.euroWhole(target))", kind: .goal))
            } else {
                footnote = "Je doel van \(Fmt.euroWhole(target)) ligt ver boven deze grafiek."
            }
        }
        let horizon = months / unit.months(1)
        let horizonText = "\(Fmt.input(horizon, maxDigits: 1)) \(unit.title)"
        var parts: [String] = ["Toekomstschatting over \(horizonText)."]
        let names: [String] = results.map { "\($0.title.lowercased()) \(ChartText.euro($0.value))" }
        parts.append(ChartText.capitalized(names.joined(separator: ", ")) + ".")
        parts.append("Daarvan ingelegd \(ChartText.euro(contributed)).")
        if inflationAdjusted { parts.append("In koopkracht van vandaag.") }
        var caption = "Verwacht \(Fmt.euroWhole(results[1].value)) over \(horizonText)"
        if inflationAdjusted { caption += " (in koopkracht van vandaag)" }
        return TrendModel(title: title, lines: lines, markers: markers, xAxis: .elapsed(unit), summary: parts.joined(separator: " "),
                          caption: caption, footnote: footnote, includesZero: true)
    }
}

// MARK: - Noodbuffer

enum BufferTrend {
    /// Je noodbuffer tegenover je doel, per maand vanaf `start` (punt 0 is nu). Het doel is een lijn met tekst; de maand waarin het
    /// doel gehaald wordt is een punt met tekst ("Doel bereikt in augustus 2027"). Zonder doel een lege staat.
    static func model(_ result: BufferResult, start: YearMonth) -> TrendModel {
        let title = "Je noodbuffer"
        guard result.hasTarget else {
            let e = ChartEmpty(symbol: "chart.xyaxis.line", title: "Nog geen doel",
                               message: "Zodra je uitgaven bekend zijn, zie je hier hoe je noodbuffer groeit.")
            return TrendModel.placeholder(title: title, empty: e)
        }
        let series = BufferCalc.series(result, start: start)
        var points: [ChartPoint] = []
        for (i, p) in series.enumerated() {
            points.append(ChartPoint(id: "buffer-\(p.id)", date: p.month.firstDay, value: p.projected, kind: i == 0 ? .actual : .projected))
        }
        let line = ChartLine(id: "buffer", name: "Je noodbuffer", points: finitePoints(points), role: .primary, symbol: .circle)
        var markers: [ChartMarker] = []
        var goalText = "Doel \(Fmt.euroWhole(result.target))"
        if result.isFull { goalText += ", al bereikt" }
        markers.append(ChartMarker(id: "doel", value: result.target, label: goalText, kind: .goal))
        var reachText = ""
        if let n = result.monthsToFill, n > 0 {
            let month = start.adding(n)
            reachText = "Doel bereikt in \(Fmt.month(month))"
            markers.append(ChartMarker(id: "bereikt", value: result.target, label: reachText, kind: .reached, date: month.firstDay))
        }
        var parts: [String] = ["Noodbuffer: nu \(ChartText.euro(result.current)) van een doel van \(ChartText.euro(result.target))."]
        if result.isFull {
            parts.append("Je doel is bereikt.")
        } else if let n = result.monthsToFill {
            parts.append("Met \(ChartText.euro(result.monthlySaving)) per maand is het doel bereikt in \(Fmt.month(start.adding(n))).")
        } else {
            parts.append("Met \(ChartText.euro(result.monthlySaving)) per maand haal je het doel niet binnen 100 jaar.")
        }
        let caption = reachText.isEmpty ? "Nu \(Fmt.euroWhole(result.current)) van \(Fmt.euroWhole(result.target))" : reachText
        return TrendModel(title: title, lines: [line], markers: markers, summary: parts.joined(separator: " "), caption: caption,
                          includesZero: true)
    }
}

// MARK: - Spaardoel berekenen

enum SavingsGoalTrend {
    /// Je saldo met je eigen inleg ("Mijn inleg") tegenover het doel, en de "Benodigde inleg" als gestreepte lijn als die afwijkt.
    /// Al bereikt of een doel van 0 is een lege staat (geen vlakke lijn). De lijn loopt minstens tot het einde van de termijn.
    static func model(plan: SavingsGoalPlan, now: YearMonth) -> TrendModel {
        let title = "Spaardoel"
        if plan.cleanGoal <= 0 {
            let e = ChartEmpty(symbol: "target", title: "Nog geen doel",
                               message: "Vul een bedrag in dat je wilt sparen, dan zie je hier het verloop.")
            return TrendModel.placeholder(title: title, empty: e)
        }
        if plan.isReached {
            let e = ChartEmpty(symbol: "checkmark.circle", title: "Je hebt dit bedrag al",
                               message: "Je saldo is hoger dan je doel.")
            return TrendModel.placeholder(title: title, empty: e)
        }
        let mineMonths = max(plan.months, plan.chosenOutcome.months)
        let mine = plan.series(monthly: plan.cleanMonthly, months: mineMonths)
        var lines: [ChartLine] = [
            ChartLine(id: "mijn", name: "Mijn inleg", points: seriesPoints(mine, prefix: "mijn", start: now), role: .primary, symbol: .circle)
        ]
        let showNeeded = abs(plan.cleanMonthly - plan.requiredMonthlyWhole) > 0.5
        if showNeeded {
            let needed = plan.series(monthly: plan.requiredMonthlyWhole, months: plan.months)
            lines.append(ChartLine(id: "benodigd", name: "Benodigde inleg", points: seriesPoints(needed, prefix: "benodigd", start: now),
                                   dash: .dashed, role: .tertiary, symbol: .diamond))
        }
        let markers = [ChartMarker(id: "doel", value: plan.cleanGoal, label: "Doel \(Fmt.euroWhole(plan.cleanGoal))", kind: .goal)]
        var parts: [String] = ["Spaardoel \(ChartText.euro(plan.cleanGoal)) in \(plan.months) maanden."]
        var caption: String
        if let reach = plan.reachMonth(from: now) {
            parts.append("Met \(ChartText.euro(plan.cleanMonthly)) per maand haal je het in \(Fmt.month(reach)).")
            caption = "Met je inleg klaar in \(Fmt.month(reach))"
        } else {
            parts.append("Met \(ChartText.euro(plan.cleanMonthly)) per maand haal je het niet binnen 100 jaar.")
            caption = "Met je inleg haal je het doel niet binnen 100 jaar"
        }
        if showNeeded {
            parts.append("Voor de termijn heb je \(ChartText.euro(plan.requiredMonthlyWhole)) per maand nodig.")
            caption += " · nodig \(Fmt.euroWhole(plan.requiredMonthlyWhole)) per maand"
        }
        return TrendModel(title: title, lines: lines, markers: markers, summary: parts.joined(separator: " "), caption: caption,
                          includesZero: true)
    }

    /// Een reeks per maand (index 0 = `start`) als punten, uitgedund tot hooguit 120 met altijd het eerste en het laatste.
    fileprivate static func seriesPoints(_ values: [Double], prefix: String, start: YearMonth) -> [ChartPoint] {
        var indexed: [Int] = []
        for i in values.indices { indexed.append(i) }
        let kept = ChartAxis.downsample(indexed, limit: 120)
        var points: [ChartPoint] = []
        for i in kept {
            points.append(ChartPoint(id: "\(prefix)-\(i)", date: start.adding(i).firstDay, value: values[i], kind: .actual))
        }
        return finitePoints(points)
    }
}

// MARK: - Versnellers

enum GoalCurveTrend {
    /// "Nu" tegenover "Met versnellers" (twee lijnstijlen: vol en gestreept) en het doel. De uitdunning houdt het laatste punt, waar
    /// het doel gehaald wordt. Zonder reeks een lege staat.
    static func model(curves: GoalCurves, goalName: String, start: YearMonth) -> TrendModel {
        let title = goalName.isEmpty ? "Versnellers" : "Versnellers voor \(goalName)"
        guard curves.baseline.count > 1 else {
            let e = ChartEmpty(symbol: "bolt", title: "Kies een versneller",
                               message: "Kies een versneller om te zien hoeveel sneller je je doel haalt.")
            return TrendModel.placeholder(title: title, empty: e)
        }
        let now = SavingsGoalTrend.seriesPoints(curves.baseline, prefix: "nu", start: start)
        let withAccelerators = SavingsGoalTrend.seriesPoints(curves.scenario, prefix: "versnellers", start: start)
        var lines: [ChartLine] = [ChartLine(id: "nu", name: "Nu", points: now, role: .secondary, symbol: .square)]
        if withAccelerators.count > 1 {
            lines.append(ChartLine(id: "versnellers", name: "Met versnellers", points: withAccelerators, dash: .dashed,
                                   role: .primary, symbol: .circle))
        }
        let markers = [ChartMarker(id: "doel", value: curves.scenarioTarget, label: "Doel \(Fmt.euroWhole(curves.scenarioTarget))",
                                   kind: .goal)]
        let baseMonths = monthsToReach(curves.baseline, target: curves.target)
        let scenarioMonths = monthsToReach(curves.scenario, target: curves.scenarioTarget)
        let name = goalName.isEmpty ? "Je doel" : goalName
        func durationText(_ months: Int?) -> String { months.map { Fmt.duration(months: $0) } ?? "niet binnen de grafiek" }
        let summary = "\(name): zonder versnellers \(durationText(baseMonths)), met je keuze \(durationText(scenarioMonths))."
        let caption = "Met je keuze: \(durationText(scenarioMonths)) · nu: \(durationText(baseMonths))"
        return TrendModel(title: title, lines: lines, markers: markers, summary: summary, caption: caption)
    }

    /// Na hoeveel maanden de reeks het doel haalt (index van het eerste punt op of boven het doel), nil als dat niet gebeurt.
    static func monthsToReach(_ values: [Double], target: Double) -> Int? {
        values.firstIndex(where: { $0 >= target })
    }
}

// MARK: - Saldoverloop van een spaarpot

enum PotTrend {
    /// Het saldo van de pot aan het eind van elke maand: tot drie jaar terug en een jaar vooruit, vanaf de startmaand van de pot.
    /// De lopende maand toont het saldo van nu (per kalenderdag, zoals de rest van de pot). Met een doel: de doellijn en "Doel
    /// bereikt in {maand}". Zonder boeking of inleg een lege staat.
    static func model(_ data: FinanceData, potID: UUID, current: YearMonth, today: Date) -> TrendModel {
        guard let pot = data.pot(potID) else {
            let e = ChartEmpty(symbol: "banknote", title: "Spaarpot niet gevonden", message: "Deze spaarpot bestaat niet meer.")
            return TrendModel.placeholder(title: "Saldo", empty: e)
        }
        let title = "Saldo van \(pot.name)"
        let from = max(pot.startMonth, current.adding(-36))
        let count = max(0, from.months(to: current.adding(12)) + 1)
        let series = data.potSeries(potID, from: from, count: count, current: current)
        guard series.contains(where: { $0.balance != 0 }) else {
            let e = ChartEmpty(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen verloop",
                               message: "Zodra er een boeking of inleg is, zie je hier het saldo per maand.")
            return TrendModel.placeholder(title: title, empty: e)
        }
        let balanceNow = data.potBalanceNow(potID, current: current, today: today)
        var points: [ChartPoint] = []
        for p in series {
            let value: Double = p.month == current ? balanceNow : p.balance
            points.append(ChartPoint(id: "pot-\(p.id)", date: p.month.firstDay, value: value, kind: p.isProjected ? .projected : .actual))
        }
        let line = ChartLine(id: "pot", name: "Saldo", points: finitePoints(points), role: .primary, symbol: .circle, fillsArea: true)
        var markers: [ChartMarker] = []
        var parts: [String] = ["\(title) per maand-einde. Nu \(ChartText.euro(balanceNow))."]
        var caption = "Nu \(Fmt.euroWhole(balanceNow))"
        if let goal = pot.goalAmount, goal > 0 {
            markers.append(ChartMarker(id: "doel", value: goal, label: "Doel \(Fmt.euroWhole(goal))", kind: .goal))
            parts.append("Doel \(ChartText.euro(goal)).")
            if let reach = data.potGoalMonth(potID, current: current) {
                let text = reach == current && balanceNow >= goal ? "Doel bereikt" : "Doel bereikt in \(Fmt.month(reach))"
                parts.append("\(text).")
                caption += " · " + ChartText.lowercasedFirst(text)
                if reach > current, reach <= current.adding(12) {
                    markers.append(ChartMarker(id: "bereikt", value: goal, label: text, kind: .reached, date: reach.firstDay))
                }
            }
        }
        if let end = series.last, end.isProjected {
            parts.append("Verwacht in \(Fmt.month(end.month)): \(ChartText.euro(end.balance)).")
        }
        return TrendModel(title: title, lines: [line], markers: markers, summary: parts.joined(separator: " "), caption: caption)
    }
}

// MARK: - Verdeling (donut)

struct DonutSlice: Identifiable, Equatable {
    let id: String
    let name: String
    let value: Double
    /// 0...1
    let share: Double
    /// Kleur per SOORT (vast), niet per plek in de rangorde: dezelfde soort heeft overal dezelfde kleur.
    let colorIndex: Int
}

struct DonutModel: Equatable {
    var slices: [DonutSlice]
    var total: Double
    var summary: String
    var empty: ChartEmpty?

    /// De verdeling van je beleggingen over soorten van nu (per kalenderdag): ook bij een soort (een volle ring van 100%). Een belegging
    /// zonder meetpunt telt mee met haar afgeleide waarde.
    static func holdingKinds(_ d: FinanceData, current: YearMonth, today: Date) -> DonutModel {
        let kinds = d.valueByKind(current: current, today: today).filter { $0.value.isFinite && $0.value > 0 }
        let total = CentsMath.value(CentsMath.sum(kinds.map { CentsMath.int($0.value) }))
        guard total > 0 else {
            let e = ChartEmpty(symbol: "chart.pie", title: "Nog geen verdeling",
                               message: "Zodra een belegging een waarde heeft, zie je hier hoe je geld over soorten is verdeeld.")
            return DonutModel(slices: [], total: 0, summary: "Geen verdeling. Nog geen waarde.", empty: e)
        }
        var slices: [DonutSlice] = []
        for k in kinds {
            slices.append(DonutSlice(id: k.kind.rawValue, name: k.kind.title, value: k.value, share: k.value / total,
                                     colorIndex: k.kind.colorIndex))
        }
        let parts: [String] = slices.map { "\($0.name) \(Int(($0.share * 100).rounded())) procent (\(ChartText.euro($0.value)))" }
        let count = slices.count
        let kindWord: String = count == 1 ? "soort" : "soorten"
        let summary = "Verdeling van je beleggingen over \(count) \(kindWord): " + parts.joined(separator: ", ") + "."
        return DonutModel(slices: slices, total: total, summary: summary, empty: nil)
    }
}

// MARK: - Gestapelde staven per maand (Waar gaat je geld heen)

enum FlowKind: String, CaseIterable, Equatable {
    case expenses, saved, invested, free

    var title: String {
        switch self {
        case .expenses: return "Uitgaven"
        case .saved: return "Gespaard"
        case .invested: return "Belegd"
        case .free: return "Overgehouden"
        }
    }

    var role: ChartRole {
        switch self {
        case .expenses: return .expenses
        case .saved: return .saved
        case .invested: return .invested
        case .free: return .free
        }
    }
}

struct BarSegment: Identifiable, Equatable {
    let id: String
    /// De sleutel van de maand ("2026-10"): de categorie op de x-as.
    let monthID: String
    let kind: FlowKind
    let amount: Double
    let isProjected: Bool
}

/// De streep van het inkomen over de staaf van een maand: bij een tekort steekt de stapel erboven uit.
struct IncomeMark: Identifiable, Equatable {
    let id: String
    let monthID: String
    let income: Double
}

/// Alles over een maand in de grafiek, ook als tekst: voor een tik op een staaf en voor VoiceOver.
struct BarEntry: Identifiable, Equatable {
    let id: String
    let date: Date
    let label: String
    let income: Double
    /// Alleen het deel van de uitgaven dat van je inkomen gaat (wat uit een spaarpot wordt betaald staat al in de pot).
    let expenses: Double
    let saved: Double
    let invested: Double
    /// Wat er over is (nooit negatief); bij een tekort 0.
    let free: Double
    let shortfall: Double
    let isProjected: Bool
    /// De zin voor VoiceOver en bij een tik.
    let text: String
}

struct StackedBarModel: Equatable {
    var bars: [BarSegment]
    var incomeMarks: [IncomeMark]
    var kinds: [FlowKind]
    var entries: [BarEntry]
    var summary: String
    var empty: ChartEmpty?

    /// De maanden waarvan de x-as een label heeft, vast uitgelijnd op de kalender.
    var tickIDs: [String] {
        let stride = ChartAxis.monthStride(span: entries.count)
        var ids: [String] = []
        for entry in entries {
            let month = YearMonth(date: entry.date)
            if stride == 1 || (month.month - 1) % stride == 0 { ids.append(entry.id) }
        }
        if ids.isEmpty, let first = entries.first { ids.append(first.id) }
        return ids
    }

    /// Alleen maanden vanaf de startmaand van de gegevens (daarvoor is er niets en tekende de app lege staven). Bij een tekort steekt
    /// de stapel (uitgaven, gespaard, belegd) boven de inkomenslijn uit en staat het tekort in de tekst; "Overgehouden" blijft op
    /// `max(0, remaining)`. Een verwachte maand heeft "(verwacht)" in zijn tekst.
    static func months(_ summaries: [MonthSummary], startMonth: YearMonth) -> StackedBarModel {
        let shown = summaries.filter { $0.month >= startMonth }
        let hasData = shown.contains { $0.income != 0 || $0.expenses != 0 || $0.saved != 0 || $0.invested != 0 }
        guard hasData else {
            let e = ChartEmpty(symbol: "chart.bar", title: "Nog geen maanden om te tonen",
                               message: "Vul je salaris of een uitgave in, dan zie je per maand waar je geld heen gaat.",
                               action: .openSalary, actionTitle: "Salaris instellen")
            return StackedBarModel(bars: [], incomeMarks: [], kinds: [], entries: [],
                                   summary: "Waar gaat je geld heen. Nog geen maanden om te tonen.", empty: e)
        }
        var bars: [BarSegment] = []
        var marks: [IncomeMark] = []
        var entries: [BarEntry] = []
        for s in shown {
            let monthID = s.month.key
            let fromIncome = max(0, s.expenses - s.fromPots)
            let saved = max(0, s.saved)
            let invested = max(0, s.invested)
            let remaining = s.remaining
            let free = max(0, remaining)
            let shortfall = max(0, -remaining)
            let amounts: [(FlowKind, Double)] = [(.expenses, fromIncome), (.saved, saved), (.invested, invested), (.free, free)]
            for (kind, amount) in amounts where amount > 0 && amount.isFinite {
                bars.append(BarSegment(id: "\(monthID)-\(kind.rawValue)", monthID: monthID, kind: kind, amount: amount,
                                       isProjected: s.isProjected))
            }
            marks.append(IncomeMark(id: monthID, monthID: monthID, income: s.income))
            let projectedNote: String = s.isProjected ? " (verwacht)" : ""
            let leftWord: String = s.isProjected ? "nog te verdelen" : "overgehouden"
            var text = "\(ChartText.monthTitle(s.month))\(projectedNote): inkomen \(ChartText.euro(s.income)), uitgaven \(ChartText.euro(fromIncome)), gespaard \(ChartText.euro(saved)), belegd \(ChartText.euro(invested))"
            if shortfall > 0 {
                text += ", tekort \(ChartText.euro(shortfall))."
            } else {
                text += ", \(leftWord) \(ChartText.euro(free))."
            }
            entries.append(BarEntry(id: monthID, date: s.month.firstDay, label: ChartAxis.monthLabel(s.month.firstDay),
                                    income: s.income, expenses: fromIncome, saved: saved, invested: invested, free: free,
                                    shortfall: shortfall, isProjected: s.isProjected, text: text))
        }
        let kinds = FlowKind.allCases.filter { kind in bars.contains { $0.kind == kind } }
        var summary = "Waar gaat je geld heen, per maand."
        if let first = entries.first, let last = entries.last, entries.count > 1 {
            summary = "Waar gaat je geld heen, van \(Fmt.month(YearMonth(date: first.date))) tot \(Fmt.month(YearMonth(date: last.date)))."
        }
        let shortfalls = entries.filter { $0.shortfall > 0 }.count
        if shortfalls > 0 {
            let monthWord: String = shortfalls == 1 ? "maand" : "maanden"
            summary += " In \(shortfalls) \(monthWord) is er een tekort."
        }
        return StackedBarModel(bars: bars, incomeMarks: marks, kinds: kinds, entries: entries, summary: summary, empty: nil)
    }
}
