import SwiftUI

// De plank (shelf) van Apple Muziek en Apple TV: een kop met "Toon alles" en daaronder een horizontaal scrollende rij tegels die
// per tegel snapt, met de volgende tegel deels zichtbaar. Alle breedtes komen uit `ShelfMetrics` (Foundation-only, getest).
// De rij is bewust geen `LazyHStack`: met hoogstens acht tegels moet VoiceOver ze allemaal kunnen bereiken. Bij
// toegankelijkheidsformaten van Dynamic Type staan de tegels onder elkaar.

/// Een actie in het "…"-menu van een plankkop (bijvoorbeeld "Kies potten…").
struct ShelfAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var role: ButtonRole? = nil
    let action: () -> Void

    init(_ title: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.action = action
    }
}

/// Een plank: titel (een kop voor VoiceOver), eventueel een ondertitel, rechts "Toon alles" en een "…"-menu, en eronder de
/// tegels. De tegel komt van de aanroeper (`PosterCard`, `ShelfCard`) en krijgt zijn breedte van de plank; met `wide` zijn het
/// brede kaarten (twee tegelbreedtes plus de tussenruimte). Hoogstens acht tegels; meer staan achter "Toon alles". Met
/// `orderID` krijgt de kop het contextmenu om de volgorde van de planken aan te passen (lang indrukken). Met
/// `showAllShowsCurrentMonth` opent "Toon alles" een maandpagina op de huidige maand (`router.showCurrentMonth`, B8), zoals
/// `showsCurrentMonth` bij een tegel.
struct Shelf<Item: Identifiable, Tile: View>: View {
    let title: String
    let subtitle: String?
    let showAll: Destination?
    let showAllLabel: String?
    let showAllShowsCurrentMonth: Bool
    let actions: [ShelfAction]
    let orderID: String?
    let wide: Bool
    let items: [Item]
    let tile: (Item) -> Tile
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, subtitle: String? = nil, showAll: Destination? = nil, showAllLabel: String? = nil,
         showAllShowsCurrentMonth: Bool = false,
         actions: [ShelfAction] = [], orderID: String? = nil, wide: Bool = false,
         items: [Item], @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.title = title
        self.subtitle = subtitle
        self.showAll = showAll
        self.showAllLabel = showAllLabel
        self.showAllShowsCurrentMonth = showAllShowsCurrentMonth
        self.actions = actions
        self.orderID = orderID
        self.wide = wide
        self.items = items
        self.tile = tile
    }

    /// Het grootste aantal tegels op een plank.
    static var maxItems: Int { 8 }

    private var compact: Bool { sizeClass == .compact }
    private var margin: CGFloat { CGFloat(ShelfMetrics.margin(compact: compact)) }
    private var spacing: CGFloat { CGFloat(ShelfMetrics.spacing(compact: compact)) }
    private var visibleItems: [Item] { Array(items.prefix(Shelf.maxItems)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            orderedHeader
            if typeSize.isAccessibilitySize {
                stackedTiles
            } else {
                tileRow
            }
        }
    }

    // MARK: Kop

    @ViewBuilder
    private var orderedHeader: some View {
        if let orderID {
            header.blockOrderMenu(page: .overview, id: orderID)
        } else {
            header
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            showAllLink
            actionsMenu
        }
        .padding(.horizontal, margin)
    }

    @ViewBuilder
    private var showAllLink: some View {
        if let showAll {
            DestinationLink(destination: showAll, showsCurrentMonth: showAllShowsCurrentMonth) { _ in
                Text("Toon alles")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: Theme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TilePressStyle())
            .accessibilityLabel(showAllLabel ?? "Toon alles")
        }
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if !actions.isEmpty {
            Menu {
                ForEach(actions) { item in
                    Button(role: item.role, action: item.action) {
                        Label(item.title, systemImage: item.symbol)
                    }
                }
            } label: {
                Label("Meer", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Meer, " + title)
            .help("Meer")
        }
    }

    // MARK: Tegels

    private var tileRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(visibleItems) { item in
                    tile(item)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            tileWidth(in: length)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, margin)
        .scrollClipDisabled()
    }

    /// Bij toegankelijkheidsformaten onder elkaar, elke tegel hoogstens 320 punten breed.
    private var stackedTiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleItems) { item in
                tile(item)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .padding(.horizontal, margin)
    }

    private func tileWidth(in length: CGFloat) -> CGFloat {
        let gap = Double(spacing)
        if wide {
            return CGFloat(ShelfMetrics.wideTileWidth(in: Double(length), spacing: gap))
        }
        return CGFloat(ShelfMetrics.tileWidth(in: Double(length), spacing: gap))
    }
}
