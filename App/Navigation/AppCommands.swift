import SwiftUI

/// De commando's in de menubalk (Mac en iPad met toetsenbord): de tabs in het menu Weergave met Cmd+1 t/m Cmd+5 (op de Mac
/// Cmd+1 t/m Cmd+4, want Instellingen is daar een eigen venster met Cmd+komma), Zoeken met Cmd+F, en in het menu Gegevens
/// Koersen vernieuwen (Cmd+R) en Back-up maken. Alles is uitgeschakeld zolang er niemand is ingelogd.
@MainActor
struct AppCommands: Commands {
    let session: ActiveSession

    init(session: ActiveSession) {
        self.session = session
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            tabButton(.overview, key: "1")
            tabButton(.month, key: "2")
            tabButton(.saving, key: "3")
            tabButton(.planning, key: "4")
            #if !os(macOS)
            tabButton(.settings, key: "5")
            #endif
        }
        CommandGroup(after: .textEditing) {
            Button("Zoeken") {
                session.router?.requestSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(session.router == nil)
        }
        CommandMenu("Gegevens") {
            Button("Koersen vernieuwen") {
                refreshPrices()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(session.store == nil)
            Button("Back-up maken…") {
                session.router?.go(.settings(.data))
            }
            .disabled(session.router == nil)
        }
    }

    private func tabButton(_ tab: AppTab, key: Character) -> some View {
        Button(tab.title) {
            session.router?.select(tab)
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        .disabled(session.router == nil)
    }

    private func refreshPrices() {
        guard let store = session.store else { return }
        Task { await store.refreshPrices(force: true) }
    }
}
