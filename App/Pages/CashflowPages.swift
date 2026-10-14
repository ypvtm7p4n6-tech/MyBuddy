import SwiftUI
import Charts

// MARK: - Dagen in woorden

/// Korte Nederlandse teksten voor dagen en datums ("de 25e", "ma 25 okt").
enum DayText {
    static let weekdays = ["zo", "ma", "di", "wo", "do", "vr", "za"]

    /// "de 25e"
    static func ordinal(_ day: Int) -> String {
        "de \(day)e"
    }

    /// "25 okt"
    static func short(_ date: Date) -> String {
        let cal = YearMonth.calendar
        let number = cal.component(.day, from: date)
        return "\(number) \(Fmt.shortMonth(YearMonth(date: date, calendar: cal)))"
    }

    /// "ma 25 okt"
    static func weekdayShort(_ date: Date) -> String {
        let cal = YearMonth.calendar
        let weekday = cal.component(.weekday, from: date) // 1 = zondag
        let name = weekdays[min(max(weekday - 1, 0), 6)]
        return "\(name) \(short(date))"
    }

    /// "Vakantie", "Vakantie en Fun", "Vakantie, Fun en Auto"
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " en " + names[names.count - 1]
        }
    }

    /// Valt `date` op dezelfde kalenderdag als `other`?
    static func isSameDay(_ date: Date, _ other: Date) -> Bool {
        YearMonth.calendar.isDate(date, inSameDayAs: other)
    }
}

// MARK: - Logica van de dagschermen (zonder SwiftUI)
//
// Alles tussen "BEGIN LOGICA" en "EINDE LOGICA" is Foundation-only en leest alleen uit de dagboekhouding van de
// rekenmotor (`MonthLedger` en `DayTotals`, zie Ledger.swift). Er wordt hier geen bedrag zelf uitgerekend: de
// schermen tonen wat de motor levert, zodat Overzicht, "Nog te verdelen", spaarpotten, bankrekening en dagen
// precies dezelfde cijfers hebben. Alleen waar een bedrag uit twee motorwaarden samengesteld wordt (bijvoorbeeld
// "overgeschreven" = spaarpotten + beleggingen) gebeurt dat in hele centen en staat het hieronder uitgelegd.

// BEGIN LOGICA

/// Bedragen met teken, voor regels en tegels.
enum CashflowText {
    /// "+ € 3.000", "− € 1.000" of "€ 0" (zonder teken bij nul).
    static func signed(_ amount: Double) -> String {
        let sign = amount > 0 ? "+ " : (amount < 0 ? "− " : "")
        return sign + Fmt.euro(abs(amount))
    }
}

/// Houdt de dagboekhouding van de maanden bij die één scherm nodig heeft, zodat elke maand per berekening maar één keer
/// wordt uitgerekend (`monthLedger` kost enkele milliseconden; per dag aanroepen is veel duurder). Maak er één per `body`.
final class LedgerBook {
    let data: FinanceData
    let today: Date
    private var cache: [YearMonth: MonthLedger] = [:]

    init(_ data: FinanceData, today: Date) {
        self.data = data
        self.today = today
    }

    /// De dagboekhouding van een maand.
    func ledger(_ month: YearMonth) -> MonthLedger {
        if let known = cache[month] { return known }
        let made = data.monthLedger(month, asOf: today)
        cache[month] = made
        return made
    }

    /// De cijfers van de kalenderdag waar `date` in valt.
    func day(_ date: Date) -> DayTotals {
        let cal = YearMonth.calendar
        let list = ledger(YearMonth(date: date, calendar: cal))
        let number = DayMath.dayNumber(of: date, calendar: cal)
        return list.days[min(max(number, 1), list.days.count) - 1]
    }

    /// De dagen van `from` t/m `to` (maximaal 800), ook over maandgrenzen heen. Elke dag heeft zijn cijfers uit de
    /// dagboekhouding van zijn eigen maand.
    func days(from: Date, to: Date, limit: Int = 800) -> [DayTotals] {
        let cal = YearMonth.calendar
        let first = cal.startOfDay(for: from)
        let last = cal.startOfDay(for: to)
        guard last >= first else { return [] }
        var result: [DayTotals] = []
        var month = YearMonth(date: first, calendar: cal)
        let lastMonth = YearMonth(date: last, calendar: cal)
        while month <= lastMonth && result.count < limit {
            for day in ledger(month).days {
                let start = cal.startOfDay(for: day.date)
                guard start >= first && start <= last else { continue }
                result.append(day)
                if result.count >= limit { break }
            }
            month = month.adding(1)
        }
        return result
    }
}

extension DayTotals {
    /// Wat er die dag naar spaarpotten en beleggingen samen gaat, in hele centen opgeteld uit `toPots` en `toHoldings`.
    /// Negatief als er die dag meer van een spaarpot terug naar de bank gaat dan erheen.
    var totalTransferred: Double {
        CentsMath.value(CentsMath.add(CentsMath.int(toPots), CentsMath.int(toHoldings)))
    }
}

extension MonthLedger {
    /// Het aantal salarisuitbetalingen in de maand (meer dan één bij een schema om de zoveel weken of dagen).
    var salaryPayoutCount: Int {
        days.reduce(0) { total, day in total + day.events.filter { $0.kind == .salary }.count }
    }
}

/// Het laagste dagsaldo uit een rij dagen.
enum CashflowLowPoint {
    /// De dag met het laagste bekende saldo (bij gelijke saldi de eerste). nil als geen enkele dag een saldo heeft.
    static func lowest(in days: [DayTotals]) -> DayTotals? {
        var best: DayTotals?
        var bestBalance = 0.0
        for day in days {
            guard let balance = day.bankBalance else { continue }
            if best == nil || balance < bestBalance {
                best = day
                bestBalance = balance
            }
        }
        return best
    }
}

/// Welke dagen de lijst toont.
enum CashflowDayFilter: String, CaseIterable, Identifiable {
    case all, withEntries
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Alle dagen"
        case .withEntries: return "Alleen met boekingen"
        }
    }

    /// De dagen van de maand die erbij horen. Vandaag blijft er altijd bij: daar scrolt de lijst naartoe en het saldo
    /// van vandaag wil je kunnen zien.
    func days(of ledger: MonthLedger) -> [DayTotals] {
        switch self {
        case .all: return ledger.days
        case .withEntries: return ledger.days.filter { $0.hasActivity || $0.isToday }
        }
    }
}

/// Ankers om naar een dag te scrollen.
enum CashflowScroll {
    static func dayID(_ day: Int) -> String { "cashflow-day-\(day)" }
}

/// De controle "klopt het met je overzicht?". Is alles in orde (`MonthLedger.allReconciles`), dan zijn er geen
/// meldingen. Anders staat er per afwijking een Nederlandse zin met het verschil, zodat de gebruiker ziet waar het zit.
struct LedgerCheck: Equatable {
    struct Issue: Identifiable, Equatable {
        let id: String
        let text: String
    }

    let issues: [Issue]
    var isOK: Bool { issues.isEmpty }

    init(_ ledger: MonthLedger) {
        var found: [Issue] = []
        if !ledger.bankReconciles { found.append(contentsOf: LedgerCheck.bankIssues(ledger)) }
        if !ledger.potsReconciles { found.append(contentsOf: LedgerCheck.potsIssues(ledger)) }
        if !ledger.overviewReconciles { found.append(contentsOf: LedgerCheck.overviewIssues(ledger)) }
        issues = found
    }

    /// Een verschil in centen als bedrag zonder teken.
    private static func text(_ cents: Int) -> String {
        Fmt.euroExact(CentsMath.value(abs(cents)))
    }

    private static func bankIssues(_ l: MonthLedger) -> [Issue] {
        var out: [Issue] = []
        if let opening = l.openingBank, let closing = l.closingBank {
            var expected = CentsMath.int(opening)
            expected = CentsMath.add(expected, CentsMath.int(l.inflow))
            expected = CentsMath.add(expected, -CentsMath.int(l.outflow))
            expected = CentsMath.add(expected, -CentsMath.int(l.toPots))
            expected = CentsMath.add(expected, -CentsMath.int(l.toHoldings))
            expected = CentsMath.add(expected, CentsMath.int(l.bankCorrections))
            let difference = CentsMath.int(closing) - expected
            if difference != 0 {
                out.append(Issue(id: "bank-month",
                                 text: "Bankrekening: het eindsaldo wijkt \(text(difference)) af van begin + binnen − eruit − overgeschreven."))
            }
        }
        if let day = l.days.first(where: { !$0.bankReconciles }),
           let before = day.openingBank, let after = day.bankBalance {
            let expected = CentsMath.add(CentsMath.int(before), CentsMath.int(day.bankChange))
            let difference = CentsMath.int(after) - expected
            out.append(Issue(id: "bank-day-\(day.day)",
                             text: "Bankrekening op \(DayText.weekdayShort(day.date)): het saldo wijkt \(text(difference)) af van het saldo van de dag ervoor plus wat er die dag binnenkwam en eruit ging."))
        }
        if out.isEmpty {
            out.append(Issue(id: "bank", text: "Het saldo van je bankrekening sluit niet met de cijfers van deze maand."))
        }
        return out
    }

    private static func potsIssues(_ l: MonthLedger) -> [Issue] {
        var out: [Issue] = []
        var expected = CentsMath.int(l.openingPots)
        expected = CentsMath.add(expected, CentsMath.int(l.planToPots))
        expected = CentsMath.add(expected, CentsMath.int(l.potEntriesNet))
        expected = CentsMath.add(expected, CentsMath.int(l.interest))
        expected = CentsMath.add(expected, -CentsMath.int(l.paidFromPots))
        let difference = CentsMath.int(l.closingPots) - expected
        if difference != 0 {
            out.append(Issue(id: "pots-month",
                             text: "Spaarpotten: het eindsaldo wijkt \(text(difference)) af van begin + inleg + rente − betaald uit potten."))
        }
        if let day = l.days.first(where: { !$0.potsReconciles }) {
            let dayExpected = CentsMath.add(CentsMath.int(day.openingPots), CentsMath.int(day.potsChange))
            let dayDifference = CentsMath.int(day.potsTotal) - dayExpected
            out.append(Issue(id: "pots-day-\(day.day)",
                             text: "Spaarpotten op \(DayText.weekdayShort(day.date)): het totaal wijkt \(text(dayDifference)) af van het totaal van de dag ervoor plus wat er die dag bijkwam en afging."))
        }
        if out.isEmpty {
            out.append(Issue(id: "pots", text: "Het totaal van je spaarpotten sluit niet met de cijfers van deze maand."))
        }
        return out
    }

    private static func overviewIssues(_ l: MonthLedger) -> [Issue] {
        var out: [Issue] = []
        func compare(_ title: String, overview: Double, days: Double) {
            let a = CentsMath.int(overview)
            let b = CentsMath.int(days)
            guard a != b else { return }
            out.append(Issue(id: "overview-\(title)",
                             text: "\(title): overzicht \(Fmt.euroExact(overview)), dagen \(Fmt.euroExact(days)) (verschil \(text(a - b)))."))
        }
        compare("Inkomen", overview: l.income, days: l.planInflow)
        compare("Uitgaven van je rekening", overview: l.expensesFromBank, days: l.planOutflow)
        compare("Uitgaven uit spaarpotten", overview: l.expensesFromPots, days: l.paidFromPots)
        compare("Gespaard", overview: l.saved, days: l.planToPots)
        compare("Belegd", overview: l.invested, days: l.toHoldings)
        var remaining = CentsMath.int(l.planInflow)
        remaining = CentsMath.add(remaining, -CentsMath.int(l.planOutflow))
        remaining = CentsMath.add(remaining, -CentsMath.int(l.planToPots))
        remaining = CentsMath.add(remaining, -CentsMath.int(l.toHoldings))
        compare("Nog te verdelen", overview: l.remaining, days: CentsMath.value(remaining))
        if let last = l.days.last {
            compare("Nog te verdelen op de laatste dag", overview: l.remaining, days: last.remainingSoFar)
        }
        if out.isEmpty {
            out.append(Issue(id: "overview", text: "De dagen sluiten niet met het overzicht van deze maand."))
        }
        return out
    }
}

/// De regels van een maand op id, om een tik op een gebeurtenis naar de juiste regel te brengen.
struct CashflowLineLookup {
    let income: [UUID: MoneyLine]
    let expenses: [UUID: MoneyLine]

    init(plan: MonthPlan) {
        income = Dictionary(plan.extraIncome.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        expenses = Dictionary(plan.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// EINDE LOGICA

// MARK: - Een gebeurtenis in beeld

/// Hoe een gebeurtenis eruitziet: icoon, kleur en bedrag. Inkomen en rente groen, uitgaven rood,
/// overschrijvingen naar potten en beleggingen olijf.
struct DayEventStyle {
    let symbol: String
    let color: Color
    let kindText: String
    let amount: Double

    init(_ event: DayEvent) {
        let shown = event.bankAmount != 0 ? event.bankAmount : event.potAmount
        amount = shown
        switch event.kind {
        case .salary:
            symbol = "briefcase.fill"
            color = Theme.positive
            kindText = "Salaris"
        case .income:
            symbol = "plus.circle.fill"
            color = Theme.positive
            kindText = "Inkomsten"
        case .expense:
            let fromPotOnly = event.bankAmount == 0 && event.potAmount != 0
            symbol = fromPotOnly ? "tray.full.fill" : "minus.circle.fill"
            color = Theme.negative
            kindText = fromPotOnly ? "Uitgave uit spaarpot" : "Uitgave"
        case .toPot:
            symbol = "tray.and.arrow.down.fill"
            color = Theme.accent
            kindText = "Overschrijving naar spaarpot"
        case .toHolding:
            symbol = "chart.line.uptrend.xyaxis"
            color = Theme.accent
            kindText = "Overschrijving naar belegging"
        case .interest:
            symbol = "percent"
            color = Theme.positive
            kindText = "Rente op spaarpot"
        case .bankEntry:
            symbol = "building.columns.fill"
            color = shown < 0 ? Theme.negative : (shown > 0 ? Theme.positive : Theme.accent)
            kindText = "Boeking op je rekening"
        }
    }

    /// "+ € 3.000" of "− € 1.000"
    var amountText: String {
        CashflowText.signed(amount)
    }
}

/// Eén regel met een gebeurtenis: icoon, titel, soort en bedrag. Geplande gebeurtenissen zijn iets lichter.
/// Met `showsDate` staat de datum bij de soort (voor salaris dat vaker dan eens per maand binnenkomt).
struct DayEventRow: View {
    let event: DayEvent
    var showsDate = false
    var showsChevron = false

    private var caption: String {
        var parts = [DayEventStyle(event).kindText]
        if showsDate { parts.append(DayText.short(event.date)) }
        if event.isPlanned { parts.append("gepland") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let style = DayEventStyle(event)
        HStack(spacing: 10) {
            SymbolBadge(symbol: style.symbol, color: style.color, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(style.amountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: style.amountText)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(event.isPlanned ? 0.8 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - De cijfers van één dag

/// Eén regel met een omschrijving links en een bedrag rechts (saldo's op een dag).
private struct DayValueRow: View {
    let title: String
    var caption: String? = nil
    let text: String
    var color: Color = .primary
    var bold = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(text)
                .font(Font.subheadline.weight(bold ? .bold : .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: text)
        }
    }
}

/// Een kleine tegel met een titel en een bedrag.
private struct DayFigureTile: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .animation(Theme.motion, value: text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .tile()
    }
}

/// Binnen, eruit en overgeschreven van één dag. Het teken laat zien welke kant het opgaat; "Overgeschreven" staat er alleen
/// als er die dag iets naar spaarpotten of beleggingen gaat (of terug naar de bank).
struct DayFlowTiles: View {
    let day: DayTotals

    var body: some View {
        let moved = day.totalTransferred
        HStack(spacing: 8) {
            DayFigureTile(title: "Binnen", text: CashflowText.signed(day.inflow),
                          color: day.inflow > 0 ? Theme.positive : Color.secondary)
            DayFigureTile(title: "Eruit", text: CashflowText.signed(-day.outflow),
                          color: day.outflow > 0 ? Theme.negative : Color.secondary)
            if moved != 0 {
                DayFigureTile(title: moved > 0 ? "Overgeschreven" : "Teruggeboekt",
                              text: Fmt.euro(abs(moved)), color: Theme.accent)
            }
        }
    }
}

/// Het saldo van de bankrekening en van de spaarpotten aan het eind van een dag, en wat er die dag nog te verdelen is.
/// Precies de waarden van `DayTotals`, op de kaart van de dag en in het blok "Per dag" op de bankpagina.
struct DayBalanceRows: View {
    let day: DayTotals
    var showsBank = true
    var showsPots = true
    var showsRemaining = true

    var body: some View {
        VStack(spacing: 8) {
            if showsBank {
                if let balance = day.bankBalance {
                    DayValueRow(title: "Saldo bankrekening", caption: "Aan het eind van de dag", text: Fmt.euro(balance),
                                color: balance < 0 ? Theme.negative : Color.primary, bold: true)
                } else {
                    DayValueRow(title: "Saldo bankrekening", text: "onbekend", color: Color.secondary)
                }
            }
            if let measured = day.measuredBalance {
                DayValueRow(title: "Saldo dat je invulde", caption: "Zo vulde je het zelf in voor deze dag",
                            text: Fmt.euro(measured))
                if day.bankCorrection != 0 {
                    DayValueRow(title: "Verschil met wat de app verwachtte", text: CashflowText.signed(day.bankCorrection),
                                color: day.bankCorrection < 0 ? Theme.negative : Theme.positive)
                }
            }
            if showsPots {
                DayValueRow(title: "Spaarpotten totaal", caption: "Aan het eind van de dag", text: Fmt.euro(day.potsTotal))
                if day.potEntriesNet != 0 {
                    DayValueRow(title: "Handmatig op spaarpotten", text: CashflowText.signed(day.potEntriesNet))
                }
            }
            if showsRemaining {
                DayValueRow(title: "Nog te verdelen", caption: "Deze maand, t/m deze dag", text: Fmt.euro(day.remainingSoFar),
                            color: day.remainingSoFar < 0 ? Theme.negative : Color.primary)
            }
        }
    }
}

// MARK: - Grafiek van het dagsaldo

/// Eén punt van de dagsaldo-grafiek.
struct DayChartItem: Identifiable, Equatable {
    let id: Date
    let value: Double
    let planned: Bool
    var date: Date { id }
}

/// Lijn met vlak eronder voor het saldo aan het eind van elke dag. Geplande dagen (na vandaag) staan gestippeld en lichter,
/// de nulstreep is rood gestippeld. Een gekozen dag krijgt een stip. De punten zijn de dagen uit de dagboekhouding,
/// dus dezelfde saldi als op de dagkaarten.
struct DayBalanceChart: View {
    let days: [DayTotals]
    var selected: Date? = nil
    var height: CGFloat = 190

    /// Punten voor de grafiek: de dagen met een bekend saldo.
    static func items(from days: [DayTotals]) -> [DayChartItem] {
        days.compactMap { day -> DayChartItem? in
            guard let balance = day.bankBalance else { return nil }
            return DayChartItem(id: day.date, value: balance, planned: day.isPlanned)
        }
    }

    var body: some View {
        let items = DayBalanceChart.items(from: days)
        let actual = items.filter { !$0.planned }
        let bridge: [DayChartItem] = actual.last.map { [$0] } ?? []
        let future = bridge + items.filter { $0.planned }
        let lowest = items.min(by: { $0.value < $1.value })
        let chosen: DayChartItem? = selected.flatMap { day in
            items.first(where: { DayText.isSameDay($0.date, day) })
        }
        // De hoogte volgt de saldi, met wat ruimte. Zo zie je het dagverloop ook bij een hoog saldo.
        // De nulstreep staat er alleen bij als nul binnen beeld valt.
        let lowValue = lowest?.value ?? 0
        let highValue = items.map { $0.value }.max() ?? 0
        let pad = max((highValue - lowValue) * 0.12, 50)
        let floorValue = lowValue - pad
        let ceilingValue = highValue + pad
        let showsZero = floorValue <= 0 && ceilingValue >= 0
        Chart {
            ForEach(items) { item in
                AreaMark(x: .value("Dag", item.date),
                         yStart: .value("Basis", floorValue),
                         yEnd: .value("Saldo", item.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.linear)
            }
            ForEach(actual) { item in
                LineMark(x: .value("Dag", item.date), y: .value("Saldo", item.value),
                         series: .value("Soort", "Werkelijk"))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.linear)
            }
            if future.count > 1 {
                ForEach(future) { item in
                    LineMark(x: .value("Dag", item.date), y: .value("Saldo", item.value),
                             series: .value("Soort", "Verwacht"))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.linear)
                }
            }
            if showsZero {
                RuleMark(y: .value("Nul", 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.negative.opacity(0.7))
            }
            if let low = lowest, low.value < 0 {
                PointMark(x: .value("Dag", low.date), y: .value("Saldo", low.value))
                    .foregroundStyle(Theme.negative)
            }
            if let pick = chosen {
                PointMark(x: .value("Dag", pick.date), y: .value("Saldo", pick.value))
                    .foregroundStyle(Color.primary)
            }
        }
        .chartYScale(domain: floorValue...ceilingValue)
        .chartAxes(shown: true)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(DayText.short(date)).font(.caption2) }
                }
            }
        }
        .frame(height: height)
        .animation(Theme.motion, value: items)
        .accessibilityLabel("Grafiek van je banksaldo per dag")
    }
}

// MARK: - Waarschuwing: onder nul of onder de buffer

/// Meldt wanneer het dagsaldo onder nul komt (of onder de gewenste buffer), met de datum.
/// Voor de huidige maand kijkt hij vanaf vandaag (een dip in het verleden verbergt dan geen dip die nog komt)
/// en 30 dagen vooruit, dus ook over de maandwisseling heen. Voor andere maanden kijkt hij naar de hele maand.
/// De saldi komen uit de dagboekhouding, dezelfde als op de dagkaarten. Toont niets als alles in orde is.
struct BankLowPointNotice: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    private struct Note {
        let text: String
        let severe: Bool
    }

    /// De dag met het laagste saldo in het bereik dat bij deze maand hoort.
    private func lowestPoint(_ book: LedgerBook, today: Date) -> DayTotals? {
        let cal = YearMonth.calendar
        let todayStart = cal.startOfDay(for: today)
        let monthEnd = month.date(day: month.dayCount)
        var from = month.firstDay
        var to = monthEnd
        if month == store.now {
            from = todayStart
            let ahead = cal.date(byAdding: .day, value: 30, to: todayStart) ?? todayStart
            to = max(monthEnd, ahead)
        }
        return CashflowLowPoint.lowest(in: book.days(from: from, to: to))
    }

    var body: some View {
        let d = store.data
        let today = store.today
        let book = LedgerBook(d, today: today)
        if let low = lowestPoint(book, today: today), let lowBalance = low.bankBalance {
            let buffer = d.bankBuffer(current: store.now)
            let balanceNow = d.bankBalanceNowIfKnown(current: store.now, today: today)
            if let note = makeNote(for: low, balance: lowBalance, buffer: buffer, balanceNow: balanceNow) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: note.severe ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(note.severe ? Theme.negative : Theme.warning)
                    Text(note.text)
                        .font(.footnote)
                        .foregroundStyle(note.severe ? Theme.negative : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(Theme.cardInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(tint: (note.severe ? Theme.negative : Theme.warning).opacity(0.22))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func makeNote(for low: DayTotals, balance lowBalance: Double, buffer: Double, balanceNow: Double?) -> Note? {
        let cal = YearMonth.calendar
        let today = store.today
        let past = cal.startOfDay(for: low.date) < cal.startOfDay(for: today)
        let isToday = DayText.isSameDay(low.date, today)
        let day = DayText.weekdayShort(low.date)
        let balance = Fmt.euro(lowBalance)
        if lowBalance < 0 {
            if past {
                return Note(text: "Op \(day) stond je saldo onder nul (\(balance)).", severe: true)
            }
            let when = isToday ? "vandaag" : "op \(day)"
            return Note(text: "Let op: \(when) staat je saldo onder nul (\(balance)). Kijk of je een uitgave of overschrijving naar een andere dag kunt zetten.",
                        severe: true)
        }
        // De buffermelding is bedoeld voor een dip die je plan veroorzaakt. Zit je nu al onder je buffer,
        // dan zie je dat bij het blok Buffer en blijft deze balk weg, zodat de melding "onder nul" opvalt.
        // Is het saldo van nu niet bekend, dan is er niets om mee te vergelijken en blijft de melding ook weg.
        if let now = balanceNow, buffer > 0 && lowBalance < buffer && now >= buffer && !past {
            let start = isToday ? "Vandaag" : "Op \(day)"
            return Note(text: "\(start) zakt je saldo naar \(balance). Dat is onder je gewenste buffer van \(Fmt.euro(buffer)).",
                        severe: false)
        }
        return nil
    }
}

// MARK: - Bankrekening: per dag

/// Hoe ver de dagsaldo-grafiek kijkt: de komende 30 dagen of de gekozen maand.
enum DayChartRange: String, CaseIterable, Identifiable {
    case next30, month
    var id: String { rawValue }
}

/// Blok "Per dag" op de bankpagina: kies een datum en zie wat er die dag binnenkomt, eruit gaat en wordt overgeschreven,
/// het saldo van de bankrekening en de spaarpotten aan het eind van de dag, en wat er t/m die dag nog te verdelen is.
/// Dat zijn dezelfde `DayTotals` als op de pagina "Dag voor dag". Eronder een grafiek van het dagsaldo.
struct BankDayBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var date = Date()
    @State private var rangeChoice: DayChartRange?

    private struct ChartWindow {
        let from: Date
        let to: Date
    }

    private func chartWindow(_ range: DayChartRange, focus: YearMonth, today: Date) -> ChartWindow {
        let cal = YearMonth.calendar
        let todayStart = cal.startOfDay(for: today)
        switch range {
        case .next30:
            let end = cal.date(byAdding: .day, value: 29, to: todayStart) ?? todayStart
            return ChartWindow(from: todayStart, to: end)
        case .month:
            return ChartWindow(from: focus.firstDay, to: focus.date(day: focus.dayCount))
        }
    }

    /// De dagen die je kunt kiezen: vanaf de eerste dag van de startmaand van de gegevens tot twee jaar na vandaag.
    /// Zonder grens rekent elke body alle maanden vanaf het laatste saldo door (een datum in het jaar 3000 kost
    /// bijna een seconde), en zoiets ver vooruit zegt niets.
    private var dayRange: ClosedRange<Date> {
        let cal = YearMonth.calendar
        let upper = cal.date(byAdding: .year, value: 2, to: store.today) ?? store.today
        // Vandaag valt altijd binnen het bereik, ook als de startmaand (na een import) later ligt.
        let lower = min(store.data.startMonth.firstDay, cal.startOfDay(for: store.today))
        return lower...upper
    }

    private func clampedDay(_ value: Date) -> Date {
        let range = dayRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// De gekozen dag, met een korte animatie zodat saldo en gebeurtenissen niet hard omspringen.
    private var animatedDate: Binding<Date> {
        Binding<Date>(get: { date },
                      set: { newValue in withAnimation(Theme.quickMotion) { date = clampedDay(newValue) } })
    }

    private func shiftDay(_ amount: Int) {
        let cal = YearMonth.calendar
        withAnimation(Theme.quickMotion) {
            date = clampedDay(cal.date(byAdding: .day, value: amount, to: date) ?? date)
        }
    }

    var body: some View {
        let d = store.data
        let today = store.today
        let focus = router.focusMonth
        let book = LedgerBook(d, today: today)
        let defaultRange: DayChartRange = focus == store.now ? .next30 : .month
        let range = rangeChoice ?? defaultRange
        GlassBlock(title: "Per dag", symbol: "calendar",
                   subtitle: "Binnen, eruit en saldo op elke dag",
                   tint: Theme.olive.opacity(0.3)) {
            dayPicker(today: today)
            dayDetails(d, book: book, today: today)
            chartSection(book, range: range, defaultRange: defaultRange, focus: focus, today: today)
        }
        .onAppear {
            if focus != store.now { date = clampedDay(focus.date(day: 1)) }
        }
        .onChange(of: router.focusMonth) { _, newMonth in
            rangeChoice = nil
            withAnimation(Theme.quickMotion) {
                date = clampedDay(newMonth == store.now ? store.today : newMonth.date(day: 1))
            }
        }
    }

    // MARK: Onderdelen

    @ViewBuilder
    private func dayPicker(today: Date) -> some View {
        HStack {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left").padding(8).contentShape(Rectangle())
            }
            .accessibilityLabel("Vorige dag")
            Spacer()
            DatePicker("Dag", selection: animatedDate, in: dayRange, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Fmt.locale)
            Spacer()
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right").padding(8).contentShape(Rectangle())
            }
            .accessibilityLabel("Volgende dag")
        }
        .buttonStyle(.plain)
        if !DayText.isSameDay(date, today) {
            ChipButton(title: "Terug naar vandaag", symbol: "arrow.uturn.backward") {
                withAnimation(Theme.quickMotion) { date = today }
            }
        }
    }

    @ViewBuilder
    private func dayDetails(_ d: FinanceData, book: LedgerBook, today: Date) -> some View {
        let totals = book.day(date)
        let multipleSalaries = book.ledger(YearMonth(date: date)).salaryPayoutCount > 1
        VStack(alignment: .leading, spacing: 2) {
            Text("Saldo aan het eind van \(totals.isToday ? "vandaag" : DayText.weekdayShort(date))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let balance = totals.bankBalance {
                BigAmount(value: balance, font: .system(.title, design: .rounded, weight: .bold),
                          color: balance < 0 ? Theme.negative : Color.primary)
            } else {
                Text("Op deze dag is je saldo nog niet bekend.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if totals.isPlanned {
                Text("Verwacht: deze dag ligt nog voor je.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        DayFlowTiles(day: totals)
        if totals.events.isEmpty {
            Text("Op deze dag komt er niets binnen en gaat er niets weg.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(totals.events) { event in
                    DayEventRow(event: event, showsDate: multipleSalaries && event.kind == .salary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(10)
            .tile()
        }
        DayBalanceRows(day: totals, showsBank: false, showsPots: !d.pots.isEmpty)
        if !d.hasBankBalance {
            Text("Vul je saldo in of zet er geld op. Dan zie je per dag hoeveel je hebt, ook voor dagen die nog komen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chartSection(_ book: LedgerBook, range: DayChartRange, defaultRange: DayChartRange,
                              focus: YearMonth, today: Date) -> some View {
        let span = chartWindow(range, focus: focus, today: today)
        let days = book.days(from: span.from, to: span.to).filter { $0.bankBalance != nil }
        let lowest = CashflowLowPoint.lowest(in: days)
        Divider()
        Picker("Periode van de grafiek", selection: Binding(get: { rangeChoice ?? defaultRange },
                                                           set: { rangeChoice = $0 })) {
            Text("Komende 30 dagen").tag(DayChartRange.next30)
            Text(Fmt.month(focus)).tag(DayChartRange.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if days.count > 1 {
            DayBalanceChart(days: days, selected: date)
            if let low = lowest, let lowBalance = low.bankBalance, let end = days.last, let endBalance = end.bankBalance {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    StatTile(title: "Laagste saldo", value: Fmt.euro(lowBalance),
                             color: lowBalance < 0 ? Theme.negative : Color.primary,
                             caption: DayText.short(low.date))
                    StatTile(title: "Saldo op het eind", value: Fmt.euro(endBalance),
                             color: endBalance < 0 ? Theme.negative : Color.primary,
                             caption: DayText.short(end.date))
                }
            }
            Text("Gestippeld en lichter is gepland. De rode stippellijn is nul.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Voor deze periode is je saldo nog niet bekend.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bankrekening: komende 14 dagen

/// Wat er de komende 14 dagen gebeurt, dag voor dag, met het saldo aan het eind van elke dag (uit de dagboekhouding).
struct BankUpcomingBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let today = store.today
        let cal = YearMonth.calendar
        let start = cal.startOfDay(for: today)
        let end = cal.date(byAdding: .day, value: 13, to: start) ?? start
        let book = LedgerBook(d, today: today)
        let busy = book.days(from: start, to: end).filter { !$0.events.isEmpty }
        GlassBlock(title: "Komende 14 dagen", symbol: "calendar.badge.clock",
                   subtitle: "\(DayText.short(start)) t/m \(DayText.short(end))") {
            if busy.isEmpty {
                Text("De komende 14 dagen komt er niets binnen en gaat er niets weg.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(busy) { day in
                        UpcomingDayRow(day: day)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        if day.id != busy.last?.id { Divider() }
                    }
                }
            }
            if !d.hasBankBalance {
                Text("Vul je saldo in om ook het saldo per dag te zien.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ChipButton(title: "Alle dagen bekijken", symbol: "calendar") {
                // Het pad van de tab waar je nu bent, zodat "terug" bij deze pagina uitkomt.
                router.open(.cashflow)
            }
        }
    }
}

/// Eén dag in de lijst "Komende 14 dagen": datum, saldo aan het eind van de dag en de gebeurtenissen.
struct UpcomingDayRow: View {
    let day: DayTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DayText.weekdayShort(day.date)).font(.subheadline.weight(.semibold))
                    if day.isToday { Text("Vandaag").font(.caption).foregroundStyle(Theme.accent) }
                }
                Spacer(minLength: 8)
                if let balance = day.bankBalance {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Saldo").font(.caption2).foregroundStyle(.secondary)
                        Text(Fmt.euro(balance))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(balance < 0 ? Theme.negative : Color.primary)
                            .contentTransition(.numericText())
                            .animation(Theme.motion, value: balance)
                    }
                }
            }
            ForEach(day.events) { event in
                DayEventRow(event: event)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Dag voor dag: de maand in cijfers

/// Eén regel in een sluitend overzicht: teken, omschrijving en bedrag.
private struct LedgerLineRow: View {
    enum Style { case line, detail, total }

    let sign: String
    let title: String
    let amount: Double?
    var tone: Color = .primary
    var style: Style = .line
    var note: String? = nil
    /// Toont het bedrag met een plus of min (voor regels die ook negatief kunnen zijn).
    var showsSign = false

    private var titleFont: Font {
        switch style {
        case .line: return Font.subheadline
        case .detail: return Font.footnote
        case .total: return Font.subheadline.weight(.bold)
        }
    }

    private var amountFont: Font {
        switch style {
        case .line: return Font.subheadline.weight(.semibold)
        case .detail: return Font.footnote
        case .total: return Font.subheadline.weight(.bold)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(sign)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(style == .detail ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            amountView
        }
        .padding(.leading, style == .detail ? 22 : 0)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var amountView: some View {
        if let amount {
            Text(showsSign ? CashflowText.signed(amount) : Fmt.euro(amount))
                .font(amountFont)
                .foregroundStyle(style == .detail ? Color.secondary : tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: amount)
        } else {
            Text("onbekend")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Rij die naar een pagina leidt, met het bedrag zoals op die pagina.
private struct LedgerLinkRow: View {
    let symbol: String
    let title: String
    var caption: String? = nil
    let value: Double
    var tone: Color = .primary
    let destination: Destination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: symbol, color: Theme.accent, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let caption {
                        Text(caption).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(Fmt.euro(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(Theme.motion, value: value)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .tile()
        }
        .buttonStyle(.plain)
    }
}

/// De bankrekening van de maand: begin, wat er binnenkwam, eruit ging en werd overgeschreven, en het eind.
/// Handmatige stortingen, opnames en overboekingen staan er apart bij als ze er zijn.
struct CashflowBankBlock: View {
    let ledger: MonthLedger
    let lowest: DayTotals?
    /// Het saldo van nu (alleen in de huidige maand, en alleen als het bekend is).
    let balanceNow: Double?
    /// Is er ooit een saldo ingevuld of een boeking gemaakt?
    let hasBalance: Bool

    var body: some View {
        let lowBalance = lowest?.bankBalance
        let lowText = lowBalance.map { Fmt.euro($0) } ?? "–"
        let lowCaption = lowest.map { DayText.weekdayShort($0.date) }
        let payouts = ledger.salaryPayoutCount
        let toPotsOut = ledger.toPots >= 0
        GlassBlock(title: "Bankrekening", symbol: "building.columns.fill", subtitle: Fmt.month(ledger.month),
                   tint: Theme.olive.opacity(0.3)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                if let balanceNow {
                    StatTile(title: "Saldo nu", value: Fmt.euro(balanceNow),
                             color: balanceNow < 0 ? Theme.negative : Color.primary)
                }
                StatTile(title: "Laagste saldo", value: lowText,
                         color: (lowBalance ?? 0) < 0 ? Theme.negative : Color.primary,
                         caption: lowCaption)
            }
            VStack(spacing: 8) {
                LedgerLineRow(sign: "", title: "Begin van de maand", amount: ledger.openingBank, style: .total)
                LedgerLineRow(sign: "+", title: "Binnen", amount: ledger.inflow, tone: Theme.positive,
                              note: payouts > 1 ? "Met \(payouts) salarisuitbetalingen" : nil)
                if ledger.manualInflow != 0 {
                    LedgerLineRow(sign: "", title: "Salaris en inkomsten", amount: ledger.planInflow, style: .detail)
                    LedgerLineRow(sign: "", title: "Handmatig gestort", amount: ledger.manualInflow, style: .detail)
                }
                LedgerLineRow(sign: "−", title: "Eruit", amount: ledger.outflow, tone: Theme.negative)
                if ledger.manualOutflow != 0 {
                    LedgerLineRow(sign: "", title: "Uitgaven van je rekening", amount: ledger.planOutflow, style: .detail)
                    LedgerLineRow(sign: "", title: "Handmatig opgenomen", amount: ledger.manualOutflow, style: .detail)
                }
                if ledger.toPots != 0 {
                    LedgerLineRow(sign: toPotsOut ? "−" : "+",
                                  title: toPotsOut ? "Overgeschreven naar spaarpotten" : "Teruggeboekt van spaarpotten",
                                  amount: abs(ledger.toPots), tone: Theme.accent)
                    if ledger.manualToPots != 0 {
                        LedgerLineRow(sign: "", title: "Maandverdeling", amount: ledger.planToPots, style: .detail)
                        LedgerLineRow(sign: "", title: "Handmatig overgeboekt", amount: ledger.manualToPots,
                                      style: .detail, showsSign: true)
                    }
                }
                if ledger.toHoldings != 0 {
                    LedgerLineRow(sign: "−", title: "Overgeschreven naar beleggingen", amount: ledger.toHoldings,
                                  tone: Theme.accent)
                }
                if ledger.bankCorrections != 0 {
                    LedgerLineRow(sign: "±", title: "Verschil met je ingevulde saldo", amount: ledger.bankCorrections,
                                  note: "Je vulde een saldo in dat afweek van wat de app verwachtte.", showsSign: true)
                }
                Divider()
                LedgerLineRow(sign: "=", title: "Eind van de maand", amount: ledger.closingBank, style: .total)
            }
            if ledger.openingBank == nil && ledger.closingBank != nil {
                Text("Je saldo is pas later in de maand bekend, dus er is nog geen beginsaldo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !hasBalance {
                Text("Vul je saldo in op de bankrekening. Dan rekent de app per dag uit hoeveel je hebt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// De spaarpotten van de maand: begin, inleg, rente, wat er uit potten is betaald en het eind.
struct CashflowPotsBlock: View {
    let ledger: MonthLedger

    var body: some View {
        GlassBlock(title: "Spaarpotten", symbol: "tray.full.fill", subtitle: Fmt.month(ledger.month),
                   headerLink: .pots) {
            VStack(spacing: 8) {
                LedgerLineRow(sign: "", title: "Begin van de maand", amount: ledger.openingPots, style: .total)
                if ledger.planToPots != 0 {
                    LedgerLineRow(sign: "+", title: "Inleg volgens je verdeling", amount: ledger.planToPots, tone: Theme.accent)
                }
                if ledger.potEntriesNet != 0 {
                    LedgerLineRow(sign: "±", title: "Handmatige boekingen", amount: ledger.potEntriesNet,
                                  note: "Stortingen, opnames en overboekingen die je zelf deed.", showsSign: true)
                }
                if ledger.interest != 0 {
                    LedgerLineRow(sign: "+", title: "Rente", amount: ledger.interest, tone: Theme.positive)
                }
                if ledger.paidFromPots != 0 {
                    LedgerLineRow(sign: "−", title: "Betaald uit potten", amount: ledger.paidFromPots, tone: Theme.negative)
                }
                Divider()
                LedgerLineRow(sign: "=", title: "Eind van de maand", amount: ledger.closingPots, style: .total)
            }
            Text("Inleg telt mee vanaf de overschrijfdag, rente vanaf de uitbetaaldag en een uitgave uit een pot vanaf de dag van die uitgave.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// De koppeling met het Overzicht: inkomen, uitgaven, gespaard, belegd en nog te verdelen van de maand, met precies
/// dezelfde waarden als op het Overzicht, en de controle of alles sluit.
struct CashflowOverviewBlock: View {
    let ledger: MonthLedger
    let check: LedgerCheck

    var body: some View {
        let fromPots = ledger.expensesFromPots
        GlassBlock(title: "Je overzicht", symbol: "chart.bar.xaxis", subtitle: "Dezelfde cijfers als in je overzicht") {
            VStack(spacing: 8) {
                LedgerLinkRow(symbol: "briefcase.fill", title: "Inkomen", value: ledger.income, destination: .income)
                LedgerLinkRow(symbol: "minus.circle.fill", title: "Uitgaven",
                              caption: fromPots > 0 ? "Waarvan \(Fmt.euro(fromPots)) uit spaarpotten" : nil,
                              value: ledger.expensesTotal, destination: .expenses)
                LedgerLinkRow(symbol: "tray.full.fill", title: "Gespaard", value: ledger.saved, destination: .pots)
                LedgerLinkRow(symbol: "chart.line.uptrend.xyaxis", title: "Belegd", value: ledger.invested,
                              destination: .portfolio)
                LedgerLinkRow(symbol: "square.split.2x2.fill", title: "Nog te verdelen",
                              caption: "Inkomen min uitgaven van je rekening, gespaard en belegd",
                              value: ledger.remaining, tone: ledger.remaining < 0 ? Theme.negative : Color.primary,
                              destination: .distribute)
            }
            if check.isOK {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Klopt met je overzicht")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("De cijfers sluiten niet")
                    }
                    .font(.footnote.weight(.semibold))
                    ForEach(check.issues) { issue in
                        Text(issue.text).font(.footnote)
                    }
                }
                .foregroundStyle(Theme.negative)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .tile(tint: Theme.negative)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Dag voor dag

/// Een regel die in een maand staat en die je vanuit de dagpagina kunt wijzigen.
struct CashflowLineTarget: Identifiable {
    let line: MoneyLine
    let kind: FinanceData.LineKind
    let month: YearMonth
    var id: UUID { line.id }
}

/// Wat een tik op een gebeurtenis doet.
enum CashflowAction {
    case open(Destination)
    case edit(CashflowLineTarget)
    case none
}

/// Alle dagen van een maand: wat er binnenkomt, weggaat en wordt overgeschreven, met het saldo van de bankrekening en de
/// spaarpotten aan het eind van elke dag. Bovenaan sluit de maand: begin + binnen − eruit − overgeschreven = eind, met
/// dezelfde cijfers als het Overzicht, "Nog te verdelen", de spaarpotten en de bankrekening.
struct CashflowPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: CashflowLineTarget?
    @State private var filter: CashflowDayFilter = .all

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let today = store.today
        // Eén dagboek voor de hele pagina: alle cijfers hieronder komen uit deze maand.
        let book = LedgerBook(d, today: today)
        let ledger = book.ledger(month)
        let check = LedgerCheck(ledger)
        let lookup = CashflowLineLookup(plan: d.plan(for: month))
        let lowest = CashflowLowPoint.lowest(in: ledger.days)
        let balanceNow: Double? = month == store.now ? d.bankBalanceNowIfKnown(current: store.now, today: today) : nil
        PageScaffold(title: "Dag voor dag") {
            ScrollViewReader { proxy in
                VStack(spacing: Theme.pageSpacing) {
                    MonthPickerBlock()
                    BankLowPointNotice(month: month)
                    EqualSizeGrid(minimumColumnWidth: 340) {
                        CashflowBankBlock(ledger: ledger, lowest: lowest, balanceNow: balanceNow, hasBalance: d.hasBankBalance)
                        if !d.pots.isEmpty {
                            CashflowPotsBlock(ledger: ledger)
                        }
                        CashflowOverviewBlock(ledger: ledger, check: check)
                    }
                    chartBlock(ledger)
                    daysSection(d, ledger: ledger, lookup: lookup, month: month, proxy: proxy)
                }
                .onAppear { scrollToToday(proxy, ledger: ledger) }
            }
        }
        .sheet(item: $editing) { target in
            MoneyLineSheet(line: target.line, kind: target.kind, month: target.month,
                           defaultExpenseKind: target.line.kind)
        }
    }

    // MARK: Grafiek

    @ViewBuilder
    private func chartBlock(_ ledger: MonthLedger) -> some View {
        let days = ledger.days.filter { $0.bankBalance != nil }
        if days.count > 1 {
            GlassBlock(title: "Saldo per dag", symbol: "chart.xyaxis.line") {
                DayBalanceChart(days: days)
                Text("Gestippeld en lichter is gepland. De rode stippellijn is nul.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Lijst per dag

    private var filterBinding: Binding<CashflowDayFilter> {
        Binding<CashflowDayFilter>(get: { filter },
                                   set: { newValue in withAnimation(Theme.motion) { filter = newValue } })
    }

    @ViewBuilder
    private func daysSection(_ d: FinanceData, ledger: MonthLedger, lookup: CashflowLineLookup,
                             month: YearMonth, proxy: ScrollViewProxy) -> some View {
        let days = filter.days(of: ledger)
        let multipleSalaries = ledger.salaryPayoutCount > 1
        let hasToday = ledger.days.contains(where: { $0.isToday })
        GlassBlock(title: "Dag voor dag", symbol: "calendar", subtitle: "\(days.count) dagen in \(Fmt.month(month))") {
            Picker("Welke dagen", selection: filterBinding) {
                ForEach(CashflowDayFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if hasToday {
                ChipButton(title: "Naar vandaag", symbol: "arrow.down.to.line") {
                    scrollToToday(proxy, ledger: ledger, delay: false)
                }
            }
        }
        if days.isEmpty {
            GlassBlock(title: "Gebeurtenissen", symbol: "list.bullet") {
                EmptyHint(symbol: "calendar", title: "Niets in \(Fmt.month(month))",
                          message: "Er komt niets binnen, gaat niets weg en er wordt niets overgeschreven. Stel je salaris, inkomsten en uitgaven in met een dag naar keuze.")
            }
        } else {
            LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                ForEach(days) { day in
                    dayCard(d, day: day, lookup: lookup, month: month, multipleSalaries: multipleSalaries)
                        .id(CashflowScroll.dayID(day.day))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if days.contains(where: { $0.isPlanned }) {
                Text("Lichtere dagen liggen nog voor je: ze staan in je plan maar zijn nog niet gebeurd.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder
    private func dayCard(_ d: FinanceData, day: DayTotals, lookup: CashflowLineLookup,
                         month: YearMonth, multipleSalaries: Bool) -> some View {
        GlassBlock(title: DayText.weekdayShort(day.date),
                   symbol: day.isToday ? "calendar.badge.clock" : "calendar",
                   subtitle: daySubtitle(day),
                   tint: day.isToday ? Theme.olive.opacity(0.3) : nil) {
            VStack(spacing: 10) {
                DayFlowTiles(day: day)
                if day.events.isEmpty {
                    Text("Geen boekingen op deze dag.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        ForEach(day.events) { event in
                            eventRow(event, lookup: lookup, month: month,
                                     showsDate: multipleSalaries && event.kind == .salary)
                        }
                    }
                }
                Divider()
                DayBalanceRows(day: day, showsPots: !d.pots.isEmpty)
            }
            .opacity(day.isPlanned ? 0.8 : 1)
        }
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private func daySubtitle(_ day: DayTotals) -> String? {
        if day.isToday { return "Vandaag" }
        if day.isPlanned { return "Gepland" }
        return nil
    }

    @ViewBuilder
    private func eventRow(_ event: DayEvent, lookup: CashflowLineLookup, month: YearMonth, showsDate: Bool) -> some View {
        switch action(for: event, lookup: lookup, month: month) {
        case .open(let destination):
            NavigationLink(value: destination) {
                DayEventRow(event: event, showsDate: showsDate, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .edit(let target):
            Button { editing = target } label: {
                DayEventRow(event: event, showsDate: showsDate, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .none:
            DayEventRow(event: event, showsDate: showsDate)
        }
    }

    // MARK: Hulpjes

    /// Scrolt naar de kaart van vandaag, als de maand de huidige is. Bij het openen kort wachten: de lijst heeft zijn
    /// plek pas na de eerste layout.
    private func scrollToToday(_ proxy: ScrollViewProxy, ledger: MonthLedger, delay: Bool = true) {
        guard let todayCard = ledger.days.first(where: { $0.isToday }) else { return }
        let target = CashflowScroll.dayID(todayCard.day)
        Task { @MainActor in
            if delay { try? await Task.sleep(nanoseconds: 300_000_000) }
            withAnimation(Theme.motion) { proxy.scrollTo(target, anchor: .top) }
        }
    }

    /// Een tik op een gebeurtenis: de regel wijzigen, of naar de pot of belegging waar het bij hoort.
    private func action(for event: DayEvent, lookup: CashflowLineLookup, month: YearMonth) -> CashflowAction {
        switch event.kind {
        case .salary:
            return .open(.income)
        case .income:
            if let id = event.lineID, let line = lookup.income[id] {
                return .edit(CashflowLineTarget(line: line, kind: .income, month: month))
            }
            return .none
        case .expense:
            if let id = event.lineID, let line = lookup.expenses[id] {
                return .edit(CashflowLineTarget(line: line, kind: .expense, month: month))
            }
            return .none
        case .toPot, .interest:
            if let id = event.potID { return .open(.pot(id)) }
            return .none
        case .toHolding:
            if let id = event.holdingID { return .open(.holding(id)) }
            return .none
        case .bankEntry:
            return .none
        }
    }
}
