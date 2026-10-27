import SwiftUI

// De volgorde van de blokken op een pagina (par. 2.7 van docs/design/plan.md en B16 van docs/design2/plan.md). De gebruiker kiest
// de volgorde zelf: via Instellingen, Indeling en via lang indrukken op een plankkop op Home. Een opgeslagen volgorde onder de
// oude sleutels (`home`, `savings`, `tools`) wordt bij het lezen omgezet (`BlockOrderMigration`). De pagina's en hun blokken
// (`BlockPage`, `BlockInfo`) en het uitrekenen van de volgorde (`AppSettings.orderedBlocks`) staan zonder SwiftUI in
// `BlockOrderMigration.swift`, zodat ze getest worden.

// MARK: - Opslaan

@MainActor
extension AppStore {
    /// Bewaart de volgorde van een pagina. De standaardvolgorde wordt niet apart opgeslagen, behalve als er nog een volgorde
    /// onder een oude sleutel staat: dan blijft de keuze voor de standaard expliciet staan, anders zou de oude volgorde bij het
    /// lezen weer terugkomen.
    func setBlockOrder(_ ids: [String], for page: BlockPage) {
        let isDefault = ids == page.blocks.map(\.id)
        mutate { d in
            let keepExplicit = BlockOrderMigration.hasLegacyKeys(d.settings.blockOrder)
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

// MARK: - Bewerkmodus

extension View {
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
