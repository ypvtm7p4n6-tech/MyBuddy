import SwiftUI

// De secties van de pagina Werkuren die over de regels gaan: toeslagen, pauzes, feestdagen en het voorbeeld van de volgende twee
// uitbetalingen (docs/work/plan.md par. 4.4, punt 5 tot en met 8). Elke wijziging gaat via `store.mutate` naar `work.rules`; de
// rekenmotor rekent daarna alles opnieuw (`DerivedWork` wordt gewist zodra `work` verandert).

// MARK: - Toeslagen

struct WorkPayRulesSection: View {
    @Environment(AppStore.self) private var store

    private var rules: [PayRule] { store.data.work.rules.payRules }

    var body: some View {
        Section {
            ForEach(rules) { rule in
                WorkPayRuleRow(rule: rule, onChange: { updated in update(updated) })
            }
            .onDelete { offsets in
                store.mutate { $0.work.rules.payRules.remove(atOffsets: offsets) }
            }
            addMenu
            Picker(WorkText.combineTitle, selection: combineBinding) {
                ForEach(PayCombine.allCases) { Text(WorkText.combineTitle($0)).tag($0) }
            }
            .frame(minHeight: Theme.minTapTarget)
        } header: {
            SectionHeader(WorkText.rulesTitle)
        } footer: {
            SettingsFootnote("Een toeslag vermenigvuldigt het uurloon voor de uren op die dag: × 1,5 is anderhalf keer je uurloon. Veeg naar links om een toeslag te verwijderen.")
        }
    }

    private var combineBinding: Binding<PayCombine> {
        Binding(get: { store.data.work.rules.combine },
                set: { value in store.mutate { $0.work.rules.combine = value } })
    }

    private func update(_ rule: PayRule) {
        store.mutate { data in
            guard let index = data.work.rules.payRules.firstIndex(where: { $0.id == rule.id }) else { return }
            data.work.rules.payRules[index] = rule
        }
    }

    private func add(_ kind: PayRuleKind) {
        store.mutate { $0.work.rules.payRules.append(PayRule(kind: kind, factor: 1.5)) }
    }

    private var hasHolidayRule: Bool {
        rules.contains { if case .holiday = $0.kind { return true } else { return false } }
    }

    private func hasWeekday(_ weekday: Int) -> Bool {
        rules.contains { if case .weekday(let n) = $0.kind { return n == weekday } else { return false } }
    }

    private var addMenu: some View {
        Menu {
            Menu(WorkText.addWeekdayTitle) {
                // Maandag eerst, zoals een Nederlandse agenda.
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                    Button(WorkText.weekdayTitle(weekday)) { add(.weekday(weekday)) }
                        .disabled(hasWeekday(weekday))
                }
            }
            Button(WorkText.addHolidayRuleTitle) { add(.holiday) }
                .disabled(hasHolidayRule)
            Button(WorkText.addDateTitle) { add(.date(CalendarDay(date: store.today))) }
        } label: {
            Label(WorkText.addRuleTitle, systemImage: "plus.circle")
                .frame(minHeight: Theme.minTapTarget)
        }
    }
}

/// Eén toeslag: aan of uit, de factor en bij een eigen datum de dag.
private struct WorkPayRuleRow: View {
    let rule: PayRule
    let onChange: (PayRule) -> Void

    private var enabled: Binding<Bool> {
        Binding(get: { rule.isEnabled }, set: { var r = rule; r.isEnabled = $0; onChange(r) })
    }

    private var factor: Binding<Double> {
        Binding(get: { rule.factor }, set: { var r = rule; r.factor = min(max($0, 0), 10); onChange(r) })
    }

    private var day: Binding<Date> {
        Binding(get: {
            if case .date(let d) = rule.kind { return d.date() }
            return Date()
        }, set: { var r = rule; r.kind = .date(CalendarDay(date: $0)); onChange(r) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(WorkText.ruleTitle(rule), isOn: enabled)
                .frame(minHeight: Theme.minTapTarget)
            if case .date = rule.kind {
                DatePicker("Datum", selection: day, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .environment(\.locale, Fmt.locale)
                    .frame(minHeight: Theme.minTapTarget)
            }
            NumberRow(title: WorkText.factorTitle, value: factor, unit: .plain("×"), range: 0...10)
                .disabled(!rule.isEnabled)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WorkText.ruleLine(rule))
    }
}

// MARK: - Pauzes

struct WorkBreakRulesSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Section {
            ForEach(store.data.work.rules.breakRules) { rule in
                WorkBreakRuleRow(rule: rule, onChange: { updated in update(updated) })
            }
            .onDelete { offsets in
                store.mutate { $0.work.rules.breakRules.remove(atOffsets: offsets) }
            }
            Button {
                let longest = store.data.work.rules.breakRules.map(\.fromHours).max() ?? 4
                store.mutate { $0.work.rules.breakRules.append(BreakRule(fromHours: min(longest + 2, 24), minutes: 30)) }
            } label: {
                Label(WorkText.addBreakTitle, systemImage: "plus.circle")
                    .frame(minHeight: Theme.minTapTarget)
            }
        } header: {
            SectionHeader(WorkText.breaksTitle)
        } footer: {
            SettingsFootnote(WorkText.breakFooter + " Bij een dienst geldt de regel met de langste drempel die de dienst haalt.")
        }
    }

    private func update(_ rule: BreakRule) {
        store.mutate { data in
            guard let index = data.work.rules.breakRules.firstIndex(where: { $0.id == rule.id }) else { return }
            data.work.rules.breakRules[index] = rule
        }
    }
}

private struct WorkBreakRuleRow: View {
    let rule: BreakRule
    let onChange: (BreakRule) -> Void

    private var from: Binding<Double> {
        Binding(get: { rule.fromHours }, set: { var r = rule; r.fromHours = min(max($0, 0), 24); onChange(r) })
    }

    private var minutes: Binding<Int> {
        Binding(get: { rule.minutes }, set: { var r = rule; r.minutes = min(max($0, 0), 240); onChange(r) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NumberRow(title: WorkText.breakFromTitle, value: from, unit: .plain("uur"), maxDigits: 2, range: 0...24)
            IntStepperRow(title: WorkText.breakMinutesTitle, value: minutes, range: 0...240, unit: "min")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WorkText.breakTitle(rule))
    }
}

// MARK: - Feestdagen

struct WorkHolidaysSection: View {
    @Environment(AppStore.self) private var store

    private var holidays: HolidaySettings { store.data.work.rules.holidays }

    var body: some View {
        Section {
            ForEach(HolidayKind.calendarOrder) { kind in
                Toggle(kind.title, isOn: binding(kind))
                    .frame(minHeight: Theme.minTapTarget)
            }
            ForEach(Array(holidays.custom.enumerated()), id: \.offset) { index, day in
                DatePicker("Eigen feestdag", selection: customBinding(index, day), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .environment(\.locale, Fmt.locale)
                    .frame(minHeight: Theme.minTapTarget)
            }
            .onDelete { offsets in
                store.mutate { $0.work.rules.holidays.custom.remove(atOffsets: offsets) }
            }
            Button {
                store.mutate { $0.work.rules.holidays.custom.append(CalendarDay(date: store.today)) }
            } label: {
                Label(WorkText.addHolidayTitle, systemImage: "plus.circle")
                    .frame(minHeight: Theme.minTapTarget)
            }
        } header: {
            SectionHeader(WorkText.holidaysTitle)
        } footer: {
            SettingsFootnote([WorkText.nextHolidaysText(holidays, from: CalendarDay(date: store.today)), WorkText.holidaysFooter,
                              "Een feestdag telt alleen als er een toeslag \u{201C}Feestdag\u{201D} aanstaat."]
                .compactMap { $0 }.joined(separator: " "))
        }
    }

    private func binding(_ kind: HolidayKind) -> Binding<Bool> {
        Binding(get: { store.data.work.rules.holidays.enabled.contains(kind) },
                set: { on in
                    store.mutate { data in
                        if on { data.work.rules.holidays.enabled.insert(kind) } else { data.work.rules.holidays.enabled.remove(kind) }
                    }
                })
    }

    private func customBinding(_ index: Int, _ day: CalendarDay) -> Binding<Date> {
        Binding(get: { day.date() },
                set: { date in
                    store.mutate { data in
                        guard data.work.rules.holidays.custom.indices.contains(index) else { return }
                        data.work.rules.holidays.custom[index] = CalendarDay(date: date)
                    }
                })
    }
}

// MARK: - Voorbeeld

/// De volgende twee uitbetalingen zoals de rekenmotor ze nu uitrekent: datum, periode, uren, toeslagen, pauze en bedrag.
struct WorkPayoutPreviewSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let today = store.today
        let days = d.upcomingPayoutDays(count: 2, after: today)
        Section {
            if days.isEmpty {
                MonthExplanation(text: "Er staat nog geen uitbetaling gepland.")
            }
            ForEach(days, id: \.self) { day in
                if let report = d.workReport(forPayoutOn: day, asOf: today) {
                    WorkPayoutBlock(day: day, report: report, rules: d.work.rules)
                }
            }
        } header: {
            SectionHeader(WorkText.previewTitle)
        } footer: {
            SettingsFootnote("Gewerkt: diensten tot nu. Gepland: diensten die nog komen. Verwacht: wat je agenda nog niet kent, uit je gemiddelde uren per week bij Salaris.")
        }
    }
}

/// Eén uitbetaling met haar uitleg (ook gebruikt op Salaris, `SalaryHoursCard`).
struct WorkPayoutBlock: View {
    let day: CalendarDay
    let report: WorkHoursReport
    let rules: WorkRules

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Uitbetaling \(Fmt.longDayMonth(day))")
                    .font(.body.weight(.semibold))
                Text("Uren van \(WorkText.periodText(report.period))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(WorkText.breakdown(report, rules: rules)) { line in
                AmountRow(title: line.title, value: line.value, detail: line.note, bold: line.id == "amount")
            }
            if report.isAllExpected {
                MonthExplanation(text: WorkText.nothingInCalendarNote)
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
// MARK: - Previews

/// Voorbeelddata met uurloon en uren uit de agenda "werken", een vaste demo-agenda en een router.
@MainActor
struct WorkHoursPreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    @State private var calendar: WorkCalendarController
    private let content: Content

    init(access: CalendarAccess = .granted, calendarHours: Bool = true, calendarTitle: String = "werken",
         @ViewBuilder content: () -> Content) {
        let sample = AppStore(storage: nil)
        sample.loadSampleData()
        sample.mutate { data in
            data.salary.mode = .hourly
            data.work.hoursSource = calendarHours ? .calendar : .manual
            data.work.calendarTitle = calendarTitle
        }
        _store = State(initialValue: sample)
        _calendar = State(initialValue: WorkCalendarController(source: DemoWorkCalendar(state: access)))
        self.content = content()
    }

    var body: some View {
        NavigationStack { content }
            .environment(store)
            .environment(router)
            .environment(calendar)
            .task {
                await calendar.prepare()
                await calendar.refresh(into: store, force: true)
            }
    }
}

#Preview("Werkuren") {
    WorkHoursPreviewHost { WorkHoursPage() }
}

#Preview("Werkuren, donker") {
    WorkHoursPreviewHost { WorkHoursPage() }
        .preferredColorScheme(.dark)
}

#Preview("Werkuren, grote tekst") {
    WorkHoursPreviewHost { WorkHoursPage() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Werkuren, geen toegang") {
    WorkHoursPreviewHost(access: .denied) { WorkHoursPage() }
}

#Preview("Werkuren, geen agenda") {
    WorkHoursPreviewHost(calendarTitle: "dienst") { WorkHoursPage() }
}

#Preview("Werkuren, handmatig") {
    WorkHoursPreviewHost(calendarHours: false) { WorkHoursPage() }
}
#endif
