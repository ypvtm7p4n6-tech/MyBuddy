import SwiftUI

// Regels van een maand (overige inkomsten en uitgaven) als rijen in een `List`: tikken bewerkt, swipen en het contextmenu
// geven Bewerken en Verwijderen. De logica zonder SwiftUI staat in App/UI/SavingsDisplay.swift, zodat de tests in CoreTests
// haar meedraaien.
//
// Een terugkerende regel komt elke maand terug op zijn eigen dag, ook in maanden die nog komen. Bij bewerken en verwijderen
// kies je of het alleen voor deze maand geldt of ook voor de maanden erna.

// MARK: - Het verzoek om het blad te tonen

/// Het verzoek om het blad voor een regel te tonen: een nieuwe regel (`line == nil`) of een bestaande bewerken. De pagina houdt
/// het in een `@State` en toont `MoneyLineSheet` met `.sheet(item:)`: een blad dat bij de pagina hoort blijft staan als een
/// rij verhuist (bijvoorbeeld van Vast naar Variabel).
struct MoneyLineSheetRequest: Identifiable {
    let id = UUID()
    let line: MoneyLine?
    let kind: FinanceData.LineKind
    let month: YearMonth
    let defaultExpenseKind: ExpenseKind
}

// MARK: - De inhoud van een rij

/// Eén regel in de lijst: naam, dag van de maand, of hij terugkeert, eventueel de spaarpot(ten) waar het uit komt, en het
/// bedrag. Bij grote tekst staat het bedrag onder de naam. Eén element voor VoiceOver.
struct MoneyLineRowLabel: View {
    let line: MoneyLine
    let kind: FinanceData.LineKind
    let month: YearMonth

    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

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
        let info: SeriesInfo? = line.isRecurring ? d.seriesInfo(of: line, in: month) : nil
        let note = RecurringText.rowNote(info: info, month: month, current: store.now)
        let texts = detailTexts(day: day, payers: payers, note: note)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    texts
                    amountText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    texts
                    Spacer(minLength: 8)
                    amountText
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metaText(day: Int) -> String {
        let dayText = DayText.ordinal(day)
        return line.isRecurring ? "\(dayText) · elke maand" : dayText
    }

    private func detailTexts(day: Int, payers: [Pot], note: RecurringRowNote?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.name)
                .font(.body)
                .foregroundStyle(Color.primary)
            Label(metaText(day: day), systemImage: line.isRecurring ? "arrow.triangle.2.circlepath" : "calendar")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if let note {
                Text(note.text)
                    .font(.footnote)
                    .foregroundStyle(note.isWarning ? Theme.warning : Theme.textSecondary)
            }
            if let first = payers.first {
                Label {
                    Text("uit \(DayText.list(payers.map { $0.name }))")
                } icon: {
                    Image(systemName: first.symbol)
                        .foregroundStyle(Theme.color(first.colorIndex))
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var amountText: some View {
        Text(Fmt.euro(line.amount))
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
            .contentTransition(.numericText())
            .animated(by: line.amount)
    }
}

// MARK: - Een rij in een lijst

/// Een regel als rij: tikken bewerkt, swipen en het contextmenu geven Bewerken en Verwijderen (`rowActions`). Een eenmalige
/// regel verdwijnt meteen; bij een terugkerende vraagt de rij eerst voor welke maanden (een bevestiging aan de rij zelf).
struct MoneyLineRow: View {
    let line: MoneyLine
    let kind: FinanceData.LineKind
    let month: YearMonth
    let onEdit: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onEdit) {
            MoneyLineRowLabel(line: line, kind: kind, month: month)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowActions(edit: onEdit, delete: requestDelete)
        .confirmationDialog(RecurringText.deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(RecurringText.skipTitle) { remove(scope: .thisMonth) }
            Button(RecurringText.stopTitle, role: .destructive) { remove(scope: .thisAndFollowing) }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(RecurringText.deleteMessage(name: line.name, month: month, current: store.now))
        }
    }

    /// Een eenmalige regel verdwijnt meteen; bij een terugkerende vraagt de app eerst voor welke maanden.
    private func requestDelete() {
        if line.isRecurring {
            confirmingDelete = true
        } else {
            remove(scope: .thisAndFollowing)
        }
    }

    private func remove(scope: SeriesScope) {
        let id = line.id
        let lineKind = kind
        let lineMonth = month
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.mutate { $0.removeLine(id: id, kind: lineKind, in: lineMonth, scope: scope) }
        }
    }
}

// MARK: - Teksten bij een sectie met regels

/// Titels, symbolen en uitleg van een sectie met regels, gebruikt door `MoneyLinesSection`.
enum MoneyLinesText {
    static func title(kind: FinanceData.LineKind, expenseKind: ExpenseKind?) -> String {
        if kind == .income { return "Overige inkomsten" }
        switch expenseKind {
        case .fixed: return "Vaste uitgaven"
        case .variable: return "Variabele uitgaven"
        case nil: return "Uitgaven"
        }
    }

    static func symbol(kind: FinanceData.LineKind, expenseKind: ExpenseKind?) -> String {
        if kind == .income { return "plus.circle" }
        return expenseKind == .variable ? "cart" : "lock"
    }

    static func emptyTitle(kind: FinanceData.LineKind, expenseKind: ExpenseKind?) -> String {
        if kind == .income { return "Geen overige inkomsten" }
        switch expenseKind {
        case .fixed: return "Nog geen vaste uitgaven"
        case .variable: return "Nog geen variabele uitgaven"
        case nil: return "Nog geen uitgaven"
        }
    }

    static func emptyText(kind: FinanceData.LineKind, expenseKind: ExpenseKind?) -> String {
        if kind == .income { return "Denk aan zorgtoeslag, huurtoeslag of een bijverdienste." }
        switch expenseKind {
        case .fixed: return "Denk aan huur, verzekeringen en abonnementen."
        case .variable: return "Denk aan boodschappen, uit eten en kleding."
        case nil: return "Voeg een uitgave toe."
        }
    }

    static func recurringHint(month: YearMonth, current: YearMonth) -> String {
        if month > current {
            return "Terugkerende regels staan er vanzelf in. Pas je er een aan, dan kies je of dat alleen voor \(Fmt.month(month)) geldt of ook voor de maanden erna."
        }
        return "Een terugkerende regel komt elke maand terug op zijn eigen dag, ook in maanden die nog komen."
    }
}

// MARK: - Een sectie met regels

/// De regels van één soort in één maand als sectie van een `List`: rijen, het totaal en een lege staat met een knop. Bij
/// uitgaven kies je met `expenseKind` alleen de vaste of alleen de variabele posten. Het blad om toe te voegen of te
/// bewerken is van de pagina (`onAdd`, `onEdit`).
struct MoneyLinesSection: View {
    let kind: FinanceData.LineKind
    var expenseKind: ExpenseKind? = nil
    let month: YearMonth
    let onAdd: () -> Void
    let onEdit: (MoneyLine) -> Void

    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let plan = d.plan(for: month)
        // Maanden vóór de startmaand tellen nergens mee (Maandoverzicht, Nog te verdelen, Bankrekening, Dag voor dag): regels erin zouden
        // een bedrag tonen dat op geen enkel ander scherm terugkomt. Daarom laat deze sectie daar niets zien en niets toevoegen.
        let beforeStart = month < d.startMonth
        let all: [MoneyLine] = beforeStart ? [] : (kind == .income ? plan.extraIncome : plan.expenses)
        let lines = all.filter { expenseKind == nil || kind == .income || $0.kind == expenseKind }
        Section {
            if beforeStart {
                MonthExplanation(text: "Maanden vóór je startmaand (\(Fmt.month(d.startMonth))) tellen niet mee: daar vul je niets in.")
            } else if lines.isEmpty {
                EmptyHint(symbol: MoneyLinesText.symbol(kind: kind, expenseKind: expenseKind),
                          title: MoneyLinesText.emptyTitle(kind: kind, expenseKind: expenseKind),
                          message: MoneyLinesText.emptyText(kind: kind, expenseKind: expenseKind),
                          actionTitle: "Toevoegen", action: onAdd)
            }
            ForEach(lines) { line in
                MoneyLineRow(line: line, kind: kind, month: month, onEdit: { onEdit(line) })
            }
            totalRow(d, lines: lines)
            if lines.contains(where: { $0.isRecurring }) {
                MonthExplanation(text: MoneyLinesText.recurringHint(month: month, current: store.now))
            }
        } header: {
            SectionHeader(MoneyLinesText.title(kind: kind, expenseKind: expenseKind),
                          symbol: MoneyLinesText.symbol(kind: kind, expenseKind: expenseKind), domain: .money)
        }
    }

    @ViewBuilder
    private func totalRow(_ d: FinanceData, lines: [MoneyLine]) -> some View {
        if !lines.isEmpty {
            let fromPots = kind == .expense
                ? CentsMath.value(CentsMath.sum(lines.map { CentsMath.int(d.fromPots(of: $0)) }))
                : 0
            AmountRow(title: "Totaal", value: Fmt.euro(lines.total),
                      detail: fromPots > 0 ? "Waarvan \(Fmt.euro(fromPots)) uit spaarpotten" : nil, bold: true)
        }
    }
}
