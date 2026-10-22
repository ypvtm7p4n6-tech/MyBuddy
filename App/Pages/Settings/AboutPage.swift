import SwiftUI

/// De pagina Over MyBuddy (`.settings(.about)`): de versie uit de bundel, de disclaimer en "Bronnen en privacy".
struct AboutPage: View {
    var body: some View {
        ListScaffold(title: "Over MyBuddy") {
            versionSection
            disclaimerSection
            sourcesSection
            privacySection
        }
    }

    private var versionSection: some View {
        Section {
            LabeledContent("MyBuddy", value: SettingsText.detailedVersionText(short: SettingsText.appVersionShort,
                                                                              build: SettingsText.appBuild))
                .frame(minHeight: Theme.minTapTarget)
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text("Een persoonlijke indicatie, geen financieel advies. Rendementen uit het verleden zijn geen garantie voor de toekomst.")
                .font(.subheadline)
        } header: {
            SectionHeader("Let op")
        }
    }

    /// Waar de cijfers vandaan komen.
    private var sourcesSection: some View {
        Section {
            sourceRow(title: "Koersen",
                      detail: "Yahoo Finance, met Stooq en CoinGecko als reserve. Het zijn gratis, onofficiële bronnen zonder garantie op beschikbaarheid of juistheid.")
            sourceRow(title: "Inflatie",
                      detail: "Wereldbank, het laatst bekende jaar.")
            sourceRow(title: "Spaarrente",
                      detail: "De depositorente van de Europese Centrale Bank. Dat is een richtpunt: banken geven vaak iets minder.")
        } header: {
            SectionHeader("Bronnen")
        }
    }

    /// Wat er met je gegevens gebeurt.
    private var privacySection: some View {
        Section {
            if FirebaseConfig.isConfigured {
                sourceRow(title: "Synchronisatie",
                          detail: "Met een cloudaccount gaan je gegevens versleuteld (HTTPS) naar je eigen Firebase-database en blijven ze ook op dit apparaat staan. Ze zijn niet end-to-end versleuteld: wie toegang heeft tot je Firebase-project kan ze lezen. Zonder internet werk je gewoon door.")
            } else {
                sourceRow(title: "Op dit apparaat",
                          detail: "Alles wordt alleen op dit apparaat bewaard. Accounts zijn lokaal: er is geen server en geen synchronisatie tussen apparaten.")
            }
            sourceRow(title: "Back-ups en exports",
                      detail: "Een back-up of export bevat al je persoonlijke gegevens. Bewaar hem op een veilige plek en deel hem niet zomaar.")
        } header: {
            SectionHeader("Privacy")
        }
    }

    private func sourceRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
