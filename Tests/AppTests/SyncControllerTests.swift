import XCTest
@testable import MyBuddy

// Test van de hele synchronisatie in de app: CloudAccount, SyncController, AppStore en de motor, met een
// nagebootste Firebase (inloggen en Realtime Database) en een nagebootste live verbinding.
// De wachttijden (rustperiode, opnieuw verbinden, nieuwe poging) zijn kort gemaakt via `SyncTiming`, en de
// tijdstempels van de cloud zijn vaste datums. Een test wacht alleen tot iets waar wordt, met een ruime
// bovengrens; die grens speelt alleen mee als er iets misgaat.

private extension SyncTiming {
    /// Korte wachttijden voor tests.
    static var fast: SyncTiming {
        var timing = SyncTiming()
        timing.debouncer = SyncDebouncer(quietPeriod: 0.05, minimumInterval: 0.1, maximumWait: 0.5)
        timing.backoff = ReconnectBackoff(base: 0.05, maximum: 0.2)
        timing.retryAfterFailure = 0.3
        timing.pauseAfterStop = 0.3
        timing.rescheduleDelay = 0.05
        timing.restoreGrace = 0
        timing.pollInterval = 0.02
        return timing
    }
}

/// Nagebootste Firebase: inloggen, token verversen en de Realtime Database (met ETag en 412) in één.
private final class FakeFirebase: HTTPClient {
    private(set) var puts = 0
    private(set) var gets = 0
    private(set) var document: String?
    private var version = 0
    var offline = false
    var tokenRefreshFails = false
    var rejectedTokens: Set<String> = []

    private var etag: String { document == nil ? "null_etag" : "etag-\(version)" }

    func seed(_ finance: FinanceData, device: String = "ander apparaat") throws {
        let text = try FirebaseDatabaseClient.encodeFinance(finance)
        let stamp = finance.modifiedAt ?? Date()
        let envelope = CloudEnvelope(data: text, modifiedAt: CloudSync.milliseconds(stamp), device: device, schema: 1)
        document = String(data: try JSONEncoder().encode(envelope), encoding: .utf8)
        version += 1
    }

    /// De gegevens zijn uit de database verdwenen, zoals na het verwijderen van het account op een ander apparaat.
    func wipeDocument() {
        document = nil
        version += 1
    }

    func storedFinance() -> FinanceData? {
        guard let document, let bytes = document.data(using: .utf8),
              let reading = try? JSONDecoder().decode(CloudEnvelopeReading.self, from: bytes),
              let snapshot = RemoteSnapshot(reading: reading, etag: nil) else { return nil }
        return try? snapshot.decodeFinance()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await Task.yield()
        if offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        func reply(_ status: Int, _ body: String, etag: String? = nil) -> (Data, HTTPURLResponse) {
            var headers: [String: String] = [:]
            if let etag { headers["ETag"] = etag }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }

        switch url.host {
        case "identitytoolkit.googleapis.com":
            return reply(200, #"{"localId":"uid123","email":"jan@mail.nl","idToken":"tok-uid123","refreshToken":"refresh-1","expiresIn":"3600"}"#)
        case "securetoken.googleapis.com":
            if tokenRefreshFails { return reply(400, #"{"error":{"code":400,"message":"TOKEN_EXPIRED"}}"#) }
            return reply(200, #"{"id_token":"tok-uid123-v2","refresh_token":"refresh-1","user_id":"uid123","expires_in":"3600"}"#)
        default:
            break
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let token = components.queryItems?.first(where: { $0.name == "auth" })?.value ?? ""
        if rejectedTokens.contains(token) { return reply(401, #"{"error":"Auth token is expired"}"#) }
        guard token.hasPrefix("tok-uid123") else { return reply(401, #"{"error":"Permission denied"}"#) }

        switch request.httpMethod ?? "GET" {
        case "GET":
            gets += 1
            return reply(200, document ?? "null", etag: etag)
        case "PUT":
            if let ifMatch = request.value(forHTTPHeaderField: "if-match"), ifMatch != etag {
                return reply(412, document ?? "null", etag: etag)
            }
            puts += 1
            document = String(data: request.httpBody ?? Data(), encoding: .utf8)
            version += 1
            return reply(204, "", etag: etag)
        case "DELETE":
            document = nil
            version += 1
            return reply(200, "null")
        default:
            return reply(405, "{}")
        }
    }
}

/// Een nagebootste live verbinding: de test bepaalt wat er binnenkomt en wanneer de verbinding wegvalt.
private final class ScriptedStream: EventStreaming {
    private(set) var requests: [URLRequest] = []
    private var current: AsyncThrowingStream<Data, Error>.Continuation?

    func chunks(for request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            self.current = continuation
        }
    }

    func send(_ text: String) {
        current?.yield(Data(text.utf8))
    }

    func drop(_ error: Error? = nil) {
        current?.finish(throwing: error)
        current = nil
    }
}

@MainActor
final class SyncControllerTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var runTask: Task<Void, Never>?

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyBuddySyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "nl.mybuddy.tests.sync.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        addTeardownBlock { [directory, suite] in
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            if let directory { try? FileManager.default.removeItem(at: directory) }
        }
    }

    override func tearDown() async throws {
        runTask?.cancel()
        runTask = nil
    }

    // MARK: Hulpjes

    /// Vaste tijdstempels voor wat "in de cloud" staat (hele seconden, onafhankelijk van de klok).
    private let stampBase = Date(timeIntervalSince1970: 1_790_000_000)

    private func stamp(_ seconds: TimeInterval) -> Date {
        stampBase.addingTimeInterval(seconds)
    }

    private func finance(salary: Double, modified: Date? = nil) -> FinanceData {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 8))
        data.salary.fixedMonthly = salary
        data.modifiedAt = modified
        return data
    }

    private struct Setup {
        var firebase: FakeFirebase
        var stream: ScriptedStream
        var account: CloudAccount
        var store: AppStore
        var controller: SyncController
    }

    /// Een ingelogd account met een lege of gevulde winkel en een controller die nog niet draait.
    private func makeSetup(localSalary: Double? = nil, cloud: FinanceData? = nil, firebase existing: FakeFirebase? = nil) async throws -> Setup {
        let firebase = existing ?? FakeFirebase()
        if let cloud { try firebase.seed(cloud) }
        let account = CloudAccount(apiKey: "TEST-KEY",
                                   databaseURL: "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app",
                                   http: firebase,
                                   secrets: InMemorySecretStore(),
                                   directory: directory)
        try await account.signIn(email: "jan@mail.nl", password: "geheim12")
        let user = try XCTUnwrap(account.user)
        let store = AppStore(storage: FinanceStorage(url: account.storageURL(for: user)), quotes: DemoQuoteService())
        if let localSalary {
            store.mutate { $0.salary.fixedMonthly = localSalary }
        }
        let stream = ScriptedStream()
        let controller = SyncController(store: store, account: account, user: user, directory: directory,
                                        streamer: stream, timing: .fast, defaults: defaults)
        return Setup(firebase: firebase, stream: stream, account: account, store: store, controller: controller)
    }

    private func start(_ setup: Setup) {
        let controller = setup.controller
        runTask = Task { await controller.run() }
    }

    /// Wacht tot iets waar is (of de tijd om is) en laat de rest van de app intussen doorwerken.
    private func waitUntil(_ seconds: TimeInterval = 8, _ message: String = "", file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        XCTFail("Tijd om voordat dit waar werd: \(message)", file: file, line: line)
    }

    private func isSynced(_ controller: SyncController) -> Bool {
        if case .synced = controller.displayStatus { return true }
        return false
    }

    private func putEvent(_ firebase: FakeFirebase) -> String {
        "event: put\ndata: {\"path\":\"/\",\"data\":\(firebase.document ?? "null")}\n\n"
    }

    // MARK: Starten

    func testLocalDataIsUploadedAndTheLiveConnectionOpens() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)

        await waitUntil(8, "gesynchroniseerd en verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }

        XCTAssertEqual(setup.firebase.storedFinance()?.salary.fixedMonthly, 3100)
        let request = try XCTUnwrap(setup.stream.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.url?.path, "/users/uid123/finance.json")
        XCTAssertNotNil(setup.controller.lastSyncedAt)
        XCTAssertNil(setup.controller.conflict)
        XCTAssertEqual(setup.firebase.puts, 1)
    }

    func testNewDeviceDownloadsTheCloud() async throws {
        let setup = try await makeSetup(cloud: finance(salary: 4200, modified: stamp(-600)))
        start(setup)
        await waitUntil(8, "gegevens overgenomen") { setup.store.data.salary.fixedMonthly == 4200 }
        await waitUntil(8, "gesynchroniseerd") { isSynced(setup.controller) }
        XCTAssertEqual(setup.firebase.puts, 0, "Er hoeft niets geschreven te worden")
    }

    // MARK: Live wijzigingen

    func testChangeFromAnotherDeviceArrivesThroughTheLiveConnection() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }
        let putsBefore = setup.firebase.puts

        try setup.firebase.seed(finance(salary: 5555, modified: stamp(30)), device: "iPad (zz)")
        setup.stream.send(putEvent(setup.firebase))

        await waitUntil(8, "wijziging overgenomen") { setup.store.data.salary.fixedMonthly == 5555 }
        XCTAssertEqual(setup.firebase.puts, putsBefore, "Overnemen mag niets terugsturen")
    }

    func testKeepAliveAndPartialChangesAreHarmless() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }

        setup.stream.send("event: keep-alive\ndata: null\n\n")
        setup.stream.send(": commentaar\n\n")
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(setup.store.data.salary.fixedMonthly, 3100)
        XCTAssertEqual(setup.stream.requests.count, 1)
    }

    // MARK: Lokale wijzigingen

    func testLocalEditsAreSentAfterTheQuietPeriodInOneWrite() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }
        let putsBefore = setup.firebase.puts

        // Drie wijzigingen vlak na elkaar, zonder tussendoor te wachten: dat blijft binnen de rustperiode.
        for value in [3200.0, 3300.0, 3400.0] {
            setup.store.mutate { $0.salary.fixedMonthly = value }
        }
        XCTAssertEqual(setup.firebase.puts, putsBefore, "Binnen de rustperiode wordt nog niets verstuurd")

        await waitUntil(8, "wijziging in de cloud") { setup.firebase.storedFinance()?.salary.fixedMonthly == 3400 }
        XCTAssertEqual(setup.firebase.puts, putsBefore + 1, "Drie snelle wijzigingen zijn één schrijfactie")
        XCTAssertFalse(setup.controller.hasUnsyncedChanges)
    }

    func testEditsOfAnotherDeviceAreNotSentBack() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }
        try setup.firebase.seed(finance(salary: 6000, modified: stamp(60)), device: "iPad (zz)")
        setup.stream.send(putEvent(setup.firebase))
        await waitUntil(8, "overgenomen") { setup.store.data.salary.fixedMonthly == 6000 }
        let putsBefore = setup.firebase.puts
        // Ruim langer dan de rustperiode en de minimale tussentijd samen.
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(setup.firebase.puts, putsBefore)
    }

    // MARK: Conflicten

    func testConflictAtStartAsksAndKeepingLocalUploadsAndBacksUpTheCloudVersion() async throws {
        let setup = try await makeSetup(localSalary: 3000, cloud: finance(salary: 3900, modified: stamp(-300)))
        start(setup)

        await waitUntil(8, "conflict gemeld") { setup.controller.conflict != nil }
        XCTAssertEqual(setup.controller.displayStatus, .conflict)
        XCTAssertEqual(setup.controller.conflict?.remoteDevice, "ander apparaat")
        XCTAssertEqual(setup.firebase.puts, 0, "Bij een conflict wordt niets overschreven")
        XCTAssertEqual(setup.store.data.salary.fixedMonthly, 3000)

        await setup.controller.resolve(.keepLocal)

        XCTAssertNil(setup.controller.conflict)
        XCTAssertEqual(setup.firebase.storedFinance()?.salary.fixedMonthly, 3000)
        let backups = setup.controller.conflictBackups()
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?.side, .cloud)

        // De back-up is terug te zetten: de cloudversie komt weer als huidige gegevens.
        XCTAssertTrue(setup.controller.restoreBackup(try XCTUnwrap(backups.first)))
        XCTAssertEqual(setup.store.data.salary.fixedMonthly, 3900)
        XCTAssertEqual(setup.controller.conflictBackups().count, 2, "De gegevens van vlak ervoor zijn zelf een back-up geworden")
        await waitUntil(8, "teruggezette versie in de cloud") { setup.firebase.storedFinance()?.salary.fixedMonthly == 3900 }
    }

    func testTakingTheCloudVersionReplacesLocalData() async throws {
        let setup = try await makeSetup(localSalary: 3000, cloud: finance(salary: 3900, modified: stamp(-300)))
        start(setup)
        await waitUntil(8, "conflict gemeld") { setup.controller.conflict != nil }

        await setup.controller.resolve(.takeRemote)

        XCTAssertNil(setup.controller.conflict)
        XCTAssertEqual(setup.store.data.salary.fixedMonthly, 3900)
        XCTAssertEqual(setup.controller.conflictBackups().first?.side, .local)
        XCTAssertEqual(setup.firebase.puts, 0)
    }

    func testDeferringTheConflictPromptKeepsTheConflictOpen() async throws {
        let setup = try await makeSetup(localSalary: 3000, cloud: finance(salary: 3900, modified: stamp(-300)))
        start(setup)
        await waitUntil(8, "conflict gemeld") { setup.controller.conflict != nil }
        XCTAssertFalse(setup.controller.conflictPromptDeferred)
        setup.controller.deferConflictPrompt()
        XCTAssertTrue(setup.controller.conflictPromptDeferred)
        XCTAssertNotNil(setup.controller.conflict)
        XCTAssertEqual(setup.controller.displayStatus, .conflict)
    }

    // MARK: Lokale gegevens meenemen

    func testLocalAccountDataIsOfferedAndUploadedWhenAccepted() async throws {
        // Een bestand van een lokaal account (finance-<UUID>.json) staat klaar op het apparaat.
        let localFile = directory.appendingPathComponent("finance-\(UUID().uuidString).json")
        try FinanceStorage(url: localFile).save(finance(salary: 2800, modified: stamp(-86_400)))

        let setup = try await makeSetup()
        start(setup)
        await waitUntil(8, "aanbod") { setup.controller.importOffer != nil }
        XCTAssertEqual(setup.controller.importOffer?.data.salary.fixedMonthly, 2800)
        XCTAssertEqual(setup.firebase.puts, 0, "Eerst vragen, dan pas uploaden")

        setup.controller.answerImportOffer(accept: true)

        XCTAssertNil(setup.controller.importOffer)
        XCTAssertEqual(setup.store.data.salary.fixedMonthly, 2800)
        await waitUntil(8, "geüpload") { setup.firebase.storedFinance()?.salary.fixedMonthly == 2800 }
    }

    func testDecliningTheOfferStartsWithTheCloudAndAsksOnlyOnce() async throws {
        let localFile = directory.appendingPathComponent("finance.json")
        try FinanceStorage(url: localFile).save(finance(salary: 2800, modified: stamp(-86_400)))

        let setup = try await makeSetup(cloud: finance(salary: 4400, modified: stamp(-600)))
        start(setup)
        await waitUntil(8, "aanbod") { setup.controller.importOffer != nil }
        setup.controller.answerImportOffer(accept: false)
        await waitUntil(8, "cloud overgenomen") { setup.store.data.salary.fixedMonthly == 4400 }
        XCTAssertEqual(setup.firebase.puts, 0)

        // Een volgende keer (nieuwe sessie op hetzelfde apparaat) wordt er niet meer gevraagd.
        runTask?.cancel()
        runTask = nil
        let again = try await makeSetup(firebase: setup.firebase)
        start(again)
        await waitUntil(8, "gesynchroniseerd") { isSynced(again.controller) }
        XCTAssertNil(again.controller.importOffer)
    }

    func testNoOfferWhenThereIsNothingLocal() async throws {
        let setup = try await makeSetup(cloud: finance(salary: 4400, modified: stamp(-600)))
        start(setup)
        await waitUntil(8, "gesynchroniseerd") { isSynced(setup.controller) }
        XCTAssertNil(setup.controller.importOffer)
    }

    // MARK: Verbinding

    func testDroppedConnectionReconnectsAndCatchesUp() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }

        // De verbinding valt weg, intussen verandert er iets in de cloud.
        setup.stream.drop()
        try setup.firebase.seed(finance(salary: 7777, modified: stamp(60)), device: "iPad (zz)")

        await waitUntil(8, "opnieuw verbonden en ingehaald") { setup.stream.requests.count == 2 && setup.store.data.salary.fixedMonthly == 7777 }
    }

    func testAuthRevokedMessageReconnectsWithAFreshToken() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }
        setup.stream.send("event: auth_revoked\ndata: \"credential is no longer valid\"\n\n")
        await waitUntil(8, "opnieuw verbonden") { setup.stream.requests.count == 2 }
    }

    func testComingBackFromTheBackgroundReconnects() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }

        setup.controller.appMovedToBackground()
        setup.controller.appBecameActive()

        await waitUntil(8, "opnieuw verbonden") { setup.stream.requests.count == 2 }
    }

    func testBecomingActiveWithoutHavingBeenInTheBackgroundKeepsTheConnection() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }
        setup.controller.appBecameActive()
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(setup.stream.requests.count, 1)
    }

    func testStartingWithoutInternetShowsOfflineAndCatchesUpWhenSyncingAgain() async throws {
        let firebase = FakeFirebase()
        let setup = try await makeSetup(localSalary: 3100, firebase: firebase)
        firebase.offline = true
        start(setup)
        await waitUntil(8, "offline") { setup.controller.displayStatus == .offline }
        XCTAssertEqual(setup.store.data.salary.fixedMonthly, 3100, "Lokaal werkt alles gewoon")

        setup.store.mutate { $0.salary.fixedMonthly = 3150 }
        firebase.offline = false
        await setup.controller.syncNow()

        await waitUntil(8, "ingehaald") { firebase.storedFinance()?.salary.fixedMonthly == 3150 }
        await waitUntil(8, "gesynchroniseerd") { isSynced(setup.controller) }
    }

    // MARK: Sessie

    func testRejectedSessionSignsTheUserOutAndKeepsTheLocalFile() async throws {
        let firebase = FakeFirebase()
        let setup = try await makeSetup(localSalary: 3100, firebase: firebase)
        let file = setup.account.storageURL(for: try XCTUnwrap(setup.account.user))
        firebase.rejectedTokens = ["tok-uid123"]
        firebase.tokenRefreshFails = true
        start(setup)

        await waitUntil(8, "uitgelogd") { setup.account.user == nil }
        XCTAssertNotNil(setup.account.notice)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "De gegevens op het apparaat blijven staan")
    }

    func testDataVanishingBecauseTheAccountWasDeletedElsewhereIsNotWrittenBack() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }
        let putsBefore = setup.firebase.puts

        // Een ander apparaat verwijdert het account: de gegevens zijn weg en het token wordt niet meer vernieuwd.
        setup.firebase.wipeDocument()
        setup.firebase.tokenRefreshFails = true
        setup.stream.send(putEvent(setup.firebase))

        await waitUntil(8, "uitgelogd") { setup.account.user == nil }
        XCTAssertNotNil(setup.account.notice)
        XCTAssertEqual(setup.firebase.puts, putsBefore, "Er worden geen gegevens van een verwijderd account teruggezet")
        XCTAssertNil(setup.firebase.document)
    }

    func testDataVanishingWhileTheAccountStillExistsIsRestored() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }

        setup.firebase.wipeDocument()
        setup.stream.send(putEvent(setup.firebase))

        await waitUntil(8, "teruggezet") { setup.firebase.storedFinance()?.salary.fixedMonthly == 3100 }
        XCTAssertNotNil(setup.account.user)
    }

    func testDeletingTheAccountRemovesCloudDataAndLocalFiles() async throws {
        let firebase = FakeFirebase()
        let setup = try await makeSetup(localSalary: 3100, firebase: firebase)
        let user = try XCTUnwrap(setup.account.user)
        start(setup)
        await waitUntil(8, "geüpload") { firebase.storedFinance()?.salary.fixedMonthly == 3100 }
        runTask?.cancel()
        runTask = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.account.storageURL(for: user).path))

        try await setup.account.deleteAccount(password: "geheim12")

        XCTAssertNil(firebase.document)
        XCTAssertNil(setup.account.user)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.account.storageURL(for: user).path))
    }

    func testSignOutWhileRunningStopsTheLoopWithoutErrors() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }
        setup.account.signOut()
        runTask?.cancel()
        await runTask?.value
        XCTAssertNil(setup.account.user)
        XCTAssertNil(setup.store.onDataChanged, "De koppeling met de winkel is opgeruimd")
    }

    // MARK: Gegevens vervangen

    func testReplacingAllDataNeedsAMarkToBeSynced() async throws {
        let setup = try await makeSetup(localSalary: 3100)
        start(setup)
        await waitUntil(8, "verbonden") { isSynced(setup.controller) && setup.stream.requests.count == 1 }

        // Zoals "Alles wissen" of een back-up terugzetten: de winkel past zijn gegevens aan zonder wijzigingstijd.
        setup.store.eraseEverything()
        setup.store.markChangedForSync()

        await waitUntil(8, "lege gegevens in de cloud") {
            guard let stored = setup.firebase.storedFinance() else { return false }
            return stored.salary.fixedMonthly == 0
        }
    }
}
