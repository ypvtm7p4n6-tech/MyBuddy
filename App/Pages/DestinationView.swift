import SwiftUI

/// Koppelt elke `Destination` aan zijn pagina. Alle kaarten en rijen in de app verwijzen hiernaartoe (via de
/// `NavigationStack` van `TabStack`). De `switch` is uitputtend en heeft bewust geen `default`: een nieuwe bestemming moet
/// hier een pagina krijgen.
struct DestinationView: View {
    let destination: Destination

    var body: some View {
        switch destination {
        case .overview: OverviewTab() // noodgreep: het Overzicht is een tabwortel en komt normaal nooit op een pad
        case .income: IncomePage()
        case .salary: SalaryPage()
        case .expenses: ExpensesPage()
        case .distribute: DistributePage()
        case .pots: PotsPage()
        case .pot(let id): PotDetailPage(potID: id)
        case .bank: BankPage(section: .balance)
        case .portfolio: PortfolioPage()
        case .holding(let id): HoldingDetailPage(holdingID: id)
        case .projection: ProjectionPage()
        case .goals: GoalsPage()
        case .goal(let id): GoalDetailPage(goalID: id)
        case .accelerators: AcceleratorsPage()
        case .buffer: BufferPage()
        case .savingsGoal: SavingsGoalPage()
        case .purchase: PurchasePage()
        case .cashflow: BankPage(section: .days)
        case .settings(let page): SettingsDestination(page: page)
        }
    }
}

/// De maanden die in een grafiek getoond worden: bij "maand" de laatste zes, anders de hele periode.
func chartMonths(mode: PeriodMode, focus: YearMonth) -> [YearMonth] {
    mode == .month ? focus.adding(-5).range(count: 6) : mode.months(containing: focus)
}
