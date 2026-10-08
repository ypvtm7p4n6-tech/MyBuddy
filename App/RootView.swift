import SwiftUI

/// Drie pagina's met een zwevende glazen balk onderin, overal gelijk: iPhone, iPad en Mac.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        Group {
            switch router.tab {
            case .home: HomeView()
            case .savings: SavingsView()
            case .investing: InvestView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassTabBar(selection: $router.tab)
        }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .task { await store.refreshPrices() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshClock()
                Task { await store.refreshPrices() }
            }
        }
    }
}

struct GlassTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol(selected: isSelected))
                            .font(.system(size: 19, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
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
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }
}
