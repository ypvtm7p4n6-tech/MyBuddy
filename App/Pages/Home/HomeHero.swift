import SwiftUI

// De hero van Home: drie grote kaarten in een carrousel (Nog te verdelen, Vermogen, Saldo vandaag). Alle bedragen komen uit
// dezelfde bronnen als de oude kaarten van het Overzicht: `MonthBoard` (en daarmee `MonthFigures`), `netWorth(at:current:)` met
// `NetWorthTrend`, en het banksaldo van vandaag met de dagboekhouding (`LedgerBook`, `UpcomingDaysWindow`). De kaarten zijn geen
// links: de pillen leiden naar de pagina's. De achtergrond van Home volgt de zichtbare kaart (`HomeTab`).

// MARK: - De carrousel

/// De drie hero-kaarten, met de selectie die `HomeTab` leest voor de kleur van de achtergrond.
struct HomeHeroSection: View {
    @Binding var selection: String?
    let present: HomePresent

    var body: some View {
        HeroCarousel(ids: HomeHeroID.all, selection: $selection) { id in
            HomeHeroCard(id: id, present: present)
        }
    }
}

/// De kaart bij een hero-id, bovenaan uitgelijnd: de kaarten zijn niet even hoog, dus de kortere staat niet in het midden.
private struct HomeHeroCard: View {
    let id: String
    let present: HomePresent

    var body: some View {
        card
            .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var card: some View {
        if id == HomeHeroID.wealth {
            HomeWealthHero(present: present)
        } else if id == HomeHeroID.balance {
            HomeBalanceHero(present: present)
        } else {
            HomeDistributeHero()
        }
    }
}

// MARK: - Kaart 1: Nog te verdelen

/// Wat er van het inkomen van de huidige maand nog te verdelen is. Alle cijfers komen uit `MonthBoard`, hetzelfde getal als op
/// Verdelen en in de Bibliotheek. De pil opent Verdelen op de huidige maand.
struct HomeDistributeHero: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let month = store.now
        let board = MonthBoard(d, month: month)
        let percentWarning = d.allocationWarnings(in: month).first { $0.isPercentageWarning }
        let notes = HomeHeroNotes.list(board: board, percentWarning: percentWarning)
        HeroCard(hue: .olive, eyebrow: "\(MoneyLabels.remaining) in \(Fmt.month(month))", symbol: "square.split.2x2") {
            BigAmount(value: board.remaining, font: Theme.heroAmount, color: Theme.onTile, label: MoneyLabels.remaining)
            if !notes.isEmpty {
                HomeHeroNoteList(notes: notes)
            }
        } pills: {
            PillLink("Verdelen", style: .onTile, destination: .distribute, showsCurrentMonth: true)
        }
    }
}

/// Eén regel bij het getal van kaart 1.
struct HomeHeroNote: Identifiable {
    let id: String
    let text: String
    let symbol: String?
}

/// Wat er bij "Nog te verdelen" hoort: waarom het negatief is, het salarisschema, wat uit een spaarpot komt en een waarschuwing
/// over de percentages. Dezelfde regels en teksten als het oude Overzicht; zonder een van die dingen staat er niets.
enum HomeHeroNotes {
    static func list(board: MonthBoard, percentWarning: AllocationWarning?) -> [HomeHeroNote] {
        var notes: [HomeHeroNote] = []
        if board.isNegative {
            // De tekst volgt de oorzaak: te hoge uitgaven (bijvoorbeeld nog geen salaris) of te veel verdeeld.
            let text = board.spendingExceedsIncome ? "Je uitgaven zijn hoger dan je inkomen deze maand."
                                                   : "Je hebt meer verdeeld dan er te verdelen was deze maand."
            notes.append(HomeHeroNote(id: "negative", text: text, symbol: "exclamationmark.triangle.fill"))
        }
        // Bij een salaris om de zoveel weken of dagen is het inkomen de som van de uitbetalingen van deze maand.
        if let salaryNote = board.salaryNote {
            notes.append(HomeHeroNote(id: "salary", text: salaryNote, symbol: nil))
        }
        // Uitgaven uit een spaarpot kosten dit maandbudget niets.
        if board.hasPotExpenses {
            let text = "Wat je uit een spaarpot betaalt (\(Fmt.euro(board.fromPots))) telt niet mee in dit bedrag."
            notes.append(HomeHeroNote(id: "pots", text: text, symbol: nil))
        }
        if let percentWarning {
            notes.append(HomeHeroNote(id: "percent", text: percentWarning.message, symbol: "exclamationmark.triangle.fill"))
        }
        return notes
    }
}

private struct HomeHeroNoteList: View {
    let notes: [HomeHeroNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notes) { note in
                HomeHeroLine(text: note.text, symbol: note.symbol)
            }
        }
    }
}

// MARK: - Kaart 2: Vermogen

/// Het vermogen aan het eind van de huidige maand (bank, spaarpotten en beleggingen), met het verloop over de laatste 12 maanden
/// als kleine grafiek zonder assen (een vast venster, geen periodekeuze) en drie pillen naar waar het uit bestaat. Alle bedragen
/// komen uit `netWorth(at:current:)`, de grafiek uit `NetWorthTrend`.
struct HomeWealthHero: View {
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let worth = d.netWorth(at: now, current: now)
        let months = now.adding(-11).range(count: 12)
        let model = NetWorthTrend.model(d, months: months, current: now, today: store.today)
        let title = MoneyLabels.netWorthEnd(of: now)
        HeroCard(hue: .slate, eyebrow: title, symbol: "chart.pie") {
            BigAmount(value: worth.total, font: Theme.heroAmount, color: Theme.onTile, label: title)
            TrendChart(model: model, size: .compact, showsAxes: false, onAction: handleChartAction)
                .heroPanel()
            if !worth.bankKnown {
                HomeHeroLine(text: "Je banksaldo is nog niet bekend, dus de bank telt als € 0 mee. Vul je saldo in voor een compleet vermogen.",
                             symbol: "info.circle")
            }
        } pills: {
            HomeWealthPills(worth: worth)
        }
    }

    /// De knop in de lege staat van de grafiek: "Banksaldo invullen" opent het blad om je saldo in te vullen.
    private func handleChartAction(_ action: ChartEmpty.Action) {
        if case .enterBankBalance = action {
            present(.balance)
        }
    }
}

/// Bank, Spaarpotten en Beleggingen met hun bedrag, elk een pil naar de eigen pagina.
private struct HomeWealthPills: View {
    let worth: NetWorthPoint

    var body: some View {
        PillRow {
            PillLink("Bank " + (worth.bankKnown ? Fmt.euro(worth.bank) : "onbekend"), style: .onTile, destination: .bank)
            PillLink("Potten " + Fmt.euro(worth.pots), style: .onTile, destination: .pots)
            PillLink("Beleggingen " + Fmt.euro(worth.investments), style: .onTile, destination: .portfolio)
        }
    }
}

// MARK: - Kaart 3: Saldo vandaag

/// Het saldo van de bankrekening van vandaag en de volgende betaling uit de dagboekhouding. Zonder bekend saldo staat er "Vul je
/// saldo in" met een pil die het blad opent. De pil "Dag voor dag" opent de dagen van de huidige maand.
struct HomeBalanceHero: View {
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let today = store.today
        let balance = d.bankBalanceNowIfKnown(current: store.now, today: today)
        let next = UpcomingDaysWindow.nextPayment(in: LedgerBook(d, today: today), today: today)
        HeroCard(hue: .terracotta, eyebrow: "Saldo vandaag", symbol: "building.columns") {
            if let balance {
                BigAmount(value: balance, font: Theme.heroAmount, color: Theme.onTile, label: "Saldo vandaag")
            } else {
                Text("Vul je saldo in")
                    .font(Theme.titleAmount)
                    .foregroundStyle(Theme.onTile)
            }
            HomeHeroLine(text: HomeBalanceText.nextPayment(next))
        } pills: {
            PillRow {
                PillLink("Dag voor dag", symbol: "calendar", style: .onTile, destination: .cashflow, showsCurrentMonth: true)
                PillButton(balance == nil ? "Saldo invullen" : "Saldo bijwerken", symbol: "pencil", style: .onTile) {
                    present(.balance)
                }
            }
        }
    }
}

/// De tekst van de volgende betaling.
enum HomeBalanceText {
    /// "Volgende betaling: Huur, ma 27 okt, − € 850", of "Geen betalingen gepland".
    static func nextPayment(_ next: (day: DayTotals, event: DayEvent)?) -> String {
        guard let next else { return "Geen betalingen gepland" }
        let date = DayText.weekdayShort(next.day.date)
        let amount = CashflowText.signed(next.event.bankAmount)
        return "Volgende betaling: \(next.event.title), \(date), \(amount)"
    }
}
