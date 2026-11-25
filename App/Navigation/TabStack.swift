import SwiftUI

/// De `NavigationStack` van een tab. Elke tab heeft een eigen pad (`router.paths[tab]`), dus van tab wisselen wist niets.
/// Het pad loopt door `NavigationRules.normalize` (`Router.pathBinding(for:)`): een pagina staat nooit twee keer in een pad,
/// ook niet via een `NavigationLink(value:)`. De tabroot zelf is alleen inhoud; de stapel komt van hier. Een pagina mag wel op de
/// stapels van twee tabs staan (B5: een pagina opent op de stapel waar je bent).
struct TabStack<Root: View>: View {
    @Environment(Router.self) private var router
    /// De ruimte waarin een tegel en de pagina die hij opent elkaar vinden voor de zoomovergang.
    @Namespace private var zoom
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
                    ZoomablePage(destination: destination, tab: tab, zooms: router.zoomRequest == destination, namespace: zoom)
                }
        }
        .environment(\.zoomNamespace, zoom)
    }
}

/// Een pagina op de stapel. Opende een tegel haar (`Router.zoomRequest`), dan groeit ze uit die tegel en krimpt ze er bij
/// teruggaan weer in (iOS 18 en nieuwer, het systeem doet de overgang en het terugvegen); anders schuift ze in zoals gewoonlijk.
/// De keuze wordt één keer gemaakt bij het openen, zodat de pagina nooit van overgang wisselt terwijl ze er staat.
private struct ZoomablePage: View {
    let destination: Destination
    let tab: AppTab
    let namespace: Namespace.ID
    @State private var zooms: Bool
    @Environment(Router.self) private var router
    @Environment(AppStore.self) private var store

    init(destination: Destination, tab: AppTab, zooms: Bool, namespace: Namespace.ID) {
        self.destination = destination
        self.tab = tab
        self.namespace = namespace
        _zooms = State(initialValue: zooms)
    }

    var body: some View {
        #if os(iOS)
        if zooms {
            page
                .navigationTransition(.zoom(sourceID: destination, in: namespace))
                .onAppear { if router.zoomRequest == destination { router.zoomRequest = nil } }
        } else {
            page
        }
        #else
        page
        #endif
    }

    /// De pagina met het kruimelpad onder haar titel: tik op de titel en kies een niveau erboven (zoals op apple.com).
    private var page: some View {
        DestinationView(destination: destination)
            .toolbarTitleMenu {
                ForEach(crumbs) { crumb in
                    Button {
                        router.paths[tab] = Array((router.paths[tab] ?? []).prefix(crumb.depth))
                    } label: {
                        Label(crumb.title, systemImage: crumb.symbol)
                    }
                }
            }
    }

    private var crumbs: [Breadcrumb] {
        let path = router.paths[tab] ?? []
        guard let index = path.lastIndex(of: destination) else { return [] }
        return Breadcrumbs.crumbs(above: index, in: path, tab: tab, data: store.data)
    }
}

// MARK: - Zoombron

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// De zoomruimte van de stapel waar een view in staat (nil buiten een `TabStack`, zoals in previews en op de Mac).
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Maakt deze view de bron van de zoomovergang naar `destination` (een tegel of poster).
    func zoomSource(_ destination: Destination) -> some View {
        modifier(ZoomSourceModifier(destination: destination))
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let destination: Destination
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace {
            content.matchedTransitionSource(id: destination, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
