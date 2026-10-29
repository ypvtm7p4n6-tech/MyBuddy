import XCTest
import Foundation
@testable import MyBuddyCore

/// Het model van de startdatum (docs/work/plan.md par. 2.2 en 2.4): `FinanceData.startDay`, het opslagformaat (zonder startdatum
/// byte voor byte gelijk aan vroeger), lenient lezen, `setStart(_:)` en de eerste dag die meetelt.
final class StartDateModelTests: XCTestCase {
    private func decode(_ json: String) throws -> FinanceData {
        try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(json.utf8))
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    private func tempURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mybuddy-start-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("finance.json")
    }

    // MARK: Het oude formaat blijft byte voor byte gelijk

    func testLegacyDataEncodesByteForByteLikeBeforeTheStartDate() throws {
        let data = startFixtureLegacyData()
        XCTAssertNil(data.startDay)
        XCTAssertEqual(text(try FinanceStorage.makeEncoder().encode(data)), StartDateLegacyOutput.pretty,
                       "de opgemaakte codering (cloud, back-up, vergelijken) is veranderd")
        XCTAssertEqual(text(try FinanceStorage.makeFileEncoder().encode(data)), StartDateLegacyOutput.compact,
                       "de compacte codering (het lokale bestand) is veranderd")
    }

    func testLegacyOutputDecodesToTheSameDataAndEncodesAgainIdentically() throws {
        let data = startFixtureLegacyData()
        for legacy in [StartDateLegacyOutput.pretty, StartDateLegacyOutput.compact] {
            let loaded = try decode(legacy)
            XCTAssertEqual(loaded, data)
            XCTAssertNil(loaded.startDay)
            XCTAssertEqual(text(try FinanceStorage.makeEncoder().encode(loaded)), StartDateLegacyOutput.pretty)
            XCTAssertEqual(text(try FinanceStorage.makeFileEncoder().encode(loaded)), StartDateLegacyOutput.compact)
        }
    }

    func testTheBackupOfLegacyDataStillHoldsTheSameFinanceData() throws {
        let data = startFixtureLegacyData()
        let raw = try BackupService.export(data, now: Date(timeIntervalSince1970: 1_800_000_000))
        let envelope = text(raw)
        XCTAssertFalse(envelope.contains("startDay"), "een back-up zonder startdatum noemt hem niet")
        let back = try BackupService.importBackup(raw)
        XCTAssertEqual(back, data)
        // De gegevens in de back-up zijn de opgemaakte codering van de gegevens, ingesprongen onder "data".
        XCTAssertEqual(try FinanceStorage.makeEncoder().encode(back), try FinanceStorage.makeEncoder().encode(data))
    }

    func testTheKeysOfLegacyDataAreExactlyTheOldKeys() throws {
        let raw = try FinanceStorage.makeFileEncoder().encode(startFixtureLegacyData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let expected: Set<String> = ["appliedAccelerators", "bankEntries", "bankSnapshots", "goals", "holdings", "homeHoldingIDs",
                                     "homePotIDs", "modifiedAt", "months", "potEntries", "pots", "salary", "settings", "startMonth",
                                     "version"]
        XCTAssertEqual(Set(object.keys), expected)
    }

    // MARK: Opslaan en lezen met een startdatum

    func testAStartDayIsWrittenOnlyWhenItIsSet() throws {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        XCTAssertFalse(text(try FinanceStorage.makeFileEncoder().encode(data)).contains("startDay"))
        data.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        let compact = text(try FinanceStorage.makeFileEncoder().encode(data))
        XCTAssertTrue(compact.contains("\"startDay\":\"2026-10-15\""), compact)
        XCTAssertTrue(text(try FinanceStorage.makeEncoder().encode(data)).contains("\"startDay\" : \"2026-10-15\""))
    }

    func testAStartDayAddsExactlyOneKeyToTheLegacyKeys() throws {
        var data = startFixtureLegacyData()
        data.setStart(CalendarDay(year: 2026, month: 9, day: 12))
        let raw = try FinanceStorage.makeFileEncoder().encode(data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(object["startDay"] as? String, "2026-09-12")
        XCTAssertEqual(object["startMonth"] as? String, "2026-09")
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(StartDateLegacyOutput.compact.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys).subtracting(["startDay"]), Set(legacy.keys))
    }

    func testRoundTripThroughFinanceStorage() throws {
        var data = startFixtureLegacyData()
        data.setStart(CalendarDay(year: 2026, month: 9, day: 12))
        let storage = FinanceStorage(url: try tempURL())
        try storage.save(data)
        guard case .loaded(let loaded) = storage.load() else { return XCTFail("kon niet laden") }
        XCTAssertEqual(loaded.startDay, CalendarDay(year: 2026, month: 9, day: 12))
        XCTAssertEqual(loaded.startMonth, YearMonth(year: 2026, month: 9))
        XCTAssertEqual(loaded, data)
    }

    func testRoundTripThroughTheBackup() throws {
        var data = startFixtureLegacyData()
        data.setStart(CalendarDay(year: 2026, month: 9, day: 12))
        let raw = try BackupService.export(data, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(text(raw).contains("\"startDay\" : \"2026-09-12\""))
        let back = try BackupService.importBackup(raw)
        XCTAssertEqual(back.startDay, CalendarDay(year: 2026, month: 9, day: 12))
        XCTAssertEqual(back, data)
    }

    func testRoundTripThroughBothEncoders() throws {
        var data = startFixtureLegacyData()
        data.setStart(CalendarDay(year: 2026, month: 9, day: 30))
        for encoder in [FinanceStorage.makeEncoder(), FinanceStorage.makeFileEncoder()] {
            let loaded = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: try encoder.encode(data))
            XCTAssertEqual(loaded, data)
            XCTAssertEqual(loaded.effectiveStartDay, CalendarDay(year: 2026, month: 9, day: 30))
        }
    }

    func testCloudComparisonSeesAChangedStartDay() {
        let base = startFixtureLegacyData()
        var started = base
        started.setStart(CalendarDay(year: 2026, month: 9, day: 12))
        XCTAssertTrue(CloudSync.contentEqual(base, base))
        XCTAssertFalse(CloudSync.contentEqual(base, started), "een andere startdatum is een echt verschil")
        XCTAssertNotEqual(CloudSync.contentDigest(base), CloudSync.contentDigest(started))
        XCTAssertEqual(CloudSync.contentDigest(started), CloudSync.contentDigest(started))
    }

    // MARK: Lenient lezen

    func testAMissingStartDayLeavesTheStartMonthAlone() throws {
        let data = try decode(#"{"startMonth":"2026-08","version":1}"#)
        XCTAssertNil(data.startDay)
        XCTAssertEqual(data.startMonth, YearMonth(year: 2026, month: 8))
        XCTAssertNil(data.effectiveStartDay)
        XCTAssertEqual(data.firstDay, CalendarDay(year: 2026, month: 8, day: 1))
    }

    func testAnUnreadableStartDayIsIgnoredAndTheFileStillLoads() throws {
        for bad in ["\"kapot\"", "12345", "\"2026-13-45\"", "\"2026-02-30\"", "null", "{}", "[1]", "\"26-10-15\""] {
            let data = try decode("{\"startMonth\":\"2026-08\",\"startDay\":\(bad),\"version\":1}")
            XCTAssertNil(data.startDay, "startDay \(bad) hoort genegeerd te worden")
            XCTAssertEqual(data.startMonth, YearMonth(year: 2026, month: 8), "startMonth blijft bij startDay \(bad)")
        }
    }

    func testAStartDayInsideTheStartMonthIsKept() throws {
        let data = try decode(#"{"startMonth":"2026-10","startDay":"2026-10-15","version":1}"#)
        XCTAssertEqual(data.startDay, CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(data.effectiveStartDay, CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(data.startMonth, YearMonth(year: 2026, month: 10))
    }

    func testAStartDayOutsideTheStartMonthMakesTheStartMonthFollowTheDay() throws {
        let data = try decode(#"{"startMonth":"2026-08","startDay":"2026-10-15","version":1}"#)
        XCTAssertEqual(data.startDay, CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(data.startMonth, YearMonth(year: 2026, month: 10), "startDay.yearMonth == startMonth, altijd")
        XCTAssertEqual(data.effectiveStartDay, data.startDay)
        // Zonder startmaand in het bestand ook.
        let bare = try decode(#"{"startDay":"2027-01-03"}"#)
        XCTAssertEqual(bare.startMonth, YearMonth(year: 2027, month: 1))
    }

    func testAStartDayLeftBehindByADirectStartMonthChangeDoesNotApplyAndIsNotSaved() throws {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        data.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        data.startMonth = YearMonth(year: 2026, month: 6)   // rechtstreeks gezet: de startdatum geldt niet meer
        XCTAssertNotNil(data.startDay)
        XCTAssertNil(data.effectiveStartDay)
        XCTAssertNil(data.startDate)
        XCTAssertEqual(data.firstDay, CalendarDay(year: 2026, month: 6, day: 1))
        XCTAssertNil(data.startCutoff)
        XCTAssertEqual(data.firstCountedDay(in: YearMonth(year: 2026, month: 10)), 1)
        XCTAssertFalse(text(try FinanceStorage.makeFileEncoder().encode(data)).contains("startDay"))
    }

    // MARK: setStart

    func testSetStartSetsTheDayAndTheStartMonth() {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        data.setStart(CalendarDay(year: 2026, month: 11, day: 3))
        XCTAssertEqual(data.startDay, CalendarDay(year: 2026, month: 11, day: 3))
        XCTAssertEqual(data.startMonth, YearMonth(year: 2026, month: 11))
        XCTAssertEqual(data.effectiveStartDay, CalendarDay(year: 2026, month: 11, day: 3))
        XCTAssertEqual(data.firstDay, CalendarDay(year: 2026, month: 11, day: 3))
        // Een eerdere datum werkt ook.
        data.setStart(CalendarDay(year: 2026, month: 8, day: 20))
        XCTAssertEqual(data.startMonth, YearMonth(year: 2026, month: 8))
        XCTAssertEqual(data.firstDay, CalendarDay(year: 2026, month: 8, day: 20))
    }

    func testSetStartIsIdempotent() {
        var data = startFixtureLegacyData()
        data.setStart(CalendarDay(year: 2026, month: 10, day: 7))
        let once = data
        data.setStart(CalendarDay(year: 2026, month: 10, day: 7))
        XCTAssertEqual(data, once)
    }

    func testSetStartFreezesTheImplicitAnchorOfAWeeklySalary() {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        data.salary = SalarySettings(mode: .fixed, fixedMonthly: 1_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        data.salary.setSchedule(.weeks, interval: 2)
        XCTAssertNil(data.salary.anchor, "zonder eigen anker volgt het anker de startmaand")
        let november = YearMonth(year: 2026, month: 11)
        let december = YearMonth(year: 2026, month: 12)
        let before = [november, december].map { data.salaryPayDays(in: $0) }
        let anchorBefore = data.salaryAnchor()
        data.setStart(CalendarDay(year: 2026, month: 11, day: 10))
        XCTAssertEqual(data.salary.anchor, anchorBefore, "het impliciete anker (de salarisdag van de oude startmaand) is vastgezet")
        XCTAssertEqual(data.salaryAnchor(), anchorBefore)
        XCTAssertEqual([november, december].map { data.salaryPayDays(in: $0) }, before, "de uitbetalingen schuiven niet")
    }

    func testSetStartKeepsAnExplicitAnchorAndLeavesAMonthlySalaryAlone() {
        var weekly = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        weekly.salary.setSchedule(.days, interval: 10, anchor: CalendarDay(year: 2026, month: 9, day: 3))
        weekly.setStart(CalendarDay(year: 2026, month: 12, day: 1))
        XCTAssertEqual(weekly.salary.anchor, CalendarDay(year: 2026, month: 9, day: 3))
        var monthly = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        monthly.setStart(CalendarDay(year: 2026, month: 12, day: 1))
        XCTAssertNil(monthly.salary.anchor, "het maandelijkse schema heeft geen anker")
        XCTAssertEqual(monthly.salary, SalarySettings())
    }

    func testTheStartDateForAPickerIsNoonOfTheStartDay() throws {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        XCTAssertNil(data.startDate)
        data.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        let date = try XCTUnwrap(data.startDate)
        let cal = YearMonth.calendar
        XCTAssertEqual(cal.component(.hour, from: date), 12)
        XCTAssertEqual(CalendarDay(date: date, calendar: cal), CalendarDay(year: 2026, month: 10, day: 15))
    }

    func testEquatableSeesTheStartDay() {
        let base = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        var started = base
        started.setStart(CalendarDay(year: 2026, month: 10, day: 1))
        XCTAssertNotEqual(base, started, "een startdatum is een verschil, ook als hij op de eerste valt")
        var other = base
        other.setStart(CalendarDay(year: 2026, month: 10, day: 2))
        XCTAssertNotEqual(started, other)
    }

    // MARK: De eerste dag die meetelt

    func testFirstCountedDay() {
        let october = YearMonth(year: 2026, month: 10)
        var data = FinanceData(startMonth: october)
        // Zonder startdatum telt elke maand vanaf de 1e (de controles op startMonth houden eerdere maanden buiten beeld).
        for offset in -2...2 { XCTAssertEqual(data.firstCountedDay(in: october.adding(offset)), 1) }
        XCTAssertTrue(data.counts(day: 1, in: october.adding(-1)))
        data.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(data.firstCountedDay(in: october.adding(-1)), Int.max)
        XCTAssertEqual(data.firstCountedDay(in: october), 15)
        XCTAssertEqual(data.firstCountedDay(in: october.adding(1)), 1)
        XCTAssertEqual(data.firstCountedDay(in: october.adding(40)), 1)
        XCTAssertFalse(data.counts(day: 14, in: october))
        XCTAssertTrue(data.counts(day: 15, in: october))
        XCTAssertTrue(data.counts(day: 31, in: october))
        XCTAssertFalse(data.counts(day: 31, in: october.adding(-1)))
        XCTAssertTrue(data.counts(day: 1, in: october.adding(1)))
    }

    func testStartCutoffIsTheStartOfTheStartDay() throws {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        XCTAssertNil(data.startCutoff)
        data.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        let cutoff = try XCTUnwrap(data.startCutoff)
        let cal = YearMonth.calendar
        XCTAssertEqual(cutoff, cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 17)) ?? cutoff))
        XCTAssertEqual(cal.component(.hour, from: cutoff), 0)
        XCTAssertEqual(DayMath.dayNumber(of: cutoff, calendar: cal), 15)
    }

    func testCountedListsAreTheRawListsWithoutAStartDay() {
        let data = startFixtureLegacyData()
        XCTAssertEqual(data.countedBankEntries, data.bankEntries)
        XCTAssertEqual(data.countedPotEntries, data.potEntries)
        XCTAssertEqual(data.countedBankSnapshots, data.bankSnapshots)
        XCTAssertEqual(data.hiddenBankCount, 0)
        XCTAssertEqual(data.hiddenPotCount(), 0)
    }

    func testCountedListsLeaveOutWhatLiesBeforeTheStartDay() {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        let pot = Pot(name: "Buffer", startMonth: YearMonth(year: 2026, month: 10))
        data.pots = [pot]
        let cal = YearMonth.calendar
        func moment(_ day: Int, hour: Int = 12) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date()
        }
        data.addBankEntry(amount: 10, note: "vroeg", date: moment(14, hour: 23))
        data.addBankEntry(amount: 20, note: "begin van de startdag", date: cal.startOfDay(for: moment(15)))
        data.addBankEntry(amount: 30, note: "laat", date: moment(20))
        data.addBankSnapshot(balance: 100, note: "oud", date: moment(3))
        data.addBankSnapshot(balance: 200, note: "nieuw", date: moment(16))
        data.addPotEntry(potID: pot.id, amount: 40, kind: .deposit, note: "oud", date: moment(2))
        data.addPotEntry(potID: pot.id, amount: 50, kind: .deposit, note: "nieuw", date: moment(15))
        data.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(data.countedBankEntries.map { $0.note }, ["begin van de startdag", "laat"])
        XCTAssertEqual(data.countedBankSnapshots.map { $0.note }, ["nieuw"])
        XCTAssertEqual(data.countedPotEntries.map { $0.note }, ["nieuw"])
        // Alles blijft bewaard.
        XCTAssertEqual(data.bankEntries.count, 3)
        XCTAssertEqual(data.bankSnapshots.count, 2)
        XCTAssertEqual(data.potEntries.count, 2)
        XCTAssertEqual(data.hiddenBankCount, 2, "een boeking en een saldo")
        XCTAssertEqual(data.hiddenPotCount(), 1)
        XCTAssertEqual(data.hiddenPotCount(for: pot.id), 1)
        XCTAssertEqual(data.hiddenPotCount(for: UUID()), 0)
        let hidden = data.entriesBefore(CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(hidden.bank, 1)
        XCTAssertEqual(hidden.pots, 1)
        XCTAssertEqual(hidden.balances, 1)
        // Een eerdere startdatum brengt ze terug.
        data.setStart(CalendarDay(year: 2026, month: 10, day: 1))
        XCTAssertEqual(data.countedBankEntries.count, 3)
        XCTAssertEqual(data.countedBankSnapshots.count, 2)
        XCTAssertEqual(data.countedPotEntries.count, 2)
        XCTAssertEqual(data.hiddenBankCount, 0)
    }

    func testEntriesBeforeAnyDay() {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        let cal = YearMonth.calendar
        let when = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9)) ?? Date()
        data.addBankEntry(amount: 5, date: when)
        let before = data.entriesBefore(CalendarDay(year: 2026, month: 10, day: 10))
        XCTAssertEqual(before.bank, 0, "een boeking op de dag zelf ligt niet vóór die dag")
        XCTAssertEqual(data.entriesBefore(CalendarDay(year: 2026, month: 10, day: 11)).bank, 1)
        XCTAssertEqual(data.monthsDropped(by: CalendarDay(year: 2026, month: 12, day: 3)), 2)
        XCTAssertEqual(data.monthsDropped(by: CalendarDay(year: 2026, month: 10, day: 20)), 0)
        XCTAssertEqual(data.monthsDropped(by: CalendarDay(year: 2026, month: 3, day: 1)), 0)
    }

    // MARK: Een startdatum is geen gegevens

    func testAStartDayAloneIsNoContent() {
        var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
        data.setStart(CalendarDay(year: 2026, month: 11, day: 3))
        XCTAssertTrue(data.isEmptyStart)
        XCTAssertFalse(CloudSync.hasContent(data))
        XCTAssertTrue(CloudSync.isPristine(data))
    }
}
