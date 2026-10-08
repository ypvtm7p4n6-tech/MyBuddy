import XCTest
@testable import MyBuddyCore

// Vaste momenten, zodat geen enkele test van de klok afhangt.
// 1_791_460_800 = 2026-10-08 12:00:00 UTC, 1_791_502_200 = 2026-10-08 23:30:00 UTC, 1_767_614_400 = 2026-01-05 12:00:00 UTC.
private let exportMoment = Date(timeIntervalSince1970: 1_791_460_800)
private let exportLateMoment = Date(timeIntervalSince1970: 1_791_502_200)
private let exportJanuaryMoment = Date(timeIntervalSince1970: 1_767_614_400)

private func exportUTC() -> TimeZone { TimeZone(secondsFromGMT: 0)! }

private func exportAssertError(_ raw: Data, _ expected: BackupError,
                               file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try BackupService.importBackup(raw)
        XCTFail("Er had een fout moeten komen", file: file, line: line)
    } catch let error as BackupError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Onverwachte fout: \(error)", file: file, line: line)
    }
}

/// Geeft de tekst van een `.unreadable`-fout terug (en faalt bij elke andere uitkomst).
private func exportUnreadableDetail(_ raw: Data, file: StaticString = #filePath, line: UInt = #line) -> String {
    do {
        _ = try BackupService.importBackup(raw)
        XCTFail("Er had een fout moeten komen", file: file, line: line)
    } catch let error as BackupError {
        if case .unreadable(let detail) = error { return detail }
        XCTFail("Verwachtte .unreadable, kreeg \(error)", file: file, line: line)
    } catch {
        XCTFail("Onverwachte fout: \(error)", file: file, line: line)
    }
    return ""
}

/// Basisdata met een variabele post en een spaarpot, zodat alle kolommen van de maandtabel gevuld zijn.
private func exportMonthlyData() -> FinanceData {
    var d = makeBaseData()
    d.editPlan(aug2026) { plan in
        plan.expenses.append(MoneyLine(name: "Boodschappen", amount: 300, isRecurring: true, kind: .variable))
    }
    _ = addBufferPot(&d)
    return d
}

/// Boekingen op spaarpot en bankrekening, met lastige teksten in de omschrijving.
private func exportTransactionsData() -> FinanceData {
    var d = makeBaseData()
    let pot = addBufferPot(&d)
    d.addBankEntry(amount: 250, note: "Cadeau", date: day(sep2026, 5))
    d.transferBankToPot(potID: pot.id, amount: 75.5, date: day(sep2026, 10))
    d.addPotEntry(potID: pot.id, amount: -20, kind: .withdrawal, note: "=SOM(A1)", date: day(oct2026, 3))
    d.addBankEntry(amount: -12, note: "Pizza; \"extra\" kaas\nen bier", date: day(oct2026, 4))
    return d
}

private func exportHoldingsData() -> FinanceData {
    var d = makeBaseData()
    var etf = Holding(name: "Wereld ETF", kind: .etf, ticker: "VWCE.DE", units: 12.5, investedTotal: 1000,
                      expectedReturn: 0.06, annualCost: 0.002, monthlyContribution: 0, startMonth: aug2026)
    etf.lastPrice = 96.4
    d.addHolding(etf, initialValue: 1205, now: day(aug2026, 3))
    let other = Holding(name: "=Fonds; B", kind: .other, ticker: nil, units: nil, investedTotal: 0,
                        expectedReturn: 0.04, annualCost: 0.005, monthlyContribution: 0, startMonth: aug2026)
    d.addHolding(other)
    return d
}

private func exportLines(_ text: String) -> [String] {
    text.split(separator: "\n").map { String($0) }
}

// MARK: - Back-up (JSON)

final class BackupJSONTests: XCTestCase {
    func testRoundTripOfSampleDataKeepsCountsAndNumbers() throws {
        let now = day(oct2026, 10)
        let original = FinanceData.sample(now: now)
        let raw = try BackupService.export(original, now: now)
        let restored = try BackupService.importBackup(raw)

        XCTAssertEqual(restored.pots.count, 3)
        XCTAssertEqual(restored.holdings.count, 3)
        XCTAssertEqual(restored.goals.count, 2)
        XCTAssertEqual(restored.potEntries.count, original.potEntries.count)
        XCTAssertEqual(restored.months.count, original.months.count)
        XCTAssertEqual(restored.salary, original.salary)
        XCTAssertEqual(restored.settings, original.settings)
        XCTAssertEqual(restored.remaining(in: oct2026), original.remaining(in: oct2026), accuracy: 0.001)
        XCTAssertEqual(restored.totalSaved(current: oct2026), original.totalSaved(current: oct2026), accuracy: 0.001)
        XCTAssertEqual(restored.portfolioValue(current: oct2026), original.portfolioValue(current: oct2026), accuracy: 0.001)
        XCTAssertEqual(restored.bankBalanceNow(current: oct2026), original.bankBalanceNow(current: oct2026), accuracy: 0.001)
    }

    func testRoundTripOfBaseDataIsIdentical() throws {
        let base = makeBaseData()
        let restored = try BackupService.importBackup(try BackupService.export(base, now: exportMoment))
        XCTAssertEqual(restored, base)
    }

    func testExportWritesFormatVersionAndDate() throws {
        let raw = try BackupService.export(makeBaseData(), now: exportMoment)
        let envelope = try FinanceStorage.makeDecoder().decode(BackupEnvelope.self, from: raw)
        XCTAssertEqual(envelope.format, "mybuddy-backup")
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.appVersion, BackupService.appVersion)
        XCTAssertEqual(envelope.exportedAt, exportMoment)

        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.contains("2026-10-08T12:00:00Z"), "datums als ISO 8601")
        XCTAssertTrue(text.contains("\n"), "opgemaakt, niet op één regel")
    }

    func testExportIsDeterministic() throws {
        let base = makeBaseData()
        let first = try BackupService.export(base, now: exportMoment)
        let second = try BackupService.export(base, now: exportMoment)
        XCTAssertEqual(first, second, "vaste volgorde van sleutels")
    }

    func testInspectReportsDateAndCounts() throws {
        let now = day(oct2026, 10)
        let raw = try BackupService.export(FinanceData.sample(now: now), now: exportMoment)
        let contents = try BackupService.inspect(raw)
        XCTAssertEqual(contents.exportedAt, exportMoment)
        XCTAssertEqual(contents.appVersion, BackupService.appVersion)
        XCTAssertEqual(contents.potCount, 3)
        XCTAssertEqual(contents.holdingCount, 3)
        XCTAssertEqual(contents.goalCount, 2)
        XCTAssertEqual(contents.summaryText, "3 spaarpotten, 3 beleggingen")
    }

    func testCountTextUsesSingularAndPlural() {
        XCTAssertEqual(BackupContents.countText(0, one: "spaarpot", many: "spaarpotten"), "0 spaarpotten")
        XCTAssertEqual(BackupContents.countText(1, one: "spaarpot", many: "spaarpotten"), "1 spaarpot")
        XCTAssertEqual(BackupContents.countText(2, one: "belegging", many: "beleggingen"), "2 beleggingen")
    }

    func testBareFinanceDataIsAccepted() throws {
        // Zo ziet finance.json eruit: de gegevens zelf, zonder verpakking.
        let base = makeBaseData()
        let bare = try FinanceStorage.makeEncoder().encode(base)
        let contents = try BackupService.inspect(bare)
        XCTAssertEqual(contents.data, base)
        XCTAssertNil(contents.exportedAt)
        XCTAssertNil(contents.appVersion)
        XCTAssertEqual(try BackupService.importBackup(bare), base)
    }

    func testUTF8ByteOrderMarkIsIgnored() throws {
        // Eén keer aanmaken: elke aanroep van makeBaseData() geeft nieuwe id's.
        let base = makeBaseData()
        var raw = Data([0xEF, 0xBB, 0xBF])
        raw.append(try BackupService.export(base, now: exportMoment))
        XCTAssertEqual(try BackupService.importBackup(raw), base)
    }

    func testWrongFormatIsRejected() throws {
        let other = BackupEnvelope(format: "iets-anders", version: 1, exportedAt: exportMoment,
                                   appVersion: "1.0", data: makeBaseData())
        exportAssertError(try FinanceStorage.makeEncoder().encode(other), .notAMyBuddyFile)

        let zero = BackupEnvelope(format: BackupEnvelope.formatName, version: 0, exportedAt: exportMoment,
                                  appVersion: "1.0", data: makeBaseData())
        exportAssertError(try FinanceStorage.makeEncoder().encode(zero), .notAMyBuddyFile)
    }

    func testNewerVersionIsRejected() throws {
        let future = BackupEnvelope(format: BackupEnvelope.formatName, version: 2, exportedAt: exportMoment,
                                    appVersion: "9.0", data: makeBaseData())
        exportAssertError(try FinanceStorage.makeEncoder().encode(future), .newerVersion(2))

        var newerBare = makeBaseData()
        newerBare.version = 7
        exportAssertError(try FinanceStorage.makeEncoder().encode(newerBare), .newerVersion(7))
    }

    func testGarbageIsRejected() {
        exportAssertError(Data("dit is geen json".utf8), .notAMyBuddyFile)
        exportAssertError(Data(), .notAMyBuddyFile)
        exportAssertError(Data("[1, 2, 3]".utf8), .notAMyBuddyFile)
        exportAssertError(Data("\"alleen een tekst\"".utf8), .notAMyBuddyFile)
        exportAssertError(Data([0x00, 0xFF, 0xFE, 0x10]), .notAMyBuddyFile)
    }

    func testRandomJSONObjectDoesNotWipeData() {
        // FinanceData zelf leest `{}` zonder fout; de import mag dat nooit als lege gegevens accepteren.
        exportAssertError(Data("{}".utf8), .notAMyBuddyFile)
        exportAssertError(Data("{\"naam\": \"Jan\", \"pots\": []}".utf8), .notAMyBuddyFile)
    }

    func testBrokenContentIsUnreadable() {
        let envelope = """
        {"format":"mybuddy-backup","version":1,"exportedAt":"2026-10-08T12:00:00Z","appVersion":"1.0",
         "data":{"startMonth":"2026-08","pots":"kapot"}}
        """
        let detail = exportUnreadableDetail(Data(envelope.utf8))
        XCTAssertTrue(detail.contains("pots"), detail)

        let bare = "{\"startMonth\":\"geen-maand\"}"
        XCTAssertFalse(exportUnreadableDetail(Data(bare.utf8)).isEmpty)
    }

    func testOversizedFileIsRejected() {
        let huge = Data(count: BackupService.maxImportBytes + 1)
        XCTAssertFalse(exportUnreadableDetail(huge).isEmpty)
    }

    func testErrorMessagesAreFilledIn() {
        XCTAssertFalse((BackupError.notAMyBuddyFile.errorDescription ?? "").isEmpty)
        XCTAssertTrue((BackupError.newerVersion(3).errorDescription ?? "").contains("3"))
        XCTAssertTrue((BackupError.unreadable("Reden X").errorDescription ?? "").contains("Reden X"))
        XCTAssertEqual(BackupError.newerVersion(2), BackupError.newerVersion(2))
        XCTAssertNotEqual(BackupError.newerVersion(2), BackupError.newerVersion(3))
    }

    // MARK: Bestandsnaam

    func testSuggestedFileNameHasFixedFormat() {
        let utc = exportUTC()
        XCTAssertEqual(BackupService.suggestedFileName(now: exportMoment, timeZone: utc), "MyBuddy-back-up-2026-10-08.json")
        XCTAssertEqual(BackupService.suggestedBaseName(now: exportMoment, timeZone: utc), "MyBuddy-back-up-2026-10-08")
        XCTAssertEqual(BackupService.suggestedFileName(now: exportJanuaryMoment, timeZone: utc), "MyBuddy-back-up-2026-01-05.json")
        XCTAssertEqual(BackupService.dateStamp(exportMoment, timeZone: utc), "2026-10-08")
    }

    func testFileNameFollowsTheTimeZone() {
        let plusTwo = TimeZone(secondsFromGMT: 7200)!
        XCTAssertEqual(BackupService.suggestedFileName(now: exportLateMoment, timeZone: exportUTC()), "MyBuddy-back-up-2026-10-08.json")
        XCTAssertEqual(BackupService.suggestedFileName(now: exportLateMoment, timeZone: plusTwo), "MyBuddy-back-up-2026-10-09.json")
    }
}

// MARK: - CSV

final class CSVExportTests: XCTestCase {
    // MARK: Cellen

    func testPlainTextIsLeftAlone() {
        XCTAssertEqual(CSVExport.text("Boodschappen"), "Boodschappen")
        XCTAssertEqual(CSVExport.text(""), "")
        XCTAssertEqual(CSVExport.text("Cadeau voor mama (€ 25)"), "Cadeau voor mama (€ 25)")
        XCTAssertEqual(CSVExport.text("a=b"), "a=b")
    }

    func testSpecialCharactersAreQuoted() {
        XCTAssertEqual(CSVExport.text("a;b"), "\"a;b\"")
        XCTAssertEqual(CSVExport.text("zeg \"hoi\""), "\"zeg \"\"hoi\"\"\"")
        XCTAssertEqual(CSVExport.text("regel een\nregel twee"), "\"regel een\nregel twee\"")
        XCTAssertEqual(CSVExport.text("a\rb"), "\"a\rb\"")
        XCTAssertEqual(CSVExport.text("een, twee"), "een, twee", "een komma is geen scheiding")
    }

    func testFormulaInjectionGetsAnApostrophe() {
        XCTAssertEqual(CSVExport.text("=1+1"), "'=1+1")
        XCTAssertEqual(CSVExport.text("+31612345678"), "'+31612345678")
        XCTAssertEqual(CSVExport.text("-5% korting"), "'-5% korting")
        XCTAssertEqual(CSVExport.text("@SOM(A1)"), "'@SOM(A1)")
        XCTAssertEqual(CSVExport.text("\t=cmd"), "'\t=cmd")
        // Apostrof eerst, daarna pas de aanhalingstekens.
        XCTAssertEqual(CSVExport.text("=A1;B1"), "\"'=A1;B1\"")
    }

    func testNumbersUseCommaAndTwoDecimals() {
        XCTAssertEqual(CSVExport.number(1234.5), "1234,50")
        XCTAssertEqual(CSVExport.number(0), "0,00")
        XCTAssertEqual(CSVExport.number(-12), "-12,00")
        XCTAssertEqual(CSVExport.number(7.126), "7,13")
        XCTAssertEqual(CSVExport.number(7.124), "7,12")
        XCTAssertEqual(CSVExport.number(1_000_000), "1000000,00")
        XCTAssertEqual(CSVExport.number(-0.001), "0,00", "geen '-0,00'")
        XCTAssertEqual(CSVExport.number(Double.nan), "")
        XCTAssertEqual(CSVExport.number(Double.infinity), "")
    }

    func testFlexibleDecimalsTrimTrailingZeros() {
        XCTAssertEqual(CSVExport.decimal(12.5, maxDecimals: 8, minDecimals: 0), "12,5")
        XCTAssertEqual(CSVExport.decimal(40, maxDecimals: 8, minDecimals: 0), "40")
        XCTAssertEqual(CSVExport.decimal(0.02, maxDecimals: 8, minDecimals: 0), "0,02")
        XCTAssertEqual(CSVExport.decimal(0.00012345, maxDecimals: 8, minDecimals: 0), "0,00012345")
        XCTAssertEqual(CSVExport.decimal(96.4, maxDecimals: 4, minDecimals: 2), "96,40")
        XCTAssertEqual(CSVExport.decimal(3.7, maxDecimals: 0, minDecimals: 0), "4")
    }

    func testPercentIsWrittenWithSign() {
        XCTAssertEqual(CSVExport.percent(0.205), "20,50%")
        XCTAssertEqual(CSVExport.percent(-0.1), "-10,00%")
        XCTAssertEqual(CSVExport.percent(0), "0,00%")
    }

    func testCSVDataStartsWithByteOrderMark() {
        let data = CSVExport.csvData("a;€\n")
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(Array(data.dropFirst(3)), Array("a;€\n".utf8))
    }

    // MARK: Maandcijfers

    func testMonthlyCSVOnBaseData() {
        let csv = CSVExport.monthlyCSV(exportMonthlyData(), from: aug2026, count: 4, current: oct2026)
        let expected = [
            "Maand;Inkomen;Uitgaven vast;Uitgaven variabel;Gespaard;Belegd;Over;Verwacht ja/nee",
            "2026-08;3100,00;1050,00;300,00;200,00;0,00;1550,00;nee",
            "2026-09;3100,00;1000,00;300,00;200,00;0,00;1600,00;nee",
            "2026-10;3100,00;1000,00;300,00;200,00;0,00;1600,00;nee",
            "2026-11;3100,00;1000,00;300,00;200,00;0,00;1600,00;ja"
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(csv, expected)
    }

    func testMonthlyCSVWithoutPotsOrVariableExpenses() {
        let csv = CSVExport.monthlyCSV(makeBaseData(), from: aug2026, count: 3, current: oct2026)
        let expected = [
            "Maand;Inkomen;Uitgaven vast;Uitgaven variabel;Gespaard;Belegd;Over;Verwacht ja/nee",
            "2026-08;3100,00;1050,00;0,00;0,00;0,00;2050,00;nee",
            "2026-09;3100,00;1000,00;0,00;0,00;0,00;2100,00;nee",
            "2026-10;3100,00;1000,00;0,00;0,00;0,00;2100,00;nee"
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(csv, expected)
    }

    func testMonthlyCSVRowCountAndMonthsBeforeStart() {
        let base = makeBaseData()
        let jul2026 = YearMonth(year: 2026, month: 7)
        let two = exportLines(CSVExport.monthlyCSV(base, from: jul2026, count: 2, current: oct2026))
        XCTAssertEqual(two.count, 3)
        XCTAssertEqual(two[1], "2026-07;0,00;0,00;0,00;0,00;0,00;0,00;nee", "voor de startmaand is alles nul")
        XCTAssertTrue(two[2].hasPrefix("2026-08;3100,00;"))

        let none = exportLines(CSVExport.monthlyCSV(base, from: aug2026, count: 0, current: oct2026))
        XCTAssertEqual(none.count, 1, "alleen de kopregel")

        let year = exportLines(CSVExport.monthlyCSV(base, from: aug2026, count: 12, current: oct2026))
        XCTAssertEqual(year.count, 13)
        XCTAssertEqual(year.filter { $0.hasSuffix(";ja") }.count, 9, "nov 2026 t/m jul 2027 zijn verwacht")
    }

    func testEveryMonthlyRowHasEightColumns() {
        let csv = CSVExport.monthlyCSV(FinanceData.sample(now: day(oct2026, 10)), from: aug2026, count: 6, current: oct2026)
        for line in exportLines(csv) {
            XCTAssertEqual(line.split(separator: ";", omittingEmptySubsequences: false).count, 8, line)
        }
    }

    func testDefaultMonthRange() {
        let normal = CSVExport.defaultMonthRange(makeBaseData(), current: oct2026)
        XCTAssertEqual(normal.from, aug2026)
        XCTAssertEqual(normal.count, 15, "augustus 2026 t/m oktober 2027")

        let future = CSVExport.defaultMonthRange(FinanceData(startMonth: YearMonth(year: 2026, month: 11)), current: oct2026)
        XCTAssertEqual(future.from, oct2026, "een startmaand na nu telt niet")
        XCTAssertEqual(future.count, 13)

        let ancient = CSVExport.defaultMonthRange(FinanceData(startMonth: YearMonth(year: 1900, month: 1)), current: oct2026)
        XCTAssertEqual(ancient.count, 600)
        XCTAssertEqual(ancient.from.months(to: oct2026.adding(12)), 599)
    }

    // MARK: Transacties

    func testTransactionsCSVIsSortedEscapedAndSafe() {
        let csv = CSVExport.transactionsCSV(exportTransactionsData())
        let expected = [
            "Datum;Soort;Rekening of pot;Omschrijving;Bedrag",
            "2026-08-02;Beginsaldo;Buffer;;500,00",
            "2026-09-05;Geld erbij;Bankrekening;Cadeau;250,00",
            "2026-09-10;Gestort;Buffer;Van bankrekening;75,50",
            "2026-09-10;Naar spaarpot;Bankrekening;Naar Buffer;-75,50",
            "2026-10-03;Opgenomen;Buffer;'=SOM(A1);-20,00",
            "2026-10-04;Geld eraf;Bankrekening;\"Pizza; \"\"extra\"\" kaas",
            "en bier\";-12,00"
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(csv, expected)
    }

    func testTransactionsCSVOfEmptyDataIsOnlyAHeader() {
        let csv = CSVExport.transactionsCSV(FinanceData(startMonth: aug2026))
        XCTAssertEqual(csv, "Datum;Soort;Rekening of pot;Omschrijving;Bedrag\n")
    }

    func testTransactionsCSVUsesGivenTimeZone() {
        var d = FinanceData(startMonth: aug2026)
        let pot = Pot(name: "Buffer", startMonth: aug2026)
        d.addPot(pot, openingBalance: 100, now: exportLateMoment)
        let plusTwo = TimeZone(secondsFromGMT: 7200)!
        XCTAssertTrue(CSVExport.transactionsCSV(d, timeZone: exportUTC()).contains("2026-10-08;Beginsaldo;Buffer;;100,00"))
        XCTAssertTrue(CSVExport.transactionsCSV(d, timeZone: plusTwo).contains("2026-10-09;Beginsaldo;Buffer;;100,00"))
    }

    // MARK: Beleggingen

    func testHoldingsCSV() {
        let csv = CSVExport.holdingsCSV(exportHoldingsData(), current: oct2026)
        let expected = [
            "Naam;Soort;Ticker;Aantal;Koers;Waarde;Ingelegd;Rendement",
            "Wereld ETF;Indexfonds / ETF;VWCE.DE;12,5;96,40;1205,00;1000,00;20,50%",
            "\"'=Fonds; B\";Overig;;;;0,00;0,00;"
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(csv, expected)
    }

    // MARK: Rapporten

    func testReportsProduceTheirTables() {
        let sample = FinanceData.sample(now: day(oct2026, 10))
        XCTAssertEqual(CSVReport.allCases.count, 3)

        // Startmaand mei 2026 t/m oktober 2027 = 18 maanden.
        let monthly = exportLines(CSVReport.monthly.csv(for: sample, current: oct2026))
        XCTAssertEqual(monthly.count, 19)
        XCTAssertTrue(monthly[1].hasPrefix("2026-05;"))
        XCTAssertTrue(monthly[18].hasPrefix("2027-10;"))
        XCTAssertTrue(monthly[18].hasSuffix(";ja"))

        let transactions = exportLines(CSVReport.transactions.csv(for: sample, current: oct2026))
        XCTAssertEqual(transactions.count, 1 + sample.potEntries.count + sample.bankEntries.count)

        let holdings = exportLines(CSVReport.holdings.csv(for: sample, current: oct2026))
        XCTAssertEqual(holdings.count, 4)
    }

    func testReportOutputSurvivesABackupRoundTrip() throws {
        let now = day(oct2026, 10)
        let original = FinanceData.sample(now: now)
        let restored = try BackupService.importBackup(try BackupService.export(original, now: now))
        for report in CSVReport.allCases {
            XCTAssertEqual(report.csv(for: restored, current: oct2026), report.csv(for: original, current: oct2026), report.title)
        }
    }

    func testReportTitlesAndFileNames() {
        let utc = exportUTC()
        XCTAssertEqual(CSVReport.monthly.title, "Maandcijfers")
        XCTAssertEqual(CSVReport.transactions.title, "Transacties")
        XCTAssertEqual(CSVReport.holdings.title, "Beleggingen")
        XCTAssertEqual(CSVReport.monthly.baseFileName(now: exportMoment, timeZone: utc), "MyBuddy-maandcijfers-2026-10-08")
        XCTAssertEqual(CSVReport.transactions.baseFileName(now: exportMoment, timeZone: utc), "MyBuddy-transacties-2026-10-08")
        XCTAssertEqual(CSVReport.holdings.baseFileName(now: exportMoment, timeZone: utc), "MyBuddy-beleggingen-2026-10-08")
    }
}
