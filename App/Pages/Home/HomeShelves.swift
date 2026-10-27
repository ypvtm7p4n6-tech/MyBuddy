import SwiftUI

// De planken van Home in de volgorde van de gebruiker (`BlockPage.overview`: upcoming, pots, invest, goals, tools) en de plank
// Komende dagen. De volgorde komt uit `blockIDs(for: .overview)`; het ordenmenu zit op de plankkop (`Shelf(orderID:)`, lang
// indrukken) en in Instellingen, Indeling. De planken Spaarpotten en Beleggingen staan in HomeSaving.swift, Doelen en
// Hulpmiddelen in HomePlanning.swift.

// MARK: - De planken

/// Alle planken van Home, in de volgorde van de gebruiker. Een onbekend blok-id blijft leeg (`blockIDs` laat het al weg).
struct HomeShelfStack: View {
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            ForEach(store.data.settings.blockIDs(for: .overview), id: \.self) { id in
                HomeShelfBlock(id: id, present: present)
            }
        }
    }
}

/// De plank bij een blok-id van `BlockPage.overview`.
private struct HomeShelfBlock: View {
    let id: String
    let present: HomePresent

    var body: some View {
        switch id {
        case "upcoming": HomeUpcomingShelf(present: present)
        case "pots": HomePotsShelf(present: present)
        case "invest": HomeHoldingsShelf(present: present)
        case "goals": HomeGoalsShelf()
        case "tools": HomeToolsShelf()
        default: EmptyView()
        }
    }
}

// MARK: - Komende dagen

/// Eén tegel op de plank Komende dagen: een drukke dag, de melding dat het rustig is, of de vraag om je saldo in te vullen.
struct HomeUpcomingItem: Identifiable {
    enum Kind {
        case day(DayTotals)
        case quiet
        case balancePrompt
    }

    let id: String
    let kind: Kind

    /// Hoeveel drukke dagen de plank toont: samen met de vraag om het saldo blijft het bij hoogstens acht tegels. De rest staat
    /// op Dag voor dag ("Toon alle dagen").
    static let maxDays = 7

    /// De tegels bij de drukke dagen van het venster. Zonder drukke dag komt de melding dat het rustig is; zonder bekend saldo
    /// komt als laatste de vraag het in te vullen (de saldi per dag hebben dat nodig).
    static func items(busy: [DayTotals], hasBalance: Bool) -> [HomeUpcomingItem] {
        var list: [HomeUpcomingItem] = []
        if busy.isEmpty {
            list.append(HomeUpcomingItem(id: "quiet", kind: .quiet))
        } else {
            for day in busy.prefix(maxDays) {
                let stamp = Int(day.date.timeIntervalSince1970)
                list.append(HomeUpcomingItem(id: "day-\(stamp)", kind: .day(day)))
            }
        }
        if !hasBalance {
            list.append(HomeUpcomingItem(id: "balance", kind: .balancePrompt))
        }
        return list
    }
}

/// De plank Komende dagen: wat er de komende 14 dagen gebeurt, per drukke dag een brede kaart met het saldo aan het eind van de
/// dag (uit de dagboekhouding). Het venster en de dagen komen uit `UpcomingDaysWindow`. Toont de plank niet alle drukke dagen,
/// dan loopt de ondertitel alleen tot de laatste getoonde dag.
struct HomeUpcomingShelf: View {
    let present: HomePresent
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let today = store.today
        let window = UpcomingDaysWindow.range(today: today)
        let busy = UpcomingDaysWindow.busyDays(in: LedgerBook(d, today: today), today: today)
        let hasBalance = d.hasBankBalanceNow(current: store.now, today: today)
        let items = HomeUpcomingItem.items(busy: busy, hasBalance: hasBalance)
        Shelf("Komende dagen", subtitle: subtitle(window: window, busy: busy), showAll: .cashflow,
              showAllLabel: "Toon alle dagen", orderID: "upcoming", wide: true, items: items) { item in
            HomeUpcomingTile(item: item, present: present)
        }
    }

    /// "25 okt t/m 7 nov": het venster, of tot de laatste getoonde dag als er meer drukke dagen zijn dan tegels.
    private func subtitle(window: (from: Date, to: Date), busy: [DayTotals]) -> String {
        var end = window.to
        if busy.count > HomeUpcomingItem.maxDays, let last = busy.prefix(HomeUpcomingItem.maxDays).last {
            end = last.date
        }
        return "\(DayText.short(window.from)) t/m \(DayText.short(end))"
    }
}

private struct HomeUpcomingTile: View {
    let item: HomeUpcomingItem
    let present: HomePresent

    var body: some View {
        switch item.kind {
        case .day(let day):
            HomeDayCard(day: day)
        case .quiet:
            HomeQuietCard()
        case .balancePrompt:
            HomeBalancePromptCard(present: present)
        }
    }
}

/// Eén drukke dag: weekdag en datum, "Vandaag" of "Gepland", hoogstens drie gebeurtenissen met hun bedrag (met teken) en het
/// saldo aan het eind van de dag. De hele kaart is één element voor VoiceOver en opent Dag voor dag op de huidige maand.
private struct HomeDayCard: View {
    let day: DayTotals

    /// Hoeveel gebeurtenissen op de kaart staan; de rest is "en nog n".
    private static let maxEvents = 3

    var body: some View {
        ShelfCard(destination: .cashflow, showsCurrentMonth: true) {
            VStack(alignment: .leading, spacing: 8) {
                header
                events
                Spacer(minLength: 0)
                balanceLine
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DayText.weekdayShort(day.date))
                .font(.headline)
                .foregroundStyle(.primary)
            if let status = CashflowText.status(of: day) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(day.events.prefix(HomeDayCard.maxEvents))) { event in
                HomeDayEventLine(event: event)
            }
            if day.events.count > HomeDayCard.maxEvents {
                Text(moreText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var balanceLine: some View {
        if let balance = day.bankBalance {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Saldo")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
                Text(Fmt.euro(balance))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? Theme.negative : Color.primary)
            }
        }
    }

    private var moreText: String {
        let rest = day.events.count - HomeDayCard.maxEvents
        return "en nog \(rest) " + (rest == 1 ? "gebeurtenis" : "gebeurtenissen")
    }

    /// "ma 27 okt, gepland, Huur − € 850, Salaris + € 3.000, saldo aan het eind van de dag € 1.234".
    private var spokenLabel: String {
        var parts: [String] = [DayText.weekdayShort(day.date)]
        if let status = CashflowText.status(of: day) { parts.append(status) }
        for event in day.events.prefix(HomeDayCard.maxEvents) {
            parts.append(event.title + " " + DayEventStyle(event).amountText)
        }
        if day.events.count > HomeDayCard.maxEvents { parts.append(moreText) }
        if let balance = day.bankBalance { parts.append("saldo aan het eind van de dag " + Fmt.euro(balance)) }
        return parts.joined(separator: ", ")
    }
}

/// Eén gebeurtenis op een dagkaart: titel links, bedrag met teken rechts. De kleur versterkt het teken, hij vervangt het niet.
private struct HomeDayEventLine: View {
    let event: DayEvent

    var body: some View {
        let style = DayEventStyle(event)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(event.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Text(style.amountText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(style.color)
                .layoutPriority(1)
        }
    }
}

/// De kaart als er in het venster niets gebeurt: dezelfde tekst als op de oude Home.
private struct HomeQuietCard: View {
    var body: some View {
        ShelfCard {
            Text("De komende \(UpcomingDaysWindow.length) dagen komt er niets binnen en gaat er niets weg.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// De vraag om je saldo in te vullen, zodat ook het saldo per dag te zien is.
private struct HomeBalancePromptCard: View {
    let present: HomePresent

    var body: some View {
        ShelfCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vul je saldo in om ook het saldo per dag te zien.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                PillButton(BankAction.balance.title, symbol: BankAction.balance.symbol) {
                    present(.balance)
                }
            }
        }
    }
}
