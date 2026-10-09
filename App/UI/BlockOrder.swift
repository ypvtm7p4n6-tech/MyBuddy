import SwiftUI

// MARK: - Welke blokken een pagina heeft

/// Eén blok van een pagina, met de naam en het icoon dat in het ordenen-blad staat.
struct BlockInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

/// De pagina's waarvan je de volgorde van de blokken zelf kunt kiezen.
/// De blok-id's staan ook in `docs/v3-spec.md`.
enum BlockPage: String, CaseIterable, Identifiable {
    case home, savings, tools

    var id: String { rawValue }

    /// Sleutel in `AppSettings.blockOrder`.
    var key: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .savings: return "Savings"
        case .tools: return "Tools"
        }
    }

    /// De blokken in de standaardvolgorde.
    var blocks: [BlockInfo] {
        switch self {
        case .home:
            return [
                BlockInfo(id: "overview", title: "Overzicht", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full.fill"),
                BlockInfo(id: "invest", title: "Beleggingen", symbol: "chart.line.uptrend.xyaxis")
            ]
        case .savings:
            return [
                BlockInfo(id: "period", title: "Overzicht", symbol: "chart.bar.xaxis"),
                BlockInfo(id: "income", title: "Salaris & inkomsten", symbol: "eurosign.circle.fill"),
                BlockInfo(id: "bank", title: "Bankrekening", symbol: "building.columns.fill"),
                BlockInfo(id: "distribute", title: "Verdelen", symbol: "square.split.2x2.fill"),
                BlockInfo(id: "pots", title: "Spaarpotten", symbol: "tray.full.fill"),
                BlockInfo(id: "buffer", title: "Buffer", symbol: "shield.lefthalf.filled"),
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
    /// De blokken van een pagina in de volgorde van de gebruiker. Onbekende of dubbele id's worden
    /// overgeslagen en blokken die nog niet in de opgeslagen lijst staan (nieuwe blokken) komen achteraan.
    func orderedBlocks(for page: BlockPage) -> [BlockInfo] {
        let defaults = page.blocks
        var result: [BlockInfo] = []
        var seen = Set<String>()
        for id in blockOrder[page.key] ?? [] {
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
    /// Bewaart de volgorde van een pagina. De standaardvolgorde wordt niet apart opgeslagen.
    func setBlockOrder(_ ids: [String], for page: BlockPage) {
        let isDefault = ids == page.blocks.map(\.id)
        mutate { d in
            if isDefault {
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

/// Geeft per blok-id van de pagina een view, in de volgorde die de gebruiker koos.
/// Gebruik het binnen `EqualSizeGrid` (Home) of een `LazyVGrid` (Savings, Tools). Elk blok krijgt
/// automatisch het contextmenu om de volgorde aan te passen.
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

/// Lang indrukken op een blok: "Volgorde aanpassen…" en snel een plek omhoog of omlaag.
/// Een gewone tik blijft het blok openen.
@MainActor
struct BlockOrderMenu: ViewModifier {
    let page: BlockPage
    let id: String
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
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
    }

    private func move(_ offset: Int) {
        withAnimation(Theme.motion) {
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

// MARK: - Het blad "Volgorde aanpassen"

/// Lijst met de blokken van een pagina. Altijd in bewerkmodus, dus je sleept ze direct naar een andere plek.
/// Elke verandering wordt meteen bewaard.
struct BlockOrderSheet: View {
    let page: BlockPage
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let blocks = store.data.settings.orderedBlocks(for: page)
        let isDefault = blocks.map(\.id) == page.blocks.map(\.id)
        NavigationStack {
            List {
                Section {
                    ForEach(blocks) { block in
                        HStack(spacing: 12) {
                            SymbolBadge(symbol: block.symbol, color: Theme.accent, size: 32)
                            Text(block.title)
                            Spacer(minLength: 0)
                        }
                    }
                    .onMove { source, destination in
                        var ids = blocks.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        withAnimation(Theme.motion) {
                            store.setBlockOrder(ids, for: page)
                        }
                    }
                } header: {
                    Text("Sleep de blokken van \(page.title) in de volgorde die je wilt.")
                        .textCase(nil)
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .scrollContentBackground(.hidden)
            .background { MeshBackground() }
            .safeAreaInset(edge: .bottom) {
                ChipButton(title: "Standaardvolgorde", symbol: "arrow.counterclockwise") {
                    withAnimation(Theme.motion) {
                        store.setBlockOrder(page.blocks.map(\.id), for: page)
                    }
                }
                .disabled(isDefault)
                .opacity(isDefault ? 0.45 : 1)
                .frame(maxWidth: 420)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Volgorde aanpassen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
