import SwiftUI

// De onderste secties van een spaarpot: Geschiedenis (de tracklijst met swipe en contextmenu), Saldo op datum en Verwijderen. De
// kop en de eerste secties staan in PotDetailPage.swift en PotDetailSections.swift.

// MARK: - Geschiedenis

/// Alles wat het saldo veranderde, tot en met vandaag, als tracklijst met een kleine tegel per boeking. Een boeking die je mag
/// verwijderen heeft swipe en contextmenu; hoort ze bij een overboeking, dan vraagt de rij eerst om bevestiging en zegt ze wat er
/// verdwijnt.
struct PotHistorySection: View {
    let pot: Pot
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAll = false
    @State private var pending: PendingEntryDelete?

    /// Zoveel boekingen uit het verleden staan standaard in de lijst.
    private let limit = 20

    /// Een boeking waarvan het verwijderen eerst om een bevestiging vraagt, omdat er een andere helft bij hoort.
    struct PendingEntryDelete: Identifiable {
        let id: UUID
        let message: String
    }

    init(pot: Pot) {
        self.pot = pot
    }

    var body: some View {
        let d = store.data
        // De geschiedenis hoeft niet verder dan deze maand: wat nog komt staat bij "Komende boekingen".
        let done = d.potTimeline(pot.id, current: store.now, asOf: store.today).filter { !$0.isPlanned }
        let history = PotHistoryContext(pot: pot, data: d, through: store.now)
        let shown = showAll ? done : Array(done.prefix(limit))
        Section {
            if done.isEmpty {
                Text("Nog geen boekingen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(shown) { item in
                historyRow(item, history: history)
            }
            if done.count > limit {
                ActionButton(title: showAll ? "Toon minder" : "Toon alle \(done.count) boekingen",
                             symbol: showAll ? "chevron.up" : "chevron.down") {
                    withAnimation(reduceMotion ? nil : Theme.motion) { showAll.toggle() }
                }
            }
            if let hiddenNote = StartDateText.hiddenPotNote(d, potID: pot.id) {
                NavigationRow(title: StartDateText.pageTitle, symbol: "calendar", domain: .settings, subtitle: hiddenNote,
                              destination: .settings(.startDate))
            }
        } header: {
            SectionHeader("Geschiedenis", symbol: "clock.arrow.circlepath", domain: .saving)
        }
    }

    @ViewBuilder
    private func historyRow(_ item: PotTimelineItem, history: PotHistoryContext) -> some View {
        let row = MediaRowLabel(symbol: rowSymbol(item), hue: Theme.hue(pot.colorIndex), title: item.title,
                                subtitle: rowSubtitle(item, history: history), value: rowAmount(item),
                                valueColor: item.amount >= 0 ? Theme.positive : Theme.negative)
        if let entryID = history.deletableEntryID(for: item) {
            row
                .rowActions(delete: { requestDelete(entryID) })
                .confirmationDialog("Boeking verwijderen?", isPresented: dialogBinding(for: entryID), titleVisibility: .visible,
                                    presenting: pending) { request in
                    Button("Verwijder", role: .destructive) { deleteEntry(request.id) }
                    Button("Annuleer", role: .cancel) {}
                } message: { request in
                    Text(request.message)
                }
        } else {
            row
        }
    }

    /// De bevestiging hoort bij de rij van de boeking die wacht, niet bij alle rijen tegelijk.
    private func dialogBinding(for entryID: UUID) -> Binding<Bool> {
        Binding(get: { pending?.id == entryID }, set: { if !$0 { pending = nil } })
    }

    /// Een losse boeking verdwijnt meteen. Hoort ze bij een overboeking, dan vraagt de app eerst om bevestiging en zegt ze wat
    /// er verdwijnt.
    private func requestDelete(_ entryID: UUID) {
        if let message = deleteMessage(forEntry: entryID) {
            pending = PendingEntryDelete(id: entryID, message: message)
        } else {
            deleteEntry(entryID)
        }
    }

    private func deleteEntry(_ entryID: UUID) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.mutate { $0.deletePotEntry(entryID) }
        }
    }

    /// De tekst voor de bevestiging, of nil als de boeking los staat (dan is verwijderen veilig).
    private func deleteMessage(forEntry id: UUID) -> String? {
        let d = store.data
        guard let entry = d.potEntries.first(where: { $0.id == id }) else { return nil } // raw: zoeken op id
        // Een overboeking met `pairID`: `deletePotEntry` verwijdert beide helften, dus dat zeggen we vooraf.
        if !d.pairedEntries(ofPot: id).isEmpty {
            return "Dit verwijdert ook de bijbehorende boeking op de bankrekening of bij de andere spaarpot."
        }
        // Een oude overboeking tussen potten zonder `pairID`: alleen deze kant verdwijnt.
        if entry.kind == .transferIn || entry.kind == .transferOut {
            return "Dit is een oude overboeking zonder koppeling: alleen deze boeking verdwijnt. De bijbehorende boeking bij de andere spaarpot blijft staan; die verwijder je daar zelf."
        }
        return nil
    }

    private func rowSymbol(_ item: PotTimelineItem) -> String {
        switch item.kind {
        case .interest: return "percent"
        case .expense: return "cart.fill"
        case .allocation: return "calendar"
        case .manual: return item.amount >= 0 ? "plus" : "minus"
        }
    }

    private func rowSubtitle(_ item: PotTimelineItem, history: PotHistoryContext) -> String {
        var parts = [Fmt.date(item.date)]
        if item.kind == .interest {
            // De notitie van de rekenmotor negeren: "Verwacht" klopt niet voor rente uit het verleden, en het percentage in de
            // opgeslagen notitie is op één decimaal afgerond (de badge toont er twee).
            if history.entryID(for: item) != nil {
                parts.append("Bijgeschreven")
            } else {
                parts.append(item.isPlanned ? "Verwacht" : "Wordt bijgeschreven")
            }
        } else if item.isPlanned {
            parts.append("Gepland")
        } else if !item.note.isEmpty {
            parts.append(item.note)
        }
        return parts.joined(separator: " · ")
    }

    private func rowAmount(_ item: PotTimelineItem) -> String {
        let text = item.kind == .interest ? PotFormat.interest(item.amount) : Fmt.euro(item.amount)
        return (item.amount >= 0 ? "+" : "") + text
    }
}

// MARK: - Saldo op datum

/// Het saldo op een gekozen dag, in een uitklapper: vandaag is het het saldo van nu, een andere dag het saldo aan het eind van die dag.
struct PotDateBalanceSection: View {
    let pot: Pot
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    /// Begint een maand vooruit.
    @State private var balanceDate = YearMonth.calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    init(pot: Pot) {
        self.pot = pot
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                expandedContent
            } label: {
                Text("Saldo op datum")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        let today = store.today
        let balance = store.data.potBalanceNow(pot.id, current: store.now, today: today)
        // Vandaag is het het saldo van nu (zoals bovenaan de pagina); een andere dag is het saldo aan het eind van die dag.
        let isToday = YearMonth.calendar.isDate(balanceDate, inSameDayAs: today)
        let atDate = isToday ? balance : store.data.potBalance(pot.id, asOf: balanceDate)
        let difference = CentsMath.value(CentsMath.int(atDate) - CentsMath.int(balance))
        let shownDifference = difference.rounded()
        let differenceColor: Color = shownDifference > 0 ? Theme.positive : (shownDifference < 0 ? Theme.negative : Color.primary)
        DatePicker("Datum", selection: $balanceDate, in: dateRange(today: today), displayedComponents: .date)
        FigureRow {
            StatTile(title: "Saldo op \(Fmt.date(balanceDate))", value: Fmt.euro(atDate))
            StatTile(title: "Verschil met vandaag", value: PotFormat.signed(difference), color: differenceColor)
        }
        quickDates(today: today)
        Text("Inleg, uitgaven uit de pot en rente tellen mee vanaf de dag waarop ze gepland staan. Voor een dag na vandaag is het saldo dat aan het eind van die dag.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }

    private func quickDates(today: Date) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
            quickDate("Vandaag", months: 0, today: today)
            quickDate("Over 3 maanden", months: 3, today: today)
            quickDate("Over 1 jaar", months: 12, today: today)
            quickDate("Over 5 jaar", months: 60, today: today)
        }
    }

    private func quickDate(_ title: String, months: Int, today: Date) -> some View {
        ActionButton(title: title) {
            withAnimation(reduceMotion ? nil : Theme.motion) {
                balanceDate = YearMonth.calendar.date(byAdding: .month, value: months, to: today) ?? today
            }
        }
    }

    /// De datums die je kunt kiezen: vanaf de start van de pot tot 50 jaar vooruit.
    private func dateRange(today: Date) -> ClosedRange<Date> {
        let cal = YearMonth.calendar
        let lower = min(pot.startMonth.firstDay, cal.startOfDay(for: today))
        // Op kalenderjaren gerekend, niet in seconden (schrikkeljaren en zomertijd verschuiven de dag).
        let upper = cal.date(byAdding: .year, value: 50, to: today) ?? today
        return lower...upper
    }
}

// MARK: - Verwijderen

/// Onderaan de pagina, rood, met de bevestiging aan de knop zelf.
struct PotDeleteSection: View {
    let pot: Pot
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    /// Wat het verwijderen van deze pot doet met je rekening (uit de rekenmotor, op het moment dat je op verwijderen tikt).
    @State private var deleteEffect: PotDeleteEffect?

    init(pot: Pot) {
        self.pot = pot
    }

    var body: some View {
        Section {
            ActionButton(title: "Spaarpot verwijderen", symbol: "trash", role: .destructive) {
                // De proef op een kopie van de gegevens kost wat rekenwerk: alleen als je echt wilt verwijderen.
                deleteEffect = PotDeleteEffect(store.data, potID: pot.id, current: store.now, today: store.today)
                confirmDelete = true
            }
            .modifier(PotDeleteDialog(pot: pot, isPresented: $confirmDelete, effect: deleteEffect, onDeleted: { dismiss() }))
        }
    }
}
