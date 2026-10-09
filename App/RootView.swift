import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Drie pagina's met een glazen tabbalk onderin, overal gelijk: iPhone, iPad en Mac.
/// De balk neemt zijn eigen ruimte in onder de pagina (geen zwevende laag over de inhoud),
/// zodat de onderste blokken er helemaal boven kunnen scrollen.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    /// Het toetsenbord staat open: de balk maakt dan plaats, anders zweeft hij boven de toetsen.
    @State private var keyboardVisible = false

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            tabContent
            if !keyboardVisible {
                GlassTabBar(selection: router.tab) { router.select($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background { MeshBackground() }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
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
        // Begint er een nieuwe maand terwijl de app openstaat, dan schuift de Savings-pagina mee, maar alleen
        // als je niet zelf naar een andere maand was gebladerd.
        .onChange(of: store.now) { old, new in
            if router.focusMonth == old { router.resetFocus(to: new) }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(Theme.quickMotion) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Theme.quickMotion) { keyboardVisible = false }
        }
        #endif
    }

    /// De pagina van de gekozen tab. Bij het wisselen vloeit de ene zacht over in de andere.
    private var tabContent: some View {
        ZStack {
            switch router.tab {
            case .home:
                HomeView().transition(Self.tabTransition)
            case .savings:
                SavingsView().transition(Self.tabTransition)
            case .tools:
                ToolsView().transition(Self.tabTransition)
            }
        }
        .animation(Theme.quickMotion, value: router.tab)
    }

    private static let tabTransition: AnyTransition = .opacity.combined(with: .scale(scale: 0.98))

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

/// Glazen balk met de drie tabs en een indicator die van tab naar tab glijdt.
/// Onder en vlak boven de balk ligt een zachte laag glas, zodat de inhoud er vloeiend onder wegvalt.
struct GlassTabBar: View {
    let selection: AppTab
    /// Wordt ook aangeroepen als je op de tab tikt waar je al op zit: dan ga je terug naar de hoofdpagina.
    let onSelect: (AppTab) -> Void
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(Theme.quickMotion) { onSelect(tab) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol(selected: isSelected))
                            .font(.system(size: 19, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.cardRadius - 8, style: .continuous)
                                .fill(Theme.accent.opacity(0.18))
                                .matchedGeometryEffect(id: "indicator", in: indicator)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(6)
        .glassCard(radius: Theme.cardRadius, interactive: true)
        .frame(maxWidth: 460)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { barBackdrop }
    }

    /// Het glas achter de balk: onder de balk (ook onder de thuisknop-streep) volledig, erboven
    /// een strook die langzaam doorzichtig wordt.
    private var barBackdrop: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
            Rectangle()
                .fill(.bar)
                .frame(height: 24)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                .offset(y: -24)
        }
        .allowsHitTesting(false)
    }
}
