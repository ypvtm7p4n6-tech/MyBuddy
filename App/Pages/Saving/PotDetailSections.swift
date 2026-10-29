import SwiftUI

// De eerste secties onder de kop van een spaarpot: Verloop (de grafiek met wat er nog gepland is), Komende boekingen en Inleg en
// rente. Geschiedenis, Saldo op datum en Verwijderen staan in PotHistorySections.swift.

// MARK: - Verloop

/// Een korte notitie onder de grafiek: een symbool en een zin.
private struct PotNote: Identifiable {
    let id: String
    let symbol: String
    let text: String
}

/// Het verloop van de pot per maand (de grafiek) met eronder wat er deze maand nog gepland is en wat het doel vraagt. Het saldo
/// zelf, de voortgang, de rente en de inleg staan in de kop van de pagina.
struct PotTrendSection: View {
    let pot: Pot
    @Environment(AppStore.self) private var store

    init(pot: Pot) {
        self.pot = pot
    }

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        let balance = d.potBalanceNow(pot.id, current: now, today: today)
        let endOfMonth = d.potBalance(pot.id, at: now)
        Section {
            TrendChart(model: PotTrend.model(d, potID: pot.id, current: now, today: today), size: .regular, nonNegative: true)
            ForEach(notes(balance: balance, endOfMonth: endOfMonth)) { note in
                Label(note.text, systemImage: note.symbol)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            SectionHeader("Verloop", symbol: "chart.line.uptrend.xyaxis", domain: .saving)
        }
    }

    // MARK: Notities

    private func notes(balance: Double, endOfMonth: Double) -> [PotNote] {
        var result: [PotNote] = []
        if let planned = plannedNote(balance: balance, endOfMonth: endOfMonth) {
            result.append(planned)
        }
        if let goal = pot.goalAmount, goal > 0 {
            if balance < goal, let reach = reachNote() {
                result.append(reach)
            }
            if let date = pot.goalDate, let needed = neededNote(goal: goal, balance: balance, date: date) {
                result.append(needed)
            }
        }
        return result
    }

    /// Wat er deze maand nog bij of af gaat: het verschil tussen het saldo aan het eind van de maand en het saldo van nu.
    private func plannedNote(balance: Double, endOfMonth: Double) -> PotNote? {
        let planned = CentsMath.value(CentsMath.int(endOfMonth) - CentsMath.int(balance))
        guard planned != 0 else { return nil }
        let monthName = Fmt.monthNames[store.now.month - 1]
        let text = "Nog deze maand gepland: \(PotFormat.signed(planned)). Verwacht eind \(monthName): \(Fmt.euro(endOfMonth))."
        return PotNote(id: "planned", symbol: "calendar", text: text)
    }

    /// Wanneer het doel bereikt is bij de geplande inleg, of wat je moet doen om dat te zien.
    private func reachNote() -> PotNote? {
        if let month = store.data.potGoalMonth(pot.id, current: store.now) {
            return PotNote(id: "reach", symbol: "flag.checkered",
                           text: "Bij je geplande inleg is het doel bereikt in \(Fmt.month(month)).")
        }
        return PotNote(id: "reach", symbol: "info.circle",
                       text: "Stel een maandelijkse inleg in om te zien wanneer je er bent.")
    }

    /// Wat je per maand nodig hebt om het doel op de gekozen datum te halen. Hetzelfde rekenwerk als bij de doelen (`GoalMath`):
    /// naar boven afgerond op hele euro's, met de rente van de pot als die er is, zodat het bedrag het doel zeker haalt.
    private func neededNote(goal: Double, balance: Double, date: Date) -> PotNote? {
        let months = store.now.months(to: YearMonth(date: date))
        guard months > 0 && balance < goal else { return nil }
        let needed = GoalMath.wholeMonthlyToReach(target: goal, start: balance,
                                                  annualReturn: InterestRules.isActive(pot) ? pot.interestRate : 0,
                                                  months: months)
        return PotNote(id: "needed", symbol: "calendar.badge.clock",
                       text: "Voor \(Fmt.month(YearMonth(date: date))) heb je \(Fmt.euro(needed)) per maand nodig.")
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
        MediaRowLabel(symbol: upcomingSymbol(item), hue: Theme.hue(pot.colorIndex), title: item.title,
                      subtitle: upcomingDetail(item),
                      value: PotFormat.bookingAmount(item.amount, isInterest: item.kind == .interest),
                      valueColor: item.amount >= 0 ? Theme.positive : Theme.negative)
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
                // De inleg hoort bij deze maand: de verdeelpagina opent op de huidige maand, niet op de maand waar je in de
                // maandpagina's het laatst keek.
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
        if store.data.countedPotEntries.contains(where: { $0.potID == pot.id && $0.kind == .interest }) {
            Text("Rente die al is bijgeschreven blijft in de geschiedenis staan. Klopt het saldo niet meer, pas het dan aan met Saldo aanpassen.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        ActionButton(title: "Rente instellen", symbol: "percent") { onEdit() }
    }
}
