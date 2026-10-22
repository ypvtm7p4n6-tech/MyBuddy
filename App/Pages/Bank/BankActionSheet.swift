import SwiftUI

// Het blad voor geld bewegen op de bankrekening: een saldo invullen, geld storten of opnemen, en geld naar of van een spaarpot.
// Het opent vanuit het menu "Geld bewegen" van Bankrekening, vanuit een lege staat en vanuit de kaart "Komende dagen".

enum BankAction: String, Identifiable, CaseIterable {
    case balance, deposit, withdraw, toPot, fromPot
    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: return "Saldo invullen"
        case .deposit: return "Geld storten"
        case .withdraw: return "Geld opnemen"
        case .toPot: return "Naar spaarpot"
        case .fromPot: return "Van spaarpot"
        }
    }

    var symbol: String {
        switch self {
        case .balance: return "square.and.pencil"
        case .deposit: return "plus.circle"
        case .withdraw: return "minus.circle"
        case .toPot: return "arrow.right.circle"
        case .fromPot: return "arrow.left.circle"
        }
    }
}

struct BankActionSheet: View {
    let action: BankAction

    @Environment(AppStore.self) private var store
    @State private var amount = 0.0
    /// Het bedrag waarmee het blad opende (bij "Saldo invullen" het saldo van vandaag): wat daarvan afwijkt is een wijziging.
    @State private var startAmount = 0.0
    @State private var note = ""
    @State private var potID: UUID?

    private var hasChanges: Bool {
        amount != startAmount || !note.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        // Saldo's van nu, per kalenderdag: wat vandaag op je plan staat telt al mee, wat op een latere dag komt (het salaris
        // van de 25e, de inleg) nog niet.
        let bank = d.bankBalanceNowIfKnown(current: now, today: today)
        let potBalance = potID.map { d.potBalanceNow($0, current: now, today: today) } ?? 0
        SheetScaffold(title: action.title, canSave: canSave(potBalance: potBalance), hasChanges: hasChanges,
                      onSave: { save() }) {
            Section {
                if action == .toPot || action == .fromPot {
                    if d.pots.isEmpty {
                        Text("Je hebt nog geen spaarpotten.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Picker("Spaarpot", selection: $potID) {
                            ForEach(d.pots) { pot in Text(pot.name).tag(pot.id as UUID?) }
                        }
                    }
                }
                NumberRow(title: action == .balance ? "Saldo vandaag" : "Bedrag", value: $amount,
                          allowsNegative: action == .balance)
                TextField("Notitie (optioneel)", text: $note)
            } header: {
                Text(headerText(bank: bank, potBalance: potBalance))
                    .textCase(nil)
            } footer: {
                Text(footerText)
            }
        }
        .onAppear {
            if action == .balance {
                amount = bank ?? 0
                startAmount = amount
            }
            if potID == nil { potID = d.pots.first?.id }
        }
    }

    private func headerText(bank: Double?, potBalance: Double) -> String {
        let bankText = bank.map { Fmt.euro($0) } ?? "onbekend"
        switch action {
        case .fromPot: return "Saldo spaarpot \(Fmt.euro(potBalance)) · bankrekening \(bankText)"
        default: return "Saldo bankrekening \(bankText)"
        }
    }

    private var footerText: String {
        switch action {
        case .balance: return "Vul het saldo in zoals het nu op je rekening staat. Boekingen van de dag waarop je het saldo invult gelden als al verwerkt. Elke invoer wordt bewaard."
        case .deposit: return "Dit zet geld op de bankrekening in de app. Er gebeurt niets bij een echte bank."
        case .withdraw: return "Dit haalt geld van de bankrekening in de app, bijvoorbeeld voor contant geld of een grote uitgave."
        case .toPot: return "Het bedrag gaat van de bankrekening naar de spaarpot en staat in de geschiedenis van beide."
        case .fromPot: return "Het bedrag gaat van de spaarpot terug naar de bankrekening."
        }
    }

    private func canSave(potBalance: Double) -> Bool {
        switch action {
        case .balance: return true
        case .deposit, .withdraw: return amount > 0
        case .toPot: return amount > 0 && potID != nil
        case .fromPot: return amount > 0 && potID != nil && amount <= potBalance + 0.005
        }
    }

    private func save() {
        let a = amount
        let n = note.trimmingCharacters(in: .whitespaces)
        let pot = potID
        apply(amount: a, note: n, potID: pot)
    }

    private func apply(amount a: Double, note n: String, potID pot: UUID?) {
        switch action {
        case .balance:
            store.mutate { $0.addBankSnapshot(balance: a, note: n) }
        case .deposit:
            store.mutate { $0.addBankEntry(amount: a, note: n) }
        case .withdraw:
            store.mutate { $0.addBankEntry(amount: -a, note: n) }
        case .toPot:
            if let pot { store.mutate { $0.transferBankToPot(potID: pot, amount: a, note: n) } }
        case .fromPot:
            if let pot { store.mutate { $0.transferPotToBank(potID: pot, amount: a, note: n) } }
        }
    }
}
