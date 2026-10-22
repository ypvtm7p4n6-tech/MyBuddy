import SwiftUI

/// De pagina bij een `SettingsPage`: de inhoud van alle tien bestemmingen onder `Destination.settings(_)`. Heeft geen eigen
/// `NavigationStack`: de stapel komt van `TabStack` (iOS) of van `SettingsPane` (Mac).
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
/// Importoverzicht zijn pushes in de stapel van de pane waar ze bij horen.
struct SettingsPane: View {
    let page: SettingsPage
    @State private var path: [Destination] = []

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
        #if os(macOS)
        .frame(minHeight: 440)
        #endif
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
