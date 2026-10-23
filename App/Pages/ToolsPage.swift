import SwiftUI

/// Hulpmiddelen (`.tools`): de vier rekenpagina's Noodbuffer, Versnellers, Toekomstschatting en Aankoopcheck als lijst.
/// TIJDELIJK met rijen zonder uitlegregel (pakket 1, tot pakket 2B de uitleg per hulpmiddel toevoegt).
struct ToolsPage: View {
    private let tools: [Destination] = [.buffer, .accelerators, .projection, .purchase]

    var body: some View {
        ListScaffold(title: "Hulpmiddelen") {
            Section {
                ForEach(tools, id: \.self) { destination in
                    ToolsRow(destination: destination)
                }
            }
        }
    }
}

/// Eén rij van Hulpmiddelen, met titel, symbool en tint uit `PageCatalog`.
private struct ToolsRow: View {
    let destination: Destination

    var body: some View {
        if let info = PageCatalog.info(destination) {
            MediaRow(symbol: info.symbol, hue: info.hue, title: info.title, destination: destination)
        }
    }
}
