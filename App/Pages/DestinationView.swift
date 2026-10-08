import SwiftUI

/// Koppelt elke `Destination` aan zijn pagina. Alle blokken in de app verwijzen hiernaartoe.
struct DestinationView: View {
    let destination: Destination

    var body: some View {
        switch destination {
        case .overview: OverviewPage()
        case .income: IncomePage()
        case .expenses: BankPage() // Uitgaven en bankrekening zijn één pagina
        case .distribute: DistributePage()
        case .pots: PotsPage()
        case .pot(let id): PotDetailPage(potID: id)
        case .bank: BankPage()
        case .portfolio: PortfolioPage()
        case .holding(let id): HoldingDetailPage(holdingID: id)
        case .projection: ProjectionPage()
        case .goals: GoalsPage()
        case .goal(let id): GoalDetailPage(goalID: id)
        case .accelerators: AcceleratorsPage()
        case .buffer: BufferPage()
        case .savingsGoal: SavingsGoalPage()
        }
    }
}

/// De maanden die in een grafiek getoond worden: bij "maand" de laatste zes, anders de hele periode.
func chartMonths(mode: PeriodMode, focus: YearMonth) -> [YearMonth] {
    mode == .month ? focus.adding(-5).range(count: 6) : mode.months(containing: focus)
}
