import SwiftUI
#if os(iOS)
import UIKit
#endif

// De pagina Werkuren (`.settings(.workHours)`): de uren van je salaris uit je agenda (standaard "werken"), met toeslagen, pauzes en
// feestdagen (docs/work/plan.md par. 4.4). Een lijstpagina, geen bladen. De rekenregels staan in de rekenmotor (`WorkHours`,
// `WorkRules`, `WorkCalendar`), de teksten in `WorkText` (App/UI/WorkDisplay.swift) en het lezen van de agenda in
// `WorkCalendarController` (App/Calendar). Wat je hier verandert, geldt meteen voor Salaris, Inkomen, Verdelen, Dag voor dag en Home:
// die lezen allemaal `FinanceData.workPayoutCents(on:)`.

struct WorkHoursPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(WorkCalendarController.self) private var calendar: WorkCalendarController?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirmFreeze = false
    @State private var notice: String?
    @State private var successCount = 0

    private var work: WorkSettings { store.data.work }
    private var access: CalendarAccess { calendar?.access ?? .notDetermined }
    private var isHourly: Bool { store.data.salary.mode == .hourly }
    private var usesCalendar: Bool { work.hoursSource == .calendar }

    var body: some View {
        ListScaffold(title: WorkText.pageTitle) {
            if let notice {
                SettingsNotice(text: notice, symbol: "checkmark.circle.fill")
            }
            problemNotice
            sourceSection
            if usesCalendar && isHourly {
                calendarSection
                periodSection
                WorkPayRulesSection()
                WorkBreakRulesSection()
                WorkHolidaysSection()
                WorkPayoutPreviewSection()
            }
            managementSection
        }
        .sensoryFeedback(.success, trigger: successCount)
        .task { await calendar?.prepare() }
    }

    // MARK: Bindings

    private func setting<T>(_ keyPath: WritableKeyPath<WorkSettings, T>) -> Binding<T> {
        Binding(get: { store.data.work[keyPath: keyPath] },
                set: { value in store.mutate { $0.work[keyPath: keyPath] = value } })
    }

    /// Aanzetten vraagt zo nodig om toegang (de systeemvraag, na deze tik) en haalt meteen de diensten op.
    private var sourceBinding: Binding<Bool> {
        Binding(get: { store.data.work.hoursSource == .calendar },
                set: { on in
                    withAnimation(reduceMotion ? nil : Theme.motion) {
                        store.mutate { $0.work.hoursSource = on ? .calendar : .manual }
                    }
                    if on { Task { await connectAndRefresh() } }
                })
    }

    private var calendarTitleBinding: Binding<String> {
        Binding(get: { store.data.work.calendarTitle },
                set: { title in
                    store.mutate { $0.work.calendarTitle = title }
                    Task { await calendar?.refresh(into: store, force: true) }
                })
    }

    private var allDayBinding: Binding<Bool> {
        Binding(get: { store.data.work.allDayShiftHours != nil },
                set: { on in
                    store.mutate { $0.work.allDayShiftHours = on ? 8 : nil }
                    Task { await calendar?.refresh(into: store, force: true) }
                })
    }

    private var allDayHoursBinding: Binding<Int> {
        Binding(get: { Int((store.data.work.allDayShiftHours ?? 8).rounded()) },
                set: { hours in
                    store.mutate { $0.work.allDayShiftHours = Double(min(max(hours, 1), 16)) }
                    Task { await calendar?.refresh(into: store, force: true) }
                })
    }

    private func connectAndRefresh() async {
        guard let calendar else { return }
        if calendar.access == .notDetermined { await calendar.requestAccess() }
        await calendar.refresh(into: store, force: true)
    }

    // MARK: Melding

    /// Een melding alleen bij een probleem; de rest van de pagina blijft bruikbaar.
    @ViewBuilder
    private var problemNotice: some View {
        if usesCalendar && isHourly {
            let text = WorkText.accessText(access)
            if let action = text.action {
                SettingsNotice(text: "\(text.title). \(text.message)", symbol: "calendar.badge.exclamationmark",
                               actionTitle: action.title) { perform(action) }
            } else if let error = calendar?.lastError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle.fill", actionTitle: WorkText.refreshTitle) {
                    Task { await calendar?.refresh(into: store, force: true) }
                }
            } else if matched.isEmpty, calendar != nil {
                SettingsNotice(text: WorkText.matchedText([], title: work.calendarTitle) + " Maak in je agenda-app een agenda met die naam, of kies hieronder een andere.",
                               symbol: "calendar.badge.exclamationmark")
            }
        }
    }

    private func perform(_ action: WorkAccessAction) {
        switch action {
        case .requestAccess:
            Task { await connectAndRefresh() }
        case .openSettings:
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            #else
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { openURL(url) }
            #endif
        }
    }

    // MARK: Urenbron

    @ViewBuilder
    private var sourceSection: some View {
        Section {
            Toggle(WorkText.sourceTitle, isOn: sourceBinding)
                .disabled(!isHourly)
                .frame(minHeight: Theme.minTapTarget)
            if !isHourly {
                MonthExplanation(text: WorkText.fixedSalaryNote)
                salaryLink
            } else if !usesCalendar {
                MonthExplanation(text: "Nu rekent je salaris met de uren per week die je bij Salaris invult. Zet dit aan om de uren uit je agenda te halen, met toeslagen en pauzes.")
                salaryLink
            }
        } footer: {
            SettingsFootnote(WorkText.sourceFooter)
        }
    }

    /// Naar Salaris: op de iPhone en iPad op dezelfde stapel, op de Mac in het hoofdvenster.
    private var salaryLink: some View {
        Button {
            #if os(macOS)
            router.go(.salary)
            #else
            router.open(.salary)
            #endif
        } label: {
            SettingsActionLabel(title: "Naar Salaris",
                                detail: isHourly ? "Uurloon en uren per week" : "Kies daar Uurloon om uren uit je agenda te gebruiken",
                                symbol: "eurosign.circle")
        }
        .accessibilityAddTraits(.isLink)
    }

    // MARK: Agenda

    /// De agenda's met de gekozen naam (hoofdletters en accenten tellen niet).
    private var matched: [CalendarInfo] {
        let list = calendar?.calendars ?? []
        if list.isEmpty, let fetch = calendar?.lastFetch { return fetch.matched }
        return list.filter { CalendarTitle.matches($0.title, work.calendarTitle) }
    }

    /// De namen in de kiezer: elke agenda één keer, plus de gekozen naam als die (nog) niet bestaat.
    private var calendarTitles: [String] {
        var titles: [String] = []
        for info in calendar?.calendars ?? [] where !titles.contains(where: { CalendarTitle.matches($0, info.title) }) {
            titles.append(info.title)
        }
        if !titles.contains(where: { CalendarTitle.matches($0, work.calendarTitle) }) { titles.insert(work.calendarTitle, at: 0) }
        return titles
    }

    /// De kiezer bewaart de naam zoals de agenda hem schrijft; een opgeslagen "Werken" kiest de agenda "werken".
    private var pickerSelection: Binding<String> {
        Binding(get: { calendarTitles.first { CalendarTitle.matches($0, store.data.work.calendarTitle) } ?? store.data.work.calendarTitle },
                set: { calendarTitleBinding.wrappedValue = $0 })
    }

    @ViewBuilder
    private var calendarSection: some View {
        Section {
            Picker(WorkText.calendarTitle, selection: pickerSelection) {
                ForEach(calendarTitles, id: \.self) { Text($0).tag($0) }
            }
            .frame(minHeight: Theme.minTapTarget)
            if access.canRead {
                MonthExplanation(text: WorkText.matchedText(matched, title: work.calendarTitle))
            }
            Toggle(WorkText.allDayTitle, isOn: allDayBinding)
                .frame(minHeight: Theme.minTapTarget)
            if work.allDayShiftHours != nil {
                IntStepperRow(title: WorkText.allDayHoursTitle, value: allDayHoursBinding, range: 1...16, unit: "uur")
            }
            Text(WorkText.lastRefreshText(work.snapshot, refreshedAt: calendar?.refreshedAt, today: store.today))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if let fetch = calendar?.lastFetch, let skipped = WorkText.skippedText(fetch) {
                MonthExplanation(text: "Overgeslagen: \(skipped).")
            }
            if calendar?.isRefreshing == true {
                SettingsProgressRow(text: "Bezig met de agenda lezen…")
            }
            ActionButton(title: WorkText.refreshTitle, symbol: "arrow.clockwise") {
                Task { await calendar?.refresh(into: store, force: true) }
            }
            .disabled(!access.canRead || calendar?.isRefreshing == true)
            .listRowBackground(Color.clear)
        } header: {
            SectionHeader(WorkText.calendarTitle)
        } footer: {
            SettingsFootnote("Alle afspraken in deze agenda tellen als diensten, behalve afgewezen en geannuleerde afspraken en afspraken van meer dan \(WorkCalendarRules.maxShiftHours) uur.")
        }
    }

    // MARK: Periode

    @ViewBuilder
    private var periodSection: some View {
        let d = store.data
        Section {
            Picker(WorkText.periodTitle, selection: setting(\.periodBasis)) {
                ForEach(HoursPeriodBasis.allCases) { Text(WorkText.periodBasisTitle($0)).tag($0) }
            }
            .frame(minHeight: Theme.minTapTarget)
            if let next = d.upcomingPayoutDays(count: 1, after: store.today).first {
                let range = WorkPeriods.period(forPayoutOn: next, salary: d.salarySettings(forPayoutOn: next), basis: work.periodBasis)
                MonthExplanation(text: "De uitbetaling van \(Fmt.longDayMonth(next)) rekent met de uren van \(WorkText.periodText(range)).")
            }
        } header: {
            SectionHeader("Periode")
        } footer: {
            SettingsFootnote("Deze periode: de uren tot je salarisdag. De vorige periode: de uren van de periode daarvoor, zoals veel werkgevers een maand later uitbetalen.")
        }
    }

    // MARK: Beheer

    @ViewBuilder
    private var managementSection: some View {
        let d = store.data
        let average = d.averageAgendaHoursPerWeek(asOf: store.today)
        Section {
            if isHourly && usesCalendar {
                Button {
                    guard let average else { return }
                    let hours = (average * 10).rounded() / 10
                    store.mutate { $0.setWage(current: store.now, hoursPerWeek: hours) }
                    show("Gemiddeld \(Fmt.input(hours)) uur per week ingevuld bij Salaris.")
                } label: {
                    SettingsActionLabel(title: WorkText.fillAverageTitle,
                                        detail: average.map { "Je agenda: gemiddeld \(Fmt.input(($0 * 10).rounded() / 10)) uur per week over de laatste 12 weken. Voor schattingen en voor wat nog niet in je agenda staat." }
                                            ?? "Nog geen volle weken met diensten in je agenda.",
                                        symbol: "chart.bar")
                }
                .disabled(average == nil)
            }
            Button {
                confirmFreeze = true
            } label: {
                SettingsActionLabel(title: WorkText.freezeTitle,
                                    detail: "Het salaris van de maanden vóór \(Fmt.month(store.now)) blijft vast staan.",
                                    symbol: "lock")
            }
            .confirmationDialog(WorkText.freezeTitle, isPresented: $confirmFreeze, titleVisibility: .visible) {
                Button("Leg vast") {
                    store.mutate { $0.freezeSalaryHistory(before: store.now) }
                    show("Het salaris van eerdere maanden staat vast.")
                }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text(WorkText.freezeMessage)
            }
        } header: {
            SectionHeader(WorkText.managementTitle)
        } footer: {
            SettingsFootnote(WorkText.privacyFooter)
        }
    }

    private func show(_ text: String) {
        notice = text
        successCount += 1
    }
}
