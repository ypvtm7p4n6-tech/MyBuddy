import SwiftUI

// Alle spaarpotten (lijstpagina). De pagina van één spaarpot staat in Saving/PotDetailPage.swift, de bladen in Saving/PotSheets.swift
// en de kaarten voor het Overzicht en Sparen in Saving/FavoriteCards.swift. De teksten en cijfers rond rente (zonder SwiftUI:
// `PotFormat`, `PotInterestStats`, `PotHistoryContext`) staan in App/UI/PotDisplay.swift, zodat de tests in CoreTests ze meecompileren.

/// Klein label "2% rente" voor potten met rente.
struct PotInterestBadge: View {
    let rate: Double

    var body: some View {
        Text("\(Fmt.percent(rate, digits: 2)) rente")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.positive)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.positive.opacity(0.16), in: Capsule())
            .accessibilityLabel("Rente \(Fmt.percent(rate, digits: 2)) per jaar")
    }
}

// MARK: - Een spaarpot verwijderen

/// De bevestiging bij het verwijderen van een spaarpot, aan de rij of de knop waar je verwijdert (DLG-4). Met saldo eerst de veilige
/// keuze: het geld gaat terug naar je rekening. De getallen in de uitleg komen uit een proef op een kopie van de gegevens
/// (`PotDeleteEffect`).
struct PotDeleteDialog: ViewModifier {
    let pot: Pot
    @Binding var isPresented: Bool
    let effect: PotDeleteEffect?
    let onDeleted: () -> Void
    @Environment(AppStore.self) private var store

    init(pot: Pot, isPresented: Binding<Bool>, effect: PotDeleteEffect?, onDeleted: @escaping () -> Void = {}) {
        self.pot = pot
        self._isPresented = isPresented
        self.effect = effect
        self.onDeleted = onDeleted
    }

    private var hasBalance: Bool {
        if let effect { return effect.hasBalance }
        return CentsMath.int(store.data.potBalanceNow(pot.id, current: store.now, today: store.today)) > 0
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Deze spaarpot verwijderen?", isPresented: $isPresented, titleVisibility: .visible) {
                dialogButtons
            } message: {
                Text(effect?.message ?? "De boekingen van deze pot verdwijnen ook.")
            }
    }

    @ViewBuilder
    private var dialogButtons: some View {
        if hasBalance {
            // Eerst de veilige keuze: het geld gaat terug naar je rekening.
            Button("Saldo terugzetten op je rekening en verwijderen") { deleteReturningBalance() }
            Button("Verwijderen en saldo laten vervallen", role: .destructive) { deleteDiscardingBalance() }
        } else {
            Button("Verwijder \(pot.name)", role: .destructive) { deleteDiscardingBalance() }
        }
        Button("Annuleer", role: .cancel) {}
    }

    private func deleteReturningBalance() {
        let id = pot.id
        let current = store.now
        let moment = store.today
        store.mutate { $0.deletePot(id, returningBalanceToBank: true, current: current, today: moment) }
        onDeleted()
    }

    private func deleteDiscardingBalance() {
        let id = pot.id
        store.mutate { $0.deletePot(id) }
        onDeleted()
    }
}

// MARK: - Alle spaarpotten

struct PotsPage: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: PotsPageSheet?

    /// De bladen die deze pagina opent, in een `.sheet(item:)`.
    private enum PotsPageSheet: Identifiable {
        case newPot
        case editPot(Pot)
        case pickFavorites

        var id: String {
            switch self {
            case .newPot: return "new"
            case .editPot(let pot): return "edit-" + pot.id.uuidString
            case .pickFavorites: return "favorites"
            }
        }
    }

    var body: some View {
        let d = store.data
        ListScaffold(title: "Spaarpotten") {
            if d.pots.isEmpty {
                emptySection
            } else {
                PotsSummarySection()
                potsSection(d.pots)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                IconButton("Nieuwe spaarpot", symbol: "plus") { sheet = .newPot }
            }
            if !d.pots.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    moreMenu
                }
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
    }

    private var emptySection: some View {
        Section {
            EmptyHint(symbol: "tray", title: "Nog geen spaarpotten",
                      message: "Maak een pot voor je noodbuffer, een vakantie of een nieuwe laptop.",
                      actionTitle: "Nieuwe spaarpot", action: { sheet = .newPot })
        }
    }

    private func potsSection(_ pots: [Pot]) -> some View {
        Section {
            ForEach(pots) { pot in
                PotRow(pot: pot, onEdit: { sheet = .editPot(pot) })
            }
        } header: {
            SectionHeader("Potten", domain: .saving)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button { sheet = .pickFavorites } label: {
                Label("Kies potten voor het Overzicht…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("Meer", systemImage: "ellipsis")
        }
        .help("Meer")
    }

    @ViewBuilder
    private func sheetContent(_ item: PotsPageSheet) -> some View {
        switch item {
        case .newPot: PotEditSheet(pot: nil)
        case .editPot(let pot): PotEditSheet(pot: pot)
        case .pickFavorites: FavoritePotsSheet()
        }
    }
}

/// De samenvatting bovenaan Spaarpotten: totaal gespaard met drie ondersteunende cijfers en de voortgang naar het totale doel.
struct PotsSummarySection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let monthName = Fmt.monthNames[now.month - 1]
        // Het saldo van vandaag (de tegels, het Overzicht en de pagina van een pot tonen hetzelfde) en wat het aan het eind van de
        // maand wordt: dezelfde som als "Spaarpotten" in het Vermogen.
        let saved = d.totalSaved(current: now, today: today)
        let endOfMonth = d.totalSaved(asOf: now.date(day: now.dayCount))
        let hasInterest = d.pots.contains { InterestRules.isActive($0) }
        let received = PotInterestStats.received(in: d, asOf: today)
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Totaal gespaard")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    BigAmount(value: saved, label: "Totaal gespaard")
                    Text("Saldo vandaag")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                FigureRow {
                    StatTile(title: "Inleg deze maand", value: Fmt.euro(d.savedTotal(in: now)),
                             caption: "Volgens je verdeling van \(monthName)")
                    StatTile(title: "Verwacht eind \(monthName)", value: Fmt.euro(endOfMonth),
                             caption: "Met alles wat nog komt")
                    if hasInterest {
                        StatTile(title: "Rente dit jaar", value: PotFormat.interest(received.thisYear), color: Theme.positive)
                    }
                }
                goalProgress(goal: d.totalGoal(), towardGoals: d.savedTowardGoals(current: now, today: today))
            }
        } header: {
            SectionHeader("Samenvatting", domain: .saving)
        }
    }

    /// De voortgang naar het totale doel van alle potten met een doel. Zonder doel staat er niets.
    @ViewBuilder
    private func goalProgress(goal: Double, towardGoals: Double) -> some View {
        if goal > 0 {
            let fraction = towardGoals / goal
            VStack(alignment: .leading, spacing: 6) {
                ProgressMeter(value: fraction, tint: Theme.accent, style: .bar(), label: "Voortgang naar je totale doel",
                              valueText: PotFormat.progressSpeech(balance: towardGoals, goal: goal, progress: fraction))
                Text("\(Fmt.percent(min(fraction, 9.99), digits: 0)) van je totale doel van \(Fmt.euro(goal)) gehaald")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Een rij in de lijst

/// Een spaarpot in de lijst: naam, saldo, voortgang naar het doel (of "Geen doel ingesteld") en de inleg. Swipe en contextmenu geven
/// Bewerken en Verwijderen; Verwijderen vraagt dezelfde bevestiging als op de pagina van de pot.
struct PotRow: View {
    let pot: Pot
    let onEdit: () -> Void
    @Environment(AppStore.self) private var store
    @State private var confirmDelete = false
    @State private var deleteEffect: PotDeleteEffect?

    init(pot: Pot, onEdit: @escaping () -> Void) {
        self.pot = pot
        self.onEdit = onEdit
    }

    var body: some View {
        SavingLink(.pot(pot.id)) { rowLabel }
            .rowActions(edit: { onEdit() }, delete: { requestDelete() })
            .modifier(PotDeleteDialog(pot: pot, isPresented: $confirmDelete, effect: deleteEffect))
    }

    @ViewBuilder
    private var rowLabel: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let balance = d.potBalanceNow(pot.id, current: now, today: today)
        let progress = d.potProgress(pot.id, current: now, today: today)
        let color = Theme.color(pot.colorIndex)
        HStack(alignment: .top, spacing: 12) {
            SymbolBadge(symbol: pot.symbol, color: color, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                AmountRow(title: pot.name, value: Fmt.euro(balance), bold: true)
                if let progress, let goal = pot.goalAmount, goal > 0 {
                    ProgressMeter(value: progress, tint: color, style: .bar(), label: "Voortgang \(pot.name)",
                                  valueText: PotFormat.progressSpeech(balance: balance, goal: goal, progress: progress))
                }
                Text(detailLine(progress: progress))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if let line = ContributionInfo.listLine(d, id: pot.id, month: now) {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            SavingChevron()
                .padding(.top, 4)
        }
        .foregroundStyle(Color.primary)
    }

    /// "Doel € 2.400 · 43%", of "Geen doel ingesteld", met de rente erachter als die er is.
    private func detailLine(progress: Double?) -> String {
        var parts: [String] = []
        if let progress, let goal = pot.goalAmount, goal > 0 {
            parts.append("Doel \(Fmt.euro(goal))")
            parts.append(Fmt.percent(progress, digits: 0))
        } else {
            parts.append("Geen doel ingesteld")
        }
        if InterestRules.isActive(pot) {
            parts.append("\(Fmt.percent(pot.interestRate, digits: 2)) rente")
        }
        return parts.joined(separator: " · ")
    }

    private func requestDelete() {
        // De proef op een kopie van de gegevens kost wat rekenwerk: alleen als je echt wilt verwijderen.
        deleteEffect = PotDeleteEffect(store.data, potID: pot.id, current: store.now, today: store.today)
        confirmDelete = true
    }
}
