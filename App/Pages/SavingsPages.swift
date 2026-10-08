import SwiftUI

// MARK: - Overzicht (alles bij elkaar)

struct OverviewPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let now = store.now
        let mode = router.periodMode
        let period = d.periodSummary(mode, containing: router.focusMonth, current: now)
        let months = chartMonths(mode: mode, focus: router.focusMonth)
        let chart = d.summaries(from: months.first ?? router.focusMonth, count: months.count, current: now)
        let worthSeries = d.netWorthSeries(from: months.first ?? router.focusMonth, count: months.count, current: now)
        let endMonth = period.months.last?.month ?? router.focusMonth
        let endWorth = d.netWorth(at: endMonth, current: now)
        let grid = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        PageScaffold(title: "Overzicht") {
            VStack(spacing: Theme.pageSpacing) {
                PeriodControl()
                    .padding(Theme.cardInset)
                    .glassCard()

                GlassBlock(title: "Cijfers", symbol: "sum", subtitle: Fmt.period(mode, containing: router.focusMonth)) {
                    LazyVGrid(columns: grid, spacing: 10) {
                        StatTile(title: "Inkomen", value: Fmt.euro(period.income))
                        StatTile(title: "Uitgaven", value: Fmt.euro(period.expenses))
                        StatTile(title: "Gespaard", value: Fmt.euro(period.saved))
                        StatTile(title: "Belegd", value: Fmt.euro(period.invested))
                        StatTile(title: "Over", value: Fmt.euro(period.remaining),
                                 color: period.remaining < 0 ? Theme.negative : Color.primary)
                        StatTile(title: "Gemiddeld over per maand", value: Fmt.euro(period.average(period.remaining)))
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
                           subtitle: "Eind \(Fmt.period(mode, containing: router.focusMonth))") {
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
                                    Text(Fmt.euroWhole(s.remaining))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(s.remaining < 0 ? Theme.negative : Color.primary)
                                    Text("\(Fmt.euroWhole(s.income)) in · \(Fmt.euroWhole(s.expenses)) uit")
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
                Text(Fmt.euro(value)).font(.subheadline.weight(.semibold))
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
        MonthStepper(month: $router.focusMonth, current: store.now)
            .padding(Theme.cardInset)
            .glassCard()
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

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let plan = d.plan(for: month)
        let s = d.salary

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
                        Text("\(Fmt.euro(s.hourlyRate)) × \(Fmt.input(s.hoursPerWeek)) uur × 52 ÷ 12 = \(Fmt.euro(s.monthlyAmount())) per maand")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                MonthPickerBlock()

                GlassBlock(title: "Salaris deze maand", symbol: "calendar") {
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
                    store.mutate { data in
                        let fallback = data.salary.fixedMonthly
                        data.editPlan(month) { $0.salaryOverride = on ? fallback : nil }
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
                    store.mutate { data in
                        let fallback = data.salary.defaultMonthlyHours.rounded()
                        data.editPlan(month) { $0.hoursOverride = on ? fallback : nil }
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
        let plan = store.data.plan(for: month)
        let all = kind == .income ? plan.extraIncome : plan.expenses
        let lines = all.filter { expenseKind == nil || kind == .income || $0.kind == expenseKind }
        GlassBlock(title: title, symbol: symbol, subtitle: "Totaal \(Fmt.euro(lines.total))") {
            if lines.isEmpty {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(lines) { line in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            if line.isRecurring {
                                Label("Terugkerend", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(Fmt.euro(line.amount))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Menu {
                            Button("Wijzig") { editing = line }
                            Button("Verwijder", role: .destructive) {
                                store.mutate { $0.deleteLine(id: line.id, kind: kind, in: month) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    .padding(.vertical, 8)
                    if line.id != lines.last?.id { Divider() }
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
}

struct MoneyLineSheet: View {
    let line: MoneyLine?
    let kind: FinanceData.LineKind
    let month: YearMonth
    var defaultExpenseKind: ExpenseKind = .fixed

    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var amount = 0.0
    @State private var recurring = false
    @State private var expenseKind: ExpenseKind = .fixed

    var body: some View {
        SheetScaffold(title: titleText,
                      canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0,
                      onSave: save) {
            Section {
                TextField(kind == .income ? "Naam, bijv. Zorgtoeslag" : "Naam, bijv. Huur", text: $name)
                NumberRow(title: "Bedrag", value: $amount)
                if kind == .expense {
                    Picker("Soort", selection: $expenseKind) {
                        ForEach(ExpenseKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Terugkerend, elke maand", isOn: $recurring)
            } footer: {
                Text("Voor \(Fmt.month(month)). Vast zijn kosten die elke maand gelijk zijn, zoals huur. Variabel zijn kosten die schommelen, zoals boodschappen. Terugkerende regels verschijnen automatisch in de volgende maanden.")
            }
        }
        .onAppear {
            expenseKind = defaultExpenseKind
            if let line {
                name = line.name
                amount = line.amount
                recurring = line.isRecurring
                expenseKind = line.kind
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

    private func save() {
        var updated = line ?? MoneyLine(name: "", amount: 0)
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.amount = amount.cents
        updated.isRecurring = recurring
        updated.kind = kind == .expense ? expenseKind : .fixed
        let kind = kind
        let month = month
        store.mutate { $0.upsertLine(updated, kind: kind, in: month) }
    }
}

// MARK: - Verdelen

struct DistributePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let available = d.income(in: month) - d.expensesTotal(in: month)
        let allocated = d.savedTotal(in: month) + d.investedTotal(in: month)
        let left = d.remaining(in: month)
        let over = left < 0

        PageScaffold(title: "Verdelen") {
            VStack(spacing: Theme.pageSpacing) {
                MonthPickerBlock()

                GlassBlock(title: "Nog te verdelen", symbol: "square.split.2x2.fill",
                           subtitle: month > store.now ? "Verwacht" : nil,
                           tint: Theme.olive.opacity(0.3)) {
                    BigAmount(value: left, color: over ? Theme.negative : Color.primary)
                    ProgressBar(progress: available > 0 ? allocated / available : 0,
                                tint: over ? Theme.negative : Theme.accent, height: 10)
                    HStack(spacing: 8) {
                        StatTile(title: "Inkomen", value: Fmt.euroWhole(d.income(in: month)))
                        StatTile(title: "Uitgaven", value: Fmt.euroWhole(d.expensesTotal(in: month)))
                        StatTile(title: "Verdeeld", value: Fmt.euroWhole(allocated))
                    }
                    if over {
                        Text("Je hebt \(Fmt.euro(-left)) meer verdeeld dan je beschikbaar hebt.")
                            .font(.footnote)
                            .foregroundStyle(Theme.negative)
                    }
                    ChipGrid {
                        ChipButton(title: "Standaardverdeling", symbol: "arrow.counterclockwise") {
                            store.mutate { $0.applyDefaultAllocations(in: month) }
                        }
                        ChipButton(title: "Rest over potten", symbol: "divide") {
                            store.mutate { $0.spreadRemainingOverPots(in: month) }
                        }
                        ChipButton(title: "Alles op nul", symbol: "xmark.circle") {
                            store.mutate { $0.clearAllocations(in: month) }
                        }
                    }
                }

                GlassBlock(title: "Spaarpotten", symbol: "tray.full.fill", headerLink: .pots) {
                    if d.pots.isEmpty {
                        Text("Je hebt nog geen spaarpotten. Maak er een op de pagina Spaarpotten.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(d.pots) { pot in
                        HStack(spacing: 10) {
                            SymbolBadge(symbol: pot.symbol, color: Theme.color(pot.colorIndex), size: 30)
                            NumberRow(title: pot.name, value: allocationBinding(pot.id, month))
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
                        HStack(spacing: 10) {
                            SymbolBadge(symbol: h.kind.symbol, color: Theme.accent, size: 30)
                            NumberRow(title: h.name, value: allocationBinding(h.id, month))
                        }
                    }
                }
            }
        }
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
            VStack(spacing: Theme.pageSpacing) {
                BankBalanceBlock(action: $action)
                MonthPickerBlock()
                BankFlowBlock(month: month)
                MoneyLinesBlock(kind: .expense, expenseKind: .fixed, month: month)
                MoneyLinesBlock(kind: .expense, expenseKind: .variable, month: month)
                BankTransfersBlock(month: month)
                BankForecastBlock()
                BankBufferBlock()
                BankHistoryBlock()
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
                BigAmount(value: d.bankBalanceNow(current: now))
                if let last = d.sortedBankSnapshots.last {
                    Text("Laatst ingevuld: \(Fmt.euro(last.balance)) op \(Fmt.date(last.date)). Stortingen, opnames en het overschot van elke maand komen daar bovenop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Het saldo volgt je stortingen, opnames en het overschot van elke maand.")
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

    var body: some View {
        let d = store.data
        let o = d.expenseOverview(in: month)
        let missing = d.missingStandardExpenses(in: month).count
        GlassBlock(title: "Binnen en eruit", symbol: "arrow.left.arrow.right",
                   subtitle: month > store.now ? "\(Fmt.month(month)) · verwacht" : Fmt.month(month)) {
            SegmentBar(segments: [
                SegmentBar.Segment(id: "fixed", value: o.fixed, color: Theme.flowExpenses),
                SegmentBar.Segment(id: "variable", value: o.variable, color: Theme.flowVariable),
                SegmentBar.Segment(id: "pots", value: o.toPots, color: Theme.flowSaved),
                SegmentBar.Segment(id: "invest", value: o.toInvestments, color: Theme.flowInvested),
                SegmentBar.Segment(id: "free", value: max(0, o.leftAfterTransfers), color: Theme.flowFree)
            ])
            VStack(spacing: 0) {
                FlowRow(title: "Salaris en inkomsten", value: o.income, sign: "+", color: Theme.positive)
                FlowRow(title: "Vaste uitgaven", value: o.fixed, sign: "−", dot: Theme.flowExpenses)
                FlowRow(title: "Variabele uitgaven", value: o.variable, sign: "−", dot: Theme.flowVariable)
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
                    store.mutate { $0.fillStandardExpenses(in: month) }
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
        }
        .padding(.vertical, 5)
    }
}

/// Overschrijvingen vanaf de rekening naar spaarpotten en beleggingen, volgens je maandverdeling.
struct BankTransfersBlock: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    private struct Row: Identifiable {
        let id: UUID
        let symbol: String
        let color: Color
        let title: String
        let amount: Double
    }

    var body: some View {
        let d = store.data
        let potRows: [Row] = d.pots.map { pot in
            Row(id: pot.id, symbol: pot.symbol, color: Theme.color(pot.colorIndex), title: pot.name,
                amount: d.allocation(pot.id, in: month))
        }.filter { $0.amount != 0 }
        let holdingRows: [Row] = d.holdings.map { h in
            Row(id: h.id, symbol: h.kind.symbol, color: Theme.flowInvested, title: h.name,
                amount: d.allocation(h.id, in: month))
        }.filter { $0.amount != 0 }
        let rows = potRows + holdingRows
        let total = rows.reduce(0) { $0 + $1.amount }
        GlassBlock(title: "Overschrijvingen", symbol: "arrow.up.right.circle.fill",
                   subtitle: "Van de rekening naar spaarpotten en beleggingen", headerLink: .distribute) {
            if rows.isEmpty {
                Text("Je hebt voor \(Fmt.month(month)) nog niets verdeeld. Tik hier om geld te verdelen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        TransferRow(symbol: row.symbol, color: row.color, title: row.title, amount: row.amount)
                    }
                }
                .padding(10)
                .tile()
                HStack {
                    Text("Totaal overgeschreven").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Fmt.euro(total)).font(.subheadline.weight(.bold))
                }
            }
        }
    }
}

struct TransferRow: View {
    let symbol: String
    let color: Color
    let title: String
    let amount: Double

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(symbol: symbol, color: color, size: 28)
            Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 6)
            Text("−" + Fmt.euro(amount))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct BankForecastBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let now = store.now
        let series = store.data.bankSeries(from: now.adding(-3), count: 16, current: now).map { TimePoint($0) }
        if series.count > 1 {
            GlassBlock(title: "Verwacht verloop", symbol: "chart.line.uptrend.xyaxis") {
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
                    StatTile(title: "Gewenste buffer", value: Fmt.euroWhole(d.bankBuffer(current: now)))
                    StatTile(title: "Daarboven", value: Fmt.euroWhole(d.bankSurplusAboveBuffer(current: now)),
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
                                Button("Verwijder", role: .destructive) {
                                    let id = item.id
                                    let snapshot = item.isSnapshot
                                    store.mutate { data in
                                        if snapshot { data.deleteBankSnapshot(id) } else { data.deleteBankEntry(id) }
                                    }
                                }
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
        }
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
        let bank = d.bankBalanceNow(current: now)
        let potBalance = potID.map { d.potBalance($0, at: now) } ?? 0
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
                NumberRow(title: action == .balance ? "Saldo nu" : "Bedrag", value: $amount)
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
