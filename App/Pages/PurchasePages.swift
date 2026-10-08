import SwiftUI

// Tijdelijke plaatsvervangers; worden vervangen door de aankoopcheck.

struct PurchaseBlock: View {
    var body: some View {
        LinkedBlock(title: "Aankoopcheck", symbol: "cart", subtitle: "Is het je werkuren waard?", destination: .purchase) {
            Text("Binnenkort.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct PurchasePage: View {
    var body: some View {
        PageScaffold(title: "Aankoopcheck") { Text("Binnenkort.") }
    }
}
