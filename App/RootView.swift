import SwiftUI

/// De schil van de app: een native tabbalk met een eigen navigatiepad per tab (`Router.paths`).
/// iPhone: tabbalk onderin (op iOS 26 als glas boven de inhoud). iPad: balk bovenin die een zijbalk kan worden.
/// Mac: zijbalk met vier items; Instellingen is daar het `Settings`-venster (zie `SettingsScene`).
/// Op iPhone en iPad is Instellingen de vijfde tab, met een badge zolang de synchronisatie aandacht vraagt.
/// De titels en symbolen van de tabs zijn gelijk aan `AppTab.title` en `AppTab.symbol`.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.syncController) private var sync
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        @Bindable var router = router
        tabs
            .sheet(item: $router.orderPage) { page in BlockOrderSheet(page: page) }
            .task { await store.refreshPrices() }
            // Zolang de app open staat, gaat de klok bij: een nieuwe dag of een betaaldag verandert de "nu"-saldi.
            .task(id: scenePhase) { await keepClockFresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.refreshClock()
                    Task { await store.refreshPrices() }
                }
            }
            // Begint er een nieuwe maand terwijl de app openstaat, dan schuift de Maand-tab mee, maar alleen
            // als je niet zelf naar een andere maand was gebladerd.
            .onChange(of: store.now) { old, new in
                if router.focusMonth == old { router.resetFocus(to: new) }
            }
            #if os(macOS)
            // Een diepe link naar Instellingen opent op de Mac het Settings-venster; dat venster wist het verzoek.
            .onChange(of: router.settingsRequest) { _, request in
                if request != nil { openSettings() }
            }
            .onAppear {
                if router.settingsRequest != nil { openSettings() }
            }
            #endif
    }

    // MARK: Tabs

    /// De selectie van de tabbalk. Tik je op de tab waar je al op zit, dan ga je terug naar de wortel van die tab;
    /// een andere tab laat zijn eigen pad zoals het was.
    private var selection: Binding<AppTab> {
        Binding(
            get: { router.tab },
            set: { newTab in
                if newTab == router.tab {
                    router.popToRoot(newTab)
                } else {
                    router.select(newTab)
                }
            }
        )
    }

    /// Instellingen vraagt aandacht: er is een synchronisatieconflict, of een aanbod om lokale gegevens te uploaden.
    private var needsAttention: Bool {
        sync?.importOffer != nil || sync?.conflict != nil
    }

    private var tabs: some View {
        withMinimizingTabBar(tabView)
    }

    #if os(macOS)
    private var tabView: some View {
        TabView(selection: selection) {
            Tab("Overzicht", systemImage: "chart.pie", value: AppTab.overview) {
                TabRoot(.overview)
            }
            Tab("Maand", systemImage: "calendar", value: AppTab.month) {
                TabRoot(.month)
            }
            Tab("Sparen", systemImage: "banknote", value: AppTab.saving) {
                TabRoot(.saving)
            }
            Tab("Plannen", systemImage: "flag.checkered", value: AppTab.planning) {
                TabRoot(.planning)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
    #else
    private var tabView: some View {
        TabView(selection: selection) {
            Tab("Overzicht", systemImage: "chart.pie", value: AppTab.overview) {
                TabRoot(.overview)
            }
            Tab("Maand", systemImage: "calendar", value: AppTab.month) {
                TabRoot(.month)
            }
            Tab("Sparen", systemImage: "banknote", value: AppTab.saving) {
                TabRoot(.saving)
            }
            Tab("Plannen", systemImage: "flag.checkered", value: AppTab.planning) {
                TabRoot(.planning)
            }
            Tab("Instellingen", systemImage: "gearshape", value: AppTab.settings) {
                TabRoot(.settings)
            }
            .badge(needsAttention ? 1 : 0)
        }
        .tabViewStyle(.sidebarAdaptable)
    }
    #endif

    /// Op iOS 26 schuift de tabbalk weg als je omlaag scrolt (op de Mac niet: die waarde bestaat daar niet). Eerdere versies laten alles zoals het is.
    @ViewBuilder
    private func withMinimizingTabBar<Content: View>(_ content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
        #else
        // `.onScrollDown` bestaat alleen op iOS en iPadOS.
        content
        #endif
    }

    // MARK: Klok

    /// Controleert elke minuut of er een nieuwe dag of maand is (alleen terwijl de app actief is).
    /// Het eerste moment na het actief worden regelt `onChange(of: scenePhase)`.
    private func keepClockFresh() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                return
            }
            store.refreshClock()
        }
    }
}
