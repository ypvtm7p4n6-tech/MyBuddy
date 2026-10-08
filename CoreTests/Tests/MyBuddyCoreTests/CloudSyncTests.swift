import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MyBuddyCore

// De regels van het synchroniseren: beslissen, uitstellen, opnieuw verbinden, berichten lezen en kleine bestanden.

final class CloudSyncTests: XCTestCase {
    // MARK: Hulpjes

    private func remote(_ finance: FinanceData, modified: Date? = nil, device: String = "ander apparaat") throws -> RemoteSnapshot {
        try RemoteSnapshot(finance: finance, modifiedAt: modified ?? finance.modifiedAt, device: device, etag: "etag-x")
    }

    private func decide(local: FinanceData?, synced: Date?, remote: RemoteSnapshot?) -> SyncDecision {
        CloudSync.reconcile(local: local, localLastSyncedAt: synced, remote: remote)
    }

    /// Alleen een wijzigingstijd, geen inhoud (iemand maakte alles leeg).
    private func wiped(modified: Date) -> FinanceData {
        var d = cloudPristine()
        d.modifiedAt = modified
        return d
    }

    // MARK: Inhoud herkennen

    func testHasContent() {
        XCTAssertFalse(CloudSync.hasContent(FinanceData(startMonth: aug2026)))
        XCTAssertFalse(CloudSync.hasContent(cloudPristine()))
        XCTAssertTrue(CloudSync.hasContent(cloudFinance()))

        var salary = cloudPristine()
        salary.salary.fixedMonthly = 100
        XCTAssertTrue(CloudSync.hasContent(salary))

        var pot = cloudPristine()
        _ = addBufferPot(&pot)
        XCTAssertTrue(CloudSync.hasContent(pot))

        var expense = cloudPristine()
        expense.editPlan(oct2026) { $0.expenses.append(MoneyLine(name: "Huur", amount: 1)) }
        XCTAssertTrue(CloudSync.hasContent(expense))

        var override = cloudPristine()
        override.editPlan(oct2026) { $0.salaryOverride = 10 }
        XCTAssertTrue(CloudSync.hasContent(override))

        // Instellingen die vanzelf bijgewerkt worden tellen niet als inhoud.
        var settings = cloudPristine()
        settings.settings.inflation = 0.031
        settings.settings.lastMarketUpdate = cloudT0
        settings.settings.blockOrder = ["home": ["pots"]]
        XCTAssertFalse(CloudSync.hasContent(settings))
    }

    func testPristine() {
        XCTAssertTrue(CloudSync.isPristine(nil))
        XCTAssertTrue(CloudSync.isPristine(cloudPristine()))
        XCTAssertFalse(CloudSync.isPristine(wiped(modified: cloudT0)))
        var legacy = cloudFinance()
        legacy.modifiedAt = nil
        XCTAssertFalse(CloudSync.isPristine(legacy))
    }

    func testContentEqualIgnoresModifiedAtAndSubSecondDates() throws {
        var a = cloudFinance(salary: 100, modified: cloudAt(1))
        var b = a
        b.modifiedAt = cloudAt(500)
        XCTAssertTrue(CloudSync.contentEqual(a, b))
        b.salary.fixedMonthly = 101
        XCTAssertFalse(CloudSync.contentEqual(a, b))

        // Een tijdstip met een fractie van een seconde is na opslaan op de seconde afgerond. Dat is geen verschil.
        var pot = Pot(name: "Buffer", monthlyContribution: 10, startMonth: aug2026)
        pot.createdAt = cloudT0.addingTimeInterval(0.7)
        a.pots = [pot]
        let roundTripped = try RemoteSnapshot(finance: a).decodeFinance()
        XCTAssertNotEqual(roundTripped.pots.first?.createdAt, pot.createdAt)
        XCTAssertTrue(CloudSync.contentEqual(a, roundTripped))
    }

    // MARK: Tijdstempels

    func testStampHelpers() {
        XCTAssertEqual(CloudSync.milliseconds(Date(timeIntervalSince1970: 1_790_000_000.4567)), 1_790_000_000_457)
        XCTAssertEqual(CloudSync.date(milliseconds: 1_790_000_000_500), Date(timeIntervalSince1970: 1_790_000_000.5))

        // Tijden uit de cloud: alleen een afronding op de milliseconde is "dezelfde versie".
        XCTAssertTrue(CloudSync.sameStamp(nil, nil))
        XCTAssertFalse(CloudSync.sameStamp(nil, cloudT0))
        XCTAssertFalse(CloudSync.sameStamp(cloudT0, nil))
        XCTAssertTrue(CloudSync.sameStamp(cloudT0, cloudT0))
        XCTAssertTrue(CloudSync.sameStamp(cloudT0, cloudT0.addingTimeInterval(0.0005)))
        XCTAssertFalse(CloudSync.sameStamp(cloudT0, cloudT0.addingTimeInterval(0.01)))
        XCTAssertFalse(CloudSync.sameStamp(cloudT0, cloudT0.addingTimeInterval(1)))
        XCTAssertFalse(CloudSync.sameStamp(cloudT0, cloudT0.addingTimeInterval(-5)))
    }

    func testLocalTimestampMayBeRoundedDownButNeverIsNewer() {
        let version = cloudAt(100.7)   // zoals in de cloud: milliseconden
        XCTAssertTrue(CloudSync.localMatches(nil, nil))
        XCTAssertFalse(CloudSync.localMatches(nil, version))
        XCTAssertFalse(CloudSync.localMatches(version, nil))
        // Precies dezelfde tijd, of de tijd zoals die na opslaan op de seconde is afgerond.
        XCTAssertTrue(CloudSync.localMatches(version, version))
        XCTAssertTrue(CloudSync.localMatches(cloudAt(100), version))
        XCTAssertTrue(CloudSync.localMatches(version.addingTimeInterval(0.0004), version))
        // Een lokale tijd die later is, is een nieuwe wijziging, ook als het maar een halve seconde scheelt.
        XCTAssertFalse(CloudSync.localMatches(cloudAt(101.2), version))
        XCTAssertFalse(CloudSync.localMatches(version.addingTimeInterval(0.01), version))
        // En een lokale tijd die ruim eerder is, hoort niet bij deze versie.
        XCTAssertFalse(CloudSync.localMatches(cloudAt(99), version))
        XCTAssertFalse(CloudSync.localMatches(cloudAt(0), version))
    }

    func testNewerSideNeedsMoreThanTheClockSkewTolerance() {
        XCTAssertEqual(CloudSync.clockSkewTolerance, 60)
        XCTAssertNil(CloudSync.newerSide(localModified: cloudAt(0), remoteModified: cloudAt(59)))
        XCTAssertNil(CloudSync.newerSide(localModified: cloudAt(59), remoteModified: cloudAt(0)))
        XCTAssertNil(CloudSync.newerSide(localModified: cloudAt(0), remoteModified: cloudAt(60)))
        XCTAssertEqual(CloudSync.newerSide(localModified: cloudAt(61), remoteModified: cloudAt(0)), .local)
        XCTAssertEqual(CloudSync.newerSide(localModified: cloudAt(0), remoteModified: cloudAt(61)), .remote)
        XCTAssertNil(CloudSync.newerSide(localModified: nil, remoteModified: cloudAt(0)))
        XCTAssertNil(CloudSync.newerSide(localModified: cloudAt(0), remoteModified: nil))
    }

    // MARK: Beslissen: cloud leeg

    func testEmptyCloudWithExistingLocalDataMeansUpload() throws {
        // Eerste login op een apparaat met bestaande gegevens en een lege cloud.
        XCTAssertEqual(decide(local: cloudFinance(), synced: nil, remote: nil), .pushLocal)
        // Ook als er al eens gesynchroniseerd was (iemand wiste de cloud): zet de gegevens terug.
        XCTAssertEqual(decide(local: cloudFinance(), synced: cloudAt(-100), remote: nil), .pushLocal)
        // Gegevens van vóór de synchronisatie hebben geen wijzigingstijd, maar gaan wel mee.
        var legacy = cloudFinance()
        legacy.modifiedAt = nil
        XCTAssertEqual(decide(local: legacy, synced: nil, remote: nil), .pushLocal)
    }

    func testEmptyCloudAndNothingLocalMeansNothingToDo() {
        XCTAssertEqual(decide(local: nil, synced: nil, remote: nil), .noop)
        XCTAssertEqual(decide(local: cloudPristine(), synced: nil, remote: nil), .noop)
        XCTAssertEqual(decide(local: wiped(modified: cloudT0), synced: nil, remote: nil), .noop)
    }

    // MARK: Beslissen: leeg versus gevuld

    func testNewDeviceTakesTheCloud() throws {
        let cloud = try remote(cloudFinance(salary: 1234, modified: cloudAt(50)))
        XCTAssertEqual(decide(local: nil, synced: nil, remote: cloud), .pullRemote)
        XCTAssertEqual(decide(local: cloudPristine(), synced: nil, remote: cloud), .pullRemote)
        // Ook als dit apparaat vroeger al eens gesynchroniseerd had (opnieuw geïnstalleerd).
        XCTAssertEqual(decide(local: cloudPristine(), synced: cloudAt(10), remote: cloud), .pullRemote)
        // Een leeg document in de cloud wordt ook gewoon overgenomen.
        let emptyCloud = try remote(wiped(modified: cloudAt(5)))
        XCTAssertEqual(decide(local: cloudPristine(), synced: nil, remote: emptyCloud), .pullRemote)
    }

    func testFilledDeviceAndEmptyCloudDocumentMeansUpload() throws {
        let emptyCloud = try remote(wiped(modified: cloudAt(5)))
        XCTAssertEqual(decide(local: cloudFinance(modified: cloudAt(10)), synced: nil, remote: emptyCloud), .pushLocal)
    }

    func testBothEmptyMeansNothingToDo() throws {
        let emptyCloud = try remote(wiped(modified: cloudAt(5)))
        XCTAssertEqual(decide(local: wiped(modified: cloudAt(9)), synced: nil, remote: emptyCloud), .noop)
    }

    func testStampedButEmptyLocalWithoutHistoryTakesTheCloud() throws {
        // Iemand typte op het nieuwe apparaat iets en wiste het weer: er is niets te verliezen.
        let cloud = try remote(cloudFinance(modified: cloudAt(50)))
        XCTAssertEqual(decide(local: wiped(modified: cloudAt(60)), synced: nil, remote: cloud), .pullRemote)
    }

    // MARK: Beslissen: zonder historie (nog nooit gesynchroniseerd)

    func testBothFilledWithoutHistoryAndDifferentIsAConflict() throws {
        let local = cloudFinance(salary: 3000, modified: cloudAt(100))
        let cloud = try remote(cloudFinance(salary: 3500, modified: cloudAt(200)))
        XCTAssertEqual(decide(local: local, synced: nil, remote: cloud),
                       .conflict(localModified: cloudAt(100), remoteModified: cloudAt(200)))
    }

    func testBothFilledWithoutHistoryButIdenticalIsNothingToDo() throws {
        let local = cloudFinance(salary: 3000, modified: cloudAt(100))
        let cloud = try remote(cloudFinance(salary: 3000, modified: cloudAt(300)))
        XCTAssertEqual(decide(local: local, synced: nil, remote: cloud), .noop)
    }

    func testLegacyDataWithoutTimestampConflictsWithDifferentCloudData() throws {
        var local = cloudFinance(salary: 3000)
        local.modifiedAt = nil
        let cloud = try remote(cloudFinance(salary: 3500, modified: cloudAt(200)))
        XCTAssertEqual(decide(local: local, synced: nil, remote: cloud),
                       .conflict(localModified: nil, remoteModified: cloudAt(200)))
    }

    func testUnreadableCloudDataIsTreatedAsFilled() {
        let broken = RemoteSnapshot(json: "geen json", modifiedAt: cloudAt(200), device: "x")
        XCTAssertEqual(decide(local: cloudFinance(modified: cloudAt(100)), synced: nil, remote: broken),
                       .conflict(localModified: cloudAt(100), remoteModified: cloudAt(200)))
    }

    // MARK: Beslissen: met historie

    func testSameVersionIsNothingToDo() throws {
        let local = cloudFinance(modified: cloudAt(100))
        let cloud = try remote(local)
        XCTAssertEqual(decide(local: local, synced: nil, remote: cloud), .noop)
        XCTAssertEqual(decide(local: local, synced: cloudAt(100), remote: cloud), .noop)
        // Een afronding op de seconde maakt het geen andere versie.
        let nearlyThere = try remote(local, modified: cloudAt(100.4))
        XCTAssertEqual(decide(local: local, synced: cloudAt(50), remote: nearlyThere), .noop)
    }

    func testOnlyLocalChangedMeansUpload() throws {
        let synced = cloudAt(100)
        let local = cloudFinance(salary: 3100, modified: cloudAt(150))
        let cloud = try remote(cloudFinance(salary: 3000, modified: synced))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud), .pushLocal)
    }

    func testOnlyCloudChangedMeansDownload() throws {
        let synced = cloudAt(100)
        let local = cloudFinance(salary: 3000, modified: synced)
        let cloud = try remote(cloudFinance(salary: 3200, modified: cloudAt(180)))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud), .pullRemote)
    }

    func testBothChangedAndDifferentIsAConflict() throws {
        let synced = cloudAt(100)
        let local = cloudFinance(salary: 3100, modified: cloudAt(150))
        let cloud = try remote(cloudFinance(salary: 3200, modified: cloudAt(180)))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud),
                       .conflict(localModified: cloudAt(150), remoteModified: cloudAt(180)))
    }

    func testBothChangedToTheSameContentIsNothingToDo() throws {
        let synced = cloudAt(100)
        let local = cloudFinance(salary: 3100, modified: cloudAt(150))
        let cloud = try remote(cloudFinance(salary: 3100, modified: cloudAt(180)))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud), .noop)
    }

    func testWipeIsPropagatedOnceItWasSynced() throws {
        let synced = cloudAt(100)
        let cloud = try remote(cloudFinance(modified: synced))
        // Lokaal alles gewist (met wijzigingstijd): de cloud volgt.
        XCTAssertEqual(decide(local: wiped(modified: cloudAt(160)), synced: synced, remote: cloud), .pushLocal)
        // En een ander apparaat dat niets veranderde, neemt de lege versie over.
        let emptyCloud = try remote(wiped(modified: cloudAt(160)))
        XCTAssertEqual(decide(local: cloudFinance(modified: synced), synced: synced, remote: emptyCloud), .pullRemote)
    }

    func testRemoteDeletedWhileLocalUnchangedStillUploads() {
        XCTAssertEqual(decide(local: cloudFinance(modified: cloudAt(100)), synced: cloudAt(100), remote: nil), .pushLocal)
    }

    // MARK: Beslissen: klokken die afwijken

    func testCloudChangeWithAnEarlierClockIsStillDetected() throws {
        // Een ander apparaat loopt een half uur achter: zijn wijziging heeft een eerdere tijd dan onze sync.
        let synced = cloudAt(1000)
        let local = cloudFinance(salary: 3000, modified: synced)
        let cloud = try remote(cloudFinance(salary: 3300, modified: cloudAt(1000 - 1800)))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud), .pullRemote)
    }

    func testLocalChangeWithASlowClockIsStillDetected() throws {
        let synced = cloudAt(1000)
        let local = cloudFinance(salary: 3300, modified: cloudAt(1000 - 1800))
        let cloud = try remote(cloudFinance(salary: 3000, modified: synced))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud), .pushLocal)
    }

    func testChangeFiveSecondsAfterTheSyncIsNotLost() throws {
        let synced = cloudAt(1000)
        let local = cloudFinance(salary: 3300, modified: cloudAt(1005))
        let cloud = try remote(cloudFinance(salary: 3000, modified: synced))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud), .pushLocal)
    }

    func testLegacyLocalDataWithHistoryCountsAsChanged() throws {
        var local = cloudFinance(salary: 3300)
        local.modifiedAt = nil
        let cloud = try remote(cloudFinance(salary: 3000, modified: cloudAt(100)))
        XCTAssertEqual(decide(local: local, synced: cloudAt(100), remote: cloud), .pushLocal)
    }

    func testChangeJustAfterTheSyncIsNotMissed() throws {
        // De versie is gesynchroniseerd op 1000,0; een halve seconde later wijzigt de gebruiker iets.
        let synced = cloudAt(1000)
        let local = cloudFinance(salary: 3300, modified: cloudAt(1000.5))
        let cloud = try remote(cloudFinance(salary: 3000, modified: synced))
        XCTAssertEqual(decide(local: local, synced: synced, remote: cloud), .pushLocal)
    }

    func testKnownUnsyncedChangesCountEvenWhenTheTimestampsLookEqual() throws {
        let synced = cloudAt(1000)
        let local = cloudFinance(salary: 3300, modified: synced)    // zelfde tijd, andere inhoud (bijvoorbeeld een wissel van klok)
        let cloud = try remote(cloudFinance(salary: 3000, modified: synced))
        XCTAssertEqual(CloudSync.reconcile(local: local, localLastSyncedAt: synced, remote: cloud), .noop)
        XCTAssertEqual(CloudSync.reconcile(local: local, localLastSyncedAt: synced, remote: cloud, localHasUnsyncedChanges: true), .pushLocal)

        // Is de cloud ook veranderd, dan is het een conflict.
        let changedCloud = try remote(cloudFinance(salary: 3600, modified: cloudAt(1100)))
        XCTAssertEqual(CloudSync.reconcile(local: local, localLastSyncedAt: synced, remote: changedCloud, localHasUnsyncedChanges: true),
                       .conflict(localModified: synced, remoteModified: cloudAt(1100)))
    }

    func testSyncStateRememberingUnsyncedChangesAndReadingOldFiles() throws {
        let state = SyncState(lastSyncedStamp: cloudT0, lastSyncedAt: cloudAt(1), dirty: true)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SyncState.self, from: data), state)
        // Een bestand zonder het veld "dirty" blijft leesbaar.
        let old = Data(#"{"lastSyncedStamp":1000.5}"#.utf8)
        let decoded = try JSONDecoder().decode(SyncState.self, from: old)
        XCTAssertFalse(decoded.dirty)
        XCTAssertNotNil(decoded.lastSyncedStamp)
    }

    // MARK: Koersen tellen niet als wijziging

    private func holdingData(salary: Double = 3000, modified: Date?) -> (FinanceData, UUID) {
        var data = cloudFinance(salary: salary, modified: modified)
        var tracked = Holding(name: "Wereld-ETF", ticker: "VWCE.DE", units: 10, startMonth: aug2026)
        tracked.id = cloudUUID(900)
        var manual = Holding(name: "Huis", startMonth: aug2026)
        manual.id = cloudUUID(901)
        data.holdings = [tracked, manual]
        data.addSnapshot(holdingID: manual.id, value: 250_000, invested: 200_000, date: cloudAt(5))
        return (data, tracked.id)
    }

    private func withPrice(_ data: FinanceData, _ id: UUID, price: Double, modified: Date) -> FinanceData {
        var copy = data
        copy.recordPrice(holdingID: id, price: price, currency: "EUR", date: modified)
        copy.modifiedAt = modified
        return copy
    }

    func testWithoutMarketDataRemovesOnlyThePricesOfHoldingsThatFollowAQuote() {
        let (base, id) = holdingData(modified: cloudAt(100))
        let priced = withPrice(base, id, price: 61.5, modified: cloudAt(150))
        XCTAssertNotNil(priced.holdings[0].lastPrice)
        XCTAssertEqual(priced.holdings[0].snapshots.count, 1)

        let stripped = CloudSync.withoutMarketData(priced)
        XCTAssertNil(stripped.holdings[0].lastPrice)
        XCTAssertNil(stripped.holdings[0].lastPriceDate)
        XCTAssertNil(stripped.holdings[0].priceCurrency)
        XCTAssertTrue(stripped.holdings[0].snapshots.isEmpty)
        XCTAssertNil(stripped.modifiedAt)
        // Een belegging zonder ticker houdt haar meetpunten: die heeft de gebruiker zelf ingevuld.
        XCTAssertEqual(stripped.holdings[1].snapshots.count, 1)
        XCTAssertEqual(stripped.salary, priced.salary)
    }

    func testDigestIgnoresPricesAndTimestampsButNotRealChanges() {
        let (base, id) = holdingData(modified: cloudAt(100))
        let digest = CloudSync.contentDigest(base)
        XCTAssertNotNil(digest)
        XCTAssertEqual(CloudSync.contentDigest(withPrice(base, id, price: 61, modified: cloudAt(200))), digest)
        XCTAssertEqual(CloudSync.contentDigest(withPrice(base, id, price: 62, modified: cloudAt(300))), digest)
        var later = base
        later.modifiedAt = cloudAt(999)
        XCTAssertEqual(CloudSync.contentDigest(later), digest)

        var edited = base
        edited.salary.fixedMonthly = 3001
        XCTAssertNotEqual(CloudSync.contentDigest(edited), digest)
        var manual = base
        manual.addSnapshot(holdingID: cloudUUID(901), value: 260_000, invested: 200_000, date: cloudAt(9))
        XCTAssertNotEqual(CloudSync.contentDigest(manual), digest)
        var units = base
        units.holdings[0].units = 11
        XCTAssertNotEqual(CloudSync.contentDigest(units), digest)
    }

    func testDigestSurvivesTheTripThroughTheCloud() throws {
        // Wat we schreven en wat een ander apparaat terugleest, geeft dezelfde vingerafdruk.
        let (start, id) = holdingData(modified: cloudAt(100))
        let base = withPrice(start, id, price: 61.55, modified: cloudT0.addingTimeInterval(100.7))
        let read = try RemoteSnapshot(finance: base).decodeFinance()
        XCTAssertEqual(CloudSync.contentDigest(read), CloudSync.contentDigest(base))
    }

    private func decideWithDigests(local: FinanceData, remote: FinanceData, base: FinanceData, synced: Date,
                                   unsynced: Bool = true) throws -> SyncDecision {
        let digest = CloudSync.contentDigest(base)
        return CloudSync.reconcile(local: local, localLastSyncedAt: synced, remote: try self.remote(remote),
                                   localHasUnsyncedChanges: unsynced,
                                   syncedLocalDigest: digest, syncedRemoteDigest: digest)
    }

    func testOnlyLocalPricesChangedWhileTheCloudChangedTakesTheCloud() throws {
        let (base, id) = holdingData(modified: cloudAt(100))
        let local = withPrice(base, id, price: 61.5, modified: cloudAt(150))
        var cloud = base
        cloud.salary.fixedMonthly = 3500
        cloud.modifiedAt = cloudAt(180)
        XCTAssertEqual(try decideWithDigests(local: local, remote: cloud, base: base, synced: cloudAt(100)), .pullRemote)
    }

    func testOnlyCloudPricesChangedWhileLocalChangedUploads() throws {
        let (base, id) = holdingData(modified: cloudAt(100))
        var local = base
        local.salary.fixedMonthly = 3200
        local.modifiedAt = cloudAt(150)
        let cloud = withPrice(base, id, price: 62, modified: cloudAt(180))
        XCTAssertEqual(try decideWithDigests(local: local, remote: cloud, base: base, synced: cloudAt(100)), .pushLocal)
    }

    func testBothOnlyChangedPricesTheNewestVersionWins() throws {
        let (base, id) = holdingData(modified: cloudAt(100))
        let older = withPrice(base, id, price: 61, modified: cloudAt(150))
        let newer = withPrice(base, id, price: 62, modified: cloudAt(180))
        XCTAssertEqual(try decideWithDigests(local: newer, remote: older, base: base, synced: cloudAt(100)), .pushLocal)
        XCTAssertEqual(try decideWithDigests(local: older, remote: newer, base: base, synced: cloudAt(100)), .pullRemote)
        let sameTime = withPrice(base, id, price: 63, modified: cloudAt(150))
        XCTAssertEqual(try decideWithDigests(local: sameTime, remote: older, base: base, synced: cloudAt(100)), .pushLocal,
                       "Bij gelijke tijd blijft de lokale versie")
    }

    func testRealChangesOnBothSidesAreStillAConflictWithDigests() throws {
        let (base, id) = holdingData(modified: cloudAt(100))
        var local = withPrice(base, id, price: 61.5, modified: cloudAt(140))
        local.salary.fixedMonthly = 3200
        local.modifiedAt = cloudAt(150)
        var cloud = base
        cloud.salary.fixedMonthly = 3500
        cloud.modifiedAt = cloudAt(180)
        XCTAssertEqual(try decideWithDigests(local: local, remote: cloud, base: base, synced: cloudAt(100)),
                       .conflict(localModified: cloudAt(150), remoteModified: cloudAt(180)))
    }

    func testWithoutDigestsAPriceDifferenceStaysAConflict() throws {
        let (base, id) = holdingData(modified: cloudAt(100))
        let local = withPrice(base, id, price: 61, modified: cloudAt(150))
        let cloud = withPrice(base, id, price: 62, modified: cloudAt(180))
        XCTAssertEqual(CloudSync.reconcile(local: local, localLastSyncedAt: cloudAt(100), remote: try remote(cloud),
                                           localHasUnsyncedChanges: true),
                       .conflict(localModified: cloudAt(150), remoteModified: cloudAt(180)))
        // Ook met maar één vingerafdruk durven we niet te kiezen.
        XCTAssertEqual(CloudSync.reconcile(local: local, localLastSyncedAt: cloudAt(100), remote: try remote(cloud),
                                           localHasUnsyncedChanges: true,
                                           syncedLocalDigest: CloudSync.contentDigest(base), syncedRemoteDigest: nil),
                       .conflict(localModified: cloudAt(150), remoteModified: cloudAt(180)))
    }

    func testLocalDataThatDiffersFromTheSyncedVersionIsNeverTreatedAsPricesOnly() throws {
        // Lokaal is de inhoud vervangen (bijvoorbeeld een teruggezette back-up) zonder dat dat is gemeld.
        let (base, _) = holdingData(modified: cloudAt(100))
        var local = base
        local.salary.fixedMonthly = 1234
        local.modifiedAt = cloudAt(150)
        var cloud = base
        cloud.salary.fixedMonthly = 3500
        cloud.modifiedAt = cloudAt(180)
        XCTAssertEqual(try decideWithDigests(local: local, remote: cloud, base: base, synced: cloudAt(100), unsynced: false),
                       .conflict(localModified: cloudAt(150), remoteModified: cloudAt(180)))
    }

    func testSyncStateKeepsItsDigestsAndOldFilesStayReadable() throws {
        let state = SyncState(lastSyncedStamp: cloudT0, lastSyncedAt: cloudAt(1), dirty: false,
                              inFlightStamp: cloudAt(7.25), syncedLocalDigest: "abc-1", syncedRemoteDigest: "def-2")
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SyncState.self, from: data), state)
        // Een bestand van een eerdere versie van de app heeft deze velden niet.
        let old = Data(#"{"lastSyncedStamp":1000.5,"dirty":true}"#.utf8)
        let decoded = try JSONDecoder().decode(SyncState.self, from: old)
        XCTAssertNil(decoded.inFlightStamp)
        XCTAssertNil(decoded.syncedLocalDigest)
        XCTAssertNil(decoded.syncedRemoteDigest)
        XCTAssertTrue(decoded.dirty)
    }

    // MARK: Uitstellen van schrijven

    func testDebouncerWaitsForQuietPeriod() {
        var debouncer = SyncDebouncer()
        XCTAssertNil(debouncer.fireDate())
        XCTAssertNil(debouncer.delay(at: cloudAt(0)))
        XCTAssertFalse(debouncer.isDue(at: cloudAt(0)))
        XCTAssertFalse(debouncer.hasPending)

        debouncer.recordChange(at: cloudAt(10))
        XCTAssertTrue(debouncer.hasPending)
        XCTAssertEqual(debouncer.fireDate(), cloudAt(11.5))
        XCTAssertEqual(debouncer.delay(at: cloudAt(10)) ?? -1, 1.5, accuracy: 0.0001)
        XCTAssertFalse(debouncer.isDue(at: cloudAt(11.4)))
        XCTAssertTrue(debouncer.isDue(at: cloudAt(11.5)))
        XCTAssertEqual(debouncer.delay(at: cloudAt(20)) ?? -1, 0, accuracy: 0.0001)

        // Nog een wijziging schuift het moment op.
        debouncer.recordChange(at: cloudAt(11))
        XCTAssertEqual(debouncer.fireDate(), cloudAt(12.5))
        XCTAssertFalse(debouncer.isDue(at: cloudAt(12.4)))
    }

    func testDebouncerNeverWaitsLongerThanTheMaximumWhileTyping() {
        var debouncer = SyncDebouncer()
        for second in 0...14 { debouncer.recordChange(at: cloudAt(Double(second))) }
        // Laatste wijziging op 14 s: 15,5 s zou het worden, maar het maximum is 15 s na de eerste.
        XCTAssertEqual(debouncer.fireDate(), cloudAt(15))
        XCTAssertTrue(debouncer.isDue(at: cloudAt(15)))
    }

    func testDebouncerLimitsPushesToOneEveryFiveSeconds() {
        var debouncer = SyncDebouncer()
        debouncer.recordChange(at: cloudAt(100))
        debouncer.beginPush(at: cloudAt(101.5))
        XCTAssertFalse(debouncer.hasPending)
        XCTAssertNil(debouncer.fireDate())

        // Een wijziging vlak na het schrijven wacht tot 5 seconden na het vorige schrijven.
        debouncer.recordChange(at: cloudAt(102))
        XCTAssertEqual(debouncer.fireDate(), cloudAt(106.5))
        XCTAssertEqual(debouncer.delay(at: cloudAt(103)) ?? -1, 3.5, accuracy: 0.0001)

        // Na het schrijven volgt een latere wijziging gewoon de rustperiode.
        debouncer.beginPush(at: cloudAt(107))
        debouncer.recordChange(at: cloudAt(120))
        XCTAssertEqual(debouncer.fireDate(), cloudAt(121.5))
    }

    func testDebouncerKeepsChangesMadeDuringAPushAndRestoresAfterFailure() {
        var debouncer = SyncDebouncer()
        debouncer.recordChange(at: cloudAt(0))
        debouncer.beginPush(at: cloudAt(2))
        debouncer.recordChange(at: cloudAt(3))   // tijdens het schrijven
        XCTAssertTrue(debouncer.hasPending)

        var failed = SyncDebouncer()
        failed.recordChange(at: cloudAt(0))
        failed.beginPush(at: cloudAt(2))
        XCTAssertFalse(failed.hasPending)
        failed.restorePending(at: cloudAt(3))
        XCTAssertTrue(failed.hasPending)
        XCTAssertGreaterThanOrEqual(failed.fireDate() ?? .distantPast, cloudAt(7))

        failed.reset()
        XCTAssertFalse(failed.hasPending)
        XCTAssertNil(failed.fireDate())
    }

    func testDebouncerCanForgetAWaitingChange() {
        var debouncer = SyncDebouncer()
        debouncer.recordChange(at: cloudAt(0))
        XCTAssertTrue(debouncer.hasPending)
        debouncer.discardPending()
        XCTAssertFalse(debouncer.hasPending)
        XCTAssertNil(debouncer.fireDate())
        XCTAssertFalse(debouncer.isDue(at: cloudAt(100)))
    }

    func testDebouncerDefaultsMatchTheSpecification() {
        let debouncer = SyncDebouncer()
        XCTAssertEqual(debouncer.quietPeriod, 1.5)
        XCTAssertEqual(debouncer.minimumInterval, 5)
        XCTAssertEqual(debouncer.maximumWait, 15)
    }

    // MARK: Opnieuw verbinden

    func testBackoffDoublesUpToSixtySecondsAndResets() {
        var backoff = ReconnectBackoff()
        XCTAssertEqual((0..<9).map { _ in backoff.nextDelay() }, [1, 2, 4, 8, 16, 32, 60, 60, 60])
        backoff.reset()
        XCTAssertEqual(backoff.nextDelay(), 1)
        XCTAssertEqual(backoff.nextDelay(), 2)

        var custom = ReconnectBackoff(base: 0.5, maximum: 3)
        XCTAssertEqual((0..<5).map { _ in custom.nextDelay() }, [0.5, 1, 2, 3, 3])

        var long = ReconnectBackoff()
        for _ in 0..<500 { _ = long.nextDelay() }
        XCTAssertEqual(long.nextDelay(), 60)
    }

    // MARK: Server-Sent Events

    private let putEvent = "event: put\ndata: {\"path\":\"/\",\"data\":null}\n\n"
    private let keepAlive = "event: keep-alive\ndata: null\n\n"

    func testParserReadsCompleteEvents() {
        var parser = SSEParser()
        let events = parser.feed(putEvent + keepAlive)
        XCTAssertEqual(events, [
            SSEEvent(event: "put", data: "{\"path\":\"/\",\"data\":null}"),
            SSEEvent(event: "keep-alive", data: "null")
        ])
    }

    func testParserNeedsABlankLineBeforeAnEventIsComplete() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed("event: put\n").isEmpty)
        XCTAssertTrue(parser.feed("data: hallo\n").isEmpty)
        XCTAssertEqual(parser.feed("\n"), [SSEEvent(event: "put", data: "hallo")])
    }

    func testParserHandlesChunksBreakingAnywhere() {
        let text = putEvent + keepAlive + "event: put\ndata: {\"path\":\"/\",\"data\":{\"a\":\"café 💶 €\"}}\n\n"
        var whole = SSEParser()
        let expected = whole.feed(text)
        XCTAssertEqual(expected.count, 3)

        let bytes = Array(text.utf8)
        // Elke mogelijke breukplek, ook midden in een regel en midden in een teken van meerdere bytes.
        for split in 0...bytes.count {
            var parser = SSEParser()
            var events = parser.feed(Data(bytes[0..<split]))
            events += parser.feed(Data(bytes[split...]))
            XCTAssertEqual(events, expected, "breuk na byte \(split)")
        }

        // En byte voor byte.
        var single = SSEParser()
        var collected: [SSEEvent] = []
        for byte in bytes { collected += single.feed(Data([byte])) }
        XCTAssertEqual(collected, expected)
        XCTAssertTrue(collected[2].data.contains("café 💶 €"))
    }

    func testParserAcceptsAllLineEndings() {
        let crlf = "event: put\r\ndata: een\r\n\r\n"
        let cr = "event: put\rdata: twee\r\r"
        var parser = SSEParser()
        XCTAssertEqual(parser.feed(crlf), [SSEEvent(event: "put", data: "een")])
        XCTAssertEqual(parser.feed(cr), [SSEEvent(event: "put", data: "twee")])

        // CR en LF in aparte stukjes tellen als één regeleinde.
        var split = SSEParser()
        var events = split.feed("event: put\r")
        events += split.feed("\ndata: drie\r")
        events += split.feed("\n\r")
        events += split.feed("\n")
        XCTAssertEqual(events, [SSEEvent(event: "put", data: "drie")])
    }

    func testParserIgnoresCommentsAndUnknownFieldsAndJoinsDataLines() {
        var parser = SSEParser()
        let events = parser.feed(": dit is commentaar\nid: 42\nretry: 1000\nevent: put\ndata: regel1\ndata:regel2\ndata: regel3\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "put", data: "regel1\nregel2\nregel3")])
    }

    func testParserDefaultsToMessageAndSkipsEventsWithoutData() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: zonder naam\n\n"), [SSEEvent(event: "message", data: "zonder naam")])
        XCTAssertTrue(parser.feed("event: leeg\n\n").isEmpty)
        // De naam van een lege gebeurtenis lekt niet door naar de volgende.
        XCTAssertEqual(parser.feed("data: nog een\n\n"), [SSEEvent(event: "message", data: "nog een")])
    }

    func testParserResetDropsAPartialEvent() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed("event: put\ndata: half").isEmpty)
        parser.reset()
        XCTAssertEqual(parser.feed("data: heel\n\n"), [SSEEvent(event: "message", data: "heel")])
    }

    func testParserHandlesALargeDocumentInSmallChunks() {
        let payload = String(repeating: "abcdefghij", count: 200_000)   // 2 MB
        let text = "event: put\ndata: \(payload)\n\n"
        var parser = SSEParser()
        var events: [SSEEvent] = []
        let bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            let end = min(index + 1000, bytes.count)
            events += parser.feed(Data(bytes[index..<end]))
            index = end
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data.count, payload.count)
    }

    // MARK: Berichten van de database

    private func message(_ event: String, _ data: String) -> FirebaseStreamMessage {
        FirebaseStreamMessage.interpret(SSEEvent(event: event, data: data))
    }

    func testStreamMessagesAreInterpreted() throws {
        XCTAssertEqual(message("keep-alive", "null"), .keepAlive)
        XCTAssertEqual(message("cancel", "null"), .cancel)
        XCTAssertEqual(message("auth_revoked", "credential is no longer valid"), .authRevoked)
        XCTAssertEqual(message("iets-anders", "x"), .unknown("iets-anders"))
        XCTAssertEqual(message("put", "geen json"), .unknown("put"))

        // Document verwijderd of nog niet aanwezig.
        XCTAssertEqual(message("put", #"{"path":"/","data":null}"#), .snapshot(nil))

        // Het hele document.
        let finance = cloudFinance(modified: cloudAt(77))
        let text = try FirebaseDatabaseClient.encodeFinance(finance)
        let escaped = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
        let full = message("put", #"{"path":"/","data":{"data":\#(escaped),"modifiedAt":1790000077000,"device":"iPad (ab12)","schema":1}}"#)
        guard case .snapshot(let snapshot?) = full else { return XCTFail("Verwachtte een snapshot, kreeg \(full)") }
        XCTAssertEqual(snapshot.device, "iPad (ab12)")
        XCTAssertEqual(snapshot.modifiedAt, Date(timeIntervalSince1970: 1_790_000_077))
        XCTAssertEqual(snapshot.json, text)
        XCTAssertNil(snapshot.etag)
        XCTAssertEqual(try snapshot.decodeFinance(), finance)

        // Een deel van het document, of iets anders dan het hele document: opnieuw ophalen.
        XCTAssertEqual(message("put", #"{"path":"/modifiedAt","data":5}"#), .partialChange)
        XCTAssertEqual(message("put", #"{"path":"/data","data":"tekst"}"#), .partialChange)
        XCTAssertEqual(message("put", #"{"path":"/","data":{"modifiedAt":5}}"#), .partialChange)
        XCTAssertEqual(message("put", #"{"path":"/","data":"zomaar"}"#), .partialChange)
        XCTAssertEqual(message("patch", #"{"path":"/","data":{"modifiedAt":5}}"#), .partialChange)
        XCTAssertEqual(message("patch", #"{"path":"/","data":{"data":"x","modifiedAt":1,"device":"d","schema":1}}"#), .partialChange)
    }

    // MARK: Staat op het apparaat

    func testSyncStateRoundTripsThroughAFile() throws {
        let directory = try cloudTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSyncStateStore.standard(directory: directory, uid: "uid123")
        XCTAssertEqual(store.url.lastPathComponent, "cloud-uid123.json")
        XCTAssertEqual(store.load(), SyncState())

        let state = SyncState(lastSyncedStamp: cloudT0.addingTimeInterval(0.123), lastSyncedAt: cloudAt(9.5))
        store.save(state)
        XCTAssertEqual(store.load(), state)

        try Data("kapot".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), SyncState())

        store.save(state)
        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertEqual(store.load(), SyncState())
    }

    func testMemoryStateStore() {
        let store = MemorySyncStateStore(SyncState(lastSyncedStamp: cloudT0, lastSyncedAt: nil))
        XCTAssertEqual(store.load().lastSyncedStamp, cloudT0)
        store.save(SyncState(lastSyncedStamp: nil, lastSyncedAt: cloudT0))
        XCTAssertEqual(store.saveCount, 1)
        store.clear()
        XCTAssertEqual(store.load(), SyncState())
    }

    // MARK: Back-ups bij een conflict

    func testBackupFileNamesAndContent() throws {
        let directory = try cloudTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConflictBackupStore(directory: directory, uid: "uid123")
        let finance = cloudFinance(salary: 4242, modified: cloudAt(3))

        let local = try XCTUnwrap(store.save(finance, side: .local, at: cloudT0))
        XCTAssertEqual(local.lastPathComponent, "finance-uid123.backup-lokaal-20260921-141320.json")
        let cloud = try XCTUnwrap(store.save(finance, side: .cloud, at: cloudT0))
        XCTAssertEqual(cloud.lastPathComponent, "finance-uid123.backup-cloud-20260921-141320.json")

        // Een back-up is een gewoon, terug te zetten gegevensbestand.
        guard case .loaded(let loaded) = FinanceStorage(url: local).load() else { return XCTFail("Back-up hoort te laden") }
        XCTAssertEqual(loaded, finance)

        // Nog een back-up in dezelfde seconde overschrijft de eerste niet.
        let again = try XCTUnwrap(store.save(finance, side: .local, at: cloudT0))
        XCTAssertEqual(again.lastPathComponent, "finance-uid123.backup-lokaal-20260921-141320-2.json")
        XCTAssertEqual(store.backups(side: .local).count, 2)
        XCTAssertEqual(store.backups(side: .cloud).count, 1)
    }

    func testBackupsKeepOnlyTheNewestFivePerSide() throws {
        let directory = try cloudTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConflictBackupStore(directory: directory, uid: "uid123")
        for index in 0..<7 {
            store.save(cloudFinance(salary: Double(1000 + index)), side: .local, at: cloudAt(Double(index * 10)))
        }
        store.save(cloudFinance(), side: .cloud, at: cloudT0)

        let kept = store.backups(side: .local)
        XCTAssertEqual(kept.count, 5)
        XCTAssertEqual(kept.first?.lastPathComponent, "finance-uid123.backup-lokaal-20260921-141420.json")
        XCTAssertEqual(store.backups(side: .cloud).count, 1)

        // De nieuwste staat bovenaan en bevat de laatste gegevens.
        guard case .loaded(let newest) = FinanceStorage(url: kept[0]).load() else { return XCTFail("Hoort te laden") }
        XCTAssertEqual(newest.salary.fixedMonthly, 1006)

        store.removeAll()
        XCTAssertTrue(store.backups(side: .local).isEmpty)
        XCTAssertTrue(store.backups(side: .cloud).isEmpty)
    }

    func testBackupOfAnotherUserIsNotTouched() throws {
        let directory = try cloudTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mine = ConflictBackupStore(directory: directory, uid: "uid1")
        let other = ConflictBackupStore(directory: directory, uid: "uid2")
        mine.save(cloudFinance(), side: .local, at: cloudT0)
        other.save(cloudFinance(), side: .local, at: cloudT0)
        mine.removeAll()
        XCTAssertTrue(mine.backups(side: .local).isEmpty)
        XCTAssertEqual(other.backups(side: .local).count, 1)
    }

    // MARK: Lokale gegevens die mee kunnen

    func testLocalDataFileNames() {
        let uuid = UUID().uuidString
        XCTAssertTrue(LocalDataFinder.isLocalDataFileName("finance.json"))
        XCTAssertTrue(LocalDataFinder.isLocalDataFileName("finance-\(uuid).json"))
        for name in ["finance-xYz9AbC0dEfGhIjKlMnOpQrStUvW.json", "finance-uid123.backup-lokaal-20260921-141320.json",
                     "finance.corrupt-1790000000.json", "accounts.json", "cloud-uid123.json", "finance-.json", "finance-\(uuid).txt"] {
            XCTAssertFalse(LocalDataFinder.isLocalDataFileName(name), name)
        }
    }

    func testFinderReturnsOnlyReadableFilesWithContentNewestFirst() throws {
        let directory = try cloudTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = FinanceStorage.makeEncoder()
        func write(_ name: String, _ finance: FinanceData) throws {
            try encoder.encode(finance).write(to: directory.appendingPathComponent(name))
        }
        let older = UUID().uuidString
        let newer = UUID().uuidString
        let empty = UUID().uuidString
        try write("finance.json", cloudFinance(salary: 1, modified: cloudAt(0)))
        try write("finance-\(older).json", cloudFinance(salary: 2, modified: cloudAt(100)))
        try write("finance-\(newer).json", cloudFinance(salary: 3, modified: Date().addingTimeInterval(3600)))
        try write("finance-\(empty).json", cloudPristine())
        try write("finance-xYz9AbC0dEfGhIjKlMnOpQrStUvW.json", cloudFinance(salary: 4))      // cloudaccount
        try write("finance-uid123.backup-lokaal-20260921-141320.json", cloudFinance(salary: 5)) // back-up
        try Data("kapot".utf8).write(to: directory.appendingPathComponent("finance-\(UUID().uuidString).json"))

        let found = LocalDataFinder.find(in: directory)
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(found.map { $0.data.salary.fixedMonthly }.first, 3, "De nieuwste staat eerst")
        XCTAssertEqual(Set(found.map { $0.data.salary.fixedMonthly }), [1, 2, 3])
        XCTAssertEqual(LocalDataFinder.find(in: directory.appendingPathComponent("bestaat-niet")).count, 0)
    }
}
