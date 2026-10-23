import SwiftUI

// De onderdelen van het Overzicht die niet van een ander pakket komen: de kern "Nog te verdelen", het welkomstscherm, de melding
// "De cijfers sluiten niet" en het blok Vermogen. De kaarten Spaarpotten, Beleggingen en Komende dagen komen van C en B2.

// MARK: - Kern: Nog te verdelen

/// De kern van het Overzicht: wat er van het inkomen van de huidige maand nog te verdelen is. Alle cijfers komen uit
/// `MonthBoard` (dus uit `MonthFigures`), hetzelfde getal als op Verdelen en op Maand. Een tik opent Verdelen op de huidige maand.
struct OverviewHero: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let month = store.now
        let board = MonthBoard(d, month: month)
        let left = board.remaining
        let percentWarning = d.allocationWarnings(in: month).first { $0.isPercentageWarning }
        LinkCard(title: "\(MoneyLabels.remaining) in \(Fmt.month(month))", symbol: "square.split.2x2", domain: .money,
                 destination: .distribute, showsCurrentMonth: true) {
            BigAmount(value: left, color: left < 0 ? Theme.negative : Color.primary, label: MoneyLabels.remaining)
            OverviewHeroNotes(board: board, percentWarning: percentWarning)
        }
    }
}

/// Wat er bij het getal hoort: waarom het negatief is, het salarisschema, wat uit een spaarpot komt en een waarschuwing over de
/// percentages. Zonder een van die dingen staat er niets.
struct OverviewHeroNotes: View {
    let board: MonthBoard
    let percentWarning: AllocationWarning?

    var body: some View {
        if board.isNegative {
            // De tekst volgt de oorzaak: te hoge uitgaven (bijvoorbeeld nog geen salaris) of te veel verdeeld.
            TabWarning(text: board.spendingExceedsIncome ? "Je uitgaven zijn hoger dan je inkomen deze maand."
                                                         : "Je hebt meer verdeeld dan er te verdelen was deze maand.")
        }
        // Bij een salaris om de zoveel weken of dagen is het inkomen de som van de uitbetalingen van deze maand.
        if let salaryNote = board.salaryNote {
            TabNote(text: salaryNote)
        }
        // Uitgaven uit een spaarpot kosten dit maandbudget niets.
        if board.hasPotExpenses {
            TabNote(text: "Wat je uit een spaarpot betaalt (\(Fmt.euro(board.fromPots))) telt niet mee in dit bedrag.")
        }
        if let percentWarning {
            AllocationWarningLabel(warning: percentWarning)
        }
    }
}

// MARK: - Melding bij afwijking

/// De melding "De cijfers sluiten niet" voor de huidige maand. Alleen bij een afwijking; anders staat er niets. Het oordeel komt
/// van `LedgerCheck` op de dagboekhouding, dezelfde als op Dag voor dag.
struct OverviewCheckBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let book = LedgerBook(store.data, today: store.today)
        let check = LedgerCheck(book.ledger(store.now))
        if !check.isOK {
            CashflowCheckBanner(check: check)
        }
    }
}

// MARK: - Lege start

/// Wat je ziet zolang er niets is ingevuld: uitleg, "Salaris instellen" (de ene vervolgstap) en "Voorbeelddata laden".
struct OverviewWelcome: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var confirmSample = false

    var body: some View {
        VStack(spacing: Theme.rowSpacing) {
            EmptyHint(symbol: "sparkles", title: "Welkom bij MyBuddy",
                      message: "Begin met je salaris. Daarna maak je spaarpotten, voeg je beleggingen toe en verdeel je elke maand je geld.",
                      actionTitle: "Salaris instellen",
                      action: { openSalary() },
                      style: .page)
            ActionButton(title: "Voorbeelddata laden", symbol: "wand.and.stars") {
                confirmSample = true
            }
        }
        // Voorbeelddata vervangt alles, ook in de cloud en op andere apparaten: eerst vragen.
        .confirmationDialog("Voorbeelddata laden?", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("Vervang mijn gegevens door voorbeelddata", role: .destructive) {
                store.loadSampleData()
            }
        } message: {
            if FirebaseConfig.isConfigured {
                Text("Je huidige gegevens worden vervangen, ook in de cloud en op je andere apparaten.")
            } else {
                Text("Je huidige gegevens worden vervangen.")
            }
        }
    }

    private func openSalary() {
        router.showCurrentMonth(store.now)
        router.open(.salary)
    }
}

// MARK: - Vermogen

/// Het blok `wealth`: het vermogen aan het eind van de huidige maand, het verloop over de laatste 12 maanden (een vast venster,
/// geen periodekeuze) en drie links naar waar het uit bestaat. Alle bedragen komen uit `netWorth(at:current:)`.
struct OverviewWealthCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let now = store.now
        let worth = d.netWorth(at: now, current: now)
        let months = now.adding(-11).range(count: 12)
        let model = NetWorthTrend.model(d, months: months, current: now, today: store.today)
        Card(title: "Vermogen", symbol: "chart.pie", domain: .overview) {
            headline(worth: worth, now: now)
            TrendChart(model: model, size: .regular, onAction: handleChartAction)
            parts(worth: worth)
        }
    }

    /// Het vermogen met het peilmoment ("Vermogen eind oktober"): met wat er die maand nog komt en gaat.
    private func headline(worth: NetWorthPoint, now: YearMonth) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MoneyLabels.netWorthEnd(of: now))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            BigAmount(value: worth.total, font: Theme.titleAmount, label: MoneyLabels.netWorthEnd(of: now))
        }
    }

    /// Bankrekening, Spaarpotten en Beleggingen als link: elk naar de eigen pagina (op een andere tab, dus met `go`).
    private func parts(worth: NetWorthPoint) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TabAmountLink(title: "Bankrekening", value: worth.bankKnown ? Fmt.euro(worth.bank) : "Onbekend",
                          symbol: "building.columns", destination: .bank)
            Divider()
            TabAmountLink(title: "Spaarpotten", value: Fmt.euro(worth.pots),
                          symbol: "tray.full", destination: .pots)
            Divider()
            TabAmountLink(title: "Beleggingen", value: Fmt.euro(worth.investments),
                          symbol: "chart.line.uptrend.xyaxis", destination: .portfolio)
            if !worth.bankKnown {
                TabNote(text: "Je banksaldo is nog niet bekend, dus de bank telt als € 0 mee. Vul je saldo in voor een compleet vermogen.")
                    .padding(.top, 8)
            }
        }
    }

    /// De knop in de lege staat van de grafiek: "Banksaldo invullen" gaat naar de Bankrekening.
    private func handleChartAction(_ action: ChartEmpty.Action) {
        if case .enterBankBalance = action {
            router.open(.bank)
        }
    }
}
