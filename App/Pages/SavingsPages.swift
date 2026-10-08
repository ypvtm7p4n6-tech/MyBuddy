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

// MARK: - Uitgaven

struct ExpensesPage: View {
    @Environment(Router.self) private var router

    var body: some View {
        PageScaffold(title: "Uitgaven") {
            VStack(spacing: Theme.pageSpacing) {
                MonthPickerBlock()
                MoneyLinesBlock(kind: .expense, month: router.focusMonth)
                Text("Terugkerende uitgaven, zoals huur, worden automatisch naar de volgende maanden gekopieerd.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// Lijst met regels (extra inkomsten of uitgaven) voor één maand, met toevoegen, wijzigen en verwijderen.
struct MoneyLinesBlock: View {
    let kind: FinanceData.LineKind
    let month: YearMonth

    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var editing: MoneyLine?

    var body: some View {
        let plan = store.data.plan(for: month)
        let lines = kind == .income ? plan.extraIncome : plan.expenses
        GlassBlock(title: kind == .income ? "Overige inkomsten" : "Uitgaven deze maand",
                   symbol: kind == .income ? "plus.circle.fill" : "cart.fill",
                   subtitle: "Totaal \(Fmt.euro(lines.total))") {
            if lines.isEmpty {
                Text(kind == .income ? "Geen andere inkomsten deze maand." : "Nog geen uitgaven ingevuld voor deze maand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(lines) { line in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.name).font(.subheadline.weight(.semibold))
                            if line.isRecurring {
                                Label("Terugkerend", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Fmt.euro(line.amount)).font(.subheadline.weight(.semibold))
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
        .sheet(isPresented: $showAdd) { MoneyLineSheet(line: nil, kind: kind, month: month) }
        .sheet(item: $editing) { line in MoneyLineSheet(line: line, kind: kind, month: month) }
    }
}

struct MoneyLineSheet: View {
    let line: MoneyLine?
    let kind: FinanceData.LineKind
    let month: YearMonth

    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var amount = 0.0
    @State private var recurring = false

    var body: some View {
        SheetScaffold(title: titleText,
                      canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0,
                      onSave: save) {
            Section {
                TextField(kind == .income ? "Naam, bijv. Zorgtoeslag" : "Naam, bijv. Huur", text: $name)
                NumberRow(title: "Bedrag", value: $amount)
                Toggle("Terugkerend, elke maand", isOn: $recurring)
            } footer: {
                Text("Voor \(Fmt.month(month)). Terugkerende regels verschijnen automatisch in de volgende maanden.")
            }
        }
        .onAppear {
            if let line {
                name = line.name
                amount = line.amount
                recurring = line.isRecurring
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ChipButton(title: "Standaardverdeling", symbol: "arrow.counterclockwise") {
                                store.mutate { $0.applyDefaultAllocations(in: month) }
                            }
                            ChipButton(title: "Rest verdelen over potten", symbol: "divide") {
                                store.mutate { $0.spreadRemainingOverPots(in: month) }
                            }
                            ChipButton(title: "Alles op nul", symbol: "xmark.circle") {
                                store.mutate { $0.clearAllocations(in: month) }
                            }
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

// MARK: - Bankrekening

struct BankPage: View {
    @Environment(AppStore.self) private var store
    @State private var showEntry = false

    var body: some View {
        let d = store.data
        let now = store.now
        let snapshots = Array(d.sortedBankSnapshots.reversed())
        let series = d.bankSeries(from: now.adding(-3), count: 16, current: now).map { TimePoint($0) }

        PageScaffold(title: "Bankrekening") {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: "Saldo nu", symbol: "building.columns.fill", tint: Theme.olive.opacity(0.3)) {
                    if d.hasBankBalance {
                        BigAmount(value: d.bankBalanceNow(current: now))
                        if let last = snapshots.first {
                            Text("Laatst ingevuld: \(Fmt.euro(last.balance)) op \(Fmt.date(last.date)). Daarna rekent de app het overschot van elke maand erbij.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        EmptyHint(symbol: "building.columns", title: "Vul je saldo in",
                                  message: "Je koppelt geen bank. Jij vult het saldo in, de app bewaart het en rekent ermee verder.")
                    }
                    ChipButton(title: "Saldo invullen", symbol: "square.and.pencil") { showEntry = true }
                }

                if series.count > 1 {
                    GlassBlock(title: "Verwacht verloop", symbol: "chart.line.uptrend.xyaxis") {
                        TimeLineChart(points: series, height: 160)
                        Text("Gebaseerd op je inkomen, uitgaven en verdeling per maand.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
                        Text("Het bedrag boven je buffer gebruikt de app bij Versnellers: dat geld kan voor je doelen werken.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !snapshots.isEmpty {
                    GlassBlock(title: "Geschiedenis", symbol: "clock.arrow.circlepath") {
                        VStack(spacing: 0) {
                            ForEach(snapshots) { snap in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(Fmt.date(snap.date)).font(.subheadline.weight(.semibold))
                                        if !snap.note.isEmpty {
                                            Text(snap.note).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(Fmt.euro(snap.balance)).font(.subheadline.weight(.semibold))
                                    Menu {
                                        Button("Verwijder", role: .destructive) {
                                            store.mutate { $0.deleteBankSnapshot(snap.id) }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                }
                                .padding(.vertical, 8)
                                if snap.id != snapshots.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEntry) { BankBalanceSheet() }
    }
}

struct BankBalanceSheet: View {
    @Environment(AppStore.self) private var store
    @State private var balance = 0.0
    @State private var note = ""

    var body: some View {
        SheetScaffold(title: "Saldo invullen", onSave: {
            let b = balance
            let n = note
            store.mutate { $0.addBankSnapshot(balance: b, note: n) }
        }) {
            Section {
                NumberRow(title: "Saldo nu", value: $balance)
                TextField("Notitie (optioneel)", text: $note)
            } footer: {
                Text("Vul het saldo in zoals het nu op je rekening staat. Je kunt dit zo vaak doen als je wilt; elke invoer wordt bewaard.")
            }
        }
        .onAppear { balance = store.data.bankBalanceNow(current: store.now) }
    }
}
