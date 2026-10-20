import SwiftUI

@main
struct MyBuddyApp: App {
    @State private var auth = AuthStore()
    /// Inloggen en synchroniseren via Firebase. Zonder sleutel in `FirebaseConfig` doet dit niets.
    @State private var cloud = CloudAccount()
    /// De sessie waarin nu gewerkt wordt (store, router, synchronisatie): de menubalk en het Instellingen-venster van de Mac
    /// lezen die. `SignedInRoot` en de voorbeeldsessie registreren zich hierin.
    @State private var session = ActiveSession()
    #if DEBUG
    @State private var demo: DemoSession? = nil
    #endif

    init() {
        #if DEBUG
        if DebugLaunch.isDemo {
            _demo = State<DemoSession?>(initialValue: DemoSession())
        }
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // Eén venster, geen "Nieuw venster": elk extra venster zou een eigen AppStore en synchronisatie starten
        // voor hetzelfde gegevensbestand en elkaars wijzigingen overschrijven of als conflict zien.
        Window("MyBuddy", id: "main") {
            windowContent
        }
        .defaultSize(width: 860, height: 920)
        .commands { AppCommands(session: session) }

        // Instellingen is op de Mac een eigen venster (Cmd+komma), geen tab.
        SettingsScene(session: session, auth: auth, cloud: cloud)
        #else
        WindowGroup {
            windowContent
        }
        .commands { AppCommands(session: session) }
        #endif
    }

    private var windowContent: some View {
        content
            .environment(session)
            .tint(Theme.accent)
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 640)
            #endif
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if let demo {
            RootView()
                .environment(demo.store)
                .environment(demo.router)
                .environment(auth)
                .environment(\.cloudAccount, cloud)
                .registered(in: session, store: demo.store, router: demo.router, sync: nil)
        } else {
            AppRoot()
                .environment(auth)
                .environment(\.cloudAccount, cloud)
        }
        #else
        AppRoot()
            .environment(auth)
            .environment(\.cloudAccount, cloud)
        #endif
    }
}

/// Toont het inlogscherm of, na inloggen, de app met de gegevens van dat account.
/// Met een Firebase-sleutel loggen gebruikers in via de cloud; zonder sleutel zijn het lokale accounts.
struct AppRoot: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wie er nu is ingelogd (cloud of lokaal); een wissel laat het scherm zacht overvloeien.
    private var sessionKey: String {
        if FirebaseConfig.isConfigured, let cloud {
            return "cloud-" + (cloud.user?.uid ?? "uit")
        }
        return "lokaal-" + (auth.currentAccount?.id.uuidString ?? "uit")
    }

    var body: some View {
        content
            // Bij Verlaag beweging wisselt het scherm zonder overvloeien.
            .animation(reduceMotion ? nil : Theme.motion, value: sessionKey)
    }

    @ViewBuilder
    private var content: some View {
        if FirebaseConfig.isConfigured, let cloud {
            if let user = cloud.user {
                SignedInRoot(storageURL: cloud.storageURL(for: user), cloud: CloudSession(account: cloud, user: user))
                    .id(user.uid)
                    .transition(.opacity)
            } else {
                AuthView()
                    .transition(.opacity)
            }
        } else if let account = auth.currentAccount {
            SignedInRoot(storageURL: auth.storageURL(for: account))
                .id(account.id)
                .transition(.opacity)
        } else {
            AuthView()
                .transition(.opacity)
        }
    }
}

/// De cloudgegevens die `SignedInRoot` nodig heeft om te synchroniseren.
struct CloudSession {
    let account: CloudAccount
    let user: CloudUser
}

/// De app voor één ingelogd account: eigen opslagbestand, eigen navigatie, en (met een cloudaccount) synchronisatie.
struct SignedInRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ActiveSession.self) private var session
    @State private var store: AppStore
    @State private var router = Router()
    @State private var sync: SyncController?

    init(storageURL: URL, cloud: CloudSession? = nil) {
        let newStore = AppStore(storage: FinanceStorage(url: storageURL))
        _store = State(initialValue: newStore)
        if let cloud {
            _sync = State<SyncController?>(initialValue: SyncController(
                store: newStore,
                account: cloud.account,
                user: cloud.user,
                directory: storageURL.deletingLastPathComponent()))
        } else {
            _sync = State<SyncController?>(initialValue: nil)
        }
    }

    var body: some View {
        RootView()
            .environment(store)
            .environment(router)
            .environment(\.syncController, sync)
            .registered(in: session, store: store, router: router, sync: sync)
            .syncPrompts(sync)
            .task { await sync?.run() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: sync?.appBecameActive()
                case .background: sync?.appMovedToBackground()
                default: break
                }
            }
    }
}

#if DEBUG
/// Voorbeeldsessie voor screenshots: geen account, geen opslag, vaste koersen.
@MainActor
final class DemoSession {
    let store: AppStore
    let router: Router

    init() {
        let demoStore = AppStore(storage: nil, quotes: DemoQuoteService())
        demoStore.loadSampleData()
        let demoRouter = Router()
        DebugLaunch.apply(to: demoRouter, store: demoStore)
        store = demoStore
        router = demoRouter
    }
}
#endif
