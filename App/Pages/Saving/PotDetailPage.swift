import SwiftUI

// De pagina van één spaarpot: Saldo (met het verloop), Komende boekingen, Inleg en rente, Geschiedenis en Saldo op datum, met
// onderaan Verwijderen. Elk blok is een eigen sectie in een kleine view, zodat de pagina overzichtelijk blijft.

struct PotDetailPage: View {
    let potID: UUID
    @Environment(AppStore.self) private var store
    @State private var sheet: PotDetailSheet?

    /// De bladen die deze pagina opent, in een `.sheet(item:)`.
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
            PotBalanceSection(pot: pot, onAction: { action in sheet = .entry(action) })
            PotUpcomingSection(pot: pot)
            PotContributionSection(pot: pot, onEdit: { sheet = .edit })
            PotHistorySection(pot: pot)
            PotDateBalanceSection(pot: pot)
            PotDeleteSection(pot: pot)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item, pot: pot)
        }
    }

    /// "Geld bewegen" en "Bewerken" in het menu van de werkbalk.
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

// MARK: - Saldo en verloop

/// De hero van de pagina: het saldo van vandaag met de voortgang naar het doel, het verloop per maand en de knoppen Storten en Opnemen.
struct PotBalanceSection: View {
    let pot: Pot
    let onAction: (PotAction) -> Void
    @Environment(AppStore.self) private var store
    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 96

    init(pot: Pot, onAction: @escaping (PotAction) -> Void) {
        self.pot = pot
        self.onAction = onAction
    }

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        // "Saldo vandaag" is overal hetzelfde getal: dat van de tegel op het Overzicht en van de pagina Spaarpotten.
        let balance = d.potBalanceNow(pot.id, current: now, today: today)
        let endOfMonth = d.potBalance(pot.id, at: now)
        let progress = d.potProgress(pot.id, current: now, today: today)
        Section {
            summaryRow(balance: balance, endOfMonth: endOfMonth, progress: progress)
            chartRow(d, now: now, today: today)
            ActionGroup {
                ActionButton(title: "Storten", symbol: "plus.circle", prominent: true) { onAction(.deposit) }
                ActionButton(title: "Opnemen", symbol: "minus.circle") { onAction(.withdraw) }
            }
        } header: {
            SectionHeader("Saldo", symbol: pot.symbol)
        }
    }

    // MARK: Saldo, doel en planning

    private func summaryRow(balance: Double, endOfMonth: Double, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    ring(balance: balance, progress: progress)
                    amounts(balance: balance)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ring(balance: balance, progress: progress)
                    amounts(balance: balance)
                }
            }
            plannedNote(balance: balance, endOfMonth: endOfMonth)
            goalNotes(balance: balance)
        }
    }

    private func ring(balance: Double, progress: Double?) -> some View {
        let color = Theme.color(pot.colorIndex)
        return ZStack {
            ProgressMeter(value: progress, tint: color, style: .ring(lineWidth: 10), label: "Voortgang \(pot.name)",
                          valueText: spokenProgress(balance: balance, progress: progress))
            if let progress {
                Text(Fmt.percent(progress, digits: 0))
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animated(by: progress)
            } else {
                Image(systemName: pot.symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    private func spokenProgress(balance: Double, progress: Double?) -> String {
        guard let progress, let goal = pot.goalAmount, goal > 0 else { return "Geen doel ingesteld" }
        return PotFormat.progressSpeech(balance: balance, goal: goal, progress: progress)
    }

    private func amounts(balance: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saldo vandaag")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            BigAmount(value: balance, font: Theme.titleAmount, label: "Saldo vandaag")
            goalLines(balance: balance)
            if InterestRules.isActive(pot) {
                PotInterestBadge(rate: pot.interestRate)
            }
        }
    }

    @ViewBuilder
    private func goalLines(balance: Double) -> some View {
        if let goal = pot.goalAmount, goal > 0 {
            Text("van \(Fmt.euro(goal))")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text(PotFormat.goalStatus(balance: balance, goal: goal))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(balance >= goal ? Theme.positive : Theme.textSecondary)
        } else {
            Text("Geen doel ingesteld")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Wat er deze maand nog bij of af gaat: het verschil tussen het saldo aan het eind van de maand en het saldo van nu.
    @ViewBuilder
    private func plannedNote(balance: Double, endOfMonth: Double) -> some View {
        let planned = CentsMath.value(CentsMath.int(endOfMonth) - CentsMath.int(balance))
        if planned != 0 {
            let monthName = Fmt.monthNames[store.now.month - 1]
            Label("Nog deze maand gepland: \(PotFormat.signed(planned)). Verwacht eind \(monthName): \(Fmt.euro(endOfMonth)).",
                  systemImage: "calendar")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func goalNotes(balance: Double) -> some View {
        if let goal = pot.goalAmount, goal > 0 {
            if balance < goal {
                reachNote
            }
            if let date = pot.goalDate {
                neededNote(goal: goal, balance: balance, date: date)
            }
        }
    }

    @ViewBuilder
    private var reachNote: some View {
        if let month = store.data.potGoalMonth(pot.id, current: store.now) {
            Label("Bij je geplande inleg is het doel bereikt in \(Fmt.month(month)).", systemImage: "flag.checkered")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        } else {
            Label("Stel een maandelijkse inleg in om te zien wanneer je er bent.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func neededNote(goal: Double, balance: Double, date: Date) -> some View {
        let months = store.now.months(to: YearMonth(date: date))
        if months > 0 && balance < goal {
            // Hetzelfde rekenwerk als bij de doelen (`GoalMath`): naar boven afgerond op hele euro's, met de rente van de pot als
            // die er is, zodat het bedrag het doel zeker haalt.
            let needed = GoalMath.wholeMonthlyToReach(target: goal, start: balance,
                                                      annualReturn: InterestRules.isActive(pot) ? pot.interestRate : 0,
                                                      months: months)
            Label("Voor \(Fmt.month(YearMonth(date: date))) heb je \(Fmt.euro(needed)) per maand nodig.", systemImage: "calendar.badge.clock")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Verloop

    private func chartRow(_ d: FinanceData, now: YearMonth, today: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verloop")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            TrendChart(model: PotTrend.model(d, potID: pot.id, current: now, today: today), size: .regular, nonNegative: true)
        }
    }
}

// MARK: - Komende boekingen

/// De boekingen van de komende 30 dagen (inleg, uitgaven uit deze pot, rente) met het verwachte saldo na elke boeking. Ze komen
/// uit hetzelfde dagoverzicht als "Dag voor dag"; wat vandaag valt zit al in het saldo van vandaag.
struct PotUpcomingSection: View {
    let pot: Pot
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let balance = d.potBalanceNow(pot.id, current: now, today: today)
        let items = PotUpcoming.items(d, potID: pot.id, current: now, today: today)
        Section {
            if let last = items.last {
                FigureRow {
                    StatTile(title: "Saldo vandaag", value: Fmt.euro(balance))
                    StatTile(title: "Over \(PotUpcoming.horizonDays) dagen", value: Fmt.euro(last.balanceAfter),
                             color: Theme.accent, caption: "Verwacht")
                }
                ForEach(items) { item in
                    upcomingRow(item)
                }
                Text("Het saldo erna is wat er na die boeking in de pot zit, te beginnen bij het saldo van vandaag. Elke boeking telt mee op zijn eigen dag.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("De komende \(PotUpcoming.horizonDays) dagen staat er niets gepland voor deze pot. Het saldo blijft \(Fmt.euro(balance)).")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            // Dezelfde boekingen staan, samen met die van je rekening, op de pagina Dag voor dag.
            NavigationRow(title: "Dag voor dag", symbol: "calendar", domain: .money, destination: .cashflow)
        } header: {
            SectionHeader("Komende boekingen", symbol: "calendar.badge.clock", domain: .saving)
        }
    }

    private func upcomingRow(_ item: PotUpcomingItem) -> some View {
        AmountRow(title: item.title,
                  value: PotFormat.bookingAmount(item.amount, isInterest: item.kind == .interest),
                  detail: upcomingDetail(item),
                  color: item.amount >= 0 ? Theme.positive : Theme.negative,
                  symbol: upcomingSymbol(item))
    }

    /// "ma 25 okt · over 12 dagen · 10% van je salaris · saldo erna € 1.232".
    private func upcomingDetail(_ item: PotUpcomingItem) -> String {
        var parts = [DayText.weekdayShort(item.date), PotFormat.daysAhead(item.daysAhead)]
        if let detail = item.detail { parts.append(detail) }
        parts.append("saldo erna \(Fmt.euro(item.balanceAfter))")
        return parts.joined(separator: " · ")
    }

    private func upcomingSymbol(_ item: PotUpcomingItem) -> String {
        switch item.kind {
        case .interest: return "percent"
        case .expense: return "cart.fill"
        default: return "calendar"
        }
    }
}

// MARK: - Inleg en rente

struct PotContributionSection: View {
    let pot: Pot
    let onEdit: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    init(pot: Pot, onEdit: @escaping () -> Void) {
        self.pot = pot
        self.onEdit = onEdit
    }

    var body: some View {
        Section {
            contributionRow
            interestRow
        } header: {
            SectionHeader("Inleg en rente", symbol: "percent", domain: .saving)
        }
    }

    // MARK: Inleg

    private var contributionRow: some View {
        let info = ContributionInfo(store.data, id: pot.id, month: store.now)
        return VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Inleg")
                .font(.subheadline.weight(.semibold))
            // De opbouw van de inleg: de standaardregel (een bedrag of een percentage van je inkomen), wat daar in deze maand uit
            // volgt en eventuele afwijkingen. Alles uit de rekenmotor (`ContributionInfo`).
            if let info {
                ContributionSummary(info: info)
            }
            if let note = info?.transferNote(to: "naar deze pot") {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ActionGroup {
                ActionButton(title: "Bewerken", symbol: "pencil") { onEdit() }
                // De inleg hoort bij deze maand: de verdeelpagina opent op de huidige maand, niet op de maand waar je op de
                // Maand-tab het laatst keek.
                ActionButton(title: "Verdelen", symbol: "square.split.2x2") {
                    router.showCurrentMonth(store.now)
                    router.open(.distribute)
                }
            }
        }
    }

    // MARK: Rente

    private var interestRow: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Rente")
                .font(.subheadline.weight(.semibold))
            if InterestRules.isActive(pot) {
                activeInterest
            } else {
                noInterest
            }
        }
    }

    @ViewBuilder
    private var activeInterest: some View {
        let d = store.data
        let today = store.today
        let next = d.nextInterestPayment(for: pot.id, asOf: today)
        let received = PotInterestStats.received(in: d, potID: pot.id, asOf: today)
        FigureRow {
            StatTile(title: "Rente per jaar", value: Fmt.percent(pot.interestRate, digits: 2))
            StatTile(title: "Uitbetaling", value: pot.interestPayout.title)
        }
        StatTile(title: "Volgende uitbetaling",
                 value: next.map { PotFormat.longDate($0.date) } ?? "Nog niet bekend",
                 caption: next.map { ($0.isProjected ? "Ongeveer " : "") + PotFormat.interest($0.amount) }
                    ?? "Zodra er saldo op de pot staat")
        FigureRow {
            StatTile(title: "Ontvangen dit jaar", value: PotFormat.interest(received.thisYear), color: Theme.positive)
            StatTile(title: "Ontvangen in totaal", value: PotFormat.interest(received.total), color: Theme.positive)
        }
        Text(PotFormat.schedule(pot.interestPayout, firstMonth: pot.interestPayoutMonth, day: pot.interestPayoutDay))
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private var noInterest: some View {
        Text("Geen rente ingesteld. Stel een percentage in en de app schrijft de rente zelf bij op de dag dat die wordt uitbetaald.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        if store.data.potEntries.contains(where: { $0.potID == pot.id && $0.kind == .interest }) {
            Text("Rente die al is bijgeschreven blijft in de geschiedenis staan. Klopt het saldo niet meer, pas het dan aan met Saldo aanpassen.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        ActionButton(title: "Rente instellen", symbol: "percent") { onEdit() }
    }
}

// MARK: - Geschiedenis

/// Alles wat het saldo veranderde, tot en met vandaag. Een boeking die je mag verwijderen heeft swipe en contextmenu; hoort ze bij
/// een overboeking, dan vraagt de rij eerst om bevestiging en zegt ze wat er verdwijnt.
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
        } header: {
            SectionHeader("Geschiedenis", symbol: "clock.arrow.circlepath", domain: .saving)
        }
    }

    @ViewBuilder
    private func historyRow(_ item: PotTimelineItem, history: PotHistoryContext) -> some View {
        let row = AmountRow(title: item.title, value: rowAmount(item), detail: rowSubtitle(item, history: history),
                            color: item.amount >= 0 ? Theme.positive : Theme.negative, symbol: rowSymbol(item))
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
