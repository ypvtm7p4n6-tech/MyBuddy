import SwiftUI

// Het blad om een regel (overig inkomen of uitgave) toe te voegen of te bewerken. De logica zonder SwiftUI staat in
// App/UI/SavingsDisplay.swift (`LineSave`, `RecurringText`), zodat de tests in CoreTests haar meedraaien.

/// Kijkt vooruit voor een uitgave die elke maand uit een spaarpot komt.
enum PotSpendOutlook {
    /// Het eerste moment in de `months` maanden vanaf `start` waarop `potID` onder nul staat, gemeten aan het eind van
    /// de uitgavedag `day` van elke maand (een dag buiten de maand telt als de laatste dag). nil als het saldo op die
    /// dagen steeds nul of meer is. `data` bevat de uitgave al, anders is de uitkomst die van de pot zonder haar.
    static func firstMomentBelowZero(of potID: UUID, in data: FinanceData, from start: YearMonth,
                                     day: Int, months: Int = 12) -> Date? {
        for offset in 0..<max(0, months) {
            let moment = start.adding(offset).date(day: day)
            if CentsMath.int(data.potBalance(potID, asOf: moment)) < 0 { return moment }
        }
        return nil
    }
}

/// Wat er in het blad is ingevuld, om te zien of er iets is gewijzigd (dan vraagt "Annuleer" om bevestiging).
private struct MoneyLineForm: Equatable {
    var name: String
    var amount: Double
    var recurring: Bool
    var expenseKind: ExpenseKind
    var day: Int?
    var fromPotsOn: Bool
    /// Alleen de delen boven nul: een veld dat je leegmaakt telt als niet ingevuld.
    var shares: [UUID: Double]
}

struct MoneyLineSheet: View {
    let line: MoneyLine?
    let kind: FinanceData.LineKind
    let month: YearMonth
    var defaultExpenseKind: ExpenseKind = .fixed

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name: String
    @State private var amount: Double
    @State private var recurring: Bool
    @State private var expenseKind: ExpenseKind
    @State private var day: Int?
    @State private var fromPotsOn: Bool
    /// Bedrag per spaarpot (alleen potten met een bedrag boven nul tellen mee).
    @State private var shareAmounts: [UUID: Double]
    /// Het verwijderen van een terugkerende regel vraagt eerst voor welke maanden.
    @State private var confirmingDelete = false
    /// Wat er bij het openen van het blad stond.
    private let initialForm: MoneyLineForm

    init(line: MoneyLine?, kind: FinanceData.LineKind, month: YearMonth, defaultExpenseKind: ExpenseKind = .fixed) {
        self.line = line
        self.kind = kind
        self.month = month
        self.defaultExpenseKind = defaultExpenseKind
        var shares: [UUID: Double] = [:]
        for share in line?.potShares ?? [] { shares[share.potID, default: 0] += share.amount }
        _name = State(initialValue: line?.name ?? "")
        _amount = State(initialValue: line?.amount ?? 0)
        _recurring = State(initialValue: line?.isRecurring ?? false)
        _expenseKind = State(initialValue: line?.kind ?? defaultExpenseKind)
        _day = State(initialValue: line?.day)
        _fromPotsOn = State(initialValue: !shares.isEmpty)
        _shareAmounts = State(initialValue: shares)
        initialForm = MoneyLineForm(name: line?.name ?? "", amount: line?.amount ?? 0,
                                    recurring: line?.isRecurring ?? false,
                                    expenseKind: line?.kind ?? defaultExpenseKind, day: line?.day,
                                    fromPotsOn: !shares.isEmpty, shares: shares.filter { $0.value > 0 })
    }

    private struct ShareNote: Identifiable {
        let id: UUID
        let text: String
    }

    /// Is er iets gewijzigd sinds het blad openging? Dan is veeg-om-te-sluiten uit en vraagt "Annuleer" om bevestiging.
    private var hasChanges: Bool {
        let current = MoneyLineForm(name: name, amount: amount, recurring: recurring, expenseKind: expenseKind, day: day,
                                    fromPotsOn: fromPotsOn, shares: shareAmounts.filter { $0.value > 0 })
        return current != initialForm
    }

    var body: some View {
        let d = store.data
        SheetScaffold(title: titleText, canSave: canSave(d), hasChanges: hasChanges,
                      onSave: { save(scope: .thisAndFollowing) }, saveChoices: saveChoices()) {
            Section {
                TextField(kind == .income ? "Naam, bijv. Zorgtoeslag" : "Naam, bijv. Huur", text: $name)
                NumberRow(title: "Bedrag", value: $amount)
                if kind == .expense {
                    Picker("Soort", selection: $expenseKind) {
                        ForEach(ExpenseKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                DayPickerRow(title: "Dag van de maand", day: $day, defaultText: defaultDayText(d))
            } footer: {
                Text(footerText(d))
            }
            Section {
                Toggle("Terugkerend, elke maand", isOn: recurringBinding)
            } footer: {
                Text(recurringFooter(d))
            }
            if kind == .expense && !d.pots.isEmpty {
                potSection(d)
            }
            if let line {
                deleteSection(line)
            }
        }
        .confirmationDialog(RecurringText.deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(RecurringText.skipTitle) { removeAndClose(scope: .thisMonth) }
            Button(RecurringText.stopTitle, role: .destructive) { removeAndClose(scope: .thisAndFollowing) }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(RecurringText.deleteMessage(name: line?.name ?? "", month: month, current: store.now))
        }
    }

    private var titleText: String {
        switch (kind, line) {
        case (.income, nil): return "Inkomen toevoegen"
        case (.income, _): return "Inkomen bewerken"
        case (.expense, nil): return "Uitgave toevoegen"
        case (.expense, _): return "Uitgave bewerken"
        }
    }

    /// Voert een wijziging uit met de standaardbeweging, tenzij Verlaag beweging aan staat.
    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : Theme.motion, change)
    }

    // MARK: Dag en terugkerend

    private func defaultDayPhrase(_ d: FinanceData) -> String {
        if kind == .expense { return DayText.ordinal(1) }
        let ordinal = DayText.ordinal(d.salaryDay(in: month))
        return d.salary.isMonthly ? "je salarisdag, \(ordinal)" : "de eerste salarisdag van de maand, \(ordinal)"
    }

    private func defaultDayText(_ d: FinanceData) -> String {
        if kind == .expense { return "Standaard (\(DayText.ordinal(1)))" }
        return "Standaard (\(DayText.ordinal(d.salaryDay(in: month))))"
    }

    private func footerText(_ d: FinanceData) -> String {
        let phrase = RecurringText.dayPhrase(day: day, defaultPhrase: defaultDayPhrase(d))
        if kind == .income {
            return "Voor \(Fmt.month(month)). Dit komt binnen op \(phrase). Kies een andere dag als het bedrag op een ander moment binnenkomt."
        }
        return "Voor \(Fmt.month(month)). Dit gaat van je rekening op \(phrase). Vast zijn kosten die elke maand gelijk zijn, zoals huur. Variabel zijn kosten die schommelen, zoals boodschappen."
    }

    private var recurringBinding: Binding<Bool> {
        Binding(get: { recurring }, set: { on in animate { recurring = on } })
    }

    /// Wat "Terugkerend" voor deze regel inhoudt: op welke dag hij terugkomt, vanaf en tot wanneer.
    private func recurringFooter(_ d: FinanceData) -> String {
        let phrase = RecurringText.dayPhrase(day: day, defaultPhrase: defaultDayPhrase(d))
        let wasRecurring = line?.isRecurring == true
        guard recurring else { return RecurringText.oneOff(month: month, wasRecurring: wasRecurring) }
        if let line, line.isRecurring {
            return RecurringText.existingRecurring(dayPhrase: phrase, day: effectiveDay, info: d.seriesInfo(of: line, in: month),
                                                   month: month)
        }
        // Een nieuwe terugkerende regel loopt door in een reeks met dezelfde naam die in deze maand ontbreekt.
        let resumes = line == nil && d.resumableSeries(named: name, kind: kind, in: month) != nil
        return RecurringText.newRecurring(dayPhrase: phrase, day: effectiveDay, month: month, resumes: resumes)
    }

    /// De dag waarop deze regel valt, begrensd op de lengte van de maand.
    private var effectiveDay: Int {
        let fallback = kind == .income ? store.data.salaryDay(in: month) : 1
        return min(YearMonth.clampedDay(day ?? fallback), month.dayCount)
    }

    private var lineDate: Date { month.date(day: effectiveDay) }

    // MARK: Betalen uit spaarpot

    private var amountCents: Int { CentsMath.int(amount) }

    private func shareCents(_ id: UUID) -> Int { max(0, CentsMath.int(shareAmounts[id] ?? 0)) }

    private func potsCents(_ d: FinanceData) -> Int { CentsMath.sum(d.pots.map { shareCents($0.id) }) }

    private var potToggle: Binding<Bool> {
        Binding(get: { fromPotsOn }, set: { on in animate { fromPotsOn = on } })
    }

    private func shareBinding(_ id: UUID) -> Binding<Double> {
        Binding(get: { shareAmounts[id] ?? 0 }, set: { shareAmounts[id] = $0 })
    }

    /// Wat een pot op de dag van deze uitgave kan missen. Staat de uitgave al in het plan, dan is haar oude deel
    /// al van het saldo af en rekenen we dat terug (alleen als het op of vóór de nieuwe dag viel).
    private func availability(of pot: Pot, in d: FinanceData) -> Double {
        var cents = CentsMath.int(d.potBalance(pot.id, asOf: lineDate))
        if let line, !line.potShares.isEmpty {
            let oldDay = min(d.expenseDay(of: line), month.dayCount)
            if oldDay <= effectiveDay {
                for payment in d.expenseSplit(of: line).pots where payment.potID == pot.id {
                    cents += payment.cents
                }
            }
        }
        return CentsMath.value(cents)
    }

    private func availabilityMap(_ d: FinanceData) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for pot in d.pots { result[pot.id] = availability(of: pot, in: d) }
        return result
    }

    private func shareNotes(_ d: FinanceData, available: [UUID: Double]) -> [ShareNote] {
        let dateText = DayText.short(lineDate)
        var notes: [ShareNote] = []
        for pot in d.pots {
            let cents = shareCents(pot.id)
            let have = available[pot.id] ?? 0
            guard cents > 0, cents > CentsMath.int(have) else { continue }
            let wanted = Fmt.euro(CentsMath.value(cents))
            if CentsMath.int(have) <= 0 {
                notes.append(ShareNote(id: pot.id,
                                       text: "\(pot.name) heeft op \(dateText) geen saldo (\(Fmt.euro(have))). Je haalt er \(wanted) uit."))
            } else {
                notes.append(ShareNote(id: pot.id,
                                       text: "\(pot.name) heeft op \(dateText) maar \(Fmt.euro(have)). Je haalt er \(wanted) uit."))
            }
        }
        return notes
    }

    /// Bij een terugkerende uitgave uit een pot: komt de pot daardoor in een latere maand onder nul? Alleen potten die
    /// door deze uitgave onder nul komen, of eerder dan zonder haar. Rekent op een kopie van de gegevens met de regel
    /// erin en een kopie zonder de regel; er wordt niets opgeslagen.
    private func recurringNotes(_ d: FinanceData) -> [ShareNote] {
        guard kind == .expense, fromPotsOn, recurring else { return [] }
        let draft = draftLine()
        guard !draft.potShares.isEmpty else { return [] }
        var with = d
        with.upsertLine(draft, kind: .expense, in: month)
        let expenseDay = draft.day ?? 1
        var notes: [ShareNote] = []
        for share in draft.potShares {
            guard let pot = d.pot(share.potID),
                  let moment = PotSpendOutlook.firstMomentBelowZero(of: pot.id, in: with, from: month, day: expenseDay)
            else { continue }
            var without = d
            without.deleteLine(id: draft.id, kind: .expense, in: month)
            if let before = PotSpendOutlook.firstMomentBelowZero(of: pot.id, in: without, from: month, day: expenseDay),
               before <= moment {
                continue
            }
            notes.append(ShareNote(id: pot.id,
                                   text: "Met deze terugkerende uitgave staat \(pot.name) vanaf \(Fmt.month(YearMonth(date: moment))) onder nul."))
        }
        return notes
    }

    @ViewBuilder
    private func potSection(_ d: FinanceData) -> some View {
        Section {
            Toggle("Betalen uit spaarpot", isOn: potToggle)
            if fromPotsOn {
                potDetails(d)
            }
        } header: {
            Text("Bron van het geld")
        } footer: {
            Text(fromPotsOn
                 ? "Het bedrag per pot gaat op de gekozen dag van het saldo van die pot af. Wat je niet uit een pot haalt, betaalt je bankrekening. Staat er meer in dan het saldo van de pot, dan zie je een waarschuwing en kun je toch opslaan."
                 : "Kies een of meer spaarpotten die deze uitgave (deels) betalen. Wat overblijft gaat van je bankrekening.")
        }
    }

    /// De rijen onder de schakelaar. Alleen berekend als "Betalen uit spaarpot" aan staat.
    @ViewBuilder
    private func potDetails(_ d: FinanceData) -> some View {
        let available = availabilityMap(d)
        let notes = shareNotes(d, available: available)
        let bankCents = amountCents - potsCents(d)
        let ahead = recurringNotes(d)
        ForEach(d.pots) { pot in
            potRow(pot, available: available[pot.id] ?? 0)
        }
        HStack {
            Text("Van bankrekening").font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(Fmt.euro(CentsMath.value(bankCents)))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(bankCents < 0 ? Theme.negative : Color.primary)
                .contentTransition(.numericText())
                .animated(by: bankCents)
        }
        if bankCents < 0 {
            Label("De delen uit spaarpotten zijn samen \(Fmt.euro(CentsMath.value(-bankCents))) meer dan de uitgave. Verlaag een bedrag om op te slaan.",
                  systemImage: "xmark.octagon.fill")
                .font(.footnote)
                .foregroundStyle(Theme.negative)
        }
        ForEach(notes) { note in
            Label(note.text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        ForEach(ahead) { note in
            Label(note.text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        Button { splitEvenly(d.pots) } label: {
            Label("Gelijk verdelen", systemImage: "divide")
                .frame(minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.borderless)
        .disabled(amountCents == 0)
    }

    @ViewBuilder
    private func potRow(_ pot: Pot, available: Double) -> some View {
        let tooMuch = shareCents(pot.id) > CentsMath.int(available)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: pot.symbol, color: Theme.color(pot.colorIndex), size: 32)
                NumberRow(title: pot.name, value: shareBinding(pot.id))
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    balanceCaption(available: available, tooMuch: tooMuch)
                    Spacer(minLength: 8)
                    allFromButton(pot)
                }
                VStack(alignment: .leading, spacing: 4) {
                    balanceCaption(available: available, tooMuch: tooMuch)
                    allFromButton(pot)
                }
            }
        }
    }

    private func balanceCaption(available: Double, tooMuch: Bool) -> some View {
        // Per kalenderdag: de dag van vandaag is al gebeurd, pas een latere dag is verwacht.
        let prefix = DayMath.isPlanned(lineDate, asOf: store.today) ? "Verwacht saldo op" : "Saldo op"
        return Text("\(prefix) \(DayText.short(lineDate)): \(Fmt.euro(available))")
            .font(.footnote)
            .foregroundStyle(tooMuch ? Theme.warning : Theme.textSecondary)
    }

    private func allFromButton(_ pot: Pot) -> some View {
        Button { fillAll(from: pot.id) } label: {
            Text("Alles uit deze pot")
                .font(.footnote.weight(.semibold))
                .frame(minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.borderless)
        .disabled(amountCents == 0)
    }

    /// De hele uitgave uit deze ene pot.
    private func fillAll(from potID: UUID) {
        guard amountCents > 0 else { return }
        animate { shareAmounts = [potID: CentsMath.value(amountCents)] }
    }

    /// Verdeelt het bedrag gelijk over de potten waar al iets staat, of over alle potten als nog niets is ingevuld.
    /// Er blijft geen cent liggen: de resterende centen gaan naar de eerste potten.
    private func splitEvenly(_ pots: [Pot]) {
        guard amountCents > 0, !pots.isEmpty else { return }
        let chosen = pots.filter { shareCents($0.id) > 0 }
        let targets = chosen.isEmpty ? pots : chosen
        let base = amountCents / targets.count
        let extra = amountCents % targets.count
        var result: [UUID: Double] = [:]
        for (index, pot) in targets.enumerated() {
            result[pot.id] = CentsMath.value(base + (index < extra ? 1 : 0))
        }
        animate { shareAmounts = result }
    }

    // MARK: Verwijderen

    @ViewBuilder
    private func deleteSection(_ existing: MoneyLine) -> some View {
        Section {
            Button(role: .destructive) {
                requestDelete(existing)
            } label: {
                Text(existing.isRecurring ? "Verwijder…" : "Verwijder")
            }
        }
    }

    /// Een eenmalige regel verdwijnt meteen; bij een terugkerende vraagt de app eerst voor welke maanden.
    private func requestDelete(_ existing: MoneyLine) {
        if existing.isRecurring {
            confirmingDelete = true
        } else {
            removeAndClose(scope: .thisAndFollowing)
        }
    }

    private func removeAndClose(scope: SeriesScope) {
        guard let existing = line else { return }
        let lineKind = kind
        let lineMonth = month
        animate {
            store.mutate { $0.removeLine(id: existing.id, kind: lineKind, in: lineMonth, scope: scope) }
        }
        dismiss()
    }

    // MARK: Opslaan

    private func canSave(_ d: FinanceData) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, amount > 0 else { return false }
        if kind == .expense && fromPotsOn { return potsCents(d) <= amountCents }
        return true
    }

    /// De delen per pot. Een bestaand deel houdt zijn id, zodat de boekingen niet van id wisselen.
    private func builtShares(_ pots: [Pot]) -> [PotShare] {
        var existing: [UUID: UUID] = [:]
        for share in line?.potShares ?? [] where existing[share.potID] == nil {
            existing[share.potID] = share.id
        }
        var result: [PotShare] = []
        for pot in pots {
            let cents = shareCents(pot.id)
            guard cents > 0 else { continue }
            result.append(PotShare(id: existing[pot.id] ?? UUID(), potID: pot.id, amount: CentsMath.value(cents)))
        }
        return result
    }

    /// De regel zoals hij bij "Bewaar" wordt opgeslagen. Slaat zelf niets op.
    private func draftLine() -> MoneyLine {
        var updated = line ?? MoneyLine(name: "", amount: 0)
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.amount = amount.cents
        updated.isRecurring = recurring
        updated.kind = kind == .expense ? expenseKind : .fixed
        updated.day = day.map { YearMonth.clampedDay($0) }
        updated.potShares = (kind == .expense && fromPotsOn) ? builtShares(store.data.pots) : []
        return updated
    }

    /// Bij een regel die al terugkeert vraagt "Bewaar" eerst voor welke maanden de wijziging geldt (alleen deze maand, of
    /// ook alle maanden erna). Is er niets gewijzigd, of keerde de regel niet terug, dan wordt meteen opgeslagen.
    private func saveChoices() -> SaveChoices? {
        let edited = draftLine()
        guard LineSave.needsScopeQuestion(existing: line, edited: edited) else { return nil }
        let thisMonth = SaveChoices.Option(id: "this", title: SeriesScope.thisMonth.title) { save(scope: .thisMonth) }
        if edited.isRecurring {
            let following = SaveChoices.Option(id: "following", title: SeriesScope.thisAndFollowing.title) {
                save(scope: .thisAndFollowing)
            }
            return SaveChoices(title: RecurringText.scopeTitle,
                               message: RecurringText.scopeMessage(name: edited.name, month: month, current: store.now),
                               options: [thisMonth, following])
        }
        let stop = SaveChoices.Option(id: "stop", title: RecurringText.stopTitle, role: .destructive) {
            save(scope: .thisAndFollowing)
        }
        return SaveChoices(title: RecurringText.stopRecurringTitle,
                           message: RecurringText.stopRecurringMessage(name: edited.name, month: month, current: store.now),
                           options: [thisMonth, stop])
    }

    private func save(scope: SeriesScope) {
        let edited = draftLine()
        // Niets gewijzigd: niets opslaan (een afgeleide regel van een toekomstige maand blijft dan afgeleid).
        if let line, line == edited { return }
        let isNew = line == nil
        let lineKind = kind
        let lineMonth = month
        animate {
            store.mutate { LineSave.apply(&$0, edited: edited, isNew: isNew, kind: lineKind, month: lineMonth, scope: scope) }
        }
    }
}
