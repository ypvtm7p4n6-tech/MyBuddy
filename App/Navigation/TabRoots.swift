import SwiftUI

/// De inhoud van elke tab, binnen de eigen `NavigationStack` van die tab (`TabStack`). De tabroots zelf (`OverviewTab`,
/// `MonthTab`, `SavingTab`, `PlanningTab`) zijn alleen inhoud; het pad komt uit `router.paths[tab]`.
/// `SettingsView` (de tabroot van Instellingen) heeft bewust geen eigen `NavigationStack`: de stapel komt van `TabStack`.
struct TabRoot: View {
    let tab: AppTab

    init(_ tab: AppTab) {
        self.tab = tab
    }

    var body: some View {
        switch tab {
        case .overview:
            TabStack(.overview) {
                OverviewTab()
            }
        case .month:
            TabStack(.month) {
                MonthTab()
            }
        case .saving:
            TabStack(.saving) {
                SavingTab()
            }
        case .planning:
            TabStack(.planning) {
                PlanningTab()
            }
        case .settings:
            TabStack(.settings) {
                SettingsView()
            }
        }
    }
}
