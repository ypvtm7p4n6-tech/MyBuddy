import SwiftUI

// Inkomen van de gekozen maand: een samenvatting, het salaris van deze maand en de overige inkomsten. Het standaard
// salaris en het schema staan op de pagina Salaris (`SalaryPage`). De logica zonder SwiftUI staat in
// App/UI/SavingsDisplay.swift en App/UI/MoneyFigures.swift, zodat de tests in CoreTests haar meedraaien.

struct IncomePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var sheet: MoneyLineSheetRequest?

    var body: some View {
        let month = router.focusMonth
        let beforeStart = month < store.data.startMonth
        ListScaffold(title: "Inkomen") {
            Section {
                MonthBar()
            }
            IncomeSummarySection(month: month)
            IncomeSalarySection(month: month)
            MoneyLinesSection(kind: .income, month: month,
                              onAdd: { openAdd(month) },
                              onEdit: { line in openEdit(line, month: month) })
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                IconButton("Inkomen toevoegen", symbol: "plus") { openAdd(month) }
                    .disabled(beforeStart)
            }
        }
        .sheet(item: $sheet) { request in
            MoneyLineSheet(line: request.line, kind: request.kind, month: request.month,
                           defaultExpenseKind: request.defaultExpenseKind)
        }
    }

    private func openAdd(_ month: YearMonth) {
        sheet = MoneyLineSheetRequest(line: nil, kind: .income, month: month, defaultExpenseKind: .fixed)
    }

    private func openEdit(_ line: MoneyLine, month: YearMonth) {
        sheet = MoneyLineSheetRequest(line: line, kind: .income, month: month, defaultExpenseKind: line.kind)
    }
}

// MARK: - Samenvatting

/// Het inkomen van de maand, met Salaris en Overige inkomsten, de schemazin en de link naar Salaris instellen.
private struct IncomeSummarySection: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let salary = d.salaryAmount(in: month)
        let extra = d.extraIncomeTotal(in: month)
        let income = d.income(in: month)
        let closes = DisplayRounding.closes(parts: [CentsMath.int(salary), CentsMath.int(extra)],
                                            total: CentsMath.int(income))
        Section {
            MonthFigureHero(title: "Inkomen in \(Fmt.month(month))", value: income)
            AmountRow(title: "Salaris", value: Fmt.euro(salary))
            AmountRow(title: "Overige inkomsten", value: Fmt.euro(extra))
            if !closes {
                RoundingNote()
            }
            MonthExplanation(text: SalaryScheduleText.capitalized(d.salaryScheduleSummary(asOf: store.today)))
            NavigationRow(title: "Salaris instellen", symbol: "eurosign.circle", domain: .money, destination: .salary)
        } header: {
            SectionHeader("Samenvatting", symbol: "eurosign.circle", domain: .money)
        }
    }
}

// MARK: - Salaris deze maand

/// Eén uitbetaling van de gekozen maand, voor de lijst.
private struct IncomePayoutLine: Identifiable {
    let id: String
    let date: Date
    let amount: Double
    let isPlanned: Bool
}

/// De uitbetalingen van de maand, een afwijkend bedrag of andere uren, en een link naar Dag voor dag.
private struct IncomeSalarySection: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = store.data
        let plan = d.plan(for: month)
        // De uitbetalingen en het maandtotaal komen uit dezelfde bron als "Inkomen" op alle andere schermen.
        let payouts = payoutLines(d, plan: plan)
        Section {
            MonthExplanation(text: subtitle(d, count: payouts.count))
            ForEach(payouts) { payout in
                AmountRow(title: DayText.weekdayShort(payout.date), value: "+ " + Fmt.euro(payout.amount),
                          detail: payout.isPlanned ? "Salaris · gepland" : "Salaris", color: Theme.positive,
                          symbol: "briefcase.fill")
            }
            scheduleNote(d.salary, count: payouts.count, beforeStart: month < d.startMonth)
            overrideRows(d.salary, plan: plan)
            NavigationRow(title: "Dag voor dag", symbol: "list.bullet.rectangle", domain: .money, destination: .cashflow)
        } header: {
            SectionHeader("Salaris deze maand", symbol: "calendar", domain: .money)
        }
    }

    private func payoutLines(_ d: FinanceData, plan: MonthPlan) -> [IncomePayoutLine] {
        let today = store.today
        return d.salaryPayouts(in: month, plan: plan)
            .filter { $0.cents != 0 }
            .map { payout in
                let date = month.date(day: payout.day)
                return IncomePayoutLine(id: payout.id, date: date, amount: CentsMath.value(payout.cents),
                                        isPlanned: DayMath.isPlanned(date, asOf: today))
            }
    }

    private func subtitle(_ d: FinanceData, count: Int) -> String {
        if month < d.startMonth { return "Voor je startmaand telt er geen salaris mee" }
        switch count {
        case 0: return "Geen salaris deze maand"
        case 1: return "Komt binnen op \(d.salaryPayoutDaysText(in: month))"
        default: return "\(SalaryScheduleText.payoutCount(count)): \(d.salaryPayoutDaysText(in: month))"
        }
    }

    /// Bij een schema om de zoveel weken of dagen: wat het aantal uitbetalingen van deze maand betekent.
    @ViewBuilder
    private func scheduleNote(_ s: SalarySettings, count: Int, beforeStart: Bool) -> some View {
        if !s.isMonthly {
            if count == 0 && !beforeStart {
                MonthExplanation(text: "In \(Fmt.month(month)) valt er geen uitbetaling: je salaris komt \(s.cycleDescription) binnen en deze maand zit daar tussenin.")
            } else if count >= 2 {
                MonthExplanation(text: "Deze maand krijg je \(count) keer salaris. Het maandtotaal is de som van de uitbetalingen en telt overal zo mee: bij Inkomen, bij \"Nog te verdelen\" en bij een inleg als percentage van je inkomen.")
            } else if count == 1 {
                MonthExplanation(text: "Deze maand krijg je 1 keer salaris. In een maand met een extra uitbetaling is je inkomen hoger.")
            }
        }
    }

    @ViewBuilder
    private func overrideRows(_ s: SalarySettings, plan: MonthPlan) -> some View {
        switch s.mode {
        case .fixed:
            Toggle("Afwijkend bedrag deze maand", isOn: overrideEnabled)
            if plan.salaryOverride != nil {
                NumberRow(title: s.isMonthly ? "Salaris" : "Totaal van de maand", value: overrideAmount)
                if !s.isMonthly {
                    MonthExplanation(text: "Dit totaal wordt gelijk verdeeld over de uitbetalingen van deze maand.")
                }
            }
        case .hourly:
            Toggle("Andere uren dan gemiddeld", isOn: hoursOverrideEnabled)
            if plan.hoursOverride != nil {
                NumberRow(title: s.isMonthly ? "Gewerkte uren" : "Gewerkte uren (hele maand)",
                          value: hoursAmount, unit: .plain("uur"))
                if !s.isMonthly {
                    MonthExplanation(text: "De uren worden gelijk verdeeld over de uitbetalingen van deze maand.")
                }
            }
        }
    }

    // MARK: Aanpassingen voor deze maand

    private var overrideEnabled: Binding<Bool> {
        let month = month
        return Binding(get: { store.data.plan(for: month).salaryOverride != nil },
                       set: { on in
                           withAnimation(reduceMotion ? nil : Theme.motion) {
                               store.mutate { data in
                                   // Begin bij wat het schema voor deze maand oplevert (het totaal van de uitbetalingen).
                                   let fallback = data.scheduledSalary(in: month)
                                   data.editPlan(month) { $0.salaryOverride = on ? fallback : nil }
                               }
                           }
                       })
    }

    private var overrideAmount: Binding<Double> {
        let month = month
        return Binding(get: { store.data.plan(for: month).salaryOverride ?? 0 },
                       set: { value in store.mutate { $0.editPlan(month) { $0.salaryOverride = value } } })
    }

    private var hoursOverrideEnabled: Binding<Bool> {
        let month = month
        return Binding(get: { store.data.plan(for: month).hoursOverride != nil },
                       set: { on in
                           withAnimation(reduceMotion ? nil : Theme.motion) {
                               store.mutate { data in
                                   // Begin bij de uren die het schema voor deze maand betaalt.
                                   let fallback = data.salaryHours(in: month).cents
                                   data.editPlan(month) { $0.hoursOverride = on ? fallback : nil }
                               }
                           }
                       })
    }

    private var hoursAmount: Binding<Double> {
        let month = month
        return Binding(get: { store.data.plan(for: month).hoursOverride ?? 0 },
                       set: { value in store.mutate { $0.editPlan(month) { $0.hoursOverride = value } } })
    }
}
