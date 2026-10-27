import SwiftUI

/// De pagina Indeling (`.settings(.layout)`): de volgorde van de blokken op Home (Komende dagen, Spaarpotten, Beleggingen,
/// Doelen en Hulpmiddelen), met slepen en "Standaardvolgorde". De hero-kaarten bovenaan en de Bibliotheek staan vast. Elke
/// verandering wordt meteen bewaard. De lijst staat in bewerkmodus (`blockOrderEditing`), zodat de rijen direct versleept
/// kunnen worden.
struct LayoutPage: View {
    /// Alleen een pagina met drie of meer blokken valt te ordenen: dat is nu alleen Home.
    private var pages: [BlockPage] {
        BlockPage.allCases.filter { $0.allowsOrdering }
    }

    var body: some View {
        ListScaffold(title: "Indeling") {
            ForEach(pages) { page in
                BlockOrderSection(page: page)
            }
        }
        .blockOrderEditing()
    }
}
