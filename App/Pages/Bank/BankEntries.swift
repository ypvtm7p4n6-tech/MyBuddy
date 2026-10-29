import SwiftUI

// Het onderdeel Boekingen van Bankrekening: de geschiedenis van ingevulde saldi en boekingen, de nieuwste eerst. Elke rij heeft
// swipe en contextmenu met Verwijderen (`rowActions`). Een ingevuld saldo en een losse storting of opname verdwijnen meteen; hoort
// een boeking bij een overboeking naar of van een spaarpot, dan vraagt de app eerst om bevestiging en zegt ze wat er verdwijnt.
// De lijst en de tekst van de bevestiging komen uit `BankHistoryItem` (CashflowDisplay.swift). Met een startdatum staan alleen de
// boekingen vanaf die dag in de lijst; onderaan zegt een rij hoeveel eraan voorafgingen (ze blijven bewaard).

/// Een boeking waarvan het verwijderen eerst om een bevestiging vraagt, omdat er een andere helft bij hoort.
struct BankPendingDelete: Identifiable {
    let id: UUID
    let message: String
}

struct BankEntriesSections: View {
    @Binding var sheet: BankSheet?
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingDelete: BankPendingDelete?

    var body: some View {
        let items = BankHistoryItem.items(from: store.data)
        Section {
            if items.isEmpty {
                EmptyHint(symbol: "clock.arrow.circlepath", title: "Nog geen boekingen",
                          message: "Een ingevuld saldo, een storting of een opname komt hier te staan.",
                          actionTitle: BankAction.balance.title, action: { sheet = .move(.balance) })
            } else {
                ForEach(items) { item in
                    row(item)
                }
            }
            hiddenRow
        } header: {
            SectionHeader("Geschiedenis", symbol: "clock.arrow.circlepath", domain: .money)
        }
    }

    /// Onderaan de lijst: hoeveel boekingen er vóór je startdatum liggen (bewaard, maar ze tellen niet mee), met een link naar
    /// Startdatum. Zonder startdatum, of zonder zulke boekingen, staat er niets.
    @ViewBuilder
    private var hiddenRow: some View {
        if let note = StartDateText.hiddenBankNote(store.data) {
            NavigationRow(title: StartDateText.pageTitle, symbol: "calendar", domain: .settings, subtitle: note,
                          destination: .settings(.startDate))
        }
    }

    private func row(_ item: BankHistoryItem) -> some View {
        AmountRow(title: item.title, value: valueText(item), detail: detailText(item), color: valueColor(item))
            .rowActions(delete: { requestDelete(item) })
            .confirmationDialog("Boeking verwijderen?", isPresented: isAsking(item), titleVisibility: .visible,
                                presenting: pendingDelete) { pending in
                Button("Verwijderen", role: .destructive) { remove(pending.id, snapshot: false) }
            } message: { pending in
                Text(pending.message)
            }
    }

    private func valueText(_ item: BankHistoryItem) -> String {
        item.isSnapshot ? Fmt.euro(item.amount) : CashflowText.signed(item.amount)
    }

    private func detailText(_ item: BankHistoryItem) -> String {
        item.detail.isEmpty ? Fmt.date(item.date) : "\(Fmt.date(item.date)) · \(item.detail)"
    }

    private func valueColor(_ item: BankHistoryItem) -> Color {
        if item.isSnapshot { return Color.primary }
        return item.amount >= 0 ? Theme.positive : Theme.negative
    }

    /// De bevestiging hoort bij de rij waarvan je het verwijderen vroeg (een dialoog aan de rij, niet aan de pagina).
    private func isAsking(_ item: BankHistoryItem) -> Binding<Bool> {
        Binding<Bool>(get: { pendingDelete?.id == item.id },
                      set: { isShown in if !isShown { pendingDelete = nil } })
    }

    /// Een ingevuld saldo en een losse boeking verdwijnen meteen; een boeking met een andere helft vraagt eerst om bevestiging.
    private func requestDelete(_ item: BankHistoryItem) {
        if !item.isSnapshot, let message = BankHistoryItem.removalWarning(forBankEntry: item.id, in: store.data) {
            pendingDelete = BankPendingDelete(id: item.id, message: message)
        } else {
            remove(item.id, snapshot: item.isSnapshot)
        }
    }

    private func remove(_ id: UUID, snapshot: Bool) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.mutate { data in
                if snapshot { data.deleteBankSnapshot(id) } else { data.deleteBankEntry(id) }
            }
        }
    }
}
