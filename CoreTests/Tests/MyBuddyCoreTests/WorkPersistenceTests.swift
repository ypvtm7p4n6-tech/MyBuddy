import XCTest
import Foundation
@testable import MyBuddyCore

/// Het opslagformaat van de werkuren (docs/work/plan.md par. 3.3 en B20): een bestand zonder werkuren blijft byte voor byte gelijk, de
/// instellingen worden alleen geschreven als ze iets zeggen, onleesbare delen worden overgeslagen, de afgeleide diensten bewaren alleen
/// begin en einde, en de synchronisatie laat de diensten (een eigen kopie van de agenda per apparaat) buiten de vergelijking.
final class WorkPersistenceTests: XCTestCase {
    private let cal = YearMonth.calendar
    private let oct = YearMonth(year: 2026, month: 10)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }
    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
    private func decode(_ json: String) throws -> FinanceData { try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(json.utf8)) }

    /// Een dataset met uren uit de agenda: afwijkende regels, een eigen agendanaam en een snapshot met drie diensten.
    private func agendaData() -> FinanceData {
        var d = FinanceData(startMonth: oct)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 15, hoursPerWeek: 24, payDay: 25)
        d.work.hoursSource = .calendar
        d.work.calendarTitle = "Rooster"
        d.work.periodBasis = .previous
        d.work.allDayShiftHours = 8
        d.work.rules.combine = .add
        d.work.rules.payRules.append(PayRule(id: StableID.uuid("work-test|saturday"), kind: .weekday(7), factor: 1.25))
        d.work.rules.breakRules.append(BreakRule(id: StableID.uuid("work-test|break10"), fromHours: 10, minutes: 45))
        d.work.rules.holidays.enabled.insert(.goodFriday)
        d.work.rules.holidays.custom = [day(2026, 12, 5)]
        let shifts = [engShift(engDate(cal, 2026, 10, 5, 9), engDate(cal, 2026, 10, 5, 17)),
                      engShift(engDate(cal, 2026, 10, 6, 22), engDate(cal, 2026, 10, 7, 6)),
                      engShift(engDate(cal, 2026, 10, 9, 9), engDate(cal, 2026, 10, 9, 13))]
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 11, 3), from: day(2026, 7, 24), through: day(2027, 11, 4), title: "Rooster")
        return d
    }

    // MARK: Een bestand zonder werkuren

    func testAFileWithoutWorkHoursHasNoWorkKeyAndStaysByteIdentical() throws {
        let legacy = verdelenFixtureLegacyData()
        XCTAssertEqual(legacy.work, WorkSettings())
        XCTAssertEqual(text(try FinanceStorage.makeFileEncoder().encode(legacy)), VerdelenLegacyOutput.compact)
        XCTAssertEqual(text(try FinanceStorage.makeEncoder().encode(legacy)), VerdelenLegacyOutput.pretty)
        XCTAssertFalse(text(try FinanceStorage.makeFileEncoder().encode(legacy)).contains("\"work\""))
        // Werkuren aanzetten voegt alleen de sleutel `work` toe; weer uitzetten brengt het bestand byte voor byte terug.
        var d = legacy
        d.work.hoursSource = .calendar
        let withWork = text(try FinanceStorage.makeFileEncoder().encode(d))
        XCTAssertTrue(withWork.contains("\"work\":{\"hoursSource\":\"calendar\"}"), withWork)
        XCTAssertEqual(withWork.replacingOccurrences(of: ",\"work\":{\"hoursSource\":\"calendar\"}", with: ""), VerdelenLegacyOutput.compact)
        d.work = WorkSettings()
        XCTAssertEqual(text(try FinanceStorage.makeFileEncoder().encode(d)), VerdelenLegacyOutput.compact)
    }

    func testTheKeysOfAFileWithWorkHoursAreTheOldKeysPlusWork() throws {
        let raw = try FinanceStorage.makeFileEncoder().encode(agendaData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertTrue(object.keys.contains("work"))
        XCTAssertFalse(object.keys.contains("salaryChanges"))
        let work = try XCTUnwrap(object["work"] as? [String: Any])
        XCTAssertEqual(Set(work.keys), ["hoursSource", "calendarTitle", "periodBasis", "allDayShiftHours", "rules", "snapshot"])
    }

    func testDefaultWorkSettingsWriteNothing() throws {
        XCTAssertEqual(text(try JSONEncoder().encode(WorkSettings())), "{}")
        var settings = WorkSettings()
        settings.calendarTitle = "werken"
        XCTAssertEqual(text(try JSONEncoder().encode(settings)), "{}", "de standaardnaam wordt niet geschreven")
        settings.allDayShiftHours = 6
        XCTAssertEqual(text(try JSONEncoder().encode(settings)), #"{"allDayShiftHours":6}"#)
        settings.allDayShiftHours = .nan
        XCTAssertNoThrow(try JSONEncoder().encode(settings), "een onmogelijk aantal uren zet het bewaren niet stil")
        XCTAssertEqual(text(try JSONEncoder().encode(settings)), "{}")
    }

    // MARK: Rondreis

    func testWorkHoursRoundTripThroughTheFileTheBackupAndTheCloudEncoding() throws {
        let d = agendaData()
        for encoder in [FinanceStorage.makeFileEncoder(), FinanceStorage.makeEncoder()] {
            let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: try encoder.encode(d))
            XCTAssertEqual(back.work, d.work)
            XCTAssertEqual(back, d)
            XCTAssertEqual(back.salaryAmount(in: oct), d.salaryAmount(in: oct))
        }
        let raw = try BackupService.export(d, now: Date(timeIntervalSince1970: 1_800_000_000))
        let imported = try BackupService.importBackup(raw)
        XCTAssertEqual(imported.work, d.work)
        XCTAssertEqual(imported.work.snapshot?.shifts.count, 3)
        XCTAssertEqual(try FinanceStorage.makeEncoder().encode(imported), try FinanceStorage.makeEncoder().encode(d))
    }

    func testWorkHoursSurviveTheLocalFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mybuddy-work-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let storage = FinanceStorage(url: url)
        let d = agendaData()
        try storage.save(d)
        guard case .loaded(let back) = storage.load() else { return XCTFail("het bestand laadt niet") }
        XCTAssertEqual(back, d)
        XCTAssertEqual(back.work.snapshot?.fetchedDay, day(2026, 11, 3))
        XCTAssertEqual(back.salaryAmount(in: oct), d.salaryAmount(in: oct), "de uitbetaling na het laden is dezelfde")
    }

    func testASnapshotAloneIsWrittenSoTheShiftsSurviveARestart() throws {
        var d = FinanceData(startMonth: oct)
        d.work.snapshot = engSnapshot([engShift(engDate(cal, 2026, 10, 5, 9), engDate(cal, 2026, 10, 5, 17))], fetched: day(2026, 11, 3))
        XCTAssertFalse(d.work.hasUserContent)
        XCTAssertNotEqual(d.work, WorkSettings(), "de snapshot telt wel voor het bewaren")
        let encoded = text(try FinanceStorage.makeFileEncoder().encode(d))
        XCTAssertTrue(encoded.contains("\"work\":{\"snapshot\":{"), encoded)
        XCTAssertEqual(try decode(encoded).work.snapshot?.shifts.count, 1)
    }

    // MARK: Alleen begin en einde

    func testTheSnapshotStoresOnlyTheBeginAndEndOfShiftsAndNoText() throws {
        let raw = try FinanceStorage.makeFileEncoder().encode(agendaData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let snapshot = try XCTUnwrap((object["work"] as? [String: Any])?["snapshot"] as? [String: Any])
        XCTAssertEqual(Set(snapshot.keys), ["shifts", "from", "through", "fetchedDay", "calendarTitle"], "geen titel, notitie, plaats of deelnemer")
        let shifts = try XCTUnwrap(snapshot["shifts"] as? [[Int]])
        XCTAssertEqual(shifts.count, 3)
        XCTAssertTrue(shifts.allSatisfy { $0.count == 2 && $0[1] > $0[0] }, "elke dienst is [begin, einde]")
        XCTAssertEqual(snapshot["fetchedDay"] as? String, "2026-11-03")
        XCTAssertEqual(snapshot["calendarTitle"] as? String, "Rooster")
        // De grootte: ruim onder de 40 bytes per dienst.
        let list = text(try JSONEncoder().encode(shifts.map { try? WorkShift(startMinute: $0[0], endMinute: $0[1]) ?? nil }.compactMap { $0 }))
        XCTAssertLessThan(list.utf8.count / 3, 40)
    }

    func testTheSnapshotIsSortedAndMergedWhenRead() throws {
        let json = #"{"shifts":[[300,400],[100,200],[150,250],[100,200]],"from":"2026-07-24","through":"2027-11-04","fetchedDay":"2026-11-03","calendarTitle":"werken"}"#
        let snapshot = try JSONDecoder().decode(WorkSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.shifts.map { [$0.startMinute, $0.endMinute] }, [[100, 250], [300, 400]])
        XCTAssertEqual(WorkSnapshot(shifts: [WorkShift(startMinute: 5, endMinute: 9)!, WorkShift(startMinute: 1, endMinute: 6)!],
                                    from: day(2026, 1, 1), through: day(2026, 12, 31), fetchedDay: day(2026, 6, 1), calendarTitle: "x").shifts.count, 1)
    }

    // MARK: Mild lezen

    func testUnreadableWorkGivesTheDefaultsAndTheRestOfTheFileLoads() throws {
        var text = text(try FinanceStorage.makeFileEncoder().encode(verdelenFixtureLegacyData()))
        text = text.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"work\":\"kapot\"")
        let loaded = try decode(text)
        XCTAssertEqual(loaded.work, WorkSettings())
        XCTAssertEqual(loaded, verdelenFixtureLegacyData())
        // Een werkblok van een nieuwere versie met onbekende keuzes valt per veld terug op de standaard.
        let newer = try decode(self.text(try FinanceStorage.makeFileEncoder().encode(verdelenFixtureLegacyData()))
            .replacingOccurrences(of: "\"version\":1", with: #""version":1,"work":{"hoursSource":"nieuw","periodBasis":"anders","calendarTitle":5,"rules":{"combine":"x"},"allDayShiftHours":"veel"}"#))
        XCTAssertEqual(newer.work, WorkSettings())
    }

    func testAnUnreadableSnapshotKeepsTheSettings() throws {
        var settings = try JSONDecoder().decode(WorkSettings.self, from: Data(#"{"hoursSource":"calendar","calendarTitle":"Rooster","snapshot":{"from":"kapot"}}"#.utf8))
        XCTAssertEqual(settings.hoursSource, .calendar)
        XCTAssertEqual(settings.calendarTitle, "Rooster")
        XCTAssertNil(settings.snapshot)
        settings = try JSONDecoder().decode(WorkSettings.self, from: Data(#"{"snapshot":{"from":"2026-07-24","through":"2027-11-04"}}"#.utf8))
        XCTAssertNil(settings.snapshot, "zonder dag van verversen is het geen snapshot")
        settings = try JSONDecoder().decode(WorkSettings.self, from: Data(#"{"snapshot":{"from":"2026-07-24","through":"2027-11-04","fetchedDay":"2026-11-03","shifts":[[1,2],[9]," x"]}}"#.utf8))
        XCTAssertEqual(settings.snapshot?.shifts.count, 1, "de leesbare dienst blijft")
        XCTAssertEqual(settings.snapshot?.calendarTitle, "")
    }

    func testAllDayHoursAreClampedWhenRead() throws {
        XCTAssertEqual(try JSONDecoder().decode(WorkSettings.self, from: Data(#"{"allDayShiftHours":99}"#.utf8)).allDayShiftHours, 16)
        XCTAssertEqual(try JSONDecoder().decode(WorkSettings.self, from: Data(#"{"allDayShiftHours":0}"#.utf8)).allDayShiftHours, 0.25)
        XCTAssertNil(try JSONDecoder().decode(WorkSettings.self, from: Data("{}".utf8)).allDayShiftHours)
        XCTAssertNil(try JSONDecoder().decode(WorkSettings.self, from: Data(#"{"allDayShiftHours":"x"}"#.utf8)).allDayShiftHours)
    }

    // MARK: Gebruikersinhoud, synchronisatie en de lege start

    func testHasUserContentIgnoresTheSnapshotButSeesEverythingTheUserSet() {
        var settings = WorkSettings()
        XCTAssertFalse(settings.hasUserContent)
        settings.snapshot = engSnapshot([], fetched: day(2026, 11, 3))
        XCTAssertFalse(settings.hasUserContent, "de diensten komen vanzelf uit de agenda")
        for change: (inout WorkSettings) -> Void in [
            { $0.hoursSource = .calendar }, { $0.calendarTitle = "Rooster" }, { $0.periodBasis = .previous }, { $0.allDayShiftHours = 8 },
            { $0.rules.combine = .add }, { $0.rules.breakRules = [] }, { $0.rules.holidays.custom = [CalendarDay(year: 2026, month: 12, day: 5)] }
        ] {
            var changed = WorkSettings()
            change(&changed)
            XCTAssertTrue(changed.hasUserContent)
        }
    }

    func testTheContentChecksSeeWorkSettingsAndWageChangesButNotTheShifts() {
        var d = FinanceData(startMonth: oct)
        XCTAssertTrue(d.isEmptyStart)
        XCTAssertFalse(CloudSync.hasContent(d))
        d.work.snapshot = engSnapshot([engShift(engDate(cal, 2026, 10, 5, 9), engDate(cal, 2026, 10, 5, 17))], fetched: day(2026, 11, 3))
        XCTAssertTrue(d.isEmptyStart, "alleen afgeleide diensten: nog niets ingevuld")
        XCTAssertFalse(CloudSync.hasContent(d))
        d.work.hoursSource = .calendar
        XCTAssertFalse(d.isEmptyStart)
        XCTAssertTrue(CloudSync.hasContent(d))
        var e = FinanceData(startMonth: oct)
        e.work.rules.combine = .add
        XCTAssertFalse(e.isEmptyStart)
        XCTAssertTrue(CloudSync.hasContent(e))
        var f = FinanceData(startMonth: oct)
        f.setSalaryChange(SalaryChange(from: oct, hourlyRate: 16))
        XCTAssertFalse(f.isEmptyStart, "een loonwijziging is inhoud")
        XCTAssertTrue(CloudSync.hasContent(f))
    }

    func testWithoutMarketDataDropsTheSnapshotButKeepsTheSettings() {
        let d = agendaData()
        let stripped = CloudSync.withoutMarketData(d)
        XCTAssertNil(stripped.work.snapshot)
        var expected = d.work
        expected.snapshot = nil
        XCTAssertEqual(stripped.work, expected, "bron, naam, periode en regels blijven")
        XCTAssertNotNil(d.work.snapshot, "het origineel blijft ongemoeid")
    }

    func testTwoDevicesThatOnlyDifferInTheirAgendaHaveTheSameDigest() {
        let a = agendaData()
        var b = agendaData()
        b.work.snapshot = engSnapshot([engShift(engDate(cal, 2026, 10, 13, 9), engDate(cal, 2026, 10, 13, 12))], fetched: day(2026, 11, 4))
        XCTAssertNotEqual(a.work, b.work)
        XCTAssertEqual(CloudSync.contentDigest(a), CloudSync.contentDigest(b), "geen conflict door een eigen verversing van de agenda")
        var c = agendaData()
        c.work.rules.combine = .highest
        XCTAssertNotEqual(CloudSync.contentDigest(a), CloudSync.contentDigest(c), "een andere regel is wel een verschil")
        var e = agendaData()
        e.work.calendarTitle = "werken"
        XCTAssertNotEqual(CloudSync.contentDigest(a), CloudSync.contentDigest(e))
    }
}
