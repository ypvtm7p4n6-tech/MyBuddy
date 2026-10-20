import SwiftUI

/// De `NavigationStack` van een tab. Elke tab heeft een eigen pad (`router.paths[tab]`), dus van tab wisselen wist niets.
/// Het pad loopt door `NavigationRules.normalize` (`Router.pathBinding(for:)`): een pagina staat nooit twee keer in een pad,
/// ook niet via een `NavigationLink(value:)`. De tabroot zelf is alleen inhoud; de stapel komt van hier.
struct TabStack<Root: View>: View {
    @Environment(Router.self) private var router
    private let tab: AppTab
    private let root: Root

    init(_ tab: AppTab, @ViewBuilder root: () -> Root) {
        self.tab = tab
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: router.pathBinding(for: tab)) {
            root
                .navigationDestination(for: Destination.self) { destination in
                    DestinationView(destination: destination)
                }
        }
    }
}
