import SwiftUI

/// Koppelt elke `Destination` aan zijn pagina. Alle tegels, rijen en pillen in de app verwijzen hiernaartoe (via de
/// `NavigationStack` van `TabStack`). De `switch` is uitputtend en heeft bewust geen `default`: een nieuwe bestemming moet
/// hier een pagina krijgen. Elke pagina krijgt de tint van zijn kleurverloop (`\.backdropHue`): die van de catalogus
/// (`PageCatalog`), saliegrijs voor Instellingen; een albumpagina (spaarpot, belegging, doel) zet zijn eigen tint.
struct DestinationView: View {
    let destination: Destination

    var body: some View {
        page
            .environment(\.backdropHue, hue)
    }

    /// De tint van het kleurverloop achter deze pagina.
    private var hue: TileHue {
        if case .settings = destination { return .sage }
        return PageCatalog.info(destination)?.hue ?? .olive
    }

    @ViewBuilder
    private var page: some View {
        switch destination {
        case .home: HomeTab() // noodgreep: een tabwortel komt normaal nooit op een pad
        case .library: LibraryTab() // idem
        case .flow: FlowPage()
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
        case .tools: ToolsPage()
        case .settingsRoot: SettingsView()
        case .settings(let page): SettingsDestination(page: page)
        }
    }
}

/// De maanden die in een grafiek getoond worden: bij "maand" de laatste zes, anders de hele periode.
func chartMonths(mode: PeriodMode, focus: YearMonth) -> [YearMonth] {
    mode == .month ? focus.adding(-5).range(count: 6) : mode.months(containing: focus)
}
