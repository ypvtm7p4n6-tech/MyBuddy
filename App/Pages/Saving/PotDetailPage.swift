import SwiftUI

// De pagina van één spaarpot als albumpagina (Apple Muziek, ontwerp 2): een kop met het artwork, het saldo, de voortgang en de
// acties als eerste rij van de lijst, daaronder de bestaande secties als tracklijst: Verloop, Komende boekingen, Geschiedenis,
// Inleg en rente, Saldo op datum en onderaan Verwijderen. De secties staan in PotDetailSections.swift en PotHistorySections.swift.

struct PotDetailPage: View {
    let potID: UUID
    @Environment(AppStore.self) private var store
    @State private var sheet: PotDetailSheet?

    /// De bladen die deze pagina opent, via een blad-item.
    private enum PotDetailSheet: Identifiable {
        case entry(PotAction)
        case edit

        var id: String {
            switch self {
            case .entry(let action): return "entry-" + action.rawValue
            case .edit: return "edit"
            }
        }
    }

    init(potID: UUID) {
        self.potID = potID
    }

    var body: some View {
        if let pot = store.data.pot(potID) {
            content(pot)
        } else {
            ListScaffold(title: "Spaarpot") {
                Section {
                    EmptyHint(symbol: "questionmark.folder", title: "Deze spaarpot bestaat niet meer")
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ pot: Pot) -> some View {
        ListScaffold(title: pot.name) {
            Section {
                PotAlbumHeader(pot: pot, onAction: { action in sheet = .entry(action) }, onEdit: { sheet = .edit })
                    .albumHeaderRow()
            }
            PotTrendSection(pot: pot)
            PotUpcomingSection(pot: pot)
            PotHistorySection(pot: pot)
            PotContributionSection(pot: pot, onEdit: { sheet = .edit })
            PotDateBalanceSection(pot: pot)
            PotDeleteSection(pot: pot)
        }
        .environment(\.backdropHue, Theme.hue(pot.colorIndex))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item, pot: pot)
        }
    }

    /// "Geld bewegen" en "Bewerken" in het menu van de werkbalk: dezelfde acties als de pillen in de kop, plus Saldo aanpassen en
    /// Overboeken.
    private var moreMenu: some View {
        Menu {
            actionItem(.deposit)
            actionItem(.withdraw)
            actionItem(.setBalance)
            if store.data.pots.count > 1 { actionItem(.transfer) }
            Divider()
            Button { sheet = .edit } label: {
                Label("Bewerken", systemImage: "pencil")
            }
        } label: {
            Label("Meer", systemImage: "ellipsis")
        }
        .help("Meer")
    }

    private func actionItem(_ action: PotAction) -> some View {
        Button { sheet = .entry(action) } label: {
            Label(action.title, systemImage: action.symbol)
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: PotDetailSheet, pot: Pot) -> some View {
        switch item {
        case .entry(let action): PotEntrySheet(pot: pot, action: action)
        case .edit: PotEditSheet(pot: pot)
        }
    }
}

// MARK: - De kop van het album

/// De kop van de spaarpot: een groot artwork in de kleur van de pot, de naam, "Spaarpot" met het doel, het saldo van vandaag, de
/// voortgang naar het doel, de feiten (doel, rente, inleg) en de pillen Storten (de hoofdactie), Opnemen en Bewerken. Het saldo
/// is `potBalanceNow`, hetzelfde getal als op Home en op de pagina Spaarpotten.
struct PotAlbumHeader: View {
    let pot: Pot
    let onAction: (PotAction) -> Void
    let onEdit: () -> Void
    @Environment(AppStore.self) private var store

    init(pot: Pot, onAction: @escaping (PotAction) -> Void, onEdit: @escaping () -> Void) {
        self.pot = pot
        self.onAction = onAction
        self.onEdit = onEdit
    }

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let balance = d.potBalanceNow(pot.id, current: now, today: today)
        let progress = d.potProgress(pot.id, current: now, today: today)
        AlbumHeader(symbol: pot.symbol, hue: Theme.hue(pot.colorIndex), title: pot.name,
                    subtitle: SavingAlbumText.potSubtitle(goal: pot.goalAmount),
                    figureLabel: "Saldo vandaag", figure: balance, progress: progress,
                    progressLabel: "Voortgang \(pot.name)",
                    facts: facts(balance: balance, progress: progress)) {
            pills
        }
    }

    /// Doel (of dat er geen is), rente en inleg, uit dezelfde bronnen als de secties eronder.
    private func facts(balance: Double, progress: Double?) -> [String] {
        let info = ContributionInfo(store.data, id: pot.id, month: store.now)
        let rate: Double? = InterestRules.isActive(pot) ? pot.interestRate : nil
        return SavingAlbumText.potFacts(balance: balance, goal: pot.goalAmount, progress: progress, interestRate: rate,
                                        contribution: SavingAlbumText.contributionFact(info))
    }

    @ViewBuilder
    private var pills: some View {
        PillButton("Storten", symbol: "plus.circle", style: .prominent) { onAction(.deposit) }
        PillButton("Opnemen", symbol: "minus.circle") { onAction(.withdraw) }
        PillButton("Bewerken", symbol: "pencil") { onEdit() }
    }
}
