import SwiftUI

// De uitgaven van de gekozen maand: een samenvatting, de vaste en de variabele uitgaven. Een regel toevoegen doe je met de
// plus in de werkbalk; "Standaard uitgaven invullen" staat in het menu en in de lege staat. De logica zonder SwiftUI staat in
// App/UI/SavingsDisplay.swift en App/Core/Expenses.swift.

struct ExpensesPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: MoneyLineSheetRequest?
    /// Wat "Standaard uitgaven invullen" deed, tot je een andere maand kiest.
    @State private var fillMessage: String?
    /// Loopt op bij elke keer invullen en geeft de bevestigende haptiek.
    @State private var fillCount = 0

    var body: some View {
        let month = router.focusMonth
        let d = store.data
        let beforeStart = month < d.startMonth
        let hasLines = !beforeStart && !d.plan(for: month).expenses.isEmpty
        let missing = beforeStart ? 0 : d.missingStandardExpenses(in: month).count
        ListScaffold(title: "Uitgaven") {
            Section {
                MonthBar()
                    .bankBareRow()
            }
            ExpensesSummarySection(month: month, message: fillMessage)
            lineSections(month: month, beforeStart: beforeStart, hasLines: hasLines)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                IconButton("Uitgave toevoegen", symbol: "plus") { openAdd(month, kind: .fixed) }
                    .disabled(beforeStart)
                if missing > 0 {
                    Menu {
                        Button { fillStandard(month) } label: {
                            Label("Standaard uitgaven invullen", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Label("Meer", systemImage: "ellipsis")
                    }
                    .help("Meer")
                }
            }
        }
        .sheet(item: $sheet) { request in
            MoneyLineSheet(line: request.line, kind: request.kind, month: request.month,
                           defaultExpenseKind: request.defaultExpenseKind)
        }
        .sensoryFeedback(.success, trigger: fillCount)
        .onChange(of: month) { _, _ in
            fillMessage = nil
        }
    }

    /// De twee lijsten met uitgaven, een uitleg voor een maand vóór de startmaand, of de lege staat.
    @ViewBuilder
    private func lineSections(month: YearMonth, beforeStart: Bool, hasLines: Bool) -> some View {
        if beforeStart {
            Section {
                MonthExplanation(text: StartDateText.beforeStartNote(store.data, .fillIn))
            }
        } else if hasLines {
            MoneyLinesSection(kind: .expense, expenseKind: .fixed, month: month,
                              onAdd: { openAdd(month, kind: .fixed) },
                              onEdit: { line in openEdit(line, month: month) })
            MoneyLinesSection(kind: .expense, expenseKind: .variable, month: month,
                              onAdd: { openAdd(month, kind: .variable) },
                              onEdit: { line in openEdit(line, month: month) })
        } else {
            Section {
                EmptyHint(symbol: "creditcard", title: "Nog geen uitgaven",
                          message: "Vul de gangbare posten in met een richtbedrag, of voeg zelf een uitgave toe.",
                          actionTitle: "Standaard uitgaven invullen", action: { fillStandard(month) })
            } header: {
                SectionHeader("Uitgaven", symbol: "creditcard", domain: .money)
            }
        }
    }

    private func openAdd(_ month: YearMonth, kind: ExpenseKind) {
        sheet = MoneyLineSheetRequest(line: nil, kind: .expense, month: month, defaultExpenseKind: kind)
    }

    private func openEdit(_ line: MoneyLine, month: YearMonth) {
        sheet = MoneyLineSheetRequest(line: line, kind: .expense, month: month, defaultExpenseKind: line.kind)
    }

    /// Vult de gangbare posten in met een richtbedrag, als terugkerende regel. Bestaande regels blijven staan.
    private func fillStandard(_ month: YearMonth) {
        let added = store.data.missingStandardExpenses(in: month).count
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.mutate { $0.fillStandardExpenses(in: month) }
        }
        fillCount += 1
        if added == 0 {
            fillMessage = "Alle standaardposten staan al in deze maand."
        } else {
            fillMessage = "\(added) standaardposten ingevuld met een richtbedrag. Ze komen elke maand terug; pas ze aan naar jouw situatie."
        }
    }
}

// MARK: - Samenvatting

/// De uitgaven van de maand, verdeeld in Vast en Variabel, met wat uit spaarpotten komt. Alle bedragen komen uit
/// `expenseOverview(in:)`: hetzelfde als in het Maandoverzicht en bij Nog te verdelen.
private struct ExpensesSummarySection: View {
    let month: YearMonth
    let message: String?
    @Environment(AppStore.self) private var store

    var body: some View {
        let o = store.data.expenseOverview(in: month)
        let closes = DisplayRounding.closes(parts: [CentsMath.int(o.fixed), CentsMath.int(o.variable)],
                                            total: CentsMath.int(o.expenses))
        Section {
            MonthFigureHero(title: "Uitgaven in \(Fmt.month(month))", value: o.expenses)
            AmountRow(title: "Vast", value: Fmt.euro(o.fixed))
            AmountRow(title: "Variabel", value: Fmt.euro(o.variable))
            if o.fromPots > 0 {
                AmountRow(title: "Waarvan uit spaarpotten", value: Fmt.euro(o.fromPots),
                          detail: "Dat telt niet mee in Nog te verdelen.")
            }
            if !closes {
                RoundingNote()
            }
            if let message {
                MonthExplanation(text: message)
            }
            if let note = StartDateText.partialMonthNote(store.data, month: month) {
                MonthExplanation(text: note)
            }
        } header: {
            SectionHeader("Samenvatting", symbol: "creditcard", domain: .money)
        }
    }
}
