import SwiftUI

/// Tab 1, Home: wat er nu is, in de stijl van Apple Muziek en Apple TV (par. 1.3 en 3 van docs/design2/plan.md). Bovenaan de
/// meldingen, dan de hero (een carrousel met Nog te verdelen, Vermogen en Saldo vandaag) en daaronder vijf planken: Komende dagen,
/// Spaarpotten, Beleggingen, Doelen en Hulpmiddelen, in de volgorde van de gebruiker (`Shelf(orderID:)`). Zonder gegevens
/// (`isEmptyStart`) staat er een welkomstkaart in plaats van hero en planken. De achtergrond volgt de kleur van de zichtbare
/// hero-kaart. Home gaat altijd over de huidige maand en leest `focusMonth` en `periodMode` niet (K17); een pagina van een maand
/// opent op de huidige maand (`showsCurrentMonth`). Alleen inhoud: de `NavigationStack` komt van `TabStack`.
struct HomeTab: View {
    @Environment(AppStore.self) private var store
    /// De zichtbare hero-kaart; hij bepaalt de kleur van de achtergrond.
    @State private var selectedHero: String? = HomeHeroID.startID()
    /// Het blad dat Home nu toont: alle bladen van de hero en de planken gaan door dit ene blad-item.
    @State private var sheet: HomeSheet?

    var body: some View {
        PageScaffold(title: "Home", large: true, fullBleed: true) {
            HomeContent(selectedHero: $selectedHero, present: { item in sheet = item })
        }
        .environment(\.backdropHue, backdropHue)
        .profileToolbarItem()
        .sheet(item: $sheet) { item in
            HomeSheetContent(item: item)
        }
    }

    /// De tint van het kleurverloop: die van de zichtbare hero-kaart, olijf zolang er geen hero is (lege start).
    private var backdropHue: TileHue {
        if store.data.isEmptyStart { return .olive }
        return HomeHeroID.hue(for: selectedHero)
    }
}

/// Meldingen, hero en planken, of de welkomstkaart. Elk onderdeel zorgt voor zijn eigen marge: hero en planken lopen tot de rand.
private struct HomeContent: View {
    @Binding var selectedHero: String?
    let present: HomePresent
    @Environment(AppStore.self) private var store
    @Environment(\.syncController) private var sync

    var body: some View {
        let notices = HomeNoticeState.current(store: store, sync: sync)
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            if notices.hasAny {
                HomeNotices(state: notices)
            }
            if store.data.isEmptyStart {
                HomeWelcome()
            } else {
                HomeHeroSection(selection: $selectedHero, present: present)
                HomeShelfStack(present: present)
            }
        }
    }
}
