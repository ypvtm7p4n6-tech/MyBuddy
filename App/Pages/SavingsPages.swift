import SwiftUI

// MARK: - Overzicht (alles bij elkaar)

struct OverviewPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let now = store.now
        let mode = router.periodMode
        let focus = router.focusMonth
        let period = d.periodSummary(mode, containing: focus, current: now)
        let months = chartMonths(mode: mode, focus: focus)
        let chart = d.summaries(from: months.first ?? focus, count: months.count, current: now)
        let worthSeries = d.netWorthSeries(from: months.first ?? focus, count: months.count, current: now)
        let endMonth = period.months.last?.month ?? focus
        let endWorth = d.netWorth(at: endMonth, current: now)
        // Eén getal voor "Over", overal op deze pagina: voor een maand precies `remaining(in:)`, het getal van Home.
        let left = mode == .month ? d.remaining(in: focus) : period.remaining
        let grid = [GridItem(.adaptive(minimum: 140), spacing: 10)]

        PageScaffold(title: "Overzicht") {
            VStack(spacing: Theme.pageSpacing) {
                PeriodControl()
                    .padding(Theme.cardInset)
                    .glassCard()

                GlassBlock(title: headerTitle(mode: mode, focus: focus, now: now), symbol: "calendar",
                           subtitle: headerSubtitle(mode: mode, focus: focus, now: now, period: period),
                           tint: Theme.olive.opacity(0.3)) {
                    BigAmount(value: left, color: left < 0 ? Theme.negative : Color.primary)
                    Text("Je inkomen min je uitgaven van de rekening, min wat je verdeelde over spaarpotten en beleggingen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if period.fromPots > 0 {
                        Text("Waarvan \(Fmt.euro(period.fromPots)) uit spaarpotten betaald. Dat telt niet mee in dit bedrag.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassBlock(title: "Cijfers", symbol: "sum", subtitle: Fmt.period(mode, containing: focus)) {
                    LazyVGrid(columns: grid, spacing: 10) {
                        StatTile(title: "Inkomen", value: Fmt.euro(period.income))
                        StatTile(title: "Uitgaven", value: Fmt.euro(period.expenses))
                        StatTile(title: "Gespaard", value: Fmt.euro(period.saved))
                        StatTile(title: "Belegd", value: Fmt.euro(period.invested))
                        StatTile(title: "Over", value: Fmt.euro(left),
                                 color: left < 0 ? Theme.negative : Color.primary)
                        StatTile(title: "Gemiddeld over per maand", value: Fmt.euro(period.average(left)))
                    }
                    if period.hasProjected {
                        Text("Maanden na deze maand zijn verwacht: ze volgen je standaardsalaris, terugkerende regels en standaardinleg.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassBlock(title: "Per maand", symbol: "chart.bar.xaxis") {
                    FlowChart(months: chart, height: 200)
                }

                GlassBlock(title: "Vermogen", symbol: "building.columns.fill",
                           subtitle: "Eind \(Fmt.period(mode, containing: focus))") {
                    BigAmount(value: endWorth.total)
                    TimeLineChart(points: worthSeries.map { TimePoint(id: $0.id, date: $0.month.firstDay, value: $0.total, projected: $0.isProjected) },
                                  height: 150)
                    VStack(spacing: 8) {
                        BreakdownRow(symbol: "building.columns", title: "Bankrekening", value: endWorth.bank, destination: .bank)
                        BreakdownRow(symbol: "tray.full.fill", title: "Spaarpotten", value: endWorth.pots, destination: .pots)
                        BreakdownRow(symbol: "chart.line.uptrend.xyaxis", title: "Beleggingen", value: endWorth.investments, destination: .portfolio)
                    }
                    if !d.hasBankBalance {
                        Text("Vul je banksaldo in voor een compleet vermogen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassBlock(title: "Maand voor maand", symbol: "list.bullet") {
                    VStack(spacing: 0) {
                        ForEach(period.months) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Fmt.month(s.month)).font(.subheadline.weight(.semibold))
                                    if s.isProjected { Text("Verwacht").font(.caption2).foregroundStyle(Theme.warning) }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Fmt.euro(s.remaining))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(s.remaining < 0 ? Theme.negative : Color.primary)
                                        .contentTransition(.numericText())
                                    Text("\(Fmt.euro(s.income)) in · \(Fmt.euro(s.expenses)) uit")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            if s.id != period.months.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    /// Kop van het getal "Over": voor de huidige maand precies zoals op Home.
    private func headerTitle(mode: PeriodMode, focus: YearMonth, now: YearMonth) -> String {
        if mode == .month && focus == now { return "Over deze maand" }
        return "Over \(Fmt.period(mode, containing: focus))"
    }

    private func headerSubtitle(mode: PeriodMode, focus: YearMonth, now: YearMonth, period: PeriodSummary) -> String? {
        if mode == .month && focus == now { return Fmt.month(focus) }
        if period.isFullyProjected { return "Verwacht" }
        if period.hasProjected { return "Deels verwacht" }
        return "Afgelopen"
    }
}

/// Rij die naar een pagina leidt, met een bedrag.
struct BreakdownRow: View {
    let symbol: String
    let title: String
    let value: Double
    let destination: Destination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: symbol, color: Theme.accent, size: 32)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.euro(value))
                    .font(.subheadline.weight(.semibold))
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

// MARK: - Maand kiezen

struct MonthPickerBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        let window = MonthWindow.bounds(startMonth: store.data.startMonth, now: store.now)
        MonthStepper(month: $router.focusMonth, current: store.now, minMonth: window.min, maxMonth: window.max)
            .padding(Theme.cardInset)
            .glassCard()
    }
}

// MARK: - Dag van de maand kiezen

/// Keuze van een dag van de maand (1...31). Met `defaultText` komt er een optie "standaard" bij (de waarde nil).
struct DayPickerRow: View {
    let title: String
    @Binding var day: Int?
    var defaultText: String? = nil

    var body: some View {
        Picker(title, selection: $day) {
            if let defaultText {
                Text(defaultText).tag(Int?.none)
            }
            ForEach(1...31, id: \.self) { n in
                Text(DayText.ordinal(n)).tag(Int?.some(n))
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Salaris en inkomsten

struct IncomePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private func salary<T>(_ keyPath: WritableKeyPath<SalarySettings, T>) -> Binding<T> {
        Binding(get: { store.data.salary[keyPath: keyPath] },
                set: { value in store.mutate { $0.salary[keyPath: keyPath] = value } })
    }

    /// De salarisdag als keuze (1...31). Een onzinnige opgeslagen waarde wordt netjes begrensd getoond.
    private var payDayBinding: Binding<Int?> {
        Binding<Int?>(get: { YearMonth.clampedDay(store.data.salary.payDay) },
                      set: { value in
                          guard let value else { return }
                          store.mutate { $0.salary.payDay = YearMonth.clampedDay(value) }
                      })
    }

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let plan = d.plan(for: month)
        let s = d.salary
        let payDay = min(d.salaryDay(), month.dayCount)

        PageScaffold(title: "Salaris & inkomsten") {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: "Standaard salaris", symbol: "eurosign.circle.fill",
                           subtitle: "Netto, zoals het op je rekening komt") {
                    Picker("Soort", selection: salary(\.mode)) {
                        ForEach(SalaryMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch s.mode {
                    case .fixed:
                        NumberRow(title: "Per maand", value: salary(\.fixedMonthly))
                    case .hourly:
                        NumberRow(title: "Uurloon", value: salary(\.hourlyRate))
                        NumberRow(title: "Uren per week", value: salary(\.hoursPerWeek), unit: .plain("uur"))
                        Text("\(Fmt.euroExact(s.hourlyRate)) × \(Fmt.input(s.hoursPerWeek)) uur × 52 ÷ 12 = \(Fmt.euro(s.monthlyAmount())) per maand")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassBlock(title: "Salarisdag", symbol: "calendar.badge.clock",
                           subtitle: "Wanneer komt je salaris binnen?") {
                    DayPickerRow(title: "Dag van de maand", day: payDayBinding)
                    Text("Op deze dag staat je salaris op je bankrekening. Extra inkomsten zonder eigen dag komen ook dan binnen, en de overschrijvingen naar je spaarpotten en beleggingen gaan standaard op deze dag. Is een maand korter, dan geldt de laatste dag van die maand.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                MonthPickerBlock()

                GlassBlock(title: "Salaris deze maand", symbol: "calendar",
                           subtitle: d.salaryAmount(in: month) > 0
                               ? "Komt binnen op \(DayText.ordinal(payDay))"
                               : "Geen salaris deze maand") {
                    HStack {
                        Text(Fmt.month(month)).foregroundStyle(.secondary)
                        Spacer()
                        BigAmount(value: d.salaryAmount(in: month), font: .system(.title2, design: .rounded, weight: .bold))
                    }
                    switch s.mode {
                    case .fixed:
                        Toggle("Afwijkend bedrag deze maand", isOn: overrideEnabled(month))
                        if plan.salaryOverride != nil {
                            NumberRow(title: "Salaris", value: overrideAmount(month))
                        }
                    case .hourly:
                        Toggle("Andere uren dan gemiddeld", isOn: hoursOverrideEnabled(month))
                        if plan.hoursOverride != nil {
                            NumberRow(title: "Gewerkte uren", value: hoursAmount(month), unit: .plain("uur"))
                        }
                    }
                }

                MoneyLinesBlock(kind: .income, month: month)
            }
        }
    }

    // MARK: Per-maand aanpassingen

    private func overrideEnabled(_ month: YearMonth) -> Binding<Bool> {
        Binding(get: { store.data.plan(for: month).salaryOverride != nil },
                set: { on in
                    withAnimation(Theme.motion) {
                        store.mutate { data in
                            let fallback = data.salary.fixedMonthly
                            data.editPlan(month) { $0.salaryOverride = on ? fallback : nil }
                        }
                    }
                })
    }

    private func overrideAmount(_ month: YearMonth) -> Binding<Double> {
        Binding(get: { store.data.plan(for: month).salaryOverride ?? 0 },
                set: { value in store.mutate { $0.editPlan(month) { $0.salaryOverride = value } } })
    }

    private func hoursOverrideEnabled(_ month: YearMonth) -> Binding<Bool> {
        Binding(get: { store.data.plan(for: month).hoursOverride != nil },
                set: { on in
                    withAnimation(Theme.motion) {
                        store.mutate { data in
                            let fallback = data.salary.defaultMonthlyHours.rounded()
                            data.editPlan(month) { $0.hoursOverride = on ? fallback : nil }
                        }
                    }
                })
    }

    private func hoursAmount(_ month: YearMonth) -> Binding<Double> {
        Binding(get: { store.data.plan(for: month).hoursOverride ?? 0 },
                set: { value in store.mutate { $0.editPlan(month) { $0.hoursOverride = value } } })
    }
}

// MARK: - Regels: inkomsten en uitgaven

/// Lijst met regels (extra inkomsten of uitgaven) voor één maand, met toevoegen, wijzigen en verwijderen.
/// Bij uitgaven kun je kiezen of je alleen vaste of alleen variabele posten toont.
struct MoneyLinesBlock: View {
    let kind: FinanceData.LineKind
    var expenseKind: ExpenseKind? = nil
    let month: YearMonth

    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var editing: MoneyLine?

    private var title: String {
        if kind == .income { return "Overige inkomsten" }
        switch expenseKind {
        case .fixed: return "Vaste uitgaven"
        case .variable: return "Variabele uitgaven"
        case nil: return "Uitgaven deze maand"
        }
    }

    private var symbol: String {
        if kind == .income { return "plus.circle.fill" }
        return expenseKind == .variable ? "cart.fill" : "lock.fill"
    }

    private var emptyText: String {
        if kind == .income { return "Geen andere inkomsten deze maand." }
        switch expenseKind {
        case .fixed: return "Nog geen vaste uitgaven. Denk aan huur, verzekeringen en abonnementen."
        case .variable: return "Nog geen variabele uitgaven. Denk aan boodschappen, uit eten en kleding."
        case nil: return "Nog geen uitgaven ingevuld voor deze maand."
        }
    }

    var body: some View {
        let d = store.data
        let plan = d.plan(for: month)
        let all = kind == .income ? plan.extraIncome : plan.expenses
        let lines = all.filter { expenseKind == nil || kind == .income || $0.kind == expenseKind }
        let fromPots = kind == .expense
            ? CentsMath.value(CentsMath.sum(lines.map { CentsMath.int(d.fromPots(of: $0)) }))
            : 0
        GlassBlock(title: title, symbol: symbol, subtitle: subtitle(total: lines.total, fromPots: fromPots)) {
            if lines.isEmpty {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(lines) { line in
                    VStack(spacing: 0) {
                        MoneyLineRow(line: line, kind: kind, month: month,
                                     onEdit: { editing = line },
                                     onDelete: {
                                         withAnimation(Theme.motion) {
                                             store.mutate { $0.deleteLine(id: line.id, kind: kind, in: month) }
                                         }
                                     })
                        if line.id != lines.last?.id { Divider() }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            ChipButton(title: "Toevoegen", symbol: "plus") { showAdd = true }
        }
        .sheet(isPresented: $showAdd) {
            MoneyLineSheet(line: nil, kind: kind, month: month, defaultExpenseKind: expenseKind ?? .fixed)
        }
        .sheet(item: $editing) { line in
            MoneyLineSheet(line: line, kind: kind, month: month, defaultExpenseKind: line.kind)
        }
    }

    private func subtitle(total: Double, fromPots: Double) -> String {
        if fromPots > 0 { return "Totaal \(Fmt.euro(total)) · \(Fmt.euro(fromPots)) uit spaarpotten" }
        return "Totaal \(Fmt.euro(total))"
    }
}

/// Eén regel in de lijst: naam, dag van de maand, eventueel de spaarpot(ten) waar het uit komt, en het bedrag.
struct MoneyLineRow: View {
    let line: MoneyLine
    let kind: FinanceData.LineKind
    let month: YearMonth
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(AppStore.self) private var store

    /// De spaarpotten die echt meebetalen, zoals de rekenmotor het boekt.
    private func payingPots(_ d: FinanceData) -> [Pot] {
        guard kind == .expense else { return [] }
        var seen = Set<UUID>()
        var result: [Pot] = []
        for payment in d.expenseSplit(of: line).pots where !seen.contains(payment.potID) {
            seen.insert(payment.potID)
            if let pot = d.pot(payment.potID) { result.append(pot) }
        }
        return result
    }

    var body: some View {
        let d = store.data
        let rawDay = kind == .income ? d.incomeDay(of: line) : d.expenseDay(of: line)
        let day = min(rawDay, month.dayCount)
        let payers = payingPots(d)
        let payerNames = DayText.list(payers.map { $0.name })
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(DayText.ordinal(day), systemImage: "calendar")
                    if line.isRecurring {
                        Label("Terugkerend", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let first = payers.first {
                    Label {
                        Text("uit \(payerNames)")
                    } icon: {
                        Image(systemName: first.symbol).foregroundStyle(Theme.color(first.colorIndex))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            Spacer(minLength: 6)
            Text(Fmt.euro(line.amount))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: line.amount)
            Menu {
                Button("Wijzig", action: onEdit)
                Button("Verwijder", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

/// Kijkt vooruit voor een uitgave die elke maand uit een spaarpot komt.
enum PotSpendOutlook {
    /// Het eerste moment in de `months` maanden vanaf `start` waarop `potID` onder nul staat, gemeten aan het eind van
    /// de uitgavedag `day` van elke maand (een dag buiten de maand telt als de laatste dag). nil als het saldo op die
    /// dagen steeds nul of meer is. `data` bevat de uitgave al, anders is de uitkomst die van de pot zonder haar.
    static func firstMomentBelowZero(of potID: UUID, in data: FinanceData, from start: YearMonth,
                                     day: Int, months: Int = 12) -> Date? {
        for offset in 0..<max(0, months) {
            let moment = start.adding(offset).date(day: day)
            if CentsMath.int(data.potBalance(potID, asOf: moment)) < 0 { return moment }
        }
        return nil
    }
}

struct MoneyLineSheet: View {
    let line: MoneyLine?
    let kind: FinanceData.LineKind
    let month: YearMonth
    var defaultExpenseKind: ExpenseKind = .fixed

    @Environment(AppStore.self) private var store
    @State private var name: String
    @State private var amount: Double
    @State private var recurring: Bool
    @State private var expenseKind: ExpenseKind
    @State private var day: Int?
    @State private var fromPotsOn: Bool
    /// Bedrag per spaarpot (alleen potten met een bedrag boven nul tellen mee).
    @State private var shareAmounts: [UUID: Double]

    init(line: MoneyLine?, kind: FinanceData.LineKind, month: YearMonth, defaultExpenseKind: ExpenseKind = .fixed) {
        self.line = line
        self.kind = kind
        self.month = month
        self.defaultExpenseKind = defaultExpenseKind
        var shares: [UUID: Double] = [:]
        for share in line?.potShares ?? [] { shares[share.potID, default: 0] += share.amount }
        _name = State(initialValue: line?.name ?? "")
        _amount = State(initialValue: line?.amount ?? 0)
        _recurring = State(initialValue: line?.isRecurring ?? false)
        _expenseKind = State(initialValue: line?.kind ?? defaultExpenseKind)
        _day = State(initialValue: line?.day)
        _fromPotsOn = State(initialValue: !shares.isEmpty)
        _shareAmounts = State(initialValue: shares)
    }

    private struct ShareNote: Identifiable {
        let id: UUID
        let text: String
    }

    var body: some View {
        let d = store.data
        SheetScaffold(title: titleText, canSave: canSave(d), onSave: save) {
            Section {
                TextField(kind == .income ? "Naam, bijv. Zorgtoeslag" : "Naam, bijv. Huur", text: $name)
                NumberRow(title: "Bedrag", value: $amount)
                if kind == .expense {
                    Picker("Soort", selection: $expenseKind) {
                        ForEach(ExpenseKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                DayPickerRow(title: "Dag van de maand", day: $day, defaultText: defaultDayText(d))
                Toggle("Terugkerend, elke maand", isOn: $recurring)
            } footer: {
                Text(footerText(d))
            }
            if kind == .expense && !d.pots.isEmpty {
                potSection(d)
            }
        }
    }

    private var titleText: String {
        switch (kind, line) {
        case (.income, nil): return "Inkomen toevoegen"
        case (.income, _): return "Inkomen wijzigen"
        case (.expense, nil): return "Uitgave toevoegen"
        case (.expense, _): return "Uitgave wijzigen"
        }
    }

    // MARK: Dag

    private func defaultDayText(_ d: FinanceData) -> String {
        kind == .income ? "Standaard (\(DayText.ordinal(d.salaryDay())))" : "Standaard (\(DayText.ordinal(1)))"
    }

    private func footerText(_ d: FinanceData) -> String {
        if kind == .income {
            return "Voor \(Fmt.month(month)). Standaard komt dit binnen op je salarisdag, \(DayText.ordinal(d.salaryDay())). Kies een andere dag als het bedrag op een ander moment binnenkomt. Terugkerende regels verschijnen automatisch in de volgende maanden."
        }
        return "Voor \(Fmt.month(month)). Kies de dag waarop het van je rekening gaat; standaard is dat de 1e. Vast zijn kosten die elke maand gelijk zijn, zoals huur. Variabel zijn kosten die schommelen, zoals boodschappen. Terugkerende regels verschijnen automatisch in de volgende maanden."
    }

    /// De dag waarop deze regel valt, begrensd op de lengte van de maand.
    private var effectiveDay: Int {
        let fallback = kind == .income ? store.data.salaryDay() : 1
        return min(YearMonth.clampedDay(day ?? fallback), month.dayCount)
    }

    private var lineDate: Date { month.date(day: effectiveDay) }

    // MARK: Betalen uit spaarpot

    private var amountCents: Int { CentsMath.int(amount) }

    private func shareCents(_ id: UUID) -> Int { max(0, CentsMath.int(shareAmounts[id] ?? 0)) }

    private func potsCents(_ d: FinanceData) -> Int { CentsMath.sum(d.pots.map { shareCents($0.id) }) }

    private var potToggle: Binding<Bool> {
        Binding(get: { fromPotsOn }, set: { on in withAnimation(Theme.motion) { fromPotsOn = on } })
    }

    private func shareBinding(_ id: UUID) -> Binding<Double> {
        Binding(get: { shareAmounts[id] ?? 0 }, set: { shareAmounts[id] = $0 })
    }

    /// Wat een pot op de dag van deze uitgave kan missen. Staat de uitgave al in het plan, dan is haar oude deel
    /// al van het saldo af en rekenen we dat terug (alleen als het op of vóór de nieuwe dag viel).
    private func availability(of pot: Pot, in d: FinanceData) -> Double {
        var cents = CentsMath.int(d.potBalance(pot.id, asOf: lineDate))
        if let line, !line.potShares.isEmpty {
            let oldDay = min(d.expenseDay(of: line), month.dayCount)
            if oldDay <= effectiveDay {
                for payment in d.expenseSplit(of: line).pots where payment.potID == pot.id {
                    cents += payment.cents
                }
            }
        }
        return CentsMath.value(cents)
    }

    private func availabilityMap(_ d: FinanceData) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for pot in d.pots { result[pot.id] = availability(of: pot, in: d) }
        return result
    }

    private func shareNotes(_ d: FinanceData, available: [UUID: Double]) -> [ShareNote] {
        let dateText = DayText.short(lineDate)
        var notes: [ShareNote] = []
        for pot in d.pots {
            let cents = shareCents(pot.id)
            let have = available[pot.id] ?? 0
            guard cents > 0, cents > CentsMath.int(have) else { continue }
            let wanted = Fmt.euro(CentsMath.value(cents))
            if CentsMath.int(have) <= 0 {
                notes.append(ShareNote(id: pot.id,
                                       text: "\(pot.name) heeft op \(dateText) geen saldo (\(Fmt.euro(have))). Je haalt er \(wanted) uit."))
            } else {
                notes.append(ShareNote(id: pot.id,
                                       text: "\(pot.name) heeft op \(dateText) maar \(Fmt.euro(have)). Je haalt er \(wanted) uit."))
            }
        }
        return notes
    }

    /// Bij een terugkerende uitgave uit een pot: komt de pot daardoor in een latere maand onder nul? Alleen potten die
    /// door deze uitgave onder nul komen, of eerder dan zonder haar. Rekent op een kopie van de gegevens met de regel
    /// erin en een kopie zonder de regel; er wordt niets opgeslagen.
    private func recurringNotes(_ d: FinanceData) -> [ShareNote] {
        guard kind == .expense, fromPotsOn, recurring else { return [] }
        let draft = draftLine()
        guard !draft.potShares.isEmpty else { return [] }
        var with = d
        with.upsertLine(draft, kind: .expense, in: month)
        let expenseDay = draft.day ?? 1
        var notes: [ShareNote] = []
        for share in draft.potShares {
            guard let pot = d.pot(share.potID),
                  let moment = PotSpendOutlook.firstMomentBelowZero(of: pot.id, in: with, from: month, day: expenseDay)
            else { continue }
            var without = d
            without.deleteLine(id: draft.id, kind: .expense, in: month)
            if let before = PotSpendOutlook.firstMomentBelowZero(of: pot.id, in: without, from: month, day: expenseDay),
               before <= moment {
                continue
            }
            notes.append(ShareNote(id: pot.id,
                                   text: "Met deze terugkerende uitgave staat \(pot.name) vanaf \(Fmt.month(YearMonth(date: moment))) onder nul."))
        }
        return notes
    }

    @ViewBuilder
    private func potSection(_ d: FinanceData) -> some View {
        Section {
            Toggle("Betalen uit spaarpot", isOn: potToggle)
            if fromPotsOn {
                potDetails(d)
            }
        } header: {
            Text("Bron van het geld")
        } footer: {
            Text(fromPotsOn
                 ? "Het bedrag per pot gaat op de gekozen dag van het saldo van die pot af. Wat je niet uit een pot haalt, betaalt je bankrekening. Staat er meer in dan het saldo van de pot, dan zie je een waarschuwing en kun je toch opslaan."
                 : "Kies een of meer spaarpotten die deze uitgave (deels) betalen. Wat overblijft gaat van je bankrekening.")
        }
    }

    /// De rijen onder de schakelaar. Alleen berekend als "Betalen uit spaarpot" aan staat.
    @ViewBuilder
    private func potDetails(_ d: FinanceData) -> some View {
        let available = availabilityMap(d)
        let notes = shareNotes(d, available: available)
        let bankCents = amountCents - potsCents(d)
        let ahead = recurringNotes(d)
        ForEach(d.pots) { pot in
            potRow(pot, available: available[pot.id] ?? 0)
        }
        HStack {
            Text("Van bankrekening").font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(Fmt.euro(CentsMath.value(bankCents)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(bankCents < 0 ? Theme.negative : Color.primary)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: bankCents)
        }
        if bankCents < 0 {
            Label("De delen uit spaarpotten zijn samen \(Fmt.euro(CentsMath.value(-bankCents))) meer dan de uitgave. Verlaag een bedrag om op te slaan.",
                  systemImage: "xmark.octagon.fill")
                .font(.footnote)
                .foregroundStyle(Theme.negative)
        }
        ForEach(notes) { note in
            Label(note.text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        ForEach(ahead) { note in
            Label(note.text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        Button { splitEvenly(d.pots) } label: {
            Label("Gelijk verdelen", systemImage: "divide")
        }
        .buttonStyle(.borderless)
        .disabled(amountCents == 0)
    }

    @ViewBuilder
    private func potRow(_ pot: Pot, available: Double) -> some View {
        let tooMuch = shareCents(pot.id) > CentsMath.int(available)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: pot.symbol, color: Theme.color(pot.colorIndex), size: 30)
                NumberRow(title: pot.name, value: shareBinding(pot.id))
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    balanceCaption(available: available, tooMuch: tooMuch)
                    Spacer(minLength: 8)
                    allFromButton(pot)
                }
                VStack(alignment: .leading, spacing: 4) {
                    balanceCaption(available: available, tooMuch: tooMuch)
                    allFromButton(pot)
                }
            }
        }
    }

    private func balanceCaption(available: Double, tooMuch: Bool) -> some View {
        let prefix = lineDate > store.today ? "Verwacht saldo op" : "Saldo op"
        return Text("\(prefix) \(DayText.short(lineDate)): \(Fmt.euro(available))")
            .font(.caption)
            .foregroundStyle(tooMuch ? Theme.warning : Color.secondary)
    }

    private func allFromButton(_ pot: Pot) -> some View {
        Button { fillAll(from: pot.id) } label: {
            Text("Alles uit deze pot").font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .disabled(amountCents == 0)
    }

    /// De hele uitgave uit deze ene pot.
    private func fillAll(from potID: UUID) {
        guard amountCents > 0 else { return }
        withAnimation(Theme.motion) { shareAmounts = [potID: CentsMath.value(amountCents)] }
    }

    /// Verdeelt het bedrag gelijk over de potten waar al iets staat, of over alle potten als nog niets is ingevuld.
    /// Er blijft geen cent liggen: de resterende centen gaan naar de eerste potten.
    private func splitEvenly(_ pots: [Pot]) {
        guard amountCents > 0, !pots.isEmpty else { return }
        let chosen = pots.filter { shareCents($0.id) > 0 }
        let targets = chosen.isEmpty ? pots : chosen
        let base = amountCents / targets.count
        let extra = amountCents % targets.count
        var result: [UUID: Double] = [:]
        for (index, pot) in targets.enumerated() {
            result[pot.id] = CentsMath.value(base + (index < extra ? 1 : 0))
        }
        withAnimation(Theme.motion) { shareAmounts = result }
    }

    // MARK: Opslaan

    private func canSave(_ d: FinanceData) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, amount > 0 else { return false }
        if kind == .expense && fromPotsOn { return potsCents(d) <= amountCents }
        return true
    }

    /// De delen per pot. Een bestaand deel houdt zijn id, zodat de boekingen niet van id wisselen.
    private func builtShares(_ pots: [Pot]) -> [PotShare] {
        var existing: [UUID: UUID] = [:]
        for share in line?.potShares ?? [] where existing[share.potID] == nil {
            existing[share.potID] = share.id
        }
        var result: [PotShare] = []
        for pot in pots {
            let cents = shareCents(pot.id)
            guard cents > 0 else { continue }
            result.append(PotShare(id: existing[pot.id] ?? UUID(), potID: pot.id, amount: CentsMath.value(cents)))
        }
        return result
    }

    /// De regel zoals hij bij "Bewaar" wordt opgeslagen. Slaat zelf niets op.
    private func draftLine() -> MoneyLine {
        var updated = line ?? MoneyLine(name: "", amount: 0)
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.amount = amount.cents
        updated.isRecurring = recurring
        updated.kind = kind == .expense ? expenseKind : .fixed
        updated.day = day.map { YearMonth.clampedDay($0) }
        updated.potShares = (kind == .expense && fromPotsOn) ? builtShares(store.data.pots) : []
        return updated
    }

    private func save() {
        let result = draftLine()
        let lineKind = kind
        let lineMonth = month
        withAnimation(Theme.motion) {
            store.mutate { $0.upsertLine(result, kind: lineKind, in: lineMonth) }
        }
    }
}

// MARK: - Verdelen

struct DistributePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let figures = d.monthFigures(month)
        // Dezelfde formule als overal: inkomen − uitgaven van de bank − verdeeld − belegd.
        let left = d.remaining(in: month)
        let allocatedCents = figures.saved + figures.invested
        let availableCents = figures.income - (figures.expenses - figures.fromPots)
        let over = left < 0
        let fromPots = CentsMath.value(figures.fromPots)
        let plan = d.plan(for: month)
        // Altijd drie naast elkaar, ook op een smalle iPhone.
        let tiles = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

        PageScaffold(title: "Verdelen") {
            VStack(spacing: Theme.pageSpacing) {
                MonthPickerBlock()

                GlassBlock(title: "Nog te verdelen", symbol: "square.split.2x2.fill",
                           subtitle: month > store.now ? "Verwacht" : nil,
                           tint: Theme.olive.opacity(0.3)) {
                    BigAmount(value: left, color: over ? Theme.negative : Color.primary)
                    ProgressBar(progress: availableCents > 0 ? Double(allocatedCents) / Double(availableCents) : 0,
                                tint: over ? Theme.negative : Theme.accent, height: 10)
                    LazyVGrid(columns: tiles, spacing: 8) {
                        StatTile(title: "Inkomen", value: Fmt.euro(CentsMath.value(figures.income)))
                        StatTile(title: "Uitgaven", value: Fmt.euro(CentsMath.value(figures.expenses)))
                        StatTile(title: "Verdeeld", value: Fmt.euro(CentsMath.value(allocatedCents)))
                    }
                    if fromPots > 0 {
                        Text("Waarvan \(Fmt.euro(fromPots)) uit een spaarpot. Dat telt niet mee in dit bedrag.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if over {
                        Text(availableCents < 0
                             ? "Je uitgaven zijn hoger dan je inkomen deze maand."
                             : "Je hebt \(Fmt.euro(-left)) meer verdeeld dan je beschikbaar hebt.")
                            .font(.footnote)
                            .foregroundStyle(Theme.negative)
                    }
                    ChipGrid {
                        ChipButton(title: "Standaardverdeling", symbol: "arrow.counterclockwise") {
                            withAnimation(Theme.motion) { store.mutate { $0.applyDefaultAllocations(in: month) } }
                        }
                        ChipButton(title: "Rest over potten", symbol: "divide") {
                            withAnimation(Theme.motion) { store.mutate { $0.spreadRemainingOverPots(in: month) } }
                        }
                        ChipButton(title: "Alles op nul", symbol: "xmark.circle") {
                            withAnimation(Theme.motion) { store.mutate { $0.clearAllocations(in: month) } }
                        }
                    }
                }

                GlassBlock(title: "Overschrijfdag", symbol: "calendar.badge.clock",
                           subtitle: "Wanneer gaat het geld naar de potten?") {
                    DayPickerRow(title: "Dag van de maand", day: planDayBinding(month),
                                 defaultText: "Standaard")
                    Text(transferExplanation(plan: plan, month: month, salaryDay: d.salaryDay()))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Op de overschrijfdag gaat het bedrag automatisch van je bankrekening naar de spaarpot of belegging. Dat geldt ook voor maanden die nog komen. Tot die dag telt het bedrag niet mee in het saldo van de pot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                GlassBlock(title: "Spaarpotten", symbol: "tray.full.fill", headerLink: .pots) {
                    if d.pots.isEmpty {
                        Text("Je hebt nog geen spaarpotten. Maak er een op de pagina Spaarpotten.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(d.pots) { pot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                SymbolBadge(symbol: pot.symbol, color: Theme.color(pot.colorIndex), size: 30)
                                NumberRow(title: pot.name, value: allocationBinding(pot.id, month), allowsNegative: true)
                            }
                            Text(transferCaption(id: pot.id, month: month, d: d))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 40)
                        }
                    }
                }

                GlassBlock(title: "Beleggen", symbol: "chart.line.uptrend.xyaxis", headerLink: .portfolio) {
                    if d.holdings.isEmpty {
                        Text("Je hebt nog geen beleggingen. Voeg ze toe op de pagina Beleggingen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(d.holdings) { h in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                SymbolBadge(symbol: h.kind.symbol, color: Theme.accent, size: 30)
                                NumberRow(title: h.name, value: allocationBinding(h.id, month), allowsNegative: true)
                            }
                            Text(transferCaption(id: h.id, month: month, d: d))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: Overschrijfdag

    private func planDayBinding(_ month: YearMonth) -> Binding<Int?> {
        Binding<Int?>(get: { store.data.months[month.key]?.transferDay },
                      set: { value in
                          withAnimation(Theme.motion) {
                              store.mutate { $0.editPlan(month) { $0.transferDay = value } }
                          }
                      })
    }

    private func transferExplanation(plan: MonthPlan, month: YearMonth, salaryDay: Int) -> String {
        if let chosen = plan.transferDay {
            let day = min(YearMonth.clampedDay(chosen), month.dayCount)
            return "Alles wat je deze maand verdeelt gaat op \(DayText.ordinal(day)) over."
        }
        return "Standaard geldt per pot of belegging de eigen overschrijfdag, en anders je salarisdag (\(DayText.ordinal(salaryDay)))."
    }

    /// Waar de dag van een pot of belegging vandaan komt.
    private func transferSource(id: UUID, month: YearMonth, d: FinanceData) -> String {
        if d.months[month.key]?.transferDay != nil { return "dag van deze maand" }
        let ownDay = d.pot(id)?.transferDay ?? d.holdings.first(where: { $0.id == id })?.transferDay
        return ownDay != nil ? "eigen dag" : "salarisdag"
    }

    /// "Wordt overgeschreven op de 25e · salarisdag"
    private func transferCaption(id: UUID, month: YearMonth, d: FinanceData) -> String {
        let day = d.transferDay(for: id, in: month)
        let source = transferSource(id: id, month: month, d: d)
        if CentsMath.int(d.allocation(id, in: month)) == 0 {
            return "Overschrijfdag: \(DayText.ordinal(day)) · \(source)"
        }
        let planned = month.date(day: day) > store.today
        let verb = planned ? "Wordt overgeschreven op" : "Overgeschreven op"
        return "\(verb) \(DayText.ordinal(day)) · \(source)"
    }

    private func allocationBinding(_ id: UUID, _ month: YearMonth) -> Binding<Double> {
        Binding(get: { store.data.allocation(id, in: month) },
                set: { value in store.mutate { $0.setAllocation(id, in: month, amount: value) } })
    }
}

// MARK: - Bankrekening (ook je uitgaven)

enum BankAction: String, Identifiable {
    case balance, deposit, withdraw, toPot, fromPot
    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: return "Saldo invullen"
        case .deposit: return "Geld storten"
        case .withdraw: return "Geld opnemen"
        case .toPot: return "Naar spaarpot"
        case .fromPot: return "Van spaarpot"
        }
    }

    var symbol: String {
        switch self {
        case .balance: return "square.and.pencil"
        case .deposit: return "plus.circle"
        case .withdraw: return "minus.circle"
        case .toPot: return "arrow.right.circle"
        case .fromPot: return "arrow.left.circle"
        }
    }
}

/// De bankrekening in de app: hier komt je salaris binnen, hier gaan je uitgaven vanaf
/// en vanaf hier zet je geld over naar spaarpotten en beleggingen. Het is geen echte bank.
struct BankPage: View {
    @Environment(Router.self) private var router
    @State private var action: BankAction?

    var body: some View {
        let month = router.focusMonth
        PageScaffold(title: "Bankrekening") {
            // Twee groepen: een ViewBuilder kent maximaal 10 kinderen per container.
            VStack(spacing: Theme.pageSpacing) {
                Group {
                    BankBalanceBlock(action: $action)
                    BankLowPointNotice(month: month)
                    MonthPickerBlock()
                    BankDayBlock()
                    BankUpcomingBlock()
                    BankFlowBlock(month: month)
                }
                Group {
                    MoneyLinesBlock(kind: .expense, expenseKind: .fixed, month: month)
                    MoneyLinesBlock(kind: .expense, expenseKind: .variable, month: month)
                    BankTransfersBlock(month: month)
                    BankForecastBlock()
                    BankBufferBlock()
                    BankHistoryBlock()
                }
            }
        }
        .sheet(item: $action) { act in BankActionSheet(action: act) }
    }
}

struct BankBalanceBlock: View {
    @Environment(AppStore.self) private var store
    @Binding var action: BankAction?

    var body: some View {
        let d = store.data
        let now = store.now
        GlassBlock(title: "Saldo nu", symbol: "building.columns.fill", tint: Theme.olive.opacity(0.3)) {
            if d.hasBankBalance {
                BigAmount(value: d.bankBalanceNow(current: now, today: store.today))
                if let last = d.sortedBankSnapshots.last {
                    Text("Laatst ingevuld: \(Fmt.euro(last.balance)) op \(Fmt.date(last.date)). Stortingen, opnames en alles wat je plant komen daar bovenop, op de dag waarop het gebeurt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Het saldo volgt je stortingen, opnames en alles wat je plant, op de dag waarop het gebeurt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                EmptyHint(symbol: "building.columns", title: "Begin met je saldo",
                          message: "Je koppelt geen bank. Vul je saldo in of zet er geld op; de app houdt het bij en rekent ermee verder.")
            }
            ChipGrid {
                ChipButton(title: "Geld storten", symbol: BankAction.deposit.symbol) { action = .deposit }
                ChipButton(title: "Geld opnemen", symbol: BankAction.withdraw.symbol) { action = .withdraw }
                if !d.pots.isEmpty {
                    ChipButton(title: "Naar spaarpot", symbol: BankAction.toPot.symbol) { action = .toPot }
                    ChipButton(title: "Van spaarpot", symbol: BankAction.fromPot.symbol) { action = .fromPot }
                }
                ChipButton(title: "Saldo invullen", symbol: BankAction.balance.symbol) { action = .balance }
            }
        }
    }
}

/// Wat er in een maand binnenkomt, uitgaat en overblijft, met een knop om de standaardposten in te vullen.
struct BankFlowBlock: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store
    @State private var message: String?

    /// Het deel van de uitgaven van één soort dat uit spaarpotten komt (kost de bankrekening niets).
    private func fromPots(_ d: FinanceData, kind: ExpenseKind) -> Double {
        guard month >= d.startMonth else { return 0 }
        return CentsMath.value(CentsMath.sum(d.expenseLines(in: month, kind: kind).map { CentsMath.int(d.fromPots(of: $0)) }))
    }

    var body: some View {
        let d = store.data
        let o = d.expenseOverview(in: month)
        let missing = d.missingStandardExpenses(in: month).count
        // De balk toont wat van de bank gaat, zodat alle stukken samen het inkomen vormen.
        let fixedBank = max(0, o.fixed - fromPots(d, kind: .fixed))
        let variableBank = max(0, o.variable - fromPots(d, kind: .variable))
        GlassBlock(title: "Binnen en eruit", symbol: "arrow.left.arrow.right",
                   subtitle: month > store.now ? "\(Fmt.month(month)) · verwacht" : Fmt.month(month)) {
            SegmentBar(segments: [
                SegmentBar.Segment(id: "fixed", value: fixedBank, color: Theme.flowExpenses),
                SegmentBar.Segment(id: "variable", value: variableBank, color: Theme.flowVariable),
                SegmentBar.Segment(id: "pots", value: o.toPots, color: Theme.flowSaved),
                SegmentBar.Segment(id: "invest", value: o.toInvestments, color: Theme.flowInvested),
                SegmentBar.Segment(id: "free", value: max(0, o.leftAfterTransfers), color: Theme.flowFree)
            ])
            VStack(spacing: 0) {
                FlowRow(title: "Salaris en inkomsten", value: o.income, sign: "+", color: Theme.positive)
                FlowRow(title: "Vaste uitgaven", value: o.fixed, sign: "−", dot: Theme.flowExpenses)
                FlowRow(title: "Variabele uitgaven", value: o.variable, sign: "−", dot: Theme.flowVariable)
                if o.fromPots > 0 {
                    FlowRow(title: "Betaald uit spaarpotten", value: o.fromPots, sign: "+", dot: Theme.flowSaved)
                }
                Divider().padding(.vertical, 4)
                FlowRow(title: "Over na uitgaven", value: o.leftAfterExpenses, bold: true,
                        color: o.leftAfterExpenses < 0 ? Theme.negative : Color.primary)
                FlowRow(title: "Naar spaarpotten", value: o.toPots, sign: "−", dot: Theme.flowSaved)
                FlowRow(title: "Naar beleggingen", value: o.toInvestments, sign: "−", dot: Theme.flowInvested)
                Divider().padding(.vertical, 4)
                FlowRow(title: "Over op de rekening", value: o.leftAfterTransfers, bold: true,
                        color: o.leftAfterTransfers < 0 ? Theme.negative : Theme.positive)
            }
            if o.leftAfterTransfers < 0 {
                Text("Je geeft meer uit en verdeelt meer dan je inkomen. Pas je uitgaven of je verdeling aan.")
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
            }
            ChipGrid {
                ChipButton(title: missing == 0 ? "Standaardposten staan erin" : "Standaard uitgaven invullen",
                           symbol: "wand.and.stars") {
                    let added = store.data.missingStandardExpenses(in: month).count
                    withAnimation(Theme.motion) { store.mutate { $0.fillStandardExpenses(in: month) } }
                    message = added == 0 ? "Alle standaardposten staan al in deze maand."
                                         : "\(added) standaardposten ingevuld met een richtbedrag. Pas ze aan naar jouw situatie."
                }
                ChipLink(title: "Geld verdelen", symbol: "square.split.2x2", destination: .distribute)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if missing > 0 {
                Text("De knop vult gangbare vaste en variabele posten in met een richtbedrag. Je kunt alles daarna aanpassen of verwijderen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FlowRow: View {
    let title: String
    let value: Double
    var sign: String = ""
    var bold = false
    var color: Color = .primary
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(title)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(sign + Fmt.euro(value))
                .font(bold ? .subheadline.weight(.bold) : .subheadline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: value)
        }
        .padding(.vertical, 5)
    }
}

/// Overschrijvingen vanaf de rekening naar spaarpotten en beleggingen, volgens je maandverdeling, met de dag.
struct BankTransfersBlock: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    private struct Row: Identifiable {
        let id: UUID
        let symbol: String
        let color: Color
        let title: String
        let amount: Double
        let day: Int
    }

    var body: some View {
        let d = store.data
        let potRows: [Row] = d.pots.map { pot in
            Row(id: pot.id, symbol: pot.symbol, color: Theme.color(pot.colorIndex), title: pot.name,
                amount: d.allocation(pot.id, in: month), day: d.transferDay(for: pot.id, in: month))
        }.filter { $0.amount != 0 }
        let holdingRows: [Row] = d.holdings.map { h in
            Row(id: h.id, symbol: h.kind.symbol, color: Theme.flowInvested, title: h.name,
                amount: d.allocation(h.id, in: month), day: d.transferDay(for: h.id, in: month))
        }.filter { $0.amount != 0 }
        let rows = (potRows + holdingRows).sorted { lhs, rhs in
            lhs.day != rhs.day ? lhs.day < rhs.day : lhs.title < rhs.title
        }
        let total = CentsMath.value(CentsMath.sum(rows.map { CentsMath.int($0.amount) }))
        GlassBlock(title: "Overschrijvingen", symbol: "arrow.up.right.circle.fill",
                   subtitle: "Van de rekening naar spaarpotten en beleggingen", headerLink: .distribute) {
            if rows.isEmpty {
                Text("Je hebt voor \(Fmt.month(month)) nog niets verdeeld. Tik hier om geld te verdelen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        TransferRow(symbol: row.symbol, color: row.color, title: row.title, amount: row.amount,
                                    dayText: DayText.ordinal(row.day))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(10)
                .tile()
                HStack {
                    Text("Totaal overgeschreven").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Fmt.euro(total))
                        .font(.subheadline.weight(.bold))
                        .contentTransition(.numericText())
                        .animation(Theme.motion, value: total)
                }
                Text("Op de overschrijfdag gaat het bedrag automatisch naar de pot of belegging, ook in maanden die nog komen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TransferRow: View {
    let symbol: String
    let color: Color
    let title: String
    let amount: Double
    var dayText: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(symbol: symbol, color: color, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
                if let dayText {
                    Text(dayText).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            // Een negatieve verdeling betekent geld terug naar de rekening.
            Text((amount < 0 ? "+" : "−") + Fmt.euro(abs(amount)))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: amount)
        }
    }
}

struct BankForecastBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let now = store.now
        let series = store.data.bankSeries(from: now.adding(-3), count: 16, current: now).map { TimePoint($0) }
        if series.count > 1 {
            GlassBlock(title: "Verwacht verloop", symbol: "chart.line.uptrend.xyaxis",
                       subtitle: "Saldo aan het eind van elke maand") {
                TimeLineChart(points: series, height: 160)
                Text("Gebaseerd op je saldo, inkomen, uitgaven en verdeling per maand. De grafiek past zich aan als je iets wijzigt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BankBufferBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        if d.hasBankBalance {
            GlassBlock(title: "Buffer", symbol: "shield.lefthalf.filled") {
                HStack(spacing: 8) {
                    StatTile(title: "Gewenste buffer", value: Fmt.euro(d.bankBuffer(current: now)))
                    StatTile(title: "Daarboven", value: Fmt.euro(d.bankSurplusAboveBuffer(current: now, today: store.today)),
                             color: Theme.positive)
                }
                NumberRow(title: "Buffer in maanden aan uitgaven",
                          value: Binding(get: { store.data.settings.bankBufferMonths },
                                         set: { v in store.mutate { $0.settings.bankBufferMonths = v } }),
                          unit: .plain("mnd"), maxDigits: 1)
                ChipLink(title: "Buffercalculator", symbol: "shield.lefthalf.filled", destination: .buffer)
            }
        }
    }
}

struct BankHistoryBlock: View {
    @Environment(AppStore.self) private var store
    /// Een boeking waarvan het verwijderen eerst om een bevestiging vraagt, omdat er een andere helft bij hoort.
    @State private var pendingDelete: PendingDelete?

    private struct PendingDelete: Identifiable {
        let id: UUID
        let message: String
    }

    private struct Item: Identifiable {
        let id: UUID
        let date: Date
        let title: String
        let detail: String
        let amount: Double
        let isSnapshot: Bool
    }

    var body: some View {
        let d = store.data
        let items: [Item] = (d.bankSnapshots.map { s in
            Item(id: s.id, date: s.date, title: "Saldo ingevuld", detail: s.note, amount: s.balance, isSnapshot: true)
        } + d.bankEntries.map { e in
            Item(id: e.id, date: e.date, title: e.kind.title, detail: e.note, amount: e.amount, isSnapshot: false)
        }).sorted { $0.date > $1.date }

        if !items.isEmpty {
            GlassBlock(title: "Geschiedenis", symbol: "clock.arrow.circlepath") {
                VStack(spacing: 0) {
                    ForEach(items.prefix(40)) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail.isEmpty ? Fmt.date(item.date) : "\(Fmt.date(item.date)) · \(item.detail)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 6)
                            Text(item.isSnapshot ? Fmt.euro(item.amount) : (item.amount >= 0 ? "+" : "") + Fmt.euro(item.amount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(item.isSnapshot || item.amount >= 0 ? Color.primary : Theme.negative)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Menu {
                                Button("Verwijder", role: .destructive) { requestDelete(item) }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .padding(.vertical, 8)
                        if item.id != items.prefix(40).last?.id { Divider() }
                    }
                }
            }
            .confirmationDialog("Boeking verwijderen?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { pending in
                Button("Verwijder", role: .destructive) { delete(pending.id, snapshot: false) }
            } message: { pending in
                Text(pending.message)
            }
        }
    }

    /// Een ingevuld saldo en een losse storting of opname verdwijnen meteen. Hoort een boeking bij een overboeking
    /// naar of van een spaarpot, dan vraagt de app eerst om bevestiging en zegt ze wat er verdwijnt.
    private func requestDelete(_ item: Item) {
        if !item.isSnapshot, let message = confirmationMessage(forBankEntry: item.id) {
            pendingDelete = PendingDelete(id: item.id, message: message)
        } else {
            delete(item.id, snapshot: item.isSnapshot)
        }
    }

    private func delete(_ id: UUID, snapshot: Bool) {
        withAnimation(Theme.motion) {
            store.mutate { data in
                if snapshot { data.deleteBankSnapshot(id) } else { data.deleteBankEntry(id) }
            }
        }
    }

    /// De tekst voor de bevestiging, of nil als de boeking los staat (dan is verwijderen veilig).
    private func confirmationMessage(forBankEntry id: UUID) -> String? {
        let d = store.data
        guard let entry = d.bankEntries.first(where: { $0.id == id }) else { return nil }
        // Een overboeking met `pairID`: de rekenmotor verwijdert beide helften en zegt zelf wat er verdwijnt.
        if let warning = d.pairedEntries(ofBank: id).warning { return warning }
        // Een oude overboeking zonder `pairID`: alleen de kant op de bankrekening verdwijnt.
        if entry.kind == .toPot || entry.kind == .fromPot {
            return "Dit verwijdert alleen de boeking op de bankrekening. De bijbehorende boeking bij de spaarpot blijft staan; die verwijder je bij de spaarpot."
        }
        return nil
    }
}

struct BankActionSheet: View {
    let action: BankAction

    @Environment(AppStore.self) private var store
    @State private var amount = 0.0
    @State private var note = ""
    @State private var potID: UUID?

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        // Saldo's van nu: wat nog moet komen (het salaris van de 25e, de inleg) telt nog niet mee.
        let bank = d.bankBalanceNow(current: now, today: today)
        let potBalance = potID.map { d.potBalanceNow($0, current: now, today: today) } ?? 0
        SheetScaffold(title: action.title, canSave: canSave(potBalance: potBalance), onSave: { save() }) {
            Section {
                if action == .toPot || action == .fromPot {
                    if d.pots.isEmpty {
                        Text("Je hebt nog geen spaarpotten.").foregroundStyle(.secondary)
                    } else {
                        Picker("Spaarpot", selection: $potID) {
                            ForEach(d.pots) { pot in Text(pot.name).tag(pot.id as UUID?) }
                        }
                    }
                }
                NumberRow(title: action == .balance ? "Saldo nu" : "Bedrag", value: $amount, allowsNegative: action == .balance)
                TextField("Notitie (optioneel)", text: $note)
            } header: {
                Text(headerText(bank: bank, potBalance: potBalance))
            } footer: {
                Text(footerText)
            }
        }
        .onAppear {
            if action == .balance { amount = bank }
            if potID == nil { potID = d.pots.first?.id }
        }
    }

    private func headerText(bank: Double, potBalance: Double) -> String {
        switch action {
        case .fromPot: return "Saldo spaarpot \(Fmt.euro(potBalance)) · bankrekening \(Fmt.euro(bank))"
        default: return "Saldo bankrekening \(Fmt.euro(bank))"
        }
    }

    private var footerText: String {
        switch action {
        case .balance: return "Vul het saldo in zoals het nu op je rekening staat. Elke invoer wordt bewaard."
        case .deposit: return "Dit zet geld op de bankrekening in de app. Er gebeurt niets bij een echte bank."
        case .withdraw: return "Dit haalt geld van de bankrekening in de app, bijvoorbeeld voor contant geld of een grote uitgave."
        case .toPot: return "Het bedrag gaat van de bankrekening naar de spaarpot en staat in de geschiedenis van beide."
        case .fromPot: return "Het bedrag gaat van de spaarpot terug naar de bankrekening."
        }
    }

    private func canSave(potBalance: Double) -> Bool {
        switch action {
        case .balance: return true
        case .deposit, .withdraw: return amount > 0
        case .toPot: return amount > 0 && potID != nil
        case .fromPot: return amount > 0 && potID != nil && amount <= potBalance + 0.005
        }
    }

    private func save() {
        let a = amount
        let n = note.trimmingCharacters(in: .whitespaces)
        let pot = potID
        withAnimation(Theme.motion) { apply(amount: a, note: n, potID: pot) }
    }

    private func apply(amount a: Double, note n: String, potID pot: UUID?) {
        switch action {
        case .balance:
            store.mutate { $0.addBankSnapshot(balance: a, note: n) }
        case .deposit:
            store.mutate { $0.addBankEntry(amount: a, note: n) }
        case .withdraw:
            store.mutate { $0.addBankEntry(amount: -a, note: n) }
        case .toPot:
            if let pot { store.mutate { $0.transferBankToPot(potID: pot, amount: a, note: n) } }
        case .fromPot:
            if let pot { store.mutate { $0.transferPotToBank(potID: pot, amount: a, note: n) } }
        }
    }
}
