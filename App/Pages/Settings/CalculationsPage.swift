import SwiftUI

/// De pagina Rekenen (`.settings(.calculations)`): de aannames waarmee MyBuddy rekent, en de actuele cijfers van internet.
/// Het minimumsaldo van je bankrekening staat niet hier maar bij Bankrekening (een plek, een naam).
struct CalculationsPage: View {
    @Environment(AppStore.self) private var store

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: keyPath] },
                set: { value in store.mutate { $0.settings[keyPath: keyPath] = value } })
    }

    var body: some View {
        ListScaffold(title: "Rekenen") {
            assumptionsSection
            MarketDataSection()
        }
    }

    private var assumptionsSection: some View {
        Section {
            NumberRow(title: "Inflatie per jaar", value: setting(\.inflation), unit: .percent, maxDigits: 2)
            NumberRow(title: "Spaarrente", value: setting(\.savingsRate), unit: .percent, maxDigits: 2)
            NumberRow(title: "Opnamepercentage voor nieuwe doelen", value: setting(\.defaultWithdrawalRate),
                      unit: .percent, maxDigits: 2)
        } header: {
            SectionHeader("Aannames")
        } footer: {
            SettingsFootnote("Inflatie gebruikt MyBuddy voor 'koopkracht van vandaag'. Het opnamepercentage is de beginwaarde voor een nieuw doel; per doel pas je het aan.")
        }
    }
}
