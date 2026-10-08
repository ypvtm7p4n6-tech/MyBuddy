import SwiftUI
import Observation

// De cloudvariant van `AuthStore`: inloggen met e-mail en wachtwoord via Firebase (REST, zonder SDK).
// Het refresh-token staat in de Keychain; het wachtwoord wordt nooit bewaard.
// De app werkt offline-first: een eerder ingelogde gebruiker is meteen "ingelogd" zonder internet.
// Pas als de cloud om een nieuw token vraagt, is er verbinding nodig.

/// Wie er bij de cloud is ingelogd.
struct CloudUser: Equatable, Identifiable {
    var uid: String
    var email: String
    var id: String { uid }
}

@MainActor
@Observable
final class CloudAccount {
    /// Wie er is ingelogd. `nil` betekent: toon het inlogscherm.
    private(set) var user: CloudUser?
    /// Er loopt een inlog-, registratie- of verwijderactie.
    private(set) var isWorking = false
    /// Uitleg als je opnieuw moet inloggen (bijvoorbeeld "Je sessie is verlopen").
    private(set) var notice: String?
    /// Blijft de login bewaard na het afsluiten van de app? Alleen `false` als de Keychain niet beschikbaar is.
    private(set) var keepsLoginAfterQuit = true

    @ObservationIgnored private let client: FirebaseAuthClient?
    @ObservationIgnored let database: FirebaseDatabaseClient?
    @ObservationIgnored private let fallbackStore: FallbackSecretStore?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var session: FirebaseSession?
    @ObservationIgnored private var refreshTask: Task<FirebaseSession, Error>?
    /// Tijdens het verwijderen van het account geeft `idToken` geen tokens meer uit, zodat de synchronisatie
    /// niet tussendoor nog gegevens terugzet.
    @ObservationIgnored private var isRemoving = false

    static let knownDeviceKey = "mybuddy.cloud.knownDevice"

    /// - Parameters:
    ///   - apiKey: de Web API-sleutel. Leeg betekent dat Firebase uit staat; dan doet deze klasse niets.
    ///   - databaseURL: het adres van de Realtime Database.
    ///   - http: het netwerk (tests geven hier een nagebootste versie).
    ///   - secrets: waar het refresh-token wordt bewaard.
    ///   - directory: map met de gegevensbestanden. Standaard dezelfde map als `FinanceStorage.standard()`.
    init(apiKey: String = FirebaseConfig.apiKey,
         databaseURL: String = FirebaseConfig.databaseURL,
         http: any HTTPClient = URLSessionHTTPClient(),
         secrets: (any SecretStore)? = nil,
         directory: URL? = nil) {
        let resolved = directory ?? FinanceStorage.standard().url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        self.directory = resolved

        if apiKey.isEmpty {
            client = nil
            database = nil
            fallbackStore = nil
        } else {
            let store: any SecretStore
            if let secrets {
                store = secrets
                fallbackStore = nil
            } else {
                let fallback = FallbackSecretStore.standard()
                store = fallback
                fallbackStore = fallback
            }
            let auth = FirebaseAuthClient(apiKey: apiKey, http: http, secrets: store, bundleID: FirebaseConfig.bundleID)
            client = auth
            database = FirebaseDatabaseClient(databaseURL: databaseURL, http: http)
            if let identity = auth.storedIdentity() {
                user = CloudUser(uid: identity.uid, email: identity.email)
            }
        }
    }

    var isEnabled: Bool { client != nil }

    /// Is dit apparaat al eens ingelogd geweest? Dan opent het inlogscherm op "Inloggen" in plaats van "Account maken".
    var isKnownDevice: Bool {
        UserDefaults.standard.bool(forKey: Self.knownDeviceKey)
    }

    // MARK: Bestanden

    /// Het gegevensbestand van deze gebruiker op dit apparaat: finance-<uid>.json.
    func storageURL(for user: CloudUser) -> URL {
        directory.appendingPathComponent("finance-\(Self.safeFileName(user.uid)).json")
    }

    /// Een Firebase-uid bestaat uit letters en cijfers; toch laten we nooit een vreemd teken in een bestandsnaam toe.
    static func safeFileName(_ uid: String) -> String {
        var text = ""
        for scalar in uid.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
            text.unicodeScalars.append(scalar)
        }
        return text.isEmpty ? "onbekend" : text
    }

    // MARK: Inloggen en registreren

    func signIn(email: String, password: String) async throws {
        let auth = try requireClient()
        isWorking = true
        defer { isWorking = false }
        let fresh = try await auth.signIn(email: email, password: password)
        adopt(fresh)
    }

    func register(email: String, password: String) async throws {
        let auth = try requireClient()
        isWorking = true
        defer { isWorking = false }
        let fresh = try await auth.signUp(email: email, password: password)
        adopt(fresh)
    }

    func sendPasswordReset(email: String) async throws {
        let auth = try requireClient()
        isWorking = true
        defer { isWorking = false }
        try await auth.sendPasswordReset(email: email)
    }

    /// Wijzigt het wachtwoord. Vraagt het huidige wachtwoord ter controle.
    func changePassword(current: String, new: String) async throws {
        let auth = try requireClient()
        guard let user else { throw FirebaseAuthError.notSignedIn }
        isWorking = true
        defer { isWorking = false }
        let fresh = try await auth.changePassword(email: user.email, currentPassword: current, newPassword: new)
        session = fresh
    }

    /// Logt uit. De gegevens op dit apparaat en in de cloud blijven bestaan.
    func signOut() {
        client?.signOut()
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        user = nil
    }

    /// Verwijdert het account: eerst de gegevens in de cloud, dan het account, dan de bestanden op dit apparaat.
    func deleteAccount(password: String) async throws {
        guard let auth = client, let database else { throw FirebaseAuthError.notConfigured }
        guard let current = user else { throw FirebaseAuthError.notSignedIn }
        isWorking = true
        isRemoving = true
        defer {
            isWorking = false
            isRemoving = false
        }
        try await CloudAccountOperations.deleteAccount(email: current.email, password: password, auth: auth, database: database)
        removeLocalFiles(for: current)
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        user = nil
    }

    /// De cloud weigert onze login definitief (verlopen, account weg of uitgeschakeld). Terug naar het inlogscherm.
    func sessionExpired(_ error: Error? = nil) {
        notice = (error as? LocalizedError)?.errorDescription ?? FirebaseAuthError.sessionExpired.errorDescription
        client?.signOut()
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        user = nil
    }

    func clearNotice() {
        notice = nil
    }

    // MARK: Token

    /// Een geldig ID-token. Verloopt het binnen 5 minuten, dan wordt het eerst ververst.
    /// Gooit `.network` als er geen verbinding is: de gegevens op het apparaat blijven dan gewoon bruikbaar.
    func idToken(forceRefresh: Bool = false) async throws -> String {
        guard let auth = client, user != nil else { throw FirebaseAuthError.notSignedIn }
        // Geen tokens meer tijdens het verwijderen; dit geldt als onderbreking, niet als uitloggen.
        if isRemoving { throw CancellationError() }
        if let session, !forceRefresh, !session.needsRefresh(now: Date()) { return session.idToken }
        if let running = refreshTask { return try await running.value.idToken }

        let current = session
        let task = Task { () throws -> FirebaseSession in
            if let current { return try await auth.refresh(current) }
            return try await auth.restore()
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            session = fresh
            return fresh.idToken
        } catch {
            if let authError = error as? FirebaseAuthError, authError == .sessionExpired || authError == .userDisabled {
                sessionExpired(authError)
            }
            throw error
        }
    }

    // MARK: Intern

    private func requireClient() throws -> FirebaseAuthClient {
        guard let client else { throw FirebaseAuthError.notConfigured }
        return client
    }

    private func adopt(_ fresh: FirebaseSession) {
        session = fresh
        notice = nil
        user = CloudUser(uid: fresh.uid, email: fresh.email)
        keepsLoginAfterQuit = !(fallbackStore?.usesMemoryOnly ?? false)
        UserDefaults.standard.set(true, forKey: Self.knownDeviceKey)
    }

    /// Wist de gegevens, de synchronisatiestaat en de back-ups van deze gebruiker van dit apparaat.
    private func removeLocalFiles(for user: CloudUser) {
        let name = Self.safeFileName(user.uid)
        try? FileManager.default.removeItem(at: storageURL(for: user))
        FileSyncStateStore.standard(directory: directory, uid: name).clear()
        ConflictBackupStore(directory: directory, uid: name).removeAll()
        UserDefaults.standard.removeObject(forKey: SyncController.importFlagKey(uid: user.uid))
    }
}

// MARK: - Omgeving

private struct CloudAccountKey: EnvironmentKey {
    static let defaultValue: CloudAccount? = nil
}

private struct SyncControllerKey: EnvironmentKey {
    static let defaultValue: SyncController? = nil
}

extension EnvironmentValues {
    /// Het cloudaccount. `nil` in voorbeeldsessies zonder account.
    var cloudAccount: CloudAccount? {
        get { self[CloudAccountKey.self] }
        set { self[CloudAccountKey.self] = newValue }
    }

    /// De synchronisatie van het ingelogde account. `nil` zolang er niet gesynchroniseerd wordt.
    var syncController: SyncController? {
        get { self[SyncControllerKey.self] }
        set { self[SyncControllerKey.self] = newValue }
    }
}
