import SwiftUI

/// De pagina Instellingen (`Destination.settingsRoot`): een korte lijst van vier groepen en zes rijen, elke rij met een korte
/// waarde eronder en een pijltje naar een eigen pagina. Account staat bovenaan en los van de rest. Het is een gepushte
/// pagina op de stapel van de tab waar je bent (de profielknop rechtsboven op Home, Bibliotheek en Zoeken), met een
/// terugknop: nooit een sheet en geen "Klaar"-knop. Op de Mac staat Instellingen in het `Settings`-venster (`SettingsPane`).
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.syncController) private var sync

    var body: some View {
        ListScaffold(title: "Instellingen", large: true) {
            accountSection
            calculationSection
            dataSection
            aboutSection
        }
    }

    // MARK: Groepen

    private var accountSection: some View {
        Section {
            SettingsLinkRow(page: .account,
                            title: accountTitle,
                            subtitle: accountStatus.text,
                            symbol: "person.crop.circle",
                            showsAvatar: true,
                            needsAttention: accountStatus.needsAttention)
        }
    }

    private var calculationSection: some View {
        Section {
            SettingsLinkRow(page: .calculations, subtitle: calculationsSummary)
            SettingsLinkRow(page: .prices, subtitle: pricesSummary)
        }
    }

    private var dataSection: some View {
        Section {
            SettingsLinkRow(page: .data, subtitle: "Back-up, importeren, exporteren")
            SettingsLinkRow(page: .layout, subtitle: "Volgorde van de blokken")
        }
    }

    private var aboutSection: some View {
        Section {
            SettingsLinkRow(page: .about, subtitle: SettingsText.versionText(short: SettingsText.appVersionShort))
        }
    }

    // MARK: Waarden

    /// Het e-mailadres (met een lokaal account de naam, als die er is).
    private var accountTitle: String {
        if FirebaseConfig.isConfigured, let user = cloud?.user {
            return user.email
        }
        if let account = auth.currentAccount {
            return account.displayName ?? account.email
        }
        return "Account"
    }

    /// De synchronisatiestatus onder het e-mailadres. Een conflict of een aanbod om lokale gegevens te uploaden is "Actie nodig".
    private var accountStatus: SyncSummary {
        let attention = sync?.importOffer != nil || sync?.conflict != nil
        return SettingsText.syncSummary(isConfigured: FirebaseConfig.isConfigured,
                                        status: sync?.displayStatus,
                                        needsAttention: attention)
    }

    private var calculationsSummary: String {
        let settings = store.data.settings
        return SettingsText.calculationsSummary(inflation: settings.inflation, savingsRate: settings.savingsRate)
    }

    private var pricesSummary: String {
        SettingsText.pricesSummary(automatic: store.data.settings.autoRefreshPrices, lastRefresh: store.lastPriceRefresh)
    }
}
