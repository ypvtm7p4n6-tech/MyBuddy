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
        let sign = amount > 0 ? "+ " : (amount < 0 ? "− " : "")
        return sign + Fmt.euro(abs(amount))
    }
}

/// Eén regel met een gebeurtenis: icoon, titel, soort en bedrag. Geplande gebeurtenissen zijn iets lichter.
struct DayEventRow: View {
    let event: DayEvent
    var showsChevron = false

    var body: some View {
        let style = DayEventStyle(event)
        HStack(spacing: 10) {
            SymbolBadge(symbol: style.symbol, color: style.color, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(event.isPlanned ? "\(style.kindText) · gepland" : style.kindText)
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

// MARK: - Grafiek van het dagsaldo

/// Eén punt van de dagsaldo-grafiek.
struct DayChartItem: Identifiable, Equatable {
    let id: Date
    let value: Double
    let planned: Bool
    var date: Date { id }
}

/// Lijn met vlak eronder voor het saldo aan het eind van elke dag. Geplande dagen staan gestippeld en lichter,
/// de nulstreep is rood gestippeld. Een gekozen dag krijgt een stip.
struct DayBalanceChart: View {
    let points: [BankDayPoint]
    let today: Date
    var selected: Date? = nil
    var height: CGFloat = 190

    /// Punten voor de grafiek. Een dag is gepland als hij na vandaag ligt of vandaag nog iets gepland heeft.
    static func items(from points: [BankDayPoint], today: Date) -> [DayChartItem] {
        let cal = YearMonth.calendar
        let todayStart = cal.startOfDay(for: today)
        return points.map { point in
            let isFuture = cal.startOfDay(for: point.date) > todayStart
            let hasPlanned = point.events.contains(where: { $0.isPlanned })
            return DayChartItem(id: point.date, value: point.balance, planned: isFuture || hasPlanned)
        }
    }

    var body: some View {
        let items = DayBalanceChart.items(from: points, today: today)
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
/// Toont niets als alles in orde is.
struct BankLowPointNotice: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    private struct Note {
        let text: String
        let severe: Bool
    }

    /// Het laagste dagsaldo in het bereik dat bij deze maand hoort.
    private func lowestPoint(_ d: FinanceData, today: Date) -> BankDayPoint? {
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
        let points = d.bankDailySeries(from: from, to: to, asOf: today)
        return points.min(by: { $0.balance < $1.balance })
    }

    var body: some View {
        let d = store.data
        let today = store.today
        if d.hasBankBalance, let low = lowestPoint(d, today: today) {
            let buffer = d.bankBuffer(current: store.now)
            let balanceNow = d.bankBalanceNow(current: store.now, today: today)
            if let note = makeNote(for: low, buffer: buffer, balanceNow: balanceNow) {
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

    private func makeNote(for low: BankDayPoint, buffer: Double, balanceNow: Double) -> Note? {
        let cal = YearMonth.calendar
        let today = store.today
        let past = cal.startOfDay(for: low.date) < cal.startOfDay(for: today)
        let isToday = DayText.isSameDay(low.date, today)
        let day = DayText.weekdayShort(low.date)
        let balance = Fmt.euro(low.balance)
        if low.balance < 0 {
            if past {
                return Note(text: "Op \(day) stond je saldo onder nul (\(balance)).", severe: true)
            }
            let when = isToday ? "vandaag" : "op \(day)"
            return Note(text: "Let op: \(when) staat je saldo onder nul (\(balance)). Kijk of je een uitgave of overschrijving naar een andere dag kunt zetten.",
                        severe: true)
        }
        // De buffermelding is bedoeld voor een dip die je plan veroorzaakt. Zit je nu al onder je buffer,
        // dan zie je dat bij het blok Buffer en blijft deze balk weg, zodat de melding "onder nul" opvalt.
        if buffer > 0 && low.balance < buffer && balanceNow >= buffer && !past {
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

/// Blok "Per dag" op de bankpagina: kies een datum en zie het saldo en de gebeurtenissen van die dag,
/// met eronder een grafiek van het dagsaldo.
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
        let defaultRange: DayChartRange = focus == store.now ? .next30 : .month
        let range = rangeChoice ?? defaultRange
        GlassBlock(title: "Per dag", symbol: "calendar",
                   subtitle: "Saldo en gebeurtenissen op elke dag",
                   tint: Theme.olive.opacity(0.3)) {
            if d.hasBankBalance {
                dayPicker(today: today)
                dayDetails(d, today: today)
                chartSection(d, range: range, defaultRange: defaultRange, focus: focus, today: today)
            } else {
                Text("Vul je saldo in of zet er geld op. Dan zie je per dag hoeveel je hebt, ook voor dagen die nog komen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
    private func dayDetails(_ d: FinanceData, today: Date) -> some View {
        let balance = d.bankBalance(on: date)
        let events = d.eventsOnDay(date, asOf: today)
        let isToday = DayText.isSameDay(date, today)
        VStack(alignment: .leading, spacing: 2) {
            Text("Saldo aan het eind van \(isToday ? "vandaag" : DayText.weekdayShort(date))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let balance {
                BigAmount(value: balance, font: .system(.title, design: .rounded, weight: .bold),
                          color: balance < 0 ? Theme.negative : Color.primary)
            } else {
                Text("Op deze dag is je saldo nog niet bekend.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isToday && events.contains(where: { $0.isPlanned }) {
                Text("Inclusief wat vandaag nog gepland staat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if events.isEmpty {
            Text("Op deze dag komt er niets binnen en gaat er niets weg.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(events) { event in
                    DayEventRow(event: event)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(10)
            .tile()
        }
    }

    @ViewBuilder
    private func chartSection(_ d: FinanceData, range: DayChartRange, defaultRange: DayChartRange,
                              focus: YearMonth, today: Date) -> some View {
        let span = chartWindow(range, focus: focus, today: today)
        let points = d.bankDailySeries(from: span.from, to: span.to, asOf: today)
        let items = DayBalanceChart.items(from: points, today: today)
        let lowest = items.min(by: { $0.value < $1.value })
        Divider()
        Picker("Periode van de grafiek", selection: Binding(get: { rangeChoice ?? defaultRange },
                                                           set: { rangeChoice = $0 })) {
            Text("Komende 30 dagen").tag(DayChartRange.next30)
            Text(Fmt.month(focus)).tag(DayChartRange.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if items.count > 1 {
            DayBalanceChart(points: points, today: today, selected: date)
            if let low = lowest, let end = items.last {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    StatTile(title: "Laagste saldo", value: Fmt.euro(low.value),
                             color: low.value < 0 ? Theme.negative : Color.primary,
                             caption: DayText.short(low.date))
                    StatTile(title: "Saldo op het eind", value: Fmt.euro(end.value),
                             color: end.value < 0 ? Theme.negative : Color.primary,
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

/// Wat er de komende 14 dagen gebeurt, dag voor dag, met het saldo aan het eind van elke dag.
struct BankUpcomingBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let today = store.today
        let cal = YearMonth.calendar
        let start = cal.startOfDay(for: today)
        let end = cal.date(byAdding: .day, value: 13, to: start) ?? start
        let points = d.hasBankBalance ? d.bankDailySeries(from: start, to: end, asOf: today) : []
        let busy = points.filter { !$0.events.isEmpty }
        GlassBlock(title: "Komende 14 dagen", symbol: "calendar.badge.clock",
                   subtitle: "\(DayText.short(start)) t/m \(DayText.short(end))") {
            if !d.hasBankBalance {
                Text("Vul je saldo in om te zien wat er de komende dagen op je rekening gebeurt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if busy.isEmpty {
                Text("De komende 14 dagen komt er niets binnen en gaat er niets weg.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(busy) { point in
                        UpcomingDayRow(point: point, isToday: DayText.isSameDay(point.date, today))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        if point.id != busy.last?.id { Divider() }
                    }
                }
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
    let point: BankDayPoint
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DayText.weekdayShort(point.date)).font(.subheadline.weight(.semibold))
                    if isToday { Text("Vandaag").font(.caption).foregroundStyle(Theme.accent) }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Saldo").font(.caption2).foregroundStyle(.secondary)
                    Text(Fmt.euro(point.balance))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(point.balance < 0 ? Theme.negative : Color.primary)
                        .contentTransition(.numericText())
                        .animation(Theme.motion, value: point.balance)
                }
            }
            ForEach(point.events) { event in
                DayEventRow(event: event)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Dag voor dag

/// Een dag in de lijst met gebeurtenissen.
struct CashflowDay: Identifiable {
    let id: Int
    let date: Date
    let events: [DayEvent]
    let balance: Double?
}

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

/// Alle dagen van een maand: wat er binnenkomt, weggaat en wordt overgeschreven, met het saldo aan het eind van elke dag.
struct CashflowPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: CashflowLineTarget?

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let today = store.today
        let last = month.date(day: month.dayCount)
        let events = d.dayEvents(in: month, asOf: today)
        let points = d.hasBankBalance ? d.bankDailySeries(from: month.firstDay, to: last, asOf: today) : []
        let days = buildDays(events: events, points: points, month: month)
        let lowest = d.hasBankBalance ? d.lowestBankPoint(in: month) : nil
        let endBalance = d.hasBankBalance ? d.bankBalance(at: month) : nil
        let showsNow = month == store.now && d.hasBankBalance
        PageScaffold(title: "Dag voor dag") {
            VStack(spacing: Theme.pageSpacing) {
                MonthPickerBlock()
                BankLowPointNotice(month: month)
                summaryBlock(d, month: month, lowest: lowest, endBalance: endBalance, showsNow: showsNow)
                chartBlock(d, points: points, today: today)
                daysSection(d, days: days, month: month, today: today)
            }
        }
        .sheet(item: $editing) { target in
            MoneyLineSheet(line: target.line, kind: target.kind, month: target.month,
                           defaultExpenseKind: target.line.kind)
        }
    }

    // MARK: Samenvatting en grafiek

    @ViewBuilder
    private func summaryBlock(_ d: FinanceData, month: YearMonth, lowest: BankDayPoint?,
                              endBalance: Double?, showsNow: Bool) -> some View {
        GlassBlock(title: "Samenvatting", symbol: "sum", subtitle: Fmt.month(month),
                   tint: Theme.olive.opacity(0.3)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                if showsNow {
                    StatTile(title: "Saldo nu", value: Fmt.euro(d.bankBalanceNow(current: store.now, today: store.today)))
                }
                StatTile(title: "Laagste saldo",
                         value: lowest.map { Fmt.euro($0.balance) } ?? "–",
                         color: (lowest?.balance ?? 0) < 0 ? Theme.negative : Color.primary,
                         caption: lowest.map { DayText.weekdayShort($0.date) })
                StatTile(title: "Eindsaldo",
                         value: endBalance.map { Fmt.euro($0) } ?? "–",
                         color: (endBalance ?? 0) < 0 ? Theme.negative : Color.primary,
                         caption: "Eind \(Fmt.month(month))")
            }
            if !d.hasBankBalance {
                Text("Vul je saldo in op de bankrekening. Dan rekent de app per dag uit hoeveel je hebt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func chartBlock(_ d: FinanceData, points: [BankDayPoint], today: Date) -> some View {
        if points.count > 1 {
            GlassBlock(title: "Saldo per dag", symbol: "chart.xyaxis.line") {
                DayBalanceChart(points: points, today: today)
                Text("Gestippeld en lichter is gepland. De rode stippellijn is nul.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Lijst per dag

    @ViewBuilder
    private func daysSection(_ d: FinanceData, days: [CashflowDay], month: YearMonth, today: Date) -> some View {
        if days.isEmpty {
            GlassBlock(title: "Gebeurtenissen", symbol: "list.bullet") {
                EmptyHint(symbol: "calendar", title: "Niets in \(Fmt.month(month))",
                          message: "Er komt niets binnen, gaat niets weg en er wordt niets overgeschreven. Stel je salaris, inkomsten en uitgaven in met een dag naar keuze.")
            }
        } else {
            LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                ForEach(days) { day in
                    dayCard(d, day: day, month: month, today: today)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if days.contains(where: { day in day.events.contains(where: { $0.isPlanned }) }) {
                Text("Lichtere regels zijn gepland: ze staan in je plan maar zijn nog niet gebeurd.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder
    private func dayCard(_ d: FinanceData, day: CashflowDay, month: YearMonth, today: Date) -> some View {
        let isToday = DayText.isSameDay(day.date, today)
        GlassBlock(title: DayText.weekdayShort(day.date), symbol: "calendar",
                   subtitle: isToday ? "Vandaag" : nil,
                   tint: isToday ? Theme.olive.opacity(0.3) : nil) {
            VStack(spacing: 10) {
                ForEach(day.events) { event in
                    eventRow(d, event: event, month: month)
                }
            }
            if let balance = day.balance {
                Divider()
                HStack {
                    Text("Saldo aan het eind van de dag")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(Fmt.euro(balance))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(balance < 0 ? Theme.negative : Color.primary)
                        .contentTransition(.numericText())
                        .animation(Theme.motion, value: balance)
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ d: FinanceData, event: DayEvent, month: YearMonth) -> some View {
        switch action(for: event, in: d, month: month) {
        case .open(let destination):
            NavigationLink(value: destination) {
                DayEventRow(event: event, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .edit(let target):
            Button { editing = target } label: {
                DayEventRow(event: event, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .none:
            DayEventRow(event: event)
        }
    }

    // MARK: Hulpjes

    /// De dagen van de maand met gebeurtenissen, elk met het saldo aan het eind van die dag (als dat bekend is).
    private func buildDays(events: [DayEvent], points: [BankDayPoint], month: YearMonth) -> [CashflowDay] {
        let cal = YearMonth.calendar
        var balanceByDay: [Int: Double] = [:]
        for point in points {
            balanceByDay[cal.component(.day, from: point.date)] = point.balance
        }
        var eventsByDay: [Int: [DayEvent]] = [:]
        for event in events {
            eventsByDay[event.day, default: []].append(event)
        }
        return eventsByDay.keys.sorted().map { number in
            CashflowDay(id: number, date: month.date(day: number),
                        events: eventsByDay[number] ?? [], balance: balanceByDay[number])
        }
    }

    /// Een tik op een gebeurtenis: de regel wijzigen, of naar de pot of belegging waar het bij hoort.
    private func action(for event: DayEvent, in d: FinanceData, month: YearMonth) -> CashflowAction {
        switch event.kind {
        case .salary:
            return .open(.income)
        case .income:
            if let id = event.lineID, let line = d.plan(for: month).extraIncome.first(where: { $0.id == id }) {
                return .edit(CashflowLineTarget(line: line, kind: .income, month: month))
            }
            return .none
        case .expense:
            if let id = event.lineID, let line = d.plan(for: month).expenses.first(where: { $0.id == id }) {
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
