import SwiftUI

/// De pagina Indeling (`.settings(.layout)`): de volgorde van de blokken van elke tabpagina met drie of meer blokken (Overzicht,
/// Maand en Plannen), met slepen en "Standaardvolgorde". Elke verandering wordt meteen bewaard. De lijst staat in bewerkmodus
/// (`blockOrderEditing`), zodat de rijen direct versleept kunnen worden.
struct LayoutPage: View {
    /// Sparen heeft twee blokken: daar valt niets te ordenen.
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
