import SwiftUI

// De lijst met extra overschrijfdata van een pot of belegging (D2): een rij per deel (dag en bedrag), "Datum toevoegen" en de uitleg.
// Dit is alleen invoer: de stukken en de waarschuwing komen van de aanroeper uit de rekenmotor (`TransferMath`, `transferSlices`). Hetzelfde
// onderdeel staat in het blad van een pot of belegging (de standaard) en op Verdelen (één maand).

struct TransferPartsEditor: View {
    @Binding var parts: [TransferPart]
    /// De dag waarop de rest wordt overgeschreven (voor de uitleg).
    let standardDay: Int
    /// De inleg van de maand in centen, voor de waarschuwing als de delen samen meer zijn. nil = geen waarschuwing.
    var totalCents: Int? = nil
    /// Wat als alle vakken leeg zijn: een korte tekst waarom je er een zou toevoegen.
    var emptyHint = "Alles gaat op de overschrijfdag over."

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if parts.isEmpty {
                MonthExplanation(text: emptyHint)
            }
            ForEach(parts) { part in
                partRow(part)
            }
            if parts.count < TransferMath.maxParts {
                ActionButton(title: TransferPartsText.addTitle, symbol: "plus.circle") { addPart() }
            }
            MonthExplanation(text: TransferPartsText.explanation(standardDay: standardDay))
            if let note = TransferPartsText.shortMonthNote(parts: parts) {
                MonthExplanation(text: note)
            }
            if let totalCents,
               let warning = TransferPartsText.overflowWarning(overflowCents: TransferMath.overflowCents(totalCents: totalCents, parts: parts)) {
                MonthWarningLine(text: warning)
            }
        }
    }

    // MARK: Een deel

    private func partRow(_ part: TransferPart) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Dag van de maand", selection: dayBinding(for: part)) {
                ForEach(freeDays(for: part), id: \.self) { number in
                    Text(DayText.ordinal(number)).tag(number)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Theme.minTapTarget)
            NumberRow(title: "Bedrag", value: amountBinding(for: part))
            ActionButton(title: "Verwijder deze dag", symbol: "trash", role: .destructive) { remove(part) }
        }
        .padding(10)
        .tile()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TransferPartsText.accessibilityLabel(part))
    }

    private func dayBinding(for part: TransferPart) -> Binding<Int> {
        Binding<Int>(get: { part.day }, set: { value in
            replace(part, with: TransferPart(day: value, amount: part.amount))
        })
    }

    /// De dagen die dit deel kan kiezen: alle dagen die geen ander deel al heeft (een dag komt hooguit één keer voor).
    private func freeDays(for part: TransferPart) -> [Int] {
        let others = Set(parts.filter { $0.day != part.day }.map { $0.day })
        return (1...31).filter { !others.contains($0) }
    }

    private func amountBinding(for part: TransferPart) -> Binding<Double> {
        Binding(get: { part.amount }, set: { value in
            replace(part, with: TransferPart(day: part.day, amount: value))
        })
    }

    // MARK: Wijzigen

    /// Vervangt een deel; delen op dezelfde dag vallen samen (`TransferMath.normalized` doet dat bij het bewaren).
    private func replace(_ old: TransferPart, with new: TransferPart) {
        guard let index = parts.firstIndex(where: { $0.day == old.day }) else { return }
        var copy = parts
        copy[index] = new
        parts = copy
    }

    private func remove(_ part: TransferPart) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            parts.removeAll { $0.day == part.day }
        }
    }

    /// Een nieuw deel op de eerste dag die nog vrij is, te beginnen bij de dag vóór de standaarddag, met nul als bedrag.
    private func addPart() {
        let used = Set(parts.map { $0.day })
        var day = max(1, standardDay - 1)
        for _ in 0..<31 where used.contains(day) { day = day % 31 + 1 }
        withAnimation(reduceMotion ? nil : Theme.motion) {
            parts.append(TransferPart(day: day, amount: 0))
        }
    }
}
