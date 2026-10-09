import XCTest
@testable import MyBuddyCore

/// Het lokale bestand is compact (snel te schrijven), maar oude opgemaakte bestanden blijven leesbaar.
/// De cloud, de back-up en het vergelijken van gegevens houden hun opgemaakte codering.
final class FileStorageTests: XCTestCase {
    private func tempURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mybuddy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("finance.json")
    }

    private func sample() -> FinanceData {
        FinanceData.sample(now: day(oct2026, 12))
    }

    /// Dezelfde gegevens als tekst in de opgemaakte codering (datums zijn tot op de seconde afgerond, dus
    /// vergelijken met `==` op de gegevens zelf zou vals verschil geven).
    private func canonical(_ data: FinanceData) throws -> Data {
        try FinanceStorage.makeEncoder().encode(data)
    }

    func testSavedFileIsCompactWithSortedKeys() throws {
        let url = try tempURL()
        let storage = FinanceStorage(url: url)
        let data = sample()
        try storage.save(data)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("\n"), "geen regeleinden: compact")
        XCTAssertFalse(text.contains("  "), "geen inspringing")
        XCTAssertTrue(text.hasPrefix("{\""))
        // Vaste volgorde van sleutels.
        let first = try XCTUnwrap(text.range(of: "\"appliedAccelerators\""))
        let second = try XCTUnwrap(text.range(of: "\"startMonth\""))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
        // Twee keer opslaan geeft precies hetzelfde bestand.
        let bytes = try Data(contentsOf: url)
        try storage.save(data)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testCompactFileIsSmallerThanThePrettyOne() throws {
        let data = sample()
        let compact = try FinanceStorage.makeFileEncoder().encode(data)
        let pretty = try FinanceStorage.makeEncoder().encode(data)
        XCTAssertLessThan(compact.count, pretty.count)
    }

    func testRoundTripOfTheCompactFile() throws {
        let url = try tempURL()
        let storage = FinanceStorage(url: url)
        let original = sample()
        try storage.save(original)
        guard case .loaded(let loaded) = storage.load() else { return XCTFail("kon niet laden") }
        XCTAssertEqual(try canonical(loaded), try canonical(original))
        XCTAssertEqual(loaded.goals, original.goals)
        XCTAssertEqual(loaded.pots.count, original.pots.count)
    }

    func testAnOldPrettyPrintedFileStillLoads() throws {
        let url = try tempURL()
        let original = sample()
        // Zo schreven eerdere versies het bestand.
        let pretty = try FinanceStorage.makeEncoder().encode(original)
        XCTAssertTrue(String(decoding: pretty, as: UTF8.self).contains("\n  \""), "het oude bestand is opgemaakt")
        try pretty.write(to: url)

        let storage = FinanceStorage(url: url)
        guard case .loaded(let loaded) = storage.load() else { return XCTFail("verwachtte .loaded") }
        XCTAssertEqual(try canonical(loaded), pretty)
        XCTAssertEqual(loaded.goals, original.goals)

        // Na de volgende wijziging staat er een compact bestand, met dezelfde inhoud.
        var changed = loaded
        changed.settings.inflation = 0.031
        try storage.save(changed)
        let rewritten = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(rewritten.contains("\n"))
        guard case .loaded(let again) = storage.load() else { return XCTFail("verwachtte .loaded") }
        XCTAssertEqual(again.settings.inflation, 0.031, accuracy: 1e-12)
        XCTAssertEqual(again.pots.count, original.pots.count)
    }

    func testCloudAndBackupEncodingStayPrettyPrinted() throws {
        let data = sample()
        let encoded = try FinanceStorage.makeEncoder().encode(data)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\n  \""), "opgemaakt, twee spaties inspringing")
        // Dezelfde bytes als wat de cloud verstuurt.
        XCTAssertEqual(try FirebaseDatabaseClient.encodeFinance(data), text)
        // Het lokale bestand en de cloud zijn dezelfde gegevens in een andere vorm.
        let file = try FinanceStorage.makeFileEncoder().encode(data)
        let fromFile = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: file)
        let fromCloud = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: encoded)
        XCTAssertEqual(try canonical(fromFile), try canonical(fromCloud))
        // De vingerafdruk en de vergelijking van de synchronisatie (die de opgemaakte codering gebruiken) zien na het
        // opslaan en weer inlezen van het compacte bestand geen verschil.
        XCTAssertNotNil(CloudSync.contentDigest(data))
        XCTAssertEqual(CloudSync.contentDigest(fromFile), CloudSync.contentDigest(data))
        XCTAssertTrue(CloudSync.contentEqual(fromFile, data))
    }
}
