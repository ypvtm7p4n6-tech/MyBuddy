import SwiftUI
import Observation

/// De sessie waarin de gebruiker nu werkt: zijn `AppStore`, `Router` en (met een cloudaccount) `SyncController`.
/// `ActiveSession` staat boven alle scenes van de app, zodat ook de menubalk-commando's en het `Settings`-venster op de
/// Mac erbij kunnen. `SignedInRoot` (en de voorbeeldsessie) registreert zijn gegevens hierin zodra zijn scherm verschijnt.
@MainActor
@Observable
final class ActiveSession {
    var store: AppStore?
    var router: Router?
    var sync: SyncController?

    init() {}

    func register(store: AppStore, router: Router, sync: SyncController?) {
        self.store = store
        self.router = router
        self.sync = sync
    }

    /// Wist de registratie alleen als `store` nog de geregistreerde store is. Bij een accountwissel bestaan het oude en het
    /// nieuwe scherm kort naast elkaar; het oude scherm dat verdwijnt mag de registratie van het nieuwe niet wissen.
    func unregister(store: AppStore) {
        guard self.store === store else { return }
        self.store = nil
        self.router = nil
        self.sync = nil
    }
}

/// Registreert de sessie bij `ActiveSession` zolang het scherm zichtbaar is.
private struct SessionRegistration: ViewModifier {
    let session: ActiveSession
    let store: AppStore
    let router: Router
    let sync: SyncController?

    func body(content: Content) -> some View {
        content
            .onAppear { session.register(store: store, router: router, sync: sync) }
            .onDisappear { session.unregister(store: store) }
    }
}

extension View {
    /// Maakt `store`, `router` en `sync` bekend bij de `ActiveSession` (menubalk en `Settings`-venster).
    func registered(in session: ActiveSession, store: AppStore, router: Router, sync: SyncController?) -> some View {
        modifier(SessionRegistration(session: session, store: store, router: router, sync: sync))
    }
}
