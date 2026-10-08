import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MyBuddyCore

final class FirebaseAuthTests: XCTestCase {
    private let key = "TEST-KEY-123"
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func signInJSON(token: String = "id-1", refresh: String = "refresh-1", uid: String = "uid123",
                            email: String = "jan@mail.nl", expiresIn: String = "3600") -> String {
        #"{"kind":"identitytoolkit#VerifyPasswordResponse","localId":"\#(uid)","email":"\#(email)","idToken":"\#(token)","registered":true,"refreshToken":"\#(refresh)","expiresIn":"\#(expiresIn)"}"#
    }

    private func refreshJSON(token: String = "id-2", refresh: String = "refresh-1", uid: String = "uid123") -> String {
        #"{"access_token":"\#(token)","expires_in":"3600","token_type":"Bearer","refresh_token":"\#(refresh)","id_token":"\#(token)","user_id":"\#(uid)","project_id":"123"}"#
    }

    private func errorJSON(_ message: String, code: Int = 400) -> String {
        #"{"error":{"code":\#(code),"message":"\#(message)","errors":[{"message":"\#(message)","domain":"global","reason":"invalid"}]}}"#
    }

    private func makeClient(_ http: CloudMockHTTP, secrets: SecretStore = InMemorySecretStore(),
                            clock: CloudTestClock? = nil, apiKey: String? = nil) -> FirebaseAuthClient {
        let time = clock ?? CloudTestClock(start)
        return FirebaseAuthClient(apiKey: apiKey ?? key, http: http, secrets: secrets, bundleID: "nl.mybuddy.app",
                                  clock: { time.now })
    }

    // MARK: Adressen

    func testEndpointsUseTheOfficialHostsAndTheKey() {
        for action in ["signUp", "signInWithPassword", "sendOobCode", "lookup", "delete", "update"] {
            let url = FirebaseAuthClient.identityURL(action, apiKey: "A B&C")
            XCTAssertEqual(url?.host, "identitytoolkit.googleapis.com")
            XCTAssertEqual(url?.path, "/v1/accounts:\(action)")
            let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(items?.first(where: { $0.name == "key" })?.value, "A B&C")
        }
        let token = FirebaseAuthClient.tokenURL(apiKey: key)
        XCTAssertEqual(token?.host, "securetoken.googleapis.com")
        XCTAssertEqual(token?.path, "/v1/token")
    }

    // MARK: Inloggen en registreren

    func testSignInReturnsSessionAndStoresOnlyTheRefreshToken() async throws {
        let http = CloudMockHTTP { _ in (200, self.signInJSON()) }
        let secrets = InMemorySecretStore()
        let client = makeClient(http, secrets: secrets)

        let session = try await client.signIn(email: "  Jan@Mail.NL ", password: "geheim-wachtwoord")

        XCTAssertEqual(session.uid, "uid123")
        XCTAssertEqual(session.email, "jan@mail.nl")
        XCTAssertEqual(session.idToken, "id-1")
        XCTAssertEqual(session.refreshToken, "refresh-1")
        XCTAssertEqual(session.expiresAt, start.addingTimeInterval(3600))

        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.path(0), "/v1/accounts:signInWithPassword")
        XCTAssertEqual(http.requests[0].httpMethod, "POST")
        let body = http.bodyJSON(0)
        XCTAssertEqual(body["email"] as? String, "jan@mail.nl")
        XCTAssertEqual(body["password"] as? String, "geheim-wachtwoord")
        XCTAssertEqual(body["returnSecureToken"] as? Bool, true)
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "X-Ios-Bundle-Identifier"), "nl.mybuddy.app")

        // Op het apparaat blijft alleen de identiteit met het refresh-token staan, nooit het wachtwoord.
        let stored = try XCTUnwrap(secrets.read(FirebaseAuthClient.identityKey))
        XCTAssertFalse(stored.contains("geheim-wachtwoord"))
        XCTAssertFalse(stored.contains("id-1"))
        XCTAssertEqual(client.storedIdentity(), StoredIdentity(uid: "uid123", email: "jan@mail.nl", refreshToken: "refresh-1"))
    }

    func testSignUpUsesSignUpEndpointAndRejectsShortPasswordsWithoutNetwork() async throws {
        let http = CloudMockHTTP { _ in (200, self.signInJSON(email: "nieuw@mail.nl")) }
        let client = makeClient(http)

        do {
            _ = try await client.signUp(email: "nieuw@mail.nl", password: "12345")
            XCTFail("Een wachtwoord van 5 tekens hoort geweigerd te worden")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .weakPassword)
        }
        XCTAssertTrue(http.requests.isEmpty)

        let session = try await client.signUp(email: "nieuw@mail.nl", password: "123456")
        XCTAssertEqual(http.path(0), "/v1/accounts:signUp")
        XCTAssertEqual(session.email, "nieuw@mail.nl")
    }

    func testInvalidInputIsRejectedBeforeAnyRequest() async throws {
        let http = CloudMockHTTP { _ in (200, self.signInJSON()) }
        let client = makeClient(http)
        for address in ["", "geen-email", "a@b"] {
            do {
                _ = try await client.signIn(email: address, password: "x")
                XCTFail("\(address) hoort geweigerd te worden")
            } catch {
                XCTAssertEqual(error as? FirebaseAuthError, .invalidEmail, address)
            }
        }
        do {
            _ = try await client.signIn(email: "jan@mail.nl", password: "")
            XCTFail("Leeg wachtwoord hoort geweigerd te worden")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .missingPassword)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testMissingKeyMeansNotConfigured() async throws {
        let http = CloudMockHTTP { _ in (200, self.signInJSON()) }
        let client = makeClient(http, apiKey: "")
        do {
            _ = try await client.signIn(email: "jan@mail.nl", password: "geheim")
            XCTFail("Zonder sleutel hoort er niets te gebeuren")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .notConfigured)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testSignInSucceedsEvenWhenTheKeychainRefusesToStore() async throws {
        let http = CloudMockHTTP { _ in (200, self.signInJSON()) }
        let secrets = InMemorySecretStore()
        secrets.failWrites = true
        let client = makeClient(http, secrets: secrets)
        let session = try await client.signIn(email: "jan@mail.nl", password: "geheim")
        XCTAssertEqual(session.uid, "uid123")
        XCTAssertNil(client.storedIdentity())
    }

    func testIncompleteSignInReplyIsABadResponse() async throws {
        let http = CloudMockHTTP { _ in (200, #"{"localId":"uid123"}"#) }
        let client = makeClient(http)
        do {
            _ = try await client.signIn(email: "jan@mail.nl", password: "geheim")
            XCTFail("Een antwoord zonder tokens hoort een fout te zijn")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .badResponse)
        }
    }

    // MARK: Foutvertaling

    func testEveryKnownFirebaseCodeBecomesTheRightDutchError() async throws {
        let table: [(String, FirebaseAuthError)] = [
            ("EMAIL_EXISTS", .emailExists),
            ("INVALID_LOGIN_CREDENTIALS", .wrongCredentials),
            ("INVALID_PASSWORD", .wrongCredentials),
            ("EMAIL_NOT_FOUND", .emailNotFound),
            ("USER_DISABLED", .userDisabled),
            ("WEAK_PASSWORD : Password should be at least 6 characters", .weakPassword),
            ("PASSWORD_DOES_NOT_MEET_REQUIREMENTS : Missing password requirements: [Password must contain an upper case character]", .passwordPolicy),
            ("ADMIN_ONLY_OPERATION", .signUpDisabled),
            ("TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account has been temporarily disabled", .tooManyAttempts),
            ("INVALID_EMAIL", .invalidEmail),
            ("MISSING_PASSWORD", .missingPassword),
            ("OPERATION_NOT_ALLOWED", .operationNotAllowed),
            ("CONFIGURATION_NOT_FOUND", .configurationNotFound),
            ("TOKEN_EXPIRED", .sessionExpired),
            ("CREDENTIAL_TOO_OLD_LOGIN_AGAIN", .reauthenticationRequired),
            ("RESET_PASSWORD_EXCEED_LIMIT", .resetLimit)
        ]
        for (code, expected) in table {
            let http = CloudMockHTTP { _ in (400, self.errorJSON(code)) }
            let client = makeClient(http)
            do {
                _ = try await client.signIn(email: "jan@mail.nl", password: "geheim")
                XCTFail("\(code) hoort een fout te geven")
            } catch {
                XCTAssertEqual(error as? FirebaseAuthError, expected, code)
                XCTAssertFalse((error.localizedDescription).isEmpty, code)
            }
        }
    }

    func testApiKeyProblemsAreRecognised() {
        let invalid = #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID","domain":"googleapis.com"}]}}"#
        XCTAssertEqual(FirebaseAuthError.from(body: Data(invalid.utf8), status: 400), .invalidAPIKey)

        let blocked = #"{"error":{"code":403,"message":"Requests from this iOS client application <empty> are blocked.","status":"PERMISSION_DENIED","details":[{"reason":"API_KEY_IOS_APP_BLOCKED"}]}}"#
        XCTAssertEqual(FirebaseAuthError.from(body: Data(blocked.utf8), status: 403), .apiKeyRestricted)

        let disabled = #"{"error":{"code":403,"message":"Identity Toolkit API has not been used in project 123 before or it is disabled.","status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}"#
        XCTAssertEqual(FirebaseAuthError.from(body: Data(disabled.utf8), status: 403), .apiDisabled)

        XCTAssertEqual(FirebaseAuthError.from(body: Data("geen json".utf8), status: 502), .other("HTTP 502"))
        XCTAssertEqual(FirebaseAuthError.translate(code: "IETS_NIEUWS"), .other("IETS_NIEUWS"))
    }

    func testMessagesAreDutchAndHelpful() {
        let all: [FirebaseAuthError] = [
            .emailExists, .wrongCredentials, .emailNotFound, .userDisabled, .weakPassword, .passwordPolicy,
            .signUpDisabled, .tooManyAttempts, .invalidEmail, .missingPassword, .operationNotAllowed, .configurationNotFound, .invalidAPIKey,
            .apiKeyRestricted, .apiDisabled, .sessionExpired, .reauthenticationRequired, .resetLimit, .network,
            .notSignedIn, .notConfigured, .badResponse, .other("X")
        ]
        for error in all {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error)")
        }
        XCTAssertTrue(FirebaseAuthError.operationNotAllowed.errorDescription!.contains("E-mail/wachtwoord"))
        XCTAssertTrue(FirebaseAuthError.weakPassword.errorDescription!.contains("6 tekens"))
        XCTAssertTrue(FirebaseAuthError.notConfigured.errorDescription!.contains("FirebaseConfig.swift"))
        XCTAssertTrue(FirebaseAuthError.invalidAPIKey.errorDescription!.contains("FirebaseConfig.swift"))
        XCTAssertTrue(FirebaseAuthError.network.errorDescription!.contains("internet"))
    }

    func testNetworkFailureBecomesNetworkErrorAndCancellationPassesThrough() async throws {
        let offline = CloudMockHTTP { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient(offline).signIn(email: "jan@mail.nl", password: "geheim")
            XCTFail("Geen internet hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .network)
        }

        let cancelled = CloudMockHTTP { _ in throw URLError(.cancelled) }
        do {
            _ = try await makeClient(cancelled).signIn(email: "jan@mail.nl", password: "geheim")
            XCTFail("Een geannuleerd verzoek hoort een fout te geven")
        } catch {
            XCTAssertNil(error as? FirebaseAuthError, "Annuleren is geen netwerkfout")
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    // MARK: Wachtwoord vergeten

    func testPasswordResetSendsTheRightRequest() async throws {
        let http = CloudMockHTTP { _ in (200, #"{"email":"jan@mail.nl"}"#) }
        let client = makeClient(http)
        try await client.sendPasswordReset(email: " Jan@Mail.nl ")
        XCTAssertEqual(http.path(0), "/v1/accounts:sendOobCode")
        let body = http.bodyJSON(0)
        XCTAssertEqual(body["requestType"] as? String, "PASSWORD_RESET")
        XCTAssertEqual(body["email"] as? String, "jan@mail.nl")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "X-Firebase-Locale"), "nl")
    }

    func testPasswordResetErrorsAndValidation() async throws {
        let unknown = CloudMockHTTP { _ in (400, self.errorJSON("EMAIL_NOT_FOUND")) }
        do {
            try await makeClient(unknown).sendPasswordReset(email: "niemand@mail.nl")
            XCTFail("Onbekend adres hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .emailNotFound)
        }

        let http = CloudMockHTTP { _ in (200, "{}") }
        do {
            try await makeClient(http).sendPasswordReset(email: "geen-email")
            XCTFail("Ongeldig adres hoort geweigerd te worden")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .invalidEmail)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    // MARK: Sessie herstellen en verversen

    func testRestoreWithoutIdentityThrowsNotSignedIn() async throws {
        let http = CloudMockHTTP { _ in (200, self.refreshJSON()) }
        let client = makeClient(http)
        XCTAssertNil(client.storedIdentity())
        do {
            _ = try await client.restore()
            XCTFail("Zonder opgeslagen login valt er niets te herstellen")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .notSignedIn)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testRestoreRefreshesWithTheStoredRefreshToken() async throws {
        let secrets = InMemorySecretStore()
        let signInHTTP = CloudMockHTTP { _ in (200, self.signInJSON(refresh: "refresh/+=1")) }
        _ = try await makeClient(signInHTTP, secrets: secrets).signIn(email: "jan@mail.nl", password: "geheim")

        let clock = CloudTestClock(start.addingTimeInterval(7200))
        let http = CloudMockHTTP { _ in (200, self.refreshJSON(token: "id-new", refresh: "refresh-rotated")) }
        let client = makeClient(http, secrets: secrets, clock: clock)
        let session = try await client.restore()

        XCTAssertEqual(http.path(0), "/v1/token")
        XCTAssertEqual(http.requests[0].httpMethod, "POST")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        // Speciale tekens in het token worden netjes gecodeerd.
        XCTAssertEqual(http.bodyText(0), "grant_type=refresh_token&refresh_token=refresh%2F%2B%3D1")
        XCTAssertEqual(session.idToken, "id-new")
        XCTAssertEqual(session.uid, "uid123")
        XCTAssertEqual(session.email, "jan@mail.nl")
        XCTAssertEqual(session.expiresAt, clock.now.addingTimeInterval(3600))
        // Een nieuw refresh-token vervangt het oude.
        XCTAssertEqual(client.storedIdentity()?.refreshToken, "refresh-rotated")
    }

    func testRejectedRefreshTokenForgetsTheIdentityButNetworkErrorsDoNot() async throws {
        let secrets = InMemorySecretStore()
        let signInHTTP = CloudMockHTTP { _ in (200, self.signInJSON()) }
        _ = try await makeClient(signInHTTP, secrets: secrets).signIn(email: "jan@mail.nl", password: "geheim")

        // Geen internet: de login blijft staan, zodat de app later gewoon doorgaat.
        let offline = CloudMockHTTP { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient(offline, secrets: secrets).restore()
            XCTFail("Zonder internet kan er niet ververst worden")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .network)
        }
        XCTAssertNotNil(makeClient(offline, secrets: secrets).storedIdentity())

        // Het token wordt geweigerd: de login is niet meer geldig en wordt vergeten.
        let rejected = CloudMockHTTP { _ in (400, self.errorJSON("TOKEN_EXPIRED")) }
        do {
            _ = try await makeClient(rejected, secrets: secrets).restore()
            XCTFail("Een verlopen token hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .sessionExpired)
        }
        XCTAssertNil(makeClient(rejected, secrets: secrets).storedIdentity())

        // Ook een uitgeschakeld account is geen sessie meer.
        let signInAgain = CloudMockHTTP { _ in (200, self.signInJSON()) }
        _ = try await makeClient(signInAgain, secrets: secrets).signIn(email: "jan@mail.nl", password: "geheim")
        let disabled = CloudMockHTTP { _ in (400, self.errorJSON("USER_DISABLED")) }
        do {
            _ = try await makeClient(disabled, secrets: secrets).restore()
            XCTFail("Een uitgeschakeld account hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .userDisabled)
        }
        XCTAssertNil(makeClient(disabled, secrets: secrets).storedIdentity())
    }

    func testFreshSessionRefreshesFiveMinutesBeforeExpiry() async throws {
        let clock = CloudTestClock(start)
        let http = CloudMockHTTP { _ in (200, self.refreshJSON(token: "id-verversd")) }
        let client = makeClient(http, clock: clock)
        let session = FirebaseSession(uid: "uid123", email: "jan@mail.nl", idToken: "id-oud",
                                      refreshToken: "refresh-1", expiresAt: start.addingTimeInterval(3600))

        // Ruim voor het verlopen: niets doen.
        let untouched = try await client.freshSession(session)
        XCTAssertEqual(untouched.idToken, "id-oud")
        XCTAssertTrue(http.requests.isEmpty)

        // Net buiten de marge van 5 minuten (301 seconden te gaan): nog niet.
        clock.now = start.addingTimeInterval(3600 - 301)
        _ = try await client.freshSession(session)
        XCTAssertTrue(http.requests.isEmpty)

        // Binnen de marge (299 seconden te gaan): verversen.
        clock.now = start.addingTimeInterval(3600 - 299)
        let refreshed = try await client.freshSession(session)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(refreshed.idToken, "id-verversd")
        XCTAssertEqual(refreshed.expiresAt, clock.now.addingTimeInterval(3600))

        // Al verlopen: ook verversen.
        clock.now = start.addingTimeInterval(9999)
        _ = try await client.freshSession(session)
        XCTAssertEqual(http.requests.count, 2)
    }

    func testNeedsRefreshMargin() {
        let session = FirebaseSession(uid: "u", email: "e", idToken: "i", refreshToken: "r", expiresAt: start.addingTimeInterval(1000))
        XCTAssertFalse(session.needsRefresh(now: start.addingTimeInterval(600)))
        XCTAssertTrue(session.needsRefresh(now: start.addingTimeInterval(700)))
        XCTAssertTrue(session.needsRefresh(now: start.addingTimeInterval(1000)))
        XCTAssertTrue(session.needsRefresh(now: start.addingTimeInterval(1100)))
        XCTAssertFalse(session.needsRefresh(now: start.addingTimeInterval(990), margin: 5))
        XCTAssertEqual(FirebaseAuthClient.refreshMargin, 300)
    }

    func testSignOutForgetsTheIdentity() async throws {
        let secrets = InMemorySecretStore()
        let http = CloudMockHTTP { _ in (200, self.signInJSON()) }
        let client = makeClient(http, secrets: secrets)
        _ = try await client.signIn(email: "jan@mail.nl", password: "geheim")
        XCTAssertNotNil(client.storedIdentity())
        client.signOut()
        XCTAssertNil(client.storedIdentity())
        XCTAssertTrue(secrets.isEmpty)
    }

    func testCorruptStoredIdentityIsIgnored() {
        let secrets = InMemorySecretStore()
        try? secrets.write("dit is geen json", for: FirebaseAuthClient.identityKey)
        XCTAssertNil(makeClient(CloudMockHTTP { _ in (200, "{}") }, secrets: secrets).storedIdentity())
        try? secrets.write(#"{"uid":"","email":"a@b.nl","refreshToken":"x"}"#, for: FirebaseAuthClient.identityKey)
        XCTAssertNil(makeClient(CloudMockHTTP { _ in (200, "{}") }, secrets: secrets).storedIdentity())
    }

    // MARK: Opzoeken, wijzigen, verwijderen

    func testAccountInfoParsesLookup() async throws {
        let http = CloudMockHTTP { _ in
            (200, #"{"kind":"identitytoolkit#GetAccountInfoResponse","users":[{"localId":"uid123","email":"jan@mail.nl","emailVerified":true,"passwordHash":"x"}]}"#)
        }
        let info = try await makeClient(http).accountInfo(idToken: "id-1")
        XCTAssertEqual(info, FirebaseAccountInfo(uid: "uid123", email: "jan@mail.nl", emailVerified: true))
        XCTAssertEqual(http.path(0), "/v1/accounts:lookup")
        XCTAssertEqual(http.bodyJSON(0)["idToken"] as? String, "id-1")

        let empty = CloudMockHTTP { _ in (200, #"{"users":[]}"#) }
        do {
            _ = try await makeClient(empty).accountInfo(idToken: "id-1")
            XCTFail("Zonder gebruiker hoort er een fout te komen")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .sessionExpired)
        }
    }

    func testDeleteAccountPostsTheTokenAndForgetsTheLogin() async throws {
        let secrets = InMemorySecretStore()
        let http = CloudMockHTTP { request in
            request.url?.path == "/v1/accounts:delete" ? (200, #"{"kind":"identitytoolkit#DeleteAccountResponse"}"#) : (200, self.signInJSON())
        }
        let client = makeClient(http, secrets: secrets)
        let session = try await client.signIn(email: "jan@mail.nl", password: "geheim")
        try await client.deleteAccount(idToken: session.idToken)
        XCTAssertEqual(http.path(1), "/v1/accounts:delete")
        XCTAssertEqual(http.bodyJSON(1)["idToken"] as? String, "id-1")
        XCTAssertNil(client.storedIdentity())
    }

    func testChangePasswordChecksCurrentPasswordThenUpdates() async throws {
        let secrets = InMemorySecretStore()
        let http = CloudMockHTTP { request in
            switch request.url?.path {
            case "/v1/accounts:signInWithPassword": return (200, self.signInJSON())
            case "/v1/accounts:update": return (200, self.signInJSON(token: "id-nieuw", refresh: "refresh-nieuw"))
            default: return (400, self.errorJSON("ONBEKEND"))
            }
        }
        let client = makeClient(http, secrets: secrets)
        let session = try await client.changePassword(email: "jan@mail.nl", currentPassword: "oud-wachtwoord", newPassword: "nieuw-wachtwoord")

        XCTAssertEqual(http.path(0), "/v1/accounts:signInWithPassword")
        XCTAssertEqual(http.bodyJSON(0)["password"] as? String, "oud-wachtwoord")
        XCTAssertEqual(http.path(1), "/v1/accounts:update")
        XCTAssertEqual(http.bodyJSON(1)["idToken"] as? String, "id-1")
        XCTAssertEqual(http.bodyJSON(1)["password"] as? String, "nieuw-wachtwoord")
        XCTAssertEqual(session.idToken, "id-nieuw")
        XCTAssertEqual(client.storedIdentity()?.refreshToken, "refresh-nieuw")
        let stored = try XCTUnwrap(secrets.read(FirebaseAuthClient.identityKey))
        XCTAssertFalse(stored.contains("wachtwoord"))
    }

    func testChangePasswordWithWrongCurrentOrWeakNewPasswordDoesNotUpdate() async throws {
        let wrong = CloudMockHTTP { _ in (400, self.errorJSON("INVALID_LOGIN_CREDENTIALS")) }
        do {
            _ = try await makeClient(wrong).changePassword(email: "jan@mail.nl", currentPassword: "fout", newPassword: "nieuw-wachtwoord")
            XCTFail("Een fout huidig wachtwoord hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .wrongCredentials)
        }
        XCTAssertEqual(wrong.requests.count, 1)

        let weak = CloudMockHTTP { _ in (200, self.signInJSON()) }
        do {
            _ = try await makeClient(weak).changePassword(email: "jan@mail.nl", currentPassword: "oud", newPassword: "kort")
            XCTFail("Een zwak nieuw wachtwoord hoort geweigerd te worden")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .weakPassword)
        }
        XCTAssertTrue(weak.requests.isEmpty)
    }

    // MARK: Hulpjes

    func testFormEncodingKeepsOnlySafeCharacters() {
        XCTAssertEqual(FirebaseAuthClient.formEncode("abcXYZ019-._~"), "abcXYZ019-._~")
        XCTAssertEqual(FirebaseAuthClient.formEncode("a b&c=d/e+f"), "a%20b%26c%3Dd%2Fe%2Bf")
    }

    func testInMemorySecretStore() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(store.read("a"))
        try store.write("1", for: "a")
        try store.write("2", for: "b")
        XCTAssertEqual(store.read("a"), "1")
        store.remove("a")
        XCTAssertNil(store.read("a"))
        XCTAssertEqual(store.read("b"), "2")
        store.failWrites = true
        XCTAssertThrowsError(try store.write("3", for: "c"))
        XCTAssertNil(store.read("c"))
    }
}
