#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): Home met voorbeelddata, in donker, bij grote tekst, breed (iPad en
// Mac), de lege start, zonder banksaldo en met lege planken, en de drie hero-kaarten los, ook met een deel dat aan de bankrekening is
// toegewezen (te groot en passend). Home staat in een `TabStack`, zoals in de app.

/// De gegevens van een voorbeeld.
private enum HomePreviewScenario {
    /// Voorbeelddata.
    case filled
    /// Niets ingevuld: de lege start.
    case empty
    /// Voorbeelddata zonder ingevuld banksaldo.
    case noBalance
    /// Voorbeelddata zonder spaarpotten, beleggingen en doelen: elke plank in zijn lege staat.
    case emptyShelves
    /// Voorbeelddata met 300 euro per maand aan de bankrekening toegewezen: "Nog te verdelen" is dan 300 lager dan wat er overblijft.
    case bankShare
    /// Voorbeelddata met een bankdeel dat groter is dan wat er te verdelen is: het getal is rood.
    case bankShareTooLarge
}

/// Maakt een winkel (met voorbeelddata of leeg), een router en een inlogstatus voor de voorbeelden.
@MainActor
private struct HomePreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    @State private var auth = AuthStore()
    private let content: Content

    init(_ scenario: HomePreviewScenario = .filled, @ViewBuilder content: () -> Content) {
        let previewStore = AppStore(storage: nil)
        if scenario != .empty { previewStore.loadSampleData() }
        if scenario == .noBalance {
            previewStore.mutate { d in d.bankSnapshots = [] }
        }
        if scenario == .emptyShelves {
            previewStore.mutate { d in
                d.pots = []
                d.potEntries = []
                d.holdings = []
                d.goals = []
            }
        }
        if scenario == .bankShare || scenario == .bankShareTooLarge {
            let current = previewStore.now
            let amount: Double = scenario == .bankShare ? 300 : 20_000
            previewStore.mutate { d in d.setContributionAmount(BankShare.id, amount: amount, current: current) }
        }
        _store = State(initialValue: previewStore)
        self.content = content()
    }

    var body: some View {
        content
            .environment(store)
            .environment(router)
            .environment(auth)
    }
}

/// De drie hero-kaarten onder elkaar, elk in zijn eigen breedte van een carrousel.
private struct HomeHeroCardsPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomeDistributeHero()
                HomeWealthHero(present: { _ in })
                HomeBalanceHero(present: { _ in })
            }
            .padding(16)
        }
        .background(Theme.canvas)
    }
}

#Preview("Home") {
    HomePreviewHost {
        TabStack(.home) { HomeTab() }
    }
}

#Preview("Home, donker") {
    HomePreviewHost {
        TabStack(.home) { HomeTab() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Home, grote tekst") {
    HomePreviewHost {
        TabStack(.home) { HomeTab() }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Home, breed") {
    HomePreviewHost {
        TabStack(.home) { HomeTab() }
    }
    .frame(width: 1100, height: 800)
}

#Preview("Home, lege start") {
    HomePreviewHost(.empty) {
        TabStack(.home) { HomeTab() }
    }
}

#Preview("Home, lege start, donker") {
    HomePreviewHost(.empty) {
        TabStack(.home) { HomeTab() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Home, zonder banksaldo") {
    HomePreviewHost(.noBalance) {
        TabStack(.home) { HomeTab() }
    }
}

#Preview("Home, lege planken") {
    HomePreviewHost(.emptyShelves) {
        TabStack(.home) { HomeTab() }
    }
}

#Preview("Hero-kaarten") {
    HomePreviewHost {
        HomeHeroCardsPreview()
    }
}

#Preview("Hero-kaarten, met een bankdeel") {
    HomePreviewHost(.bankShare) {
        HomeHeroCardsPreview()
    }
}

#Preview("Hero-kaarten, bankdeel te groot, donker") {
    HomePreviewHost(.bankShareTooLarge) {
        HomeHeroCardsPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Hero-kaarten, donker, grote tekst") {
    HomePreviewHost {
        HomeHeroCardsPreview()
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
#endif
