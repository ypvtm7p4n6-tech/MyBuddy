import SwiftUI

// Loon wijzigen: de pagina waar je kiest vanaf welke maand je uurloon of salaris anders is (docs/work/plan2.md par. 4.6). Je komt er via
// de kaart "Loon per maand" op Salaris (`Destination.wageChange(maand)`, onder Inkomen en Salaris); het is een pagina, geen blad. Het
// loon van een uitbetaling is dat van de maand waarin het op je rekening komt (`FinanceData.salarySettings(forPayoutOn:)`); de logica
// van het formulier staat in `WageEdit` en de teksten in `WageText` (App/UI/WageText.swift). Bewaren verandert meteen Inkomen,
// Verdelen, Dag voor dag, Home, de schattingen, de Aankoopcheck en de doelen: die lezen allemaal `salarySettings(in:)`.

struct WageChangePage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// De maand waarmee de pagina opende (een bestaande wijziging verhuist als je een andere maand kiest).
    private let openedMonth: YearMonth
    @State private var month: YearMonth
    @State private var hourlyRate = 0.0
    @State private var fixedAmount = 0.0
    @State private var hoursPerWeek = 0.0
    @State private var loadedFor: YearMonth?
    @State private var confirmDelete = false

    init(month: YearMonth) {
        openedMonth = month
        _month = State(initialValue: month)
    }

    private var data: FinanceData { store.data }
    private var salary: SalarySettings { data.salary }
    private var openedExisting: Bool { data.salaryChange(startingIn: openedMonth) != nil }

    private var change: SalaryChange {
        WageEdit.change(data, month: month, hourlyRate: hourlyRate, fixedMonthly: fixedAmount, hoursPerWeek: hoursPerWeek)
    }

    var body: some View {
        PageScaffold(title: WageText.pageTitle) {
            VStack(spacing: Theme.pageSpacing) {
                monthCard
                valuesCard
                buttons
            }
            .frame(maxWidth: Theme.readableWidth)
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: month) { _, _ in load() }
    }

    // MARK: Vanaf welke maand?

    private var monthCard: some View {
        Card(title: "Vanaf welke maand?", symbol: "calendar", domain: .money) {
            Picker("Vanaf", selection: $month) {
                ForEach(WageEdit.monthChoices(data, current: store.now, including: month), id: \.self) { m in
                    Text(Fmt.month(m)).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Theme.minTapTarget)
            if month < store.now {
                MonthWarningLine(text: WageText.pastMonthWarning)
            }
            MonthExplanation(text: WageText.footer)
        }
    }

    // MARK: Nieuw loon

    @ViewBuilder
    private var valuesCard: some View {
        Card(title: "Nieuw loon", symbol: "eurosign.circle", domain: .money, subtitle: "Netto, zoals het op je rekening komt") {
            switch salary.mode {
            case .hourly:
                NumberRow(title: "Uurloon", value: $hourlyRate)
                NumberRow(title: data.usesCalendarHours ? WorkText.averageHoursTitle : "Uren per week",
                          value: $hoursPerWeek, unit: .plain("uur"))
            case .fixed:
                NumberRow(title: salary.isMonthly ? "Per maand" : "Per uitbetaling", value: $fixedAmount)
                NumberRow(title: "Uren per week", value: $hoursPerWeek, unit: .plain("uur"))
                MonthExplanation(text: "De uren per week gebruikt de Aankoopcheck om je uurloon uit te rekenen.")
            }
            effect
        }
    }

    @ViewBuilder
    private var effect: some View {
        if data.usesCalendarHours {
            MonthExplanation(text: WageText.calendarNote)
        } else {
            let preview = WageEdit.payoutPreview(data, month: month, change: change)
            if let note = WageText.effectNote(old: preview.old, new: preview.new, isMonthly: salary.isMonthly) {
                MonthExplanation(text: note)
            } else if change.isEmpty {
                MonthExplanation(text: "Dit is hetzelfde loon als in \(Fmt.month(month.adding(-1))). Verander een bedrag om een wijziging te bewaren.")
            }
        }
    }

    // MARK: Knoppen

    private var buttons: some View {
        VStack(spacing: 12) {
            ActionButton(title: "Bewaar", symbol: "checkmark", prominent: true, action: save)
                .disabled(change.isEmpty)
            if data.salaryChange(startingIn: month) != nil {
                ActionButton(title: "Verwijder deze wijziging", symbol: "trash", role: .destructive) { confirmDelete = true }
                    .confirmationDialog("Wijziging verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Verwijder", role: .destructive, action: delete)
                        Button("Annuleer", role: .cancel) {}
                    } message: {
                        Text(WageText.deleteMessage(month: month))
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let new = change
        guard !new.isEmpty else { return }
        let moved = openedExisting && month != openedMonth
        let original = openedMonth
        store.mutate { data in
            if moved { data.removeSalaryChange(from: original) }
            data.setSalaryChange(new)
        }
        dismiss()
    }

    private func delete() {
        let target = month
        store.mutate { $0.removeSalaryChange(from: target) }
        dismiss()
    }

    // MARK: Laden

    private func loadIfNeeded() {
        if loadedFor != month { load() }
    }

    /// De velden beginnen bij het loon dat in de gekozen maand geldt (met een bestaande wijziging van die maand erin).
    private func load() {
        let start = WageEdit.start(data, month: month)
        hourlyRate = start.hourlyRate
        fixedAmount = start.fixedMonthly
        hoursPerWeek = start.hoursPerWeek
        loadedFor = month
    }
}
