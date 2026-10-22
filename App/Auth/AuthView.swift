import SwiftUI

// MARK: - Inlogscherm

/// Volledig scherm om in te loggen of een account te maken. Wordt getoond zolang er niemand is ingelogd.
/// Met een Firebase-sleutel (zie `FirebaseConfig`) logt het in via de cloud, met "Wachtwoord vergeten".
/// Zonder sleutel maakt het lokale accounts die alleen op dit apparaat bestaan.
/// Het scherm staat op het vlakke `Theme.canvas` met een `Card`; knoppen, tekstlinks en pictogramknoppen zijn minstens
/// `Theme.minTapTarget` groot. De wachtwoord-, verwijder- en wijzigpagina's staan bij Instellingen, Account.
struct AuthView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    private enum Mode: String, Identifiable {
        case signIn, create, reset
        var id: String { rawValue }
        var title: String {
            switch self {
            case .signIn: return "Inloggen"
            case .create: return "Account maken"
            case .reset: return "Wachtwoord vergeten"
            }
        }
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
    @State private var infoText: String?
    @State private var isWorking = false
    @FocusState private var focus: Field?
    /// De breedte van het pictogram voor een veld; schaalt mee met Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var fieldIconWidth: CGFloat = 20

    /// Inloggen via Firebase? Alleen als er een sleutel is ingevuld.
    private var isCloud: Bool {
        FirebaseConfig.isConfigured && cloud?.isEnabled == true
    }

    private var mode: Mode {
        if let chosenMode { return chosenMode }
        if isCloud { return (cloud?.isKnownDevice ?? false) ? .signIn : .create }
        return auth.accountCount == 0 ? .create : .signIn
    }

    /// De keuzebalk kent alleen inloggen en account maken; "wachtwoord vergeten" staat onder inloggen.
    private var modeBinding: Binding<Mode> {
        Binding(get: { mode == .reset ? .signIn : mode }, set: { chosenMode = $0 })
    }

    private var submitControlSize: ControlSize {
        #if os(macOS)
        return .regular
        #else
        return .large
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    header
                    card
                    footer
                }
                .scenePadding(.horizontal)
                .padding(.vertical, 24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
        .background { Theme.canvas.ignoresSafeArea() }
    }

    // MARK: Onderdelen

    private var header: some View {
        VStack(spacing: 10) {
            SymbolBadge(symbol: "leaf.fill", color: Theme.accent, size: 64)
            Text("MyBuddy")
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .animated(by: mode, quick: true)
    }

    private var subtitle: String {
        switch mode {
        case .signIn: return "Welkom terug. Log in om verder te gaan."
        case .create: return "Maak een account om te beginnen."
        case .reset: return "Vul je e-mailadres in. Dan sturen we je een e-mail om een nieuw wachtwoord te kiezen."
        }
    }

    private var card: some View {
        Card {
            cardHeader
            cardFields
            messageRows
            submitButton
            if mode == .reset {
                backToSignInLink
            }
        }
        .animated(by: mode, quick: true)
        .animated(by: errorText, quick: true)
        .animated(by: infoText, quick: true)
        .onChange(of: mode) { _, _ in
            errorText = nil
            infoText = nil
            confirm = ""
        }
        .onChange(of: email) { _, _ in
            errorText = nil
            infoText = nil
        }
        .onChange(of: password) { _, _ in errorText = nil }
        .onChange(of: confirm) { _, _ in errorText = nil }
    }

    /// Bovenaan de kaart: de keuzebalk (of de kop van "Wachtwoord vergeten") en een uitleg als je opnieuw moet inloggen.
    @ViewBuilder
    private var cardHeader: some View {
        if mode == .reset {
            resetHeader
        } else {
            Picker("Inloggen of account maken", selection: modeBinding) {
                ForEach([Mode.signIn, Mode.create]) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        if isCloud, mode == .signIn, let notice = cloud?.notice {
            noticeRow(notice)
        }
    }

    /// De velden van de kaart.
    @ViewBuilder
    private var cardFields: some View {
        emailField
        if showEmailHint {
            hintRow("Dit lijkt geen geldig e-mailadres.")
        }
        if mode != .reset {
            passwordField
        }
        if isCloud, mode == .signIn {
            forgotButton
        }
        if mode == .create {
            createFields
        }
    }

    /// Alleen bij "Account maken": de eisen aan het wachtwoord, herhalen en (lokaal) een naam.
    @ViewBuilder
    private var createFields: some View {
        if isCloud {
            CloudPasswordHint(password: password)
                .padding(.horizontal, 4)
        } else {
            PasswordRequirements(password: password)
        }
        confirmField
        if showMismatchHint {
            hintRow("De wachtwoorden zijn niet hetzelfde.")
        }
        if !isCloud {
            nameField
        }
    }

    /// Het resultaat van de laatste poging: een gelukt-bericht of een foutmelding.
    @ViewBuilder
    private var messageRows: some View {
        if let infoText {
            infoRow(infoText)
        }
        if let errorText {
            errorRow(errorText)
        }
    }

    private var resetHeader: some View {
        HStack(spacing: 8) {
            IconButton("Terug naar inloggen", symbol: "chevron.left") {
                leaveReset()
            }
            Text("Wachtwoord vergeten")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    private var backToSignInLink: some View {
        Button {
            leaveReset()
        } label: {
            Text("Terug naar inloggen")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var forgotButton: some View {
        Button {
            startReset()
        } label: {
            Text("Wachtwoord vergeten?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .accessibilityHidden(true)
                if isCloud {
                    Text("Je gegevens worden gesynchroniseerd met je account en blijven ook op dit apparaat staan, zodat de app zonder internet gewoon werkt.")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Je account en gegevens blijven op dit apparaat. Er is geen wachtwoordherstel.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if mode == .create {
                if isCloud {
                    Text("Gebruik een wachtwoord dat je nergens anders gebruikt. Vergeet je het, dan kun je een herstelmail laten sturen.")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Onthoud je wachtwoord goed. Zonder wachtwoord kom je niet meer bij je gegevens.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 8)
    }

    // MARK: Velden

    private func fieldRow<Content: View>(symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: fieldIconWidth)
                .accessibilityHidden(true)
            content()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.minTapTarget + 4)
        .tile()
    }

    private var emailField: some View {
        fieldRow(symbol: "envelope") {
            TextField("E-mailadres", text: $email)
                .textFieldStyle(.plain)
                .focused($focus, equals: .email)
                .submitLabel(mode == .reset ? .go : .next)
                .onSubmit {
                    if mode == .reset { submit() } else { focus = .password }
                }
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

            IconButton(showPassword ? "Verberg wachtwoord" : "Toon wachtwoord",
                       symbol: showPassword ? "eye.slash" : "eye") {
                toggleReveal()
            }
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
            .submitLabel(isCloud ? .go : .next)
            .onSubmit {
                if isCloud { submit() } else { focus = .name }
            }
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

    private var submitTitle: String {
        switch mode {
        case .signIn: return "Inloggen"
        case .create: return "Account maken"
        case .reset: return "Stuur herstelmail"
        }
    }

    /// De ene logische vervolgstap van het scherm: een gevulde knop met de accentvulling, met een rondje tijdens het werk.
    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.onAccent)
                }
                Text(submitTitle)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accentFill)
        .controlSize(submitControlSize)
        .disabled(!canSubmit || isWorking)
        .animated(by: isWorking, quick: true)
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

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func infoRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.positive)
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
            let strongEnough = isCloud
                ? password.count >= FirebaseAuthClient.minimumPasswordLength
                : AuthRules.isStrongPassword(password)
            return AuthRules.isValidEmail(trimmedEmail) && strongEnough && confirm == password
        case .reset:
            return AuthRules.isValidEmail(trimmedEmail)
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

    private func startReset() {
        errorText = nil
        infoText = nil
        password = ""
        chosenMode = .reset
        focus = .email
    }

    private func leaveReset() {
        errorText = nil
        infoText = nil
        chosenMode = .signIn
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        errorText = nil
        infoText = nil
        if isCloud {
            Task { await submitCloud() }
        } else {
            submitLocal()
        }
    }

    private func submitLocal() {
        do {
            switch mode {
            case .signIn, .reset:
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

    private func submitCloud() async {
        guard let cloud else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn:
                try await cloud.signIn(email: email, password: password)
            case .create:
                try await cloud.register(email: email, password: password)
            case .reset:
                try await cloud.sendPasswordReset(email: email)
                infoText = "Gelukt. Hoort \(trimmedEmail) bij een account, dan staat er zo een e-mail om een nieuw wachtwoord te kiezen. Kijk ook in je map met ongewenste e-mail."
                return
            }
            // Gelukt: dit scherm verdwijnt. Laat geen wachtwoord achter in het geheugen van het formulier.
            password = ""
            confirm = ""
        } catch {
            errorText = error.localizedDescription
            if let authError = error as? FirebaseAuthError {
                switch authError {
                case .wrongCredentials, .missingPassword, .weakPassword:
                    password = ""
                    confirm = ""
                    focus = .password
                case .invalidEmail, .emailExists, .emailNotFound:
                    focus = .email
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Eisen aan het wachtwoord

/// Vinkjes die laten zien wat een nieuw wachtwoord nog mist (lokaal account). Ook gebruikt op de pagina Wachtwoord wijzigen.
struct PasswordRequirements: View {
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
                .foregroundStyle(met ? Theme.positive : Theme.textSecondary)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - Invoerkenmerken per platform

extension View {
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
