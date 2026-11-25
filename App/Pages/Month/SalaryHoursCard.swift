import SwiftUI

// Twee kaarten van de pagina Salaris: "Loon per maand" (de wijzigingen van je loon vanaf een maand, docs/work/plan2.md par. 4.6) en
// "Uren van de volgende uitbetalingen" (bij uren uit je agenda, docs/work/plan.md par. 4.5). Alle bedragen en uren komen uit de
// rekenmotor (`salarySettings(in:)`, `workReport(forPayoutOn:asOf:)`); de woorden uit `WageText` en `WorkText`.

/// De wijzigingen van je loon: het loon van het begin, een rij per wijziging (de rij die nu geldt met "Nu") en de knop om er een toe
/// te voegen. Een tik op een rij opent "Loon wijzigen" voor die maand.
struct WageHistoryCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let changes = d.salaryChanges
        let current = d.salaryChange(effectiveIn: store.now)
        Card(title: WageText.sectionTitle, symbol: "eurosign.arrow.circlepath", domain: .money) {
            if let first = changes.first {
                MonthExplanation(text: WageText.baseLine(settings: d.salary, until: first.from))
                ForEach(changes, id: \.from) { change in
                    let isCurrent = current?.from == change.from
                    NavigationRow(title: WageText.fromTitle(change.from),
                                  value: isCurrent ? WageText.nowBadge : nil,
                                  subtitle: WageText.valueText(change, mode: d.salary.mode, isMonthly: d.salary.isMonthly),
                                  destination: .wageChange(change.from))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(WageText.accessibilityLine(change, mode: d.salary.mode, isMonthly: d.salary.isMonthly,
                                                                       isCurrent: isCurrent))
                }
            } else {
                MonthExplanation(text: WageText.emptyHint)
            }
            ActionButton(title: WageText.addTitle, symbol: "plus.circle") {
                router.open(.wageChange(nextFreeMonth(d)))
            }
            MonthExplanation(text: WageText.footer)
        }
    }

    /// De maand waarmee "Loon wijzigen" opent: volgende maand, of de eerste maand daarna zonder wijziging.
    private func nextFreeMonth(_ d: FinanceData) -> YearMonth {
        var month = store.now.adding(1)
        var guardCount = 0
        while d.salaryChange(startingIn: month) != nil && guardCount < 24 {
            month = month.adding(1)
            guardCount += 1
        }
        return month
    }
}

/// De uren van de volgende twee uitbetalingen uit je agenda: periode, uren (gewerkt, gepland, verwacht), toeslagen, pauze en bedrag.
struct SalaryHoursCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let today = store.today
        let days = d.upcomingPayoutDays(count: 2, after: today)
        Card(title: WorkText.upcomingTitle, symbol: WorkText.symbol, domain: .money,
             subtitle: WorkText.lastRefreshText(d.work.snapshot, today: today), headerLink: .settings(.workHours)) {
            if days.isEmpty {
                MonthExplanation(text: "Er staat nog geen uitbetaling gepland.")
            }
            ForEach(days, id: \.self) { day in
                if let report = d.workReport(forPayoutOn: day, asOf: today) {
                    WorkPayoutBlock(day: day, report: report, rules: d.work.rules)
                }
            }
        }
    }
}
