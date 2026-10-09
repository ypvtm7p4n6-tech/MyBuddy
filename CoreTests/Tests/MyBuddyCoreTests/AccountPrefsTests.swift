import XCTest
@testable import MyBuddyCore

/// Instellingen en invoer per account (UserDefaults): sleutels met een achtervoegsel en alles in één keer opruimen.
final class AccountPrefsTests: XCTestCase {
    /// Een eigen, lege UserDefaults per test.
    private func makeDefaults(_ name: String) throws -> (defaults: UserDefaults, cleanup: () -> Void) {
        let suite = "MyBuddyTests.AccountPrefs.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    func testKeyAddsTheAccountAsSuffix() {
        XCTAssertEqual(AccountPrefs.key("savingsGoalDraft", account: "abc"), "savingsGoalDraft.abc")
        XCTAssertEqual(AccountPrefs.key("x", account: "cloud-uid1"), "x.cloud-uid1")
        // Dezelfde indeling als de Buffer en de Aankoopcheck al gebruikten.
        XCTAssertEqual(AccountPrefs.key(BufferSetup.storageKey, account: "abc"), BufferSetup.storageKey + ".abc")
        XCTAssertEqual(AccountPrefs.key(PurchaseCalc.wageStorageKey, account: "abc"), PurchaseCalc.accountWageKey("abc"))
        XCTAssertEqual(AccountPrefs.key(PurchaseCalc.wageStorageKey, account: "demo"), PurchaseCalc.accountWageKey(nil))
    }

    func testAllKnownBaseKeysAreListed() {
        XCTAssertTrue(AccountPrefs.baseKeys.contains(SavingsGoalDraft.storageKey))
        XCTAssertTrue(AccountPrefs.baseKeys.contains(BufferSetup.storageKey))
        XCTAssertTrue(AccountPrefs.baseKeys.contains(PurchaseCalc.wageStorageKey))
        XCTAssertEqual(Set(AccountPrefs.baseKeys).count, AccountPrefs.baseKeys.count, "geen dubbele sleutels")
    }

    func testClearAllRemovesEveryKeyOfThatAccountOnly() throws {
        let (defaults, cleanup) = try makeDefaults("ClearAll")
        defer { cleanup() }
        for account in ["a", "b"] {
            for base in AccountPrefs.baseKeys {
                defaults.set("waarde-\(account)", forKey: AccountPrefs.key(base, account: account))
            }
        }
        defaults.set("los", forKey: "iets.anders")
        defaults.set("oud", forKey: SavingsGoalDraft.storageKey)

        AccountPrefs.clearAll(account: "a", defaults: defaults)

        for base in AccountPrefs.baseKeys {
            XCTAssertNil(defaults.object(forKey: AccountPrefs.key(base, account: "a")), base)
            XCTAssertEqual(defaults.string(forKey: AccountPrefs.key(base, account: "b")), "waarde-b", "account b blijft staan: \(base)")
        }
        XCTAssertEqual(defaults.string(forKey: "iets.anders"), "los")
        XCTAssertEqual(defaults.string(forKey: SavingsGoalDraft.storageKey), "oud", "de gedeelde sleutel zonder account blijft staan")

        // Nog eens wissen als er niets staat, mag. Een onbekend account ook.
        AccountPrefs.clearAll(account: "a", defaults: defaults)
        AccountPrefs.clearAll(account: "bestaat-niet", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AccountPrefs.key(BufferSetup.storageKey, account: "b")), "waarde-b")
    }

    func testClearAllRemovesTheRealStoredValues() throws {
        let (defaults, cleanup) = try makeDefaults("RealValues")
        defer { cleanup() }
        var draft = SavingsGoalDraft()
        draft.goal = 7_000
        draft.edited = true
        defaults.set(draft.json, forKey: SavingsGoalDraft.storageKey(account: "a"))
        var setup = BufferSetup()
        setup.manualCurrent = 1_234
        defaults.set(setup.json, forKey: AccountPrefs.key(BufferSetup.storageKey, account: "a"))
        defaults.set(31.5, forKey: PurchaseCalc.accountWageKey("a"))

        XCTAssertEqual(SavingsGoalDraft.decode(defaults.string(forKey: SavingsGoalDraft.storageKey(account: "a")) ?? "")?.goal, 7_000)
        AccountPrefs.clearAll(account: "a", defaults: defaults)
        XCTAssertNil(defaults.string(forKey: SavingsGoalDraft.storageKey(account: "a")))
        XCTAssertNil(BufferSetup.fromJSON(defaults.string(forKey: AccountPrefs.key(BufferSetup.storageKey, account: "a")) ?? ""))
        XCTAssertEqual(defaults.double(forKey: PurchaseCalc.accountWageKey("a")), 0)
    }

    // MARK: Spaardoel-concept per account

    func testDraftKeyPerAccountAndTheOldKeyStayAvailable() {
        XCTAssertEqual(SavingsGoalDraft.storageKey, "savingsGoalDraft", "de basissleutel verandert niet")
        XCTAssertEqual(SavingsGoalDraft.storageKey(account: "abc"), "savingsGoalDraft.abc")
        XCTAssertEqual(SavingsGoalDraft.storageKey(account: "demo"), "savingsGoalDraft.demo")
        let key: String = SavingsGoalDraft.storageKey
        XCTAssertEqual(key, "savingsGoalDraft")
    }

    func testClearStoredWithAnAccountRemovesThatAccountsDraft() throws {
        let (defaults, cleanup) = try makeDefaults("Draft")
        defer { cleanup() }
        var draft = SavingsGoalDraft()
        draft.goal = 9_000
        draft.edited = true
        defaults.set(draft.json, forKey: SavingsGoalDraft.storageKey(account: "a"))
        defaults.set(draft.json, forKey: SavingsGoalDraft.storageKey(account: "b"))
        defaults.set(draft.json, forKey: SavingsGoalDraft.storageKey)

        SavingsGoalDraft.clearStored(in: defaults, account: "a")
        XCTAssertNil(defaults.string(forKey: SavingsGoalDraft.storageKey(account: "a")))
        XCTAssertNotNil(defaults.string(forKey: SavingsGoalDraft.storageKey(account: "b")), "een ander account blijft staan")
        XCTAssertNil(defaults.string(forKey: SavingsGoalDraft.storageKey), "de oude gedeelde invoer gaat mee")

        // Zonder account is het "demo", en bestaande aanroepen zonder het argument blijven werken.
        defaults.set(draft.json, forKey: SavingsGoalDraft.storageKey(account: "demo"))
        SavingsGoalDraft.clearStored(in: defaults)
        XCTAssertNil(defaults.string(forKey: SavingsGoalDraft.storageKey(account: "demo")))
        XCTAssertNotNil(defaults.string(forKey: SavingsGoalDraft.storageKey(account: "b")))
    }
}
