import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Inloggen met e-mail en wachtwoord via de officiële REST-API's van Firebase, zonder Firebase-SDK:
// - Identity Toolkit (https://identitytoolkit.googleapis.com/v1/accounts:...) voor registreren, inloggen,
//   wachtwoord vergeten, wachtwoord wijzigen, opzoeken en verwijderen
// - Secure Token (https://securetoken.googleapis.com/v1/token) om een verlopen ID-token te verversen
// Alleen de Web API-sleutel is nodig. Het wachtwoord wordt nooit bewaard; alleen het refresh-token gaat
// (via `SecretStore`, in de app de Keychain) naar het apparaat.

// MARK: - Geheime opslag

/// Plek voor kleine geheimen (het refresh-token). In de app is dit de Keychain.
protocol SecretStore {
    func read(_ key: String) -> String?
    func write(_ value: String, for key: String) throws
    func remove(_ key: String)
}

struct SecretStoreError: Error, Equatable {
    var code: Int
}

/// Bewaart alles alleen in het geheugen: voor tests en als terugval als de Keychain niet beschikbaar is.
final class InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    /// Laat schrijven mislukken (voor tests van de terugvalroute).
    var failWrites = false

    init() {}

    func read(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func write(_ value: String, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if failWrites { throw SecretStoreError(code: -1) }
        values[key] = value
    }

    func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty
    }
}

// MARK: - Sessie

/// Een ingelogde sessie met een kortlevend ID-token (1 uur) en een langlevend refresh-token.
struct FirebaseSession: Equatable {
    var uid: String
    var email: String
    var idToken: String
    var refreshToken: String
    var expiresAt: Date

    /// Is het ID-token verlopen of binnen `margin` seconden (standaard 5 minuten) afgelopen?
    func needsRefresh(now: Date, margin: TimeInterval = FirebaseAuthClient.refreshMargin) -> Bool {
        now.addingTimeInterval(margin) >= expiresAt
    }
}

/// Wat er van een sessie op het apparaat blijft staan. Genoeg om offline door te gaan met de lokale gegevens.
struct StoredIdentity: Codable, Equatable {
    var uid: String
    var email: String
    var refreshToken: String
}

/// Gegevens uit `accounts:lookup`.
struct FirebaseAccountInfo: Equatable {
    var uid: String
    var email: String
    var emailVerified: Bool
}

// MARK: - Fouten

/// Fouten van de inlogdienst, met een duidelijke Nederlandse melding.
enum FirebaseAuthError: Error, Equatable, LocalizedError {
    case emailExists
    case wrongCredentials
    case emailNotFound
    case userDisabled
    case weakPassword
    case passwordPolicy
    case signUpDisabled
    case tooManyAttempts
    case invalidEmail
    case missingPassword
    case operationNotAllowed
    case configurationNotFound
    case invalidAPIKey
    case apiKeyRestricted
    case apiDisabled
    case sessionExpired
    case reauthenticationRequired
    case resetLimit
    case network
    case notSignedIn
    case notConfigured
    case badResponse
    case other(String)

    var errorDescription: String? {
        switch self {
        case .emailExists:
            return "Er bestaat al een account met dit e-mailadres. Log in, of kies 'Wachtwoord vergeten' als je het wachtwoord kwijt bent."
        case .wrongCredentials:
            return "Het e-mailadres of wachtwoord klopt niet."
        case .emailNotFound:
            return "Er is geen account met dit e-mailadres."
        case .userDisabled:
            return "Dit account is uitgeschakeld. Je kunt het weer aanzetten in de Firebase-console, onder Authentication > Users."
        case .weakPassword:
            return "Kies een wachtwoord van minimaal 6 tekens."
        case .passwordPolicy:
            return "Dit wachtwoord voldoet niet aan de wachtwoordeisen van je Firebase-project. Kies een langer wachtwoord met hoofdletters, kleine letters, cijfers en een speciaal teken."
        case .signUpDisabled:
            return "Nieuwe accounts maken staat uit in je Firebase-project. Zet het aan in de Firebase-console, onder Authentication > Settings."
        case .tooManyAttempts:
            return "Te veel pogingen. Wacht even en probeer het over een paar minuten opnieuw."
        case .invalidEmail:
            return "Dit is geen geldig e-mailadres."
        case .missingPassword:
            return "Vul je wachtwoord in."
        case .operationNotAllowed:
            return "Inloggen met e-mail en wachtwoord staat nog uit. Zet in de Firebase-console bij Authentication > Sign-in method 'E-mail/wachtwoord' aan."
        case .configurationNotFound:
            return "Authentication is nog niet ingeschakeld in je Firebase-project. Open Authentication in de Firebase-console en kies 'Aan de slag'."
        case .invalidAPIKey:
            return "De Firebase Web API-sleutel in FirebaseConfig.swift is ongeldig. Kopieer hem opnieuw uit Project settings > Algemeen."
        case .apiKeyRestricted:
            return "Deze API-sleutel is beperkt tot een andere app. Controleer in de Google Cloud Console of de beperking de bundle-ID nl.mybuddy.app toestaat."
        case .apiDisabled:
            return "De inlogdienst (Identity Toolkit API) staat uit voor dit project. Zet Authentication aan in de Firebase-console."
        case .sessionExpired:
            return "Je sessie is verlopen. Log opnieuw in."
        case .reauthenticationRequired:
            return "Log voor deze actie opnieuw in en probeer het dan nog eens."
        case .resetLimit:
            return "Er zijn te veel herstelmails aangevraagd. Probeer het later opnieuw."
        case .network:
            return "Geen verbinding met internet. Probeer het later opnieuw."
        case .notSignedIn:
            return "Je bent niet ingelogd."
        case .notConfigured:
            return "Er is nog geen Firebase Web API-sleutel ingesteld. Zet je sleutel in FirebaseConfig.swift."
        case .badResponse:
            return "Onverwacht antwoord van de inlogdienst. Probeer het later opnieuw."
        case .other(let code):
            return "Er ging iets mis bij de inlogdienst (\(code))."
        }
    }

    /// Vertaalt een foutcode van Firebase. `code` mag de volledige tekst zijn, zoals
    /// "WEAK_PASSWORD : Password should be at least 6 characters"; `reason` is de optionele
    /// detailreden van Google (bijvoorbeeld API_KEY_INVALID).
    static func translate(code: String, reason: String? = nil) -> FirebaseAuthError {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (trimmed.components(separatedBy: " : ").first ?? trimmed)
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        switch key {
        case "EMAIL_EXISTS":
            return .emailExists
        case "INVALID_LOGIN_CREDENTIALS", "INVALID_PASSWORD", "INVALID_CREDENTIAL":
            return .wrongCredentials
        case "EMAIL_NOT_FOUND":
            return .emailNotFound
        case "USER_DISABLED":
            return .userDisabled
        case "WEAK_PASSWORD":
            return .weakPassword
        case "PASSWORD_DOES_NOT_MEET_REQUIREMENTS":
            return .passwordPolicy
        case "ADMIN_ONLY_OPERATION":
            return .signUpDisabled
        case "TOO_MANY_ATTEMPTS_TRY_LATER":
            return .tooManyAttempts
        case "INVALID_EMAIL", "MISSING_EMAIL":
            return .invalidEmail
        case "MISSING_PASSWORD":
            return .missingPassword
        case "OPERATION_NOT_ALLOWED", "PASSWORD_LOGIN_DISABLED":
            return .operationNotAllowed
        case "CONFIGURATION_NOT_FOUND":
            return .configurationNotFound
        case "TOKEN_EXPIRED", "USER_NOT_FOUND", "INVALID_REFRESH_TOKEN", "INVALID_ID_TOKEN",
             "MISSING_REFRESH_TOKEN", "INVALID_GRANT_TYPE":
            return .sessionExpired
        case "CREDENTIAL_TOO_OLD_LOGIN_AGAIN", "REQUIRES_RECENT_LOGIN":
            return .reauthenticationRequired
        case "RESET_PASSWORD_EXCEED_LIMIT":
            return .resetLimit
        default:
            break
        }
        let lower = trimmed.lowercased()
        let reasonKey = (reason ?? "").uppercased()
        if reasonKey == "API_KEY_INVALID" || lower.contains("api key not valid") || lower.contains("api key expired") {
            return .invalidAPIKey
        }
        if reasonKey.hasSuffix("_BLOCKED") || lower.contains("are blocked") || lower.contains("referer") && lower.contains("blocked") {
            return .apiKeyRestricted
        }
        if reasonKey == "SERVICE_DISABLED" || lower.contains("has not been used") || lower.contains("api is not enabled") {
            return .apiDisabled
        }
        return .other(key.isEmpty ? "onbekend" : String(key.prefix(60)))
    }

    /// Leest het foutantwoord van Google: {"error":{"code":400,"message":"EMAIL_EXISTS", ...}}.
    static func from(body: Data, status: Int) -> FirebaseAuthError {
        struct Body: Decodable {
            struct Inner: Decodable {
                struct Detail: Decodable { var reason: String? }
                var message: String?
                var status: String?
                var details: [Detail]?
            }
            var error: Inner?
        }
        guard let parsed = try? JSONDecoder().decode(Body.self, from: body), let inner = parsed.error else {
            return .other("HTTP \(status)")
        }
        let reason = inner.details?.compactMap { $0.reason }.first
        let message = inner.message ?? inner.status ?? "HTTP \(status)"
        return translate(code: message, reason: reason)
    }
}

// MARK: - Client

struct FirebaseAuthClient {
    let apiKey: String
    let http: any HTTPClient
    let secrets: any SecretStore
    /// Wordt als X-Ios-Bundle-Identifier meegestuurd, zodat een sleutel die tot de app beperkt is blijft werken.
    let bundleID: String
    let clock: () -> Date

    static let identityKey = "firebase.identity"
    /// Een ID-token wordt ververst zodra het binnen 5 minuten verloopt.
    static let refreshMargin: TimeInterval = 300
    static let minimumPasswordLength = 6

    init(apiKey: String,
         http: any HTTPClient = URLSessionHTTPClient(),
         secrets: any SecretStore,
         bundleID: String = "nl.mybuddy.app",
         clock: @escaping () -> Date = { Date() }) {
        self.apiKey = apiKey
        self.http = http
        self.secrets = secrets
        self.bundleID = bundleID
        self.clock = clock
    }

    // MARK: Adressen

    static func identityURL(_ action: String, apiKey: String) -> URL? {
        var components = URLComponents(string: "https://identitytoolkit.googleapis.com/v1/accounts:\(action)")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return components?.url
    }

    static func tokenURL(apiKey: String) -> URL? {
        var components = URLComponents(string: "https://securetoken.googleapis.com/v1/token")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return components?.url
    }

    /// Spaties weg en kleine letters, zodat "Jan@Mail.nl " en "jan@mail.nl" hetzelfde account zijn.
    static func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Registreren en inloggen

    func signUp(email: String, password: String) async throws -> FirebaseSession {
        let address = try validatedEmail(email)
        guard password.count >= Self.minimumPasswordLength else { throw FirebaseAuthError.weakPassword }
        return try await authenticate(action: "signUp", email: address, password: password)
    }

    func signIn(email: String, password: String) async throws -> FirebaseSession {
        let address = try validatedEmail(email)
        guard !password.isEmpty else { throw FirebaseAuthError.missingPassword }
        return try await authenticate(action: "signInWithPassword", email: address, password: password)
    }

    /// Stuurt een e-mail om het wachtwoord opnieuw in te stellen (in het Nederlands).
    /// Firebase meldt vaak geen fout als het adres onbekend is; dat is bewust, zodat niemand adressen kan raden.
    func sendPasswordReset(email: String) async throws {
        let address = try validatedEmail(email)
        let url = try endpoint("sendOobCode")
        _ = try await send(jsonRequest(url, ["requestType": "PASSWORD_RESET", "email": address]))
    }

    /// Wijzigt het wachtwoord. Controleert eerst het huidige wachtwoord (opnieuw inloggen), want Firebase
    /// eist voor deze actie een recente login.
    func changePassword(email: String, currentPassword: String, newPassword: String) async throws -> FirebaseSession {
        guard newPassword.count >= Self.minimumPasswordLength else { throw FirebaseAuthError.weakPassword }
        let session = try await signIn(email: email, password: currentPassword)
        let url = try endpoint("update")
        let data = try await send(jsonRequest(url, [
            "idToken": session.idToken,
            "password": newPassword,
            "returnSecureToken": true
        ]))
        let reply = try decode(SignInReply.self, from: data)
        let updated = try makeSession(from: reply, fallbackEmail: session.email)
        save(updated)
        return updated
    }

    func accountInfo(idToken: String) async throws -> FirebaseAccountInfo {
        let url = try endpoint("lookup")
        let data = try await send(jsonRequest(url, ["idToken": idToken]))
        let reply = try decode(LookupReply.self, from: data)
        guard let user = reply.users?.first, let uid = user.localId else { throw FirebaseAuthError.sessionExpired }
        return FirebaseAccountInfo(uid: uid, email: user.email ?? "", emailVerified: user.emailVerified ?? false)
    }

    /// Verwijdert het account zelf. De gegevens in de database moeten eerst weg (zie `CloudAccountOperations`).
    func deleteAccount(idToken: String) async throws {
        let url = try endpoint("delete")
        _ = try await send(jsonRequest(url, ["idToken": idToken]))
        forgetIdentity()
    }

    // MARK: Sessie herstellen en verversen

    /// Wat er nog van een eerdere login op het apparaat staat. Kost geen netwerk, dus ook bruikbaar offline.
    func storedIdentity() -> StoredIdentity? {
        guard let text = secrets.read(Self.identityKey),
              let data = text.data(using: .utf8),
              let identity = try? JSONDecoder().decode(StoredIdentity.self, from: data),
              !identity.uid.isEmpty, !identity.refreshToken.isEmpty else { return nil }
        return identity
    }

    /// Haalt met het bewaarde refresh-token een nieuw ID-token op.
    func restore() async throws -> FirebaseSession {
        guard let identity = storedIdentity() else { throw FirebaseAuthError.notSignedIn }
        return try await refresh(uid: identity.uid, email: identity.email, refreshToken: identity.refreshToken)
    }

    func refresh(_ session: FirebaseSession) async throws -> FirebaseSession {
        try await refresh(uid: session.uid, email: session.email, refreshToken: session.refreshToken)
    }

    /// Geeft de sessie terug, of een ververste als het ID-token (bijna) verlopen is.
    func freshSession(_ session: FirebaseSession) async throws -> FirebaseSession {
        if session.needsRefresh(now: clock()) { return try await refresh(session) }
        return session
    }

    /// Vergeet de login op dit apparaat. Het wachtwoord werd nooit bewaard.
    func signOut() {
        forgetIdentity()
    }

    // MARK: Intern

    private func refresh(uid: String, email: String, refreshToken: String) async throws -> FirebaseSession {
        guard !apiKey.isEmpty else { throw FirebaseAuthError.notConfigured }
        guard let url = Self.tokenURL(apiKey: apiKey) else { throw FirebaseAuthError.badResponse }
        var request = baseRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=" + Self.formEncode(refreshToken)
        request.httpBody = Data(body.utf8)

        let data: Data
        do {
            data = try await send(request)
        } catch let error as FirebaseAuthError {
            // Een geweigerd refresh-token komt niet meer goed: vergeet de login.
            if error == .sessionExpired || error == .userDisabled { forgetIdentity() }
            throw error
        }
        let reply = try decode(RefreshReply.self, from: data)
        let seconds = reply.expiresInSeconds
        let session = FirebaseSession(uid: reply.userID.isEmpty ? uid : reply.userID,
                                      email: email,
                                      idToken: reply.idToken,
                                      refreshToken: reply.refreshToken.isEmpty ? refreshToken : reply.refreshToken,
                                      expiresAt: clock().addingTimeInterval(seconds))
        save(session)
        return session
    }

    private func authenticate(action: String, email: String, password: String) async throws -> FirebaseSession {
        let url = try endpoint(action)
        let data = try await send(jsonRequest(url, ["email": email, "password": password, "returnSecureToken": true]))
        let reply = try decode(SignInReply.self, from: data)
        let session = try makeSession(from: reply, fallbackEmail: email)
        save(session)
        return session
    }

    private func makeSession(from reply: SignInReply, fallbackEmail: String) throws -> FirebaseSession {
        guard let idToken = reply.idToken, let refreshToken = reply.refreshToken, let uid = reply.localId,
              !idToken.isEmpty, !refreshToken.isEmpty, !uid.isEmpty else { throw FirebaseAuthError.badResponse }
        let email = Self.normalizeEmail(reply.email ?? fallbackEmail)
        return FirebaseSession(uid: uid,
                               email: email,
                               idToken: idToken,
                               refreshToken: refreshToken,
                               expiresAt: clock().addingTimeInterval(reply.expiresInSeconds))
    }

    /// Bewaart alleen uid, e-mail en refresh-token. Lukt het bewaren niet (Keychain geweigerd), dan werkt de
    /// sessie nog gewoon tot de app sluit.
    private func save(_ session: FirebaseSession) {
        let identity = StoredIdentity(uid: session.uid, email: session.email, refreshToken: session.refreshToken)
        guard let data = try? JSONEncoder().encode(identity), let text = String(data: data, encoding: .utf8) else { return }
        try? secrets.write(text, for: Self.identityKey)
    }

    private func forgetIdentity() {
        secrets.remove(Self.identityKey)
    }

    private func validatedEmail(_ raw: String) throws -> String {
        let address = Self.normalizeEmail(raw)
        guard address.contains("@"), address.count >= 5 else { throw FirebaseAuthError.invalidEmail }
        return address
    }

    private func endpoint(_ action: String) throws -> URL {
        guard !apiKey.isEmpty else { throw FirebaseAuthError.notConfigured }
        guard let url = Self.identityURL(action, apiKey: apiKey) else { throw FirebaseAuthError.badResponse }
        return url
    }

    private func baseRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue("nl", forHTTPHeaderField: "X-Firebase-Locale")
        return request
    }

    private func jsonRequest(_ url: URL, _ body: [String: Any]) throws -> URLRequest {
        var request = baseRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { throw FirebaseAuthError.badResponse }
        request.httpBody = data
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let result: (Data, HTTPURLResponse)
        do {
            result = try await http.data(for: request)
        } catch {
            if QuoteHTTP.isCancellation(error) { throw error }
            throw FirebaseAuthError.network
        }
        guard (200..<300).contains(result.1.statusCode) else {
            throw FirebaseAuthError.from(body: result.0, status: result.1.statusCode)
        }
        return result.0
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FirebaseAuthError.badResponse
        }
    }

    /// application/x-www-form-urlencoded: alleen letters, cijfers en - . _ ~ blijven staan.
    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: Antwoorden

    /// Een getal dat als tekst ("3600") of als getal (3600) binnenkomt.
    private struct FlexibleSeconds: Decodable {
        var value: Double
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self), let number = Double(text) {
                value = number
            } else if let number = try? container.decode(Double.self) {
                value = number
            } else {
                value = 3600
            }
        }
    }

    private struct SignInReply: Decodable {
        var idToken: String?
        var refreshToken: String?
        var localId: String?
        var email: String?
        var expiresIn: FlexibleSeconds?
        var expiresInSeconds: TimeInterval { max(0, expiresIn?.value ?? 3600) }
    }

    private struct RefreshReply: Decodable {
        var idToken: String
        var refreshToken: String
        var userID: String
        var expiresIn: FlexibleSeconds?
        var expiresInSeconds: TimeInterval { max(0, expiresIn?.value ?? 3600) }

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case refreshToken = "refresh_token"
            case userID = "user_id"
            case expiresIn = "expires_in"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            idToken = try c.decode(String.self, forKey: .idToken)
            refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
            userID = try c.decodeIfPresent(String.self, forKey: .userID) ?? ""
            expiresIn = try c.decodeIfPresent(FlexibleSeconds.self, forKey: .expiresIn)
        }
    }

    private struct LookupReply: Decodable {
        struct User: Decodable {
            var localId: String?
            var email: String?
            var emailVerified: Bool?
        }
        var users: [User]?
    }
}
