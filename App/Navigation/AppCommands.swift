import SwiftUI

/// De commando's in de menubalk (Mac en iPad met toetsenbord): de drie tabs in het menu Weergave met Cmd+1 (Home), Cmd+2
/// (Bibliotheek) en Cmd+3 (Zoeken), Zoeken met Cmd+F (selecteert de zoektab en opent het zoekveld), op iPad Instellingen met
/// Cmd+komma (op de Mac is dat het `Settings`-venster van het App-menu), en in het menu Gegevens Koersen vernieuwen (Cmd+R) en
/// Back-up maken. Alles is uitgeschakeld zolang er niemand is ingelogd.
@MainActor
struct AppCommands: Commands {
    let session: ActiveSession

    init(session: ActiveSession) {
        self.session = session
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            tabButton(.home, key: "1")
            tabButton(.library, key: "2")
            tabButton(.search, key: "3")
        }
        #if !os(macOS)
        // Op iPad met toetsenbord: Cmd+komma opent Instellingen (op de Mac doet het `Settings`-venster dat).
        CommandGroup(replacing: .appSettings) {
            Button("Instellingen…") {
                session.router?.open(.settingsRoot)
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(session.router == nil)
        }
        #endif
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
