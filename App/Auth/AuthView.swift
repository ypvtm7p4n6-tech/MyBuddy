import SwiftUI

// MARK: - Inlogscherm

/// Volledig scherm om in te loggen of een account te maken. Wordt getoond zolang er niemand is ingelogd.
struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn, create
        var id: String { rawValue }
        var title: String { self == .signIn ? "Inloggen" : "Account maken" }
    }

    private enum Field: Hashable {
        case email, password, confirm, name
    }

    /// Wat de gebruiker zelf koos. Zonder keuze: nieuw account als er nog geen account is, anders inloggen.
    @State private var chosenMode: Mode?
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var name = ""
    @State private var showPassword = false
    @State private var errorText: String?
    @FocusState private var focus: Field?

    private var mode: Mode {
        chosenMode ?? (auth.accountCount == 0 ? .create : .signIn)
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: { mode }, set: { chosenMode = $0 })
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    header
                    card
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
        .background { MeshBackground() }
    }

    // MARK: Onderdelen

    private var header: some View {
        VStack(spacing: 10) {
            SymbolBadge(symbol: "leaf.fill", color: Theme.accent, size: 64)
            Text("MyBuddy")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(mode == .signIn ? "Welkom terug. Log in om verder te gaan." : "Maak een account om te beginnen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Inloggen of account maken", selection: modeBinding) {
                ForEach(Mode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            emailField
            if showEmailHint {
                hintRow("Dit lijkt geen geldig e-mailadres.")
            }

            passwordField

            if mode == .create {
                PasswordRequirements(password: password)
                confirmField
                if showMismatchHint {
                    hintRow("De wachtwoorden zijn niet hetzelfde.")
                }
                nameField
            }

            if let errorText {
                errorRow(errorText)
            }

            submitButton
        }
        .padding(Theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(.snappy(duration: 0.25), value: mode)
        .onChange(of: mode) { _, _ in
            errorText = nil
            confirm = ""
        }
        .onChange(of: email) { _, _ in errorText = nil }
        .onChange(of: password) { _, _ in errorText = nil }
        .onChange(of: confirm) { _, _ in errorText = nil }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                Text("Je account en gegevens blijven op dit apparaat. Er is geen wachtwoordherstel.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mode == .create {
                Text("Onthoud je wachtwoord goed. Zonder wachtwoord kom je niet meer bij je gegevens.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 8)
    }

    // MARK: Velden

    private func fieldRow<Content: View>(symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.buttonHeight + 4)
        .tile()
    }

    private var emailField: some View {
        fieldRow(symbol: "envelope") {
            TextField("E-mailadres", text: $email)
                .textFieldStyle(.plain)
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
                .emailFieldTraits(signIn: mode == .signIn)
        }
    }

    private var passwordField: some View {
        fieldRow(symbol: "lock") {
            Group {
                if showPassword {
                    TextField("Wachtwoord", text: $password)
                } else {
                    SecureField("Wachtwoord", text: $password)
                }
            }
            .textFieldStyle(.plain)
            .focused($focus, equals: .password)
            .submitLabel(mode == .create ? .next : .go)
            .onSubmit {
                if mode == .create { focus = .confirm } else { submit() }
            }
            .passwordFieldTraits(creating: mode == .create)

            Button { toggleReveal() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPassword ? "Verberg wachtwoord" : "Toon wachtwoord")
        }
    }

    private var confirmField: some View {
        fieldRow(symbol: "lock.rotation") {
            Group {
                if showPassword {
                    TextField("Herhaal wachtwoord", text: $confirm)
                } else {
                    SecureField("Herhaal wachtwoord", text: $confirm)
                }
            }
            .textFieldStyle(.plain)
            .focused($focus, equals: .confirm)
            .submitLabel(.next)
            .onSubmit { focus = .name }
            .passwordFieldTraits(creating: true)
        }
    }

    private var nameField: some View {
        fieldRow(symbol: "person") {
            TextField("Naam (niet verplicht)", text: $name)
                .textFieldStyle(.plain)
                .focused($focus, equals: .name)
                .submitLabel(.go)
                .onSubmit { submit() }
                .nameFieldTraits()
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(mode == .signIn ? "Inloggen" : "Account maken")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
        }
        .glassButton(prominent: true)
        .tint(Theme.olive)
        .disabled(!canSubmit)
    }

    private func hintRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "xmark.octagon.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.negative)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Controle en actie

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pas tonen als je het veld verlaat, zodat het niet knippert terwijl je nog typt.
    private var showEmailHint: Bool {
        !trimmedEmail.isEmpty && focus != .email && !AuthRules.isValidEmail(trimmedEmail)
    }

    private var showMismatchHint: Bool {
        !confirm.isEmpty && confirm != password
    }

    private var canSubmit: Bool {
        switch mode {
        case .signIn:
            return !trimmedEmail.isEmpty && !password.isEmpty
        case .create:
            return AuthRules.isValidEmail(trimmedEmail) && AuthRules.isStrongPassword(password) && confirm == password
        }
    }

    private func toggleReveal() {
        let wasFocused = (focus == .password)
        showPassword.toggle()
        if wasFocused {
            // Bij het wisselen tussen veldsoorten raakt het veld de focus kwijt. Zet die terug.
            Task { @MainActor in focus = .password }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        errorText = nil
        do {
            switch mode {
            case .signIn:
                _ = try auth.signIn(email: email, password: password)
            case .create:
                _ = try auth.register(email: email, password: password, displayName: name)
            }
            // Gelukt: dit scherm verdwijnt. Laat geen wachtwoord achter in het geheugen van het formulier.
            password = ""
            confirm = ""
        } catch {
            if let authError = error as? AuthError {
                errorText = authError.errorDescription
                switch authError {
                case .wrongCredentials, .tooManyAttempts:
                    password = ""
                    focus = .password
                case .invalidEmail, .emailInUse:
                    focus = .email
                case .weakPassword:
                    focus = .password
                case .notSignedIn, .storage:
                    break
                }
            } else {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Eisen aan het wachtwoord

/// Vinkjes die laten zien wat een nieuw wachtwoord nog mist.
private struct PasswordRequirements: View {
    let password: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AuthRules.PasswordRule.allCases, id: \.self) { rule in
                let met = rule.isMet(by: password)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: met ? "checkmark.circle.fill" : "circle")
                    Text(rule.title)
                }
                .font(.footnote)
                .foregroundStyle(met ? Theme.positive : Color.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - Invoerkenmerken per platform

private extension View {
    /// E-mailadres: e-mailtoetsenbord, geen hoofdletters, geen autocorrectie.
    @ViewBuilder
    func emailFieldTraits(signIn: Bool) -> some View {
        #if os(iOS)
        if signIn {
            self.keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            self.keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        #else
        self.autocorrectionDisabled()
        #endif
    }

    /// Wachtwoord: geen hoofdletters of autocorrectie, en de juiste aanwijzing voor wachtwoordhulp van het systeem.
    @ViewBuilder
    func passwordFieldTraits(creating: Bool) -> some View {
        #if os(iOS)
        if creating {
            self.textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            self.textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        #else
        self.autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    func nameFieldTraits() -> some View {
        #if os(iOS)
        self.textContentType(.name)
            .textInputAutocapitalization(.words)
        #else
        self
        #endif
    }
}

// MARK: - Account in de instellingen

/// Rijen voor in een `Form` op het instellingenscherm: wie je bent, uitloggen, wachtwoord wijzigen, account verwijderen.
struct AccountSection: View {
    @Environment(AuthStore.self) private var auth
    @State private var showChangePassword = false
    @State private var showDelete = false

    var body: some View {
        if let account = auth.currentAccount {
            Section {
                HStack(spacing: 12) {
                    SymbolBadge(symbol: "person.fill", color: Theme.accent, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        if let displayName = account.displayName {
                            Text(displayName).font(.headline).lineLimit(1)
                        }
                        Text(account.email)
                            .font(account.displayName == nil ? .headline : .footnote)
                            .foregroundStyle(account.displayName == nil ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
                .sheet(isPresented: $showDelete) { DeleteAccountSheet() }

                Button("Wachtwoord wijzigen") { showChangePassword = true }
                Button("Uitloggen") { auth.signOut() }
                Button("Account verwijderen", role: .destructive) { showDelete = true }
            } header: {
                Text("Account")
            } footer: {
                Text("Je account en gegevens blijven op dit apparaat. Er is geen wachtwoordherstel.")
            }
        }
    }
}

// MARK: - Wachtwoord wijzigen

private struct ChangePasswordSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var errorText: String?

    private var canSave: Bool {
        !oldPassword.isEmpty && AuthRules.isStrongPassword(newPassword) && newPassword == repeatPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Huidig wachtwoord", text: $oldPassword)
                        .passwordFieldTraits(creating: false)
                }

                Section {
                    SecureField("Nieuw wachtwoord", text: $newPassword)
                        .passwordFieldTraits(creating: true)
                    SecureField("Herhaal nieuw wachtwoord", text: $repeatPassword)
                        .passwordFieldTraits(creating: true)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        PasswordRequirements(password: newPassword)
                        if !repeatPassword.isEmpty && repeatPassword != newPassword {
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
                    Button("Wijzig") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: oldPassword) { _, _ in errorText = nil }
            .onChange(of: newPassword) { _, _ in errorText = nil }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func save() {
        do {
            try auth.changePassword(old: oldPassword, new: newPassword)
            oldPassword = ""
            newPassword = ""
            repeatPassword = ""
            dismiss()
        } catch {
            errorText = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            if let authError = error as? AuthError, authError == .wrongCredentials {
                oldPassword = ""
            }
        }
    }
}

// MARK: - Account verwijderen

private struct DeleteAccountSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorText: String?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Je account en alle gegevens die erbij horen worden van dit apparaat gewist. Dit kan niet ongedaan worden gemaakt en er is geen wachtwoordherstel of back-up bij ons.")
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
                        .disabled(password.isEmpty)
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
                }
            }
            .onChange(of: password) { _, _ in errorText = nil }
            .confirmationDialog("Weet je het zeker?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Verwijder definitief", role: .destructive) { performDelete() }
            } message: {
                Text("Je account en je gegevens worden van dit apparaat gewist.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
    }

    private func performDelete() {
        do {
            try auth.deleteCurrentAccount(password: password)
            password = ""
            dismiss()
        } catch {
            errorText = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            if let authError = error as? AuthError, authError == .wrongCredentials {
                password = ""
            }
        }
    }
}
