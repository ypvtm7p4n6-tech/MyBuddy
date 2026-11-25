import SwiftUI

// Het salaris instellen: het standaard salaris (vast of uurloon), het loon per maand, de uren van de volgende uitbetalingen (bij uren
// uit je agenda) en wanneer je het krijgt (het schema). Een rekenpagina met kaarten: de invoer is een formulier en geen lijst met
// rijen. Het schema en de soort gelden vanaf de lopende maand en leggen het verleden vast (`SalaryScheduleEdit`); een nieuw bedrag
// (uurloon, vast bedrag, uren per week) gaat via `FinanceData.setWage(current:...)`: is er al salaris in het verleden, dan wordt het
// een wijziging vanaf deze maand (docs/work/plan2.md par. 2.6 en 4.6).

struct SalaryPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(WorkCalendarController.self) private var workCalendar: WorkCalendarController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = store.data
        PageScaffold(title: "Salaris") {
            VStack(spacing: Theme.pageSpacing) {
                standardCard(d.salarySettings(in: store.now), hasChanges: !d.salaryChanges.isEmpty)
                WageHistoryCard()
                if d.usesCalendarHours {
                    SalaryHoursCard()
                }
                scheduleCard(d, today: store.today)
            }
            .frame(maxWidth: Theme.readableWidth)
        }
    }

    // MARK: Bindings

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

    /// Het loon van deze maand: lezen uit `salarySettings(in:)`, schrijven met `setWage` (een wijziging vanaf deze maand als er al
    /// salaris in het verleden is, anders het loon zelf).
    private func wage(_ keyPath: KeyPath<SalarySettings, Double>,
                      write: @escaping (inout FinanceData, YearMonth, Double) -> Void) -> Binding<Double> {
        Binding(get: { store.data.salarySettings(in: store.now)[keyPath: keyPath] },
                set: { value in
                    let current = store.now
                    store.mutate { write(&$0, current, value) }
                })
    }

    private var hourlyRateBinding: Binding<Double> {
        wage(\.hourlyRate) { data, current, value in data.setWage(current: current, hourlyRate: value) }
    }

    private var fixedBinding: Binding<Double> {
        wage(\.fixedMonthly) { data, current, value in data.setWage(current: current, fixedMonthly: value) }
    }

    private var hoursBinding: Binding<Double> {
        wage(\.hoursPerWeek) { data, current, value in data.setWage(current: current, hoursPerWeek: value) }
    }

    /// Kiest waar de uren vandaan komen. "Uren uit je agenda" vraagt zo nodig toegang en haalt de diensten meteen op.
    private func chooseHoursSource(_ source: HoursSource) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.mutate { $0.work.hoursSource = source }
        }
        guard source == .calendar, let workCalendar else { return }
        Task {
            if workCalendar.access == .notDetermined { await workCalendar.requestAccess() }
            await workCalendar.refresh(into: store, force: true)
        }
    }

    /// Schakelt het schema om (zie `SalaryScheduleEdit.change`).
    private func changeSchedule(to schedule: SalarySchedule) {
        let today = store.today
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.mutate { SalaryScheduleEdit.change(&$0, to: schedule, today: today) }
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
    private func standardCard(_ s: SalarySettings, hasChanges: Bool) -> some View {
        Card(title: "Standaard salaris", symbol: "eurosign.circle", domain: .money,
             subtitle: "Netto, zoals het op je rekening komt") {
            Picker("Soort", selection: salary(\.mode)) {
                ForEach(SalaryMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            amountFields(s)
            if hasChanges {
                MonthExplanation(text: WageText.currentMonthNote)
            }
            averageFigures(s)
        }
    }

    @ViewBuilder
    private func amountFields(_ s: SalarySettings) -> some View {
        switch s.mode {
        case .fixed:
            NumberRow(title: s.isMonthly ? "Per maand" : "Per uitbetaling", value: fixedBinding)
            if !s.isMonthly {
                MonthExplanation(text: "Vul in wat er bij elke uitbetaling op je rekening komt, niet wat je per maand krijgt.")
            }
        case .hourly:
            NumberRow(title: "Uurloon", value: hourlyRateBinding)
            hoursSourceChoices
            if store.data.work.hoursSource == .calendar {
                NumberRow(title: WorkText.averageHoursTitle, value: hoursBinding, unit: .plain("uur"))
                MonthExplanation(text: WorkText.averageHoursNote)
                NavigationRow(title: WorkText.pageTitle, symbol: WorkText.symbol, domain: .settings,
                              subtitle: WorkText.settingsSummary(store.data) + ", toeslagen en pauzes",
                              destination: .settings(.workHours))
                MonthExplanation(text: WorkText.formula)
            } else {
                NumberRow(title: "Uren per week", value: hoursBinding, unit: .plain("uur"))
                MonthExplanation(text: hourlyFormula(s))
            }
        }
    }

    /// Waar de uren van een uurloon vandaan komen (`work.hoursSource`). Geldt ook voor het verleden vanaf je startdatum.
    private var hoursSourceChoices: some View {
        let source = store.data.work.hoursSource
        return VStack(alignment: .leading, spacing: 8) {
            ChoiceRow(title: WorkText.manualHoursTitle, detail: "Elke week hetzelfde aantal uren.",
                      isSelected: source == .manual) { chooseHoursSource(.manual) }
            ChoiceRow(title: WorkText.sourceTitle, detail: "Uit je agenda \u{201C}\(store.data.work.calendarTitle)\u{201D}, met toeslagen en pauzes.",
                      isSelected: source == .calendar) { chooseHoursSource(.calendar) }
            if source == .calendar {
                MonthExplanation(text: WorkText.sourceFooter)
            }
        }
    }

    /// Bij een schema om de zoveel weken of dagen: wat een uitbetaling en een gemiddelde maand opleveren.
    @ViewBuilder
    private func averageFigures(_ s: SalarySettings) -> some View {
        if !s.isMonthly {
            FigureRow {
                if s.mode == .hourly {
                    StatTile(title: "Per uitbetaling", value: Fmt.euro(s.payoutAmount()))
                }
                StatTile(title: "Gemiddeld per maand", value: Fmt.euro(s.averageMonthlyAmount()), caption: "voor schattingen")
            }
            MonthExplanation(text: "Voor schattingen (toekomstschatting, aankoopcheck, noodbuffer en doelen) rekent de app met het gemiddelde per maand. Een echte maand telt precies de uitbetalingen die erin vallen.")
        }
    }

    // MARK: Schema

    @ViewBuilder
    private func scheduleCard(_ d: FinanceData, today: Date) -> some View {
        let s = d.salary
        Card(title: "Wanneer krijg je salaris?", symbol: "calendar.badge.clock", domain: .money,
             subtitle: SalaryScheduleText.capitalized(d.salaryScheduleSummary(asOf: today))) {
            scheduleChoices(s)
            scheduleDetails(s)
            upcomingText(d, today: today)
            MonthWarningLine(text: "Een wijziging aan je salaris of schema geldt vanaf deze maand. Eerdere maanden blijven zoals ze waren. Valt er in deze maand al een uitbetaling van het nieuwe schema voor vandaag, dan telt die wel mee.")
        }
    }

    private func scheduleChoices(_ s: SalarySettings) -> some View {
        VStack(spacing: 8) {
            ChoiceRow(title: "Maandelijks", detail: "Op een vaste dag van de maand, bijvoorbeeld de 25e.",
                      isSelected: s.schedule == .monthly) { changeSchedule(to: .monthly) }
            ChoiceRow(title: "Om de zoveel weken", detail: "Bijvoorbeeld elke week, om de 2 weken of om de 4 weken.",
                      isSelected: s.schedule == .weeks) { changeSchedule(to: .weeks) }
            ChoiceRow(title: "Om de zoveel dagen", detail: "Bijvoorbeeld elke 14 dagen of elke 30 dagen.",
                      isSelected: s.schedule == .days) { changeSchedule(to: .days) }
        }
    }

    @ViewBuilder
    private func scheduleDetails(_ s: SalarySettings) -> some View {
        switch s.schedule {
        case .monthly:
            DayPickerRow(title: "Dag van de maand", day: payDayBinding)
            MonthExplanation(text: "Op deze dag staat je salaris op je bankrekening. Extra inkomsten zonder eigen dag komen ook dan binnen, en de inleg voor je spaarpotten en beleggingen gaat standaard op deze dag. Is een maand korter, dan geldt de laatste dag van die maand.")
        case .weeks:
            IntStepperRow(title: "Elke", value: intervalBinding, range: 1...52,
                          unit: SalaryScheduleText.unit(schedule: s.schedule, interval: s.cycleInterval))
            anchorRows(s)
        case .days:
            IntStepperRow(title: "Elke", value: intervalBinding, range: 1...366,
                          unit: SalaryScheduleText.unit(schedule: s.schedule, interval: s.cycleInterval))
            anchorRows(s)
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

    @ViewBuilder
    private func upcomingText(_ d: FinanceData, today: Date) -> some View {
        let upcoming = upcomingPayDates(d, today: today)
        if !upcoming.isEmpty {
            MonthExplanation(text: "Volgende uitbetalingen: " + upcoming.map { payDateText($0, today: today) }.joined(separator: " · "))
        }
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
    private func anchorRows(_ s: SalarySettings) -> some View {
        DatePicker("Datum van een uitbetaling", selection: anchorBinding, displayedComponents: .date)
            .datePickerStyle(.compact)
            .environment(\.locale, Fmt.locale)
            .frame(minHeight: Theme.minTapTarget)
        MonthExplanation(text: "Kies een dag waarop je salaris binnenkwam of binnenkomt, ook al is dat lang geleden. Vanaf die dag telt de app \(s.cycleDescription) door, vooruit en terug. Daardoor vallen er in een maand soms 0, 1, 2 of meer uitbetalingen, gemiddeld \(Fmt.input(s.averagePayoutsPerYear, maxDigits: 1)) per jaar. Het maandtotaal is de som van de uitbetalingen. Extra inkomsten zonder eigen dag en de inleg voor je spaarpotten gaan standaard op de eerste uitbetaling van de maand.")
        Toggle("Dit is je eerste uitbetaling", isOn: salary(\.anchorIsFirst))
            .frame(minHeight: Theme.minTapTarget)
        MonthExplanation(text: "Aan: er telt niets mee van vóór deze datum, bijvoorbeeld bij een nieuwe baan. Uit: het schema loopt ook terug, zoals bij een salaris dat al langer loopt.")
        if let cycle = s.cycleDays, cycle > 28 {
            DayPickerRow(title: "Salarisdag zonder uitbetaling", day: payDayBinding)
            MonthExplanation(text: "Valt er in een maand geen uitbetaling, dan geldt deze dag als salarisdag voor extra inkomsten en inleg.")
        }
    }
}
