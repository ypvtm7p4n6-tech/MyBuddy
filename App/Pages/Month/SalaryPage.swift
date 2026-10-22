import SwiftUI

// Het salaris instellen: het standaard salaris (vast of uurloon) en wanneer je het krijgt (het schema). Een rekenpagina met
// kaarten: de invoer is een formulier en geen lijst met rijen. Een wijziging geldt vanaf de lopende maand; eerdere maanden
// blijven zoals ze waren (`SalaryScheduleEdit`, App/UI/SavingsDisplay.swift).

struct SalaryPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = store.data
        PageScaffold(title: "Salaris") {
            VStack(spacing: Theme.pageSpacing) {
                standardCard(d.salary)
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
    private func standardCard(_ s: SalarySettings) -> some View {
        Card(title: "Standaard salaris", symbol: "eurosign.circle", domain: .money,
             subtitle: "Netto, zoals het op je rekening komt") {
            Picker("Soort", selection: salary(\.mode)) {
                ForEach(SalaryMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            amountFields(s)
            averageFigures(s)
        }
    }

    @ViewBuilder
    private func amountFields(_ s: SalarySettings) -> some View {
        switch s.mode {
        case .fixed:
            NumberRow(title: s.isMonthly ? "Per maand" : "Per uitbetaling", value: salary(\.fixedMonthly))
            if !s.isMonthly {
                MonthExplanation(text: "Vul in wat er bij elke uitbetaling op je rekening komt, niet wat je per maand krijgt.")
            }
        case .hourly:
            NumberRow(title: "Uurloon", value: salary(\.hourlyRate))
            NumberRow(title: "Uren per week", value: salary(\.hoursPerWeek), unit: .plain("uur"))
            MonthExplanation(text: hourlyFormula(s))
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
