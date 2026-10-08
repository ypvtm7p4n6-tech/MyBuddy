import SwiftUI

// Schermen rond het cloudaccount en het synchroniseren:
// - de secties "Account" en "Synchroniseren" in Instellingen (of, zonder sleutel, de uitleg om het aan te zetten)
// - de meldingen "Lokale gegevens uploaden?" en "Welke versie wil je houden?"
// - de bladen om het wachtwoord te wijzigen en het account te verwijderen

// MARK: - Teksten

enum SyncText {
    static func conflictMessage(_ conflict: SyncConflict) -> String {
        let local = conflict.localModified.map { Fmt.dateTime($0) } ?? "onbekend"
        let remote = conflict.remoteModified.map { Fmt.dateTime($0) } ?? "onbekend"
        let device = conflict.remoteDevice.isEmpty ? "" : " door \(conflict.remoteDevice)"
        var text = "Op dit apparaat (gewijzigd op \(local)) en in de cloud (gewijzigd op \(remote)\(device)) staan verschillende gegevens. Welke versie wil je houden? De andere versie bewaar ik eerst als back-up op dit apparaat."
        switch conflict.newerSide {
        case .some(.local): text += " De versie op dit apparaat is nieuwer."
        case .some(.remote): text += " De cloud-versie is nieuwer."
        case .none: break
        }
        return text
    }

    static func importMessage(_ offer: LocalDataCandidate) -> String {
        "Je hebt lokale gegevens op dit apparaat (laatst gewijzigd op \(Fmt.dateTime(offer.modified))). Uploaden naar je account? Staan er in je account al gegevens, dan kies je straks welke versie je houdt."
    }
}

// MARK: - Instellingen: account en synchroniseren

/// Alles voor het account en het synchroniseren in een `Form`. Levert Sections terug.
/// Met een Firebase-sleutel: het cloudaccount en de synchronisatie. Zonder sleutel: de lokale accounts
/// en een korte uitleg over het aanzetten van Firebase.
struct AccountAndSyncSections: View {
    var body: some View {
        if FirebaseConfig.isConfigured {
            CloudAccountSection()
            SyncSection()
        } else {
            AccountSection()
            FirebaseSetupSection()
        }
    }
}

/// Uitleg voor als er nog geen sleutel is ingevuld.
struct FirebaseSetupSection: View {
    var body: some View {
        if !isDemo {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Synchroniseren staat uit", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Text("Zet je Firebase Web API-sleutel in FirebaseConfig.swift om in te loggen en je gegevens op al je apparaten bij te houden.")
                        .font(.footnote)
                    VStack(alignment: .leading, spacing: 4) {
                        step("1", "Zet in de Firebase-console Authentication aan (E-mail/wachtwoord).")
                        step("2", "Plak bij Realtime Database > Regels de inhoud van firebase/database.rules.json.")
                        step("3", "Kopieer bij Project settings > Algemeen de Web API-sleutel en plak hem in App/Config/FirebaseConfig.swift.")
                        step("4", "Bouw de app opnieuw en start hem.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Synchroniseren")
            } footer: {
                Text("Stap voor stap staat het in firebase/README.md. Tot die tijd blijft alles op dit apparaat.")
            }
        }
    }

    private var isDemo: Bool {
        #if DEBUG
        return DebugLaunch.isDemo
        #else
        return false
        #endif
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(number + ".").monospacedDigit()
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Account

struct CloudAccountSection: View {
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.syncController) private var sync
    @State private var showChangePassword = false
    @State private var showDelete = false
    @State private var confirmSignOut = false

    var body: some View {
        if let cloud, let user = cloud.user {
            Section {
                HStack(spacing: 12) {
                    SymbolBadge(symbol: "person.fill", color: Theme.accent, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.email)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("Ingelogd")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .sheet(isPresented: $showChangePassword) { ChangeCloudPasswordSheet() }
                .sheet(isPresented: $showDelete) { DeleteCloudAccountSheet() }

                Button("Wachtwoord wijzigen") { showChangePassword = true }
                Button("Uitloggen") { confirmSignOut = true }
                    .confirmationDialog("Uitloggen?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Uitloggen") { cloud.signOut() }
                    } message: {
                        Text(signOutMessage)
                    }
                Button("Account verwijderen", role: .destructive) { showDelete = true }
            } header: {
                Text("Account")
            } footer: {
                if cloud.keepsLoginAfterQuit {
                    Text("Je blijft ingelogd. Het wachtwoord wordt niet op dit apparaat bewaard.")
                } else {
                    Text("Let op: dit apparaat kan je login niet veilig bewaren (Keychain). Je bent nu ingelogd, maar moet na het afsluiten van de app opnieuw inloggen.")
                }
            }
        }
    }

    private var signOutMessage: String {
        var text = "Je gegevens blijven op dit apparaat en in de cloud staan."
        if sync?.hasUnsyncedChanges == true {
            text += " Wijzigingen die nog niet zijn verstuurd, gaan mee zodra je weer inlogt."
        }
        return text
    }
}

// MARK: - Synchroniseren

struct SyncSection: View {
    @Environment(\.syncController) private var sync
    @State private var backups: [ConflictBackupItem] = []
    @State private var pendingBackup: ConflictBackupItem?
    @State private var backupResult: String?

    var body: some View {
        Section {
            if let sync {
                SyncStatusRow(sync: sync)
                    .onAppear { backups = sync.conflictBackups() }
                    .onChange(of: sync.displayStatus) { _, _ in backups = sync.conflictBackups() }

                if let conflict = sync.conflict {
                    Text(SyncText.conflictMessage(conflict))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Bewaar deze versie") { sync.startResolving(.keepLocal) }
                        .disabled(sync.isResolving)
                    Button("Neem cloud-versie over") { sync.startResolving(.takeRemote) }
                        .disabled(sync.isResolving)
                }

                Button {
                    Task { await sync.syncNow() }
                } label: {
                    HStack {
                        Text("Nu synchroniseren")
                        Spacer()
                        if sync.isBusy { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(sync.isBusy)

                if let last = sync.lastSyncedAt {
                    LabeledContent("Laatst gesynchroniseerd", value: Fmt.dateTime(last))
                }
                if let note = sync.sizeNote {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                if !backups.isEmpty {
                    DisclosureGroup("Back-ups van conflicten (\(backups.count))") {
                        ForEach(backups) { item in
                            HStack {
                                Text(item.title)
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Button("Terugzetten") { pendingBackup = item }
                                    .buttonStyle(.borderless)
                            }
                        }
                        if let backupResult {
                            Text(backupResult)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .confirmationDialog("Deze versie terugzetten?", isPresented: pendingBackupBinding,
                                        titleVisibility: .visible, presenting: pendingBackup) { item in
                        Button("Zet terug", role: .destructive) {
                            backupResult = sync.restoreBackup(item) ? "Teruggezet." : "Terugzetten is mislukt."
                            backups = sync.conflictBackups()
                        }
                    } message: { _ in
                        Text("Je huidige gegevens worden eerst zelf een back-up. De teruggezette versie gaat ook naar de cloud en je andere apparaten.")
                    }
                }
            } else {
                Label("Synchroniseren is in deze sessie niet actief.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Synchroniseren")
        } footer: {
            Text("Je gegevens gaan versleuteld (HTTPS) naar je eigen Firebase-database en worden op al je apparaten bijgewerkt. Ze zijn niet end-to-end versleuteld: wie toegang heeft tot je Firebase-project kan ze lezen. De app werkt altijd ook zonder internet.")
        }
    }
}

extension SyncSection {
    fileprivate var pendingBackupBinding: Binding<Bool> {
        Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })
    }
}

private struct SyncStatusRow: View {
    let sync: SyncController

    var body: some View {
        let status = sync.displayStatus
        HStack(spacing: 12) {
            SymbolBadge(symbol: symbol(status), color: tint(status), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(status)).font(.headline)
                Text(detail(status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isWorking(status) {
                ProgressView().controlSize(.small)
            }
        }
        .animation(Theme.motion, value: status)
        .accessibilityElement(children: .combine)
    }

    private func isWorking(_ status: SyncStatus) -> Bool {
        switch status {
        case .busy, .connecting: return true
        default: return false
        }
    }

    private func symbol(_ status: SyncStatus) -> String {
        switch status {
        case .disabled: return "pause.circle"
        case .connecting, .busy: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        case .offline: return "wifi.slash"
        case .failed: return "exclamationmark.triangle.fill"
        case .conflict: return "arrow.triangle.branch"
        }
    }

    private func tint(_ status: SyncStatus) -> Color {
        switch status {
        case .synced: return Theme.positive
        case .failed: return Theme.negative
        case .conflict, .offline: return Theme.warning
        default: return Theme.accent
        }
    }

    private func title(_ status: SyncStatus) -> String {
        switch status {
        case .disabled: return "Uit"
        case .connecting: return "Verbinden…"
        case .busy: return "Bezig…"
        case .synced: return "Gesynchroniseerd"
        case .offline: return "Offline"
        case .failed: return "Synchroniseren mislukt"
        case .conflict: return "Kies een versie"
        }
    }

    private func detail(_ status: SyncStatus) -> String {
        switch status {
        case .disabled: return "Er wordt niet gesynchroniseerd."
        case .connecting: return "Verbinding met de cloud maken."
        case .busy: return "Je gegevens worden bijgewerkt."
        case .synced(let date): return "Bijgewerkt om \(Fmt.dateTime(date))."
        case .offline: return "Je kunt gewoon doorwerken. Wijzigingen gaan mee zodra er weer internet is."
        case .failed(let text): return text
        case .conflict: return "Op dit apparaat en in de cloud staan verschillende gegevens."
        }
    }
}

// MARK: - Meldingen

/// Toont de meldingen van de synchronisatie bovenop de app. Eén melding tegelijk, want meerdere alerts op
/// dezelfde view overschrijven elkaar.
struct SyncPromptsHost<Content: View>: View {
    let sync: SyncController?
    let content: Content

    private enum Prompt {
        case importLocal
        case conflict
    }

    private var prompt: Prompt? {
        guard let sync else { return nil }
        if sync.importOffer != nil { return .importLocal }
        if sync.conflict != nil && !sync.conflictPromptDeferred && !sync.isResolving { return .conflict }
        return nil
    }

    private var title: String {
        switch prompt {
        case .some(.importLocal): return "Lokale gegevens uploaden?"
        case .some(.conflict): return "Welke versie wil je houden?"
        case .none: return ""
        }
    }

    private var message: String {
        switch prompt {
        case .some(.importLocal):
            if let offer = sync?.importOffer { return SyncText.importMessage(offer) }
            return ""
        case .some(.conflict):
            if let conflict = sync?.conflict { return SyncText.conflictMessage(conflict) }
            return ""
        case .none:
            return ""
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { _ in })
    }

    var body: some View {
        content.alert(title, isPresented: isPresented) {
            switch prompt {
            case .some(.importLocal):
                Button("Uploaden") { sync?.answerImportOffer(accept: true) }
                Button("Niet uploaden", role: .cancel) { sync?.answerImportOffer(accept: false) }
            case .some(.conflict):
                Button("Bewaar deze versie") { sync?.startResolving(.keepLocal) }
                Button("Neem cloud-versie over") { sync?.startResolving(.takeRemote) }
                Button("Later", role: .cancel) { sync?.deferConflictPrompt() }
            case .none:
                EmptyView()
            }
        } message: {
            Text(message)
        }
    }
}

extension View {
    /// Voegt de meldingen van de synchronisatie toe (lokale gegevens uploaden, conflict).
    func syncPrompts(_ sync: SyncController?) -> some View {
        SyncPromptsHost(sync: sync, content: self)
    }
}

// MARK: - Wachtwoord wijzigen

struct ChangeCloudPasswordSheet: View {
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var repeated = ""
    @State private var errorText: String?
    @State private var isSaving = false

    private var canSave: Bool {
        !current.isEmpty && newPassword.count >= FirebaseAuthClient.minimumPasswordLength && newPassword == repeated && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Huidig wachtwoord", text: $current)
                        .passwordFieldTraits(creating: false)
                }

                Section {
                    SecureField("Nieuw wachtwoord", text: $newPassword)
                        .passwordFieldTraits(creating: true)
                    SecureField("Herhaal nieuw wachtwoord", text: $repeated)
                        .passwordFieldTraits(creating: true)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        CloudPasswordHint(password: newPassword)
                        if !repeated.isEmpty && repeated != newPassword {
                            Text("De wachtwoorden zijn niet hetzelfde.")
                                .font(.footnote)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                    .padding(.top, 4)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.negative)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background { MeshBackground() }
            .navigationTitle("Wachtwoord wijzigen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Wijzig") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .onChange(of: current) { _, _ in errorText = nil }
            .onChange(of: newPassword) { _, _ in errorText = nil }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func save() {
        guard let cloud, canSave else { return }
        isSaving = true
        errorText = nil
        Task {
            do {
                try await cloud.changePassword(current: current, new: newPassword)
                current = ""
                newPassword = ""
                repeated = ""
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorText = error.localizedDescription
                if let authError = error as? FirebaseAuthError, authError == .wrongCredentials {
                    current = ""
                }
            }
        }
    }
}

/// De ene eis die Firebase aan een wachtwoord stelt, als vinkje.
struct CloudPasswordHint: View {
    let password: String

    private var isMet: Bool { password.count >= FirebaseAuthClient.minimumPasswordLength }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
            Text("Minstens \(FirebaseAuthClient.minimumPasswordLength) tekens")
        }
        .font(.footnote)
        .foregroundStyle(isMet ? Theme.positive : Color.secondary)
        .animation(Theme.quickMotion, value: isMet)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Account verwijderen

struct DeleteCloudAccountSheet: View {
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorText: String?
    @State private var confirming = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Je account en alle gegevens in de cloud worden verwijderd, en ook de gegevens op dit apparaat. Dit kan niet ongedaan worden gemaakt. Op je andere apparaten blijven de lokale gegevens staan tot je ze daar wist.")
                        .font(.footnote)
                        .foregroundStyle(Theme.negative)
                    SecureField("Wachtwoord", text: $password)
                        .passwordFieldTraits(creating: false)
                } header: {
                    Text("Bevestig met je wachtwoord")
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.negative)
                    }
                }

                Section {
                    Button("Verwijder account en gegevens", role: .destructive) { confirming = true }
                        .disabled(password.isEmpty || isDeleting)
                    if isDeleting {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Bezig met verwijderen…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background { MeshBackground() }
            .navigationTitle("Account verwijderen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .onChange(of: password) { _, _ in errorText = nil }
            .confirmationDialog("Weet je het zeker?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Verwijder definitief", role: .destructive) { performDelete() }
            } message: {
                Text("Je account en je gegevens worden overal gewist.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
    }

    private func performDelete() {
        guard let cloud, !isDeleting else { return }
        isDeleting = true
        errorText = nil
        Task {
            do {
                try await cloud.deleteAccount(password: password)
                password = ""
                isDeleting = false
                dismiss()
            } catch {
                isDeleting = false
                errorText = error.localizedDescription
                if let authError = error as? FirebaseAuthError, authError == .wrongCredentials {
                    password = ""
                }
            }
        }
    }
}
