import XCTest
import Foundation
@testable import MyBuddyCore

/// Het opslagformaat van de nieuwe verdeelmogelijkheden (docs/work/plan2.md par. 2.7 en 3.2): zonder extra bedrag, extra overschrijfdata,
/// bankrij of doel met meer potten is het bestand byte voor byte gelijk aan vroeger; elke nieuwe sleutel wordt alleen geschreven als
/// hij iets zegt, mild gelezen en rondgereisd via `FinanceStorage` en `BackupService`.
final class DistributionPersistenceTests: XCTestCase {
    private func decode(_ json: String) throws -> FinanceData {
        try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(json.utf8))
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // MARK: Het oude formaat blijft byte voor byte gelijk

    func testLegacyDataEncodesByteForByteLikeBeforeTheDistributionRound() throws {
        let data = verdelenFixtureLegacyData()
        XCTAssertNotNil(data.startDay, "de vaste dataset heeft een startdatum midden in de maand")
        XCTAssertEqual(text(try FinanceStorage.makeEncoder().encode(data)), VerdelenLegacyOutput.pretty,
                       "de opgemaakte codering (cloud, back-up, vergelijken) is veranderd")
        XCTAssertEqual(text(try FinanceStorage.makeFileEncoder().encode(data)), VerdelenLegacyOutput.compact,
                       "de compacte codering (het lokale bestand) is veranderd")
    }

    func testLegacyOutputDecodesToTheSameDataAndEncodesAgainIdentically() throws {
        let data = verdelenFixtureLegacyData()
        for legacy in [VerdelenLegacyOutput.pretty, VerdelenLegacyOutput.compact] {
            let loaded = try decode(legacy)
            XCTAssertEqual(loaded, data)
            XCTAssertEqual(text(try FinanceStorage.makeEncoder().encode(loaded)), VerdelenLegacyOutput.pretty)
            XCTAssertEqual(text(try FinanceStorage.makeFileEncoder().encode(loaded)), VerdelenLegacyOutput.compact)
        }
    }

    func testTheBackupOfLegacyDataStillHoldsTheSameFinanceData() throws {
        let data = verdelenFixtureLegacyData()
        let raw = try BackupService.export(data, now: Date(timeIntervalSince1970: 1_800_000_000))
        let envelope = text(raw)
        for key in ["bankShare", "contributionExtra", "extraTransfers", "transferParts", "morePotIDs", "\"extra\""] {
            XCTAssertFalse(envelope.contains(key), "een back-up zonder de nieuwe functies noemt \(key) niet")
        }
        let back = try BackupService.importBackup(raw)
        XCTAssertEqual(back, data)
        XCTAssertEqual(try FinanceStorage.makeEncoder().encode(back), try FinanceStorage.makeEncoder().encode(data))
    }

    func testTheKeysOfLegacyDataAreExactlyTheOldKeys() throws {
        let raw = try FinanceStorage.makeFileEncoder().encode(verdelenFixtureLegacyData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let expected: Set<String> = ["appliedAccelerators", "bankEntries", "bankSnapshots", "goals", "holdings", "homeHoldingIDs",
                                     "homePotIDs", "modifiedAt", "months", "potEntries", "pots", "salary", "settings", "startDay",
                                     "startMonth", "version"]
        XCTAssertEqual(Set(object.keys), expected)
    }

    // MARK: Alle nieuwe sleutels

    private let mar = YearMonth(year: 2026, month: 3)
    private let apr = YearMonth(year: 2026, month: 4)
    private let may = YearMonth(year: 2026, month: 5)

    /// De dataset van het oude formaat met elke nieuwe functie erin: een extra bedrag (standaard en in één maand), extra overschrijfdata
    /// (standaard, in één maand en als lege afwijking), een bankrij (standaard en in één maand) en een doel met twee potten.
    private func richData() -> FinanceData {
        var d = verdelenFixtureLegacyData()
        let buffer = verdelenFixtureID(1), holiday = verdelenFixtureID(2), world = verdelenFixtureID(4)
        d.setContributionPercent(holiday, percent: 5, basis: .allIncome, extra: 25, current: mar)
        d.setStandardTransferParts(buffer, parts: [TransferPart(day: 10, amount: 40), TransferPart(day: 20, amount: 15)], current: mar)
        d.holdings[0].contributionExtra = 12.5
        d.holdings[0].extraTransfers = [TransferPart(day: 3, amount: 10)]
        d.setTransferParts(buffer, in: apr, parts: [])
        d.setTransferParts(holiday, in: may, parts: [TransferPart(day: 31, amount: 5)])
        d.setContributionAmount(BankShare.id, amount: 300, current: mar)
        d.setAllocationPercent(BankShare.id, in: apr, percent: 10, basis: .salary, extra: 5)
        d.setAllocationPercent(world, in: may, percent: 7.5, basis: .allIncome, extra: 12)
        d.goals[0].setFundingPots([holiday, buffer])
        return d
    }

    private func jsonObject(_ data: FinanceData) throws -> [String: Any] {
        let raw = try FinanceStorage.makeFileEncoder().encode(data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
    }

    func testEveryNewKeyIsWrittenWhenItSaysSomethingAndOnlyThen() throws {
        let object = try jsonObject(richData())
        let pots = try XCTUnwrap(object["pots"] as? [[String: Any]])
        XCTAssertNotNil(pots[0]["extraTransfers"], "de buffer heeft extra overschrijfdata")
        XCTAssertNil(pots[0]["contributionExtra"])
        XCTAssertEqual(pots[1]["contributionExtra"] as? Double, 25)
        XCTAssertNil(pots[1]["extraTransfers"])
        XCTAssertNil(pots[2]["contributionExtra"], "een pot zonder extra bedrag schrijft de sleutel niet")
        XCTAssertNil(pots[2]["extraTransfers"])
        let holdings = try XCTUnwrap(object["holdings"] as? [[String: Any]])
        XCTAssertEqual(holdings[0]["contributionExtra"] as? Double, 12.5)
        XCTAssertNotNil(holdings[0]["extraTransfers"])
        XCTAssertNil(holdings[1]["contributionExtra"])
        XCTAssertNil(holdings[1]["extraTransfers"])
        let bank = try XCTUnwrap(object["bankShare"] as? [String: Any])
        XCTAssertEqual(Set(bank.keys), ["monthlyContribution"], "alleen wat afwijkt van niets")
        let months = try XCTUnwrap(object["months"] as? [String: [String: Any]])
        let parts = try XCTUnwrap(months["2026-04"]?["transferParts"] as? [String: [Any]])
        XCTAssertEqual(parts[verdelenFixtureID(1).uuidString]?.count, 0, "een lege lijst is een afwijking en wordt wel geschreven")
        XCTAssertNil(months["2026-03"]?["transferParts"], "een maand zonder eigen delen schrijft de sleutel niet")
        let percent = try XCTUnwrap(months["2026-05"]?["percentAllocations"] as? [String: [String: Any]])
        XCTAssertEqual(percent[verdelenFixtureID(4).uuidString]?["extra"] as? Double, 12)
        let plain = try XCTUnwrap(months["2026-04"]?["percentAllocations"] as? [String: [String: Any]])
        XCTAssertNotNil(plain[verdelenFixtureID(3).uuidString], "de Auto-pot heeft in april een eigen percentage")
        XCTAssertNil(plain[verdelenFixtureID(3).uuidString]?["extra"], "een percentage zonder extra bedrag schrijft de sleutel niet")
        let synced = try XCTUnwrap(months["2026-03"]?["percentAllocations"] as? [String: [String: Any]])
        XCTAssertEqual(synced[verdelenFixtureID(2).uuidString]?["extra"] as? Double, 25, "de lopende maand kreeg de nieuwe standaard mee")
        let goals = try XCTUnwrap(object["goals"] as? [[String: Any]])
        XCTAssertEqual((goals[0]["morePotIDs"] as? [String])?.count, 1)
        XCTAssertNil(goals[1]["morePotIDs"])
        XCTAssertNil(goals[2]["morePotIDs"])
    }

    func testAFileWithAllTheNewKeysRoundTripsThroughFinanceStorage() throws {
        let data = richData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mybuddy-verdelen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = FinanceStorage(url: dir.appendingPathComponent("finance.json"))
        try storage.save(data)
        guard case .loaded(let loaded) = storage.load() else { return XCTFail("kon niet laden") }
        XCTAssertEqual(loaded, data)
        XCTAssertEqual(try FinanceStorage.makeFileEncoder().encode(loaded), try FinanceStorage.makeFileEncoder().encode(data))
        XCTAssertEqual(try FinanceStorage.makeEncoder().encode(loaded), try FinanceStorage.makeEncoder().encode(data))
        XCTAssertEqual(loaded.pots[0].extraTransfers, [TransferPart(day: 10, amount: 40), TransferPart(day: 20, amount: 15)])
        XCTAssertEqual(loaded.pots[1].contributionExtra, 25)
        XCTAssertEqual(loaded.holdings[0].extraTransfers, [TransferPart(day: 3, amount: 10)])
        XCTAssertEqual(loaded.months[apr.key]?.transferParts[verdelenFixtureID(1).uuidString], [])
        XCTAssertEqual(loaded.months[may.key]?.transferParts[verdelenFixtureID(2).uuidString], [TransferPart(day: 31, amount: 5)])
        XCTAssertEqual(loaded.bankShare.monthlyContribution, 300)
        XCTAssertEqual(loaded.goals[0].fundingPotIDs, [verdelenFixtureID(2), verdelenFixtureID(1)])
        // De rekenmotor geeft op de teruggelezen gegevens hetzelfde als op het origineel.
        for month in [mar, apr, may] {
            XCTAssertEqual(loaded.monthFigures(month), data.monthFigures(month), month.key)
        }
    }

    func testTheBackupRoundTripsEveryNewKey() throws {
        let data = richData()
        let raw = try BackupService.export(data, now: Date(timeIntervalSince1970: 1_800_000_000))
        let envelope = text(raw)
        for key in ["bankShare", "contributionExtra", "extraTransfers", "transferParts", "morePotIDs", "\"extra\""] {
            XCTAssertTrue(envelope.contains(key), "de back-up noemt \(key)")
        }
        let back = try BackupService.importBackup(raw)
        XCTAssertEqual(back, data)
        XCTAssertEqual(try FinanceStorage.makeEncoder().encode(back), try FinanceStorage.makeEncoder().encode(data))
    }

    func testAnUnreadablePartIsSkippedAndTheRestStays() throws {
        let buffer = verdelenFixtureID(1).uuidString
        var json = text(try FinanceStorage.makeFileEncoder().encode(richData()))
        let good = "[{\"amount\":40,\"day\":10},{\"amount\":15,\"day\":20}]"
        XCTAssertTrue(json.contains(good))
        let broken = "[{\"amount\":40,\"day\":10},\"kapot\",{\"amount\":\"veel\",\"day\":12},{\"day\":\"tien\",\"amount\":9},{\"amount\":15,\"day\":20}]"
        json = json.replacingOccurrences(of: good, with: broken)
        let loaded = try decode(json)
        XCTAssertEqual(loaded.pots[0].extraTransfers, [TransferPart(day: 10, amount: 40), TransferPart(day: 20, amount: 15)])
        // Hetzelfde voor de delen van één maand; een sleutel waarvan de waarde geen lijst is wordt overgeslagen (de maand volgt dan de
        // standaard van die pot).
        let monthGood = "\"transferParts\":{\"\(verdelenFixtureID(2).uuidString)\":[{\"amount\":5,\"day\":31}]}"
        XCTAssertTrue(json.contains(monthGood))
        let monthBroken = "\"transferParts\":{\"\(verdelenFixtureID(2).uuidString)\":[null,{\"amount\":5,\"day\":31},7],\"\(buffer)\":\"geen lijst\"}"
        let loadedMonth = try decode(json.replacingOccurrences(of: monthGood, with: monthBroken))
        XCTAssertEqual(loadedMonth.months[may.key]?.transferParts[verdelenFixtureID(2).uuidString], [TransferPart(day: 31, amount: 5)])
        XCTAssertNil(loadedMonth.months[may.key]?.transferParts[buffer], "de sleutel zonder lijst is overgeslagen")
        // Alles wat er mee gerekend wordt, rekent door.
        XCTAssertEqual(loadedMonth.pots.count, 3)
        XCTAssertTrue(loadedMonth.monthLedger(may).allReconciles)
    }

    func testAnUnreadableNewFieldNeverMakesTheFileUnreadable() throws {
        let original = text(try FinanceStorage.makeFileEncoder().encode(richData()))
        let data = richData()
        func variant(_ old: String, _ new: String) throws -> FinanceData {
            XCTAssertTrue(original.contains(old), old)
            return try decode(original.replacingOccurrences(of: old, with: new))
        }
        // Het bankdeel.
        let bankText = "\"bankShare\":{\"monthlyContribution\":300}"
        XCTAssertEqual(try variant(bankText, "\"bankShare\":\"kapot\"").bankShare, BankShare())
        XCTAssertEqual(try variant(bankText, "\"bankShare\":{\"monthlyContribution\":\"veel\"}").bankShare.monthlyContribution, 0)
        // Het extra bedrag van een pot, een belegging en een percentageregel.
        XCTAssertEqual(try variant("\"contributionExtra\":25", "\"contributionExtra\":\"veel\"").pots[1].contributionExtra, 0)
        XCTAssertEqual(try variant("\"contributionExtra\":12.5", "\"contributionExtra\":[1]").holdings[0].contributionExtra, 0)
        let ruleLoaded = try variant("\"extra\":12", "\"extra\":\"veel\"")
        XCTAssertEqual(ruleLoaded.months[may.key]?.percentAllocations[verdelenFixtureID(4).uuidString]?.extra, 0)
        // De extra potten van een doel: een lijst die geen lijst is, of een id dat geen id is.
        let moreText = "\"morePotIDs\":[\"\(verdelenFixtureID(1).uuidString)\"]"
        XCTAssertEqual(try variant(moreText, "\"morePotIDs\":\"kapot\"").goals[0].fundingPotIDs, [verdelenFixtureID(2)])
        XCTAssertEqual(try variant(moreText, "\"morePotIDs\":[\"geen-id\"]").goals[0].morePotIDs, nil)
        XCTAssertEqual(try variant(moreText, "\"morePotIDs\":[\"geen-id\",\"\(verdelenFixtureID(1).uuidString)\"]").goals[0].fundingPotIDs,
                       data.goals[0].fundingPotIDs, "het id dat wel te lezen is blijft")
        // Al het andere in het bestand blijft zoals het was.
        let loaded = try variant(moreText, "\"morePotIDs\":\"kapot\"")
        XCTAssertEqual(loaded.pots, data.pots)
        XCTAssertEqual(loaded.months, data.months)
        XCTAssertEqual(loaded.goals[1], data.goals[1])
    }

    func testAnOlderAppDropsTheNewKeysAndTheRestStillReads() throws {
        // Een oudere versie kent de sleutels niet en laat ze weg bij opslaan: de rest van het bestand blijft leesbaar en is het oude formaat.
        var object = try jsonObject(richData())
        let newKeys: Set<String> = ["bankShare", "contributionExtra", "extraTransfers", "transferParts", "morePotIDs", "extra"]
        func strip(_ value: Any) -> Any {
            if let dictionary = value as? [String: Any] {
                var result: [String: Any] = [:]
                for (key, inner) in dictionary where !newKeys.contains(key) { result[key] = strip(inner) }
                return result
            }
            if let list = value as? [Any] { return list.map { strip($0) } }
            return value
        }
        object = try XCTUnwrap(strip(object) as? [String: Any])
        let raw = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let old = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: raw)
        XCTAssertEqual(old.bankShare, BankShare())
        XCTAssertTrue(old.pots.allSatisfy { $0.extraTransfers.isEmpty && $0.contributionExtra == 0 })
        XCTAssertTrue(old.holdings.allSatisfy { $0.extraTransfers.isEmpty && $0.contributionExtra == 0 })
        XCTAssertTrue(old.months.values.allSatisfy { $0.transferParts.isEmpty })
        XCTAssertEqual(old.goals[0].fundingPotIDs, [verdelenFixtureID(2)], "een doel met meer potten is voor een oudere app een doel met één pot")
        XCTAssertEqual(old.goals[0].funding, .pot(verdelenFixtureID(2)))
        XCTAssertEqual(old.salary, verdelenFixtureLegacyData().salary)
        XCTAssertEqual(old.startDay, verdelenFixtureLegacyData().startDay)
        // Zonder de nieuwe velden is de codering weer het oude formaat: dezelfde sleutels als de vastgelegde uitvoer.
        let again = try jsonObject(old)
        XCTAssertEqual(Set(again.keys), Set(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(VerdelenLegacyOutput.compact.utf8)) as? [String: Any]).keys))
        XCTAssertFalse(text(try FinanceStorage.makeFileEncoder().encode(old)).contains("extraTransfers"))
    }

    func testTheMarketDataCleanUpAndTheContentChecksKeepTheNewFields() throws {
        let data = richData()
        let cleaned = CloudSync.withoutMarketData(data)
        XCTAssertEqual(cleaned.bankShare, data.bankShare)
        XCTAssertEqual(cleaned.pots, data.pots)
        XCTAssertEqual(cleaned.months, data.months)
        XCTAssertEqual(cleaned.goals, data.goals)
        XCTAssertEqual(cleaned.holdings[0].extraTransfers, data.holdings[0].extraTransfers)
        XCTAssertEqual(cleaned.holdings[0].contributionExtra, data.holdings[0].contributionExtra)
        XCTAssertTrue(CloudSync.hasContent(data))
        XCTAssertFalse(data.isEmptyStart)
    }

    func testTheFileEncodersKeepTheKeysSorted() throws {
        let compact = text(try FinanceStorage.makeFileEncoder().encode(richData()))
        func position(_ key: String) -> Int {
            guard let range = compact.range(of: "\"\(key)\":") else { return -1 }
            return compact.distance(from: compact.startIndex, to: range.lowerBound)
        }
        XCTAssertGreaterThan(position("bankShare"), position("bankEntries"))
        XCTAssertLessThan(position("bankShare"), position("bankSnapshots"))
        XCTAssertEqual(text(try FinanceStorage.makeFileEncoder().encode(richData())), compact, "twee keer coderen geeft dezelfde bytes")
    }

    func testTheCSVExportIgnoresTheBankShareAndTheExtraDays() {
        // De csv-export ("Over" is `remaining`) rekent met wat op de rekening blijft: een bankdeel is een toewijzing zonder beweging en
        // extra overschrijfdata veranderen alleen de dag, dus de bestanden zijn gelijk.
        let plain = verdelenFixtureLegacyData()
        var changed = plain
        changed.setContributionAmount(BankShare.id, amount: 300, current: mar)
        changed.setAllocation(BankShare.id, in: apr, amount: 123)
        changed.setStandardTransferParts(verdelenFixtureID(1), parts: [TransferPart(day: 10, amount: 40)], current: mar)
        changed.setTransferParts(verdelenFixtureID(5), in: apr, parts: [TransferPart(day: 2, amount: 10)])
        XCTAssertEqual(CSVExport.monthlyCSV(changed, from: mar, count: 3, current: mar), CSVExport.monthlyCSV(plain, from: mar, count: 3, current: mar))
        XCTAssertEqual(CSVExport.transactionsCSV(changed), CSVExport.transactionsCSV(plain))
        XCTAssertEqual(CSVExport.holdingsCSV(changed, current: mar), CSVExport.holdingsCSV(plain, current: mar))
        XCTAssertEqual(changed.monthFigures(apr).remaining, plain.monthFigures(apr).remaining)
        XCTAssertEqual(changed.monthFigures(apr).toBank, 12_300)
    }
}
