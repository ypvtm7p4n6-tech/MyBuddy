import Foundation
import Observation

// MARK: - Account

/// Het deel van een account dat de rest van de app mag zien. Nooit een wachtwoord of hash.
struct Account: Identifiable, Codable, Equatable {
    var id: UUID
    var email: String
    var displayName: String?
    var createdAt: Date
}

// MARK: - Fouten

enum AuthError: LocalizedError, Equatable {
    case invalidEmail
    case weakPassword
    case emailInUse
    case wrongCredentials
    case tooManyAttempts(seconds: Int)
    case notSignedIn
    case storage

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Dit is geen geldig e-mailadres."
        case .weakPassword:
            return "Kies een wachtwoord van minstens 8 tekens, met minstens één letter en één cijfer."
        case .emailInUse:
            return "Er bestaat op dit apparaat al een account met dit e-mailadres."
        case .wrongCredentials:
            return "Het e-mailadres of wachtwoord klopt niet."
        case .tooManyAttempts(let seconds):
            return "Te veel pogingen. Probeer het over \(seconds) seconden opnieuw."
        case .notSignedIn:
            return "Je bent niet ingelogd."
        case .storage:
            return "Opslaan is mislukt. Controleer of er ruimte is op je apparaat."
        }
    }
}

// MARK: - Regels voor e-mailadres en wachtwoord

/// Eén plek voor wat een geldig e-mailadres en wachtwoord is. Het formulier en de opslag gebruiken dezelfde regels.
enum AuthRules {
    static let minimumPasswordLength = 8
    static let maximumDisplayNameLength = 60

    /// Spaties weg en kleine letters, zodat "Jan@Mail.nl " en "jan@mail.nl" hetzelfde account zijn.
    static func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Eenvoudige controle: één @, een lokaal deel, en een domein met minstens één punt.
    /// Het is bewust geen volledige RFC-controle; of het adres echt bestaat is voor een lokaal account niet van belang.
    static func isValidEmail(_ raw: String) -> Bool {
        let email = normalizeEmail(raw)
        guard email.count >= 5, email.count <= 254 else { return false }
        let forbidden: Set<Character> = ["\"", ",", ";", "<", ">", "(", ")", "[", "]", "\\", ":"]
        for character in email {
            if character.isWhitespace || forbidden.contains(character) { return false }
        }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, local.count <= 64 else { return false }
        guard !local.hasPrefix("."), !local.hasSuffix("."), !local.contains("..") else { return false }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false).map { String($0) }
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            for character in label {
                if !(character.isLetter || character.isNumber || character == "-") { return false }
            }
        }
        guard let tld = labels.last, tld.count >= 2 else { return false }
        return tld.allSatisfy { $0.isLetter }
    }

    /// Eén eis aan het wachtwoord, zodat het formulier kan laten zien wat er nog mist.
    enum PasswordRule: CaseIterable {
        case length, letter, digit

        var title: String {
            switch self {
            case .length: return "Minstens \(AuthRules.minimumPasswordLength) tekens"
            case .letter: return "Minstens één letter"
            case .digit: return "Minstens één cijfer"
            }
        }

        func isMet(by password: String) -> Bool {
            switch self {
            case .length: return password.count >= AuthRules.minimumPasswordLength
            case .letter: return password.contains(where: { $0.isLetter })
            case .digit: return password.contains(where: { $0.isNumber })
            }
        }
    }

    static func isStrongPassword(_ password: String) -> Bool {
        PasswordRule.allCases.allSatisfy { $0.isMet(by: password) }
    }

    /// Naam zonder spaties aan de rand. Leeg wordt `nil`.
    static func cleanDisplayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return String(trimmed.prefix(maximumDisplayNameLength))
    }
}

// MARK: - Bewaarde gegevens

/// Eén regel in accounts.json: het account plus alles wat nodig is om het wachtwoord te controleren.
struct StoredAccount: Codable, Equatable {
    var id: UUID
    var email: String
    var displayName: String?
    var createdAt: Date
    var salt: Data
    var passwordHash: Data
    var iterations: Int

    var account: Account {
        Account(id: id, email: email, displayName: displayName, createdAt: createdAt)
    }
}

struct AccountsFile: Codable, Equatable {
    var version: Int
    var accounts: [StoredAccount]
}

// MARK: - AuthStore

/// Lokale accounts: alles blijft op dit apparaat. Er is geen server, dus ook geen wachtwoordherstel.
/// De app praat alleen met deze klasse, zodat er later een online variant voor in de plaats kan komen.
@MainActor
@Observable
final class AuthStore {
    /// Wie er nu is ingelogd. `nil` betekent: toon het inlogscherm.
    private(set) var currentAccount: Account?

    /// Alle accounts op dit apparaat, met de hash van het wachtwoord.
    private var records: [StoredAccount]

    static let sessionKey = "mybuddy.session.accountID"
    static let maxFailedAttempts = 5
    static let lockoutSeconds: TimeInterval = 30
    static let accountsFileName = "accounts.json"
    static let legacyFileName = "finance.json"

    private let directory: URL
    private let defaults: UserDefaults
    private let iterations: Int
    private let clock: () -> Date

    private struct Failure {
        var count = 0
        var lockedUntil: Date?
    }

    /// Mislukte pogingen per e-mailadres. Alleen in het geheugen: opnieuw opstarten wist de teller.
    @ObservationIgnored private var failures: [String: Failure] = [:]

    /// Zout voor het geval het e-mailadres niet bestaat. Zo duurt een poging even lang en verraadt de tijd niets.
    private static let decoySalt = Data(repeating: 0x5A, count: PasswordHasher.saltLength)

    /// - Parameters:
    ///   - directory: map met accounts.json en de gegevensbestanden. Standaard dezelfde map als `FinanceStorage.standard()`.
    ///   - defaults: hier onthoudt de app wie er was ingelogd.
    ///   - iterations: aantal PBKDF2-rondes voor nieuwe wachtwoorden. Alleen tests verlagen dit.
    ///   - clock: de tijd, zodat tests de blokkade van 30 seconden kunnen doorspoelen.
    init(directory: URL? = nil,
         defaults: UserDefaults = .standard,
         iterations: Int = PasswordHasher.defaultIterations,
         clock: @escaping () -> Date = { Date() }) {
        let resolved = directory ?? FinanceStorage.standard().url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        let loaded = AuthStore.loadRecords(at: resolved.appendingPathComponent(AuthStore.accountsFileName))

        self.directory = resolved
        self.defaults = defaults
        self.iterations = iterations
        self.clock = clock
        self.records = loaded

        // Sessie terugzetten, maar alleen als dat account nog bestaat.
        if let raw = defaults.string(forKey: AuthStore.sessionKey) {
            if let id = UUID(uuidString: raw), let stored = loaded.first(where: { $0.id == id }) {
                self.currentAccount = stored.account
            } else {
                defaults.removeObject(forKey: AuthStore.sessionKey)
            }
        }
    }

    // MARK: Lezen

    var accountCount: Int { records.count }

    /// Het bestand met de gegevens van dit account (de bestaande opslag leest en schrijft hier).
    func storageURL(for account: Account) -> URL {
        directory.appendingPathComponent("finance-\(account.id.uuidString).json")
    }

    private var accountsURL: URL {
        directory.appendingPathComponent(AuthStore.accountsFileName)
    }

    private var legacyURL: URL {
        directory.appendingPathComponent(AuthStore.legacyFileName)
    }

    // MARK: Account maken

    /// Maakt een account en logt direct in. Het eerste account neemt de gegevens over die de app vóór accounts bewaarde.
    @discardableResult
    func register(email: String, password: String, displayName: String?) throws -> Account {
        let normalized = AuthRules.normalizeEmail(email)
        guard AuthRules.isValidEmail(normalized) else { throw AuthError.invalidEmail }
        guard AuthRules.isStrongPassword(password) else { throw AuthError.weakPassword }
        guard !records.contains(where: { $0.email == normalized }) else { throw AuthError.emailInUse }

        let salt = PasswordHasher.randomSalt()
        let digest = PasswordHasher.hash(password: password, salt: salt, iterations: iterations)
        guard !digest.isEmpty else { throw AuthError.storage }

        let created = Date(timeIntervalSince1970: clock().timeIntervalSince1970.rounded(.down))
        let record = StoredAccount(id: UUID(),
                                   email: normalized,
                                   displayName: AuthRules.cleanDisplayName(displayName),
                                   createdAt: created,
                                   salt: salt,
                                   passwordHash: digest,
                                   iterations: iterations)

        // Eerste account: neem het oude bestand van vóór de accounts over, zodat er niets kwijtraakt.
        let fm = FileManager.default
        let target = storageURL(for: record.account)
        var movedLegacy = false
        if records.isEmpty && fm.fileExists(atPath: legacyURL.path) {
            do {
                try fm.moveItem(at: legacyURL, to: target)
                movedLegacy = true
            } catch {
                throw AuthError.storage
            }
        }

        let updated = records + [record]
        do {
            try persist(updated)
        } catch {
            if movedLegacy { try? fm.moveItem(at: target, to: legacyURL) }
            throw error
        }
        records = updated
        startSession(record)
        return record.account
    }

    // MARK: Inloggen en uitloggen

    @discardableResult
    func signIn(email: String, password: String) throws -> Account {
        let normalized = AuthRules.normalizeEmail(email)
        guard AuthRules.isValidEmail(normalized) else { throw AuthError.invalidEmail }
        let stored = try authenticate(email: normalized, password: password)
        startSession(stored)
        return stored.account
    }

    func signOut() {
        currentAccount = nil
        defaults.removeObject(forKey: AuthStore.sessionKey)
    }

    // MARK: Beheer van het ingelogde account

    /// Verwijdert het account en zijn gegevensbestand. Vraagt om het wachtwoord.
    func deleteCurrentAccount(password: String) throws {
        guard let current = currentAccount,
              let stored = records.first(where: { $0.id == current.id }) else { throw AuthError.notSignedIn }
        _ = try authenticate(email: stored.email, password: password)

        let remaining = records.filter { $0.id != stored.id }
        try persist(remaining)
        records = remaining
        try? FileManager.default.removeItem(at: storageURL(for: current))
        signOut()
    }

    /// Wijzigt het wachtwoord van het ingelogde account. Er komt een nieuw zout bij.
    func changePassword(old: String, new: String) throws {
        guard let current = currentAccount,
              let index = records.firstIndex(where: { $0.id == current.id }) else { throw AuthError.notSignedIn }
        _ = try authenticate(email: records[index].email, password: old)
        guard AuthRules.isStrongPassword(new) else { throw AuthError.weakPassword }

        let salt = PasswordHasher.randomSalt()
        let digest = PasswordHasher.hash(password: new, salt: salt, iterations: iterations)
        guard !digest.isEmpty else { throw AuthError.storage }

        var updated = records
        updated[index].salt = salt
        updated[index].passwordHash = digest
        updated[index].iterations = iterations
        try persist(updated)
        records = updated
    }

    // MARK: Intern

    private func startSession(_ stored: StoredAccount) {
        currentAccount = stored.account
        defaults.set(stored.id.uuidString, forKey: AuthStore.sessionKey)
    }

    /// Controleert e-mailadres en wachtwoord, met blokkade na te veel mislukte pogingen.
    private func authenticate(email: String, password: String) throws -> StoredAccount {
        try checkLockout(for: email)
        guard let stored = records.first(where: { $0.email == email }) else {
            _ = PasswordHasher.hash(password: password, salt: AuthStore.decoySalt, iterations: iterations)
            recordFailure(for: email)
            throw AuthError.wrongCredentials
        }
        let ok = PasswordHasher.verify(password: password,
                                       salt: stored.salt,
                                       iterations: stored.iterations,
                                       expected: stored.passwordHash)
        guard ok else {
            recordFailure(for: email)
            throw AuthError.wrongCredentials
        }
        failures[email] = nil
        return stored
    }

    private func checkLockout(for email: String) throws {
        guard let until = failures[email]?.lockedUntil else { return }
        let remaining = until.timeIntervalSince(clock())
        if remaining > 0 {
            throw AuthError.tooManyAttempts(seconds: Int(remaining.rounded(.up)))
        }
        // De blokkade is voorbij: begin met een schone teller.
        failures[email] = nil
    }

    private func recordFailure(for email: String) {
        var failure = failures[email] ?? Failure()
        failure.count += 1
        if failure.count >= AuthStore.maxFailedAttempts {
            failure.lockedUntil = clock().addingTimeInterval(AuthStore.lockoutSeconds)
        }
        failures[email] = failure
    }

    // MARK: Bestand

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Leest accounts.json. Een onleesbaar bestand wordt apart bewaard en nooit stilletjes overschreven.
    private static func loadRecords(at url: URL) -> [StoredAccount] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try makeDecoder().decode(AccountsFile.self, from: data).accounts
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("accounts.corrupt-\(stamp).json")
            try? fm.moveItem(at: url, to: backup)
            return []
        }
    }

    private func persist(_ newRecords: [StoredAccount]) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try AuthStore.makeEncoder().encode(AccountsFile(version: 1, accounts: newRecords))
            try data.write(to: accountsURL, options: .atomic)
        } catch {
            throw AuthError.storage
        }
    }
}
