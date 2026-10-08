import XCTest
@testable import MyBuddy

/// Een nagebootste inlogdienst: de test bepaalt per adres wat er terugkomt.
private final class ScriptedAuthHTTP: HTTPClient {
    private(set) var paths: [String] = []
    var handler: (String) throws -> (Int, String)

    init(_ handler: @escaping (String) throws -> (Int, String)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        paths.append(path)
        let (status, body) = try handler(path)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@MainActor
final class CloudTests: XCTestCase {
    private let signInBody = #"{"localId":"uid123","email":"jan@mail.nl","idToken":"id-1","refreshToken":"refresh-1","expiresIn":"3600"}"#
    private let refreshBody = #"{"id_token":"id-2","refresh_token":"refresh-1","user_id":"uid123","expires_in":"3600"}"#

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyBuddyCloudTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeAccount(_ http: ScriptedAuthHTTP, secrets: SecretStore, directory: URL,
                             apiKey: String = "TEST-KEY") -> CloudAccount {
        CloudAccount(apiKey: apiKey,
                     databaseURL: "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app",
                     http: http,
                     secrets: secrets,
                     directory: directory)
    }

    // MARK: Instellingen

    func testConfigurationDefaults() {
        XCTAssertEqual(FirebaseConfig.databaseURL, "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app")
        XCTAssertEqual(FirebaseConfig.projectID, "my-buddy-finance")
        XCTAssertEqual(FirebaseConfig.bundleID, "nl.mybuddy.app")
        XCTAssertEqual(FirebaseConfig.isConfigured, !FirebaseConfig.apiKey.isEmpty)
        XCTAssertNotNil(FirebaseDatabaseClient(databaseURL: FirebaseConfig.databaseURL))
    }

    // MARK: Keychain

    func testKeychainStoresOverwritesAndRemovesSecrets() throws {
        #if canImport(Security)
        let store = KeychainSecretStore(service: "nl.mybuddy.tests.\(UUID().uuidString)")
        do {
            try store.write("geheim-1", for: "sleutel")
        } catch {
            throw XCTSkip("De Keychain is in deze testomgeving niet beschikbaar: \(error)")
        }
        addTeardownBlock { store.remove("sleutel") }
        XCTAssertEqual(store.read("sleutel"), "geheim-1")
        try store.write("geheim-2", for: "sleutel")
        XCTAssertEqual(store.read("sleutel"), "geheim-2")
        XCTAssertNil(store.read("andere"))
        store.remove("sleutel")
        XCTAssertNil(store.read("sleutel"))
        #else
        throw XCTSkip("Geen Keychain op dit platform")
        #endif
    }

    func testFallbackStoreKeepsSecretsInMemoryWhenThePrimaryRefuses() throws {
        struct RefusingStore: SecretStore {
            func read(_ key: String) -> String? { nil }
            func write(_ value: String, for key: String) throws { throw SecretStoreError(code: -34018) }
            func remove(_ key: String) {}
        }
        let store = FallbackSecretStore(primary: RefusingStore())
        XCTAssertFalse(store.usesMemoryOnly)
        try store.write("geheim", for: "sleutel")
        XCTAssertTrue(store.usesMemoryOnly)
        XCTAssertEqual(store.read("sleutel"), "geheim")
        store.remove("sleutel")
        XCTAssertNil(store.read("sleutel"))
        XCTAssertTrue(FallbackSecretStore(primary: nil).usesMemoryOnly)
    }

    // MARK: Cloudaccount

    func testAccountIsDisabledWithoutAKey() throws {
        let http = ScriptedAuthHTTP { _ in (200, "{}") }
        let account = makeAccount(http, secrets: InMemorySecretStore(), directory: try makeDirectory(), apiKey: "")
        XCTAssertFalse(account.isEnabled)
        XCTAssertNil(account.user)
        XCTAssertTrue(http.paths.isEmpty)
    }

    func testSignInSetsTheUserAndSurvivesARestartWithoutInternet() async throws {
        let directory = try makeDirectory()
        let secrets = InMemorySecretStore()
        let http = ScriptedAuthHTTP { _ in (200, self.signInBody) }
        let account = makeAccount(http, secrets: secrets, directory: directory)
        XCTAssertNil(account.user)

        try await account.signIn(email: "Jan@Mail.nl", password: "geheim12")
        XCTAssertEqual(account.user, CloudUser(uid: "uid123", email: "jan@mail.nl"))
        XCTAssertEqual(account.storageURL(for: try XCTUnwrap(account.user)).lastPathComponent, "finance-uid123.json")

        // Een geldig token wordt niet opnieuw opgehaald.
        let token = try await account.idToken()
        XCTAssertEqual(token, "id-1")
        XCTAssertEqual(http.paths.count, 1)

        // Na een herstart ben je meteen ingelogd, ook zonder internet.
        let offline = ScriptedAuthHTTP { _ in throw URLError(.notConnectedToInternet) }
        let restarted = makeAccount(offline, secrets: secrets, directory: directory)
        XCTAssertEqual(restarted.user, CloudUser(uid: "uid123", email: "jan@mail.nl"))
        do {
            _ = try await restarted.idToken()
            XCTFail("Zonder internet kan er geen token ververst worden")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .network)
        }
        XCTAssertNotNil(restarted.user, "Geen internet is geen reden om uit te loggen")
    }

    func testRestoredSessionRefreshesItsTokenOnDemand() async throws {
        let directory = try makeDirectory()
        let secrets = InMemorySecretStore()
        let first = ScriptedAuthHTTP { _ in (200, self.signInBody) }
        try await makeAccount(first, secrets: secrets, directory: directory).signIn(email: "jan@mail.nl", password: "geheim12")

        let http = ScriptedAuthHTTP { _ in (200, self.refreshBody) }
        let restarted = makeAccount(http, secrets: secrets, directory: directory)
        let token = try await restarted.idToken()
        XCTAssertEqual(token, "id-2")
        XCTAssertEqual(http.paths, ["/v1/token"])
        _ = try await restarted.idToken()
        XCTAssertEqual(http.paths.count, 1, "Het nieuwe token is nog geldig")
    }

    func testRejectedRefreshTokenSendsTheUserBackToSignIn() async throws {
        let directory = try makeDirectory()
        let secrets = InMemorySecretStore()
        let first = ScriptedAuthHTTP { _ in (200, self.signInBody) }
        try await makeAccount(first, secrets: secrets, directory: directory).signIn(email: "jan@mail.nl", password: "geheim12")

        let http = ScriptedAuthHTTP { _ in (400, #"{"error":{"code":400,"message":"TOKEN_EXPIRED"}}"#) }
        let restarted = makeAccount(http, secrets: secrets, directory: directory)
        XCTAssertNotNil(restarted.user)
        do {
            _ = try await restarted.idToken()
            XCTFail("Een verlopen sessie hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .sessionExpired)
        }
        XCTAssertNil(restarted.user)
        XCTAssertNotNil(restarted.notice)
        XCTAssertNil(makeAccount(http, secrets: secrets, directory: directory).user, "De login is vergeten")
    }

    func testSignOutForgetsTheLogin() async throws {
        let directory = try makeDirectory()
        let secrets = InMemorySecretStore()
        let http = ScriptedAuthHTTP { _ in (200, self.signInBody) }
        let account = makeAccount(http, secrets: secrets, directory: directory)
        try await account.signIn(email: "jan@mail.nl", password: "geheim12")
        account.signOut()
        XCTAssertNil(account.user)
        XCTAssertNil(makeAccount(http, secrets: secrets, directory: directory).user)
        do {
            _ = try await account.idToken()
            XCTFail("Uitgelogd hoort geen token te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .notSignedIn)
        }
    }

    func testSignInErrorsAreDutch() async throws {
        let http = ScriptedAuthHTTP { _ in (400, #"{"error":{"code":400,"message":"INVALID_LOGIN_CREDENTIALS"}}"#) }
        let account = makeAccount(http, secrets: InMemorySecretStore(), directory: try makeDirectory())
        do {
            try await account.signIn(email: "jan@mail.nl", password: "fout")
            XCTFail("Een fout wachtwoord hoort een fout te geven")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Het e-mailadres of wachtwoord klopt niet.")
        }
        XCTAssertNil(account.user)
        XCTAssertFalse(account.isWorking)
    }

    func testFileNamesStaySafe() {
        XCTAssertEqual(CloudAccount.safeFileName("xYz9AbC0"), "xYz9AbC0")
        XCTAssertEqual(CloudAccount.safeFileName("../etc/passwd"), "etcpasswd")
        XCTAssertEqual(CloudAccount.safeFileName("///"), "onbekend")
    }

    // MARK: Lokale gegevens meenemen

    func testLocalAccountFilesAreOfferedAndCloudFilesAreNot() {
        XCTAssertTrue(LocalDataFinder.isLocalDataFileName("finance.json"))
        XCTAssertTrue(LocalDataFinder.isLocalDataFileName("finance-\(UUID().uuidString).json"))
        XCTAssertFalse(LocalDataFinder.isLocalDataFileName("finance-uid123.json"))
    }

    // MARK: Synchronisatie-opstelling

    func testDeviceLabelIsStableAndContainsAShortID() {
        let suite = "nl.mybuddy.tests.device.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let first = SyncController.deviceLabel(defaults: defaults)
        let second = SyncController.deviceLabel(defaults: defaults)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix(")"))
        XCTAssertNotNil(first.range(of: #"\([0-9a-f]{4}\)$"#, options: .regularExpression))
    }

    func testMarkChangedForSyncGivesNewDataAFreshTimestampAndNotifies() {
        let store = AppStore(storage: nil, quotes: DemoQuoteService())
        var notified = 0
        store.onDataChanged = { _ in notified += 1 }
        XCTAssertNil(store.data.modifiedAt)
        store.markChangedForSync()
        XCTAssertNotNil(store.data.modifiedAt)
        XCTAssertEqual(notified, 1)
    }
}
