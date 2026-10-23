import SwiftUI

/// TIJDELIJKE wortel van de Bibliotheek (pakket 1, tot pakket 2B hem vervangt): een lijst met de drie groepen en dertien rijen
/// uit `PageCatalog`. De rijen van "Deze maand" openen op de huidige maand (B8). Elke rij gaat naar zijn pagina op de stapel
/// van deze tab; de profielknop rechtsboven opent Instellingen.
struct LibraryTab: View {
    var body: some View {
        ListScaffold(title: "Bibliotheek", large: true) {
            ForEach(LibrarySection.allCases) { section in
                Section {
                    ForEach(PageCatalog.library(in: section)) { info in
                        MediaRow(symbol: info.symbol, hue: info.hue, title: info.title, destination: info.destination,
                                 showsCurrentMonth: section == .month)
                    }
                } header: {
                    SectionHeader(section.title)
                }
            }
        }
        .profileToolbarItem()
    }
}
