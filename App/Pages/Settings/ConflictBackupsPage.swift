import SwiftUI

/// De pagina Back-ups van conflicten (`.settings(.conflictBackups)`), een subpagina van Account. Bij een conflict bewaart de
/// synchronisatie de versie die je niet koos als back-up op dit apparaat; hier zet je zo'n versie terug. "Zet terug" staat als
/// swipe-actie, in het contextmenu en als tekst in de rij, en vraagt een bevestiging aan de rij zelf.
struct ConflictBackupsPage: View {
    @Environment(\.syncController) private var sync
    @State private var backups: [ConflictBackupItem] = []
    @State private var pending: ConflictBackupItem?
    @State private var resultText: String?
    @State private var resultIsError = false
    @State private var successCount = 0
    @State private var failureCount = 0

    var body: some View {
        ListScaffold(title: "Back-ups van conflicten") {
            if let resultText {
                SettingsNotice(text: resultText,
                               symbol: resultIsError ? SettingsText.attentionSymbol : "checkmark.circle.fill")
            }
            backupsSection
        }
        .onAppear { reload() }
        .sensoryFeedback(.success, trigger: successCount)
        .sensoryFeedback(.error, trigger: failureCount)
    }

    private var backupsSection: some View {
        Section {
            if backups.isEmpty {
                EmptyHint(symbol: "clock.arrow.circlepath",
                          title: "Geen back-ups",
                          message: "Kies je bij een conflict één versie, dan bewaart MyBuddy de andere hier als back-up.")
            } else {
                ForEach(backups) { item in
                    row(item)
                }
            }
        } header: {
            SectionHeader("Back-ups")
        } footer: {
            if !backups.isEmpty {
                SettingsFootnote("Je huidige gegevens worden eerst zelf een back-up als je een versie terugzet.")
            }
        }
    }

    private func row(_ item: ConflictBackupItem) -> some View {
        Button {
            pending = item
        } label: {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Text("Zet terug")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .rowActions(extra: [
            RowAction("Zet terug", symbol: "arrow.uturn.backward", tint: Theme.accent) {
                pending = item
            }
        ])
        .confirmationDialog("Deze versie terugzetten?", isPresented: isPending(item),
                            titleVisibility: .visible, presenting: item) { selected in
            Button("Zet terug", role: .destructive) { restore(selected) }
            Button("Annuleer", role: .cancel) {}
        } message: { _ in
            Text("Je huidige gegevens worden eerst zelf een back-up. De teruggezette versie gaat ook naar de cloud en je andere apparaten.")
        }
    }

    private func isPending(_ item: ConflictBackupItem) -> Binding<Bool> {
        Binding(get: { pending?.id == item.id },
                set: { shown in
                    if !shown && pending?.id == item.id { pending = nil }
                })
    }

    private func reload() {
        backups = sync?.conflictBackups() ?? []
    }

    private func restore(_ item: ConflictBackupItem) {
        guard let sync else { return }
        if sync.restoreBackup(item) {
            resultText = "Teruggezet. De gegevens van deze versie zijn nu je gegevens."
            resultIsError = false
            successCount += 1
        } else {
            resultText = "Terugzetten is mislukt."
            resultIsError = true
            failureCount += 1
        }
        pending = nil
        reload()
    }
}
