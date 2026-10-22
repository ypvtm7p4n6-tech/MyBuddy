import SwiftUI

/// De pagina Account (`.settings(.account)`): wie je bent, synchronisatie, wachtwoord, uitloggen en account verwijderen.
/// Staat los van Rekenen, Koersen en Gegevens (SET-4, ACT-5). Werkt voor het cloudaccount (met een Firebase-sleutel) en voor
/// het lokale account. Wachtwoord wijzigen, Account verwijderen en de back-ups van conflicten zijn eigen pagina's.
struct AccountPage: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.syncController) private var sync
    @State private var backups: [ConflictBackupItem] = []
    @State private var confirmSignOut = false
    @State private var syncSuccess = 0
    @State private var syncFailure = 0

    /// Het cloudaccount, alleen met een Firebase-sleutel.
    private var cloudUser: CloudUser? {
        FirebaseConfig.isConfigured ? cloud?.user : nil
    }

    private var localAccount: Account? {
        auth.currentAccount
    }

    /// Zonder account (alleen in een voorbeeldsessie) valt er niets te wijzigen of uit te loggen.
    private var hasAccount: Bool {
        cloudUser != nil || localAccount != nil
    }

    var body: some View {
        ListScaffold(title: "Account") {
            profileSection
            syncSection
            if hasAccount {
                securitySection
                signOutSection
                deleteSection
            }
        }
        .onAppear { reloadBackups() }
        .onChange(of: sync?.displayStatus) { _, _ in reloadBackups() }
        .sensoryFeedback(.success, trigger: syncSuccess)
        .sensoryFeedback(.error, trigger: syncFailure)
    }

    // MARK: Profiel

    private var profileSection: some View {
        Section {
            HStack(spacing: 12) {
                SymbolBadge(symbol: "person.crop.circle", color: AppDomain.settings.color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profileTitle)
                        .font(.headline)
                    Text(profileDetail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.minTapTarget)
            .accessibilityElement(children: .combine)
        } header: {
            SectionHeader("Profiel")
        } footer: {
            SettingsFootnote(profileNote)
        }
    }

    private var profileTitle: String {
        if let user = cloudUser { return user.email }
        if let account = localAccount { return account.displayName ?? account.email }
        return "Voorbeeldsessie"
    }

    private var profileDetail: String {
        if cloudUser != nil { return "Ingelogd" }
        if let account = localAccount {
            return account.displayName == nil ? "Ingelogd" : account.email
        }
        return "Niet ingelogd"
    }

    private var profileNote: String {
        if cloudUser != nil {
            if cloud?.keepsLoginAfterQuit == false {
                return "Dit apparaat kan je login niet veilig bewaren. Na het afsluiten van de app log je opnieuw in."
            }
            return "Je blijft ingelogd. Het wachtwoord staat niet op dit apparaat."
        }
        if localAccount != nil {
            return "Je account en gegevens blijven op dit apparaat. Er is geen wachtwoordherstel."
        }
        return "Dit is een voorbeeld met voorbeelddata."
    }

    // MARK: Synchronisatie

    private var syncSection: some View {
        Section {
            if FirebaseConfig.isConfigured {
                if let sync {
                    syncRows(sync)
                } else {
                    Label("Synchronisatie is in deze sessie niet actief.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Label("Alleen op dit apparaat. Er is geen synchronisatie tussen apparaten.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            SectionHeader("Synchronisatie")
        } footer: {
            if FirebaseConfig.isConfigured {
                SettingsFootnote("Je gegevens worden bijgewerkt op al je apparaten via je eigen Firebase-database. Zonder internet werk je gewoon door.")
            }
        }
    }

    @ViewBuilder
    private func syncRows(_ sync: SyncController) -> some View {
        SyncStatusRow(sync: sync)
        if let offer = sync.importOffer {
            importOfferBlock(sync, offer)
        }
        if let conflict = sync.conflict {
            conflictBlock(sync, conflict)
        }
        syncNowRow(sync)
        if let last = sync.lastSyncedAt {
            LabeledContent("Laatst gesynchroniseerd", value: Fmt.dateTime(last))
        }
        if let note = sync.sizeNote {
            Label(note, systemImage: SettingsText.attentionSymbol)
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        if !backups.isEmpty {
            SettingsLinkRow(page: .conflictBackups, title: "Back-ups van conflicten (\(backups.count))")
        }
    }

    /// Het aanbod om lokale gegevens naar het account te uploaden: de keuze zelf staat hier (geen melding bij het starten).
    private func importOfferBlock(_ sync: SyncController, _ offer: LocalDataCandidate) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Label("Lokale gegevens uploaden?", systemImage: "icloud.and.arrow.up")
                .font(.headline)
                .foregroundStyle(Theme.warning)
            Text(SyncText.importMessage(offer))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            ActionGroup {
                ActionButton(title: "Uploaden", prominent: true) {
                    sync.answerImportOffer(accept: true)
                }
                ActionButton(title: "Niet uploaden") {
                    sync.answerImportOffer(accept: false)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Bij een conflict: welke versie blijft. Prominent bovenaan de sectie zolang het conflict er is.
    private func conflictBlock(_ sync: SyncController, _ conflict: SyncConflict) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Label("Kies welke versie je houdt", systemImage: SettingsText.attentionSymbol)
                .font(.headline)
                .foregroundStyle(Theme.warning)
            Text(SyncText.conflictMessage(conflict))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            ActionGroup {
                ActionButton(title: "Bewaar deze versie") {
                    sync.startResolving(.keepLocal)
                }
                .disabled(sync.isResolving)
                ActionButton(title: "Neem cloud-versie over") {
                    sync.startResolving(.takeRemote)
                }
                .disabled(sync.isResolving)
            }
        }
        .padding(.vertical, 4)
    }

    private func syncNowRow(_ sync: SyncController) -> some View {
        Button {
            runSync(sync)
        } label: {
            HStack {
                Label("Nu synchroniseren", systemImage: "arrow.triangle.2.circlepath")
                Spacer(minLength: 8)
                if sync.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .disabled(sync.isBusy)
    }

    private func runSync(_ sync: SyncController) {
        Task { @MainActor in
            await sync.syncNow()
            reloadBackups()
            switch sync.displayStatus {
            case .synced:
                syncSuccess += 1
            case .failed, .offline:
                syncFailure += 1
            default:
                break
            }
        }
    }

    private func reloadBackups() {
        backups = sync?.conflictBackups() ?? []
    }

    // MARK: Beveiliging, uitloggen en verwijderen

    private var securitySection: some View {
        Section {
            SettingsLinkRow(page: .password)
        } header: {
            SectionHeader("Beveiliging")
        }
    }

    private var signOutSection: some View {
        Section {
            Button {
                confirmSignOut = true
            } label: {
                Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .confirmationDialog("Uitloggen?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Uitloggen") { signOut() }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text(signOutMessage)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            SettingsLinkRow(page: .deleteAccount, isDestructive: true)
        }
    }

    private func signOut() {
        if cloudUser != nil {
            cloud?.signOut()
        } else {
            auth.signOut()
        }
    }

    private var signOutMessage: String {
        if cloudUser != nil {
            var text = "Je gegevens blijven op dit apparaat en in de cloud staan."
            if sync?.hasUnsyncedChanges == true {
                text += " Wijzigingen die nog niet zijn verstuurd, gaan mee zodra je weer inlogt."
            }
            return text
        }
        return "Je gegevens blijven op dit apparaat staan. Log je weer in met hetzelfde e-mailadres, dan zijn ze er weer."
    }
}
