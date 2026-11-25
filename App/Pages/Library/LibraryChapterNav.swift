import SwiftUI

/// De rij bovenaan de Bibliotheek, zoals de "chapter nav" van apple.com/iphone: elke pagina als klein pictogram met een korte naam in
/// één horizontale rij, zodat je de hele Bibliotheek in één blik ziet en met één tik ergens bent. De pagina's, namen, symbolen en
/// tinten komen uit `PageCatalog` (dezelfde als de rijen eronder); een maandpagina opent op de huidige maand.
struct LibraryChapterNav: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(PageCatalog.library) { info in
                    Button {
                        if info.section == .month { router.showCurrentMonth(store.now) }
                        router.open(info.destination)
                    } label: {
                        VStack(spacing: 6) {
                            ArtworkTile(symbol: info.symbol, hue: info.hue, size: .row)
                            Text(info.title)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 76)
                        }
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(info.title)
                    .accessibilityAddTraits(.isLink)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alle pagina's")
    }
}
