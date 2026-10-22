import SwiftUI

/// De pagina Wachtwoord wijzigen (`.settings(.password)`), voor het cloudaccount en voor het lokale account. Een gewone pagina
/// op de stapel in plaats van een blad: invoer in `SecureField`, de volgorde van de velden met Return, de melding bij de knop.
struct PasswordPage: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var repeated = ""
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var savedCount = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case current, new, repeated
    }

    /// Met een cloudaccount gelden de eisen van de cloud; anders die van het lokale account.
    private var isCloud: Bool {
        FirebaseConfig.isConfigured && cloud?.user != nil
    }

    private var canSave: Bool {
        if isSaving || current.isEmpty || newPassword != repeated { return false }
        if isCloud {
            return newPassword.count >= FirebaseAuthClient.minimumPasswordLength
        }
        return AuthRules.isStrongPassword(newPassword)
    }

    var body: some View {
        ListScaffold(title: "Wachtwoord wijzigen") {
            currentSection
            newSection
            resultSection
        }
        .onChange(of: current) { _, _ in errorText = nil }
        .onChange(of: newPassword) { _, _ in errorText = nil }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    // MARK: Velden

    private var currentSection: some View {
        Section {
            LabeledContent("Huidig wachtwoord") {
                SecureField("Verplicht", text: $current)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: .current)
                    .submitLabel(.next)
                    .onSubmit { focus = .new }
                    .passwordFieldTraits(creating: false)
                    .accessibilityLabel("Huidig wachtwoord")
            }
            .frame(minHeight: Theme.minTapTarget)
        }
    }

    private var newSection: some View {
        Section {
            LabeledContent("Nieuw wachtwoord") {
                SecureField("Verplicht", text: $newPassword)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: .new)
                    .submitLabel(.next)
                    .onSubmit { focus = .repeated }
                    .passwordFieldTraits(creating: true)
                    .accessibilityLabel("Nieuw wachtwoord")
            }
            .frame(minHeight: Theme.minTapTarget)
            LabeledContent("Herhaal nieuw wachtwoord") {
                SecureField("Verplicht", text: $repeated)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: .repeated)
                    .submitLabel(.go)
                    .onSubmit { save() }
                    .passwordFieldTraits(creating: true)
                    .accessibilityLabel("Herhaal nieuw wachtwoord")
            }
            .frame(minHeight: Theme.minTapTarget)
        } footer: {
            hints
        }
    }

    /// Wat het nieuwe wachtwoord nog mist, en een melding als de twee velden verschillen.
    private var hints: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isCloud {
                CloudPasswordHint(password: newPassword)
            } else {
                PasswordRequirements(password: newPassword)
            }
            if !repeated.isEmpty && repeated != newPassword {
                Label("De wachtwoorden zijn niet hetzelfde.", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Knop en melding

    private var resultSection: some View {
        Section {
            if let errorText {
                SettingsErrorRow(text: errorText)
            }
            ActionButton(title: "Wijzig wachtwoord", prominent: true) {
                save()
            }
            .disabled(!canSave)
            .listRowBackground(Color.clear)
            if isSaving {
                SettingsProgressRow(text: "Bezig met wijzigen…")
            }
        }
    }

    // MARK: Bewaren

    private func save() {
        guard canSave else { return }
        errorText = nil
        if isCloud {
            saveCloud()
        } else {
            saveLocal()
        }
    }

    private func saveLocal() {
        do {
            try auth.changePassword(old: current, new: newPassword)
            finish()
        } catch {
            errorText = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            if let authError = error as? AuthError, authError == .wrongCredentials {
                current = ""
            }
        }
    }

    private func saveCloud() {
        guard let cloud else { return }
        isSaving = true
        Task { @MainActor in
            do {
                try await cloud.changePassword(current: current, new: newPassword)
                isSaving = false
                finish()
            } catch {
                isSaving = false
                errorText = error.localizedDescription
                if let authError = error as? FirebaseAuthError, authError == .wrongCredentials {
                    current = ""
                }
            }
        }
    }

    /// Wist de velden, geeft de bevestigende haptiek en gaat terug naar Account (in de eerstvolgende ronde, zodat de haptiek
    /// nog bij deze pagina hoort).
    private func finish() {
        current = ""
        newPassword = ""
        repeated = ""
        savedCount += 1
        DispatchQueue.main.async { dismiss() }
    }
}
