import SwiftUI

// De volgorde van de blokken op een pagina (par. 2.7 van docs/design/plan.md). De gebruiker kiest de volgorde zelf: via het
// menu in de werkbalk ("Volgorde aanpassen…"), via Instellingen, Indeling en via lang indrukken op een blok. Een opgeslagen
// volgorde onder de oude sleutels (`home`, `savings`, `tools`) wordt bij het lezen omgezet (`BlockOrderMigration`).

// MARK: - Welke blokken een pagina heeft

/// Eén blok van een pagina, met de naam en het icoon dat in het ordenen-blad staat.
struct BlockInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

/// De pagina's waarvan je de volgorde van de blokken zelf kunt kiezen. De blok-id's staan ook in `docs/v3-spec.md`.
/// De kern van een pagina (de hero op het Overzicht, de `MonthBar` op Maand) is geen blok en staat vast bovenaan.
enum BlockPage: String, CaseIterable, Identifiable {
    case overview, month, saving, planning
    // Overgangsvorm tot pakket G: de blokken van de drie oude tabroots.
    case home, savings, tools

    /// Alleen de vier pagina's van nu; de overgangsvormen doen niet mee in een lijst van alle pagina's.
    static var allCases: [BlockPage] { [.overview, .month, .saving, .planning] }

    var id: String { rawValue }

    /// Sleutel in `AppSettings.blockOrder`.
    var key: String { rawValue }

    /// Is dit een van de oude pagina's (tot pakket G)?
    var isLegacy: Bool {
        switch self {
        case .home, .savings, .tools: return true
        case .overview, .month, .saving, .planning: return false
        }
    }

    var title: String {
        switch self {
        case .overview, .home: return "Overzicht"
        case .month, .savings: return "Maand"
        case .saving: return "Sparen"
        case .planning, .tools: return "Plannen"
        }
    }

    /// Alleen een pagina met drie of meer blokken toont "Volgorde aanpassen": ordenen van twee blokken is zinloos.
    var allowsOrdering: Bool { blocks.count >= 3 }

    /// De blokken in de standaardvolgorde.
    var blocks: [BlockInfo] {
        switch self {
        case .overview:
            return [
                BlockInfo(id: "wealth", title: "Vermogen", symbol: "chart.pie"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full"),
                BlockInfo(id: "invest", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis"),
                BlockInfo(id: "upcoming", title: "Komende dagen", symbol: "calendar.badge.clock")
            ]
        case .month:
            return [
                BlockInfo(id: "flow", title: "Waar gaat je geld heen", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "income", title: "Inkomen", symbol: "eurosign.circle"),
                BlockInfo(id: "expenses", title: "Uitgaven", symbol: "creditcard"),
                BlockInfo(id: "distribute", title: "Verdelen", symbol: "square.split.2x2"),
                BlockInfo(id: "bank", title: "Bankrekening", symbol: "building.columns"),
                BlockInfo(id: "days", title: "Dag voor dag", symbol: "list.bullet.rectangle")
            ]
        case .saving:
            return [
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full"),
                BlockInfo(id: "portfolio", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis")
            ]
        case .planning:
            return [
                BlockInfo(id: "goals", title: "Doelen", symbol: "flag.checkered"),
                BlockInfo(id: "buffer", title: "Noodbuffer", symbol: "shield.lefthalf.filled"),
                BlockInfo(id: "accelerators", title: "Versnellers", symbol: "bolt"),
                BlockInfo(id: "projection", title: "Toekomstschatting", symbol: "calendar.badge.clock"),
                BlockInfo(id: "purchase", title: "Aankoopcheck", symbol: "cart")
            ]
        case .home:
            return [
                BlockInfo(id: "overview", title: "Overzicht", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full.fill"),
                BlockInfo(id: "invest", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis")
            ]
        case .savings:
            return [
                BlockInfo(id: "period", title: "Overzicht", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "income", title: "Inkomen", symbol: "eurosign.circle.fill"),
                BlockInfo(id: "bank", title: "Bankrekening", symbol: "building.columns.fill"),
                BlockInfo(id: "distribute", title: "Verdelen", symbol: "square.split.2x2.fill"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full.fill"),
                BlockInfo(id: "buffer", title: "Noodbuffer", symbol: "shield.lefthalf.filled"),
                BlockInfo(id: "portfolio", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis"),
                BlockInfo(id: "goals", title: "Doelen", symbol: "flag.checkered")
            ]
        case .tools:
            return [
                BlockInfo(id: "accelerators", title: "Versnellers", symbol: "bolt.fill"),
                BlockInfo(id: "projection", title: "Toekomstschatting", symbol: "calendar.badge.clock"),
                BlockInfo(id: "purchase", title: "Aankoopcheck", symbol: "cart")
            ]
        }
    }
}

// MARK: - Opslaan en uitrekenen

extension AppSettings {
    /// De blokken van een pagina in de volgorde van de gebruiker. Een opgeslagen volgorde onder de oude sleutels wordt eerst
    /// omgezet (`BlockOrderMigration`, alleen lezen). Onbekende of dubbele id's worden overgeslagen en blokken die nog niet
    /// in de opgeslagen lijst staan (nieuwe blokken) komen achteraan, in de standaardvolgorde.
    func orderedBlocks(for page: BlockPage) -> [BlockInfo] {
        let defaults = page.blocks
        let stored: [String: [String]] = page.isLegacy ? blockOrder : BlockOrderMigration.migrate(blockOrder)
        var result: [BlockInfo] = []
        var seen = Set<String>()
        for id in stored[page.key] ?? [] {
            guard !seen.contains(id), let info = defaults.first(where: { $0.id == id }) else { continue }
            seen.insert(id)
            result.append(info)
        }
        for info in defaults where !seen.contains(info.id) {
            result.append(info)
        }
        return result
    }

    func blockIDs(for page: BlockPage) -> [String] {
        orderedBlocks(for: page).map(\.id)
    }
}

@MainActor
extension AppStore {
    /// Bewaart de volgorde van een pagina. De standaardvolgorde wordt niet apart opgeslagen, behalve als er nog een volgorde
    /// onder een oude sleutel staat: dan blijft de keuze voor de standaard expliciet staan, anders zou de oude volgorde bij het
    /// lezen weer terugkomen.
    func setBlockOrder(_ ids: [String], for page: BlockPage) {
        let isDefault = ids == page.blocks.map(\.id)
        mutate { d in
            let keepExplicit = !page.isLegacy && BlockOrderMigration.hasLegacyKeys(d.settings.blockOrder)
            if isDefault && !keepExplicit {
                d.settings.blockOrder[page.key] = nil
            } else {
                d.settings.blockOrder[page.key] = ids
            }
        }
    }

    /// Schuift een blok een plek op (offset -1 = omhoog, +1 = omlaag).
    func moveBlock(_ id: String, by offset: Int, in page: BlockPage) {
        var ids = data.settings.blockIDs(for: page)
        guard let from = ids.firstIndex(of: id) else { return }
        let to = from + offset
        guard ids.indices.contains(to) else { return }
        ids.swapAt(from, to)
        setBlockOrder(ids, for: page)
    }
}

// MARK: - De blokken van een pagina, in de eigen volgorde

/// Geeft per blok-id van de pagina een view, in de volgorde die de gebruiker koos. Alleen de blokken: de kern van de pagina
/// staat erboven. Gebruik het binnen `EqualSizeGrid` of een `LazyVGrid`. Elk blok krijgt het contextmenu om de volgorde aan
/// te passen (alleen op een pagina met drie of meer blokken).
struct OrderedBlocks<Content: View>: View {
    let page: BlockPage
    private let content: (String) -> Content
    @Environment(AppStore.self) private var store

    init(page: BlockPage, @ViewBuilder content: @escaping (String) -> Content) {
        self.page = page
        self.content = content
    }

    var body: some View {
        ForEach(store.data.settings.blockIDs(for: page), id: \.self) { id in
            content(id)
                .blockOrderMenu(page: page, id: id)
        }
    }
}

// MARK: - Contextmenu (lang indrukken)

/// Lang indrukken op een blok: "Volgorde aanpassen…" en snel een plek omhoog of omlaag. Een gewone tik blijft het blok
/// openen. Op een pagina met minder dan drie blokken is er geen menu.
@MainActor
struct BlockOrderMenu: ViewModifier {
    let page: BlockPage
    let id: String
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if page.allowsOrdering {
            let ids = store.data.settings.blockIDs(for: page)
            let index = ids.firstIndex(of: id) ?? 0
            let canMoveUp = index > 0
            let canMoveDown = index < ids.count - 1
            content
                #if os(iOS)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                #endif
                .contextMenu {
                    Button {
                        router.orderPage = page
                    } label: {
                        Label("Volgorde aanpassen…", systemImage: "arrow.up.arrow.down")
                    }
                    if canMoveUp {
                        Button { move(-1) } label: { Label("Naar boven", systemImage: "arrow.up") }
                    }
                    if canMoveDown {
                        Button { move(1) } label: { Label("Naar beneden", systemImage: "arrow.down") }
                    }
                }
        } else {
            content
        }
    }

    private func move(_ offset: Int) {
        withAnimation(reduceMotion ? nil : Theme.motion) {
            store.moveBlock(id, by: offset, in: page)
        }
    }
}

extension View {
    /// Voegt het contextmenu toe waarmee je de volgorde van de blokken op een pagina aanpast.
    @MainActor
    func blockOrderMenu(page: BlockPage, id: String) -> some View {
        modifier(BlockOrderMenu(page: page, id: id))
    }
}

// MARK: - Menu in de werkbalk

private struct BlockOrderToolbar: ViewModifier {
    let page: BlockPage
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content
            .toolbar {
                if page.allowsOrdering {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                router.orderPage = page
                            } label: {
                                Label("Volgorde aanpassen…", systemImage: "arrow.up.arrow.down")
                            }
                        } label: {
                            Label("Meer", systemImage: "ellipsis")
                        }
                        .help("Meer")
                    }
                }
            }
    }
}

extension View {
    /// Een menu in de werkbalk van een tabroot met "Volgorde aanpassen…" (opent `BlockOrderSheet`). Alleen bij pagina's met
    /// drie of meer blokken: bij minder is er niets te ordenen en komt er geen menu.
    func blockOrderToolbar(page: BlockPage) -> some View {
        modifier(BlockOrderToolbar(page: page))
    }

    /// Zet een `List` altijd in bewerkmodus (iOS), zodat de rijen direct versleept kunnen worden. Op de Mac sleep je zonder
    /// bewerkmodus.
    @ViewBuilder
    func blockOrderEditing() -> some View {
        #if os(iOS)
        self.environment(\.editMode, .constant(.active))
        #else
        self
        #endif
    }
}

// MARK: - De lijst "Volgorde aanpassen"

/// De blokken van een pagina als sectie in een `List`: sleep ze naar een andere plek, elke verandering wordt meteen
/// bewaard, en "Standaardvolgorde" zet ze terug. Zet meerdere pagina's in een `List` met `.blockOrderEditing()` erop.
struct BlockOrderSection: View {
    let page: BlockPage
    @Environment(AppStore.self) private var store

    var body: some View {
        let blocks = store.data.settings.orderedBlocks(for: page)
        let isDefault = blocks.map(\.id) == page.blocks.map(\.id)
        Section {
            ForEach(blocks) { block in
                HStack(spacing: 12) {
                    SymbolBadge(symbol: block.symbol, color: Theme.textSecondary, size: 32)
                    Text(block.title)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.minTapTarget)
                .accessibilityElement(children: .combine)
            }
            .onMove { source, destination in
                var ids = blocks.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                store.setBlockOrder(ids, for: page)
            }
        } header: {
            SectionHeader(page.title)
        } footer: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sleep de blokken in de volgorde die je wilt.")
                ActionButton(title: "Standaardvolgorde", symbol: "arrow.counterclockwise") {
                    store.setBlockOrder(page.blocks.map(\.id), for: page)
                }
                .disabled(isDefault)
            }
            .padding(.top, 4)
        }
    }
}

/// De blokken van een pagina als eigen `List` in bewerkmodus: een pagina in Instellingen, Indeling of de inhoud van
/// `BlockOrderSheet`. Zonder achtergrond en zonder navigatiestapel: de aanroeper geeft de titel en de achtergrond.
struct BlockOrderList: View {
    let page: BlockPage

    init(page: BlockPage) {
        self.page = page
    }

    var body: some View {
        List {
            BlockOrderSection(page: page)
        }
        .blockOrderEditing()
    }
}

// MARK: - Het blad "Volgorde aanpassen"

/// Kort blad met de blokken van een pagina, geopend met `router.orderPage`. Elke verandering wordt meteen bewaard, dus er is
/// alleen "Klaar".
struct BlockOrderSheet: View {
    let page: BlockPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BlockOrderList(page: page)
                .navigationTitle("Volgorde aanpassen")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Klaar") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }
}
