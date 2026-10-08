import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MyBuddyCore

/// Een nagebootst apparaat: eigen gegevens, eigen klok, eigen staat en een eigen synchronisatiemotor,
/// samen met anderen aan één nagebootste database.
final class SimulatedDevice {
    let name: String
    var data: FinanceData
    let clock: CloudTestClock
    let stateStore: MemorySyncStateStore
    let backupDirectory: URL
    var applied: [FinanceData] = []
    var stampCalls = 0
    var tokenCalls: [Bool] = []
    var token = "tok-uid123"
    var refreshedToken = "tok-uid123-v2"
    var tokenFailure: Error?
    /// Alleen het vernieuwen van het token mislukt (bijvoorbeeld omdat het account is verwijderd).
    var forceRefreshFailure: Error?
    var changeNotifications = 0
    var engine: CloudSyncEngine!

    init(name: String, data: FinanceData, clock: CloudTestClock, state: SyncState, backupDirectory: URL) {
        self.name = name
        self.data = data
        self.clock = clock
        self.stateStore = MemorySyncStateStore(state)
        self.backupDirectory = backupDirectory
    }

    var deviceName: String { "\(name) (t1)" }
    var backups: ConflictBackupStore { ConflictBackupStore(directory: backupDirectory, uid: "uid123") }
}

@MainActor
final class CloudSyncEngineTests: XCTestCase {
    private let base = URL(string: "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app")!

    // MARK: Hulpjes

    private func makeDevice(_ name: String, db: FakeRealtimeDatabase, data: FinanceData,
                            clockAt: TimeInterval = 1000, state: SyncState = SyncState(),
                            backupDirectory: URL? = nil) throws -> SimulatedDevice {
        let directory = try backupDirectory ?? cloudTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let device = SimulatedDevice(name: name, data: data, clock: CloudTestClock(cloudAt(clockAt)),
                                     state: state, backupDirectory: directory)
        let tokens = CloudTokenSource(uid: "uid123") { force in
            device.tokenCalls.append(force)
            if let failure = device.tokenFailure { throw failure }
            if force, let failure = device.forceRefreshFailure { throw failure }
            if force { device.token = device.refreshedToken }
            return device.token
        }
        let local = SyncLocalAccess(
            read: { device.data },
            apply: { incoming in
                device.data = incoming
                device.applied.append(incoming)
            },
            stamp: { date in
                device.stampCalls += 1
                device.data.modifiedAt = date
            })
        device.engine = CloudSyncEngine(tokens: tokens,
                                        database: FirebaseDatabaseClient(baseURL: base, http: db),
                                        local: local,
                                        stateStore: device.stateStore,
                                        backups: ConflictBackupStore(directory: directory, uid: "uid123"),
                                        device: device.deviceName,
                                        restoreGrace: 0,
                                        clock: { device.clock.now })
        device.engine.onChange = { device.changeNotifications += 1 }
        return device
    }

    /// De gebruiker wijzigt iets (het salaris) op een bepaald moment.
    private func edit(_ device: SimulatedDevice, salary: Double, at seconds: TimeInterval) {
        device.clock.now = cloudAt(seconds)
        device.data.salary.fixedMonthly = salary
        device.data.modifiedAt = device.clock.now
        device.engine.localDidChange()
    }

    /// Zoals een bericht uit de stroom: het hele document, zonder ETag.
    private func streamSnapshot(_ db: FakeRealtimeDatabase) throws -> RemoteSnapshot {
        var snapshot = try XCTUnwrap(db.currentSnapshot())
        snapshot.etag = nil
        return snapshot
    }

    private func syncedState(stamp: TimeInterval) -> SyncState {
        SyncState(lastSyncedStamp: cloudAt(stamp), lastSyncedAt: cloudAt(stamp + 1))
    }

    // MARK: Eerste keer

    func testFirstLoginUploadsExistingLocalDataToAnEmptyCloud() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))

        let outcome = await a.engine.syncNow()

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.methods(), ["GET", "PUT"])
        XCTAssertEqual(db.log[1].headers["if-match"], "null_etag", "Alleen aanmaken als er nog niets staat")
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
        XCTAssertEqual(db.currentSnapshot()?.device, "iPhone (t1)")
        XCTAssertEqual(a.engine.status, .synced(at: a.clock.now))
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, cloudAt(500))
        XCTAssertEqual(a.stateStore.state.lastSyncedAt, a.clock.now)
        XCTAssertTrue(a.engine.isReady)
        XCTAssertEqual(a.engine.lastSyncedAt, a.clock.now)
        XCTAssertEqual(a.stampCalls, 0)
        XCTAssertTrue(a.applied.isEmpty)
        XCTAssertGreaterThan(a.changeNotifications, 0)
    }

    func testFirstLoginOnANewDeviceDownloadsTheCloud() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance(salary: 4100, modified: cloudAt(300)), device: "iPad (zz)")
        let b = try makeDevice("Mac", db: db, data: cloudPristine())

        let outcome = await b.engine.syncNow()

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.methods(), ["GET"], "Er hoeft niets geschreven te worden")
        XCTAssertEqual(b.applied.count, 1)
        XCTAssertEqual(b.data.salary.fixedMonthly, 4100)
        XCTAssertEqual(b.stateStore.state.lastSyncedStamp, cloudAt(300))
        XCTAssertEqual(b.engine.status, .synced(at: b.clock.now))
    }

    func testNothingToDoWhenBothAreEmpty() async throws {
        let db = FakeRealtimeDatabase()
        let c = try makeDevice("iPhone", db: db, data: cloudPristine())
        let outcome = await c.engine.syncNow()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.methods(), ["GET"])
        XCTAssertNil(db.document)
        XCTAssertTrue(c.engine.isReady)
        XCTAssertEqual(c.stateStore.state.lastSyncedStamp, nil)
    }

    func testSecondSyncWithoutChangesOnlyReads() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        await a.engine.syncNow()
        a.clock.advance(60)
        let outcome = await a.engine.syncNow()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.methods(), ["GET", "PUT", "GET"])
        XCTAssertEqual(a.engine.status, .synced(at: a.clock.now))
        XCTAssertTrue(a.applied.isEmpty)
    }

    func testRestartedAppRecognisesItsOwnVersion() async throws {
        // Na het herstarten staat de wijzigingstijd op de seconde afgerond in het bestand, de staat heeft de milliseconden.
        let db = FakeRealtimeDatabase()
        let precise = cloudAt(500.7)
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: precise))
        await a.engine.syncNow()
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, Date(timeIntervalSince1970: (precise.timeIntervalSince1970 * 1000).rounded() / 1000))

        let restarted = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)), state: a.stateStore.state)
        let before = db.log.count
        let outcome = await restarted.engine.syncNow()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.log.count - before, 1, "Alleen lezen: er is niets veranderd")
        XCTAssertTrue(restarted.applied.isEmpty)
    }

    // MARK: Wijzigingen wegschrijven

    func testEditAfterSyncIsPushedInOneRequestWithTheKnownETag() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        XCTAssertEqual(db.log.count, 2)

        edit(a, salary: 3200, at: 560)
        XCTAssertTrue(a.engine.hasUnsyncedChanges)
        let outcome = await a.engine.pushIfNeeded()

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.methods(), ["GET", "PUT", "PUT"], "Met een bekende ETag is vooraf lezen niet nodig")
        XCTAssertEqual(db.log[2].headers["if-match"], "etag-1")
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3200)
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, cloudAt(560))
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertEqual(a.engine.status, .synced(at: cloudAt(560)))
    }

    func testPushWithoutAKnownETagReadsFirst() async throws {
        let db = FakeRealtimeDatabase()
        db.sendsETagOnWrite = false
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        edit(a, salary: 3200, at: 560)
        await a.engine.pushIfNeeded()
        XCTAssertEqual(db.methods(), ["GET", "PUT", "GET", "PUT"])
        XCTAssertEqual(db.log[3].headers["if-match"], "etag-1")
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3200)
    }

    func testPushIfNeededDoesNothingWhenNothingChanged() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        await a.engine.syncNow()
        let before = db.log.count
        let outcome = await a.engine.pushIfNeeded()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.log.count, before)
    }

    func testNothingIsWrittenBeforeTheFirstSuccessfulComparison() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        edit(a, salary: 3300, at: 600)
        XCTAssertFalse(a.engine.isReady)
        XCTAssertNil(a.engine.secondsUntilPush())
        let outcome = await a.engine.pushIfNeeded()
        XCTAssertEqual(outcome, .done)
        XCTAssertTrue(db.log.isEmpty)
    }

    func testDelayUntilPushFollowsTheDebounceRules() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)), clockAt: 400)
        await a.engine.syncNow()
        XCTAssertNil(a.engine.secondsUntilPush(), "Er is nog niets gewijzigd")

        edit(a, salary: 1, at: 600)
        XCTAssertEqual(a.engine.secondsUntilPush() ?? -1, 1.5, accuracy: 0.001)
        a.clock.advance(1)
        XCTAssertEqual(a.engine.secondsUntilPush() ?? -1, 0.5, accuracy: 0.001)
        a.clock.advance(1)
        XCTAssertEqual(a.engine.secondsUntilPush() ?? -1, 0, accuracy: 0.001)

        await a.engine.pushIfNeeded()
        XCTAssertNil(a.engine.secondsUntilPush())

        // Direct daarna weer wijzigen: hoogstens elke 5 seconden schrijven.
        edit(a, salary: 2, at: 602)
        XCTAssertEqual(a.engine.secondsUntilPush() ?? -1, 5, accuracy: 0.001)
    }

    func testChangesMadeWhileWritingStayPending() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 1000, modified: cloudAt(500)))
        await a.engine.syncNow()

        edit(a, salary: 1100, at: 600)
        db.beforeWrite = { [unowned self] in
            // Midden in het schrijven past de gebruiker nog iets aan.
            self.edit(a, salary: 1200, at: 603)
            db.beforeWrite = nil
        }
        await a.engine.pushIfNeeded()

        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 1100, "De versie van vóór de wijziging staat in de cloud")
        XCTAssertTrue(a.engine.hasUnsyncedChanges)
        XCTAssertNotNil(a.engine.secondsUntilPush(), "De nieuwe wijziging wacht op haar eigen schrijfactie")

        a.clock.advance(10)
        await a.engine.pushIfNeeded()
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 1200)
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
    }

    func testAnEditJustAfterTheLastSyncedVersionIsStillSent() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()
        XCTAssertFalse(a.engine.hasUnsyncedChanges)

        // Een halve seconde na de gesynchroniseerde versie: dichterbij dan de afronding op de seconde.
        a.data.salary.fixedMonthly = 3050
        a.data.modifiedAt = cloudAt(500.5)
        a.engine.localDidChange()
        XCTAssertTrue(a.engine.hasUnsyncedChanges)
        await a.engine.pushIfNeeded()

        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3050)
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertFalse(a.stateStore.state.dirty)
    }

    func testWaitingChangeIsForgottenWhenThereTurnsOutToBeNothingToSend() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()

        // Er is een wijziging gemeld, maar daarna blijkt de cloud precies dezelfde inhoud te hebben (andere tijd).
        a.engine.localDidChange()
        let same = try RemoteSnapshot(finance: cloudFinance(salary: 3000, modified: cloudAt(520)), device: "ander apparaat")
        let action = await a.engine.receive(.snapshot(same))
        XCTAssertEqual(action, .keepListening)
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertNotNil(a.engine.secondsUntilPush(), "De planning weet nog van de melding")

        // Het wegschrijven ziet dat er niets te doen is en vergeet de planning, in plaats van eindeloos terug te komen.
        let before = db.log.count
        let outcome = await a.engine.pushIfNeeded()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.log.count, before)
        XCTAssertNil(a.engine.secondsUntilPush())
    }

    func testWritingClearsThePlanningSoItDoesNotLoop() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 600)
        XCTAssertNotNil(a.engine.secondsUntilPush())
        await a.engine.pushIfNeeded()
        XCTAssertNil(a.engine.secondsUntilPush())
        let before = db.log.count
        await a.engine.pushIfNeeded()
        XCTAssertEqual(db.log.count, before)
    }

    func testUnsyncedChangeIsRememberedAcrossARestart() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()

        // De gebruiker wijzigt iets en sluit de app voordat het is verstuurd. De wijziging heeft (door een afwijkende klok)
        // dezelfde tijd als de gesynchroniseerde versie; alleen de bewaarde markering verraadt hem.
        a.data.salary.fixedMonthly = 3111
        a.engine.localDidChange()
        XCTAssertTrue(a.stateStore.state.dirty)

        let restarted = try makeDevice("iPhone", db: db, data: a.data, clockAt: 600, state: a.stateStore.load())
        XCTAssertTrue(restarted.engine.hasUnsyncedChanges)
        let outcome = await restarted.engine.syncNow()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3111)
        XCTAssertFalse(restarted.stateStore.state.dirty)
    }

    func testChangeDuringAWriteStaysMarkedAsUnsynced() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 1000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()
        edit(a, salary: 1100, at: 600)
        db.beforeWrite = { [unowned self] in
            self.edit(a, salary: 1200, at: 603)
            db.beforeWrite = nil
        }
        await a.engine.pushIfNeeded()
        XCTAssertTrue(a.stateStore.state.dirty, "De wijziging tijdens het schrijven is nog niet verstuurd")
        a.clock.advance(10)
        await a.engine.pushIfNeeded()
        XCTAssertFalse(a.stateStore.state.dirty)
    }

    func testStatusIsBusyWhileWriting() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        var seen: [SyncStatus] = []
        db.beforeWrite = { [unowned a] in seen.append(a.engine.status) }
        await a.engine.syncNow()
        XCTAssertEqual(seen, [.busy])
    }

    func testLegacyDataWithoutTimestampGetsOneBeforeUploading() async throws {
        let db = FakeRealtimeDatabase()
        var legacy = cloudFinance(salary: 2000)
        legacy.modifiedAt = nil
        let a = try makeDevice("iPhone", db: db, data: legacy, clockAt: 800)

        await a.engine.syncNow()

        XCTAssertEqual(a.stampCalls, 1)
        XCTAssertEqual(a.data.modifiedAt, cloudAt(800))
        XCTAssertEqual(db.currentSnapshot()?.modifiedAt, cloudAt(800))
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, cloudAt(800))

        // Daarna is er niets meer te doen.
        await a.engine.syncNow()
        XCTAssertEqual(db.methods(), ["GET", "PUT", "GET"])
        XCTAssertEqual(a.stampCalls, 1)
    }

    // MARK: Berichten van andere apparaten

    func testChangeFromAnotherDeviceIsAppliedWithoutSendingItBack() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        try db.seed(cloudFinance(salary: 3600, modified: cloudAt(700)), device: "iPad (zz)")
        let before = db.log.count

        let action = await a.engine.receive(.snapshot(try streamSnapshot(db)))

        XCTAssertEqual(action, .keepListening)
        XCTAssertEqual(a.applied.count, 1)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3600)
        XCTAssertEqual(db.log.count, before, "Overnemen vraagt geen verzoeken en schrijft niets terug")
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, cloudAt(700))
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertNil(a.engine.secondsUntilPush())
    }

    func testEchoOfOurOwnWriteIsIgnored() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 600)
        await a.engine.pushIfNeeded()
        let before = db.log.count

        let action = await a.engine.receive(.snapshot(try streamSnapshot(db)))

        XCTAssertEqual(action, .keepListening)
        XCTAssertEqual(db.log.count, before)
        XCTAssertTrue(a.applied.isEmpty)
    }

    func testEchoThatArrivesBeforeTheWriteIsAnsweredIsIgnoredToo() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 600)

        // Het bericht van de database kan sneller zijn dan het antwoord op het schrijven zelf.
        let echo = RemoteSnapshot(json: "{}", modifiedAt: cloudAt(600), device: a.deviceName)
        var echoTask: Task<StreamAction, Never>?
        db.beforeWrite = { [unowned a] in
            echoTask = Task { @MainActor in await a.engine.receive(.snapshot(echo)) }
            db.beforeWrite = nil
        }
        let outcome = await a.engine.pushIfNeeded()
        let action = await echoTask?.value

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(action, .keepListening)
        XCTAssertEqual(db.methods(), ["GET", "PUT", "PUT"], "Geen extra ophaalronde door het echo")
        XCTAssertTrue(a.applied.isEmpty)
    }

    func testUpdateFromAnotherDeviceDuringAnActiveWriteIsPickedUpAfterwards() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 600)

        let foreign = RemoteSnapshot(json: "{}", modifiedAt: cloudAt(650), device: "iPad (zz)")
        var foreignTask: Task<StreamAction, Never>?
        db.beforeWrite = { [unowned a] in
            foreignTask = Task { @MainActor in await a.engine.receive(.snapshot(foreign)) }
            db.beforeWrite = nil
        }
        let outcome = await a.engine.pushIfNeeded()
        let action = await foreignTask?.value

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(action, .keepListening, "Tijdens een lopende actie wacht het bericht op een volgende ronde")
        // Na het schrijven volgt een volledige ronde, die de cloud als bron neemt (hier: ons eigen schrijven).
        XCTAssertEqual(db.methods(), ["GET", "PUT", "PUT", "GET"])
        XCTAssertEqual(a.engine.status, .synced(at: a.clock.now))
    }

    func testTwoDevicesStayInSync() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(100)), clockAt: 100)
        let b = try makeDevice("iPad", db: db, data: cloudPristine(), clockAt: 150)

        await a.engine.syncNow()                      // A zet zijn gegevens in de cloud
        await b.engine.syncNow()                      // B haalt ze op
        XCTAssertEqual(b.data.salary.fixedMonthly, 3000)

        edit(b, salary: 3500, at: 200)                // B wijzigt
        await b.engine.pushIfNeeded()
        let toA = await a.engine.receive(.snapshot(try streamSnapshot(db)))
        XCTAssertEqual(toA, .keepListening)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3500)

        edit(a, salary: 3800, at: 300)                // A wijzigt weer
        await a.engine.pushIfNeeded()
        let toB = await b.engine.receive(.snapshot(try streamSnapshot(db)))
        XCTAssertEqual(toB, .keepListening)
        XCTAssertEqual(b.data.salary.fixedMonthly, 3800)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3800)

        // Niemand heeft nog openstaande wijzigingen.
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertFalse(b.engine.hasUnsyncedChanges)
        XCTAssertNil(a.engine.conflict)
        XCTAssertNil(b.engine.conflict)
    }

    func testDeviceWithASlowClockDoesNotLoseItsEdit() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(5000)), clockAt: 5000)
        let b = try makeDevice("iPad", db: db, data: cloudPristine(), clockAt: 3200)   // loopt een half uur achter
        await a.engine.syncNow()
        await b.engine.syncNow()

        edit(b, salary: 3999, at: 3300)               // tijd 3300 < 5000 van de versie die B net kreeg
        XCTAssertTrue(b.engine.hasUnsyncedChanges)
        await b.engine.pushIfNeeded()
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3999)

        let action = await a.engine.receive(.snapshot(try streamSnapshot(db)))
        XCTAssertEqual(action, .keepListening)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3999, "De nieuwste wijziging wint, ook met een afwijkende klok")
    }

    func testWipeOnOneDeviceReachesTheOther() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(100)), clockAt: 100)
        let b = try makeDevice("iPad", db: db, data: cloudPristine(), clockAt: 150)
        await a.engine.syncNow()
        await b.engine.syncNow()

        // A maakt alles leeg (de app geeft dit een wijzigingstijd).
        a.clock.now = cloudAt(400)
        a.data = cloudPristine()
        a.data.modifiedAt = a.clock.now
        a.engine.localDidChange()
        await a.engine.pushIfNeeded()

        await b.engine.receive(.snapshot(try streamSnapshot(db)))
        XCTAssertFalse(CloudSync.hasContent(b.data))
        XCTAssertEqual(b.applied.count, 2)
    }

    func testCloudDocumentDeletedElsewhereIsRestoredFromLocalData() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        db.seedRaw(nil)

        let action = await a.engine.receive(.snapshot(nil))

        XCTAssertEqual(action, .keepListening)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
        XCTAssertEqual(db.log.last?.headers["if-match"], "null_etag")
    }

    func testStreamMessagesThatNeedNoActionAreIgnored() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        await a.engine.syncNow()
        let before = db.log.count

        let keepAlive = await a.engine.receive(.keepAlive)
        let unknown = await a.engine.receive(.unknown("x"))
        XCTAssertEqual(keepAlive, .keepListening)
        XCTAssertEqual(unknown, .keepListening)
        let revoked = await a.engine.receive(.authRevoked)
        XCTAssertEqual(revoked, .reconnect)
        XCTAssertEqual(db.log.count, before)
    }

    func testCancelMessageStopsListeningWithAnExplanation() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        await a.engine.syncNow()
        let action = await a.engine.receive(.cancel)
        guard case .stop(let text) = action else { return XCTFail("Verwachtte stop, kreeg \(action)") }
        XCTAssertTrue(text.contains("database.rules.json"))
        XCTAssertEqual(a.engine.status, .failed(text))
    }

    func testPartialChangeTriggersAFullRead() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        try db.seed(cloudFinance(salary: 4400, modified: cloudAt(900)), device: "iPad (zz)")
        let action = await a.engine.receive(.partialChange)
        XCTAssertEqual(action, .keepListening)
        XCTAssertEqual(db.methods().suffix(1), ["GET"])
        XCTAssertEqual(a.data.salary.fixedMonthly, 4400)
    }

    func testSnapshotBeforeTheFirstComparisonIsLeftToTheInitialSync() async throws {
        let db = FakeRealtimeDatabase()
        try db.seed(cloudFinance(salary: 4400, modified: cloudAt(900)))
        let a = try makeDevice("iPhone", db: db, data: cloudPristine())
        let action = await a.engine.receive(.snapshot(try streamSnapshot(db)))
        XCTAssertEqual(action, .keepListening)
        XCTAssertTrue(a.applied.isEmpty)
        XCTAssertTrue(db.log.isEmpty)
    }

    func testOverlappingSyncsAreSerialised() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        async let first = a.engine.syncNow()
        async let second = a.engine.syncNow()
        let results = await (first, second)
        XCTAssertEqual(results.0, .done)
        XCTAssertEqual(results.1, .done)
        XCTAssertEqual(db.count("PUT"), 1)
        XCTAssertEqual(db.methods(), ["GET", "PUT", "GET"])
    }

    // MARK: Conflicten

    private func makeConflict(_ db: FakeRealtimeDatabase) throws -> SimulatedDevice {
        try db.seed(cloudFinance(salary: 3500, modified: cloudAt(200)), device: "iPad (zz)")
        return try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(100)), clockAt: 1000)
    }

    func testBothFilledAndDifferentAsksTheUser() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeConflict(db)

        let outcome = await a.engine.syncNow()

        XCTAssertEqual(outcome, .conflict)
        XCTAssertEqual(a.engine.status, .conflict)
        XCTAssertEqual(db.methods(), ["GET"], "Bij een conflict wordt niets overschreven")
        let conflict = try XCTUnwrap(a.engine.conflict)
        XCTAssertEqual(conflict.localModified, cloudAt(100))
        XCTAssertEqual(conflict.remoteModified, cloudAt(200))
        XCTAssertEqual(conflict.remoteDevice, "iPad (zz)")
        XCTAssertEqual(conflict.local.salary.fixedMonthly, 3000)
        XCTAssertEqual(try conflict.remote.decodeFinance().salary.fixedMonthly, 3500)
        XCTAssertEqual(conflict.newerSide, .remote, "100 seconden verschil is groter dan de klokscheefheid")
        XCTAssertTrue(a.applied.isEmpty)
        XCTAssertTrue(a.engine.isReady)
        XCTAssertNil(a.engine.secondsUntilPush(), "Zolang het conflict openstaat wordt er niet geschreven")
    }

    func testKeepingTheLocalVersionBacksUpTheCloudVersionAndUploads() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeConflict(db)
        await a.engine.syncNow()

        let outcome = await a.engine.resolve(.keepLocal)

        XCTAssertEqual(outcome, .done)
        XCTAssertNil(a.engine.conflict)
        XCTAssertEqual(a.engine.status, .synced(at: a.clock.now))
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
        XCTAssertEqual(db.log.last?.headers["if-match"], "etag-1", "Alleen overschrijven wat we zagen en bewaarden")
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, cloudAt(100))

        let saved = a.backups.backups(side: .cloud)
        XCTAssertEqual(saved.count, 1)
        guard case .loaded(let backup) = FinanceStorage(url: saved[0]).load() else { return XCTFail("Back-up hoort te laden") }
        XCTAssertEqual(backup.salary.fixedMonthly, 3500)
        XCTAssertTrue(a.backups.backups(side: .local).isEmpty)
    }

    func testTakingTheCloudVersionBacksUpTheLocalVersionAndReplacesIt() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeConflict(db)
        await a.engine.syncNow()

        let outcome = await a.engine.resolve(.takeRemote)

        XCTAssertEqual(outcome, .done)
        XCTAssertNil(a.engine.conflict)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3500)
        XCTAssertEqual(a.applied.count, 1)
        XCTAssertEqual(db.methods(), ["GET"], "Er wordt niets geschreven")
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, cloudAt(200))

        let saved = a.backups.backups(side: .local)
        XCTAssertEqual(saved.count, 1)
        guard case .loaded(let backup) = FinanceStorage(url: saved[0]).load() else { return XCTFail("Back-up hoort te laden") }
        XCTAssertEqual(backup.salary.fixedMonthly, 3000)
        XCTAssertEqual(a.engine.status, .synced(at: a.clock.now))
    }

    func testTakingTheCloudVersionWorksWithoutInternet() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeConflict(db)
        await a.engine.syncNow()
        db.offline = true
        let outcome = await a.engine.resolve(.takeRemote)
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3500)
    }

    func testKeepingLocalWhileOfflineKeepsTheConflictOpen() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeConflict(db)
        await a.engine.syncNow()
        db.offline = true

        let outcome = await a.engine.resolve(.keepLocal)

        XCTAssertEqual(outcome, .offline)
        XCTAssertNotNil(a.engine.conflict, "De keuze kan later nog gemaakt worden")
        XCTAssertEqual(a.engine.status, .offline)
        db.offline = false
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3500)
        let again = await a.engine.resolve(.keepLocal)
        XCTAssertEqual(again, .done)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
    }

    func testKeepingLocalAlsoBacksUpACloudVersionThatChangedInTheMeantime() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeConflict(db)
        await a.engine.syncNow()

        db.beforeWrite = {
            try? db.seed(cloudFinance(salary: 3900, modified: cloudAt(250)), device: "Mac (qq)")
            db.beforeWrite = nil
        }
        let outcome = await a.engine.resolve(.keepLocal)

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
        let salaries = a.backups.backups(side: .cloud).compactMap { url -> Double? in
            guard case .loaded(let data) = FinanceStorage(url: url).load() else { return nil }
            return data.salary.fixedMonthly
        }
        XCTAssertEqual(Set(salaries), [3500, 3900], "Beide cloudversies zijn bewaard")
    }

    func testNothingIsOverwrittenWhenTheBackupFails() async throws {
        let db = FakeRealtimeDatabase()
        // Een "map" die in werkelijkheid een bestand is: schrijven mislukt.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        try db.seed(cloudFinance(salary: 3500, modified: cloudAt(200)))
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(100)), backupDirectory: blocker)
        await a.engine.syncNow()
        XCTAssertNotNil(a.engine.conflict)

        let keep = await a.engine.resolve(.keepLocal)
        guard case .failed(let text) = keep else { return XCTFail("Verwachtte een fout, kreeg \(keep)") }
        XCTAssertTrue(text.contains("back-up"))
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3500)

        let take = await a.engine.resolve(.takeRemote)
        XCTAssertEqual(take.isFailure, true)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3000)
        XCTAssertNotNil(a.engine.conflict, "Het conflict blijft openstaan")
    }

    func testResolveWithoutConflictDoesNothing() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        let outcome = await a.engine.resolve(.keepLocal)
        XCTAssertEqual(outcome, .done)
        XCTAssertTrue(db.log.isEmpty)
    }

    func testWriteRaceLeadsToANewDecisionNotToOverwriting() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(100)), clockAt: 100)
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 200)

        // Vlak voor ons schrijven schrijft een ander apparaat zijn eigen wijziging.
        db.beforeWrite = {
            try? db.seed(cloudFinance(salary: 3700, modified: cloudAt(250)), device: "iPad (zz)")
            db.beforeWrite = nil
        }
        let outcome = await a.engine.pushIfNeeded()

        XCTAssertEqual(outcome, .conflict)
        XCTAssertEqual(db.methods(), ["GET", "PUT", "PUT", "GET"], "412, daarna opnieuw ophalen en beslissen")
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3700, "De wijziging van het andere apparaat is niet overschreven")
        XCTAssertEqual(a.engine.conflict?.remoteModified, cloudAt(250))
        XCTAssertEqual(a.engine.conflict?.localModified, cloudAt(200))
    }

    func testHarmlessWriteRaceIsRetriedAutomatically() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(100)), clockAt: 100)
        db.sendsETagOnWrite = false
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 200)

        // Een ander apparaat raakt de database aan zonder de inhoud te veranderen: de ETag klopt niet meer.
        let before = db.log.count
        db.beforeWrite = {
            db.seedRaw(db.document)
            db.beforeWrite = nil
        }
        let outcome = await a.engine.pushIfNeeded()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(Array(db.methods().dropFirst(before)), ["GET", "PUT", "GET", "PUT"])
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3100)
    }

    // MARK: Offline, tokens en fouten

    func testOfflineKeepsLocalChangesAndCatchesUpAfterwards() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()

        db.offline = true
        edit(a, salary: 3100, at: 600)
        let failed = await a.engine.pushIfNeeded()
        XCTAssertEqual(failed, .offline)
        XCTAssertEqual(a.engine.status, .offline)
        XCTAssertTrue(a.engine.hasUnsyncedChanges)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3100, "Lokaal blijft alles gewoon werken")

        edit(a, salary: 3200, at: 700)
        db.offline = false
        let outcome = await a.engine.syncNow()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3200)
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertEqual(a.engine.status, .synced(at: a.clock.now))
    }

    func testStartingOfflineWaitsWithoutBeingReady() async throws {
        let db = FakeRealtimeDatabase()
        db.offline = true
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        let outcome = await a.engine.syncNow()
        XCTAssertEqual(outcome, .offline)
        XCTAssertEqual(a.engine.status, .offline)
        XCTAssertFalse(a.engine.isReady)

        db.offline = false
        let later = await a.engine.syncNow()
        XCTAssertEqual(later, .done)
        XCTAssertTrue(a.engine.isReady)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
    }

    func testConnectionLostUpdatesTheStatus() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        await a.engine.syncNow()
        a.engine.connectionLost(offline: true)
        XCTAssertEqual(a.engine.status, .offline)
        a.engine.connectionLost(offline: false)
        XCTAssertEqual(a.engine.status, .connecting)
        a.engine.markConnecting()
        XCTAssertEqual(a.engine.status, .connecting)
    }

    func testExpiredTokenIsRefreshedOnceAndTheRequestRepeated() async throws {
        let db = FakeRealtimeDatabase()
        db.rejectedTokens = ["tok-uid123"]
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))

        let outcome = await a.engine.syncNow()

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(a.tokenCalls.first, false)
        XCTAssertTrue(a.tokenCalls.contains(true), "Het token is ververst")
        XCTAssertEqual(a.tokenCalls.filter { $0 }.count, 1, "Maar niet vaker dan nodig")
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
        XCTAssertEqual(db.log[0].query["auth"], "tok-uid123")
        XCTAssertEqual(db.log[1].query["auth"], "tok-uid123-v2")
    }

    func testRulesThatRefuseTheRequestShowAClearMessage() async throws {
        let db = FakeRealtimeDatabase()
        db.forbidWrites = true
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        let outcome = await a.engine.syncNow()
        guard case .failed(let text) = outcome else { return XCTFail("Verwachtte een fout, kreeg \(outcome)") }
        XCTAssertTrue(text.contains("database.rules.json"))
        XCTAssertEqual(a.engine.status, .failed(text))
        XCTAssertEqual(a.tokenCalls.filter { $0 }.count, 0, "Permission denied is geen verlopen token")
    }

    func testInvalidSessionIsReported() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        a.tokenFailure = FirebaseAuthError.sessionExpired
        let outcome = await a.engine.syncNow()
        XCTAssertEqual(outcome, .authExpired)
        XCTAssertEqual(a.engine.status, .failed(FirebaseAuthError.sessionExpired.localizedDescription))
        XCTAssertTrue(db.log.isEmpty)

        a.tokenFailure = FirebaseAuthError.userDisabled
        let disabled = await a.engine.syncNow()
        XCTAssertEqual(disabled, .authExpired)
    }

    func testNoInternetDuringTokenRefreshCountsAsOffline() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        a.tokenFailure = FirebaseAuthError.network
        let outcome = await a.engine.syncNow()
        XCTAssertEqual(outcome, .offline)
        XCTAssertEqual(a.engine.status, .offline)
    }

    func testCloudDataFromANewerAppVersionIsNotTouched() async throws {
        let db = FakeRealtimeDatabase()
        let text = try FirebaseDatabaseClient.encodeFinance(cloudFinance())
        let escaped = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
        db.seedRaw(#"{"data":\#(escaped),"modifiedAt":1790000900000,"device":"nieuwe app","schema":2}"#)
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 1, modified: cloudAt(500)))

        let outcome = await a.engine.syncNow()

        guard case .failed(let message) = outcome else { return XCTFail("Verwachtte een fout, kreeg \(outcome)") }
        XCTAssertTrue(message.contains("nieuwere versie"))
        XCTAssertEqual(db.methods(), ["GET"])
        XCTAssertTrue(a.applied.isEmpty)
        XCTAssertFalse(a.engine.isReady)
    }

    func testUnreadableCloudDataIsNotOverwritten() async throws {
        let db = FakeRealtimeDatabase()
        db.seedRaw(#"{"data":"dit is geen json","modifiedAt":1790000900000,"device":"x","schema":1}"#)
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        let outcome = await a.engine.syncNow()
        guard case .failed = outcome else { return XCTFail("Verwachtte een fout, kreeg \(outcome)") }
        XCTAssertEqual(db.methods(), ["GET"])
    }

    func testEndlessWriteRacesGiveUpPolitely() async throws {
        let db = FakeRealtimeDatabase()
        db.sendsETagOnWrite = false
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(100)), clockAt: 100)
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 200)
        let putsBefore = db.count("PUT")
        db.beforeWrite = { db.seedRaw(db.document) }   // elke keer een nieuwe ETag, zonder dat de inhoud verandert
        let outcome = await a.engine.pushIfNeeded()
        guard case .failed(let text) = outcome else { return XCTFail("Verwachtte een fout, kreeg \(outcome)") }
        XCTAssertTrue(text.contains("steeds"))
        XCTAssertEqual(db.count("PUT") - putsBefore, 4)
        XCTAssertTrue(a.engine.hasUnsyncedChanges, "De wijziging gaat niet verloren en wordt later opnieuw geprobeerd")
    }

    func testStateSurvivesInTheStore() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        await a.engine.syncNow()
        XCTAssertGreaterThan(a.stateStore.saveCount, 0)
        XCTAssertEqual(a.engine.state, a.stateStore.state)

        // Een motor die later met dezelfde staat start, weet waar hij gebleven was.
        let b = try makeDevice("iPhone", db: db, data: a.data, state: a.stateStore.load())
        XCTAssertEqual(b.engine.lastSyncedAt, a.engine.lastSyncedAt)
    }

    // MARK: Koersen vervuilen het vergelijken niet

    /// Gegevens met een gevolgde belegging, zoals de koersverversing ze aanpast.
    private func financeWithHolding(salary: Double = 3000, modified: Date?) -> (FinanceData, UUID) {
        var data = cloudFinance(salary: salary, modified: modified)
        var holding = Holding(name: "Wereld-ETF", ticker: "VWCE.DE", units: 10, startMonth: aug2026)
        holding.id = cloudUUID(900)
        data.holdings = [holding]
        return (data, holding.id)
    }

    /// De automatische koersverversing: nieuwe koers, nieuw meetpunt (met een willekeurig id) en een nieuwe wijzigingstijd.
    private func refreshPrice(_ device: SimulatedDevice, _ id: UUID, price: Double, at seconds: TimeInterval) {
        device.clock.now = cloudAt(seconds)
        device.data.recordPrice(holdingID: id, price: price, currency: "EUR", date: device.clock.now)
        device.data.modifiedAt = device.clock.now
        device.engine.localDidChange()
    }

    /// Twee apparaten die gelijk beginnen en allebei gesynchroniseerd zijn.
    private func makeSyncedPair(_ db: FakeRealtimeDatabase) async throws -> (SimulatedDevice, SimulatedDevice, UUID) {
        let (base, holdingID) = financeWithHolding(modified: cloudAt(100))
        let a = try makeDevice("iPhone", db: db, data: base, clockAt: 100)
        let b = try makeDevice("iPad", db: db, data: base, clockAt: 100)
        await a.engine.syncNow()
        await b.engine.syncNow()
        return (a, b, holdingID)
    }

    func testPriceRefreshBeforeTheFirstSyncDoesNotAskTheUserToChoose() async throws {
        let db = FakeRealtimeDatabase()
        let (a, b, holdingID) = try await makeSyncedPair(db)

        // Het andere apparaat past echt iets aan.
        edit(b, salary: 3500, at: 200)
        await b.engine.pushIfNeeded()
        // Op dit apparaat was de koersverversing sneller dan de eerste synchronisatie.
        refreshPrice(a, holdingID, price: 61.5, at: 210)

        let outcome = await a.engine.syncNow()

        XCTAssertEqual(outcome, .done)
        XCTAssertNil(a.engine.conflict)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3500, "De wijziging van het andere apparaat blijft behouden")
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3500)
        XCTAssertEqual(a.engine.status, .synced(at: a.clock.now))
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
    }

    func testPriceRefreshOnTheOtherDeviceDoesNotConflictWithALocalEdit() async throws {
        let db = FakeRealtimeDatabase()
        let (a, b, holdingID) = try await makeSyncedPair(db)

        refreshPrice(b, holdingID, price: 62, at: 200)
        await b.engine.pushIfNeeded()
        edit(a, salary: 3200, at: 210)

        let outcome = await a.engine.pushIfNeeded()

        XCTAssertEqual(outcome, .done)
        XCTAssertNil(a.engine.conflict)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3200, "De eigen wijziging gaat naar de cloud")
    }

    func testTwoDevicesRefreshingPricesAtTheSameTimeTakeTheNewestOne() async throws {
        let db = FakeRealtimeDatabase()
        let (a, b, holdingID) = try await makeSyncedPair(db)

        refreshPrice(b, holdingID, price: 62, at: 210)
        await b.engine.pushIfNeeded()
        refreshPrice(a, holdingID, price: 61, at: 220)
        let newer = await a.engine.syncNow()
        XCTAssertEqual(newer, .done)
        XCTAssertNil(a.engine.conflict)
        XCTAssertEqual(db.currentFinance()?.holdings.first?.lastPrice, 61, "Het eigen, nieuwere resultaat wint")

        // En andersom: het andere apparaat was later.
        let (c, d, id) = try await makeSyncedPair(FakeRealtimeDatabase())
        refreshPrice(c, id, price: 61, at: 205)
        refreshPrice(d, id, price: 62, at: 215)
        await d.engine.pushIfNeeded()
        let older = await c.engine.syncNow()
        XCTAssertEqual(older, .done)
        XCTAssertNil(c.engine.conflict)
        XCTAssertEqual(c.data.holdings.first?.lastPrice, 62)
    }

    func testRealChangesOnBothSidesStillAskTheUserEvenWithPricesInvolved() async throws {
        let db = FakeRealtimeDatabase()
        let (a, b, holdingID) = try await makeSyncedPair(db)

        edit(b, salary: 3500, at: 200)
        await b.engine.pushIfNeeded()
        refreshPrice(a, holdingID, price: 61.5, at: 205)
        edit(a, salary: 3300, at: 210)

        let outcome = await a.engine.syncNow()

        XCTAssertEqual(outcome, .conflict)
        XCTAssertNotNil(a.engine.conflict)
        XCTAssertEqual(a.data.salary.fixedMonthly, 3300, "Er wordt niets overschreven")
    }

    func testReplacedDataWithoutAChangeNoticeIsNeverTreatedAsAPriceChange() async throws {
        let db = FakeRealtimeDatabase()
        let (a, b, _) = try await makeSyncedPair(db)

        edit(b, salary: 3500, at: 200)
        await b.engine.pushIfNeeded()
        // Gegevens vervangen zonder melding aan de synchronisatie (bijvoorbeeld een teruggezette back-up).
        a.data = cloudFinance(salary: 1234, modified: cloudAt(150))

        let outcome = await a.engine.syncNow()

        XCTAssertEqual(outcome, .conflict, "Dit is geen koerswijziging: niets stilzwijgend overschrijven")
        XCTAssertEqual(a.data.salary.fixedMonthly, 1234)
    }

    func testFingerprintsAreRecordedAfterUploadingAndAfterDownloading() async throws {
        let db = FakeRealtimeDatabase()
        let (base, _) = financeWithHolding(modified: cloudAt(100))
        let a = try makeDevice("iPhone", db: db, data: base, clockAt: 100)
        let b = try makeDevice("iPad", db: db, data: cloudPristine(), clockAt: 110)

        await a.engine.syncNow()
        let expected = CloudSync.contentDigest(base)
        XCTAssertNotNil(expected)
        XCTAssertEqual(a.stateStore.state.syncedLocalDigest, expected)
        XCTAssertEqual(a.stateStore.state.syncedRemoteDigest, expected)

        await b.engine.syncNow()
        XCTAssertEqual(b.stateStore.state.syncedRemoteDigest, expected)
        XCTAssertEqual(b.stateStore.state.syncedLocalDigest, CloudSync.contentDigest(b.data))
        XCTAssertNil(b.stateStore.state.inFlightStamp)
    }

    func testChangesMadeWhileWritingAreNotCoveredByTheRecordedFingerprint() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(100)), clockAt: 100)
        await a.engine.syncNow()
        edit(a, salary: 3100, at: 200)
        db.beforeWrite = {
            // Tijdens het schrijven wijzigt de gebruiker nog iets.
            a.data.salary.fixedMonthly = 3150
            a.data.modifiedAt = cloudAt(201)
            a.engine.localDidChange()
            db.beforeWrite = nil
        }
        await a.engine.pushIfNeeded()

        var pushed = cloudFinance(salary: 3100, modified: cloudAt(200))
        pushed.modifiedAt = nil
        XCTAssertEqual(a.stateStore.state.syncedLocalDigest, CloudSync.contentDigest(pushed))
        XCTAssertNotEqual(a.stateStore.state.syncedLocalDigest, CloudSync.contentDigest(a.data))
        XCTAssertTrue(a.engine.hasUnsyncedChanges)
    }

    // MARK: Een schrijfactie waarvan het antwoord verloren ging

    func testLostWriteResponseDoesNotTurnIntoAConflictWithOurOwnWrite() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()

        // De cloud past onze schrijfactie toe, maar het antwoord komt nooit aan.
        edit(a, salary: 3200, at: 560)
        db.dropResponseAfterWrite = true
        let lost = await a.engine.pushIfNeeded()
        db.dropResponseAfterWrite = false
        XCTAssertEqual(lost, .offline)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3200)
        XCTAssertTrue(a.engine.hasUnsyncedChanges)

        // De gebruiker wijzigt daarna nog iets.
        edit(a, salary: 3300, at: 620)
        let outcome = await a.engine.pushIfNeeded()

        XCTAssertEqual(outcome, .done)
        XCTAssertNil(a.engine.conflict)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3300)
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertNil(a.stateStore.state.inFlightStamp)
    }

    func testLostWriteResponseIsRecognisedAfterARestartToo() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()
        edit(a, salary: 3200, at: 560)
        db.dropResponseAfterWrite = true
        await a.engine.pushIfNeeded()
        db.dropResponseAfterWrite = false
        XCTAssertNotNil(a.stateStore.state.inFlightStamp, "De onzekere schrijfactie wordt onthouden")

        // De app wordt afgesloten en opnieuw gestart; de gebruiker wijzigt nog iets.
        var restartedData = a.data
        restartedData.salary.fixedMonthly = 3300
        restartedData.modifiedAt = cloudAt(620)
        let restarted = try makeDevice("iPhone", db: db, data: restartedData, clockAt: 630, state: a.stateStore.state)
        let outcome = await restarted.engine.syncNow()

        XCTAssertEqual(outcome, .done)
        XCTAssertNil(restarted.engine.conflict)
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3300)
    }

    func testLostWriteResponseWithoutFurtherEditsIsSimplyConfirmed() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()
        edit(a, salary: 3200, at: 560)
        db.dropResponseAfterWrite = true
        await a.engine.pushIfNeeded()
        db.dropResponseAfterWrite = false
        let before = db.count("PUT")

        let outcome = await a.engine.syncNow()

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(db.count("PUT"), before, "Er staat al precies wat we willen schrijven")
        XCTAssertFalse(a.engine.hasUnsyncedChanges)
        XCTAssertEqual(a.stateStore.state.lastSyncedStamp, cloudAt(560))
    }

    func testAnotherDeviceWithTheSameTimestampIsNotMistakenForOurOwnWrite() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()
        edit(a, salary: 3200, at: 560)
        db.dropResponseAfterWrite = true
        await a.engine.pushIfNeeded()
        db.dropResponseAfterWrite = false

        // Een ander apparaat schreef intussen een versie met precies dezelfde wijzigingstijd.
        try db.seed(cloudFinance(salary: 3777, modified: cloudAt(560)), device: "iPad (zz)")
        edit(a, salary: 3300, at: 620)
        let outcome = await a.engine.pushIfNeeded()

        XCTAssertEqual(outcome, .conflict, "Alleen een versie van dit apparaat telt als eigen schrijfactie")
    }

    // MARK: Een verdwenen document en een verwijderd account

    func testVanishedDocumentIsOnlyRestoredAfterConfirmingTheAccountStillExists() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        db.seedRaw(nil)
        a.tokenCalls.removeAll()

        let action = await a.engine.receive(.snapshot(nil))

        XCTAssertEqual(action, .keepListening)
        XCTAssertTrue(a.tokenCalls.contains(true), "Eerst controleren of het account nog bestaat")
        XCTAssertEqual(db.currentFinance()?.salary.fixedMonthly, 3000)
    }

    func testNothingIsRestoredForADeletedAccount() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)))
        await a.engine.syncNow()
        let putsBefore = db.count("PUT")

        // Een ander apparaat verwijderde het account: de gegevens zijn weg en het token wordt niet meer vernieuwd.
        db.seedRaw(nil)
        a.forceRefreshFailure = FirebaseAuthError.sessionExpired
        let action = await a.engine.receive(.snapshot(nil))

        XCTAssertEqual(action, .authExpired)
        XCTAssertEqual(db.count("PUT"), putsBefore, "Er worden geen gegevens van een verwijderd account teruggezet")
        XCTAssertNil(db.document)
    }

    func testNothingIsRestoredForADeletedAccountWhenSyncingAfterALocalEdit() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(salary: 3000, modified: cloudAt(500)), clockAt: 500)
        await a.engine.syncNow()
        let putsBefore = db.count("PUT")
        db.seedRaw(nil)
        a.forceRefreshFailure = FirebaseAuthError.sessionExpired

        edit(a, salary: 3100, at: 560)
        let outcome = await a.engine.pushIfNeeded()

        XCTAssertEqual(outcome, .authExpired)
        XCTAssertEqual(db.count("PUT") - putsBefore, 1, "Alleen de poging met de bekende ETag, die werd geweigerd")
        XCTAssertNil(db.document)
    }

    func testFirstUploadNeverNeedsTheExtraAccountCheck() async throws {
        let db = FakeRealtimeDatabase()
        let a = try makeDevice("iPhone", db: db, data: cloudFinance(modified: cloudAt(500)))
        await a.engine.syncNow()
        XCTAssertFalse(a.tokenCalls.contains(true))
    }
}

private extension SyncOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
