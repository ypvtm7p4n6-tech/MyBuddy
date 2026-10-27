import SwiftUI

// Gedeelde onderdelen van Home: de bladen die Home opent, de kaarten van de hero, de paginamarge en het
// contextmenu van een tegel. Alle gegevens komen uit dezelfde bronnen als de oude kaarten van Home; hier wordt niets
// zelf uitgerekend.

// MARK: - Bladen

/// De bladen die Home opent. Alle bladen staan achter één bladpresentatie op `HomeTab`; de planken en de hero melden alleen
/// welk blad ze willen (`HomePresent`). Een pot of belegging staat er met zijn id: het blad zoekt hem op bij het openen.
enum HomeSheet: Identifiable {
    case balance
    case newPot
    case pickPots
    case newHolding
    case pickHoldings
    case movePot(UUID, PotAction)
    case editPot(UUID)
    case updateValue(UUID)
    case editHolding(UUID)

    var id: String {
        switch self {
        case .balance: return "balance"
        case .newPot: return "newPot"
        case .pickPots: return "pickPots"
        case .newHolding: return "newHolding"
        case .pickHoldings: return "pickHoldings"
        case .movePot(let potID, let action): return "movePot-" + potID.uuidString + "-" + action.rawValue
        case .editPot(let potID): return "editPot-" + potID.uuidString
        case .updateValue(let holdingID): return "updateValue-" + holdingID.uuidString
        case .editHolding(let holdingID): return "editHolding-" + holdingID.uuidString
        }
    }
}

/// Zo meldt een hero-kaart of plank dat Home een blad moet openen.
typealias HomePresent = (HomeSheet) -> Void

/// De inhoud van het blad dat bij een `HomeSheet` hoort. Bestaat de pot of belegging niet meer, dan blijft het blad leeg en
/// sluit het systeem het niet vanzelf; dat gebeurt alleen als een pot tussen tikken en openen verdwijnt.
struct HomeSheetContent: View {
    let item: HomeSheet
    @Environment(AppStore.self) private var store

    var body: some View {
        switch item {
        case .balance:
            BankActionSheet(action: .balance)
        case .newPot:
            PotEditSheet(pot: nil)
        case .pickPots:
            FavoritePotsSheet()
        case .newHolding:
            HoldingEditSheet(holding: nil)
        case .pickHoldings:
            FavoriteHoldingsSheet()
        case .movePot(let potID, let action):
            if let pot = store.data.pots.first(where: { $0.id == potID }) {
                PotEntrySheet(pot: pot, action: action)
            }
        case .editPot(let potID):
            if let pot = store.data.pots.first(where: { $0.id == potID }) {
                PotEditSheet(pot: pot)
            }
        case .updateValue(let holdingID):
            if let holding = store.data.holdings.first(where: { $0.id == holdingID }) {
                ValueUpdateSheet(holding: holding)
            }
        case .editHolding(let holdingID):
            if let holding = store.data.holdings.first(where: { $0.id == holdingID }) {
                HoldingEditSheet(holding: holding)
            }
        }
    }
}

// MARK: - De hero-kaarten

/// De stabiele id's van de drie hero-kaarten, in de volgorde van de carrousel, en de tint van het kleurverloop dat bij elke kaart
/// hoort (de achtergrond van Home volgt de zichtbare kaart).
enum HomeHeroID {
    static let distribute = "distribute"
    static let wealth = "wealth"
    static let balance = "balance"
    static let all: [String] = [distribute, wealth, balance]

    /// De tegelkleur van een kaart: olijf, leiblauw of terracotta. Zonder selectie (nog niet gescrold) de eerste kaart.
    static func hue(for id: String?) -> TileHue {
        if id == wealth { return .slate }
        if id == balance { return .terracotta }
        return .olive
    }

    /// De kaart waar Home op opent: de eerste, of in een debug-build die van `-mybuddy-hero 0|1|2`.
    static func startID() -> String {
        #if DEBUG
        if let index = DebugLaunch.heroIndex, all.indices.contains(index) {
            return all[index]
        }
        #endif
        return distribute
    }
}

/// Een regel uitleg op een hero-kaart: klein, in de bijschriftkleur van een tegel. Met een symbool (een waarschuwing of
/// aanwijzing) in de volle tekstkleur, zodat de betekenis nooit alleen in kleur zit. Nooit rood of groen op een tegel.
struct HomeHeroLine: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(symbol == nil ? Theme.onTileSecondary : Theme.onTile)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paginamarge

private struct HomeMargin: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.padding(.horizontal, CGFloat(ShelfMetrics.margin(compact: sizeClass == .compact)))
    }
}

extension View {
    /// De paginamarge van Home (16 punten op een iPhone, 20 op iPad en Mac) voor inhoud die niet zelf een plank of carrousel is:
    /// de meldingen en de welkomstkaart. `PageScaffold(fullBleed:)` geeft Home zelf geen marge.
    func homeMargin() -> some View {
        modifier(HomeMargin())
    }

    /// Het voorbeeld van een contextmenu krijgt de afgeronde hoek van een tegel (alleen iOS en iPadOS; elders doet dit niets).
    @ViewBuilder
    func homeTileShape() -> some View {
        #if os(iOS)
        contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous))
        #else
        self
        #endif
    }
}

// MARK: - Een lege plek op een plank

/// Een omlijnde lege plek naast de gekozen potten: een plus en "Kies pot" (of "Nieuwe pot" als er geen pot meer is om te kiezen).
/// Een tik opent het blad. Even breed als een tegel; het vierkant is versiering, de titel is het label.
struct HomeSlotTile: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                square
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePressStyle())
    }

    private var square: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous)
                    .strokeBorder(Theme.textSecondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
    }
}
