# Grafieken: prototype, patch en tests (bijlage bij charts.md)

Alles hieronder is gedraaid of gecontroleerd zoals in `charts.md` staat; niets staat in `App/` of `CoreTests/`. Deze bijlage bestaat zodat de uitvoerder niet afhankelijk is van de tijdelijke proefmappen in `/tmp`.

| Onderdeel | Status |
|---|---|
| B1. Patch C1 (`Invest.swift`) | gecompileerd; de hele `CoreTests` ertegenaan gedraaid (1 test valt, zie `charts.md` 3.5) |
| B2. `PortfolioSeriesDerivedTests` | draait tegen `HEAD` (3 falen, 2 slagen) en tegen de patch (5 slagen) |
| B3. `ChartModels.swift` (Foundation-only) | gecompileerd en gedraaid tegen alle scenario's in `charts.md` |
| B4. `Charts.sketch.swift` (SwiftUI) | alleen syntaxcontrole (tree-sitter, 0 foutknopen); niet gecompileerd |

## B1. Patch C1: afgeleid beginpunt voor een belegging zonder meetpunt

Diff tegen `App/Core/Invest.swift` (alleen `historicState` en zijn twee aanroepen; `current` wordt doorgegeven omdat het beginpunt de inleg tot nu toe terugrekent):

```diff
@@ -35,9 +35,30 @@
     /// het nog de 9e is. Dat is de goede basis voor grafieken en prognoses (die rekenen per maand verder). Met `today` rekent
     /// de waarde per KALENDERDAG, zoals de bank en de spaarpotten: een inleg telt pas mee vanaf de dag waarop hij wordt
     /// overgeschreven (`transferDay(for:in:)`, dezelfde dag als in de dagboekhouding), en dan de hele dag.
-    private func historicState(_ h: Holding, at month: YearMonth, cache: IncomeBasesCache,
+    /// PROEF (fixcheck): een belegging zonder meetpunt krijgt een afgeleid beginpunt uit "Totaal ingelegd" en de inleg.
+    private func derivedOpening(_ h: Holding, current: YearMonth, cache: IncomeBasesCache, today: Date?) -> ValueSnapshot? {
+        let hasPlan = h.monthlyContribution != 0 || (h.contributionMode == .percentage && h.contributionPercent > 0)
+        guard h.investedTotal > 0 || hasPlan else { return nil }
+        var later = 0.0
+        var m = h.startMonth.adding(1)
+        let todayMonth = today.map { YearMonth(date: $0) }
+        while m <= current {
+            if let today, let todayMonth, m >= todayMonth,
+               DayMath.isPlanned(m.date(day: transferDay(for: h.id, in: m)), asOf: today) {
+                m = m.adding(1)
+                continue
+            }
+            later += allocation(h.id, in: m, cache: cache)
+            m = m.adding(1)
+        }
+        let opening = max(0, h.investedTotal - later).cents
+        return ValueSnapshot(date: h.startMonth.firstDay, value: opening, invested: opening)
+    }
+
+    private func historicState(_ h: Holding, at month: YearMonth, current: YearMonth, cache: IncomeBasesCache,
                                today: Date? = nil) -> HoldingState? {
-        let snaps = h.snapshots.sorted { $0.date < $1.date }
+        var snaps = h.snapshots.sorted { $0.date < $1.date }
+        if snaps.isEmpty, let opening = derivedOpening(h, current: current, cache: cache, today: today) { snaps = [opening] }
         guard let snap = snaps.last(where: { $0.date < month.endExclusive }) else { return nil }
         var value = snap.value
         var invested = snap.invested
@@ -69,8 +90,8 @@
     /// altijd uit van het EINDE van `current` (de prognose rekent per maand verder).
     private func holdingState(_ h: Holding, at month: YearMonth, current: YearMonth, cache: IncomeBasesCache,
                               today: Date? = nil) -> HoldingState? {
-        if month <= current { return historicState(h, at: month, cache: cache, today: today) }
-        guard let base = historicState(h, at: current, cache: cache) else { return nil }
+        if month <= current { return historicState(h, at: month, current: current, cache: cache, today: today) }
+        guard let base = historicState(h, at: current, current: current, cache: cache) else { return nil }
         var value = base.value
         var invested = base.invested
         let rm = Growth.monthlyRate(annual: h.netReturn)
```

Nog te doen bij de echte wijziging (niet in de proef): `HoldingState.isEstimated` en `PortfolioPoint.isEstimated` (C2), `portfolioDataStart` (C3), de klem op 0 na `current` (C4), en `HoldingDayTests.testHoldingWithoutMeasurementHasNoStateNow` aanpassen.

## B2. Falende testbeschrijving

Bestand `CoreTests/Tests/MyBuddyCoreTests/PortfolioSeriesDerivedTests.swift` (nieuw; gebruikt `oct2026`, `day(_:_:)` uit `TestSupport.swift`). Tegen `HEAD`: `testHoldingWithOnlyInvestedTotalHasAValueAndASeries`, `testHoldingWithOnlyAMonthlyContributionHasASeries` en `testTickerWithUnitsButNoPriceStillGivesASeriesFromInvestedTotal` falen; de twee andere zijn vangnet.

```swift
import XCTest
@testable import MyBuddyCore

/// Falende beschrijving van de fout "grafiek bij Beleggingen werkt niet": wat de gebruiker invult (ingelegd bedrag,
/// maandinleg, ticker met aantal) moet een reeks opleveren, ook zonder meetpunt. Deze tests falen op HEAD.
final class PortfolioSeriesDerivedTests: XCTestCase {
    private func fresh() -> FinanceData {
        var d = FinanceData(startMonth: oct2026)
        d.materialize(upTo: oct2026)
        return d
    }

    private let today = day(oct2026, 15)

    func testHoldingWithOnlyInvestedTotalHasAValueAndASeries() {
        var d = fresh()
        d.addHolding(Holding(name: "Fonds", kind: .etf, ticker: nil, units: nil, investedTotal: 3_000,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 200, startMonth: oct2026))
        // Wat de gebruiker bij "Totaal ingelegd" typte, is de waarde en het ingelegde bedrag van nu.
        XCTAssertEqual(d.portfolioInvested(current: oct2026, today: today), 3_000, accuracy: 0.001)
        XCTAssertEqual(d.portfolioValue(current: oct2026, today: today), 3_000, accuracy: 0.001)
        let series = d.portfolioSeries(from: oct2026, count: 4, current: oct2026, today: today)
        XCTAssertEqual(series.count, 4)
        XCTAssertEqual(series.map(\.value), [3_000, 3_200, 3_400, 3_600])
        XCTAssertEqual(series.map(\.isProjected), [false, true, true, true])
    }

    func testHoldingWithOnlyAMonthlyContributionHasASeries() {
        var d = fresh()
        d.addHolding(Holding(name: "Inleg", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 200, startMonth: oct2026))
        let series = d.portfolioSeries(from: oct2026, count: 3, current: oct2026, today: today)
        XCTAssertEqual(series.map(\.value), [0, 200, 400])
    }

    func testTickerWithUnitsButNoPriceStillGivesASeriesFromInvestedTotal() {
        var d = fresh()
        d.addHolding(Holding(name: "VWCE", kind: .etf, ticker: "VWCE.DE", units: 10, investedTotal: 1_000,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: oct2026))
        XCTAssertFalse(d.portfolioSeries(from: oct2026, count: 3, current: oct2026, today: today).isEmpty)
    }

    func testMeasuredHoldingIsUnchangedByTheFallback() {
        var d = fresh()
        let h = Holding(name: "Fonds", kind: .etf, ticker: nil, units: nil, investedTotal: 900,
                        expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: oct2026)
        d.addHolding(h, initialValue: 1_000, now: today)
        XCTAssertEqual(d.portfolioValue(current: oct2026, today: today), 1_000, accuracy: 0.001)
    }

    func testHoldingWithoutAnyDataStaysEmpty() {
        var d = fresh()
        d.addHolding(Holding(name: "Leeg", kind: .etf, ticker: nil, units: nil, investedTotal: 0,
                             expectedReturn: 0, annualCost: 0, monthlyContribution: 0, startMonth: oct2026))
        XCTAssertTrue(d.portfolioSeries(from: oct2026, count: 3, current: oct2026, today: today).isEmpty)
    }
}
```

## B3. `App/UI/ChartModels.swift` (voorstel, Foundation-only)

Bevat: `ChartPoint`, `ChartLine` (met `segments`), `ChartMarker`, `ChartEmpty`, `TrendModel`, `ChartAxis` (`domain`, `ticks`, `yLabels`, `monthLabel`, `monthStride`, `downsample`), `ChartText`, `PortfolioWindow`, `PortfolioTrend` (model en lege staten), `DonutModel`, `FlowKind`, `StackedBarModel`. In het proefpakket staat bovenaan `@testable import MyBuddyCore`; in de app is dat dezelfde module. De bouwers voor de andere pagina's (`PriceTrend`, `NetWorthTrend`, `BankTrend`, `DayBalanceTrend`, `ProjectionTrend`, `BufferTrend`, `SavingsGoalTrend`, `GoalCurveTrend`, `PotTrend`) ontbreken hier en volgen de vorm van `PortfolioTrend`.

```swift
import Foundation
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// VOORSTEL App/UI/ChartModels.swift: Foundation-only (geen SwiftUI), dus te testen in CoreTests via een symlink zoals
// CashflowDisplay.swift. Dit bestand staat nu alleen in het proefpakket en is daar gecompileerd en gedraaid.

// MARK: - Basistypen

enum ChartPointKind: String, Equatable {
    /// Gemeten of ingevulde waarde.
    case actual
    /// Afgeleid uit je inleg (nog geen meetpunt): getekend als lijn zonder vlak.
    case estimated
    /// Verwacht (na vandaag): gestippeld.
    case projected
}

struct ChartPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let value: Double
    let kind: ChartPointKind
}

enum ChartDash: Equatable { case solid, dashed, dotted }
/// De view vertaalt een rol naar een kleur uit `Theme`; zo blijft dit bestand Foundation-only.
enum ChartRole: Equatable {
    case primary, secondary, tertiary, warning, negative
    case flowExpenses, flowSaved, flowInvested, flowFree
}

struct ChartLine: Identifiable, Equatable {
    let id: String
    let name: String
    var points: [ChartPoint]
    var dash: ChartDash = .solid
    var role: ChartRole = .primary
    var fillsArea = false
}

/// Een aaneengesloten stuk van een lijn met dezelfde soort punten (werkelijk, afgeleid of verwacht).
struct ChartSegment: Identifiable, Equatable {
    let id: String
    let kind: ChartPointKind
    let points: [ChartPoint]
}

extension ChartLine {
    /// Stukken van dezelfde soort; elk stuk begint met het laatste punt van het vorige, zodat de lijn aansluit
    /// (dat deed `TimeLineChart` met `bridge`). Een stuk van één punt (één werkelijk punt) is een stip, geen lijn.
    var segments: [ChartSegment] {
        var result: [ChartSegment] = []
        var current: [ChartPoint] = []
        for p in points {
            if let last = current.last, last.kind != p.kind {
                result.append(ChartSegment(id: "\(id)-\(result.count)", kind: last.kind, points: current))
                current = [last]   // aansluitpunt
            }
            current.append(p)
        }
        if let last = current.last { result.append(ChartSegment(id: "\(id)-\(result.count)", kind: last.kind, points: current)) }
        return result
    }
}

struct ChartMarker: Identifiable, Equatable {
    enum Kind: Equatable { case goal, zero, threshold }
    let id: String
    let value: Double
    let label: String
    let kind: Kind
}

/// Lege staat: waarom er niets te tekenen valt en wat de gebruiker kan doen.
struct ChartEmpty: Equatable {
    enum Action: Equatable { case refreshPrices, enterValue(UUID), enterUnits(UUID), addHolding, enterBankBalance, openSalary, retry }
    var symbol: String
    var title: String
    var message: String
    var action: Action?
    var actionTitle: String?
}

enum ChartXAxis: Equatable {
    case months
    case days
    /// Verstreken tijd sinds de eerste datum, in `unit` (toekomstschatting).
    case elapsed(HorizonUnit)
}

struct TrendModel: Equatable {
    var title: String
    var lines: [ChartLine]
    var markers: [ChartMarker] = []
    var xAxis: ChartXAxis = .months
    /// Kernzin voor onder de grafiek en voor VoiceOver (`accessibilityValue`).
    var summary: String
    /// Uitleg bij een afgeleide of beperkte reeks ("Geschat uit je inleg ...").
    var note: String?
    var empty: ChartEmpty?

    var allPoints: [ChartPoint] { lines.flatMap(\.points) }
    /// Aantal maanden dat de grafiek beslaat (voor de afstand tussen x-labels).
    var monthSpan: Int {
        let dates = allPoints.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        return YearMonth(date: first).months(to: YearMonth(date: last)) + 1
    }
    /// y-domein: altijd lo < hi, altijd eindig (zie `ChartAxis.domain`).
    func domain(includeZero: Bool = false, nonNegative: Bool = false) -> ClosedRange<Double> {
        ChartAxis.domain(allPoints.map(\.value) + markers.map(\.value), includeZero: includeZero, nonNegative: nonNegative)
    }
}

// MARK: - As-logica

enum ChartAxis {
    /// Domein met lo < hi gegarandeerd; niet-eindige waarden tellen niet mee. `includeZero` voor staven en voortgang.
    static func domain(_ values: [Double], includeZero: Bool = false, nonNegative: Bool = false) -> ClosedRange<Double> {
        let finite = values.filter { $0.isFinite }
        guard var lo = finite.min(), var hi = finite.max() else { return 0...1 }
        let dataMin = lo
        if includeZero { lo = min(lo, 0); hi = max(hi, 0) }
        let spread = hi - lo
        let pad = spread > 0 ? spread * 0.08 : max(abs(hi) * 0.05, 1)
        lo -= pad; hi += pad
        if nonNegative || (includeZero && dataMin >= 0) { lo = max(lo, 0) }
        return lo...hi
    }

    /// Nette tickwaarden binnen `domain` (1, 2 of 5 maal een tientallige macht); voor `AxisMarks(values:)`.
    static func ticks(in domain: ClosedRange<Double>, count: Int = 4) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, span.isFinite else { return [domain.lowerBound] }
        let raw = span / Double(max(1, count))
        let magnitude = pow(10, floor(log10(raw)))
        let norm = raw / magnitude
        let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * magnitude
        var tick = (domain.lowerBound / step).rounded(.up) * step
        var out: [Double] = []
        while tick <= domain.upperBound + step * 1e-9, out.count < 12 {
            out.append(abs(tick) < step * 1e-9 ? 0 : tick)
            tick += step
        }
        return out
    }

    /// y-labels: zo kort mogelijk, maar naburige ticks houden verschillende labels.
    /// `step` = afstand tussen twee ticks; onder 1 euro komen er centen bij.
    static func yLabels(_ ticks: [Double]) -> [String] {
        let step = ticks.count > 1 ? abs(ticks[1] - ticks[0]) : 1
        func fixed(_ x: Double, _ d: Int) -> String { String(format: "%.\(d)f", x).replacingOccurrences(of: ".", with: ",") }
        func short(_ v: Double, _ digits: Int) -> String {
            let a = abs(v), sign = v < 0 ? "-" : ""
            if a >= 1_000_000 { return sign + "€" + fixed(a / 1_000_000, digits) + " mln" }
            if a >= 1_000 { return sign + "€" + fixed(a / 1_000, digits) + "k" }
            return sign + "€" + fixed(a, step < 1 ? 2 : 0)
        }
        func unique(_ l: [String]) -> Bool { Set(l).count == l.count }
        let biggest = ticks.map { abs($0) }.max() ?? 0
        let l0 = ticks.map { short($0, 0) }
        if unique(l0) { return l0 }
        let whole = ticks.map { Fmt.euroWhole($0).replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "") }
        if biggest < 10_000, unique(whole) { return whole }
        let l1 = ticks.map { short($0, 1) }
        if unique(l1) { return l1 }
        if unique(whole) { return whole }
        let cents = ticks.map { Fmt.euroExact($0).replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "") }
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

    /// Dunt een reeks uit tot hooguit `limit` punten en houdt ALTIJD het eerste en het laatste punt
    /// (`GoalCurveChart` verloor het laatste punt).
    static func downsample<T>(_ items: [T], limit: Int) -> [T] {
        guard items.count > limit, limit > 1 else { return items }
        let last = items.count - 1
        let step = Int((Double(last) / Double(limit - 1)).rounded(.up))
        var indices = Array(stride(from: 0, through: last, by: max(1, step)))
        if indices.last != last { indices.append(last) }
        return indices.map { items[$0] }
    }
}

// MARK: - Teksten (VoiceOver en onderschrift)

enum ChartText {
    /// "8.966 euro" (zonder valutateken, zoals VoiceOver het goed leest).
    static func euro(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = Fmt.locale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = abs(value) < 100 && value != value.rounded() ? 2 : 0
        return (nf.string(from: NSNumber(value: value)) ?? "\(value)") + " euro"
    }

    static func signedEuro(_ value: Double) -> String {
        (value >= 0 ? "plus " : "min ") + euro(abs(value))
    }
}

// MARK: - Beleggingen

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

    /// Alleen de keuzes die een ander beeld geven. `availableMonths` = aantal maanden gegevens t/m de huidige maand.
    /// Een venster van n maanden terug toont n + 1 maanden; het verschilt van "Alles" pas bij meer dan n + 1 maanden gegevens.
    static func options(availableMonths: Int) -> [PortfolioWindow] {
        let shorter = [PortfolioWindow.sixMonths, .year, .threeYears].filter { $0.rawValue + 1 < availableMonths }
        // Een keuzebalk met alleen "Alles" kiest niets: dan geen balk.
        return shorter.isEmpty ? [] : shorter + [.all]
    }
}

enum PortfolioTrend {
    /// Voorwaartse horizon in maanden (verwachting).
    static let forwardMonths = 12

    static func model(_ data: FinanceData, window: PortfolioWindow, current: YearMonth, today: Date,
                      derived: Set<UUID>) -> TrendModel {
        let title = "Waarde van je beleggingen"
        // Eerst alles vanaf (current - 120): het eerste gegeven bepaalt het begin, het venster knipt daarna.
        let all = data.portfolioSeries(from: current.adding(-120), count: 121 + forwardMonths, current: current, today: today)
        guard let first = all.first else { return empty(data, title: title) }
        let from = window == .all ? first.month : max(first.month, current.adding(-window.rawValue))
        let pts = all.filter { $0.month >= from }
        let allEstimated = !data.holdings.isEmpty && data.holdings.allSatisfy { derived.contains($0.id) || $0.snapshots.isEmpty }
        let line = ChartLine(id: "total", name: "Waarde", points: pts.map { p in
            ChartPoint(id: p.id, date: p.month.firstDay, value: p.value,
                       kind: p.isProjected ? .projected : (allEstimated ? .estimated : .actual))
        }, role: .primary, fillsArea: true)
        let actual = pts.filter { !$0.isProjected }
        let now = actual.last
        var parts: [String] = ["Waarde van je beleggingen."]
        if let now { parts.append("Nu \(ChartText.euro(now.value)).") }
        if let a = actual.first, let n = now, actual.count > 1 {
            parts.append("Sinds \(Fmt.month(a.month)) \(ChartText.signedEuro(n.value - a.value)).")
        }
        if let end = pts.last, end.isProjected { parts.append("Verwacht in \(Fmt.month(end.month)): \(ChartText.euro(end.value)).") }
        var note: String?
        if allEstimated {
            note = "Geschat uit je inleg: je hebt nog geen koers of waarde ingevuld. Vul een waarde in of ververs de koers voor het echte verloop."
        } else if actual.count < 2 {
            note = "Je echte verloop begint op \(Fmt.date(today)). Het gestippelde deel is verwacht."
        }
        return TrendModel(title: title, lines: [line], summary: parts.joined(separator: " "), note: note, empty: nil)
    }

    static func empty(_ data: FinanceData, title: String) -> TrendModel {
        let e: ChartEmpty
        if data.holdings.isEmpty {
            e = ChartEmpty(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                           message: "Voeg een ETF, aandeel, crypto of spaarrekening toe.",
                           action: .addHolding, actionTitle: "Belegging toevoegen")
        } else if let h = data.holdings.first(where: { $0.hasTicker && !$0.isTracked }) {
            e = ChartEmpty(symbol: "number", title: "Vul het aantal stuks in",
                           message: "Met een ticker en een aantal rekent de app de waarde van \(h.name) uit.",
                           action: .enterUnits(h.id), actionTitle: "Aantal invullen")
        } else if data.holdings.contains(where: { $0.isTracked }) {
            e = ChartEmpty(symbol: "arrow.clockwise", title: "Wachten op de koers",
                           message: "Zodra de koers binnen is, zie je hier je waarde. Controleer anders je internet en de ticker.",
                           action: .refreshPrices, actionTitle: "Koers vernieuwen")
        } else {
            let id = data.holdings[0].id
            e = ChartEmpty(symbol: "pencil.and.list.clipboard", title: "Nog geen waarde",
                           message: "Vul de huidige waarde of het ingelegde bedrag van een belegging in, dan tekent de app je groei.",
                           action: .enterValue(id), actionTitle: "Waarde invullen")
        }
        return TrendModel(title: title, lines: [], summary: "Geen gegevens. \(e.title).", note: nil, empty: e)
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

    static func holdingKinds(_ d: FinanceData, current: YearMonth, today: Date) -> DonutModel {
        let kinds = d.valueByKind(current: current, today: today)
        let total = CentsMath.value(CentsMath.sum(kinds.map { CentsMath.int($0.value) }))
        guard total > 0 else {
            let e = ChartEmpty(symbol: "chart.pie", title: "Nog geen verdeling",
                               message: "Zodra een belegging een waarde heeft, zie je hier hoe je geld over soorten is verdeeld.",
                               action: nil, actionTitle: nil)
            return DonutModel(slices: [], total: 0, summary: "Geen verdeling. Nog geen waarde.", empty: e)
        }
        let slices = kinds.map { k in
            DonutSlice(id: k.kind.rawValue, name: k.kind.title, value: k.value, share: k.value / total,
                       colorIndex: HoldingKind.allCases.firstIndex(of: k.kind) ?? 0)
        }
        let parts = slices.map { "\($0.name) \(Int(($0.share * 100).rounded())) procent (\(ChartText.euro($0.value)))" }
        return DonutModel(slices: slices, total: total,
                          summary: "Verdeling van je beleggingen over \(slices.count) \(slices.count == 1 ? "soort" : "soorten"): " + parts.joined(separator: ", ") + ".",
                          empty: nil)
    }
}

// MARK: - Gestapelde staven per maand (waar gaat je geld heen)

enum FlowKind: String, CaseIterable, Equatable {
    case expenses, saved, invested, free

    var title: String {
        switch self {
        case .expenses: return "Uitgaven"
        case .saved: return "Gespaard"
        case .invested: return "Belegd"
        case .free: return "Over"
        }
    }

    var role: ChartRole {
        switch self {
        case .expenses: return .flowExpenses
        case .saved: return .flowSaved
        case .invested: return .flowInvested
        case .free: return .flowFree
        }
    }
}

struct BarSegment: Identifiable, Equatable {
    let id: String
    let date: Date
    let kind: FlowKind
    let amount: Double
    let isProjected: Bool
}

struct IncomeMark: Identifiable, Equatable {
    let id: String
    let start: Date
    let end: Date
    let income: Double
}

struct StackedBarModel: Equatable {
    var bars: [BarSegment]
    var incomeMarks: [IncomeMark]
    var kinds: [FlowKind]
    var summaries: [String]
    var empty: ChartEmpty?

    /// Alleen maanden vanaf de startmaand van de gegevens (daarvoor is er niets en tekent de app nu lege staven).
    /// Bij een tekort steekt de balk (uitgaven + gespaard + belegd) boven de inkomenslijn uit; het tekort staat in de samenvatting.
    static func months(_ summaries: [MonthSummary], startMonth: YearMonth) -> StackedBarModel {
        let shown = summaries.filter { $0.month >= startMonth }
        let hasData = shown.contains { $0.income != 0 || $0.expenses != 0 || $0.saved != 0 || $0.invested != 0 }
        guard hasData else {
            let e = ChartEmpty(symbol: "chart.bar", title: "Nog geen maanden om te tonen",
                               message: "Vul je salaris of een uitgave in, dan zie je per maand waar je geld heen gaat.",
                               action: .openSalary, actionTitle: "Salaris instellen")
            return StackedBarModel(bars: [], incomeMarks: [], kinds: [], summaries: [], empty: e)
        }
        var bars: [BarSegment] = []
        var marks: [IncomeMark] = []
        var texts: [String] = []
        for s in shown {
            let date = s.month.firstDay
            let fromIncome = max(0, s.expenses - s.fromPots)
            let free = max(0, s.remaining)
            let shortfall = max(0, -s.remaining)
            func add(_ kind: FlowKind, _ amount: Double) {
                if amount > 0 { bars.append(BarSegment(id: "\(s.id)-\(kind.rawValue)", date: date, kind: kind, amount: amount, isProjected: s.isProjected)) }
            }
            add(.expenses, fromIncome); add(.saved, max(0, s.saved)); add(.invested, max(0, s.invested))
            add(.free, free)
            marks.append(IncomeMark(id: s.id, start: date, end: s.month.endExclusive, income: s.income))
            var text = "\(Fmt.month(s.month))\(s.isProjected ? " (verwacht)" : ""): inkomen \(ChartText.euro(s.income)), uitgaven \(ChartText.euro(fromIncome)), gespaard \(ChartText.euro(s.saved)), belegd \(ChartText.euro(s.invested))"
            text += shortfall > 0 ? ", tekort \(ChartText.euro(shortfall))." : ", over \(ChartText.euro(free))."
            texts.append(text)
        }
        let kinds = FlowKind.allCases.filter { k in bars.contains { $0.kind == k } }
        return StackedBarModel(bars: bars, incomeMarks: marks, kinds: kinds, summaries: texts, empty: nil)
    }
}
```

## B4. `App/UI/Charts.swift` (schets, alleen syntaxcontrole)

`TrendChart`, `TrendAxes`, `ChartEmptyView`, `TrendDescriptor` (`AXChartDescriptorRepresentable`), `ProgressMeter`, `DonutChart`, `StackedBarChart`. Niet gecompileerd: `StackedBarDescriptor` en een paar `Theme`-waarden zijn alleen benoemd. De AX-namen zijn gecontroleerd tegen Apple's documentatie (iOS 15 en macOS 12), `SectorMark` en `ContentUnavailableView` zijn iOS 17 en macOS 14, dus veilig voor iOS 18 en macOS 15.

```swift
import SwiftUI
import Charts
import Accessibility

// MARK: - Lijn/vlak met afgeleid en verwacht deel

struct TrendChart: View {
    enum Size {
        case compact, regular, tall
        var height: CGFloat {
            switch self {
            case .compact: return 96
            case .regular: return 180
            case .tall: return 240
            }
        }
    }

    let model: TrendModel
    var size: Size = .regular
    var showsAxes = true
    /// Een waarde onder nul bestaat niet (beleggingen, spaarpotten): het domein begint dan op 0.
    var nonNegative = false
    var onAction: (ChartEmpty.Action) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        if let empty = model.empty {
            ChartEmptyView(empty: empty, height: size.height, onAction: onAction)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                chart
                if let note = model.note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chart: some View {
        let domain = model.domain(nonNegative: nonNegative)
        let ticks = ChartAxis.ticks(in: domain, count: size == .compact ? 3 : 4)
        let labels = ChartAxis.yLabels(ticks)
        return Chart {
            ForEach(model.lines) { line in
                ForEach(line.segments) { segment in
                    if segment.points.count == 1, segment.kind != .projected {
                        // Eén werkelijk punt: een stip met een vorm, niet alleen een kleur.
                        PointMark(x: .value("Datum", segment.points[0].date), y: .value("Waarde", segment.points[0].value))
                            .symbol(.circle)
                            .foregroundStyle(line.role.color)
                    } else {
                        ForEach(segment.points) { p in
                            LineMark(x: .value("Datum", p.date), y: .value("Waarde", p.value),
                                     series: .value("Stuk", segment.id))
                                .foregroundStyle(line.role.color)
                                .lineStyle(segment.kind.strokeStyle(base: line.dash))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
            }
            ForEach(model.markers) { marker in
                RuleMark(y: .value(marker.label, marker.value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text(marker.label).font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYScale(domain: domain)
        .modifier(TrendAxes(shown: showsAxes, ticks: ticks, labels: labels, monthSpan: model.monthSpan))
        .frame(height: size.height)
        .animation(reduceMotion ? nil : Theme.motion, value: model)
        .accessibilityChartDescriptor(TrendDescriptor(model: model))
    }
}

/// As-stijl voor alle lijngrafieken: y compact en uniek gelabeld, x met maandlabels (en jaartal bij januari).
private struct TrendAxes: ViewModifier {
    let shown: Bool
    let ticks: [Double]
    let labels: [String]
    let monthSpan: Int

    func body(content: Content) -> some View {
        if shown {
            content
                .chartYAxis {
                    AxisMarks(position: .leading, values: ticks) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self), let i = ticks.firstIndex(of: v) {
                                Text(labels[i]).font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: ChartAxis.monthStride(span: monthSpan))) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(ChartAxis.monthLabel(date)).font(.caption2)
                            }
                        }
                    }
                }
        } else {
            content.chartXAxis(.hidden).chartYAxis(.hidden)
        }
    }
}

extension ChartRole {
    var color: Color {
        switch self {
        case .primary: return Theme.accent
        case .secondary: return Theme.flowInvested
        case .tertiary: return Theme.flowExpenses
        case .warning: return Theme.warning
        case .negative: return Theme.negative
        case .flowExpenses: return Theme.flowExpenses
        case .flowSaved: return Theme.flowSaved
        case .flowInvested: return Theme.flowInvested
        case .flowFree: return Theme.flowFree
        }
    }
}

extension ChartPointKind {
    func strokeStyle(base: ChartDash) -> StrokeStyle {
        switch self {
        case .actual: return StrokeStyle(lineWidth: 2.5)
        case .estimated: return StrokeStyle(lineWidth: 2, dash: [2, 3])
        case .projected: return StrokeStyle(lineWidth: 2, dash: [6, 4])
        }
    }
}

// MARK: - Lege staat (zelfde hoogte als de grafiek, geen sprong in de pagina)

struct ChartEmptyView: View {
    let empty: ChartEmpty
    let height: CGFloat
    let onAction: (ChartEmpty.Action) -> Void

    var body: some View {
        ContentUnavailableView {
            Label(empty.title, systemImage: empty.symbol)
        } description: {
            Text(empty.message)
        } actions: {
            if let action = empty.action, let title = empty.actionTitle {
                Button(title) { onAction(action) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

// MARK: - VoiceOver: titel, samenvatting en elk punt

struct TrendDescriptor: AXChartDescriptorRepresentable {
    let model: TrendModel

    func makeChartDescriptor() -> AXChartDescriptor {
        let cal = YearMonth.calendar
        func name(_ date: Date) -> String {
            model.xAxis == .days ? DayText.short(date) : Fmt.shortMonthYear(YearMonth(date: date, calendar: cal))
        }
        let order = model.lines.first?.points.map { name($0.date) } ?? []
        let x = AXCategoricalDataAxisDescriptor(title: model.xAxis == .days ? "Dag" : "Maand", categoryOrder: order)
        let range = model.domain()
        let y = AXNumericDataAxisDescriptor(title: "Bedrag in euro", range: range, gridlinePositions: []) { value in
            ChartText.euro(value)
        }
        let series = model.lines.map { line in
            AXDataSeriesDescriptor(name: line.name, isContinuous: true, dataPoints: line.points.map { p in
                AXDataPoint(x: name(p.date), y: p.value, additionalValues: [],
                            label: p.kind == .projected ? "verwacht" : nil)
            })
        }
        return AXChartDescriptor(title: model.title, summary: model.summary, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: series)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        descriptor.summary = model.summary
    }
}

// MARK: - Voortgang (balk of ring), met waarde voor VoiceOver

struct ProgressMeter: View {
    enum Style { case bar(height: CGFloat), ring(lineWidth: CGFloat) }

    /// nil = er is geen doel: dan tekent de component niets (geen volle ring).
    let value: Double?
    var tint: Color
    var style: Style = .bar(height: 8)
    let label: String
    let valueText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let value {
            let shown = value.isFinite ? min(1, max(0, value)) : 0
            meter(shown)
                .animation(reduceMotion ? nil : Theme.motion, value: shown)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
        }
    }

    @ViewBuilder
    private func meter(_ shown: Double) -> some View {
        switch style {
        case .bar(let height):
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.22))
                    Capsule().fill(tint).frame(width: geo.size.width * shown)
                }
            }
            .frame(height: height)
        case .ring(let lineWidth):
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
                Circle().trim(from: 0, to: shown)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

// MARK: - Verdeling (donut) met lijst eronder

struct DonutChart: View {
    let model: DonutModel
    var height: CGFloat = 160

    var body: some View {
        if let empty = model.empty {
            ChartEmptyView(empty: empty, height: height, onAction: { _ in })
        } else {
            VStack(spacing: 12) {
                Chart(model.slices) { slice in
                    SectorMark(angle: .value("Waarde", slice.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(Theme.color(slice.colorIndex))
                }
                .chartLegend(.hidden)
                .frame(height: height)
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("Totaal").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.euro(model.total)).font(.headline)
                    }
                }
                ForEach(model.slices) { slice in
                    HStack {
                        Circle().fill(Theme.color(slice.colorIndex)).frame(width: 10, height: 10)
                        Text(slice.name)
                        Spacer()
                        Text(Fmt.euro(slice.value)).monospacedDigit()
                        Text(Fmt.percent(slice.share, digits: 0)).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Verdeling van je beleggingen")
            .accessibilityValue(model.summary)
        }
    }
}

// MARK: - Gestapelde staven per maand

struct StackedBarChart: View {
    let model: StackedBarModel
    var height: CGFloat = 180
    var showsAxes = true

    var body: some View {
        if let empty = model.empty {
            ChartEmptyView(empty: empty, height: height, onAction: { _ in })
        } else {
            Chart {
                ForEach(model.bars) { bar in
                    BarMark(x: .value("Maand", bar.date, unit: .month), y: .value("Bedrag", bar.amount))
                        .foregroundStyle(by: .value("Soort", bar.kind.title))
                        .opacity(bar.isProjected ? 0.55 : 1)
                        .cornerRadius(2)
                }
                ForEach(model.incomeMarks) { mark in
                    RuleMark(xStart: .value("Van", mark.start), xEnd: .value("Tot", mark.end), y: .value("Inkomen", mark.income))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Color.primary)
                }
            }
            .chartForegroundStyleScale(domain: model.kinds.map(\.title), range: model.kinds.map { $0.role.color })
            .frame(height: height)
            .accessibilityChartDescriptor(StackedBarDescriptor(model: model))
        }
    }
}
```

## B5. Wat de proefscripts opleverden (kern)

Voorbeeld van `TrendModel` per scenario (uit `probe model`):

```
sample:                      punten 18 actual=6 projected=12; VoiceOver: Waarde van je beleggingen. Nu 8.966 euro. Sinds mei 2026 plus 1.616 euro. Verwacht in oktober 2027: 12.573 euro.
B1 ticker+aantal, geen koers punten 13 estimated=1 projected=12; y-labels €1.000 | €1.020 | €1.040 | €1.060; onderschrift "Geschat uit je inleg ..."
B3 alleen inleg 200:         punten 13 estimated=1 projected=12
belegging zonder bedrag:     LEGE STAAT Nog geen waarde | actie Waarde invullen
B1c ticker zonder aantal:    LEGE STAAT Vul het aantal stuks in | actie Aantal invullen
lege data:                   LEGE STAAT Nog geen beleggingen | actie Belegging toevoegen
```

Reproduceren: zie bijlage A van `charts.md`.
