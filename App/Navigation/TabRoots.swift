import SwiftUI

/// TIJDELIJK (golf 0a tot golf 1c): de inhoud van elke tab, zolang de nieuwe tabroots (`OverviewTab`, `MonthTab`,
/// `SavingTab`, `PlanningTab`) van pakket A er nog niet zijn. De oude views houden hun eigen `NavigationStack`
/// (op de oude padeigenschappen van `Router`, die doorverwijzen naar `router.paths`).
/// In golf 1c wordt dit de definitieve vorm: `TabStack(.overview) { OverviewTab() }` enzovoort. Dit is geen eindvorm en
/// wordt nooit opgeleverd.
struct TabRoot: View {
    let tab: AppTab

    init(_ tab: AppTab) {
        self.tab = tab
    }

    var body: some View {
        switch tab {
        case .overview:
            HomeView()
        case .month:
            SavingsView()
        case .saving:
            TabStack(.saving) {
                ContentUnavailableView(
                    "Sparen",
                    systemImage: "banknote",
                    description: Text("Wordt gebouwd")
                )
                .navigationTitle("Sparen")
            }
        case .planning:
            ToolsView()
        case .settings:
            SettingsView()
        }
    }
}
