import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MyBuddyCore

final class FirebaseDatabaseTests: XCTestCase {
    private let base = URL(string: "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app")!
    private let uid = "uid123"
    private let token = "tok-uid123"

    private func makeClient(_ db: FakeRealtimeDatabase) -> FirebaseDatabaseClient {
        FirebaseDatabaseClient(baseURL: base, http: db)
    }

    // MARK: Adressen

    func testFinanceURLPointsToTheUsersOwnPathWithTheToken() throws {
        let client = makeClient(FakeRealtimeDatabase())
        let url = try client.financeURL(uid: uid, idToken: "a.b-c_d")
        XCTAssertEqual(url.host, "my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.path, "/users/uid123/finance.json")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "auth" })?.value, "a.b-c_d")
        XCTAssertNil(items.first(where: { $0.name == "print" }))

        let silent = try client.financeURL(uid: uid, idToken: "t", silent: true)
        XCTAssertTrue(silent.absoluteString.contains("print=silent"))

        let userURL = try client.userURL(uid: uid, idToken: "t")
        XCTAssertEqual(userURL.path, "/users/uid123.json")
    }

    func testUnsafeUserIDsAreRejected() {
        let client = makeClient(FakeRealtimeDatabase())
        for bad in ["", "a/b", "../x", "uid 1", "uid.json", "uid?x=1", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try client.financeURL(uid: bad, idToken: "t"), bad) { error in
                XCTAssertEqual(error as? FirebaseDatabaseError, .invalidUser)
            }
        }
        for good in ["abc", "ABC123", "xYz9AbC0dEfGhIjKlMnOpQrStUvW", "a-b_c"] {
            XCTAssertTrue(FirebaseDatabaseClient.isValidUID(good), good)
        }
    }

    func testDatabaseURLInitialiserNeedsHTTPS() {
        XCTAssertNotNil(FirebaseDatabaseClient(databaseURL: "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app"))
        XCTAssertNil(FirebaseDatabaseClient(databaseURL: "http://example.com"))
        XCTAssertNil(FirebaseDatabaseClient(databaseURL: "geen url"))
    }

    // MARK: Lezen

    func testFetchReturnsNilWhenNothingIsStored() async throws {
        let db = FakeRealtimeDatabase()
        let snapshot = try await makeClient(db).fetchFinance(uid: uid, idToken: token)
        XCTAssertNil(snapshot)
        XCTAssertEqual(db.log.count, 1)
        XCTAssertEqual(db.log[0].method, "GET")
        XCTAssertEqual(db.log[0].path, "/users/uid123/finance.json")
        XCTAssertEqual(db.log[0].query["auth"], token)
        XCTAssertEqual(db.log[0].headers["x-firebase-etag"], "true")
    }

    func testFetchParsesTheDocumentAndTheETag() async throws {
        let db = FakeRealtimeDatabase()
        let finance = cloudFinance(salary: 3210, modified: cloudAt(90))
        try db.seed(finance, device: "iPad (ab12)")
        let fetched = try await makeClient(db).fetchFinance(uid: uid, idToken: token)
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertEqual(snapshot.device, "iPad (ab12)")
        XCTAssertEqual(snapshot.schema, 1)
        XCTAssertEqual(snapshot.modifiedAt, cloudAt(90))
        XCTAssertEqual(snapshot.etag, "etag-1")
        XCTAssertTrue(snapshot.isSupported)
        let decoded = try snapshot.decodeFinance()
        XCTAssertEqual(decoded.salary.fixedMonthly, 3210)
        XCTAssertTrue(CloudSync.contentEqual(decoded, finance))
    }

    func testFetchToleratesNumbersAndMissingOptionalFields() async throws {
        let db = FakeRealtimeDatabase()
        let finance = cloudFinance()
        let text = try FirebaseDatabaseClient.encodeFinance(finance)
        let escaped = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
        db.seedRaw(#"{"data":\#(escaped),"modifiedAt":1790000042000}"#)
        let fetched = try await makeClient(db).fetchFinance(uid: uid, idToken: token)
        let snapshot = try XCTUnwrap(fetched)
        XCTAssertEqual(snapshot.device, "")
        XCTAssertEqual(snapshot.schema, 1)
        XCTAssertEqual(snapshot.modifiedAt, Date(timeIntervalSince1970: 1_790_000_042))
    }

    func testFetchWithUnusableDocumentIsUnreadable() async throws {
        let db = FakeRealtimeDatabase()
        db.seedRaw(#"{"iets":"anders"}"#)
        do {
            _ = try await makeClient(db).fetchFinance(uid: uid, idToken: token)
            XCTFail("Een document zonder data hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .unreadable)
        }
    }

    func testFetchErrors() async throws {
        let db = FakeRealtimeDatabase()
        let client = makeClient(db)

        // Verlopen token: 401 zonder "Permission denied".
        db.rejectedTokens = [token]
        do {
            _ = try await client.fetchFinance(uid: uid, idToken: token)
            XCTFail("Verlopen token hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .unauthorized)
        }

        // Het pad van een ander: de regels weigeren.
        db.rejectedTokens = []
        do {
            _ = try await client.fetchFinance(uid: "andere", idToken: token)
            XCTFail("Andermans pad hoort geweigerd te worden")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .permissionDenied)
        }

        // Geen internet.
        db.offline = true
        do {
            _ = try await client.fetchFinance(uid: uid, idToken: token)
            XCTFail("Zonder internet hoort een fout te komen")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .network)
        }
    }

    func testStatusCodesMapToDutchErrors() {
        XCTAssertEqual(FirebaseDatabaseClient.error(status: 401, body: Data(#"{"error":"Permission denied"}"#.utf8)), .permissionDenied)
        XCTAssertEqual(FirebaseDatabaseClient.error(status: 401, body: Data(#"{"error":"Auth token is expired"}"#.utf8)), .unauthorized)
        XCTAssertEqual(FirebaseDatabaseClient.error(status: 401, body: Data(#"{"error":"Could not parse auth token."}"#.utf8)), .unauthorized)
        XCTAssertEqual(FirebaseDatabaseClient.error(status: 404, body: Data()), .databaseNotFound)
        XCTAssertEqual(FirebaseDatabaseClient.error(status: 500, body: Data()), .server(500))
        XCTAssertEqual(FirebaseDatabaseClient.error(status: 503, body: Data()), .server(503))
        // Een 400 laat de toelichting van de database zien, zodat de oorzaak te vinden is.
        let bad = FirebaseDatabaseClient.error(status: 400, body: Data("{\"error\":\"Invalid data\"}".utf8))
        XCTAssertEqual(bad, .rejected(status: 400, message: "Invalid data"))
        XCTAssertTrue((bad.errorDescription ?? "").contains("Invalid data"))
        XCTAssertEqual(FirebaseDatabaseClient.error(status: 400, body: Data()), .server(400))
        let all: [FirebaseDatabaseError] = [.unauthorized, .permissionDenied, .databaseNotFound, .tooLarge(bytes: 9_000_000),
                                            .tooLarge(bytes: 0), .network, .server(500), .badResponse, .invalidUser,
                                            .unreadable, .unsupportedSchema(2)]
        for error in all {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error)")
        }
        XCTAssertTrue(FirebaseDatabaseError.permissionDenied.errorDescription!.contains("database.rules.json"))
        XCTAssertTrue(FirebaseDatabaseError.databaseNotFound.errorDescription!.contains("FirebaseConfig.swift"))
    }

    // MARK: Schrijven

    func testWriteSendsTheEnvelopeAndTheStorageEncodingOfTheData() async throws {
        let db = FakeRealtimeDatabase()
        let finance = cloudFinance(salary: 2750, modified: cloudAt(120))
        let result = try await makeClient(db).writeFinance(finance, uid: uid, idToken: token, device: "iPhone (a1b2)", ifMatch: FirebaseDatabaseClient.nullETag)

        guard case .written(let receipt) = result else { return XCTFail("Schrijven hoort te slagen") }
        XCTAssertEqual(receipt.etag, "etag-1")
        XCTAssertFalse(receipt.sizeWarning)
        XCTAssertEqual(receipt.snapshot.modifiedAt, cloudAt(120))

        let entry = try XCTUnwrap(db.log.first)
        XCTAssertEqual(entry.method, "PUT")
        XCTAssertEqual(entry.path, "/users/uid123/finance.json")
        XCTAssertNil(entry.query["print"], "print=silent samen met if-match geeft bij Firebase een 400")
        XCTAssertEqual(entry.headers["if-match"], "null_etag")
        XCTAssertEqual(entry.headers["content-type"], "application/json")

        // Het document heeft precies de afgesproken velden.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(entry.body.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["data", "modifiedAt", "device", "schema"])
        XCTAssertEqual((object["modifiedAt"] as? NSNumber)?.int64Value, Int64(cloudAt(120).timeIntervalSince1970 * 1000))
        XCTAssertEqual(object["device"] as? String, "iPhone (a1b2)")
        XCTAssertEqual((object["schema"] as? NSNumber)?.intValue, 1)

        // De tekst is dezelfde als in het opslagbestand (zelfde encoder), dus uitwisselbaar.
        let fileBytes = try FinanceStorage.makeEncoder().encode(finance)
        XCTAssertEqual(object["data"] as? String, String(data: fileBytes, encoding: .utf8))
        let decoded = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data((object["data"] as? String ?? "").utf8))
        XCTAssertEqual(decoded.salary.fixedMonthly, 2750)
        XCTAssertEqual(decoded.modifiedAt, cloudAt(120))
    }

    func testCloudDataCanBeSavedAsLocalFileAndBack() throws {
        let finance = cloudFinance(salary: 1234, modified: cloudAt(5))
        let snapshot = try RemoteSnapshot(finance: finance, device: "x")
        let directory = try cloudTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("finance.json")
        try Data(snapshot.json.utf8).write(to: url)
        guard case .loaded(let loaded) = FinanceStorage(url: url).load() else { return XCTFail("Het bestand hoort te laden") }
        XCTAssertEqual(loaded, finance)

        // En andersom: een bestand van FinanceStorage is geldige cloudtekst.
        try FinanceStorage(url: url).save(finance)
        let text = try String(contentsOf: url, encoding: .utf8)
        let again = RemoteSnapshot(json: text, modifiedAt: cloudAt(5))
        XCTAssertEqual(try again.decodeFinance(), finance)
    }

    func testWriteIsRefusedWhenThePreconditionFails() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance(salary: 1), modified: cloudAt(10))
        let client = makeClient(db)
        let result = try await client.writeFinance(cloudFinance(salary: 2, modified: cloudAt(20)), uid: uid, idToken: token,
                                                   device: "d", ifMatch: "etag-0")
        XCTAssertEqual(result, .preconditionFailed)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 1)

        // Met de juiste ETag lukt het wel.
        let ok = try await client.writeFinance(cloudFinance(salary: 2, modified: cloudAt(20)), uid: uid, idToken: token,
                                               device: "d", ifMatch: db.etag)
        if case .written = ok {} else { XCTFail("Met de juiste ETag hoort schrijven te slagen") }
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 2)
    }

    func testNullETagOnlyAllowsCreatingWhenNothingIsStored() async throws {
        let db = FakeRealtimeDatabase()
        let client = makeClient(db)
        let first = try await client.writeFinance(cloudFinance(salary: 1), uid: uid, idToken: token, device: "d", ifMatch: FirebaseDatabaseClient.nullETag)
        if case .written = first {} else { XCTFail("Aanmaken hoort te slagen") }
        let second = try await client.writeFinance(cloudFinance(salary: 2), uid: uid, idToken: token, device: "d", ifMatch: FirebaseDatabaseClient.nullETag)
        XCTAssertEqual(second, .preconditionFailed)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 1)
    }

    func testWriteWithoutETagIsUnconditional() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance(salary: 1))
        let result = try await makeClient(db).writeFinance(cloudFinance(salary: 5), uid: uid, idToken: token, device: "d", ifMatch: nil)
        if case .written = result {} else { XCTFail("Zonder voorwaarde hoort schrijven te slagen") }
        XCTAssertNil(db.log.last?.headers["if-match"])
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 5)
    }

    func testWriteWhenTheDatabaseSendsNoETagBack() async throws {
        let db = FakeRealtimeDatabase()
        db.sendsETagOnWrite = false
        let result = try await makeClient(db).writeFinance(cloudFinance(), uid: uid, idToken: token, device: "d", ifMatch: nil)
        guard case .written(let receipt) = result else { return XCTFail("Schrijven hoort te slagen") }
        XCTAssertNil(receipt.etag)
    }

    func testWriteErrors() async throws {
        let db = FakeRealtimeDatabase()
        let client = makeClient(db)

        db.rejectedTokens = [token]
        do {
            _ = try await client.writeFinance(cloudFinance(), uid: uid, idToken: token, device: "d", ifMatch: nil)
            XCTFail("Verlopen token hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .unauthorized)
        }
        db.rejectedTokens = []

        db.forbidWrites = true
        do {
            _ = try await client.writeFinance(cloudFinance(), uid: uid, idToken: token, device: "d", ifMatch: nil)
            XCTFail("Regels die schrijven weigeren horen een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .permissionDenied)
        }
        db.forbidWrites = false

        db.offline = true
        do {
            _ = try await client.writeFinance(cloudFinance(), uid: uid, idToken: token, device: "d", ifMatch: nil)
            XCTFail("Zonder internet hoort een fout te komen")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .network)
        }
    }

    func testSizeGuardWarnsAboveFiveMegabytesAndRefusesAboveTheLimit() async throws {
        let db = FakeRealtimeDatabase()
        let client = makeClient(db)

        // Ruim boven 5 MB: wel schrijven, met waarschuwing.
        var big = cloudFinance()
        big.editPlan(oct2026) { $0.expenses.append(MoneyLine(name: String(repeating: "x", count: 5_300_000), amount: 1)) }
        let warned = try await client.writeFinance(big, uid: uid, idToken: token, device: "d", ifMatch: nil)
        guard case .written(let receipt) = warned else { return XCTFail("Een grote maar toegestane write hoort te slagen") }
        XCTAssertTrue(receipt.sizeWarning)
        XCTAssertGreaterThan(receipt.bytes, FirebaseDatabaseClient.warnBytes)
        XCTAssertLessThan(receipt.bytes, FirebaseDatabaseClient.maxBytes)

        // Boven de bovengrens: niet versturen.
        var huge = cloudFinance()
        huge.editPlan(oct2026) { $0.expenses.append(MoneyLine(name: String(repeating: "y", count: 7_600_000), amount: 1)) }
        let before = db.log.count
        do {
            _ = try await client.writeFinance(huge, uid: uid, idToken: token, device: "d", ifMatch: nil)
            XCTFail("Te grote gegevens horen geweigerd te worden")
        } catch let error as FirebaseDatabaseError {
            guard case .tooLarge(let bytes) = error else { return XCTFail("Verwachtte tooLarge, kreeg \(error)") }
            XCTAssertGreaterThan(bytes, FirebaseDatabaseClient.maxBytes)
        }
        XCTAssertEqual(db.log.count, before, "Er mag niets verstuurd zijn")

        // Een gewone dataset is ruim onder de waarschuwing.
        let small = try await client.writeFinance(cloudFinance(), uid: uid, idToken: token, device: "d", ifMatch: nil)
        if case .written(let r) = small { XCTAssertFalse(r.sizeWarning) } else { XCTFail("Kleine write hoort te slagen") }
    }

    // MARK: Verwijderen en live volgen

    func testDeleteUserDataRemovesTheWholeUserPath() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance())
        try await makeClient(db).deleteUserData(uid: uid, idToken: token)
        XCTAssertEqual(db.log.last?.method, "DELETE")
        XCTAssertEqual(db.log.last?.path, "/users/uid123.json")
        XCTAssertEqual(db.log.last?.query["auth"], token)
        XCTAssertNil(db.document)

        // Andermans pad blijft dicht.
        do {
            try await makeClient(db).deleteUserData(uid: "andere", idToken: token)
            XCTFail("Andermans gegevens verwijderen hoort geweigerd te worden")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .permissionDenied)
        }
    }

    func testStreamRequestAsksForServerSentEvents() throws {
        let client = makeClient(FakeRealtimeDatabase())
        let request = try client.streamRequest(uid: uid, idToken: "t0k")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.url?.path, "/users/uid123/finance.json")
        XCTAssertTrue(request.url?.absoluteString.contains("auth=t0k") ?? false)
        XCTAssertGreaterThanOrEqual(request.timeoutInterval, 60)
        XCTAssertThrowsError(try client.streamRequest(uid: "a/b", idToken: "t"))
    }

    // MARK: Document

    func testSnapshotInitialisersAndSchemaCheck() throws {
        let finance = cloudFinance(modified: cloudAt(33))
        let snapshot = try RemoteSnapshot(finance: finance, device: "Mac")
        XCTAssertEqual(snapshot.modifiedAt, cloudAt(33))
        XCTAssertEqual(snapshot.schema, 1)
        XCTAssertTrue(snapshot.isSupported)
        let future = RemoteSnapshot(json: "{}", modifiedAt: cloudAt(1), device: "x", schema: 2)
        XCTAssertFalse(future.isSupported)
        XCTAssertThrowsError(try RemoteSnapshot(json: "geen json", modifiedAt: cloudAt(1)).decodeFinance()) { error in
            XCTAssertEqual(error as? FirebaseDatabaseError, .unreadable)
        }
        let explicit = try RemoteSnapshot(finance: finance, modifiedAt: cloudAt(99))
        XCTAssertEqual(explicit.modifiedAt, cloudAt(99))
    }

    // MARK: Account verwijderen (gegevens eerst)

    private func authHTTP(deleteOK: Bool = true) -> CloudMockHTTP {
        CloudMockHTTP { request in
            switch request.url?.path {
            case "/v1/accounts:signInWithPassword":
                return (200, #"{"localId":"uid123","email":"jan@mail.nl","idToken":"tok-uid123","refreshToken":"r","expiresIn":"3600"}"#)
            case "/v1/accounts:delete":
                return deleteOK ? (200, "{}") : (400, #"{"error":{"message":"CREDENTIAL_TOO_OLD_LOGIN_AGAIN"}}"#)
            default:
                return (404, "{}")
            }
        }
    }

    func testDeleteAccountRemovesTheDataBeforeTheAccount() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance())
        let auth = authHTTP()
        let secrets = InMemorySecretStore()
        let client = FirebaseAuthClient(apiKey: "K", http: auth, secrets: secrets)

        try await CloudAccountOperations.deleteAccount(email: "jan@mail.nl", password: "geheim", auth: client, database: makeClient(db))

        XCTAssertEqual(auth.path(0), "/v1/accounts:signInWithPassword")
        XCTAssertEqual(auth.path(1), "/v1/accounts:delete")
        XCTAssertEqual(db.methods(), ["DELETE"])
        XCTAssertNil(db.document)
        XCTAssertNil(client.storedIdentity())
        XCTAssertEqual(auth.bodyJSON(1)["idToken"] as? String, "tok-uid123")
    }

    func testDeleteAccountStopsWhenTheDataCannotBeRemoved() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance())
        db.offline = true
        let auth = authHTTP()
        let client = FirebaseAuthClient(apiKey: "K", http: auth, secrets: InMemorySecretStore())
        do {
            try await CloudAccountOperations.deleteAccount(email: "jan@mail.nl", password: "geheim", auth: client, database: makeClient(db))
            XCTFail("Zonder internet hoort verwijderen te mislukken")
        } catch {
            XCTAssertEqual(error as? FirebaseDatabaseError, .network)
        }
        XCTAssertEqual(auth.requests.count, 1, "Het account zelf mag niet verwijderd zijn")
        XCTAssertNotNil(db.document)
    }

    func testDeleteAccountWithWrongPasswordTouchesNothing() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance())
        let auth = CloudMockHTTP { _ in (400, #"{"error":{"message":"INVALID_LOGIN_CREDENTIALS"}}"#) }
        let client = FirebaseAuthClient(apiKey: "K", http: auth, secrets: InMemorySecretStore())
        do {
            try await CloudAccountOperations.deleteAccount(email: "jan@mail.nl", password: "fout", auth: client, database: makeClient(db))
            XCTFail("Fout wachtwoord hoort een fout te geven")
        } catch {
            XCTAssertEqual(error as? FirebaseAuthError, .wrongCredentials)
        }
        XCTAssertTrue(db.log.isEmpty)
        XCTAssertNotNil(db.document)
    }

    func testDeleteAccountStillDeletesTheAccountWhenThereIsNoDatabase() async throws {
        // Een database die niet bestaat (404) levert niets om te wissen op; het account mag wel weg.
        let missing = CloudMockHTTP { _ in (404, "{}") }
        let auth = authHTTP()
        let client = FirebaseAuthClient(apiKey: "K", http: auth, secrets: InMemorySecretStore())
        try await CloudAccountOperations.deleteAccount(email: "jan@mail.nl", password: "geheim", auth: client,
                                                       database: FirebaseDatabaseClient(baseURL: base, http: missing))
        XCTAssertEqual(auth.path(1), "/v1/accounts:delete")
    }
}
