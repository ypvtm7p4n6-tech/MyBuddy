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
                        Text("Maanden na deze maand zijn verwacht: ze volgen je salarisschema, terugkerende regels en standaardinleg.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Bij één maand: sluiten deze cijfers met de dagen van die maand? Met een link naar het dagoverzicht.
                    if mode == .month {
                        DayCheckBlock(month: focus)
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
                    // Zonder bekend saldo aan het eind van de periode telt de bank als € 0 mee in het vermogen.
                    if d.bankBalance(at: endMonth) == nil {
                        Text("Voor deze periode is je banksaldo nog niet bekend. Vul je saldo in voor een compleet vermogen.")
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

/// Meldt of de cijfers van een maand (inkomen, uitgaven, gespaard, belegd, over) sluiten met de dagen van die maand, en
/// leidt naar het dagoverzicht. Het oordeel komt van de rekenmotor (`MonthLedger.allReconciles`): daar worden dezelfde
/// bedragen op twee onafhankelijke manieren uitgerekend en met elkaar vergeleken.
private struct DayCheckBlock: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    var body: some View {
        let ledger = store.data.monthLedger(month, asOf: store.today)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: ledger.allReconciles ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(ledger.allReconciles ? "Klopt met je dagoverzicht" : "Dit klopt niet met je dagoverzicht")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ledger.allReconciles ? Theme.positive : Theme.negative)
            ChipLink(title: "Per dag bekijken", symbol: "calendar", destination: .cashflow)
        }
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

// De logica hiervan (zonder SwiftUI) staat in App/UI/SavingsDisplay.swift, zodat de tests in CoreTests haar meedraaien.

struct IncomePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private func salary<T>(_ keyPath: WritableKeyPath<SalarySettings, T>) -> Binding<T> {
        Binding(get: { store.data.salary[keyPath: keyPath] },
                set: { value in
                    let today = store.today
                    store.mutate { data in SalaryScheduleEdit.edit(&data, today: today) { $0[keyPath: keyPath] = value } }
                })
    }

    /// De salarisdag als keuze (1...31). Een onzinnige opgeslagen waarde wordt netjes begrensd getoond.
    private var payDayBinding: Binding<Int?> {
        Binding<Int?>(get: { YearMonth.clampedDay(store.data.salary.payDay) },
                      set: { value in
                          guard let value else { return }
                          let today = store.today
                          store.mutate { data in
                              SalaryScheduleEdit.edit(&data, today: today) { $0.payDay = YearMonth.clampedDay(value) }
                          }
                      })
    }

    /// Om de hoeveel weken of dagen. De rekenmotor klemt het op 1...52 (weken) of 1...366 (dagen).
    private var intervalBinding: Binding<Int> {
        Binding(get: { store.data.salary.cycleInterval },
                set: { value in
                    let current = store.data.salary.schedule
                    let today = store.today
                    store.mutate { data in
                        SalaryScheduleEdit.edit(&data, today: today) { $0.setSchedule(current, interval: value) }
                    }
                })
    }

    /// Een datum waarop je salaris binnenkomt (of kwam): de uitbetalingen vallen om de zoveel weken of dagen voor en na deze
    /// dag. Is er nog geen ingesteld, dan toont de kiezer de datum waar de rekenmotor van uitgaat.
    private var anchorBinding: Binding<Date> {
        Binding(get: { store.data.salary.anchorDate ?? store.data.salaryAnchor().date() },
                set: { value in
                    let today = store.today
                    store.mutate { data in SalaryScheduleEdit.edit(&data, today: today) { $0.anchorDate = value } }
                })
    }

    /// Schakelt het schema om (zie `SalaryScheduleEdit.change`).
    private func changeSchedule(to schedule: SalarySchedule) {
        let today = store.today
        withAnimation(Theme.motion) {
            store.mutate { SalaryScheduleEdit.change(&$0, to: schedule, today: today) }
        }
    }

    /// Eén uitbetaling van de gekozen maand, voor de lijst.
    private struct PayoutLine: Identifiable {
        let id: String
        let date: Date
        let amount: Double
        let isPlanned: Bool
    }

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let plan = d.plan(for: month)
        let today = store.today
        // De uitbetalingen en het maandtotaal komen uit dezelfde bron als "Inkomen" op alle andere schermen.
        let payouts: [PayoutLine] = d.salaryPayouts(in: month, plan: plan)
            .filter { $0.cents != 0 }
            .map { payout in
                let date = month.date(day: payout.day)
                return PayoutLine(id: payout.id, date: date, amount: CentsMath.value(payout.cents),
                                  isPlanned: DayMath.isPlanned(date, asOf: today))
            }
        let total = d.salaryAmount(in: month, plan: plan)

        PageScaffold(title: "Salaris & inkomsten") {
            VStack(spacing: Theme.pageSpacing) {
                salaryBlock(d.salary)
                scheduleBlock(d, today: today)
                MonthPickerBlock()
                monthBlock(d, month: month, plan: plan, payouts: payouts, total: total)
                MoneyLinesBlock(kind: .income, month: month)
            }
        }
    }

    // MARK: Standaard salaris

    private func hourlyFormula(_ s: SalarySettings) -> String {
        let hours = Fmt.input(s.hoursPerWeek)
        if s.isMonthly {
            return "\(Fmt.euroExact(s.hourlyRate)) × \(hours) uur × 52 ÷ 12 = \(Fmt.euro(s.payoutAmount())) per maand"
        }
        let weeks = SalaryScheduleText.weeksText(schedule: s.schedule, interval: s.cycleInterval)
        return "\(Fmt.euroExact(s.hourlyRate)) × \(hours) uur × \(weeks) = \(Fmt.euro(s.payoutAmount())) per uitbetaling"
    }

    @ViewBuilder
    private func salaryBlock(_ s: SalarySettings) -> some View {
        GlassBlock(title: "Standaard salaris", symbol: "eurosign.circle.fill",
                   subtitle: "Netto, zoals het op je rekening komt") {
            Picker("Soort", selection: salary(\.mode)) {
                ForEach(SalaryMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch s.mode {
            case .fixed:
                NumberRow(title: s.isMonthly ? "Per maand" : "Per uitbetaling", value: salary(\.fixedMonthly))
                if !s.isMonthly {
                    Text("Vul in wat er bij elke uitbetaling op je rekening komt, niet wat je per maand krijgt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .hourly:
                NumberRow(title: "Uurloon", value: salary(\.hourlyRate))
                NumberRow(title: "Uren per week", value: salary(\.hoursPerWeek), unit: .plain("uur"))
                Text(hourlyFormula(s))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !s.isMonthly {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    if s.mode == .hourly {
                        StatTile(title: "Per uitbetaling", value: Fmt.euro(s.payoutAmount()))
                    }
                    StatTile(title: "Gemiddeld per maand", value: Fmt.euro(s.averageMonthlyAmount()), caption: "voor schattingen")
                }
                Text("Voor schattingen (toekomstschatting, aankoopcheck, buffer en doelen) rekent de app met het gemiddelde per maand. Een echte maand telt precies de uitbetalingen die erin vallen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Schema

    @ViewBuilder
    private func scheduleBlock(_ d: FinanceData, today: Date) -> some View {
        let s = d.salary
        GlassBlock(title: "Wanneer krijg je salaris?", symbol: "calendar.badge.clock",
                   subtitle: SalaryScheduleText.capitalized(d.salaryScheduleSummary(asOf: today))) {
            VStack(spacing: 8) {
                ChoiceRow(title: "Maandelijks", detail: "Op een vaste dag van de maand, bijvoorbeeld de 25e.",
                          isSelected: s.schedule == .monthly) { changeSchedule(to: .monthly) }
                ChoiceRow(title: "Om de zoveel weken", detail: "Bijvoorbeeld elke week, om de 2 weken of om de 4 weken.",
                          isSelected: s.schedule == .weeks) { changeSchedule(to: .weeks) }
                ChoiceRow(title: "Om de zoveel dagen", detail: "Bijvoorbeeld elke 14 dagen of elke 30 dagen.",
                          isSelected: s.schedule == .days) { changeSchedule(to: .days) }
            }

            switch s.schedule {
            case .monthly:
                DayPickerRow(title: "Dag van de maand", day: payDayBinding)
                Text("Op deze dag staat je salaris op je bankrekening. Extra inkomsten zonder eigen dag komen ook dan binnen, en de overschrijvingen naar je spaarpotten en beleggingen gaan standaard op deze dag. Is een maand korter, dan geldt de laatste dag van die maand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .weeks:
                IntStepperRow(title: "Elke", value: intervalBinding, range: 1...52,
                              unit: SalaryScheduleText.unit(schedule: s.schedule, interval: s.cycleInterval))
                anchorRow(s)
            case .days:
                IntStepperRow(title: "Elke", value: intervalBinding, range: 1...366,
                              unit: SalaryScheduleText.unit(schedule: s.schedule, interval: s.cycleInterval))
                anchorRow(s)
            }

            let upcoming = upcomingPayDates(d, today: today)
            if !upcoming.isEmpty {
                Text("Volgende uitbetalingen: " + upcoming.map { payDateText($0, today: today) }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                Text("Een wijziging aan je salaris of schema geldt vanaf deze maand. Eerdere maanden blijven zoals ze waren. Valt er in deze maand al een uitbetaling van het nieuwe schema voor vandaag, dan telt die wel mee.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// De eerstvolgende uitbetalingen vanaf vandaag, elk de volgende van de vorige (`nextPayDate(after:)`): zo zie je meteen
    /// of het schema klopt met wat je verwacht.
    private func upcomingPayDates(_ d: FinanceData, today: Date, count: Int = 4) -> [Date] {
        var result: [Date] = []
        var cursor = today
        for _ in 0..<count {
            guard let next = d.nextPayDate(after: cursor) else { break }
            result.append(next)
            cursor = next
        }
        return result
    }

    /// "23 okt", met het jaar erbij als het niet dit jaar is.
    private func payDateText(_ date: Date, today: Date) -> String {
        let calendar = YearMonth.calendar
        let year = calendar.component(.year, from: date)
        if year == calendar.component(.year, from: today) { return DayText.short(date) }
        return DayText.short(date) + " " + String(year)
    }

    /// De datum van een uitbetaling en uitleg bij een schema om de zoveel weken of dagen.
    @ViewBuilder
    private func anchorRow(_ s: SalarySettings) -> some View {
        DatePicker("Datum van een uitbetaling", selection: anchorBinding, displayedComponents: .date)
            .datePickerStyle(.compact)
            .environment(\.locale, Fmt.locale)
        Text("Kies een dag waarop je salaris binnenkwam of binnenkomt, ook al is dat lang geleden. Vanaf die dag telt de app \(s.cycleDescription) door, vooruit en terug. Daardoor vallen er in een maand soms 0, 1, 2 of meer uitbetalingen, gemiddeld \(Fmt.input(s.averagePayoutsPerYear, maxDigits: 1)) per jaar. Het maandtotaal is de som van de uitbetalingen. Extra inkomsten zonder eigen dag en de overschrijvingen naar je spaarpotten gaan standaard op de eerste uitbetaling van de maand.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        if let cycle = s.cycleDays, cycle > 28 {
            DayPickerRow(title: "Salarisdag zonder uitbetaling", day: payDayBinding)
            Text("Valt er in een maand geen uitbetaling, dan geldt deze dag als salarisdag voor extra inkomsten en overschrijvingen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Deze maand

    @ViewBuilder
    private func monthBlock(_ d: FinanceData, month: YearMonth, plan: MonthPlan, payouts: [PayoutLine],
                            total: Double) -> some View {
        let s = d.salary
        // Altijd drie naast elkaar, ook op een smalle iPhone.
        let tiles = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let subtitle: String = {
            if month < d.startMonth { return "Voor je startmaand telt er geen salaris mee" }
            switch payouts.count {
            case 0: return "Geen salaris deze maand"
            case 1: return "Komt binnen op \(d.salaryPayoutDaysText(in: month))"
            default: return "\(SalaryScheduleText.payoutCount(payouts.count)): \(d.salaryPayoutDaysText(in: month))"
            }
        }()
        GlassBlock(title: "Salaris deze maand", symbol: "calendar", subtitle: subtitle) {
            HStack {
                Text(Fmt.month(month)).foregroundStyle(.secondary)
                Spacer()
                BigAmount(value: total, font: .system(.title2, design: .rounded, weight: .bold))
            }
            if !payouts.isEmpty {
                VStack(spacing: 10) {
                    ForEach(payouts) { payout in
                        HStack(spacing: 10) {
                            SymbolBadge(symbol: "briefcase.fill", color: Theme.positive, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(DayText.weekdayShort(payout.date)).font(.subheadline.weight(.semibold))
                                Text(payout.isPlanned ? "Salaris · gepland" : "Salaris")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("+ " + Fmt.euro(payout.amount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.positive)
                                .contentTransition(.numericText())
                                .animation(Theme.motion, value: payout.amount)
                        }
                        .opacity(payout.isPlanned ? 0.8 : 1)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(10)
                .tile()
            }
            if !s.isMonthly {
                if payouts.isEmpty && month >= d.startMonth {
                    Text("In \(Fmt.month(month)) valt er geen uitbetaling: je salaris komt \(s.cycleDescription) binnen en deze maand zit daar tussenin.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if payouts.count >= 2 {
                    Text("Deze maand krijg je \(payouts.count) keer salaris. Het maandtotaal is de som van de uitbetalingen en telt overal zo mee: in je overzicht, bij \"nog te verdelen\" en bij een inleg als percentage van je inkomen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if payouts.count == 1 {
                    Text("Deze maand krijg je 1 keer salaris. In een maand met een extra uitbetaling is je inkomen hoger.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // Het inkomen van de maand is precies het getal van het overzicht en van "Nog te verdelen": salaris plus overig.
            LazyVGrid(columns: tiles, spacing: 8) {
                StatTile(title: "Salaris", value: Fmt.euro(total))
                StatTile(title: "Overig", value: Fmt.euro(d.extraIncomeTotal(in: month)))
                StatTile(title: "Inkomen", value: Fmt.euro(d.income(in: month)), caption: "in je overzicht")
            }

            switch s.mode {
            case .fixed:
                Toggle("Afwijkend bedrag deze maand", isOn: overrideEnabled(month))
                if plan.salaryOverride != nil {
                    NumberRow(title: s.isMonthly ? "Salaris" : "Totaal van de maand", value: overrideAmount(month))
                    if !s.isMonthly {
                        Text("Dit totaal wordt gelijk verdeeld over de uitbetalingen van deze maand.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            case .hourly:
                Toggle("Andere uren dan gemiddeld", isOn: hoursOverrideEnabled(month))
                if plan.hoursOverride != nil {
                    NumberRow(title: s.isMonthly ? "Gewerkte uren" : "Gewerkte uren (hele maand)",
                              value: hoursAmount(month), unit: .plain("uur"))
                    if !s.isMonthly {
                        Text("De uren worden gelijk verdeeld over de uitbetalingen van deze maand.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ChipLink(title: "Dag voor dag bekijken", symbol: "calendar", destination: .cashflow)
        }
    }

    // MARK: Per-maand aanpassingen

    private func overrideEnabled(_ month: YearMonth) -> Binding<Bool> {
        Binding(get: { store.data.plan(for: month).salaryOverride != nil },
                set: { on in
                    withAnimation(Theme.motion) {
                        store.mutate { data in
                            // Begin bij wat het schema voor deze maand oplevert (het totaal van de uitbetalingen).
                            let fallback = data.scheduledSalary(in: month)
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
                            // Begin bij de uren die het schema voor deze maand betaalt.
                            let fallback = data.salaryHours(in: month).cents
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

// De logica hiervan (zonder SwiftUI) staat in App/UI/SavingsDisplay.swift, zodat de tests in CoreTests haar meedraaien.

/// Lijst met regels (extra inkomsten of uitgaven) voor één maand, met toevoegen, wijzigen en verwijderen.
/// Bij uitgaven kun je kiezen of je alleen vaste of alleen variabele posten toont.
///
/// Een terugkerende regel komt elke maand terug op zijn eigen dag, ook in maanden die nog komen. Bij wijzigen en
/// verwijderen kies je of het alleen voor deze maand geldt of ook voor de maanden erna.
struct MoneyLinesBlock: View {
    let kind: FinanceData.LineKind
    var expenseKind: ExpenseKind? = nil
    let month: YearMonth

    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var editing: MoneyLine?
    /// Een terugkerende regel waarvan het verwijderen eerst vraagt voor welke maanden.
    @State private var deleting: MoneyLine?

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
                                     onDelete: { requestDelete(line) })
                        if line.id != lines.last?.id { Divider() }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            ChipButton(title: "Toevoegen", symbol: "plus") { showAdd = true }
            if lines.contains(where: { $0.isRecurring }) {
                Text(recurringHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showAdd) {
            MoneyLineSheet(line: nil, kind: kind, month: month, defaultExpenseKind: expenseKind ?? .fixed)
        }
        .sheet(item: $editing) { line in
            MoneyLineSheet(line: line, kind: kind, month: month, defaultExpenseKind: line.kind)
        }
        .confirmationDialog(RecurringText.deleteTitle,
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { pending in
            Button(RecurringText.skipTitle) { remove(pending, scope: .thisMonth) }
            Button(RecurringText.stopTitle, role: .destructive) { remove(pending, scope: .thisAndFollowing) }
            Button("Annuleer", role: .cancel) {}
        } message: { pending in
            Text(RecurringText.deleteMessage(name: pending.name, month: month, current: store.now))
        }
    }

    private var recurringHint: String {
        if month > store.now {
            return "Terugkerende regels staan er vanzelf in. Pas je er een aan, dan kies je of dat alleen voor \(Fmt.month(month)) geldt of ook voor de maanden erna."
        }
        return "Een terugkerende regel komt elke maand terug op zijn eigen dag, ook in maanden die nog komen."
    }

    private func subtitle(total: Double, fromPots: Double) -> String {
        if fromPots > 0 { return "Totaal \(Fmt.euro(total)) · \(Fmt.euro(fromPots)) uit spaarpotten" }
        return "Totaal \(Fmt.euro(total))"
    }

    /// Een eenmalige regel verdwijnt meteen; bij een terugkerende vraagt de app eerst voor welke maanden.
    private func requestDelete(_ line: MoneyLine) {
        if line.isRecurring {
            deleting = line
        } else {
            remove(line, scope: .thisAndFollowing)
        }
    }

    private func remove(_ line: MoneyLine, scope: SeriesScope) {
        let lineKind = kind
        let lineMonth = month
        withAnimation(Theme.motion) {
            store.mutate { $0.removeLine(id: line.id, kind: lineKind, in: lineMonth, scope: scope) }
        }
    }
}

/// Eén regel in de lijst: naam, dag van de maand, of hij terugkeert, eventueel de spaarpot(ten) waar het uit komt, en het bedrag.
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
        let rawDay = kind == .income ? d.incomeDay(of: line, in: month) : d.expenseDay(of: line)
        let day = min(rawDay, month.dayCount)
        let payers = payingPots(d)
        let payerNames = DayText.list(payers.map { $0.name })
        let info: SeriesInfo? = line.isRecurring ? d.seriesInfo(of: line, in: month) : nil
        let note = RecurringText.rowNote(info: info, month: month, current: store.now)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(DayText.ordinal(day), systemImage: "calendar")
                    if line.isRecurring {
                        Label("Terugkerend, elke maand", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let note {
                    Text(note.text)
                        .font(.caption2)
                        .foregroundStyle(note.isWarning ? Theme.warning : Color.secondary)
                }
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
                Button(line.isRecurring ? "Verwijder…" : "Verwijder", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Opties voor \(line.name)")
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
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: Double
    @State private var recurring: Bool
    @State private var expenseKind: ExpenseKind
    @State private var day: Int?
    @State private var fromPotsOn: Bool
    /// Bedrag per spaarpot (alleen potten met een bedrag boven nul tellen mee).
    @State private var shareAmounts: [UUID: Double]
    /// Het verwijderen van een terugkerende regel vraagt eerst voor welke maanden.
    @State private var confirmingDelete = false

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
        SheetScaffold(title: titleText, canSave: canSave(d), onSave: { save(scope: .thisAndFollowing) },
                      saveChoices: saveChoices()) {
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
            } footer: {
                Text(footerText(d))
            }
            Section {
                Toggle("Terugkerend, elke maand", isOn: recurringBinding)
            } footer: {
                Text(recurringFooter(d))
            }
            if kind == .expense && !d.pots.isEmpty {
                potSection(d)
            }
            if let line {
                deleteSection(line)
            }
        }
        .confirmationDialog(RecurringText.deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(RecurringText.skipTitle) { removeAndClose(scope: .thisMonth) }
            Button(RecurringText.stopTitle, role: .destructive) { removeAndClose(scope: .thisAndFollowing) }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(RecurringText.deleteMessage(name: line?.name ?? "", month: month, current: store.now))
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

    // MARK: Dag en terugkerend

    private func defaultDayPhrase(_ d: FinanceData) -> String {
        if kind == .expense { return DayText.ordinal(1) }
        let ordinal = DayText.ordinal(d.salaryDay(in: month))
        return d.salary.isMonthly ? "je salarisdag, \(ordinal)" : "de eerste salarisdag van de maand, \(ordinal)"
    }

    private func defaultDayText(_ d: FinanceData) -> String {
        if kind == .expense { return "Standaard (\(DayText.ordinal(1)))" }
        return "Standaard (\(DayText.ordinal(d.salaryDay(in: month))))"
    }

    private func footerText(_ d: FinanceData) -> String {
        let phrase = RecurringText.dayPhrase(day: day, defaultPhrase: defaultDayPhrase(d))
        if kind == .income {
            return "Voor \(Fmt.month(month)). Dit komt binnen op \(phrase). Kies een andere dag als het bedrag op een ander moment binnenkomt."
        }
        return "Voor \(Fmt.month(month)). Dit gaat van je rekening op \(phrase). Vast zijn kosten die elke maand gelijk zijn, zoals huur. Variabel zijn kosten die schommelen, zoals boodschappen."
    }

    private var recurringBinding: Binding<Bool> {
        Binding(get: { recurring }, set: { on in withAnimation(Theme.motion) { recurring = on } })
    }

    /// Wat "Terugkerend" voor deze regel inhoudt: op welke dag hij terugkomt, vanaf en tot wanneer.
    private func recurringFooter(_ d: FinanceData) -> String {
        let phrase = RecurringText.dayPhrase(day: day, defaultPhrase: defaultDayPhrase(d))
        let wasRecurring = line?.isRecurring == true
        guard recurring else { return RecurringText.oneOff(month: month, wasRecurring: wasRecurring) }
        if let line, line.isRecurring {
            return RecurringText.existingRecurring(dayPhrase: phrase, day: effectiveDay, info: d.seriesInfo(of: line, in: month),
                                                   month: month)
        }
        // Een nieuwe terugkerende regel loopt door in een reeks met dezelfde naam die in deze maand ontbreekt.
        let resumes = line == nil && d.resumableSeries(named: name, kind: kind, in: month) != nil
        return RecurringText.newRecurring(dayPhrase: phrase, day: effectiveDay, month: month, resumes: resumes)
    }

    /// De dag waarop deze regel valt, begrensd op de lengte van de maand.
    private var effectiveDay: Int {
        let fallback = kind == .income ? store.data.salaryDay(in: month) : 1
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
        // Per kalenderdag: de dag van vandaag is al gebeurd, pas een latere dag is verwacht.
        let prefix = DayMath.isPlanned(lineDate, asOf: store.today) ? "Verwacht saldo op" : "Saldo op"
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

    // MARK: Verwijderen

    @ViewBuilder
    private func deleteSection(_ existing: MoneyLine) -> some View {
        Section {
            Button(role: .destructive) {
                requestDelete(existing)
            } label: {
                Text(existing.isRecurring ? "Verwijder…" : "Verwijder")
            }
        }
    }

    /// Een eenmalige regel verdwijnt meteen; bij een terugkerende vraagt de app eerst voor welke maanden.
    private func requestDelete(_ existing: MoneyLine) {
        if existing.isRecurring {
            confirmingDelete = true
        } else {
            removeAndClose(scope: .thisAndFollowing)
        }
    }

    private func removeAndClose(scope: SeriesScope) {
        guard let existing = line else { return }
        let lineKind = kind
        let lineMonth = month
        withAnimation(Theme.motion) {
            store.mutate { $0.removeLine(id: existing.id, kind: lineKind, in: lineMonth, scope: scope) }
        }
        dismiss()
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

    /// Bij een regel die al terugkeert vraagt "Bewaar" eerst voor welke maanden de wijziging geldt (alleen deze maand, of
    /// ook alle maanden erna). Is er niets gewijzigd, of keerde de regel niet terug, dan wordt meteen opgeslagen.
    private func saveChoices() -> SaveChoices? {
        let edited = draftLine()
        guard LineSave.needsScopeQuestion(existing: line, edited: edited) else { return nil }
        let thisMonth = SaveChoices.Option(id: "this", title: SeriesScope.thisMonth.title) { save(scope: .thisMonth) }
        if edited.isRecurring {
            let following = SaveChoices.Option(id: "following", title: SeriesScope.thisAndFollowing.title) {
                save(scope: .thisAndFollowing)
            }
            return SaveChoices(title: RecurringText.scopeTitle,
                               message: RecurringText.scopeMessage(name: edited.name, month: month, current: store.now),
                               options: [thisMonth, following])
        }
        let stop = SaveChoices.Option(id: "stop", title: RecurringText.stopTitle, role: .destructive) {
            save(scope: .thisAndFollowing)
        }
        return SaveChoices(title: RecurringText.stopRecurringTitle,
                           message: RecurringText.stopRecurringMessage(name: edited.name, month: month, current: store.now),
                           options: [thisMonth, stop])
    }

    private func save(scope: SeriesScope) {
        let edited = draftLine()
        // Niets gewijzigd: niets opslaan (een afgeleide regel van een toekomstige maand blijft dan afgeleid).
        if let line, line == edited { return }
        let isNew = line == nil
        let lineKind = kind
        let lineMonth = month
        withAnimation(Theme.motion) {
            store.mutate { LineSave.apply(&$0, edited: edited, isNew: isNew, kind: lineKind, month: lineMonth, scope: scope) }
        }
    }
}

// MARK: - Verdelen

// De logica hiervan (zonder SwiftUI) staat in App/UI/SavingsDisplay.swift, zodat de tests in CoreTests haar meedraaien.

/// Eén spaarpot of belegging op de pagina Verdelen: de inleg van deze maand als vast bedrag of als percentage van het
/// inkomen (per maand te overschrijven), met wat het percentage in euro's oplevert, de overschrijfdag en de standaard.
private struct AllocationRow: View {
    let id: UUID
    let name: String
    let symbol: String
    let color: Color
    let month: YearMonth
    /// "Wordt overgeschreven op de 25e · salarisdag" (de pagina stelt dit samen uit de rekenmotor).
    let caption: String

    @Environment(AppStore.self) private var store

    private var modeBinding: Binding<ContributionMode> {
        Binding(get: { store.data.allocationRule(id, in: month).isPercent ? ContributionMode.percentage : ContributionMode.fixed },
                set: { newMode in
                    withAnimation(Theme.motion) {
                        store.mutate { AllocationEdit.setMode(&$0, id: id, month: month, to: newMode) }
                    }
                })
    }

    private var amountBinding: Binding<Double> {
        Binding(get: { store.data.allocation(id, in: month) },
                set: { value in store.mutate { AllocationEdit.setAmount(&$0, id: id, month: month, amount: value) } })
    }

    private var percentBinding: Binding<Double> {
        Binding(get: {
            if case .percent(let rule) = store.data.allocationRule(id, in: month) { return rule.percent }
            return 0
        }, set: { value in
            store.mutate { AllocationEdit.setPercent(&$0, id: id, month: month, percent: value) }
        })
    }

    private var basisBinding: Binding<IncomeBasis> {
        Binding(get: {
            if case .percent(let rule) = store.data.allocationRule(id, in: month) { return rule.basis }
            return IncomeBasis.salary
        }, set: { newBasis in
            withAnimation(Theme.motion) {
                store.mutate { AllocationEdit.setBasis(&$0, id: id, month: month, to: newBasis) }
            }
        })
    }

    var body: some View {
        let d = store.data
        let effective = d.effectiveAllocation(id, in: month)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: symbol, color: color, size: 30)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 6)
                if effective.isOverride {
                    Text("Afwijkend")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.warning)
                        .transition(.opacity)
                }
            }
            ContributionFields(mode: modeBinding, amount: amountBinding, percent: percentBinding, basis: basisBinding,
                               allowsNegativeAmount: true,
                               resolvedAmount: effective.rule.isPercent ? effective.amount : nil,
                               resolvedNote: effective.rule.isPercent ? effective.rule.summary : nil,
                               footnote: noIncomeNote(d, rule: effective.rule), subject: name)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if effective.isOverride {
                standardRow(d)
            }
        }
        .padding(10)
        .tile()
    }

    /// Een percentage van niets is niets: zeg dat, anders lijkt het veld stuk.
    private func noIncomeNote(_ d: FinanceData, rule: AllocationRule) -> String? {
        guard case .percent(let percent) = rule, d.incomeBases(in: month).cents(for: percent.basis) == 0 else { return nil }
        let what = percent.basis == .salary ? "salaris" : "inkomen"
        return "Er is in \(Fmt.month(month)) geen \(what): het percentage geeft nu € 0."
    }

    /// Wat de standaard is, met de knoppen om daarnaar terug te gaan of van deze maand de standaard te maken.
    @ViewBuilder
    private func standardRow(_ d: FinanceData) -> some View {
        let standard = d.defaultAllocationRule(id, in: month)
        Text("Standaard: \(standard?.summary ?? Fmt.euro(0))")
            .font(.caption)
            .foregroundStyle(.secondary)
        ChipGrid {
            ChipButton(title: "Terug naar standaard", symbol: "arrow.counterclockwise") {
                withAnimation(Theme.motion) {
                    store.mutate { AllocationEdit.resetToStandard(&$0, id: id, month: month) }
                }
            }
            // Van een maand in het verleden maak je geen standaard: dat gaat over wat er vanaf nu gebeurt.
            if month >= store.now {
                ChipButton(title: "Maak dit je standaard", symbol: "pin") {
                    let current = store.now
                    withAnimation(Theme.motion) {
                        store.mutate { AllocationEdit.makeStandard(&$0, id: id, month: month, current: current) }
                    }
                }
            }
        }
    }
}

struct DistributePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let figures = d.monthFigures(month)
        let plan = d.plan(for: month)

        PageScaffold(title: "Verdelen") {
            VStack(spacing: Theme.pageSpacing) {
                MonthPickerBlock()
                remainingBlock(d, month: month, figures: figures)
                transferDayBlock(d, month: month, plan: plan)
                potsBlock(d, month: month)
                holdingsBlock(d, month: month)
            }
        }
    }

    // MARK: Nog te verdelen

    @ViewBuilder
    private func remainingBlock(_ d: FinanceData, month: YearMonth, figures: MonthFigures) -> some View {
        // Dezelfde formule als overal: inkomen − uitgaven van de bank − verdeeld − belegd.
        let left = CentsMath.value(figures.remaining)
        let allocatedCents = CentsMath.add(figures.saved, figures.invested)
        let availableCents = figures.available
        let over = left < 0
        let fromPots = CentsMath.value(figures.fromPots)
        // Waar de verdeling niet klopt (percentages samen boven 100%, of meer verdeeld dan er is): tekst van de rekenmotor.
        let warnings = d.allocationWarnings(in: month)
        let explanation = percentExplanation(d, month: month)
        // Altijd drie naast elkaar, ook op een smalle iPhone.
        let tiles = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

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
            if month < d.startMonth {
                Text("Maanden vóór je startmaand (\(Fmt.month(d.startMonth))) tellen niet mee: daar verdeel je niets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if availableCents < 0 {
                Text("Je uitgaven zijn hoger dan je inkomen deze maand.")
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
            }
            ForEach(warnings, id: \.message) { warning in
                Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(warningColor(warning))
            }
            if let explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }

    private func warningColor(_ warning: AllocationWarning) -> Color {
        switch warning {
        case .percentagesOver100: return Theme.warning
        case .overAllocated: return Theme.negative
        }
    }

    /// Waarover de percentages van deze maand rekenen, en wat ze samen vragen. nil als niets een percentage heeft.
    private func percentExplanation(_ d: FinanceData, month: YearMonth) -> String? {
        let ids = d.pots.map { $0.id } + d.holdings.map { $0.id }
        guard ids.contains(where: { d.allocationRule($0, in: month).isPercent }) else { return nil }
        let bases = d.incomeBases(in: month)
        let salary = Fmt.euro(CentsMath.value(bases.cents(for: .salary)))
        let all = Fmt.euro(CentsMath.value(bases.cents(for: .allIncome)))
        let total = Fmt.percent(d.percentTotal(in: month) / 100, digits: 2)
        return "Een percentage rekent over het inkomen van \(Fmt.month(month)): \(salary) salaris, \(all) met extra inkomsten. Je percentages samen: \(total). \"Rest over potten\" maakt van een percentage een vast bedrag."
    }

    // MARK: Overschrijfdag

    @ViewBuilder
    private func transferDayBlock(_ d: FinanceData, month: YearMonth, plan: MonthPlan) -> some View {
        GlassBlock(title: "Overschrijfdag", symbol: "calendar.badge.clock",
                   subtitle: "Wanneer gaat het geld naar de potten?") {
            DayPickerRow(title: "Dag van de maand", day: planDayBinding(month),
                         defaultText: "Standaard")
            Text(transferExplanation(plan: plan, month: month, d: d))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Op de overschrijfdag gaat het bedrag automatisch van je bankrekening naar de spaarpot of belegging. Dat geldt ook voor maanden die nog komen. Tot die dag telt het bedrag niet mee in het saldo van de pot.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func planDayBinding(_ month: YearMonth) -> Binding<Int?> {
        Binding<Int?>(get: { store.data.months[month.key]?.transferDay },
                      set: { value in
                          withAnimation(Theme.motion) {
                              store.mutate { $0.editPlan(month) { $0.transferDay = value } }
                          }
                      })
    }

    private func transferExplanation(plan: MonthPlan, month: YearMonth, d: FinanceData) -> String {
        if let chosen = plan.transferDay {
            let day = min(YearMonth.clampedDay(chosen), month.dayCount)
            return "Alles wat je deze maand verdeelt gaat op \(DayText.ordinal(day)) over."
        }
        let salaryDay = DayText.ordinal(d.salaryDay(in: month))
        let phrase = d.salary.isMonthly ? "je salarisdag (\(salaryDay))" : "de eerste salarisdag van de maand (\(salaryDay))"
        return "Standaard geldt per pot of belegging de eigen overschrijfdag, en anders \(phrase)."
    }

    /// Waar de dag van een pot of belegging vandaan komt.
    private func transferSource(id: UUID, month: YearMonth, d: FinanceData) -> String {
        if d.months[month.key]?.transferDay != nil { return "dag van deze maand" }
        let ownDay = d.pot(id)?.transferDay ?? d.holdings.first(where: { $0.id == id })?.transferDay
        if ownDay != nil { return "eigen dag" }
        return d.salary.isMonthly ? "salarisdag" : "eerste salaris van de maand"
    }

    /// "Wordt overgeschreven op de 25e · salarisdag"
    private func transferCaption(id: UUID, month: YearMonth, d: FinanceData) -> String {
        let day = d.transferDay(for: id, in: month)
        let source = transferSource(id: id, month: month, d: d)
        if d.allocationCents(id, in: month) == 0 {
            return "Overschrijfdag: \(DayText.ordinal(day)) · \(source)"
        }
        // Per kalenderdag: de overschrijfdag zelf is al gebeurd (vanaf het begin van die dag), pas een latere dag is gepland.
        let planned = DayMath.isPlanned(month.date(day: day), asOf: store.today)
        let verb = planned ? "Wordt overgeschreven op" : "Overgeschreven op"
        return "\(verb) \(DayText.ordinal(day)) · \(source)"
    }

    // MARK: Spaarpotten en beleggingen

    @ViewBuilder
    private func potsBlock(_ d: FinanceData, month: YearMonth) -> some View {
        GlassBlock(title: "Spaarpotten", symbol: "tray.full.fill", headerLink: .pots) {
            if d.pots.isEmpty {
                Text("Je hebt nog geen spaarpotten. Maak er een op de pagina Spaarpotten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(d.pots) { pot in
                AllocationRow(id: pot.id, name: pot.name, symbol: pot.symbol, color: Theme.color(pot.colorIndex),
                              month: month, caption: transferCaption(id: pot.id, month: month, d: d))
                    .disabled(month < d.startMonth)
            }
            if !d.pots.isEmpty || !d.holdings.isEmpty {
                Text("Wat je hier invult geldt voor \(Fmt.month(month)). Kies Percentage om een deel van je inkomen te verdelen: het bedrag rekent mee als je inkomen verandert. Een ander percentage in één maand mag ook. Wil je het elke maand, kies dan Maak dit je standaard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func holdingsBlock(_ d: FinanceData, month: YearMonth) -> some View {
        GlassBlock(title: "Beleggen", symbol: "chart.line.uptrend.xyaxis", headerLink: .portfolio) {
            if d.holdings.isEmpty {
                Text("Je hebt nog geen beleggingen. Voeg ze toe op de pagina Beleggingen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(d.holdings) { h in
                AllocationRow(id: h.id, name: h.name, symbol: h.kind.symbol, color: Theme.accent,
                              month: month, caption: transferCaption(id: h.id, month: month, d: d))
                    .disabled(month < d.startMonth)
            }
        }
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

/// Het saldo van de bankrekening van nu. Dit is hetzelfde getal als het saldo aan het eind van vandaag op de dagpagina
/// (`DayTotals.bankBalance`): alles gebeurt per kalenderdag, dus wat vandaag op je plan staat telt al mee. Het eindsaldo
/// van de maand is `bankBalance(at:)` (`MonthLedger.closingBank`).
struct BankBalanceBlock: View {
    @Environment(AppStore.self) private var store
    @Binding var action: BankAction?

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        // Alleen een saldo tonen als het van nu bekend is: een saldo dat pas later begint zegt niets over vandaag.
        let balanceNow = d.bankBalanceNowIfKnown(current: now, today: today)
        let monthEnd = d.bankBalance(at: now)
        GlassBlock(title: "Saldo nu", symbol: "building.columns.fill",
                   subtitle: balanceNow == nil ? nil : "Vandaag, \(DayText.weekdayShort(today))",
                   tint: Theme.olive.opacity(0.3)) {
            if let balanceNow {
                BigAmount(value: balanceNow, color: balanceNow < 0 ? Theme.negative : Color.primary)
                if let monthEnd {
                    StatTile(title: "Eind van \(Fmt.month(now))", value: Fmt.euro(monthEnd),
                             color: monthEnd < 0 ? Theme.negative : Color.primary,
                             caption: "verwacht, met alles wat nog komt")
                }
                Text(explanation(d))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if d.hasBankBalance {
                EmptyHint(symbol: "calendar.badge.clock", title: "Je saldo van vandaag is nog niet bekend",
                          message: "Wat je invulde begint pas op een latere dag. Vul je saldo van vandaag in.")
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

    /// Hoe het saldo tot stand komt, met de regel voor een ingevuld saldo.
    private func explanation(_ d: FinanceData) -> String {
        let perDay = "Het saldo telt per dag: wat vandaag op je plan staat, is al meegerekend."
        if let last = d.sortedBankSnapshots.last {
            return "Laatst ingevuld: \(Fmt.euro(last.balance)) op \(Fmt.date(last.date)). Boekingen van de dag waarop je het saldo invult gelden als al verwerkt. Stortingen, opnames en alles wat je plant komen daar bovenop, op de dag waarop het gebeurt. \(perDay)"
        }
        return "Het saldo volgt je stortingen, opnames en alles wat je plant, op de dag waarop het gebeurt. \(perDay)"
    }
}

/// Wat er in een maand binnenkomt, uitgaat en overblijft, met een knop om de standaardposten in te vullen.
/// Onderaan staat het saldo aan het eind van de maand (`bankBalance(at:)`, hetzelfde als `MonthLedger.closingBank`).
struct BankFlowBlock: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store
    @State private var message: String?

    /// Het deel van de uitgaven van één soort dat van de bankrekening gaat, zoals de rekenmotor het boekt per regel.
    private func bankPart(_ d: FinanceData, kind: ExpenseKind) -> Double {
        guard month >= d.startMonth else { return 0 }
        return CentsMath.value(CentsMath.sum(d.expenseLines(in: month, kind: kind).map { CentsMath.int(d.fromBank(of: $0)) }))
    }

    var body: some View {
        let d = store.data
        let o = d.expenseOverview(in: month)
        let missing = d.missingStandardExpenses(in: month).count
        // De balk toont wat van de bank gaat, zodat alle stukken samen het inkomen vormen.
        let fixedBank = bankPart(d, kind: .fixed)
        let variableBank = bankPart(d, kind: .variable)
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
            if let note = payoutNote(d) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if o.leftAfterTransfers < 0 {
                Text("Je geeft meer uit en verdeelt meer dan je inkomen. Pas je uitgaven of je verdeling aan.")
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
            }
            endBalance(d)
            ChipGrid {
                ChipButton(title: missing == 0 ? "Standaardposten staan erin" : "Standaard uitgaven invullen",
                           symbol: "wand.and.stars") {
                    let added = store.data.missingStandardExpenses(in: month).count
                    withAnimation(Theme.motion) { store.mutate { $0.fillStandardExpenses(in: month) } }
                    message = added == 0 ? "Alle standaardposten staan al in deze maand."
                                         : "\(added) standaardposten ingevuld met een richtbedrag. Ze komen elke maand terug; pas ze aan naar jouw situatie."
                }
                ChipLink(title: "Geld verdelen", symbol: "square.split.2x2", destination: .distribute)
                ChipLink(title: "Dag voor dag", symbol: "calendar", destination: .cashflow)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if missing > 0 {
                Text("De knop vult gangbare vaste en variabele posten in met een richtbedrag, als terugkerende regel. Je kunt alles daarna aanpassen of verwijderen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Komt het salaris vaker dan één keer in de maand binnen, dan staat hier wanneer.
    private func payoutNote(_ d: FinanceData) -> String? {
        let payouts = d.salaryPayouts(in: month, plan: d.plan(for: month)).filter { $0.cents != 0 }
        guard payouts.count > 1 else { return nil }
        return "Je salaris komt in \(Fmt.month(month)) \(payouts.count) keer binnen: \(d.salaryPayoutDaysText(in: month))."
    }

    /// Het saldo van de rekening aan het eind van de maand: begin, binnen, eruit en overgeschreven, met handmatige boekingen
    /// en je ingevulde saldo erbij. Per dag staat het bij Dag voor dag.
    @ViewBuilder
    private func endBalance(_ d: FinanceData) -> some View {
        if let closing = d.bankBalance(at: month) {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                FlowRow(title: "Saldo aan het eind van de maand", value: closing, bold: true,
                        color: closing < 0 ? Theme.negative : Color.primary)
                Text("Dit is het saldo van je rekening, met je eigen stortingen, opnames en ingevulde saldo. Per dag zie je het bij Dag voor dag.")
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
/// Bij een percentage staat erbij welk percentage het is; het bedrag is altijd wat de rekenmotor van dat percentage maakt.
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
        let detail: String
    }

    /// "de 25e" of, bij een percentage, "de 25e · 10% van je salaris".
    private func detail(_ d: FinanceData, id: UUID, day: Int) -> String {
        let rule = d.allocationRule(id, in: month)
        return rule.isPercent ? "\(DayText.ordinal(day)) · \(rule.summary)" : DayText.ordinal(day)
    }

    var body: some View {
        let d = store.data
        let potRows: [Row] = d.pots.map { pot in
            let day = d.transferDay(for: pot.id, in: month)
            return Row(id: pot.id, symbol: pot.symbol, color: Theme.color(pot.colorIndex), title: pot.name,
                       amount: d.allocation(pot.id, in: month), day: day, detail: detail(d, id: pot.id, day: day))
        }.filter { $0.amount != 0 }
        let holdingRows: [Row] = d.holdings.map { h in
            let day = d.transferDay(for: h.id, in: month)
            return Row(id: h.id, symbol: h.kind.symbol, color: Theme.flowInvested, title: h.name,
                       amount: d.allocation(h.id, in: month), day: day, detail: detail(d, id: h.id, day: day))
        }.filter { $0.amount != 0 }
        let rows = (potRows + holdingRows).sorted { lhs, rhs in
            lhs.day != rhs.day ? lhs.day < rhs.day : lhs.title < rhs.title
        }
        // Samen precies wat het overzicht als gespaard en belegd telt.
        let figures = d.monthFigures(month)
        let total = CentsMath.value(CentsMath.add(figures.saved, figures.invested))
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
                                    dayText: row.detail)
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
                Text("Gebaseerd op je saldo, inkomen, uitgaven en verdeling per maand. Het eindsaldo van een maand is hetzelfde getal als bij Binnen en eruit en bij Dag voor dag. De grafiek past zich aan als je iets wijzigt.")
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
        // Alleen als het saldo van nu bekend is: zonder saldo zegt "daarboven" niets.
        if d.hasBankBalanceNow(current: now, today: store.today) {
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
        // Saldo's van nu, per kalenderdag: wat vandaag op je plan staat telt al mee, wat op een latere dag komt (het salaris
        // van de 25e, de inleg) nog niet.
        let bank = d.bankBalanceNowIfKnown(current: now, today: today)
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
            if action == .balance { amount = bank ?? 0 }
            if potID == nil { potID = d.pots.first?.id }
        }
    }

    private func headerText(bank: Double?, potBalance: Double) -> String {
        let bankText = bank.map { Fmt.euro($0) } ?? "onbekend"
        switch action {
        case .fromPot: return "Saldo spaarpot \(Fmt.euro(potBalance)) · bankrekening \(bankText)"
        default: return "Saldo bankrekening \(bankText)"
        }
    }

    private var footerText: String {
        switch action {
        case .balance: return "Vul het saldo in zoals het nu op je rekening staat. Boekingen van de dag waarop je het saldo invult gelden als al verwerkt. Elke invoer wordt bewaard."
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
