import SwiftUI

/// De pagina Account verwijderen (`.settings(.deleteAccount)`), onderaan Account. Legt uit wat er gebeurt (ook in de cloud, en
/// dat het niet ongedaan kan), vraagt het wachtwoord en heeft een destructieve knop met een bevestiging aan de knop zelf.
struct DeleteAccountPage: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud
    @State private var password = ""
    @State private var errorText: String?
    @State private var confirming = false
    @State private var isDeleting = false

    private var isCloud: Bool {
        FirebaseConfig.isConfigured && cloud?.user != nil
    }

    var body: some View {
        ListScaffold(title: "Account verwijderen") {
            explanationSection
            confirmSection
        }
        .onChange(of: password) { _, _ in errorText = nil }
    }

    // MARK: Uitleg

    private var explanationSection: some View {
        Section {
            Label {
                Text(explanation)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.negative)
            }
        } header: {
            SectionHeader("Wat er gebeurt")
        }
    }

    private var explanation: String {
        if isCloud {
            return "Je account en alle gegevens in de cloud worden verwijderd, en ook de gegevens op dit apparaat. Dit kan niet ongedaan worden gemaakt. Op je andere apparaten blijven de lokale gegevens staan tot je ze daar wist."
        }
        return "Je account en alle gegevens die erbij horen worden van dit apparaat gewist. Dit kan niet ongedaan worden gemaakt en er is geen wachtwoordherstel of back-up bij ons."
    }

    private var confirmMessage: String {
        isCloud ? "Je account en je gegevens worden overal gewist." : "Je account en je gegevens worden van dit apparaat gewist."
    }

    // MARK: Bevestigen

    private var confirmSection: some View {
        Section {
            LabeledContent("Wachtwoord") {
                SecureField("Verplicht", text: $password)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.go)
                    .onSubmit { confirmIfPossible() }
                    .passwordFieldTraits(creating: false)
                    .accessibilityLabel("Wachtwoord")
            }
            .frame(minHeight: Theme.minTapTarget)
            if let errorText {
                SettingsErrorRow(text: errorText)
            }
            deleteButton
            if isDeleting {
                SettingsProgressRow(text: "Bezig met verwijderen…")
            }
        } header: {
            SectionHeader("Bevestig met je wachtwoord")
        }
    }

    /// De bevestiging hangt aan de knop zelf (op iPad en Mac komt de dialoog daar uit).
    private var deleteButton: some View {
        ActionButton(title: "Verwijder account en gegevens", symbol: "trash", role: .destructive) {
            confirming = true
        }
        .disabled(password.isEmpty || isDeleting)
        .listRowBackground(Color.clear)
        .confirmationDialog("Weet je het zeker?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Verwijder definitief", role: .destructive) { performDelete() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: Verwijderen

    private func confirmIfPossible() {
        if !password.isEmpty && !isDeleting {
            confirming = true
        }
    }

    private func performDelete() {
        guard !isDeleting else { return }
        errorText = nil
        if isCloud {
            deleteCloud()
        } else {
            deleteLocal()
        }
    }

    private func deleteLocal() {
        do {
            try auth.deleteCurrentAccount(password: password)
            password = ""
        } catch {
            errorText = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            if let authError = error as? AuthError, authError == .wrongCredentials {
                password = ""
            }
        }
    }

    private func deleteCloud() {
        guard let cloud else { return }
        isDeleting = true
        Task { @MainActor in
            do {
                try await cloud.deleteAccount(password: password)
                password = ""
                isDeleting = false
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
