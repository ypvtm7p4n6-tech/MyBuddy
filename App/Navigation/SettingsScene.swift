#if os(macOS)
import SwiftUI

/// Het `Settings`-venster van de Mac (Cmd+komma, App-menu). Instellingen is daar geen tab maar een eigen venster met zes
/// panes: Account, Rekenen, Koersen, Gegevens, Indeling en Over. De scene heeft de gegevens van de actieve sessie nodig
/// (`ActiveSession`); `auth` en `cloud` staan op `MyBuddyApp` en komen er expliciet in.
/// TIJDELIJK (tot golf 1c): elke pane toont nog de oude `SettingsView`; daarna `SettingsPane(page:)`.
struct SettingsScene: Scene {
    let session: ActiveSession
    let auth: AuthStore
    let cloud: CloudAccount

    init(session: ActiveSession, auth: AuthStore, cloud: CloudAccount) {
        self.session = session
        self.auth = auth
        self.cloud = cloud
    }

    var body: some Scene {
        Settings {
            SettingsSceneContent(session: session, auth: auth, cloud: cloud)
        }
    }
}

/// Zonder actieve sessie (niemand is ingelogd) is er niets om in te stellen.
private struct SettingsSceneContent: View {
    let session: ActiveSession
    let auth: AuthStore
    let cloud: CloudAccount

    var body: some View {
        if let store = session.store, let router = session.router {
            SettingsPanes(router: router)
                .environment(store)
                .environment(router)
                .environment(auth)
                .environment(\.cloudAccount, cloud)
                .environment(\.syncController, session.sync)
        } else {
            ContentUnavailableView(
                "Log eerst in",
                systemImage: "person.crop.circle",
                description: Text("Instellingen zijn er zodra je bent ingelogd.")
            )
            .frame(width: 520, height: 320)
        }
    }
}

/// De zes panes. De laatst gebruikte pane wordt onthouden; een diepe link (`router.go(.settings(_))`) zet
/// `router.settingsRequest`, waarna hier de pane van die pagina opent en het verzoek wordt gewist.
private struct SettingsPanes: View {
    let router: Router
    @AppStorage("settings.pane") private var paneRaw = SettingsPage.account.rawValue

    private var selection: Binding<SettingsPage> {
        Binding(
            get: { SettingsPage(rawValue: paneRaw)?.pane ?? SettingsPage.account },
            set: { page in paneRaw = page.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            Tab("Account", systemImage: "person.crop.circle", value: SettingsPage.account) {
                SettingsView()
            }
            Tab("Rekenen", systemImage: "percent", value: SettingsPage.calculations) {
                SettingsView()
            }
            Tab("Koersen", systemImage: "arrow.triangle.2.circlepath", value: SettingsPage.prices) {
                SettingsView()
            }
            Tab("Gegevens", systemImage: "externaldrive", value: SettingsPage.data) {
                SettingsView()
            }
            Tab("Indeling", systemImage: "arrow.up.arrow.down", value: SettingsPage.layout) {
                SettingsView()
            }
            Tab("Over MyBuddy", systemImage: "info.circle", value: SettingsPage.about) {
                SettingsView()
            }
        }
        .frame(width: 520)
        .onAppear { consumeRequest() }
        .onChange(of: router.settingsRequest) { _, _ in consumeRequest() }
    }

    private func consumeRequest() {
        guard let page = router.settingsRequest else { return }
        paneRaw = page.pane.rawValue
        router.settingsRequest = nil
    }
}
#endif
