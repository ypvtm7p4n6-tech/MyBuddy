import SwiftUI

// De kaart "Komende dagen" voor het Overzicht (plan par. 2.4, blok `upcoming`): wat er de komende 14 dagen gebeurt, dag voor dag,
// met het saldo aan het eind van elke dag (uit de dagboekhouding). Hij leest zijn gegevens zelf uit `AppStore` en heeft een lege
// `init()`. Het venster en de dagen komen uit `UpcomingDaysWindow` (CashflowDisplay.swift).

struct UpcomingDaysCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var action: BankAction?

    init() {}

    var body: some View {
        let d = store.data
        let today = store.today
        let window = UpcomingDaysWindow.range(today: today)
        let busy = UpcomingDaysWindow.busyDays(in: LedgerBook(d, today: today), today: today)
        Card(title: "Komende dagen", symbol: "calendar.badge.clock", domain: .money,
             subtitle: "\(DayText.short(window.from)) t/m \(DayText.short(window.to))") {
            dayRows(busy)
            if !d.hasBankBalanceNow(current: store.now, today: today) {
                missingBalance
            }
            ActionButton(title: "Dag voor dag", symbol: "calendar") {
                // Het Overzicht gaat over de huidige maand: Dag voor dag opent dan ook op de huidige maand.
                router.showCurrentMonth(store.now)
                router.open(.cashflow)
            }
        }
        .sheet(item: $action) { chosen in
            BankActionSheet(action: chosen)
        }
    }

    @ViewBuilder
    private func dayRows(_ busy: [DayTotals]) -> some View {
        if busy.isEmpty {
            Text("De komende \(UpcomingDaysWindow.length) dagen komt er niets binnen en gaat er niets weg.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(busy) { day in
                    UpcomingDayRow(day: day)
                    if day.id != busy.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var missingBalance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vul je saldo in om ook het saldo per dag te zien.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            ActionButton(title: BankAction.balance.title, symbol: BankAction.balance.symbol) {
                action = .balance
            }
        }
    }
}

/// Eén dag in de lijst "Komende dagen": datum, saldo aan het eind van de dag en de gebeurtenissen.
struct UpcomingDayRow: View {
    let day: DayTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    dateColumn
                    Spacer(minLength: 8)
                    balanceColumn
                }
                VStack(alignment: .leading, spacing: 4) {
                    dateColumn
                    balanceColumn
                }
            }
            ForEach(day.events) { event in
                DayEventRow(event: event)
            }
        }
        .padding(.vertical, 10)
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(DayText.weekdayShort(day.date))
                .font(.subheadline.weight(.semibold))
            if day.isToday {
                Text("Vandaag")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var balanceColumn: some View {
        if let balance = day.bankBalance {
            VStack(alignment: .leading, spacing: 1) {
                Text("Saldo")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(Fmt.euro(balance))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? Theme.negative : Color.primary)
                    .contentTransition(.numericText())
                    .animated(by: balance)
            }
        }
    }
}
