import SwiftUI

@main
struct MyBuddyApp: App {
    @State private var store: AppStore
    @State private var router: Router

    init() {
        #if DEBUG
        if DebugLaunch.isDemo {
            let demoStore = AppStore(storage: nil, quotes: DemoQuoteService())
            demoStore.loadSampleData()
            let demoRouter = Router()
            DebugLaunch.apply(to: demoRouter, store: demoStore)
            _store = State(initialValue: demoStore)
            _router = State(initialValue: demoRouter)
            return
        }
        #endif
        _store = State(initialValue: AppStore())
        _router = State(initialValue: Router())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .tint(Theme.accent)
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 860, height: 920)
        #endif
    }
}
