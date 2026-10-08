import SwiftUI

// TIJDELIJKE STUB: wordt vervangen door de echte spaardoel-calculator.
struct SavingsGoalPage: View {
    var body: some View {
        PageScaffold(title: "Spaardoel") { Text("Spaardoel-calculator") }
    }
}

struct SavingsGoalBlock: View {
    var body: some View {
        LinkedBlock(title: "Spaardoel", symbol: "target", destination: .savingsGoal) { Text("Spaardoel-calculator") }
    }
}
