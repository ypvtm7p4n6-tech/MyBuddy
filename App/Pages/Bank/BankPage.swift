import SwiftUI

// De pagina Bankrekening (docs/design/plan.md par. 2.4 en K15): een lijst met drie onderdelen.
//   Saldo         het saldo van vandaag, het verwachte verloop, binnen en eruit van een maand en het minimumsaldo
//   Dag voor dag  de maand dag voor dag: grafiek, de twee sluitende uitklappers en een sectie per dag
//   Boekingen     de geschiedenis van ingevulde saldi en boekingen, met swipe
// Geld bewegen (storten, opnemen, naar of van een spaarpot, saldo invullen) staat in het menu van de werkbalk.
// Alle bedragen komen uit de rekenmotor (bank, dagboekhouding, maandcijfers); hier wordt niets zelf uitgerekend.

/// De onderdelen van Bankrekening.
enum BankSection: String, CaseIterable, Identifiable {
    case balance, days, entries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: return "Saldo"
        case .days: return "Dag voor dag"
        case .entries: return "Boekingen"
        }
    }
}

/// Het blad dat open staat op Bankrekening: geld bewegen, of de regel achter een gebeurtenis bewerken. Eén blad tegelijk.
enum BankSheet: Identifiable {
    case move(BankAction)
    case line(CashflowLineTarget)

    var id: String {
        switch self {
        case .move(let action): return "move-" + action.rawValue
        case .line(let target): return "line-" + target.id.uuidString
        }
    }
}

// MARK: - Hulpmiddelen voor de rijen van deze pagina

/// Knopstijl voor een rij in een lijst die iets opent: de rij wordt iets doorzichtig zolang je drukt (een drukstatus, en op de Mac
/// geen knoprand).
struct BankRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// Een rij zonder kaartachtergrond, over de hele breedte van de lijst: voor een eigen kaart of een bediening (kiezer,
    /// maandkiezer) tussen de secties van een lijst.
    func bankBareRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

// MARK: - De pagina

/// De bankrekening in de app: hier komt je salaris binnen, hier gaan je uitgaven vanaf en vanaf hier zet je geld over naar
/// spaarpotten en beleggingen. Het is geen echte bank. `section` kiest het onderdeel waarmee de pagina opent.
struct BankPage: View {
    private let startSection: BankSection
    @State private var selection: BankSection
    @State private var sheet: BankSheet?
    @Environment(AppStore.self) private var store

    init(section: BankSection = .balance) {
        startSection = section
        _selection = State(initialValue: section)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ListScaffold(title: "Bankrekening") {
                Section {
                    sectionPicker
                }
                content(proxy: proxy)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    moveMenu
                }
            }
            .sheet(item: $sheet) { item in
                sheetContent(item)
            }
            .sensoryFeedback(.selection, trigger: selection)
            .onChange(of: startSection) { _, newSection in
                selection = newSection
            }
        }
    }

    // MARK: Onderdelen

    private var sectionPicker: some View {
        Picker("Onderdeel van Bankrekening", selection: $selection) {
            ForEach(BankSection.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .bankBareRow()
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        switch selection {
        case .balance:
            BankBalanceSections(sheet: $sheet, showDays: { selection = .days })
        case .days:
            BankDaysSections(sheet: $sheet, proxy: proxy)
        case .entries:
            BankEntriesSections(sheet: $sheet)
        }
    }

    /// Het menu "Geld bewegen": storten, opnemen, naar of van een spaarpot (alleen met spaarpotten) en saldo invullen.
    private var moveMenu: some View {
        Menu {
            Button { sheet = .move(.deposit) } label: {
                Label(BankAction.deposit.title, systemImage: BankAction.deposit.symbol)
            }
            Button { sheet = .move(.withdraw) } label: {
                Label(BankAction.withdraw.title, systemImage: BankAction.withdraw.symbol)
            }
            if !store.data.pots.isEmpty {
                Button { sheet = .move(.toPot) } label: {
                    Label(BankAction.toPot.title, systemImage: BankAction.toPot.symbol)
                }
                Button { sheet = .move(.fromPot) } label: {
                    Label(BankAction.fromPot.title, systemImage: BankAction.fromPot.symbol)
                }
            }
            Button { sheet = .move(.balance) } label: {
                Label(BankAction.balance.title, systemImage: BankAction.balance.symbol)
            }
        } label: {
            Label("Geld bewegen", systemImage: "plus")
        }
        .help("Geld bewegen")
    }

    @ViewBuilder
    private func sheetContent(_ item: BankSheet) -> some View {
        switch item {
        case .move(let action):
            BankActionSheet(action: action)
        case .line(let target):
            MoneyLineSheet(line: target.line, kind: target.kind, month: target.month, defaultExpenseKind: target.line.kind)
        }
    }
}

// MARK: - Voorbeelden (alleen in Xcode)

#if DEBUG
@MainActor
private struct BankPreviewHost: View {
    @State private var store: AppStore
    @State private var router = Router()
    let section: BankSection

    init(section: BankSection) {
        let sampleStore = AppStore(storage: nil)
        sampleStore.loadSampleData()
        _store = State(initialValue: sampleStore)
        self.section = section
    }

    var body: some View {
        NavigationStack {
            BankPage(section: section)
        }
        .environment(store)
        .environment(router)
    }
}

#Preview("Saldo") {
    BankPreviewHost(section: .balance)
}

#Preview("Dag voor dag") {
    BankPreviewHost(section: .days)
}

#Preview("Dag voor dag, donker, grote tekst") {
    BankPreviewHost(section: .days)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Boekingen") {
    BankPreviewHost(section: .entries)
}
#endif
