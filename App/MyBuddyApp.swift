import SwiftUI

@main
struct MyBuddyApp: App {
    @State private var auth = AuthStore()
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
        WindowGroup {
            content
                .tint(Theme.accent)
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 860, height: 920)
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
        } else {
            AppRoot().environment(auth)
        }
        #else
        AppRoot().environment(auth)
        #endif
    }
}

/// Toont het inlogscherm of, na inloggen, de app met de gegevens van dat account.
struct AppRoot: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        if let account = auth.currentAccount {
            SignedInRoot(storageURL: auth.storageURL(for: account))
                .id(account.id)
        } else {
            AuthView()
        }
    }
}

/// De app voor één ingelogd account: eigen opslagbestand, eigen navigatie.
struct SignedInRoot: View {
    @State private var store: AppStore
    @State private var router = Router()

    init(storageURL: URL) {
        _store = State(initialValue: AppStore(storage: FinanceStorage(url: storageURL)))
    }

    var body: some View {
        RootView()
            .environment(store)
            .environment(router)
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
