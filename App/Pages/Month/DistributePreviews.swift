#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): Verdelen met de voorbeelddata van de nieuwe mogelijkheden
// (`FinanceData.sampleWithDistribution`: een percentage met een extra bedrag, een extra overschrijfdag en een bankdeel), in donker,
// bij grote tekst, breed, met een bankdeel dat te groot is (rood), met extra overschrijfdagen die samen te veel zijn (waarschuwing),
// een maand vóór de startdatum, een startmaand met een deel vóór de startdag en zonder gegevens.

/// De gegevens van een voorbeeld.
private enum DistributePreviewScenario {
    /// De voorbeelddata met extra bedrag, extra overschrijfdag en bankdeel.
    case filled
    /// Een bankdeel dat groter is dan wat er te verdelen is: "Nog te verdelen" is rood.
    case bankTooLarge
    /// Extra overschrijfdagen die samen meer zijn dan de inleg van de maand.
    case partsTooMany
    /// De maand vóór de startmaand: niets te verdelen en de rijen staan uit.
    case beforeStart
    /// Een startdatum midden in de maand, met een deel van de inleg dat vóór de startdag valt.
    case startMonthWithEarlyPart
    /// Niets ingevuld.
    case empty

    /// Zet de gegevens en de maand waar je naar kijkt klaar.
    @MainActor
    func configure(store: AppStore, router: Router) {
        let now = store.now
        if self != .empty {
            store.mutate { data in
                data = FinanceData.sampleWithDistribution(now: Date())
                data.materialize(upTo: now)
            }
        }
        switch self {
        case .bankTooLarge:
            store.mutate { $0.setContributionAmount(BankShare.id, amount: 10_000, current: now) }
        case .partsTooMany:
            store.mutate { data in
                guard let holiday = data.pots.first(where: { $0.name == "Vakantie" }) else { return }
                data.setStandardTransferParts(holiday.id, parts: [TransferPart(day: 5, amount: 400), TransferPart(day: 20, amount: 400)],
                                              current: now)
            }
        case .beforeStart:
            router.focusMonth = store.data.startMonth.adding(-1)
        case .startMonthWithEarlyPart:
            store.mutate { $0.setStart(CalendarDay(month: now, day: 15)) }
        case .filled, .empty:
            break
        }
    }
}

/// Maakt een winkel (met voorbeelddata of leeg), een router en een inlogstatus voor de voorbeelden.
@MainActor
private struct DistributePreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router: Router
    @State private var auth = AuthStore()
    private let content: Content

    init(_ scenario: DistributePreviewScenario = .filled, @ViewBuilder content: () -> Content) {
        let previewStore = AppStore(storage: nil)
        let previewRouter = Router()
        scenario.configure(store: previewStore, router: previewRouter)
        _store = State(initialValue: previewStore)
        _router = State(initialValue: previewRouter)
        self.content = content()
    }

    var body: some View {
        content
            .environment(store)
            .environment(router)
            .environment(auth)
    }
}

/// De uitklapper met de extra overschrijfdagen van de eerste spaarpot, open, in een kaart (voor de waarschuwing als ze samen te veel zijn).
private struct DistributePartsPreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        ScrollView {
            if let pot = d.pots.first(where: { $0.name == "Vakantie" }) ?? d.pots.first {
                Card(title: pot.name, symbol: pot.symbol, domain: .saving) {
                    DistributePartsGroup(id: pot.id, month: store.now, startsExpanded: true)
                }
                .padding(16)
            }
        }
        .background(Theme.canvas)
    }
}

#Preview("Verdelen") {
    DistributePreviewHost {
        NavigationStack { DistributePage() }
    }
}

#Preview("Verdelen, donker") {
    DistributePreviewHost {
        NavigationStack { DistributePage() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Verdelen, grote tekst") {
    DistributePreviewHost {
        NavigationStack { DistributePage() }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Verdelen, breed") {
    DistributePreviewHost {
        NavigationStack { DistributePage() }
    }
    .frame(width: 900, height: 900)
}

#Preview("Verdelen, bankdeel te groot") {
    DistributePreviewHost(.bankTooLarge) {
        NavigationStack { DistributePage() }
    }
}

#Preview("Verdelen, extra dagen samen te veel") {
    DistributePreviewHost(.partsTooMany) {
        NavigationStack { DistributePage() }
    }
}

#Preview("Extra overschrijfdagen, samen te veel, open") {
    DistributePreviewHost(.partsTooMany) {
        DistributePartsPreview()
    }
}

#Preview("Verdelen, maand vóór de startdatum") {
    DistributePreviewHost(.beforeStart) {
        NavigationStack { DistributePage() }
    }
}

#Preview("Verdelen, startmaand met een deel vóór de startdag") {
    DistributePreviewHost(.startMonthWithEarlyPart) {
        NavigationStack { DistributePage() }
    }
}

#Preview("Verdelen, leeg") {
    DistributePreviewHost(.empty) {
        NavigationStack { DistributePage() }
    }
}
#endif
