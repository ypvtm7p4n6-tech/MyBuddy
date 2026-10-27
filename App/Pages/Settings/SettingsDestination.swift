import SwiftUI

/// De pagina bij een `SettingsPage`: de inhoud van alle tien bestemmingen onder `Destination.settings(_)`. Heeft geen eigen
/// `NavigationStack`: de stapel komt van `TabStack` (iPhone en iPad, achter de profielknop) of van `SettingsPane` (Mac). Het
/// kleurverloop erachter is saliegrijs (`DestinationView` of `SettingsPane` zet het).
struct SettingsDestination: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .account:
            AccountPage()
        case .password:
            PasswordPage()
        case .deleteAccount:
            DeleteAccountPage()
        case .conflictBackups:
            ConflictBackupsPage()
        case .calculations:
            CalculationsPage()
        case .prices:
            PricesPage()
        case .data:
            DataPage()
        case .layout:
            LayoutPage()
        case .about:
            AboutPage()
        case .importReview:
            SpreadsheetImportPage()
        }
    }
}

/// Een pane van het `Settings`-venster op de Mac (Account, Rekenen, Koersen, Gegevens, Indeling, Over MyBuddy). Elke pane
/// heeft een eigen `NavigationStack`: Wachtwoord wijzigen, Account verwijderen, Back-ups van conflicten en het
/// Importoverzicht zijn pushes in de stapel van de pane waar ze bij horen. Een diepe link naar zo'n subpagina
/// (`router.go(.settings(.password))`) komt hier als `subpageRequest` binnen: hoort de subpagina bij deze pane, dan gaat de
/// pane ernaartoe en wordt het verzoek gewist.
struct SettingsPane: View {
    let page: SettingsPage
    @Binding private var subpageRequest: SettingsPage?
    @State private var path: [Destination] = []

    init(page: SettingsPage, subpageRequest: Binding<SettingsPage?> = .constant(nil)) {
        self.page = page
        _subpageRequest = subpageRequest
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsDestination(page: page)
                .navigationDestination(for: Destination.self) { destination in
                    SettingsPaneDestination(destination: destination)
                }
        }
        .environment(\.openSettingsPage, { subpage in
            path = NavigationRules.push(Destination.settings(subpage), onto: path)
        })
        .environment(\.backdropHue, .sage)
        .onAppear { openRequestedSubpage() }
        .onChange(of: subpageRequest) { _, _ in openRequestedSubpage() }
        #if os(macOS)
        .frame(minHeight: 440)
        #endif
    }

    /// Gaat naar de gevraagde subpagina als die bij deze pane hoort; een andere pane laat het verzoek staan.
    private func openRequestedSubpage() {
        guard let subpage = subpageRequest, subpage.pane == page else { return }
        path = [Destination.settings(subpage)]
        subpageRequest = nil
    }
}

/// Wat een push in de stapel van een pane toont: alleen instellingenpagina's.
private struct SettingsPaneDestination: View {
    let destination: Destination

    var body: some View {
        switch destination {
        case .settings(let subpage):
            SettingsDestination(page: subpage)
        default:
            EmptyView()
        }
    }
}
