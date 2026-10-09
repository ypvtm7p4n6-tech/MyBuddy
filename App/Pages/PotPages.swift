import SwiftUI

// MARK: - Teksten en cijfers rond rente (alleen Foundation, zonder SwiftUI)

// PURE-BEGIN
/// Kleine hulpjes voor teksten rond rente en dagen, zodat tegels, het bewerkblad en de detailpagina hetzelfde zeggen.
enum PotFormat {
    /// "1 januari 2027".
    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Fmt.locale
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    /// Rente-bedragen: onder de 10 euro met centen (anders staat er "€ 0"), daarboven afgerond op hele euro's.
    static func interest(_ value: Double) -> String {
        if value != 0 && abs(value) < 10 { return Fmt.euroExact(value) }
        return Fmt.euro(value)
    }

    /// "de 25e".
    static func dayName(_ day: Int) -> String {
        "de \(day)e"
    }

    /// Naam van een maand (1...12), bijvoorbeeld "januari".
    static func monthName(_ number: Int) -> String {
        Fmt.monthNames[min(max(number, 1), 12) - 1]
    }

    /// "januari, april en juli".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " en " + items[items.count - 1]
        }
    }

    /// De maanden (1...12) waarin een pot rente uitbetaalt. Zelfde regel als de rekenmotor:
    /// vanaf de eerste uitbetaalmaand telkens `intervalMonths` verder.
    static func payoutMonths(_ payout: InterestPayout, firstMonth: Int) -> [Int] {
        let interval = max(1, payout.intervalMonths)
        let anchor = min(max(firstMonth, 1), 12)
        return (1...12).filter { (($0 - anchor) % interval + interval) % interval == 0 }
    }

    /// De eerste uitbetaalmaand van het jaar die bij dit ritme past: bij elk kwartaal januari t/m maart, bij elk
    /// half jaar januari t/m juni, bij elk jaar elke maand. Maandelijks heeft er geen last van (alleen begrensd op 1...12).
    /// De rekenmotor telt vanaf deze maand telkens `intervalMonths` verder, dus een maand erboven geeft dezelfde
    /// uitbetalingen als de maand die hier uitkomt.
    static func firstMonth(_ month: Int, for payout: InterestPayout) -> Int {
        let clamped = min(max(month, 1), 12)
        guard payout != .monthly else { return clamped }
        let interval = max(1, payout.intervalMonths)
        return (clamped - 1) % interval + 1
    }

    /// De maanden die je kunt kiezen als eerste uitbetaling van het jaar: 1...3 bij kwartaal, 1...6 bij half jaar, 1...12 bij jaar.
    static func firstMonthChoices(for payout: InterestPayout) -> ClosedRange<Int> {
        1...min(12, max(1, payout.intervalMonths))
    }

    /// "+€ 120", "€ -30" of "€ 0": een verschil dat op nul afrondt krijgt geen plus.
    static func signed(_ value: Double) -> String {
        let shown = value.rounded()
        if shown == 0 { return Fmt.euro(0) }
        return (shown > 0 ? "+" : "") + Fmt.euro(value)
    }

    /// "Je krijgt rente in januari en juli, op de 1e."
    static func schedule(_ payout: InterestPayout, firstMonth: Int, day: Int) -> String {
        var text: String
        if payout == .monthly {
            text = "Je krijgt elke maand rente, op \(dayName(day))."
        } else {
            let names = payoutMonths(payout, firstMonth: firstMonth).map { monthName($0) }
            text = "Je krijgt rente in \(list(names)), op \(dayName(day))."
        }
        if day > 28 {
            text += " Heeft een maand die dag niet, dan is het de laatste dag van die maand."
        }
        return text
    }

    /// "1 januari 2027, ongeveer € 12" (zonder "ongeveer" als de uitbetaling al vaststaat).
    static func nextPayment(_ payment: InterestPayment) -> String {
        let approx = payment.isProjected ? "ongeveer " : ""
        return longDate(payment.date) + ", " + approx + interest(payment.amount)
    }
}

/// Rente die een pot (of alle potten) echt heeft gekregen.
struct PotInterestReceived: Equatable {
    var total: Double
    var thisYear: Double
}

enum PotInterestStats {
    /// Wat er aan rente is bijgeschreven op of voor `today`: opgeslagen boekingen plus uitbetalingen die al
    /// aan de beurt waren maar nog niet zijn opgeslagen (die tellen al wel mee in het saldo).
    /// Zonder `potID` telt het alle potten.
    static func received(in d: FinanceData, potID: UUID? = nil, asOf today: Date) -> PotInterestReceived {
        let cal = YearMonth.calendar
        let year = cal.component(.year, from: today)
        let wanted: Set<UUID> = potID.map { Set([$0]) } ?? Set(d.pots.map { $0.id })
        var total = 0
        var thisYear = 0

        for entry in d.potEntries where entry.kind == .interest && entry.date <= today && wanted.contains(entry.potID) {
            let cents = CentsMath.int(entry.amount)
            total = CentsMath.add(total, cents)
            if cal.component(.year, from: entry.date) == year { thisYear = CentsMath.add(thisYear, cents) }
        }

        for pot in d.pots where wanted.contains(pot.id) && InterestRules.isActive(pot) {
            let payments = d.interestPayments(for: pot.id, from: pot.startMonth.firstDay, to: today, asOf: today)
            for payment in payments where payment.isProjected && payment.date <= today {
                let cents = CentsMath.int(payment.amount)
                total = CentsMath.add(total, cents)
                if cal.component(.year, from: payment.date) == year { thisYear = CentsMath.add(thisYear, cents) }
            }
        }
        return PotInterestReceived(total: CentsMath.value(total), thisYear: CentsMath.value(thisYear))
    }
}

/// Wat de regels in de geschiedenis van een pot nodig hebben om te weten welke boeking erachter zit
/// en of je die mag verwijderen.
struct PotHistoryContext {
    let potID: UUID
    /// Id's van de opgeslagen rente-boekingen van deze pot.
    let storedInterest: Set<UUID>
    /// Id's van de uitbetalingen die de app zelf beheert: bij actieve rente schrijft de app die direct weer bij.
    let managedInterest: Set<UUID>

    init(pot: Pot, data: FinanceData, through last: YearMonth) {
        potID = pot.id
        storedInterest = Set(data.potEntries.filter { $0.potID == pot.id && $0.kind == .interest }.map { $0.id })
        managedInterest = Set(data.interestPayoutMonths(for: pot, through: last)
            .map { InterestRules.entryID(for: pot.id, month: $0) })
    }

    /// De opgeslagen boeking achter een regel. nil voor maandverdelingen, geplande uitgaven en verwachte rente.
    func entryID(for item: PotTimelineItem) -> UUID? {
        if item.isMonthlyAllocation { return nil }
        if let id = UUID(uuidString: item.id) { return id }
        // Opgeslagen rente draagt de id van de uitbetaling ("interest-<pot>-<jjjj-mm>"); de boeking zelf heeft een vast id.
        guard item.kind == .interest else { return nil }
        let id = InterestRules.entryID(for: potID, month: YearMonth(date: item.date))
        return storedInterest.contains(id) ? id : nil
    }

    /// De boeking die je mag verwijderen. Rente nooit: de app boekt ontbrekende rente bij de volgende start
    /// (of het volgende bewaren van de pot) opnieuw, dus verwijderen helpt niet en maakt alleen de geschiedenis
    /// onbetrouwbaar. Klopt het saldo niet, pas het dan aan met "Saldo aanpassen".
    func deletableEntryID(for item: PotTimelineItem) -> UUID? {
        guard item.kind != .interest, let id = entryID(for: item) else { return nil }
        return managedInterest.contains(id) ? nil : id
    }
}
// PURE-END

/// Klein label "2% rente" voor potten met rente. Ook bruikbaar op andere pagina's.
struct PotInterestBadge: View {
    let rate: Double

    var body: some View {
        Text("\(Fmt.percent(rate, digits: 2)) rente")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.positive)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.positive.opacity(0.16), in: Capsule())
            .accessibilityLabel("Rente \(Fmt.percent(rate, digits: 2)) per jaar")
    }
}

/// Maten die alleen deze pagina's gebruiken.
private enum PotLayout {
    /// Minimale breedte van een tegel.
    static let tileWidth: CGFloat = 140
    /// Zoveel maanden vooruit kijkt de geschiedenis voor geplande boekingen.
    static let lookAheadMonths = 12
    /// Zoveel geplande boekingen staan onder "Binnenkort".
    static let upcomingLimit = 4
    /// Zoveel boekingen uit het verleden staan standaard in de lijst.
    static let historyLimit = 20
}

/// Tegels naast elkaar, even groot en over de volle breedte van het blok: twee op een iPhone, meer als er ruimte is.
/// (Een `LazyVGrid` met `.adaptive` liet op iPad en Mac de helft van de rij leeg.)
private struct PotTileGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        EqualSizeGrid(minimumColumnWidth: PotLayout.tileWidth, spacing: 8) { content }
    }
}

// MARK: - Alle spaarpotten

struct PotsPage: View {
    @Environment(AppStore.self) private var store
    @State private var showNew = false
    @State private var showPicker = false

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let hasInterest = d.pots.contains { InterestRules.isActive($0) }
        let received = PotInterestStats.received(in: d, asOf: today)
        PageScaffold(title: "Spaarpotten") {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: "Totaal gespaard", symbol: "tray.full.fill", tint: Theme.olive.opacity(0.3)) {
                    BigAmount(value: d.totalSaved(current: now, today: today))
                    PotTileGrid {
                        StatTile(title: "Deze maand erbij", value: Fmt.euro(d.savedTotal(in: now)))
                        if hasInterest {
                            StatTile(title: "Rente dit jaar", value: PotFormat.interest(received.thisYear),
                                     color: Theme.positive)
                        }
                        StatTile(title: "Aantal potten", value: "\(d.pots.count)")
                    }
                }

                if d.pots.isEmpty {
                    GlassBlock(title: "Nog geen spaarpotten") {
                        EmptyHint(symbol: "tray", title: "Maak je eerste spaarpot",
                                  message: "Geef elke pot een doel, bijvoorbeeld een buffer, een vakantie of een nieuwe laptop.",
                                  actionTitle: "Nieuwe spaarpot") { showNew = true }
                    }
                } else {
                    LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                        ForEach(d.pots) { pot in
                            PotRowCard(pot: pot)
                                .transition(.opacity)
                        }
                    }
                    ChipGrid {
                        ChipButton(title: "Nieuwe spaarpot", symbol: "plus") { showNew = true }
                        ChipButton(title: "Kies potten voor Home", symbol: "slider.horizontal.3") { showPicker = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showNew) { PotEditSheet(pot: nil) }
        .sheet(isPresented: $showPicker) { PotPickerSheet() }
    }
}

struct PotRowCard: View {
    @Environment(AppStore.self) private var store
    let pot: Pot

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let balance = d.potBalanceNow(pot.id, current: now, today: today)
        let progress = d.potProgress(pot.id, current: now, today: today)
        let color = Theme.color(pot.colorIndex)
        let hasInterest = InterestRules.isActive(pot)
        NavigationLink(value: Destination.pot(pot.id)) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: pot.symbol, color: color, size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(pot.name).font(.headline).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Fmt.euro(balance))
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            .animation(Theme.motion, value: balance)
                    }
                    if let goal = pot.goalAmount, let progress {
                        ProgressBar(progress: progress, tint: color)
                        HStack(spacing: 6) {
                            Text("Doel \(Fmt.euro(goal))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if hasInterest { PotInterestBadge(rate: pot.interestRate) }
                            Spacer(minLength: 4)
                            Text(Fmt.percent(progress, digits: 0))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color)
                                .contentTransition(.numericText())
                                .animation(Theme.motion, value: progress)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text("Geen doel ingesteld")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if hasInterest { PotInterestBadge(rate: pot.interestRate) }
                            Spacer(minLength: 0)
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Eén spaarpot

enum PotAction: String, Identifiable {
    case deposit, withdraw, setBalance, transfer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .deposit: return "Geld storten"
        case .withdraw: return "Geld opnemen"
        case .setBalance: return "Saldo aanpassen"
        case .transfer: return "Overboeken"
        }
    }

    var symbol: String {
        switch self {
        case .deposit: return "plus.circle.fill"
        case .withdraw: return "minus.circle.fill"
        case .setBalance: return "slider.horizontal.3"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
}

struct PotDetailPage: View {
    let potID: UUID
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var action: PotAction?
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var showAllHistory = false
    /// Een boeking waarvan het verwijderen eerst om een bevestiging vraagt, omdat er een andere helft bij hoort.
    @State private var pendingEntryDelete: PendingEntryDelete?

    private struct PendingEntryDelete: Identifiable {
        let id: UUID
        let message: String
    }
    /// Datum voor de tegel "Saldo op datum". Begint een maand vooruit.
    @State private var balanceDate = YearMonth.calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    var body: some View {
        if let pot = store.data.pot(potID) {
            content(pot)
        } else {
            PageScaffold(title: "Spaarpot") {
                EmptyHint(symbol: "questionmark.folder", title: "Deze spaarpot bestaat niet meer")
            }
        }
    }

    @ViewBuilder
    private func content(_ pot: Pot) -> some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let balance = d.potBalanceNow(pot.id, current: now, today: today)
        let progress = d.potProgress(pot.id, current: now, today: today)
        let timeline = d.potTimeline(pot.id, current: now.adding(PotLayout.lookAheadMonths), asOf: today)
        let planned = timeline.filter { $0.isPlanned }.sorted { $0.date < $1.date }
        let done = timeline.filter { !$0.isPlanned }
        let plannedCents = planned.filter { $0.date < now.endExclusive }.map { CentsMath.int($0.amount) }
        let plannedThisMonth = CentsMath.value(CentsMath.sum(plannedCents))
        let thisMonth = d.allocation(pot.id, in: now)
        let history = PotHistoryContext(pot: pot, data: d, through: now.adding(PotLayout.lookAheadMonths))
        // Een positief saldo (op centen) moet bij verwijderen een keuze krijgen: terugzetten of laten vervallen.
        let hasBalance = CentsMath.int(balance) > 0

        PageScaffold(title: pot.name) {
            VStack(spacing: Theme.pageSpacing) {
                balanceBlock(pot, balance: balance, progress: progress, plannedThisMonth: plannedThisMonth)

                LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                    moveBlock()
                    contributionBlock(pot, thisMonth: thisMonth)
                    interestBlock(pot, today: today)
                    dateBalanceBlock(pot, balance: balance, today: today)
                }

                historyBlock(planned: planned, done: done, history: history)

                ChipButton(title: "Spaarpot verwijderen", symbol: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(item: $action) { act in PotEntrySheet(pot: pot, action: act) }
        .sheet(isPresented: $showEdit) { PotEditSheet(pot: pot) }
        .confirmationDialog("Deze spaarpot verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            if hasBalance {
                Button("Saldo terugzetten op je rekening en verwijderen") {
                    let id = pot.id
                    let current = store.now
                    let moment = store.today
                    store.mutate { $0.deletePot(id, returningBalanceToBank: true, current: current, today: moment) }
                    dismiss()
                }
                Button("Verwijderen en saldo laten vervallen", role: .destructive) {
                    let id = pot.id
                    store.mutate { $0.deletePot(id) }
                    dismiss()
                }
            } else {
                Button("Verwijder \(pot.name)", role: .destructive) {
                    let id = pot.id
                    store.mutate { $0.deletePot(id) }
                    dismiss()
                }
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            if hasBalance {
                Text("Er staat \(Fmt.euro(balance)) op. Zet je het saldo terug, dan komt dat bedrag op je rekening. Laat je het vervallen, dan verdwijnt het uit je vermogen. De boekingen van deze pot verdwijnen in beide gevallen.")
            } else {
                Text("De boekingen van deze pot verdwijnen ook.")
            }
        }
    }

    // MARK: Blokken

    @ViewBuilder
    private func balanceBlock(_ pot: Pot, balance: Double, progress: Double?, plannedThisMonth: Double) -> some View {
        let color = Theme.color(pot.colorIndex)
        GlassBlock(title: "Saldo", symbol: pot.symbol, tint: color.opacity(0.28)) {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(progress: progress ?? 1, tint: color, lineWidth: 10)
                        .frame(width: 96, height: 96)
                    if let progress {
                        Text(Fmt.percent(progress, digits: 0))
                            .font(.headline)
                            .contentTransition(.numericText())
                            .animation(Theme.motion, value: progress)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    BigAmount(value: balance, font: .system(.title, design: .rounded, weight: .bold))
                    if let goal = pot.goalAmount {
                        Text("van \(Fmt.euro(goal))").font(.subheadline).foregroundStyle(.secondary)
                        Text(balance >= goal ? "Doel bereikt" : "Nog \(Fmt.euro(goal - balance)) te gaan")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(balance >= goal ? Theme.positive : color)
                    } else {
                        Text("Geen doel ingesteld").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if InterestRules.isActive(pot) {
                        PotInterestBadge(rate: pot.interestRate)
                    }
                }
                Spacer(minLength: 0)
            }
            if plannedThisMonth != 0 {
                Label("Nog deze maand gepland: \(PotFormat.signed(plannedThisMonth))", systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            goalText(pot, balance: balance)
        }
    }

    @ViewBuilder
    private func moveBlock() -> some View {
        GlassBlock(title: "Geld bewegen", symbol: "arrow.up.arrow.down") {
            ChipGrid {
                actionButton(.deposit)
                actionButton(.withdraw)
                actionButton(.setBalance)
                if store.data.pots.count > 1 { actionButton(.transfer) }
            }
        }
    }

    @ViewBuilder
    private func contributionBlock(_ pot: Pot, thisMonth: Double) -> some View {
        GlassBlock(title: "Inleg", symbol: "calendar") {
            PotTileGrid {
                StatTile(title: "Deze maand erbij", value: Fmt.euro(thisMonth))
                StatTile(title: "Standaard per maand", value: Fmt.euro(pot.monthlyContribution))
            }
            if let note = transferNote(pot, thisMonth: thisMonth) {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            ChipGrid {
                ChipButton(title: "Doel en instellingen", symbol: "pencil") { showEdit = true }
                // De inleg hoort bij deze maand: de verdeelpagina opent op de huidige maand, niet op de maand
                // waar je op Savings het laatst keek. `open` gebruikt het pad van de tab waar je nu bent.
                ChipButton(title: "Verdelen", symbol: "square.split.2x2") {
                    router.showCurrentMonth(store.now)
                    router.open(.distribute)
                }
            }
        }
    }

    @ViewBuilder
    private func interestBlock(_ pot: Pot, today: Date) -> some View {
        let d = store.data
        GlassBlock(title: "Rente", symbol: "percent", tint: Theme.positive.opacity(0.18)) {
            if InterestRules.isActive(pot) {
                let next = d.nextInterestPayment(for: pot.id, asOf: today)
                let received = PotInterestStats.received(in: d, potID: pot.id, asOf: today)
                PotTileGrid {
                    StatTile(title: "Rente per jaar", value: Fmt.percent(pot.interestRate, digits: 2))
                    StatTile(title: "Uitbetaling", value: pot.interestPayout.title)
                }
                StatTile(title: "Volgende uitbetaling",
                         value: next.map { PotFormat.longDate($0.date) } ?? "Nog niet bekend",
                         caption: next.map { ($0.isProjected ? "Ongeveer " : "") + PotFormat.interest($0.amount) }
                            ?? "Zodra er saldo op de pot staat")
                PotTileGrid {
                    StatTile(title: "Ontvangen dit jaar", value: PotFormat.interest(received.thisYear),
                             color: Theme.positive)
                    StatTile(title: "Ontvangen in totaal", value: PotFormat.interest(received.total),
                             color: Theme.positive)
                }
                Text(PotFormat.schedule(pot.interestPayout, firstMonth: pot.interestPayoutMonth, day: pot.interestPayoutDay))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ChipButton(title: "Rente aanpassen", symbol: "pencil") { showEdit = true }
            } else {
                Text("Geen rente ingesteld. Stel een percentage in en de app schrijft de rente zelf bij op de dag dat die wordt uitbetaald.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if d.potEntries.contains(where: { $0.potID == pot.id && $0.kind == .interest }) {
                    Text("Rente die al is bijgeschreven blijft in de geschiedenis staan. Klopt het saldo niet meer, pas het dan aan met Saldo aanpassen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ChipButton(title: "Rente instellen", symbol: "percent") { showEdit = true }
            }
        }
    }

    @ViewBuilder
    private func dateBalanceBlock(_ pot: Pot, balance: Double, today: Date) -> some View {
        let d = store.data
        // Vandaag is het saldo van nu (zoals bovenaan de pagina); een andere dag is het saldo aan het eind van die dag.
        let isToday = YearMonth.calendar.isDate(balanceDate, inSameDayAs: today)
        let atDate = isToday ? balance : d.potBalance(pot.id, asOf: balanceDate)
        let difference = CentsMath.value(CentsMath.int(atDate) - CentsMath.int(balance))
        let shownDifference = difference.rounded()
        GlassBlock(title: "Saldo op datum", symbol: "calendar.badge.clock") {
            DatePicker("Datum", selection: $balanceDate, in: dateRange(pot, today: today), displayedComponents: .date)
            PotTileGrid {
                StatTile(title: "Saldo op \(Fmt.date(balanceDate))", value: Fmt.euro(atDate))
                StatTile(title: "Verschil met nu", value: PotFormat.signed(difference),
                         color: shownDifference > 0 ? Theme.positive : (shownDifference < 0 ? Theme.negative : Color.primary))
            }
            ChipGrid(minimumWidth: 110) {
                quickDate("Vandaag", months: 0, today: today)
                quickDate("Over 3 maanden", months: 3, today: today)
                quickDate("Over 1 jaar", months: 12, today: today)
                quickDate("Over 5 jaar", months: 60, today: today)
            }
            Text("Inleg, uitgaven uit de pot en rente tellen mee vanaf de dag waarop ze gepland staan. Voor een dag na vandaag is het saldo dat aan het eind van die dag.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func historyBlock(planned: [PotTimelineItem], done: [PotTimelineItem], history: PotHistoryContext) -> some View {
        let upcoming = Array(planned.prefix(PotLayout.upcomingLimit))
        let shown = showAllHistory ? done : Array(done.prefix(PotLayout.historyLimit))
        GlassBlock(title: "Waar is het geld heen gegaan?", symbol: "clock.arrow.circlepath") {
            if upcoming.isEmpty && done.isEmpty {
                Text("Nog geen boekingen.").font(.footnote).foregroundStyle(.secondary)
            }
            if !upcoming.isEmpty {
                Text("Binnenkort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                timelineList(upcoming, history: history)
            }
            if !shown.isEmpty {
                if !upcoming.isEmpty {
                    Text("Tot nu toe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                timelineList(shown, history: history)
            }
            if done.count > PotLayout.historyLimit {
                ChipButton(title: showAllHistory ? "Toon minder" : "Toon alle \(done.count) boekingen",
                           symbol: showAllHistory ? "chevron.up" : "chevron.down") {
                    withAnimation(Theme.motion) { showAllHistory.toggle() }
                }
            }
        }
        // Op dit blok (niet op de hele pagina), zodat het niet botst met de bevestiging voor "Spaarpot verwijderen".
        .confirmationDialog("Boeking verwijderen?",
                            isPresented: Binding(get: { pendingEntryDelete != nil },
                                                 set: { if !$0 { pendingEntryDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingEntryDelete) { pending in
            Button("Verwijder", role: .destructive) { deleteEntry(pending.id) }
            Button("Annuleren", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    // MARK: Onderdelen

    private func timelineList(_ items: [PotTimelineItem], history: PotHistoryContext) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 0) {
                    timelineRow(item, history: history)
                    if item.id != items.last?.id { Divider() }
                }
                .transition(.opacity)
            }
        }
    }

    private func actionButton(_ a: PotAction) -> some View {
        ChipButton(title: a.title, symbol: a.symbol) { action = a }
    }

    private func quickDate(_ title: String, months: Int, today: Date) -> some View {
        ChipButton(title: title) {
            withAnimation(Theme.motion) {
                balanceDate = YearMonth.calendar.date(byAdding: .month, value: months, to: today) ?? today
            }
        }
    }

    /// De datums die je kunt kiezen: vanaf de start van de pot tot 50 jaar vooruit.
    private func dateRange(_ pot: Pot, today: Date) -> ClosedRange<Date> {
        let cal = YearMonth.calendar
        let lower = min(pot.startMonth.firstDay, cal.startOfDay(for: today))
        let upper = cal.date(byAdding: .year, value: 50, to: today) ?? today.addingTimeInterval(50 * 365 * 86_400)
        return lower...upper
    }

    /// "De inleg gaat op de 25e naar deze pot, je salarisdag."
    private func transferNote(_ pot: Pot, thisMonth: Double) -> String? {
        let d = store.data
        let now = store.now
        guard thisMonth != 0 || pot.monthlyContribution != 0 else { return nil }
        let day = d.transferDay(for: pot.id, in: now)
        let usesPayDay = pot.transferDay == nil && d.months[now.key]?.transferDay == nil
        let base = "De inleg gaat op \(PotFormat.dayName(day)) naar deze pot"
        return usesPayDay ? base + ", je salarisdag." : base + "."
    }

    @ViewBuilder
    private func goalText(_ pot: Pot, balance: Double) -> some View {
        let d = store.data
        if let goal = pot.goalAmount, goal > 0 {
            if balance >= goal {
                EmptyView()
            } else if let month = d.potGoalMonth(pot.id, current: store.now) {
                Label("Bij je geplande inleg is het doel bereikt in \(Fmt.month(month)).", systemImage: "flag.checkered")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Stel een maandelijkse inleg in om te zien wanneer je er bent.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let date = pot.goalDate {
                let months = store.now.months(to: YearMonth(date: date))
                if months > 0 && balance < goal {
                    let needed = ((goal - balance) / Double(months)).cents
                    Label("Voor \(Fmt.month(YearMonth(date: date))) heb je \(Fmt.euro(needed)) per maand nodig.", systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Regel in de geschiedenis

    private func timelineRow(_ item: PotTimelineItem, history: PotHistoryContext) -> some View {
        HStack(spacing: 10) {
            SymbolBadge(symbol: rowSymbol(item), color: rowColor(item), size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(rowSubtitle(item, history: history))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(rowAmount(item))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.amount >= 0 ? Theme.positive : Theme.negative)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            if let entryID = history.deletableEntryID(for: item) {
                Menu {
                    Button("Verwijder boeking", role: .destructive) { requestDelete(entryID) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.vertical, 8)
        .opacity(item.isPlanned ? 0.75 : 1)
    }

    /// Een losse boeking verdwijnt meteen. Hoort ze bij een overboeking, dan vraagt de app eerst om bevestiging
    /// en zegt ze wat er verdwijnt.
    private func requestDelete(_ entryID: UUID) {
        if let message = deleteMessage(forEntry: entryID) {
            pendingEntryDelete = PendingEntryDelete(id: entryID, message: message)
        } else {
            deleteEntry(entryID)
        }
    }

    private func deleteEntry(_ entryID: UUID) {
        withAnimation(Theme.motion) {
            store.mutate { $0.deletePotEntry(entryID) }
        }
    }

    /// De tekst voor de bevestiging, of nil als de boeking los staat (dan is verwijderen veilig).
    private func deleteMessage(forEntry id: UUID) -> String? {
        let d = store.data
        guard let entry = d.potEntries.first(where: { $0.id == id }) else { return nil }
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

    private func rowColor(_ item: PotTimelineItem) -> Color {
        switch item.kind {
        case .interest: return Theme.positive
        case .expense: return Theme.negative
        case .allocation: return Theme.accent
        case .manual: return item.amount >= 0 ? Theme.positive : Theme.negative
        }
    }

    private func rowSubtitle(_ item: PotTimelineItem, history: PotHistoryContext) -> String {
        var parts = [Fmt.date(item.date)]
        if item.kind == .interest {
            // De notitie van de rekenmotor negeren: "Verwacht" klopt niet voor rente uit het verleden, en het
            // percentage in de opgeslagen notitie is op één decimaal afgerond (de badge toont er twee).
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

// MARK: - Sheets

struct PotEntrySheet: View {
    let pot: Pot
    let action: PotAction

    @Environment(AppStore.self) private var store
    @State private var amount = 0.0
    @State private var note = ""
    @State private var targetID: UUID?
    @State private var viaBank = false

    private var others: [Pot] { store.data.pots.filter { $0.id != pot.id } }

    var body: some View {
        let balance = store.data.potBalanceNow(pot.id, current: store.now, today: store.today)
        SheetScaffold(title: action.title, canSave: canSave(balance: balance), onSave: { save() }) {
            Section {
                switch action {
                case .deposit, .withdraw:
                    NumberRow(title: "Bedrag", value: $amount)
                case .setBalance:
                    NumberRow(title: "Nieuw saldo", value: $amount)
                case .transfer:
                    NumberRow(title: "Bedrag", value: $amount)
                    Picker("Naar", selection: $targetID) {
                        ForEach(others) { other in Text(other.name).tag(other.id as UUID?) }
                    }
                }
                if action != .transfer {
                    TextField("Waarvoor? (optioneel)", text: $note)
                }
                if action == .deposit || action == .withdraw {
                    Toggle(action == .deposit ? "Van de bankrekening" : "Naar de bankrekening", isOn: $viaBank)
                }
            } header: {
                Text("Huidig saldo \(Fmt.euro(balance))")
            } footer: {
                if action == .setBalance {
                    Text("Het verschil wordt als correctie in de geschiedenis gezet.")
                }
            }
        }
        .onAppear {
            if action == .setBalance { amount = balance }
            if targetID == nil { targetID = others.first?.id }
        }
    }

    private func canSave(balance: Double) -> Bool {
        switch action {
        case .deposit: return amount > 0
        case .withdraw: return amount > 0 && amount <= balance + 0.005
        case .setBalance: return amount >= 0
        case .transfer: return amount > 0 && amount <= balance + 0.005 && targetID != nil
        }
    }

    private func save() {
        let id = pot.id
        let a = amount
        let n = note.trimmingCharacters(in: .whitespaces)
        let now = store.now
        let today = store.today
        let target = targetID
        switch action {
        case .deposit:
            if viaBank {
                store.mutate { $0.transferBankToPot(potID: id, amount: a, note: n) }
            } else {
                store.mutate { $0.addPotEntry(potID: id, amount: a, kind: .deposit, note: n) }
            }
        case .withdraw:
            if viaBank {
                store.mutate { $0.transferPotToBank(potID: id, amount: a, note: n) }
            } else {
                store.mutate { $0.addPotEntry(potID: id, amount: -a, kind: .withdrawal, note: n) }
            }
        case .setBalance:
            // Het verschil wordt gemeten tegen het saldo van nu: precies het getal dat je zag.
            store.mutate { $0.setPotBalance(id, to: a, current: now, note: n, asOf: today) }
        case .transfer:
            if let target { store.mutate { $0.transfer(from: id, to: target, amount: a) } }
        }
    }
}

struct PotEditSheet: View {
    let pot: Pot?

    @Environment(AppStore.self) private var store
    @State private var loaded = false
    /// Vaste id voor een nieuwe pot, zodat de voorvertoning van de rente en het bewaren dezelfde pot zijn.
    @State private var draftID = UUID()
    @State private var name = ""
    @State private var symbol = "banknote"
    @State private var colorIndex = 0
    @State private var goal: Double?
    @State private var goalDate: Date?
    @State private var monthly = 0.0
    @State private var opening = 0.0
    @State private var transferDay: Int?
    // Rente
    @State private var rate = 0.0
    @State private var payout: InterestPayout = .yearly
    @State private var payoutDay = 1
    @State private var payoutMonth = 1

    /// Wat de voorvertoning van de rente laat zien.
    private struct InterestPreview {
        var text: String
        var isActive: Bool
        /// Melding als er door deze wijziging rente uit eerdere maanden wordt bijgeschreven.
        var catchUp: String?
    }

    private var rateIsValid: Bool {
        rate.isFinite && rate >= 0 && rate <= 1
    }

    var body: some View {
        SheetScaffold(title: pot == nil ? "Nieuwe spaarpot" : "Spaarpot aanpassen",
                      canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && rateIsValid,
                      onSave: { save() }) {
            Section("Naam") {
                TextField("Bijvoorbeeld Vakantie", text: $name)
            }
            Section("Uiterlijk") {
                SymbolChoiceRow(symbol: $symbol, color: Theme.color(colorIndex))
                ColorChoiceRow(index: $colorIndex)
            }
            Section {
                OptionalNumberRow(title: "Doelbedrag", value: $goal, defaultValue: 1000)
                OptionalDateRow(title: "Streefdatum", date: $goalDate)
            } header: {
                Text("Doel")
            } footer: {
                Text("Met een doelbedrag laat de app zien hoe ver je bent en wanneer je er bent.")
            }
            Section {
                NumberRow(title: "Standaard inleg per maand", value: $monthly)
                Toggle("Eigen overschrijfdag inleg", isOn: animated(Binding(
                    get: { transferDay != nil },
                    set: { on in transferDay = on ? store.data.salaryDay() : nil }
                )))
                if let day = transferDay {
                    Stepper(value: Binding(get: { day }, set: { transferDay = $0 }), in: 1...31) {
                        HStack {
                            Text("Overschrijfdag inleg")
                            Spacer()
                            Text(PotFormat.dayName(day)).foregroundStyle(.secondary)
                        }
                    }
                }
                if pot == nil {
                    NumberRow(title: "Beginsaldo", value: $opening)
                }
            } header: {
                Text("Geld")
            } footer: {
                moneyFooter
            }
            interestSection
        }
        .onAppear { load() }
    }

    // MARK: Rente

    @ViewBuilder
    private var interestSection: some View {
        let preview = interestPreview()
        Section {
            NumberRow(title: "Rentepercentage per jaar", value: $rate, unit: .percent)
            Picker("Uitbetaling", selection: payoutBinding) {
                ForEach(InterestPayout.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Stepper(value: $payoutDay, in: 1...31) {
                HStack {
                    Text("Dag van de maand")
                    Spacer()
                    Text("\(payoutDay)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if payout != .monthly {
                // Bij een kwartaal of half jaar kies je de eerste uitbetaling van het jaar (de rest volgt): januari t/m maart of juni.
                Picker(payout == .yearly ? "Maand van uitbetaling" : "Eerste uitbetaling in", selection: $payoutMonth) {
                    ForEach(PotFormat.firstMonthChoices(for: payout), id: \.self) { number in
                        Text(PotFormat.monthName(number)).tag(number)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: preview.isActive ? "calendar.badge.clock" : "percent")
                    .foregroundStyle(preview.isActive ? Theme.positive : Color.secondary)
                Text(preview.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .animation(Theme.quickMotion, value: preview.text)
        } header: {
            Text("Rente")
        } footer: {
            interestFooter(preview)
        }
    }

    private func interestFooter(_ preview: InterestPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !rateIsValid {
                Text("Vul een rente tussen 0% en 100% in.").foregroundStyle(Theme.negative)
            } else if rate > 0 {
                Text(PotFormat.schedule(payout, firstMonth: payoutMonth, day: payoutDay))
                Text("De app schrijft de rente zelf bij op die dag. Het bedrag is een verwachting: per maand telt een twaalfde van het percentage over je saldo op de eerste van de maand.")
                if let catchUp = preview.catchUp {
                    Text(catchUp).foregroundStyle(Theme.warning)
                }
            } else {
                Text("Vul een percentage in om rente te krijgen. De app schrijft de rente dan zelf bij op de dag die je kiest.")
            }
        }
    }

    private var moneyFooter: some View {
        let payDay = store.data.salaryDay()
        return VStack(alignment: .leading, spacing: 6) {
            Text("De standaard inleg komt elke maand in je verdeling; die kun je per maand aanpassen.")
            Text("Op de overschrijfdag gaat de inleg naar de pot en telt hij mee in het saldo. Zonder eigen dag is dat je salarisdag (\(PotFormat.dayName(payDay))). Een verdeling die je voor één maand maakt, kan een eigen dag hebben; die gaat voor.")
        }
    }

    /// Verwachte volgende uitbetaling met de instellingen zoals ze nu in het scherm staan.
    private func interestPreview() -> InterestPreview {
        guard rateIsValid else {
            return InterestPreview(text: "Controleer het rentepercentage", isActive: false, catchUp: nil)
        }
        guard rate > 0 else {
            return InterestPreview(text: "Geen rente ingesteld", isActive: false, catchUp: nil)
        }
        let today = store.today
        let draft = draftPot()
        // Reken op een kopie van de gegevens, na precies dezelfde stappen als bij bewaren.
        var trial = store.data
        commit(draft, to: &trial, now: store.now, today: today)
        guard let next = trial.nextInterestPayment(for: draft.id, asOf: today) else {
            return InterestPreview(text: "Volgende uitbetaling: zodra er saldo op de pot staat", isActive: false, catchUp: nil)
        }
        return InterestPreview(text: "Volgende uitbetaling: " + PotFormat.nextPayment(next),
                               isActive: true,
                               catchUp: catchUpNote(trial: trial, draft: draft, today: today))
    }

    /// Een pot die al langer bestaat krijgt de rente ook over eerdere maanden. Laat dat vooraf weten.
    private func catchUpNote(trial: FinanceData, draft: Pot, today: Date) -> String? {
        guard let existing = pot else { return nil }
        let from = existing.startMonth.firstDay
        // Alles wat nu al aan de beurt was (opgeslagen of verwacht), tegenover wat er na bewaren aan de beurt is.
        // In `trial` is de rente al bijgeschreven, daarom telt hier niet mee of een uitbetaling nog "verwacht" is.
        let before = store.data.interestPayments(for: existing.id, from: from, to: today, asOf: today)
            .filter { $0.date <= today }
        let after = trial.interestPayments(for: draft.id, from: from, to: today, asOf: today)
            .filter { $0.date <= today }
        let known = Set(before.map { $0.id })
        let added = after.filter { !known.contains($0.id) }
        guard !added.isEmpty else { return nil }
        let cents = CentsMath.sum(added.map { CentsMath.int($0.amount) })
        let count = added.count == 1 ? "1 uitbetaling" : "\(added.count) uitbetalingen"
        return "Deze pot bestaat al langer. De app schrijft daarom ook de rente van eerdere maanden bij: \(count), samen ongeveer \(PotFormat.interest(CentsMath.value(cents)))."
    }

    // MARK: Laden en bewaren

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let pot {
            name = pot.name
            symbol = pot.symbol
            colorIndex = pot.colorIndex
            goal = pot.goalAmount
            goalDate = pot.goalDate
            monthly = pot.monthlyContribution
            transferDay = pot.transferDay
            rate = pot.interestRate
            payout = pot.interestPayout
            payoutDay = min(max(pot.interestPayoutDay, 1), 31)
            payoutMonth = PotFormat.firstMonth(pot.interestPayoutMonth, for: pot.interestPayout)
        } else {
            colorIndex = store.data.pots.count % Theme.palette.count
        }
    }

    /// De pot zoals hij na bewaren is: voor de voorvertoning en om te bewaren.
    private func draftPot() -> Pot {
        var p: Pot
        if let existing = pot {
            p = existing
        } else {
            p = Pot(name: name, symbol: symbol, colorIndex: colorIndex,
                    goalAmount: goal, goalDate: goalDate,
                    monthlyContribution: monthly.cents, startMonth: store.now)
            p.id = draftID
        }
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.symbol = symbol
        p.colorIndex = colorIndex
        p.goalAmount = goal
        p.goalDate = goalDate
        p.monthlyContribution = monthly.cents
        p.transferDay = transferDay
        // Afgerond op 0,001%, zodat een getypt percentage geen afrondruis meekrijgt.
        p.interestRate = (rate * 100_000).rounded() / 100_000
        p.interestPayout = payout
        p.interestPayoutDay = payoutDay
        p.interestPayoutMonth = PotFormat.firstMonth(payoutMonth, for: payout)
        return p
    }

    private func save() {
        let saved = draftPot()
        let now = store.now
        let today = store.today
        store.mutate { commit(saved, to: &$0, now: now, today: today) }
    }

    /// De stappen van bewaren, ook gebruikt door de voorvertoning van de rente.
    private func commit(_ draft: Pot, to data: inout FinanceData, now: YearMonth, today: Date) {
        if pot == nil {
            data.addPot(draft, openingBalance: opening)
        } else {
            // Eerst de rente vastleggen die al aan de beurt was, met de oude instellingen. Anders wordt die achteraf
            // met het nieuwe percentage, de nieuwe dag of de nieuwe inleg berekend, terwijl in die maanden de oude gold.
            data.applyDueInterest(upTo: today)
            data.updatePot(draft, current: now)
        }
        // Wat na deze wijziging aan de beurt is (bijvoorbeeld bij rente die je net hebt aangezet) schrijft de app nu bij.
        data.applyDueInterest(upTo: today)
    }

    /// Bij een andere uitbetaling blijft de eerste uitbetaalmaand binnen het nieuwe ritme.
    private var payoutBinding: Binding<InterestPayout> {
        Binding(
            get: { payout },
            set: { newValue in
                withAnimation(Theme.motion) {
                    payout = newValue
                    payoutMonth = PotFormat.firstMonth(payoutMonth, for: newValue)
                }
            }
        )
    }

    /// Dezelfde binding, maar een wijziging beweegt zacht (rijen die verschijnen of verdwijnen).
    private func animated<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                withAnimation(Theme.motion) { binding.wrappedValue = newValue }
            }
        )
    }
}
