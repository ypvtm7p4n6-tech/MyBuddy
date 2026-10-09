import XCTest
import Foundation
@testable import MyBuddyCore

// Tests voor de grenzen van de werkmaplezer (XLSX.swift): hoeveel bladen, cellen en tekst we lezen, en dat een gemaakt
// bestand ons niet minutenlang bezig houdt. De twee bestanden die dit aan het licht brachten zijn hier nagebouwd:
// 1. een workbook.xml met honderden <sheet r:id="rId1"> naar één blad van 20.000 rijen (hing eerst meer dan 300 seconden);
// 2. een gedeelde tekst van 1 MB die 20.000 rijen gebruiken (hing eerst meer dan 120 seconden, elke cel trimde de hele tekst).
// De grenzen met lage waarden (`XLSXLimits`) laten zien wat er gebeurt als ze worden overschreden, zonder gigabytes te bouwen.

// MARK: - Bestanden bouwen

private let bxColumns = (0..<26).map { String(UnicodeScalar(UInt8(65 + $0))) }

private struct BXSheetRef {
    var name: String
    /// Welk werkblad (index in de lijst met bladinhoud) deze naam gebruikt.
    var target: Int
    var hidden = false
}

private let bxMain = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
private let bxRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

private func bxZipParts(sheets: [String], refs: [BXSheetRef], sharedStrings: String? = nil) -> [(name: String, data: Data)] {
    var parts: [(name: String, data: Data)] = []
    parts.append(("_rels/.rels", Data("""
        <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\(bxRel)/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """.utf8)))
    var sheetElements = ""
    for (n, ref) in refs.enumerated() {
        let state = ref.hidden ? " state=\"hidden\"" : ""
        sheetElements += "<sheet name=\"\(ref.name)\" sheetId=\"\(n + 1)\"\(state) r:id=\"rId\(ref.target + 1)\"/>"
    }
    parts.append(("xl/workbook.xml", Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"\(bxMain)\" xmlns:r=\"\(bxRel)\"><sheets>\(sheetElements)</sheets></workbook>".utf8)))
    var relationships = ""
    for index in sheets.indices {
        relationships += "<Relationship Id=\"rId\(index + 1)\" Type=\"\(bxRel)/worksheet\" Target=\"worksheets/sheet\(index + 1).xml\"/>"
    }
    if sharedStrings != nil {
        relationships += "<Relationship Id=\"rIdShared\" Type=\"\(bxRel)/sharedStrings\" Target=\"sharedStrings.xml\"/>"
    }
    parts.append(("xl/_rels/workbook.xml.rels", Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships)</Relationships>".utf8)))
    for (index, xml) in sheets.enumerated() {
        parts.append(("xl/worksheets/sheet\(index + 1).xml", Data(xml.utf8)))
    }
    if let sharedStrings {
        parts.append(("xl/sharedStrings.xml", Data(sharedStrings.utf8)))
    }
    return parts
}

private func bxWorkbook(sheets: [String], refs: [BXSheetRef], sharedStrings: String? = nil) -> Data {
    ZipWriter.archive(bxZipParts(sheets: sheets, refs: refs, sharedStrings: sharedStrings))
}

private func bxSheetXML(_ rows: String) -> String {
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"\(bxMain)\"><sheetData>\(rows)</sheetData></worksheet>"
}

/// Een blad met `rows` rijen van `columns` getallen: cel (r, c) heeft de waarde (r × 7 + c × 3) mod 1000, rijen vanaf 1.
private func bxNumberSheet(rows: Int, columns: Int) -> String {
    var xml = ""
    xml.reserveCapacity(rows * columns * 28)
    for r in 1...rows {
        xml += "<row r=\"\(r)\">"
        for c in 0..<columns {
            xml += "<c r=\"\(bxColumns[c])\(r)\"><v>\((r * 7 + c * 3) % 1000)</v></c>"
        }
        xml += "</row>"
    }
    return bxSheetXML(xml)
}

/// Een klein blad met een kopregel en twee regels, met tekst in de cel zelf (geen gedeelde teksten nodig).
private func bxBudgetSheet(_ lines: [(String, Int)]) -> String {
    var xml = "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Omschrijving</t></is></c><c r=\"B1\" t=\"inlineStr\"><is><t>Bedrag</t></is></c></row>"
    for (n, line) in lines.enumerated() {
        let r = n + 2
        xml += "<row r=\"\(r)\"><c r=\"A\(r)\" t=\"inlineStr\"><is><t>\(line.0)</t></is></c><c r=\"B\(r)\"><v>\(line.1)</v></c></row>"
    }
    return bxSheetXML(xml)
}

private func bxSharedStrings(_ items: [String]) -> String {
    let list = items.map { "<si><t xml:space=\"preserve\">\($0)</t></si>" }.joined()
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><sst xmlns=\"\(bxMain)\" count=\"\(items.count)\" uniqueCount=\"\(items.count)\">\(list)</sst>"
}

private func bxSeconds(_ body: () throws -> Void) rethrows -> Double {
    let start = Date()
    try body()
    return Date().timeIntervalSince(start)
}

final class XLSXSheetLimitTests: XCTestCase {

    // MARK: Dubbele verwijzingen

    func testHundredsOfReferencesToOneSheetReadItOnce() throws {
        // 300 namen, allemaal naar rId1: één blad van 20.000 rijen. Het gemelde bestand had 20 kolommen; hier 10, zodat de test
        // ook in een debugbouw snel blijft. Zonder de oplossing is het nog steeds driehonderd keer het werk.
        let refs = (1...300).map { BXSheetRef(name: "Blad\($0)", target: 0) }
        let data = bxWorkbook(sheets: [bxNumberSheet(rows: 20_000, columns: 10)], refs: refs)

        var book: SpreadsheetWorkbook?
        let seconds = try bxSeconds { book = try SpreadsheetReader.read(data, fileName: "dubbel.xlsx") }
        XCTAssertLessThan(seconds, 5, "lezen duurde \(seconds) seconden")

        let table = try XCTUnwrap(book?.tables.first)
        XCTAssertEqual(book?.tables.count, 1)
        XCTAssertEqual(table.name, "Blad1", "de eerste naam blijft")
        XCTAssertEqual(table.rows.count, 20_000)
        XCTAssertEqual(table.columnCount, 10)
        XCTAssertFalse(table.isTruncated)
        XCTAssertEqual(book?.skippedSheets, 0)
        // Een paar cellen nagerekend met dezelfde formule als waarmee het bestand is gemaakt: rij 1 begint op 7 + 0.
        XCTAssertEqual(table.cell(0, 0), .number(7))
        XCTAssertEqual(table.cell(0, 9), .number(34))
        XCTAssertEqual(table.cell(19_999, 4), .number(Double((20_000 * 7 + 4 * 3) % 1000)))
        XCTAssertEqual(table.cell(142, 3), .number(Double((143 * 7 + 3 * 3) % 1000)))
    }

    func testReferencesToTheSameSheetNeverCountTowardsTheLimit() throws {
        // 120 namen die samen drie bladen gebruiken: drie tabellen, niets overgeslagen.
        let sheets = (1...3).map { bxBudgetSheet([("Huur \($0)", 100 * $0)]) }
        let refs = (0..<120).map { BXSheetRef(name: "Naam\($0)", target: $0 % 3) }
        let book = try SpreadsheetReader.read(bxWorkbook(sheets: sheets, refs: refs), fileName: "drie.xlsx")
        XCTAssertEqual(book.tables.map(\.name), ["Naam0", "Naam1", "Naam2"])
        XCTAssertEqual(book.skippedSheets, 0)
        XCTAssertEqual(book.tables.map { $0.cell(1, 1) }, [.number(100), .number(200), .number(300)])
    }

    func testASheetIsVisibleWhenAnyNameForItIsVisible() throws {
        let sheet = bxBudgetSheet([("Huur", 900)])
        let hiddenFirst = try SpreadsheetReader.read(
            bxWorkbook(sheets: [sheet], refs: [BXSheetRef(name: "A", target: 0, hidden: true), BXSheetRef(name: "B", target: 0)]),
            fileName: "a.xlsx")
        XCTAssertEqual(hiddenFirst.tables.count, 1)
        XCTAssertFalse(hiddenFirst.tables[0].isHidden)
        let allHidden = try SpreadsheetReader.read(
            bxWorkbook(sheets: [sheet], refs: [BXSheetRef(name: "A", target: 0, hidden: true),
                                               BXSheetRef(name: "B", target: 0, hidden: true)]),
            fileName: "b.xlsx")
        XCTAssertEqual(allHidden.tables.count, 1)
        XCTAssertTrue(allHidden.tables[0].isHidden)
    }

    // MARK: Maximaal 50 bladen

    func testMoreThanFiftyDifferentSheetsAreLimitedAndReported() throws {
        let sheets = (1...70).map { bxBudgetSheet([("Huur \($0)", $0)]) }
        let refs = (1...70).map { BXSheetRef(name: "Blad\($0)", target: $0 - 1) }
        let book = try SpreadsheetReader.read(bxWorkbook(sheets: sheets, refs: refs), fileName: "veel.xlsx")
        XCTAssertEqual(XLSXReader.maxSheets, 50)
        XCTAssertEqual(book.tables.count, 50)
        XCTAssertEqual(book.tables.first?.name, "Blad1")
        XCTAssertEqual(book.tables.last?.name, "Blad50")
        XCTAssertEqual(book.skippedSheets, 20)

        let draft = ImportMapper.draft(from: book, preferredMonth: YearMonth(year: 2026, month: 10))
        XCTAssertTrue(draft.warnings.contains { $0.contains("meer dan 50 bladen") && $0.contains("20 bladen zijn overgeslagen") },
                      "\(draft.warnings)")
        XCTAssertEqual(draft.rows.filter { $0.name.hasPrefix("Huur") }.count, 50)
    }

    func testExactlyFiftySheetsSkipNothing() throws {
        let sheets = (1...50).map { bxBudgetSheet([("Huur \($0)", $0)]) }
        let refs = (1...50).map { BXSheetRef(name: "Blad\($0)", target: $0 - 1) }
        let book = try SpreadsheetReader.read(bxWorkbook(sheets: sheets, refs: refs), fileName: "vijftig.xlsx")
        XCTAssertEqual(book.tables.count, 50)
        XCTAssertEqual(book.skippedSheets, 0)
        let draft = ImportMapper.draft(from: book, preferredMonth: YearMonth(year: 2026, month: 10))
        XCTAssertFalse(draft.warnings.contains { $0.contains("bladen") && $0.contains("overgeslagen") }, "\(draft.warnings)")
    }

    func testCustomSheetLimit() throws {
        let sheets = (1...5).map { bxBudgetSheet([("Huur \($0)", $0)]) }
        let refs = (1...5).map { BXSheetRef(name: "Blad\($0)", target: $0 - 1) }
        let data = bxWorkbook(sheets: sheets, refs: refs)
        let book = try XLSXReader.read(data, fileName: "vijf.xlsx", limits: XLSXLimits(maxSheets: 3))
        XCTAssertEqual(book.tables.map(\.name), ["Blad1", "Blad2", "Blad3"])
        XCTAssertEqual(book.skippedSheets, 2)
    }

    func testThousandsOfSheetElementsInTheWorkbookAreCut() throws {
        // 3000 namen voor 60 verschillende bladen (elk blad vijftig keer): we kijken niet verder dan 1000 elementen.
        let sheets = (1...60).map { bxBudgetSheet([("Huur \($0)", $0)]) }
        let refs = (0..<3000).map { BXSheetRef(name: "N\($0)", target: $0 % 60) }
        let book = try SpreadsheetReader.read(bxWorkbook(sheets: sheets, refs: refs), fileName: "elementen.xlsx")
        XCTAssertEqual(book.tables.count, 50)
        XCTAssertGreaterThanOrEqual(book.skippedSheets, 10)
    }
}

final class XLSXCellBudgetTests: XCTestCase {

    private func read(_ data: Data, limits: XLSXLimits) throws -> SpreadsheetWorkbook {
        try XLSXReader.read(data, fileName: "test.xlsx", limits: limits)
    }

    private func assertTooLarge(_ data: Data, limits: XLSXLimits, _ message: String = "", line: UInt = #line) {
        XCTAssertThrowsError(try read(data, limits: limits), message, line: line) { error in
            XCTAssertEqual(error as? SpreadsheetError, .tooLarge, message, line: line)
        }
    }

    func testDefaultLimits() {
        XCTAssertEqual(XLSXReader.maxSheets, 50)
        XCTAssertEqual(XLSXReader.maxCells, 2_000_000)
        XCTAssertEqual(XLSXReader.maxTextLength, 500)
        XCTAssertEqual(XLSXLimits(), XLSXLimits(maxSheets: 50, maxCells: 2_000_000, maxVisited: XLSXReader.maxVisited,
                                                 maxInflatedBytes: 2 * Inflate.defaultLimit))
        // Een gewoon blad van 20.000 rijen met 256 kolommen mag net.
        XCTAssertLessThan(XLSXReader.maxRows * XLSXReader.maxColumns + XLSXReader.maxRows, XLSXReader.maxVisited)
    }

    func testOneSheetOverTheCellBudgetIsTooLarge() throws {
        let data = bxWorkbook(sheets: [bxNumberSheet(rows: 100, columns: 5)], refs: [BXSheetRef(name: "Groot", target: 0)])
        // 500 cellen: met een budget van 500 kan het, met 499 niet.
        XCTAssertEqual(try read(data, limits: XLSXLimits(maxCells: 500)).tables[0].rows.count, 100)
        assertTooLarge(data, limits: XLSXLimits(maxCells: 499))
    }

    func testTheCellBudgetCountsAllSheetsTogether() throws {
        // Drie verschillende bladen van 100 cellen: elk apart past in 250, samen (300) niet.
        let sheets = (0..<3).map { _ in bxNumberSheet(rows: 20, columns: 5) }
        let refs = (0..<3).map { BXSheetRef(name: "Blad\($0)", target: $0) }
        let data = bxWorkbook(sheets: sheets, refs: refs)
        let limits = XLSXLimits(maxCells: 250)
        assertTooLarge(data, limits: limits, "samen 300 cellen")
        let two = bxWorkbook(sheets: Array(sheets.prefix(2)), refs: Array(refs.prefix(2)))
        XCTAssertEqual(try read(two, limits: limits).tables.count, 2)
        // Dezelfde cellen via dubbele verwijzingen tellen één keer.
        let dups = bxWorkbook(sheets: [sheets[0]], refs: (0..<10).map { BXSheetRef(name: "N\($0)", target: 0) })
        XCTAssertEqual(try read(dups, limits: limits).tables.count, 1)
    }

    func testEmptyStyledCellsHaveTheirOwnBudget() throws {
        // Een blad vol cellen met alleen een opmaak (geen waarde): bewaren kost niets, doorlopen wel tijd.
        var rows = ""
        for r in 1...50 {
            rows += "<row r=\"\(r)\">" + (0..<4).map { "<c r=\"\(bxColumns[$0])\(r)\" s=\"1\"/>" }.joined() + "<c r=\"E\(r)\"><v>1</v></c></row>"
        }
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Opmaak", target: 0)])
        // 50 rijen + 250 cellen = 300 doorlopen, 50 bewaard.
        let book = try read(data, limits: XLSXLimits(maxCells: 50, maxVisited: 300))
        XCTAssertEqual(book.tables[0].rows.count, 50)
        assertTooLarge(data, limits: XLSXLimits(maxCells: 50, maxVisited: 299))
        assertTooLarge(data, limits: XLSXLimits(maxCells: 49, maxVisited: 300))
    }

    func testMoreSharedStringsThanCellsCanUseIsTooLarge() throws {
        let items = (0..<100).map { "tekst \($0)" }
        let data = bxWorkbook(sheets: [bxSheetXML("<row r=\"1\"><c r=\"A1\" t=\"s\"><v>3</v></c></row>")],
                              refs: [BXSheetRef(name: "Blad", target: 0)], sharedStrings: bxSharedStrings(items))
        XCTAssertEqual(try read(data, limits: XLSXLimits(maxCells: 100)).tables[0].cell(0, 0), .text("tekst 3"))
        assertTooLarge(data, limits: XLSXLimits(maxCells: 99))
    }

    func testTheTotalAmountOfUnpackedXMLIsLimited() throws {
        let data = bxWorkbook(sheets: [bxNumberSheet(rows: 50, columns: 5)], refs: [BXSheetRef(name: "Blad", target: 0)])
        let total = bxZipParts(sheets: [bxNumberSheet(rows: 50, columns: 5)], refs: [BXSheetRef(name: "Blad", target: 0)])
            .reduce(0) { $0 + $1.data.count }
        XCTAssertNoThrow(try read(data, limits: XLSXLimits(maxInflatedBytes: total)))
        assertTooLarge(data, limits: XLSXLimits(maxInflatedBytes: total / 2))
    }

    func testLimitsAlsoApplyThroughTheNormalEntryPoint() throws {
        // De gewone weg (zonder eigen grenzen) leest een middelgroot blad gewoon.
        let data = bxWorkbook(sheets: [bxNumberSheet(rows: 2_000, columns: 10)], refs: [BXSheetRef(name: "Blad", target: 0)])
        let book = try SpreadsheetReader.read(data, fileName: "middel.xlsx")
        XCTAssertEqual(book.tables[0].rows.count, 2_000)
    }

    func testRowsBeyondTheLimitAreCutOffQuickly() throws {
        let data = bxWorkbook(sheets: [bxNumberSheet(rows: 25_000, columns: 2)], refs: [BXSheetRef(name: "Lang", target: 0)])
        var book: SpreadsheetWorkbook?
        let seconds = try bxSeconds { book = try SpreadsheetReader.read(data, fileName: "lang.xlsx") }
        XCTAssertLessThan(seconds, 5)
        let table = try XCTUnwrap(book?.tables.first)
        XCTAssertEqual(table.rows.count, XLSXReader.maxRows)
        XCTAssertTrue(table.isTruncated)
        XCTAssertEqual(table.cell(XLSXReader.maxRows - 1, 0), .number(Double((XLSXReader.maxRows * 7) % 1000)))
    }

    func testTooLargeSaysSoInDutch() {
        let text = SpreadsheetError.tooLarge.errorDescription ?? ""
        XCTAssertTrue(text.contains("50 MB"), text)
        XCTAssertTrue(text.contains("2 miljoen gevulde cellen"), text)
        XCTAssertTrue(text.hasSuffix("."), text)
    }
}

final class XLSXTextLimitTests: XCTestCase {

    // MARK: Gedeelde teksten

    func testHugeSharedTextUsedByManyRowsIsCappedAndFast() throws {
        // Eén gedeelde tekst van 1 MB die 20.000 rijen (de grens per blad) gebruiken.
        let big = String(repeating: "Huur ", count: 200_000)
        XCTAssertEqual(big.count, 1_000_000)
        var rows = "<row r=\"1\"><c r=\"A1\" t=\"s\"><v>1</v></c><c r=\"B1\" t=\"s\"><v>1</v></c></row>"
        for r in 2...20_000 { rows += "<row r=\"\(r)\"><c r=\"A\(r)\" t=\"s\"><v>0</v></c><c r=\"B\(r)\"><v>\(r % 500)</v></c></row>" }
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Tekst", target: 0)],
                              sharedStrings: bxSharedStrings([big, "Omschrijving"]))

        var book: SpreadsheetWorkbook?
        let seconds = try bxSeconds { book = try SpreadsheetReader.read(data, fileName: "tekst.xlsx") }
        XCTAssertLessThan(seconds, 5, "lezen duurde \(seconds) seconden")

        let table = try XCTUnwrap(book?.tables.first)
        XCTAssertEqual(table.rows.count, 20_000)
        XCTAssertFalse(table.isTruncated)
        XCTAssertEqual(table.cell(0, 0), .text("Omschrijving"))
        // De lange tekst is afgekapt op 500 tekens (honderd keer "Huur "), in elke rij dezelfde.
        let expected = CellValue.text(String(repeating: "Huur ", count: 100))
        XCTAssertEqual(table.cell(1, 0), expected)
        XCTAssertEqual(table.cell(10_000, 0), expected)
        XCTAssertEqual(table.cell(19_999, 0), expected)
        XCTAssertEqual(table.cell(19_999, 1), .number(Double(20_000 % 500)))
        XCTAssertTrue(table.hasContent)
    }

    func testBlankSharedTextsStayEmptyAndOthersKeepTheirSpaces() throws {
        let rows = "<row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c><c r=\"C1\" t=\"s\"><v>2</v></c>"
            + "<c r=\"D1\" t=\"s\"><v>9</v></c><c r=\"E1\" t=\"s\"><v>-1</v></c><c r=\"F1\" t=\"s\"><v>x</v></c></row>"
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Leeg", target: 0)],
                              sharedStrings: bxSharedStrings(["   ", "\n\t ", " x "]))
        let table = try SpreadsheetReader.read(data, fileName: "leeg.xlsx").tables[0]
        XCTAssertEqual(table.cell(0, 0), .empty, "alleen spaties")
        XCTAssertEqual(table.cell(0, 1), .empty, "alleen witruimte")
        XCTAssertEqual(table.cell(0, 2), .text(" x "), "de tekst blijft zoals hij was")
        XCTAssertEqual(table.cell(0, 3), .empty, "verwijzing buiten de lijst")
        XCTAssertEqual(table.cell(0, 4), .empty, "negatieve verwijzing")
        XCTAssertEqual(table.cell(0, 5), .empty, "geen getal")
        XCTAssertEqual(table.cell(0, 2).trimmedText, "x")
    }

    func testSharedTextsWithSeveralPartsStillJoinBeforeCapping() throws {
        let items = "<si><r><t>Hu</t></r><r><t>ur</t></r></si><si><t>\(String(repeating: "ab", count: 600))</t></si>"
        let sst = "<?xml version=\"1.0\"?><sst xmlns=\"\(bxMain)\">\(items)</sst>"
        let rows = "<row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c></row>"
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Delen", target: 0)], sharedStrings: sst)
        let table = try SpreadsheetReader.read(data, fileName: "delen.xlsx").tables[0]
        XCTAssertEqual(table.cell(0, 0), .text("Huur"))
        XCTAssertEqual(table.cell(0, 1), .text(String(repeating: "ab", count: 250)))
    }

    // MARK: Tekst in de cel zelf

    func testLongInlineAndFormulaTextsAreCapped() throws {
        let long = String(repeating: "z", count: 100_000)
        let rows = "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>\(long)</t></is></c>"
            + "<c r=\"B1\" t=\"str\"><f>A1</f><v>\(long)</v></c><c r=\"C1\" t=\"inlineStr\"><is><t>kort</t></is></c></row>"
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Lang", target: 0)])
        let table = try SpreadsheetReader.read(data, fileName: "lang.xlsx").tables[0]
        XCTAssertEqual(table.cell(0, 0), .text(String(repeating: "z", count: 500)))
        XCTAssertEqual(table.cell(0, 1), .text(String(repeating: "z", count: 500)))
        XCTAssertEqual(table.cell(0, 2), .text("kort"))
    }

    func testCappingCountsCharactersNotBytes() throws {
        // 600 keer een letter met accent en een emoji (meerdere bytes per teken): 500 tekens blijven over, niets wordt middenin gesneden.
        let text = String(repeating: "é😀", count: 300)
        let rows = "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>\(text)</t></is></c></row>"
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Tekens", target: 0)])
        let value = try SpreadsheetReader.read(data, fileName: "tekens.xlsx").tables[0].cell(0, 0)
        XCTAssertEqual(value, .text(String(repeating: "é😀", count: 250)))
    }

    func testNumbersAndShortValuesAreNotAffected() throws {
        let rows = "<row r=\"1\"><c r=\"A1\"><v> 12,5 </v></c><c r=\"B1\"><v> 42 </v></c><c r=\"C1\" t=\"b\"><v>1</v></c>"
            + "<c r=\"D1\"><v>\u{00A0}7\u{00A0}</v></c></row>"
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Waarden", target: 0)])
        let table = try SpreadsheetReader.read(data, fileName: "waarden.xlsx").tables[0]
        XCTAssertEqual(table.cell(0, 0), .text("12,5"), "geen getal: tekst zonder spaties aan de randen")
        XCTAssertEqual(table.cell(0, 1), .number(42))
        XCTAssertEqual(table.cell(0, 2), .bool(true))
        XCTAssertEqual(table.cell(0, 3), .number(7), "ook een harde spatie wordt weggehaald")
    }

    func testCellReferencesStillParse() {
        // parseReference is privé; de uitkomst is zichtbaar aan de plek van de cellen.
        let rows = "<row r=\"2\"><c r=\"B2\"><v>1</v></c><c r=\"$D$2\"><v>2</v></c><c r=\"aa2\"><v>3</v></c><c><v>4</v></c></row>"
        let data = bxWorkbook(sheets: [bxSheetXML(rows)], refs: [BXSheetRef(name: "Plek", target: 0)])
        let table = try? SpreadsheetReader.read(data, fileName: "plek.xlsx").tables[0]
        XCTAssertEqual(table?.cell(1, 1), .number(1))
        XCTAssertEqual(table?.cell(1, 3), .number(2))
        XCTAssertEqual(table?.cell(1, 26), .number(3), "AA is kolom 27, dus index 26")
        XCTAssertEqual(table?.cell(1, 27), .number(4), "zonder verwijzing volgt de cel op de vorige")
    }

    // MARK: Samengevoegde cellen

    func testManyMergedAreasDoNotMakeReadingSlow() throws {
        // 30.000 samengevoegde vakken van 100 × 100 cellen boven een blad van 100 rijen: zonder grens driehonderd miljoen handelingen.
        var rows = ""
        for r in 1...100 { rows += "<row r=\"\(r)\"><c r=\"A\(r)\"><v>\(r)</v></c></row>" }
        let merges = (0..<30_000).map { _ in "<mergeCell ref=\"A1:CV100\"/>" }.joined()
        let xml = "<?xml version=\"1.0\"?><worksheet xmlns=\"\(bxMain)\"><sheetData>\(rows)</sheetData><mergeCells>\(merges)</mergeCells></worksheet>"
        let data = bxWorkbook(sheets: [xml], refs: [BXSheetRef(name: "Vakken", target: 0)])
        var table: SpreadsheetTable?
        let seconds = try bxSeconds { table = try SpreadsheetReader.read(data, fileName: "vakken.xlsx").tables[0] }
        XCTAssertLessThan(seconds, 5, "lezen duurde \(seconds) seconden")
        // Het eerste vak wordt nog wel ingevuld (A1 geldt voor het hele vak).
        XCTAssertEqual(table?.cell(0, 1), .number(1))
        XCTAssertEqual(table?.cell(0, 99), .number(1))
    }
}

// MARK: - Zip-bommen

/// Eén onderdeel van een ZIP-bestand dat we met opzet "liegen" over zijn grootte laten doen.
private struct BXEntry {
    var name: String
    var method: UInt16 = 0
    var payload: [UInt8]
    /// De ongecomprimeerde grootte zoals de ZIP die opgeeft (kan afwijken van de werkelijkheid).
    var claimedSize: UInt32
    var crc: UInt32 = 0
}

private func bxLE16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
private func bxLE32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }

private func bxZip(_ entries: [BXEntry]) -> Data {
    var out: [UInt8] = []
    var central: [UInt8] = []
    for entry in entries {
        let name = Array(entry.name.utf8)
        let offset = out.count
        // Lokale kop: handtekening, versie, vlaggen, methode, tijd, datum, controlesom, groottes, lengte van naam en extra.
        out += bxLE32(0x0403_4B50)
        out += bxLE16(20)
        out += bxLE16(0x0800)
        out += bxLE16(entry.method)
        out += bxLE16(0)
        out += bxLE16(0x5821)
        out += bxLE32(entry.crc)
        out += bxLE32(UInt32(entry.payload.count))
        out += bxLE32(entry.claimedSize)
        out += bxLE16(UInt16(name.count))
        out += bxLE16(0)
        out += name
        out += entry.payload

        // Centrale kop: dezelfde gegevens plus commentaar, schijf, kenmerken en de plek van de lokale kop.
        central += bxLE32(0x0201_4B50)
        central += bxLE16(20)
        central += bxLE16(20)
        central += bxLE16(0x0800)
        central += bxLE16(entry.method)
        central += bxLE16(0)
        central += bxLE16(0x5821)
        central += bxLE32(entry.crc)
        central += bxLE32(UInt32(entry.payload.count))
        central += bxLE32(entry.claimedSize)
        central += bxLE16(UInt16(name.count))
        central += bxLE16(0)
        central += bxLE16(0)
        central += bxLE16(0)
        central += bxLE16(0)
        central += bxLE32(0)
        central += bxLE32(UInt32(offset))
        central += name
    }
    let directoryOffset = out.count
    out += central
    out += bxLE32(0x0605_4B50)
    out += bxLE16(0)
    out += bxLE16(0)
    out += bxLE16(UInt16(entries.count))
    out += bxLE16(UInt16(entries.count))
    out += bxLE32(UInt32(central.count))
    out += bxLE32(UInt32(directoryOffset))
    out += bxLE16(0)
    return Data(out)
}

/// Een DEFLATE-stroom met vaste codes: één "a" en daarna `matches` keer een kopie van 258 bytes op afstand 1.
/// Dat pakt uit tot 1 + 258 × matches bytes uit ongeveer 1,6 byte per kopie, dus een zip-bom in het klein.
private func bxDeflateBomb(matches: Int) -> [UInt8] {
    var bytes: [UInt8] = []
    var used = 0
    func bit(_ value: Int) {
        if used == 0 { bytes.append(0) }
        if value & 1 == 1 { bytes[bytes.count - 1] |= UInt8(1 << used) }
        used = (used + 1) % 8
    }
    func raw(_ value: Int, _ length: Int) { for i in 0..<length { bit((value >> i) & 1) } }
    func code(_ value: Int, _ length: Int) { for i in stride(from: length - 1, through: 0, by: -1) { bit((value >> i) & 1) } }

    raw(1, 1)               // laatste blok
    raw(1, 2)               // vaste Huffman-codes
    code(0x30 + 97, 8)      // letterlijk "a"
    for _ in 0..<matches {
        code(0xC0 + 5, 8)   // lengtesymbool 285 = 258 bytes
        code(0, 5)          // afstandscode 0 = 1 byte terug
    }
    code(0, 7)              // einde van het blok
    return bytes
}

final class XLSXZipBombTests: XCTestCase {

    private let cleanRels = Array("""
        <?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """.utf8)

    private func honest(_ name: String, _ text: String) -> BXEntry {
        let payload = Array(text.utf8)
        return BXEntry(name: name, payload: payload, claimedSize: UInt32(payload.count), crc: CRC32.checksum(payload))
    }

    private let workbookXML = "<workbook xmlns=\"\(bxMain)\" xmlns:r=\"\(bxRel)\"><sheets><sheet name=\"Blad1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
    private let relsXML = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(bxRel)/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"
    private let sheetXML = "<worksheet xmlns=\"\(bxMain)\"><sheetData><row r=\"1\"><c r=\"A1\"><v>5</v></c></row></sheetData></worksheet>"

    private func entries(replacing name: String, with replacement: BXEntry) -> [BXEntry] {
        var list = [
            BXEntry(name: "_rels/.rels", payload: cleanRels, claimedSize: UInt32(cleanRels.count), crc: CRC32.checksum(cleanRels)),
            honest("xl/workbook.xml", workbookXML),
            honest("xl/_rels/workbook.xml.rels", relsXML),
            honest("xl/worksheets/sheet1.xml", sheetXML)
        ]
        if let index = list.firstIndex(where: { $0.name == name }) { list[index] = replacement }
        return list
    }

    func testTheHelperBuildsAWorkbookThatReads() throws {
        let book = try SpreadsheetReader.read(bxZip(entries(replacing: "-", with: honest("-", ""))), fileName: "ok.xlsx")
        XCTAssertEqual(book.tables.first?.cell(0, 0), .number(5))
    }

    func testTheBombGeneratorExpandsAsExpected() throws {
        // Controle op de testdata zelf: 100 kopieën van 258 bytes plus de eerste letter, zonder grens gewoon uitgepakt.
        let out = try Inflate.inflate(bxDeflateBomb(matches: 100))
        XCTAssertEqual(out.count, 1 + 258 * 100)
        XCTAssertTrue(out.allSatisfy { $0 == 97 })
        XCTAssertLessThan(bxDeflateBomb(matches: 100).count, 200)
    }

    func testEntryClaimingTwoGigabytesIsRefusedImmediately() {
        for name in ["xl/worksheets/sheet1.xml", "xl/workbook.xml", "xl/sharedStrings.xml", "xl/styles.xml"] {
            var parts = entries(replacing: "-", with: honest("-", ""))
            let liar = BXEntry(name: name, payload: Array("<x/>".utf8), claimedSize: 0x7FFF_FFFF)
            if let index = parts.firstIndex(where: { $0.name == name }) { parts[index] = liar } else { parts.append(liar) }
            var error: Error?
            let seconds = bxSeconds {
                do { _ = try SpreadsheetReader.read(bxZip(parts), fileName: "bom.xlsx") } catch let caught { error = caught }
            }
            XCTAssertEqual(error as? SpreadsheetError, .tooLarge, name)
            XCTAssertLessThan(seconds, 2, name)
        }
    }

    func testEntryThatExpandsFarBeyondItsClaimedSizeIsStopped() {
        // De ZIP zegt 1000 bytes, de stroom pakt uit tot meer dan 25.000: de decoder stopt bij de opgegeven grootte.
        let bomb = bxDeflateBomb(matches: 100)
        let liar = BXEntry(name: "xl/worksheets/sheet1.xml", method: 8, payload: bomb, claimedSize: 1_000)
        var error: Error?
        let seconds = bxSeconds {
            do { _ = try SpreadsheetReader.read(bxZip(entries(replacing: "xl/worksheets/sheet1.xml", with: liar)), fileName: "bom.xlsx") }
            catch let caught { error = caught }
        }
        XCTAssertEqual(error as? SpreadsheetError, .tooLarge)
        XCTAssertLessThan(seconds, 2)
    }

    func testEntryWhoseStreamEndsAtTheClaimedSizeButHasAWrongChecksumIsCorrupt() {
        // Een eerlijke grootte maar een verkeerde controlesom blijft een beschadigd bestand, geen "te groot".
        let bomb = bxDeflateBomb(matches: 4)   // 1033 bytes
        let wrong = BXEntry(name: "xl/worksheets/sheet1.xml", method: 8, payload: bomb, claimedSize: 1_033, crc: 12_345)
        XCTAssertThrowsError(try SpreadsheetReader.read(bxZip(entries(replacing: "xl/worksheets/sheet1.xml", with: wrong)), fileName: "k.xlsx")) { error in
            if case .corrupt? = error as? SpreadsheetError { return }
            XCTFail("verwachtte corrupt, kreeg \(error)")
        }
    }

    func testBombAsWorkbookOrSharedStringsIsStoppedToo() {
        let bomb = bxDeflateBomb(matches: 100)
        let liar = BXEntry(name: "xl/workbook.xml", method: 8, payload: bomb, claimedSize: 500)
        XCTAssertThrowsError(try SpreadsheetReader.read(bxZip(entries(replacing: "xl/workbook.xml", with: liar)), fileName: "w.xlsx")) {
            XCTAssertEqual($0 as? SpreadsheetError, .tooLarge)
        }
        var parts = entries(replacing: "-", with: honest("-", ""))
        parts.append(BXEntry(name: "xl/sharedStrings.xml", method: 8, payload: bomb, claimedSize: 500))
        XCTAssertThrowsError(try SpreadsheetReader.read(bxZip(parts), fileName: "s.xlsx")) {
            XCTAssertEqual($0 as? SpreadsheetError, .tooLarge)
        }
    }

    func testManyRepeatedReadsOfOneBombStayBounded() {
        // Veel verwijzingen naar één onderdeel dat te groot is: de eerste keer faalt het bestand al.
        let liar = BXEntry(name: "xl/worksheets/sheet1.xml", payload: Array("<x/>".utf8), claimedSize: 0x7FFF_FFFF)
        let sheets = (0..<500).map { "<sheet name=\"B\($0)\" sheetId=\"\($0 + 1)\" r:id=\"rId1\"/>" }.joined()
        let workbook = "<workbook xmlns=\"\(bxMain)\" xmlns:r=\"\(bxRel)\"><sheets>\(sheets)</sheets></workbook>"
        var parts = entries(replacing: "xl/worksheets/sheet1.xml", with: liar)
        parts[1] = honest("xl/workbook.xml", workbook)
        var error: Error?
        let seconds = bxSeconds {
            do { _ = try SpreadsheetReader.read(bxZip(parts), fileName: "bom.xlsx") } catch let caught { error = caught }
        }
        XCTAssertEqual(error as? SpreadsheetError, .tooLarge)
        XCTAssertLessThan(seconds, 2)
    }
}
