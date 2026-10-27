import SwiftUI

// Het Maandoverzicht (`.flow`, B7 van docs/design2/plan.md): de oude kaart "Waar gaat je geld heen" van de Maand-tab als eigen
// pagina, met alles wat erop stond: de keuze Maand, Half jaar of Jaar, de grafiek per maand, de tegel Nog te verdelen en de
// uitklappers "Cijfers van deze periode" en "Maand voor maand". Alle bedragen komen uit dezelfde bronnen als toen
// (`periodSummary`, `summaries`, `StackedBarModel.months`, `MonthBoard`). Alleen inhoud: de stapel komt van `TabStack`.

/// De pagina Maandoverzicht: de `MonthBar` (stapt per maand) en daaronder "Waar gaat je geld heen".
struct FlowPage: View {
    var body: some View {
        PageScaffold(title: "Maandoverzicht") {
            VStack(spacing: Theme.pageSpacing) {
                MonthBar()
                FlowContent()
            }
        }
    }
}

/// "Waar gaat je geld heen". De keuze Maand, Half jaar of Jaar (`PeriodPicker`) bepaalt alleen de lengte van het venster en
/// verschuift `focusMonth` niet (K17); de grafiek toont per maand uitgaven, gespaard, belegd en wat over is. Eronder de tegel
/// Nog te verdelen (voor het verleden en periodes: Overgehouden) en twee uitklappers: "Cijfers van deze periode" en
/// "Maand voor maand".
struct FlowContent: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var figuresOpen = false
    @State private var monthsOpen = false

    var body: some View {
        let d = store.data
        let now = store.now
        let mode = router.periodMode
        let focus = router.focusMonth
        let period = d.periodSummary(mode, containing: focus, current: now)
        let label = MoneyLabels.remainingLabel(of: focus, current: now, isPeriod: mode != .month)
        Card(title: "Waar gaat je geld heen", symbol: "chart.bar.xaxis", domain: .money,
             subtitle: Fmt.period(mode, containing: focus)) {
            PeriodPicker()
            chart(d, mode: mode, focus: focus, now: now)
            leftTile(period: period, label: label)
            Divider()
            figuresGroup(period: period, focus: focus, label: label)
            monthsGroup(period: period, now: now)
        }
    }

    // MARK: Grafiek en tegel

    /// De staven per maand in het gekozen venster (`chartMonths`: bij Maand de laatste zes maanden tot en met de gekozen maand).
    private func chart(_ d: FinanceData, mode: PeriodMode, focus: YearMonth, now: YearMonth) -> some View {
        let months = chartMonths(mode: mode, focus: focus)
        let summaries = d.summaries(from: months.first ?? focus, count: months.count, current: now)
        let model = StackedBarModel.months(summaries, startMonth: d.startMonth)
        return StackedBarChart(model: model, size: .regular, onAction: handleChartAction)
    }

    /// Wat er van het inkomen van de periode over is: dezelfde som als `remaining(in:)`, ook voor een periode.
    private func leftTile(period: PeriodSummary, label: String) -> some View {
        let left = period.remaining
        return FigureRow {
            StatTile(title: label, value: Fmt.euro(left), color: left < 0 ? Theme.negative : Color.primary,
                     caption: period.hasProjected ? "Verwacht" : nil)
        }
    }

    /// De knop in de lege staat van de grafiek: "Salaris instellen".
    private func handleChartAction(_ action: ChartEmpty.Action) {
        if case .openSalary = action {
            router.open(.salary)
        }
    }

    // MARK: Uitklappers

    private func figuresGroup(period: PeriodSummary, focus: YearMonth, label: String) -> some View {
        let left = period.remaining
        return DisclosureGroup(isExpanded: $figuresOpen) {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                AmountRow(title: "Inkomen", value: Fmt.euro(period.income))
                AmountRow(title: "Uitgaven", value: Fmt.euro(period.expenses))
                AmountRow(title: "Gespaard", value: Fmt.euro(period.saved))
                AmountRow(title: "Belegd", value: Fmt.euro(period.invested))
                AmountRow(title: "Gemiddeld overgehouden per maand", value: Fmt.euro(period.average(left)))
                figureNotes(period: period, focus: focus, label: label)
            }
            .padding(.top, 8)
        } label: {
            disclosureLabel("Cijfers van deze periode")
        }
        .animated(by: figuresOpen)
    }

    /// De toelichtingen bij de cijfers: verwachte maanden, wat uit spaarpotten komt en de afronding.
    @ViewBuilder
    private func figureNotes(period: PeriodSummary, focus: YearMonth, label: String) -> some View {
        if period.hasProjected {
            FlowNote(text: "Maanden na deze maand zijn verwacht: ze volgen je salarisschema, terugkerende regels en standaardinleg.")
        }
        if period.fromPots > 0 {
            FlowNote(text: "Waarvan \(Fmt.euro(period.fromPots)) uit spaarpotten betaald. Dat telt niet mee in \(label).")
        }
        if MonthBoard(month: focus, figures: period.figures).roundingHidesSum {
            RoundingNote()
        }
    }

    private func monthsGroup(period: PeriodSummary, now: YearMonth) -> some View {
        DisclosureGroup(isExpanded: $monthsOpen) {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach(period.months) { summary in
                    AmountRow(title: Fmt.month(summary.month), value: Fmt.euro(summary.remaining),
                              detail: monthDetail(summary, now: now),
                              color: summary.remaining < 0 ? Theme.negative : Color.primary)
                }
            }
            .padding(.top, 8)
        } label: {
            disclosureLabel("Maand voor maand")
        }
        .animated(by: monthsOpen)
    }

    /// "Overgehouden · € 3.000 in · € 2.000 uit", met "verwacht" erbij voor een maand die nog komt.
    private func monthDetail(_ summary: MonthSummary, now: YearMonth) -> String {
        let label = MoneyLabels.remainingLabel(of: summary.month, current: now)
        let flows = "\(label) · \(Fmt.euro(summary.income)) in · \(Fmt.euro(summary.expenses)) uit"
        return summary.isProjected ? flows + " · verwacht" : flows
    }

    /// De kop van een uitklapper: een kop voor VoiceOver met een raakdoel van `Theme.minTapTarget`.
    private func disclosureLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Een regel uitleg onder de cijfers: klein, in de gedempte tekstkleur en nooit afgekapt.
private struct FlowNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
