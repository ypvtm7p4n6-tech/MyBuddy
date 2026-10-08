import XCTest
@testable import MyBuddy

/// Een klok die de test zelf verzet, zodat de blokkade van 30 seconden niet echt hoeft te duren.
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class AuthTests: XCTestCase {
    /// Weinig rondes houdt de tests snel. Eén test gebruikt het echte aantal.
    private let fastRounds = 1_000
    private let password = "Welkom123"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Hulpjes

    private func makeEnvironment() throws -> (directory: URL, defaults: UserDefaults) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyBuddyAuthTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "nl.mybuddy.tests.auth.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        return (directory, defaults)
    }

    private func makeStore(_ env: (directory: URL, defaults: UserDefaults),
                           iterations: Int? = nil,
                           clock: @escaping () -> Date = { Date() }) -> AuthStore {
        AuthStore(directory: env.directory,
                  defaults: env.defaults,
                  iterations: iterations ?? fastRounds,
                  clock: clock)
    }

    private func assertThrows(_ expected: AuthError,
                              file: StaticString = #filePath,
                              line: UInt = #line,
                              _ body: () throws -> Void) {
        do {
            try body()
            XCTFail("Verwachtte de fout \(expected), maar er kwam geen fout", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AuthError, expected, file: file, line: line)
        }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func readAccountsFile(_ directory: URL) throws -> AccountsFile {
        let data = try Data(contentsOf: directory.appendingPathComponent("accounts.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AccountsFile.self, from: data)
    }

    // MARK: Hasher

    func testHasherMatchesKnownPBKDF2Vectors() {
        let salt = Data("salt".utf8)
        XCTAssertEqual(hex(PasswordHasher.hash(password: "password", salt: salt, iterations: 1)),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        XCTAssertEqual(hex(PasswordHasher.hash(password: "password", salt: salt, iterations: 2)),
                       "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        XCTAssertEqual(hex(PasswordHasher.hash(password: "password", salt: salt, iterations: 4096)),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    func testHasherHandlesUnicodePasswords() {
        let salt = Data("zout-zout-zout!!".utf8)
        XCTAssertEqual(hex(PasswordHasher.hash(password: "pässwörd🔑9", salt: salt, iterations: 10)),
                       "9580f4e00bb5bd558b8293305f7aa8458c9200b4e022182002031f685ee4b9a2")
    }

    func testHasherTreatsComposedAndDecomposedLettersAlike() {
        let salt = Data(Array(UInt8(0)..<UInt8(16)))
        let decomposed = "cafe\u{0301}-1234"
        let composed = "caf\u{00E9}-1234"
        let expected = "3341ddc7f2a2a1c7e1402c7551d932f6de3642a767641f941b5d8ff24a2b3fb3"
        XCTAssertEqual(hex(PasswordHasher.hash(password: decomposed, salt: salt, iterations: 1000)), expected)
        XCTAssertEqual(hex(PasswordHasher.hash(password: composed, salt: salt, iterations: 1000)), expected)
    }

    func testHasherIsDeterministicAndDependsOnSaltAndPassword() {
        let saltA = Data(repeating: 1, count: 16)
        let saltB = Data(repeating: 2, count: 16)
        let first = PasswordHasher.hash(password: "Geheim123", salt: saltA, iterations: 1000)
        let again = PasswordHasher.hash(password: "Geheim123", salt: saltA, iterations: 1000)
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, PasswordHasher.hash(password: "Geheim123", salt: saltB, iterations: 1000))
        XCTAssertNotEqual(first, PasswordHasher.hash(password: "Geheim124", salt: saltA, iterations: 1000))
        XCTAssertNotEqual(first, PasswordHasher.hash(password: "Geheim123", salt: saltA, iterations: 1001))
    }

    func testRandomSaltIsSixteenBytesAndDifferentEachTime() {
        let a = PasswordHasher.randomSalt()
        let b = PasswordHasher.randomSalt()
        XCTAssertEqual(a.count, 16)
        XCTAssertEqual(b.count, 16)
        XCTAssertNotEqual(a, b)
    }

    func testVerifyAcceptsOnlyTheRightPassword() {
        let salt = PasswordHasher.randomSalt()
        let stored = PasswordHasher.hash(password: "Geheim123", salt: salt, iterations: 1000)
        XCTAssertTrue(PasswordHasher.verify(password: "Geheim123", salt: salt, iterations: 1000, expected: stored))
        XCTAssertFalse(PasswordHasher.verify(password: "geheim123", salt: salt, iterations: 1000, expected: stored))
        XCTAssertFalse(PasswordHasher.verify(password: "Geheim123", salt: PasswordHasher.randomSalt(), iterations: 1000, expected: stored))
        XCTAssertFalse(PasswordHasher.verify(password: "Geheim123", salt: salt, iterations: 999, expected: stored))
        XCTAssertFalse(PasswordHasher.verify(password: "Geheim123", salt: salt, iterations: 1000, expected: Data()))
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(PasswordHasher.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 3])))
        XCTAssertTrue(PasswordHasher.constantTimeEquals(Data(), Data()))
        XCTAssertFalse(PasswordHasher.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 4])))
        XCTAssertFalse(PasswordHasher.constantTimeEquals(Data([1, 2, 3]), Data([1, 2])))
        XCTAssertFalse(PasswordHasher.constantTimeEquals(Data([1, 2]), Data([1, 2, 0])))
    }

    // MARK: Regels

    func testPasswordRules() {
        XCTAssertTrue(AuthRules.isStrongPassword("Abcdefg1"))
        XCTAssertTrue(AuthRules.isStrongPassword("een lange zin met 1 cijfer"))
        XCTAssertFalse(AuthRules.isStrongPassword("Abcdef1"))     // 7 tekens
        XCTAssertFalse(AuthRules.isStrongPassword("abcdefgh"))    // geen cijfer
        XCTAssertFalse(AuthRules.isStrongPassword("12345678"))    // geen letter
        XCTAssertFalse(AuthRules.isStrongPassword(""))
        XCTAssertTrue(AuthRules.PasswordRule.length.isMet(by: "12345678"))
        XCTAssertFalse(AuthRules.PasswordRule.letter.isMet(by: "12345678"))
        XCTAssertTrue(AuthRules.PasswordRule.digit.isMet(by: "12345678"))
        XCTAssertFalse(AuthRules.PasswordRule.digit.isMet(by: "abcdefgh"))
    }

    func testEmailValidation() {
        let valid = ["jan@mail.nl", "Jan.de-Vries+bank@Sub.Mail.nl", " jan@mail.nl "]
        for address in valid {
            XCTAssertTrue(AuthRules.isValidEmail(address), address)
        }
        let invalid = ["", "geen-email", "jan@mail", "a@@b.nl", "jan @mail.nl", "@mail.nl", "jan@.nl",
                       "jan@mail..nl", "jan@mail.n", "jan@mail.n1", ".jan@mail.nl", "jan.@mail.nl", "jan@-mail.nl"]
        for address in invalid {
            XCTAssertFalse(AuthRules.isValidEmail(address), address)
        }
        XCTAssertEqual(AuthRules.normalizeEmail("  Jan@Mail.NL \n"), "jan@mail.nl")
    }

    func testDisplayNameCleaning() {
        XCTAssertNil(AuthRules.cleanDisplayName(nil))
        XCTAssertNil(AuthRules.cleanDisplayName("   "))
        XCTAssertEqual(AuthRules.cleanDisplayName("  Jan  "), "Jan")
        XCTAssertEqual(AuthRules.cleanDisplayName(String(repeating: "x", count: 100))?.count, 60)
    }

    func testErrorMessagesAreDutchAndNeverEmpty() {
        let all: [AuthError] = [.invalidEmail, .weakPassword, .emailInUse, .wrongCredentials,
                                .tooManyAttempts(seconds: 30), .notSignedIn, .storage]
        for error in all {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
        XCTAssertTrue((AuthError.tooManyAttempts(seconds: 30).errorDescription ?? "").contains("30"))
        XCTAssertEqual(AuthError.tooManyAttempts(seconds: 30), AuthError.tooManyAttempts(seconds: 30))
        XCTAssertNotEqual(AuthError.tooManyAttempts(seconds: 30), AuthError.tooManyAttempts(seconds: 29))
    }

    // MARK: Account maken, uitloggen, inloggen

    func testRegisterSignOutSignInRoundTrip() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        XCTAssertNil(store.currentAccount)
        XCTAssertEqual(store.accountCount, 0)

        let account = try store.register(email: "  Jan@Mail.NL ", password: password, displayName: "  Jan  ")
        XCTAssertEqual(account.email, "jan@mail.nl")
        XCTAssertEqual(account.displayName, "Jan")
        XCTAssertEqual(store.currentAccount, account)
        XCTAssertEqual(store.accountCount, 1)
        XCTAssertEqual(env.defaults.string(forKey: "mybuddy.session.accountID"), account.id.uuidString)

        store.signOut()
        XCTAssertNil(store.currentAccount)
        XCTAssertNil(env.defaults.string(forKey: "mybuddy.session.accountID"))
        XCTAssertEqual(store.accountCount, 1)

        let signedIn = try store.signIn(email: "JAN@mail.nl", password: password)
        XCTAssertEqual(signedIn, account)
        XCTAssertEqual(store.currentAccount, account)
        XCTAssertEqual(env.defaults.string(forKey: "mybuddy.session.accountID"), account.id.uuidString)
    }

    func testRegisterWithoutNameStoresNil() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let account = try store.register(email: "jan@mail.nl", password: password, displayName: "   ")
        XCTAssertNil(account.displayName)
    }

    func testStorageURLIsPerAccountInsideTheDirectory() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let first = try store.register(email: "een@mail.nl", password: password, displayName: nil)
        let second = try store.register(email: "twee@mail.nl", password: password, displayName: nil)
        let firstURL = store.storageURL(for: first)
        let secondURL = store.storageURL(for: second)
        XCTAssertEqual(firstURL.lastPathComponent, "finance-\(first.id.uuidString).json")
        XCTAssertEqual(secondURL.lastPathComponent, "finance-\(second.id.uuidString).json")
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(firstURL.deletingLastPathComponent().standardizedFileURL.path,
                       env.directory.standardizedFileURL.path)
    }

    func testDefaultIterationsAreStoredAndNoPasswordIsWritten() throws {
        let env = try makeEnvironment()
        let store = AuthStore(directory: env.directory, defaults: env.defaults)
        let account = try store.register(email: "jan@mail.nl", password: password, displayName: nil)

        let file = try readAccountsFile(env.directory)
        XCTAssertEqual(file.version, 1)
        XCTAssertEqual(file.accounts.count, 1)
        let stored = try XCTUnwrap(file.accounts.first)
        XCTAssertEqual(stored.id, account.id)
        XCTAssertEqual(stored.iterations, 150_000)
        XCTAssertEqual(stored.salt.count, 16)
        XCTAssertEqual(stored.passwordHash.count, 32)

        let raw = try String(contentsOf: env.directory.appendingPathComponent("accounts.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains(password))

        // Een nieuwe instantie controleert het wachtwoord tegen wat op schijf staat.
        let reopened = AuthStore(directory: env.directory, defaults: env.defaults)
        reopened.signOut()
        let again = try reopened.signIn(email: "jan@mail.nl", password: password)
        XCTAssertEqual(again, account)
    }

    // MARK: Fouten bij maken en inloggen

    func testDuplicateEmailIsRejectedIgnoringCase() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        assertThrows(.emailInUse) {
            try store.register(email: " JAN@Mail.nl", password: "AnderWachtwoord9", displayName: nil)
        }
        XCTAssertEqual(store.accountCount, 1)
    }

    func testWeakPasswordsAreRejected() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        for candidate in ["kort1", "alleenletters", "12345678", ""] {
            assertThrows(.weakPassword) {
                try store.register(email: "jan@mail.nl", password: candidate, displayName: nil)
            }
        }
        XCTAssertEqual(store.accountCount, 0)
        XCTAssertNil(store.currentAccount)
    }

    func testInvalidEmailIsRejected() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        assertThrows(.invalidEmail) {
            try store.register(email: "geen-email", password: password, displayName: nil)
        }
        assertThrows(.invalidEmail) {
            try store.signIn(email: "geen-email", password: password)
        }
        XCTAssertEqual(store.accountCount, 0)
    }

    func testWrongPasswordAndUnknownEmailGiveTheSameError() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        store.signOut()

        assertThrows(.wrongCredentials) {
            try store.signIn(email: "jan@mail.nl", password: "Verkeerd123")
        }
        assertThrows(.wrongCredentials) {
            try store.signIn(email: "niemand@mail.nl", password: password)
        }
        XCTAssertNil(store.currentAccount)
        XCTAssertNil(env.defaults.string(forKey: "mybuddy.session.accountID"))
    }

    // MARK: Blokkade

    func testFiveWrongPasswordsLockTheEmailForThirtySeconds() throws {
        let env = try makeEnvironment()
        let clock = TestClock(start)
        let store = makeStore(env, clock: { clock.now })
        try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        try store.register(email: "piet@mail.nl", password: password, displayName: nil)
        store.signOut()

        for _ in 0..<5 {
            assertThrows(.wrongCredentials) {
                try store.signIn(email: "jan@mail.nl", password: "Verkeerd123")
            }
        }

        // Ook het juiste wachtwoord wordt nu geweigerd.
        assertThrows(.tooManyAttempts(seconds: 30)) {
            try store.signIn(email: "jan@mail.nl", password: password)
        }
        XCTAssertNil(store.currentAccount)

        // Een ander e-mailadres heeft er geen last van.
        let piet = try store.signIn(email: "piet@mail.nl", password: password)
        XCTAssertEqual(piet.email, "piet@mail.nl")
        store.signOut()

        clock.now = start.addingTimeInterval(10)
        assertThrows(.tooManyAttempts(seconds: 20)) {
            try store.signIn(email: "jan@mail.nl", password: password)
        }

        clock.now = start.addingTimeInterval(30)
        let jan = try store.signIn(email: "jan@mail.nl", password: password)
        XCTAssertEqual(jan.email, "jan@mail.nl")
    }

    func testCounterStartsOverAfterTheLockExpires() throws {
        let env = try makeEnvironment()
        let clock = TestClock(start)
        let store = makeStore(env, clock: { clock.now })
        try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        store.signOut()

        for _ in 0..<5 {
            assertThrows(.wrongCredentials) {
                try store.signIn(email: "jan@mail.nl", password: "Verkeerd123")
            }
        }
        clock.now = start.addingTimeInterval(31)
        // Na de blokkade krijg je weer vijf pogingen, niet één.
        for _ in 0..<4 {
            assertThrows(.wrongCredentials) {
                try store.signIn(email: "jan@mail.nl", password: "Verkeerd123")
            }
        }
        let account = try store.signIn(email: "jan@mail.nl", password: password)
        XCTAssertEqual(account.email, "jan@mail.nl")
    }

    func testSuccessfulSignInResetsTheFailureCounter() throws {
        let env = try makeEnvironment()
        let clock = TestClock(start)
        let store = makeStore(env, clock: { clock.now })
        try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        store.signOut()

        for _ in 0..<4 {
            assertThrows(.wrongCredentials) {
                try store.signIn(email: "jan@mail.nl", password: "Verkeerd123")
            }
        }
        try store.signIn(email: "jan@mail.nl", password: password)
        store.signOut()
        for _ in 0..<4 {
            assertThrows(.wrongCredentials) {
                try store.signIn(email: "jan@mail.nl", password: "Verkeerd123")
            }
        }
        // Zonder reset was het account na de vijfde fout in totaal al geblokkeerd.
        try store.signIn(email: "jan@mail.nl", password: password)
        XCTAssertNotNil(store.currentAccount)
    }

    func testUnknownEmailIsLockedToo() throws {
        let env = try makeEnvironment()
        let clock = TestClock(start)
        let store = makeStore(env, clock: { clock.now })
        for _ in 0..<5 {
            assertThrows(.wrongCredentials) {
                try store.signIn(email: "niemand@mail.nl", password: password)
            }
        }
        assertThrows(.tooManyAttempts(seconds: 30)) {
            try store.signIn(email: "niemand@mail.nl", password: password)
        }
    }

    // MARK: Gegevens van vóór de accounts

    func testFirstAccountAdoptsTheLegacyDataFile() throws {
        let env = try makeEnvironment()
        let legacy = env.directory.appendingPathComponent("finance.json")
        let payload = Data("{\"legacy\":true}".utf8)
        try payload.write(to: legacy)

        let store = makeStore(env)
        let account = try store.register(email: "jan@mail.nl", password: password, displayName: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let adopted = store.storageURL(for: account)
        XCTAssertTrue(FileManager.default.fileExists(atPath: adopted.path))
        XCTAssertEqual(try Data(contentsOf: adopted), payload)
    }

    func testSecondAccountDoesNotTakeTheLegacyFile() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        _ = try store.register(email: "een@mail.nl", password: password, displayName: nil)

        let legacy = env.directory.appendingPathComponent("finance.json")
        try Data("{\"legacy\":true}".utf8).write(to: legacy)
        let second = try store.register(email: "twee@mail.nl", password: password, displayName: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.storageURL(for: second).path))
    }

    func testRegisteringWithoutLegacyFileCreatesNoDataFile() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let account = try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.storageURL(for: account).path))
    }

    // MARK: Verwijderen

    func testDeleteAccountRemovesRecordDataAndSession() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let account = try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        let dataURL = store.storageURL(for: account)
        try Data("{}".utf8).write(to: dataURL)

        assertThrows(.wrongCredentials) {
            try store.deleteCurrentAccount(password: "Verkeerd123")
        }
        XCTAssertEqual(store.accountCount, 1)
        XCTAssertNotNil(store.currentAccount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path))

        try store.deleteCurrentAccount(password: password)
        XCTAssertNil(store.currentAccount)
        XCTAssertEqual(store.accountCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataURL.path))
        XCTAssertNil(env.defaults.string(forKey: "mybuddy.session.accountID"))

        let reopened = makeStore(env)
        XCTAssertEqual(reopened.accountCount, 0)
        assertThrows(.wrongCredentials) {
            try reopened.signIn(email: "jan@mail.nl", password: password)
        }
        let file = try readAccountsFile(env.directory)
        XCTAssertTrue(file.accounts.isEmpty)
    }

    func testDeleteLeavesOtherAccountsUntouched() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let first = try store.register(email: "een@mail.nl", password: password, displayName: nil)
        let second = try store.register(email: "twee@mail.nl", password: "Ander12345", displayName: nil)
        try Data("een".utf8).write(to: store.storageURL(for: first))
        try Data("twee".utf8).write(to: store.storageURL(for: second))

        try store.deleteCurrentAccount(password: "Ander12345")   // ingelogd als "twee"
        XCTAssertEqual(store.accountCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.storageURL(for: first).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.storageURL(for: second).path))
        _ = try store.signIn(email: "een@mail.nl", password: password)
    }

    func testDeleteWithoutSignInFails() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        assertThrows(.notSignedIn) {
            try store.deleteCurrentAccount(password: password)
        }
    }

    func testSignOutKeepsTheDataFile() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let account = try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        let dataURL = store.storageURL(for: account)
        try Data("{}".utf8).write(to: dataURL)
        store.signOut()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path))
    }

    // MARK: Wachtwoord wijzigen

    func testChangePasswordRehashesWithNewSalt() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        let before = try XCTUnwrap(try readAccountsFile(env.directory).accounts.first)

        assertThrows(.wrongCredentials) {
            try store.changePassword(old: "Verkeerd123", new: "Nieuw123456")
        }
        assertThrows(.weakPassword) {
            try store.changePassword(old: password, new: "kort")
        }

        try store.changePassword(old: password, new: "Nieuw123456")
        let after = try XCTUnwrap(try readAccountsFile(env.directory).accounts.first)
        XCTAssertNotEqual(before.salt, after.salt)
        XCTAssertNotEqual(before.passwordHash, after.passwordHash)
        XCTAssertEqual(before.id, after.id)
        XCTAssertEqual(store.currentAccount?.id, before.id)

        store.signOut()
        assertThrows(.wrongCredentials) {
            try store.signIn(email: "jan@mail.nl", password: password)
        }
        let account = try store.signIn(email: "jan@mail.nl", password: "Nieuw123456")
        XCTAssertEqual(account.id, before.id)
    }

    func testChangePasswordNeedsSignIn() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        assertThrows(.notSignedIn) {
            try store.changePassword(old: password, new: "Nieuw123456")
        }
    }

    // MARK: Sessie en bestanden

    func testSessionIsRestoredByANewStore() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let account = try store.register(email: "jan@mail.nl", password: password, displayName: "Jan")

        let restored = makeStore(env)
        XCTAssertEqual(restored.currentAccount, account)
        XCTAssertEqual(restored.accountCount, 1)

        restored.signOut()
        let afterSignOut = makeStore(env)
        XCTAssertNil(afterSignOut.currentAccount)
        XCTAssertEqual(afterSignOut.accountCount, 1)
    }

    func testSessionForAMissingAccountIsDiscarded() throws {
        let env = try makeEnvironment()
        env.defaults.set(UUID().uuidString, forKey: "mybuddy.session.accountID")
        let store = makeStore(env)
        XCTAssertNil(store.currentAccount)
        XCTAssertNil(env.defaults.string(forKey: "mybuddy.session.accountID"))

        env.defaults.set("geen-uuid", forKey: "mybuddy.session.accountID")
        let other = makeStore(env)
        XCTAssertNil(other.currentAccount)
        XCTAssertNil(env.defaults.string(forKey: "mybuddy.session.accountID"))
    }

    func testUnreadableAccountsFileIsSetAsideNotOverwritten() throws {
        let env = try makeEnvironment()
        let url = env.directory.appendingPathComponent("accounts.json")
        try Data("dit is geen json".utf8).write(to: url)

        let store = makeStore(env)
        XCTAssertEqual(store.accountCount, 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: env.directory.path)
        XCTAssertTrue(names.contains(where: { $0.hasPrefix("accounts.corrupt-") }))
        XCTAssertFalse(names.contains("accounts.json"))

        // Een nieuw account kan gewoon gemaakt worden.
        _ = try store.register(email: "jan@mail.nl", password: password, displayName: nil)
        XCTAssertEqual(store.accountCount, 1)
    }

    func testAccountsSurviveARestart() throws {
        let env = try makeEnvironment()
        let store = makeStore(env)
        let first = try store.register(email: "een@mail.nl", password: password, displayName: "Een")
        let second = try store.register(email: "twee@mail.nl", password: "Ander12345", displayName: nil)
        store.signOut()

        let reopened = makeStore(env)
        XCTAssertEqual(reopened.accountCount, 2)
        XCTAssertEqual(try reopened.signIn(email: "een@mail.nl", password: password), first)
        XCTAssertEqual(try reopened.signIn(email: "twee@mail.nl", password: "Ander12345"), second)
    }
}
