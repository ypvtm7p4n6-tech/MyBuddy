import SwiftUI

// TIJDELIJKE STUB: wordt vervangen door de echte buffercalculator.
struct BufferPage: View {
    var body: some View {
        PageScaffold(title: "Buffer") { Text("Buffercalculator") }
    }
}

struct BufferBlock: View {
    var body: some View {
        LinkedBlock(title: "Buffer", symbol: "shield.lefthalf.filled", destination: .buffer) { Text("Buffercalculator") }
    }
}
