import SwiftUI

/// De inhoud van elke tab, binnen de eigen `NavigationStack` van die tab (`TabStack`). De tabroots zelf (`HomeTab`, `LibraryTab`,
/// `SearchTab`) zijn alleen inhoud; het pad komt uit `router.paths[tab]`. Elke wortel heeft de profielknop rechtsboven
/// (`profileToolbarItem()`), die de pagina Instellingen op de stapel van de tab zet.
struct TabRoot: View {
    let tab: AppTab

    init(_ tab: AppTab) {
        self.tab = tab
    }

    var body: some View {
        switch tab {
        case .home:
            TabStack(.home) {
                HomeTab()
            }
        case .library:
            TabStack(.library) {
                LibraryTab()
            }
        case .search:
            TabStack(.search) {
                SearchTab()
            }
        }
    }
}
