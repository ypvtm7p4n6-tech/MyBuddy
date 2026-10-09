import XCTest
import Foundation
@testable import MyBuddyCore

// Tests voor het herkennen en indelen van rijen (ImportMapping.swift) en voor het toevoegen aan de gegevens.
// De spreadsheets komen uit XLSXTests.swift (XLSXFixtures); CSV staat hier als tekst. De verwachte categorieën en
// bedragen volgen uit hoe de voorbeelden zijn opgebouwd, niet uit onze eigen code.

private let importOctober = YearMonth(year: 2026, month: 10)

/// "Naam|categorie|bedrag" per rij, voor vergelijkingen.
private func lines(_ rows: [ImportRow]) -> [String] {
    rows.map { "\($0.name)|\($0.category.rawValue)|\(CSVExport.number($0.amount))" }
}

private func csvDraft(_ text: String, name: String = "test.csv", month: Int = 10) throws -> ImportDraft {
    let book = try SpreadsheetReader.read(Data(text.utf8), fileName: name)
    return ImportMapper.draft(from: book, preferredMonth: YearMonth(year: 2026, month: month))
}

private func xlsxDraft(_ data: Data, name: String = "test.xlsx", month: Int = 10) throws -> ImportDraft {
    let book = try SpreadsheetReader.read(data, fileName: name)
    return ImportMapper.draft(from: book, preferredMonth: YearMonth(year: 2026, month: month))
}

private func row(_ draft: ImportDraft, _ name: String, file: StaticString = #filePath, line: UInt = #line) -> ImportRow {
    guard let found = draft.rows.first(where: { $0.name == name }) else {
        XCTFail("Rij '\(name)' ontbreekt in \(draft.rows.map(\.name))", file: file, line: line)
        return ImportRow(name: name, amount: 0, category: .overslaan)
    }
    return found
}

final class ImportTextTests: XCTestCase {

    // MARK: Bedragen als tekst

    func testAmountTextFormats() {
        let cases: [(String, Double)] = [
            ("€ 1.234,56", 1234.56), ("1.234,56", 1234.56), ("-45,00", -45), ("45 EUR", 45), ("45 euro", 45),
            ("(45,00)", -45), ("45,00-", -45), ("+12,5", 12.5), ("1.234", 1234), ("12.50", 12.5),
            ("1,234.56", 1234.56), ("1.234.567,89", 1234567.89), ("0,5", 0.5), ("1 234,50", 1234.5),
            ("1\u{00A0}234", 1234), ("€ -45", -45), ("-€ 45", -45), ("\u{2212}12,00", -12), ("950 p.m.", 950),
            ("950 per maand", 950), ("0.123", 0.123), ("1,234,567", 1234567), ("  12  ", 12), ("1.234,5", 1234.5),
            ("€45", 45), ("10.000", 10000), ("7", 7),
            // Een streepje na de komma staat voor nul cent en is geen min-teken.
            ("€ 1.050,-", 1050), ("25,-", 25), ("25,--", 25), ("1.050,=", 1050), ("-25,-", -25), ("12.-", 12),
            ("1.050,\u{2014}", 1050), ("1.050,\u{2013}", 1050), ("(25,-)", -25), ("45,00-", -45)
        ]
        for (text, expected) in cases {
            guard let value = AmountText.parse(text) else { XCTFail("'\(text)' hoort een bedrag te zijn"); continue }
            XCTAssertEqual(value, expected, accuracy: 0.0001, text)
        }
    }

    func testAmountTextRejectsNonAmounts() {
        for text in ["", " ", "12%", "n.v.t.", "abc", "12 maanden", "15-10-2026", "1e3", "€", "-", "(", "huur 900", "12,5,5x", ",-", ",--"] {
            XCTAssertNil(AmountText.parse(text), "'\(text)' is geen bedrag")
        }
    }

    // MARK: Datums en dagen

    func testDayNumberFromCells() {
        XCTAssertEqual(ImportText.dayNumber(from: .number(25)), 25)
        XCTAssertNil(ImportText.dayNumber(from: .number(32)))
        XCTAssertNil(ImportText.dayNumber(from: .number(0)))
        XCTAssertNil(ImportText.dayNumber(from: .number(2.5)))
        XCTAssertEqual(ImportText.dayNumber(from: .text("25e")), 25)
        XCTAssertEqual(ImportText.dayNumber(from: .text("1ste")), 1)
        XCTAssertEqual(ImportText.dayNumber(from: .text("Elke 15e")), 15)
        XCTAssertEqual(ImportText.dayNumber(from: .text("15-10-2026")), 15)
        XCTAssertEqual(ImportText.dayNumber(from: .text("20261004")), 4)
        XCTAssertEqual(ImportText.dayNumber(from: .date(SheetDate(year: 2026, month: 10, day: 17))), 17)
        XCTAssertNil(ImportText.dayNumber(from: .text("abc")))
        XCTAssertNil(ImportText.dayNumber(from: .text("2026")))
        XCTAssertNil(ImportText.dayNumber(from: .empty))
    }

    func testParseDateFormats() {
        XCTAssertEqual(ImportText.parseDate("15-10-2026"), SheetDate(year: 2026, month: 10, day: 15))
        XCTAssertEqual(ImportText.parseDate("5/1/26"), SheetDate(year: 2026, month: 1, day: 5))
        XCTAssertEqual(ImportText.parseDate("15.10.2026"), SheetDate(year: 2026, month: 10, day: 15))
        XCTAssertEqual(ImportText.parseDate("2026-10-15"), SheetDate(year: 2026, month: 10, day: 15))
        XCTAssertEqual(ImportText.parseDate("20261015"), SheetDate(year: 2026, month: 10, day: 15))
        XCTAssertNil(ImportText.parseDate("31-13-2026"))
        XCTAssertNil(ImportText.parseDate("12345678"))
        XCTAssertNil(ImportText.parseDate("hallo"))
    }

    func testMonthNames() {
        let cases: [(String, Int?)] = [
            ("jan", 1), ("januari 2026", 1), ("Mrt", 3), ("okt", 10), ("sept", 9), ("mei", 5), ("december", 12),
            ("2026 01", 1), ("01 2026", 1), ("jan 26", 1), ("maand", nil), ("huur", nil), ("jan feb", nil), ("13 2026", nil)
        ]
        for (text, expected) in cases {
            XCTAssertEqual(ImportText.monthNumber(ImportText.normalize(text)), expected, text)
        }
    }

    func testNormalize() {
        XCTAssertEqual(ImportText.normalize("Café Zoë!"), "cafe zoe")
        XCTAssertEqual(ImportText.normalize("S&P 500"), "sp 500")
        XCTAssertEqual(ImportText.normalize("  Uit  eten "), "uit eten")
        XCTAssertEqual(ImportText.normalize("Gas/Water/Licht"), "gas water licht")
        XCTAssertEqual(ImportText.normalize("€ 12,50"), "12 50")
        XCTAssertEqual(ImportText.normalize("!!!"), "")
    }

    func testTotalNames() {
        for name in ["Totaal", "Totaal inkomsten", "Subtotaal vast", "Saldo", "Overschot", "Tekort", "Vaste lasten totaal", "Som", "Te besteden"] {
            XCTAssertTrue(ImportText.isTotalName(ImportText.normalize(name)), name)
        }
        for name in ["Saldo spaarrekening ING", "Huur", "Overige kosten", "Restaurant"] {
            XCTAssertFalse(ImportText.isTotalName(ImportText.normalize(name)), name)
        }
    }

    func testCleanName() {
        XCTAssertEqual(ImportText.cleanName("  - Huur:  "), "Huur")
        XCTAssertEqual(ImportText.cleanName("Uit\neten\t  en  drinken"), "Uit eten en drinken")
        XCTAssertEqual(ImportText.cleanName("• Kleding"), "Kleding")
        XCTAssertEqual(ImportText.cleanName(String(repeating: "a", count: 200)).count, 80)
    }

    // MARK: Trefwoorden

    func testKeywordCategories() {
        let cases: [(String, ImportCategory)] = [
            ("Huur", .vasteLasten), ("Hypotheek ING", .vasteLasten), ("Gas, water en licht", .vasteLasten),
            ("Zorgverzekering", .vasteLasten), ("Internetabonnement", .vasteLasten), ("Kinderopvang", .vasteLasten),
            ("Aflossing studieschuld", .vasteLasten), ("Telefoon KPN", .vasteLasten), ("Gemeentebelasting", .vasteLasten),
            ("Autoverzekering", .vasteLasten), ("Energie", .vasteLasten), ("Netflix", .vasteLasten),
            ("Boodschappen AH", .variabeleLasten), ("Supermarkt", .variabeleLasten), ("Uit eten", .variabeleLasten),
            ("Kleding", .variabeleLasten), ("Benzine", .variabeleLasten), ("Openbaar vervoer", .variabeleLasten),
            ("Cadeaus", .variabeleLasten), ("Hobby", .variabeleLasten), ("Kapper", .variabeleLasten),
            ("Vakantie", .variabeleLasten), ("Albert Heijn 1234 Amsterdam", .variabeleLasten),
            ("Salaris", .inkomen), ("Loon", .inkomen), ("Huurtoeslag", .inkomen), ("Huurinkomsten", .inkomen),
            ("Bonus", .inkomen), ("Uitkering", .inkomen), ("Teruggave belasting", .inkomen), ("Belastingteruggave", .inkomen),
            ("Pensioenuitkering", .inkomen), ("Vakantiegeld", .inkomen), ("Zorgtoeslag", .inkomen),
            ("Sparen", .spaarpot), ("Spaarrekening", .spaarpot), ("Noodfonds", .spaarpot), ("Vakantiepot", .spaarpot),
            ("Buffer", .spaarpot), ("Reservering auto", .spaarpot),
            ("ETF", .belegging), ("VWCE", .belegging), ("Aandelen", .belegging), ("Bitcoin", .belegging),
            ("Obligaties", .belegging), ("Beleggingsrekening", .belegging), ("Pensioen", .belegging),
            ("S&P 500 tracker", .belegging), ("Degiro", .belegging)
        ]
        for (name, expected) in cases {
            guard let hit = ImportKeywords.best(in: name) else { XCTFail("Geen trefwoord voor '\(name)'"); continue }
            XCTAssertEqual(hit.category, expected, "'\(name)' kreeg woord '\(hit.word)'")
        }
        XCTAssertNil(ImportKeywords.best(in: "Iets heel onbekends"))
        XCTAssertNil(ImportKeywords.best(in: ""))
    }

    func testStrongAndWeakKeywords() {
        XCTAssertEqual(ImportKeywords.best(in: "Huur")?.strong, true)
        XCTAssertEqual(ImportKeywords.best(in: "Gas")?.strong, false)
        XCTAssertEqual(ImportKeywords.best(in: "Vakantie")?.strong, false)
        XCTAssertEqual(ImportKeywords.best(in: "Hypotheek")?.word, "hypotheek")
    }

    func testShortWordsOnlyMatchWholeWords() {
        // "gas" mag niet in "gasten" worden gevonden, "tv" niet in "attvx".
        XCTAssertNil(ImportKeywords.best(in: "Gasten"))
        XCTAssertNil(ImportKeywords.best(in: "Attvx"))
        XCTAssertEqual(ImportKeywords.best(in: "Gas en elektra")?.category, .vasteLasten)
        // Woorden van vier letters als begin van een woord: huurwoning wel, schuur niet.
        XCTAssertEqual(ImportKeywords.best(in: "Huurwoning")?.category, .vasteLasten)
        XCTAssertNil(ImportKeywords.best(in: "Schuur"))
    }

    func testStandardExpensesAreRecognizedByName() {
        for item in StandardExpenses.all {
            XCTAssertEqual(ImportKeywords.standardExpense(named: item.name)?.name, item.name)
            XCTAssertEqual(ImportKeywords.standardExpense(named: item.name.uppercased())?.name, item.name)
        }
        XCTAssertNil(ImportKeywords.standardExpense(named: "Niet standaard"))
    }

    func testLabels() {
        XCTAssertEqual(ImportLabels.category(of: "Vaste lasten")?.category, .vasteLasten)
        XCTAssertEqual(ImportLabels.category(of: "VASTE KOSTEN")?.category, .vasteLasten)
        XCTAssertEqual(ImportLabels.category(of: "Variabele kosten")?.category, .variabeleLasten)
        XCTAssertEqual(ImportLabels.category(of: "Inkomsten (netto)")?.category, .inkomen)
        XCTAssertEqual(ImportLabels.category(of: "Beleggingen")?.category, .belegging)
        XCTAssertEqual(ImportLabels.category(of: "Sparen")?.category, .spaarpot)
        XCTAssertEqual(ImportLabels.category(of: "Vast inkomen")?.category, .inkomen)
        XCTAssertEqual(ImportLabels.category(of: "Vast")?.category, .vasteLasten)
        // Twee even sterke categorieën: niet kiezen.
        XCTAssertNil(ImportLabels.category(of: "Sparen en beleggen"))
        XCTAssertNil(ImportLabels.category(of: "Wonen"))
        XCTAssertNil(ImportLabels.category(of: ""))
        XCTAssertTrue(ImportLabels.isGeneric("Uitgaven"))
        XCTAssertFalse(ImportLabels.isGeneric("Huur"))
        XCTAssertTrue(ImportLabels.isStrongHeading("Vaste lasten"))
        XCTAssertFalse(ImportLabels.isStrongHeading("Sparen"))
    }

    func testTickerHelpers() {
        XCTAssertEqual(ImportMapper.tickerFromName("VWCE (wereld-ETF)"), "VWCE.DE")
        XCTAssertEqual(ImportMapper.tickerFromName("iShares IWDA.AS"), "IWDA.AS")
        XCTAssertEqual(ImportMapper.tickerFromName("Bitcoin"), "BTC-EUR")
        XCTAssertEqual(ImportMapper.tickerFromName("ETH-EUR portemonnee"), "ETH-EUR")
        XCTAssertNil(ImportMapper.tickerFromName("Wereld-ETF"))
        XCTAssertNil(ImportMapper.tickerFromName("Spaarrekening"))
        XCTAssertEqual(ImportMapper.sanitizedTicker(" vwce.de "), "VWCE.DE")
        XCTAssertEqual(ImportMapper.sanitizedTicker("AAPL"), "AAPL")
        XCTAssertNil(ImportMapper.sanitizedTicker("n.v.t."))
        XCTAssertNil(ImportMapper.sanitizedTicker("-"))
        XCTAssertNil(ImportMapper.sanitizedTicker("12345"))
        XCTAssertNil(ImportMapper.sanitizedTicker("heel veel tekst met spaties"))
    }

    func testHoldingKindAndPotSymbol() {
        XCTAssertEqual(ImportMapper.holdingKind(for: "Bitcoin"), .crypto)
        XCTAssertEqual(ImportMapper.holdingKind(for: "Wereld", ticker: "BTC-EUR"), .crypto)
        XCTAssertEqual(ImportMapper.holdingKind(for: "VWCE (wereld-ETF)"), .etf)
        XCTAssertEqual(ImportMapper.holdingKind(for: "Vanguard FTSE All-World", ticker: "VWCE.DE"), .etf)
        XCTAssertEqual(ImportMapper.holdingKind(for: "Aandelen Philips"), .stocks)
        XCTAssertEqual(ImportMapper.holdingKind(for: "Staatsobligaties"), .bonds)
        XCTAssertEqual(ImportMapper.holdingKind(for: "Goud"), .commodities)
        XCTAssertEqual(ImportMapper.holdingKind(for: "Vastgoed crowdfunding"), .realEstate)
        XCTAssertEqual(ImportMapper.holdingKind(for: "Mijn pot"), .other)
        XCTAssertEqual(ImportMapper.potSymbol(for: "Noodfonds"), "shield.lefthalf.filled")
        XCTAssertEqual(ImportMapper.potSymbol(for: "Vakantiepot"), "airplane")
        XCTAssertEqual(ImportMapper.potSymbol(for: "Iets anders"), "banknote")
    }
}

final class ImportMappingTests: XCTestCase {

    // MARK: Spreadsheets met kopjes

    func testBudgetWithHeadingsAndTotals() throws {
        let draft = try xlsxDraft(XLSXFixtures.budget)
        XCTAssertEqual(lines(draft.rows.filter { $0.category != .overslaan }), [
            "Salaris|inkomen|2850,00", "Kinderbijslag|inkomen|250,00",
            "Huur|vasteLasten|1050,00", "Zorgverzekering|vasteLasten|145,00", "Internet en tv|vasteLasten|55,00",
            "Energie (gas, water, licht)|vasteLasten|160,00", "Autoverzekering|vasteLasten|60,00",
            "Boodschappen|variabeleLasten|380,00", "Uit eten|variabeleLasten|90,00", "Kleding|variabeleLasten|60,00",
            "Verjaardagen en cadeaus|variabeleLasten|40,00",
            "Noodfonds|spaarpot|150,00", "Vakantiepot|spaarpot|100,00",
            "VWCE (wereld-ETF)|belegging|250,00", "Bitcoin|belegging|50,00"
        ])
        // Totaalregels en "Overschot" staan uit en tellen niet mee; de titel is geen regel.
        let skipped = draft.rows.filter { $0.category == .overslaan }
        XCTAssertEqual(skipped.map(\.name), ["Totaal inkomsten", "Totaal vaste lasten", "Totaal variabele lasten", "Overschot"])
        XCTAssertTrue(skipped.allSatisfy { !$0.isIncluded && !$0.isActive })
        XCTAssertFalse(draft.rows.contains { $0.name.contains("Huishoudbegroting") })

        // Alles komt uit een kopje, dus hoge zekerheid, met het kopje als reden.
        for item in draft.activeRows {
            XCTAssertEqual(item.confidence, .hoog, item.name)
            XCTAssertTrue(item.reason.contains("kopje"), "\(item.name): \(item.reason)")
            XCTAssertEqual(item.sheet, "Begroting")
        }
        XCTAssertEqual(row(draft, "Huur").reason, "onder het kopje 'Vaste lasten'")
        XCTAssertEqual(row(draft, "Huur").sourceRow, 10)

        // Sparen en beleggen in een lijst met inkomsten en lasten: de inleg per maand.
        XCTAssertEqual(row(draft, "Noodfonds").meaning, .perMaand)
        XCTAssertEqual(row(draft, "VWCE (wereld-ETF)").meaning, .perMaand)
        XCTAssertEqual(row(draft, "VWCE (wereld-ETF)").ticker, "VWCE.DE")
        XCTAssertEqual(row(draft, "Bitcoin").ticker, "BTC-EUR")
        XCTAssertNil(row(draft, "Noodfonds").ticker)

        // Samenvatting per categorie.
        XCTAssertEqual(draft.summary.map(\.category), [.inkomen, .vasteLasten, .variabeleLasten, .spaarpot, .belegging])
        XCTAssertEqual(draft.summary.map(\.count), [2, 5, 4, 2, 2])
        XCTAssertEqual(draft.summary.map(\.total), [3100, 1470, 570, 250, 300])
        XCTAssertTrue(draft.warnings.isEmpty)
    }

    func testMonthColumnsUseCurrentMonthOrAverage() throws {
        let october = try xlsxDraft(XLSXFixtures.months, month: 10)
        XCTAssertEqual(lines(october.activeRows), [
            "Salaris|inkomen|2850,00", "Huur|vasteLasten|1075,00", "Energie|vasteLasten|126,11",
            "Boodschappen|variabeleLasten|400,00", "Noodfonds|spaarpot|150,00"
        ])
        // Elke maand gelijk: geen notitie. Huur wijkt af per maand: het bedrag van oktober.
        XCTAssertEqual(row(october, "Salaris").note, "")
        XCTAssertEqual(row(october, "Huur").note, "Bedrag van oktober.")
        // Energie: oktober is leeg, dus het gemiddelde van de 9 gevulde maanden: (190+180+150+120+100+90+95+100+110)/9.
        XCTAssertEqual(row(october, "Energie").note, "Gemiddelde van 9 gevulde maanden.")
        XCTAssertEqual(row(october, "Noodfonds").meaning, .perMaand)
        // De totaalrij en het verborgen blad tellen niet mee.
        XCTAssertEqual(october.rows.filter { $0.category == .overslaan }.map(\.name), ["Totaal"])
        XCTAssertEqual(october.warnings, ["Eén verborgen blad is overgeslagen."])

        // In maart: huur 1050, energie 150 (de waarde van maart).
        let march = try xlsxDraft(XLSXFixtures.months, month: 3)
        XCTAssertEqual(row(march, "Huur").amount, 1050)
        XCTAssertEqual(row(march, "Huur").note, "Bedrag van maart.")
        XCTAssertEqual(row(march, "Energie").amount, 150)

        // In december: huur 1075; energie weer het gemiddelde.
        let december = try xlsxDraft(XLSXFixtures.months, month: 12)
        XCTAssertEqual(row(december, "Huur").amount, 1075)
        XCTAssertEqual(row(december, "Energie").amount, 126.11)
    }

    func testCategoryColumnTextAmountsDaysAndNegatives() throws {
        let draft = try xlsxDraft(XLSXFixtures.categories)
        XCTAssertEqual(lines(draft.activeRows), [
            "Salaris|inkomen|2850,00", "Huur|vasteLasten|1050,00", "Netflix|vasteLasten|13,99", "Sportschool|vasteLasten|45,00",
            "Boodschappen|variabeleLasten|380,00", "Spaarrekening ING|spaarpot|200,00", "Wereld ETF|belegging|250,00",
            "Iets raars|variabeleLasten|25,00", "Verzekering aansprakelijkheid|vasteLasten|9,50"
        ])
        XCTAssertEqual(row(draft, "Salaris").day, 25)
        XCTAssertEqual(row(draft, "Huur").day, 1)
        XCTAssertEqual(row(draft, "Netflix").day, 12)
        XCTAssertNil(row(draft, "Sportschool").day)
        // Een echte datum in de kolom Dag geeft de dag van de maand.
        XCTAssertEqual(row(draft, "Verzekering aansprakelijkheid").day, 17)
        XCTAssertEqual(row(draft, "Wereld ETF").ticker, "VWCE.DE")
        XCTAssertEqual(row(draft, "Salaris").reason, "categorie 'Inkomen' in het bestand")
        // "Overig" is geen categorie: alleen een gok, met lage zekerheid.
        XCTAssertEqual(row(draft, "Iets raars").confidence, .laag)
        XCTAssertEqual(row(draft, "Salaris").confidence, .hoog)
        // Negatieve bedragen (-380,00 en (13,99)) zijn uitgaven, en dat wordt gemeld.
        XCTAssertEqual(draft.warnings, ["In blad 'Overzicht' staan negatieve bedragen; die zijn als uitgaven gelezen."])
    }

    func testPortfolioSheet() throws {
        let draft = try xlsxDraft(XLSXFixtures.portfolio)
        XCTAssertEqual(lines(draft.activeRows), [
            "Vanguard FTSE All-World|belegging|1612,00", "iShares Core MSCI World|belegging|800,00", "Bitcoin|belegging|950,00"
        ])
        let first = row(draft, "Vanguard FTSE All-World")
        XCTAssertEqual(first.ticker, "VWCE.DE")
        XCTAssertEqual(first.units, 12.5)
        XCTAssertEqual(first.invested, 1400)
        XCTAssertEqual(first.meaning, .saldo)
        XCTAssertEqual(row(draft, "Bitcoin").units, 0.015)
        XCTAssertEqual(row(draft, "iShares Core MSCI World").invested, 700)
        XCTAssertEqual(draft.rows.filter { $0.category == .overslaan }.map(\.name), ["Totaal"])
    }

    func testMergedCategoryCells() throws {
        let draft = try xlsxDraft(XLSXFixtures.merged)
        XCTAssertEqual(lines(draft.activeRows), [
            "Huur|vasteLasten|1050,00", "Zorgverzekering|vasteLasten|145,00", "Internet|vasteLasten|55,00",
            "Boodschappen|variabeleLasten|380,00", "Kleding|variabeleLasten|60,00", "Reisfonds|spaarpot|75,00"
        ])
        XCTAssertEqual(row(draft, "Zorgverzekering").reason, "categorie 'Vaste lasten' in het bestand")
        XCTAssertEqual(row(draft, "Reisfonds").meaning, .perMaand)
    }

    func testOneSheetPerMonthUsesTheChosenMonth() throws {
        let october = try xlsxDraft(XLSXFixtures.monthSheets, month: 10)
        XCTAssertEqual(lines(october.activeRows), ["Huur|vasteLasten|1075,00", "Boodschappen|variabeleLasten|410,00"])
        XCTAssertEqual(october.rows.map(\.sheet), ["Oktober", "Oktober"])
        XCTAssertEqual(october.warnings.count, 1)
        XCTAssertTrue(october.warnings[0].contains("blad per maand"))
        XCTAssertTrue(october.warnings[0].contains("'Augustus'"))
        XCTAssertFalse(october.warnings[0].contains("'Oktober',"))

        // Geen blad voor december: het eerste blad.
        let december = try xlsxDraft(XLSXFixtures.monthSheets, month: 12)
        XCTAssertEqual(lines(december.activeRows), ["Huur|vasteLasten|1050,00", "Boodschappen|variabeleLasten|380,00"])
        XCTAssertEqual(december.rows.map(\.sheet), ["Augustus", "Augustus"])
    }

    func testSheetNameGivesTheCategory() throws {
        let draft = try xlsxDraft(XLSXFixtures.sheetCategories)
        XCTAssertEqual(lines(draft.activeRows), [
            "Loon Jan|inkomen|2400,00", "Abonnement krant|vasteLasten|22,00", "Mevrouw Jansen|vasteLasten|90,00",
            "Kapper|variabeleLasten|35,00", "Mijn pot|belegging|300,00"
        ])
        XCTAssertEqual(row(draft, "Mevrouw Jansen").reason, "blad 'Vaste lasten'")
        XCTAssertEqual(row(draft, "Mevrouw Jansen").confidence, .hoog)
        // Het blad met alleen tekst levert niets op en geeft geen waarschuwing.
        XCTAssertTrue(draft.warnings.isEmpty)
        XCTAssertEqual(row(draft, "Mijn pot").meaning, .saldo)
    }

    func testTemplateCanBeReadBackExactly() throws {
        let expected = [
            "Salaris|inkomen|2800,00", "Kinderbijslag|inkomen|250,00", "Huur|vasteLasten|1050,00",
            "Zorgverzekering|vasteLasten|145,00", "Internet en tv|vasteLasten|55,00", "Energie|vasteLasten|120,00",
            "Boodschappen|variabeleLasten|380,00", "Uit eten|variabeleLasten|90,00", "Kleding|variabeleLasten|60,00",
            "Noodfonds|spaarpot|150,00", "Vakantiepot|spaarpot|100,00", "Wereld-ETF|belegging|250,00"
        ]
        let fromExcel = try xlsxDraft(ImportTemplate.workbookData(), name: "voorbeeld.xlsx")
        XCTAssertEqual(lines(fromExcel.rows), expected)
        XCTAssertTrue(fromExcel.warnings.isEmpty)
        XCTAssertTrue(fromExcel.rows.allSatisfy { $0.confidence == .hoog })
        XCTAssertEqual(row(fromExcel, "Salaris").day, 25)
        XCTAssertEqual(row(fromExcel, "Huur").day, 1)
        XCTAssertEqual(row(fromExcel, "Wereld-ETF").ticker, "VWCE.DE")
        XCTAssertEqual(row(fromExcel, "Wereld-ETF").meaning, .perMaand)

        let fromCSV = try csvDraft(ImportTemplate.csvText(), name: "voorbeeld.csv")
        XCTAssertEqual(lines(fromCSV.rows), expected)
        XCTAssertEqual(row(fromCSV, "Salaris").day, 25)
        XCTAssertEqual(row(fromCSV, "Wereld-ETF").ticker, "VWCE.DE")
    }

    // MARK: CSV-indelingen

    func testHeaderlessListUsesFirstTextAndNumberColumns() throws {
        let draft = try csvDraft("Huur;900\nBoodschappen;380,50\nSalaris;2.500,00\nVWCE;100\nKlusje;-25\n", name: "kaal.csv")
        XCTAssertEqual(lines(draft.rows), [
            "Huur|vasteLasten|900,00", "Boodschappen|variabeleLasten|380,50", "Salaris|inkomen|2500,00",
            "VWCE|belegging|100,00", "Klusje|variabeleLasten|25,00"
        ])
        // Zonder enig woord: een gok met lage zekerheid, en een min-teken telt als uitgave.
        XCTAssertEqual(row(draft, "Klusje").confidence, .laag)
        XCTAssertEqual(row(draft, "Klusje").reason, "negatief bedrag: uitgave, soort onbekend")
        XCTAssertEqual(row(draft, "Huur").confidence, .hoog)
        XCTAssertEqual(row(draft, "VWCE").ticker, "VWCE.DE")
        XCTAssertEqual(row(draft, "VWCE").meaning, .perMaand)
    }

    func testHeaderlessWithCategoryInFirstColumn() throws {
        let draft = try csvDraft("Vaste lasten;Huur;900\nVaste lasten;Internet;50\nSparen;Noodfonds;100\nInkomsten;Salaris;2.500\n")
        XCTAssertEqual(lines(draft.rows), [
            "Huur|vasteLasten|900,00", "Internet|vasteLasten|50,00", "Noodfonds|spaarpot|100,00", "Salaris|inkomen|2500,00"
        ])
        XCTAssertEqual(row(draft, "Huur").reason, "categorie 'Vaste lasten' in het bestand")
    }

    func testBankExportWithDebitCreditColumn() throws {
        let text = "\"Datum\";\"Naam / Omschrijving\";\"Rekening\";\"Tegenrekening\";\"Code\";\"Af Bij\";\"Bedrag (EUR)\";\"Mutatiesoort\";\"Mededelingen\"\n"
            + "\"20261001\";\"Albert Heijn 1234 Amsterdam\";\"NL01\";\"\";\"BA\";\"Af\";\"45,67\";\"Betaalautomaat\";\"x\"\n"
            + "\"20261002\";\"Werkgever BV\";\"NL01\";\"NL02\";\"OV\";\"Bij\";\"2.850,00\";\"Overschrijving\";\"Salaris oktober\"\n"
            + "\"20261003\";\"Albert Heijn 1234 Amsterdam\";\"NL01\";\"\";\"BA\";\"Af\";\"12,33\";\"Betaalautomaat\";\"x\"\n"
            + "\"20261004\";\"Vattenfall\";\"NL01\";\"\";\"IC\";\"Af\";\"89,00\";\"Incasso\";\"Energie\"\n"
        let draft = try csvDraft(text)
        // Twee betalingen bij dezelfde winkel op verschillende dagen worden opgeteld: 45,67 + 12,33.
        XCTAssertEqual(lines(draft.rows), [
            "Albert Heijn 1234 Amsterdam|variabeleLasten|58,00", "Werkgever BV|inkomen|2850,00", "Vattenfall|variabeleLasten|89,00"
        ])
        XCTAssertEqual(row(draft, "Albert Heijn 1234 Amsterdam").note, "2 regels met dezelfde naam samengevoegd.")
        XCTAssertEqual(row(draft, "Albert Heijn 1234 Amsterdam").day, 1)
        // "Bij" bij een onbekende naam: inkomen, met lage zekerheid.
        XCTAssertEqual(row(draft, "Werkgever BV").confidence, .laag)
        XCTAssertEqual(row(draft, "Werkgever BV").reason, "bijschrijving, soort onbekend")
        XCTAssertEqual(row(draft, "Werkgever BV").day, 2)
    }

    func testEnglishColumnNamesAndWords() throws {
        let draft = try csvDraft("Name,Amount,Category\nRent,900,Housing\nGroceries,350.50,Food\nSalary,2500,Income\n")
        XCTAssertEqual(lines(draft.rows), ["Rent|vasteLasten|900,00", "Groceries|variabeleLasten|350,50", "Salary|inkomen|2500,00"])
    }

    func testSeparateIncomeAndExpenseColumns() throws {
        let draft = try csvDraft("Omschrijving;Inkomsten;Uitgaven\nSalaris;2.800,00;\nHuur;;1.050,00\nSupermarkt;;-120\nBonus;500;\nIets;;30\n")
        XCTAssertEqual(lines(draft.rows), [
            "Salaris|inkomen|2800,00", "Huur|vasteLasten|1050,00", "Supermarkt|variabeleLasten|120,00",
            "Bonus|inkomen|500,00", "Iets|variabeleLasten|30,00"
        ])
        XCTAssertEqual(row(draft, "Salaris").reason, "staat in de kolom 'Inkomsten'")
        // Een onbekende naam in de uitgavenkolom is zeker een uitgave, maar de soort is een gok.
        XCTAssertEqual(row(draft, "Iets").confidence, .laag)
        XCTAssertEqual(row(draft, "Iets").reason, "staat bij de uitgaven, soort onbekend")
    }

    func testSingleIncomeColumnForcesIncome() throws {
        let draft = try csvDraft("Omschrijving;Inkomsten\nKlusje voor de buren;150\nOpa;50\n")
        XCTAssertEqual(lines(draft.rows), ["Klusje voor de buren|inkomen|150,00", "Opa|inkomen|50,00"])
    }

    func testYearlyAmountsAreDividedByTwelve() throws {
        let draft = try csvDraft("Omschrijving;Bedrag per jaar\nAutoverzekering;600\nWegenbelasting;360,00\n")
        XCTAssertEqual(lines(draft.rows), ["Autoverzekering|vasteLasten|50,00", "Wegenbelasting|vasteLasten|30,00"])
        XCTAssertEqual(row(draft, "Autoverzekering").note, "Jaarbedrag gedeeld door 12.")
        let quarterly = try csvDraft("Omschrijving;Bedrag per kwartaal\nWaterschap;90\n")
        XCTAssertEqual(row(quarterly, "Waterschap").amount, 30)
        let weekly = try csvDraft("Omschrijving;Bedrag per week\nBoodschappen;60\n")
        XCTAssertEqual(row(weekly, "Boodschappen").amount, 260)
    }

    func testDuplicatesAreMarkedOrMerged() throws {
        let draft = try csvDraft("Omschrijving;Bedrag\nHuur;900\nHuur;900\nKoffie;2,50\nKoffie;3,00\nSalaris;2000\n")
        // Twee keer precies dezelfde regel: de tweede gaat uit. Verschillende bedragen worden opgeteld.
        XCTAssertEqual(draft.rows.count, 4)
        XCTAssertEqual(draft.rows.filter { $0.name == "Huur" }.map(\.isIncluded), [true, false])
        XCTAssertEqual(draft.rows.filter { $0.name == "Huur" }[1].note, "Staat er twee keer in; de tweede is uitgezet.")
        XCTAssertEqual(row(draft, "Koffie").amount, 5.5)
        XCTAssertEqual(row(draft, "Koffie").note, "2 regels met dezelfde naam samengevoegd.")
        XCTAssertEqual(draft.summary[1].total, 900)
    }

    func testSameNameInOtherSheetIsSwitchedOff() {
        let first = ImportRow(sheet: "Begroting", name: "Huur", amount: 900, category: .vasteLasten)
        let second = ImportRow(sheet: "Overzicht", name: "huur", amount: 950, category: .vasteLasten)
        let third = ImportRow(sheet: "Overzicht", name: "Huur", amount: 900, category: .inkomen)
        let result = ImportMapper.removeDuplicates([first, second, third])
        XCTAssertEqual(result.map(\.isIncluded), [true, false, true])
        XCTAssertTrue(result[1].note.contains("Begroting"))
    }

    func testTitleRowsAndTotalsInCSV() throws {
        let draft = try csvDraft("Mijn budget\n\nUitgaven;Bedrag\nHuur;900\nBoodschappen;300\nTotaal;1200\n\nInkomsten;\nSalaris;2000\n")
        XCTAssertEqual(lines(draft.rows), [
            "Huur|vasteLasten|900,00", "Boodschappen|variabeleLasten|300,00", "Totaal|overslaan|1200,00", "Salaris|inkomen|2000,00"
        ])
        XCTAssertEqual(row(draft, "Salaris").reason, "onder het kopje 'Inkomsten'")
        XCTAssertFalse(row(draft, "Totaal").isIncluded)
    }

    func testRepeatedHeaderPerBlock() throws {
        let text = "Vaste lasten\nOmschrijving;Bedrag\nHuur;1050\nVerzekering;100\n\nVariabele lasten\nOmschrijving;Bedrag\nIets;380\nNog iets;20\n"
        let draft = try csvDraft(text)
        XCTAssertEqual(lines(draft.rows), [
            "Huur|vasteLasten|1050,00", "Verzekering|vasteLasten|100,00", "Iets|variabeleLasten|380,00", "Nog iets|variabeleLasten|20,00"
        ])
        XCTAssertEqual(row(draft, "Iets").confidence, .hoog)
    }

    func testHeadingWithTotalIsNotAnItem() throws {
        // "Vaste lasten 1.150" is het totaal van de twee regels eronder; "Sparen 100" is een gewone regel.
        let text = "Omschrijving;Bedrag\nVaste lasten;1.150\nHuur;1.050\nInternet;100\nSparen;100\n"
        let draft = try csvDraft(text)
        XCTAssertEqual(lines(draft.rows), [
            "Huur|vasteLasten|1050,00", "Internet|vasteLasten|100,00", "Sparen|spaarpot|100,00"
        ])
    }

    func testPercentagesAndOtherTextAreNotAmounts() throws {
        let draft = try csvDraft("Naam;Bedrag;Rente\nSpaarrekening;5000;2,5%\nHuur;900;\nNotitie;n.v.t.;\n")
        XCTAssertEqual(lines(draft.rows), ["Spaarrekening|spaarpot|5000,00", "Huur|vasteLasten|900,00"])
    }

    func testBalanceColumnMakesSavingsWithBalance() throws {
        let draft = try csvDraft("Naam;Saldo\nNoodfonds;2.500\nVakantie;800\n")
        XCTAssertEqual(lines(draft.rows), ["Noodfonds|spaarpot|2500,00", "Vakantie|spaarpot|800,00"])
        XCTAssertEqual(row(draft, "Vakantie").meaning, .saldo)
        XCTAssertEqual(row(draft, "Vakantie").confidence, .middel)
    }

    func testDayColumnAcceptsNumbersTextAndDates() throws {
        let draft = try csvDraft("Omschrijving;Bedrag;Dag\nHuur;900;1e\nSalaris;2800;25\nNetflix;13,99;15-10-2026\nGeen;5;\n")
        XCTAssertEqual(row(draft, "Huur").day, 1)
        XCTAssertEqual(row(draft, "Salaris").day, 25)
        XCTAssertEqual(row(draft, "Netflix").day, 15)
        XCTAssertNil(row(draft, "Geen").day)
    }

    func testMeaningOfAmountForSavingsAndInvestments() throws {
        // Kop zegt "per maand": inleg. Kop zegt "saldo" of "waarde": wat erin zit.
        XCTAssertEqual(row(try csvDraft("Naam;Bedrag per maand\nNoodfonds;100\nVWCE;50\n"), "VWCE").meaning, .perMaand)
        XCTAssertEqual(row(try csvDraft("Naam;Saldo\nNoodfonds;100\n"), "Noodfonds").meaning, .saldo)
        // De naam kan het ook zeggen.
        XCTAssertEqual(row(try csvDraft("Naam;Bedrag\nSpaarrekening saldo;1000\n"), "Spaarrekening saldo").meaning, .saldo)
        XCTAssertEqual(row(try csvDraft("Naam;Bedrag\nVWCE inleg;100\nHuur;900\n"), "VWCE inleg").meaning, .perMaand)
        // Een lijst met alleen beleggingen: wat erin zit. Een spaarpot zonder context: de inleg.
        XCTAssertEqual(row(try csvDraft("Naam;Bedrag\nVWCE;5000\nBitcoin;1200\n"), "VWCE").meaning, .saldo)
        XCTAssertEqual(row(try csvDraft("Naam;Bedrag\nNoodfonds;100\n"), "Noodfonds").meaning, .perMaand)
        // Aantal en waarde: altijd wat erin zit.
        XCTAssertEqual(row(try csvDraft("Fonds;Aantal;Koers\nVWCE;10;120,50\n"), "VWCE").meaning, .saldo)
        XCTAssertEqual(row(try csvDraft("Fonds;Aantal;Koers\nVWCE;10;120,50\n"), "VWCE").amount, 1205)
        XCTAssertEqual(row(try csvDraft("Fonds;Aantal;Koers\nVWCE;10;120,50\n"), "VWCE").units, 10)
    }

    func testDateColumnStoredAsPlainNumberGivesTheDay() {
        // Serienummer 46303 is 8 oktober 2026, zonder datumopmaak bewaard.
        let table = SpreadsheetTable(name: "Blad", rows: [
            [.text("Datum"), .text("Omschrijving"), .text("Bedrag")],
            [.number(46_303), .text("Huur"), .number(900)],
            [.date(SheetDate(year: 2026, month: 10, day: 17)), .text("Netflix"), .number(13.99)]
        ])
        let draft = ImportMapper.draft(from: SpreadsheetWorkbook(fileName: "x.xlsx", tables: [table]), preferredMonth: importOctober)
        XCTAssertEqual(row(draft, "Huur").day, 8)
        XCTAssertEqual(row(draft, "Netflix").day, 17)
    }

    func testTransactionListOverSeveralMonthsUsesOneMonth() throws {
        var text = "Datum;Omschrijving;Bedrag\n"
        // September: 6 keer Albert Heijn van 10 en 6 keer Spotify van 10; oktober: 6 keer Albert Heijn van 20 en 6 keer Spotify van 12.
        for i in 0..<6 { text += "\(i + 1)-09-2026;Albert Heijn;-10,00\n\(i + 1)-09-2026;Spotify;-10,00\n" }
        for i in 0..<6 { text += "\(i + 1)-10-2026;Albert Heijn;-20,00\n\(i + 1)-10-2026;Spotify;-12,00\n" }
        let october = try csvDraft(text, month: 10)
        XCTAssertEqual(lines(october.rows), ["Albert Heijn|variabeleLasten|120,00", "Spotify|vasteLasten|72,00"])
        XCTAssertTrue(october.warnings.contains { $0.contains("meerdere maanden") && $0.contains("oktober 2026") && $0.contains("12 regels") })
        // Voor een maand zonder boekingen nemen we de laatste maand in het bestand.
        let december = try csvDraft(text, month: 12)
        XCTAssertEqual(lines(december.rows), ["Albert Heijn|variabeleLasten|120,00", "Spotify|vasteLasten|72,00"])
        let august = try csvDraft(text, month: 8)
        XCTAssertEqual(row(august, "Albert Heijn").amount, 120)
    }

    func testBudgetWithAFewDueDatesIsNotCutIntoMonths() throws {
        let text = "Omschrijving;Bedrag;Vervaldatum\nAutoverzekering;50;15-03-2027\nHuur;900;01-10-2026\nInternet;40;05-11-2026\n"
        let draft = try csvDraft(text)
        XCTAssertEqual(lines(draft.rows), ["Autoverzekering|vasteLasten|50,00", "Huur|vasteLasten|900,00", "Internet|vasteLasten|40,00"])
        XCTAssertTrue(draft.warnings.isEmpty)
    }

    func testTwoTablesSideBySide() throws {
        // Inkomsten links, uitgaven rechts, met een lege kolom ertussen.
        let text = "Inkomsten;Bedrag;;Uitgaven;Bedrag\nSalaris;2800;;Huur;1050\nIets extra;300;;Boodschappen;380\n;;;Energie;120\n"
        let draft = try csvDraft(text)
        XCTAssertEqual(lines(draft.rows), [
            "Salaris|inkomen|2800,00", "Huur|vasteLasten|1050,00",
            "Iets extra|inkomen|300,00", "Boodschappen|variabeleLasten|380,00",
            "Energie|vasteLasten|120,00"
        ])
        // Alles onder "Inkomsten" is inkomen, ook als het woord niets zegt.
        XCTAssertEqual(row(draft, "Iets extra").reason, "onder het kopje 'Inkomsten'")
    }

    func testTwoTablesSideBySideWithSameHeaders() throws {
        let text = "Vaste lasten;Bedrag;Variabele lasten;Bedrag\nHuur;1050;Boodschappen;380\nInternet;55;Kleding;60\n"
        let draft = try csvDraft(text)
        XCTAssertEqual(draft.rows.count, 4)
        XCTAssertEqual(row(draft, "Huur").category, .vasteLasten)
        XCTAssertEqual(row(draft, "Internet").category, .vasteLasten)
        XCTAssertEqual(row(draft, "Boodschappen").category, .variabeleLasten)
        XCTAssertEqual(row(draft, "Kleding").category, .variabeleLasten)
        XCTAssertEqual(row(draft, "Kleding").amount, 60)
    }

    func testWideBankHeaderIsNotSplitIntoTables() throws {
        // Rabobank-achtig: na het bedrag komt weer een "Naam"-kolom. Dat is één brede tabel.
        let text = "Datum;Bedrag;Saldo na trn;Naam tegenpartij;Omschrijving-1\n2026-10-01;-45,67;100,00;Albert Heijn;pin\n2026-10-02;2850,00;2950,00;Werkgever;salaris\n"
        let draft = try csvDraft(text)
        XCTAssertEqual(lines(draft.rows), ["Albert Heijn|variabeleLasten|45,67", "Werkgever|inkomen|2850,00"])
    }

    func testHouseholdBookWithPerMonthAndPerYearColumns() throws {
        let text = "Huishoudboekje 2026;;\n\nInkomsten;Per maand;Per jaar\nNetto salaris;2.750,00;33.000,00\nKinderbijslag;250,00;3.000,00\nTotaal inkomsten;3.000,00;36.000,00\n\n"
            + "Vaste lasten;Per maand;Per jaar\nHuur;1.050,00;12.600,00\nZorgverzekering;145,00;1.740,00\nGas, water, licht;160,00;1.920,00\nTotaal vaste lasten;1.355,00;16.260,00\n\n"
            + "Variabele lasten;Per maand;Per jaar\nBoodschappen;380,00;4.560,00\nKleding;60,00;720,00\nTotaal;440,00;5.280,00\n\n"
            + "Sparen;Per maand;Per jaar\nNoodfonds;150,00;1.800,00\n\nBeleggen;Per maand;Per jaar\nVWCE;250,00;3.000,00\n"
        let draft = try csvDraft(text)
        // De kolom "Per maand" telt, de kolom "Per jaar" niet; elk blok heeft zijn eigen kop met het kopje erin.
        XCTAssertEqual(lines(draft.activeRows), [
            "Netto salaris|inkomen|2750,00", "Kinderbijslag|inkomen|250,00",
            "Huur|vasteLasten|1050,00", "Zorgverzekering|vasteLasten|145,00", "Gas, water, licht|vasteLasten|160,00",
            "Boodschappen|variabeleLasten|380,00", "Kleding|variabeleLasten|60,00",
            "Noodfonds|spaarpot|150,00", "VWCE|belegging|250,00"
        ])
        XCTAssertEqual(draft.rows.filter { $0.category == .overslaan }.map(\.name),
                       ["Totaal inkomsten", "Totaal vaste lasten", "Totaal"])
        XCTAssertTrue(draft.activeRows.allSatisfy { $0.confidence == .hoog })
        XCTAssertEqual(row(draft, "Noodfonds").meaning, .perMaand)
        XCTAssertEqual(row(draft, "VWCE").ticker, "VWCE.DE")
    }

    func testSavingsOverviewWithBalances() throws {
        let draft = try csvDraft("Rekening;Saldo;Rente\nSpaarrekening ING;5.230,00;2,0%\nOranje spaarrekening;1.200,50;1,5%\nVakantiespaarpot;800;\nTotaal;7.230,50;\n")
        XCTAssertEqual(lines(draft.activeRows), [
            "Spaarrekening ING|spaarpot|5230,00", "Oranje spaarrekening|spaarpot|1200,50", "Vakantiespaarpot|spaarpot|800,00"
        ])
        XCTAssertTrue(draft.activeRows.allSatisfy { $0.meaning == .saldo })
    }

    func testMonthNamesInFullAndAnAverageOverTheFilledOnes() throws {
        let text = "Post;Januari;Februari;Maart;April;Mei;Juni;Juli;Augustus;September;Oktober;November;December;Jaar\n"
            + "Salaris;2800;2800;2800;2800;2800;2800;2800;2800;2800;2800;2800;2800;33600\n"
            + "Boodschappen;380;400;390;410;;;;;;;;;1580\n"
        let draft = try csvDraft(text)
        XCTAssertEqual(row(draft, "Salaris").amount, 2800)
        XCTAssertEqual(row(draft, "Boodschappen").amount, 395)
        XCTAssertEqual(row(draft, "Boodschappen").note, "Gemiddelde van 4 gevulde maanden.")
    }

    func testRandomTablesNeverCrash() throws {
        // Een vaste toevalsgenerator maakt tabellen van kopwoorden, namen, bedragen en rommel. Het gaat erom dat er nooit
        // iets vastloopt, ook niet bij rare combinaties van kolommen; de uitkomst zelf is hier niet van belang.
        var state: UInt64 = 20_261_008
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        let pieces = ["Huur", "Salaris", "Totaal", "Vaste lasten", "Sparen", "Beleggingen", "Inkomsten", "Uitgaven", "Bedrag",
                      "Omschrijving", "Categorie", "Dag", "Datum", "Ticker", "Aantal", "Waarde", "Koers", "Saldo", "Af Bij", "Af", "Bij",
                      "Per maand", "Per jaar", "jan", "feb", "mrt", "dec", "Naam", "Ingelegd", "VWCE.DE", "25", "1e", "-45,00",
                      "(12,00)", "1.234,56", "€ 5", "0", "99999999999999999999", "1e308", "2,5%", "15-10-2026", "2026-10-15",
                      "20261015", "x", "", " ", "Albert Heijn", "Netflix", "Bitcoin", "Noodfonds", "S&P 500"]
        for iteration in 0..<300 {
            let delimiter = [";", ",", "\t"][iteration % 3]
            var text = ""
            for _ in 0..<(1 + next(25)) {
                var cells: [String] = []
                for _ in 0..<(1 + next(7)) { cells.append(pieces[next(pieces.count)]) }
                text += cells.joined(separator: delimiter) + "\n"
            }
            guard let book = try? SpreadsheetReader.read(Data(text.utf8), fileName: "w.csv") else { continue }
            let draft = ImportMapper.draft(from: book, preferredMonth: YearMonth(year: 2026, month: 10))
            var data = FinanceData(startMonth: YearMonth(year: 2026, month: 10))
            data.applyImport(draft, month: YearMonth(year: 2026, month: 10), existing: iteration % 2 == 0 ? .skip : .update,
                             now: Date(timeIntervalSince1970: 1_791_460_800))
            _ = draft.summary
            _ = data.remaining(in: YearMonth(year: 2026, month: 10))
        }
    }

    func testEmptyOrUnreadableTablesGiveNoRows() throws {
        let noNumbers = try csvDraft("Huur\nEnergie\nInternet\n")
        XCTAssertTrue(noNumbers.isEmpty)
        let onlyText = try csvDraft("a;b\nc;d\n")
        XCTAssertTrue(onlyText.isEmpty)
        let numbersWithoutNames = try csvDraft("1;2\n3;4\n")
        XCTAssertTrue(numbersWithoutNames.isEmpty)
    }

    func testManyRowsStayFastAndAreMergedByName() throws {
        var text = "Datum;Omschrijving;Bedrag\n"
        for i in 0..<2_000 {
            text += "\(i % 28 + 1)-10-2026;Winkel \(i % 40);\(i % 7 + 1),50\n"
        }
        let draft = try csvDraft(text)
        XCTAssertEqual(draft.rows.count, 40)
        // Het totaal klopt met de som van alle regels: elke regel i heeft bedrag (i % 7 + 1) + 0,50.
        var expectedCents = 0
        for i in 0..<2_000 { expectedCents += (i % 7 + 1) * 100 + 50 }
        XCTAssertEqual(draft.rows.reduce(0) { $0 + CentsMath.int($1.amount) }, expectedCents)
    }

    func testVeryLongSheetIsCappedWithWarning() throws {
        var text = "Omschrijving;Bedrag\n"
        for i in 0..<5_100 { text += "Post \(i);1\n" }
        let draft = try csvDraft(text)
        XCTAssertEqual(draft.rows.count, 5_000)
        XCTAssertTrue(draft.warnings.contains { $0.contains("alleen de eerste") })
    }

    func testWorkbookWithOnlyHiddenSheetStillReadsThem() {
        let hidden = SpreadsheetTable(name: "Weg", rows: [[.text("Omschrijving"), .text("Bedrag")], [.text("Huur"), .number(900)]], isHidden: true)
        let draft = ImportMapper.draft(from: SpreadsheetWorkbook(fileName: "x.xlsx", tables: [hidden]), preferredMonth: importOctober)
        XCTAssertEqual(lines(draft.rows), ["Huur|vasteLasten|900,00"])
    }

    // MARK: Conceptlijst aanpassen

    private func sampleDraft() -> ImportDraft {
        ImportDraft(fileName: "x.csv", rows: [
            ImportRow(name: "Salaris", amount: 2800, category: .inkomen),
            ImportRow(name: "Huur", amount: 1000, category: .vasteLasten),
            ImportRow(name: "Boodschappen", amount: 300.5, category: .variabeleLasten),
            ImportRow(name: "Noodfonds", amount: 100, category: .spaarpot, meaning: .perMaand),
            ImportRow(name: "VWCE", amount: 250, category: .belegging, meaning: .perMaand),
            ImportRow(name: "Totaal", amount: 4000, category: .overslaan, isIncluded: false)
        ])
    }

    func testSummaryOnlyCountsActiveRows() {
        var draft = sampleDraft()
        XCTAssertEqual(draft.activeCount, 5)
        XCTAssertEqual(draft.total(of: .variabeleLasten), 300.5)
        XCTAssertEqual(draft.count(of: .inkomen), 1)
        let id = draft.rows[1].id
        draft.setIncluded(false, for: id)
        XCTAssertEqual(draft.count(of: .vasteLasten), 0)
        XCTAssertEqual(draft.total(of: .vasteLasten), 0)
        XCTAssertEqual(draft.activeCount, 4)
        // Een totaalregel kun je niet aanzetten zolang hij op "overslaan" staat.
        let totalID = draft.rows[5].id
        draft.setIncluded(true, for: totalID)
        XCTAssertFalse(draft.rows[5].isIncluded)
        XCTAssertEqual(draft.rows(in: .overslaan).count, 1)
    }

    func testChangingCategory() {
        var draft = sampleDraft()
        let id = draft.rows[2].id
        draft.setCategory(.vasteLasten, for: id)
        XCTAssertEqual(draft.rows[2].category, .vasteLasten)
        XCTAssertEqual(draft.rows[2].confidence, .hoog)
        XCTAssertEqual(draft.rows[2].reason, "zelf gekozen")
        XCTAssertEqual(draft.total(of: .vasteLasten), 1300.5)
        // Een uitgezette rij gaat weer aan als je er een categorie voor kiest.
        let totalID = draft.rows[5].id
        draft.setCategory(.variabeleLasten, for: totalID)
        XCTAssertTrue(draft.rows[5].isIncluded)
        // "Overslaan" zet de rij uit.
        draft.setCategory(.overslaan, for: id)
        XCTAssertFalse(draft.rows[2].isIncluded)
        XCTAssertEqual(draft.rows[2].reason, "overgeslagen door jou")
        // Onbekende id: geen effect, geen crash.
        draft.setCategory(.inkomen, for: UUID())
        draft.setMeaning(.saldo, for: UUID())
    }

    func testChangingToInvestmentFillsInKnownTicker() {
        var draft = ImportDraft(rows: [ImportRow(name: "VWCE (wereld-ETF)", amount: 100, category: .variabeleLasten)])
        draft.setCategory(.belegging, for: draft.rows[0].id)
        XCTAssertEqual(draft.rows[0].ticker, "VWCE.DE")
    }

    func testMeaningCanBeChanged() {
        var draft = sampleDraft()
        draft.setMeaning(.saldo, for: draft.rows[3].id)
        XCTAssertEqual(draft.rows[3].meaning, .saldo)
    }

    func testSalaryRowsAreSwitchedOffWhenSalaryIsAlreadySet() {
        var draft = ImportDraft(rows: [
            ImportRow(name: "Netto salaris", amount: 2800, category: .inkomen),
            ImportRow(name: "Kinderbijslag", amount: 250, category: .inkomen),
            ImportRow(name: "Loon bijbaan", amount: 300, category: .inkomen)
        ])
        XCTAssertEqual(draft.disableSalaryRows(configuredSalary: 0), 0)
        XCTAssertEqual(draft.activeCount, 3)
        // Alleen je eigen salaris gaat uit; "Loon bijbaan" kan ander inkomen zijn en blijft aan, met een opmerking.
        XCTAssertEqual(draft.disableSalaryRows(configuredSalary: 3000), 1)
        XCTAssertEqual(draft.rows.map(\.isIncluded), [false, true, true])
        XCTAssertTrue(draft.rows[0].note.contains("salaris staat al"))
        XCTAssertEqual(draft.rows[1].note, "")
        XCTAssertTrue(draft.rows[2].note.contains("Staat je eigen salaris al in de instellingen?"))
        // Nog een keer aanroepen verandert niets en herhaalt de opmerking niet.
        XCTAssertEqual(draft.disableSalaryRows(configuredSalary: 3000), 0)
        XCTAssertEqual(draft.rows[2].note.components(separatedBy: "Staat je eigen").count, 2)
    }

    func testOnlyPlainSalaryNamesAreSwitchedOff() {
        let names = ["Salaris", "Netto salaris", "Salaris per maand", "Nettoloon", "Loon", "Mijn salaris", "Maandsalaris",
                     "Salaris partner", "Salaris vrouw", "Loon bijbaan", "Salaris 2026", "Kinderbijslag"]
        var draft = ImportDraft(rows: names.map { ImportRow(name: $0, amount: 100, category: .inkomen) })
        XCTAssertEqual(draft.disableSalaryRows(configuredSalary: 3000), 7)
        XCTAssertEqual(draft.rows.map(\.isIncluded), [false, false, false, false, false, false, false,
                                                       true, true, true, true, true])
        // Een salarisregel die geen inkomen is, blijft met rust.
        var other = ImportDraft(rows: [ImportRow(name: "Salaris", amount: 100, category: .vasteLasten)])
        XCTAssertEqual(other.disableSalaryRows(configuredSalary: 3000), 0)
        XCTAssertTrue(other.rows[0].isIncluded)
    }

    // MARK: Herstel na de review

    /// Een tweede tabel onder "Inkomsten" met een algemene kop (Uitgaven, Kosten, ...): die regels zijn geen inkomen.
    func testSecondTableWithGenericHeadingIsNotIncome() throws {
        for heading in ["Uitgaven", "Uitgave", "Lasten", "Kosten", "Overige uitgaven"] {
            let text = "Inkomsten;Bedrag\nSalaris;2800\nBonus;300\n\n\(heading);Bedrag\nHuur;1050\nBoodschappen;380\nNetflix;13,99\n"
            let draft = try csvDraft(text)
            XCTAssertEqual(lines(draft.rows), [
                "Salaris|inkomen|2800,00", "Bonus|inkomen|300,00",
                "Huur|vasteLasten|1050,00", "Boodschappen|variabeleLasten|380,00", "Netflix|vasteLasten|13,99"
            ], heading)
            XCTAssertFalse(row(draft, "Huur").reason.contains("Inkomsten"), heading)
            XCTAssertEqual(row(draft, "Huur").confidence, .hoog, heading)
        }
        // Een onbekende naam onder zo'n kop is een uitgave (een gok), geen inkomen.
        let unknown = try csvDraft("Inkomsten;Bedrag\nSalaris;2800\n\nUitgaven;Bedrag\nIets bijzonders;50\n")
        XCTAssertEqual(row(unknown, "Iets bijzonders").category, .variabeleLasten)
    }

    func testSavingsListKeepsTheBalanceNextToTheMonthlyAmount() throws {
        let variants = [
            "Spaarpot;Saldo;Maandinleg\nNoodfonds;5000;150\nVakantiepot;800;50\n",
            "Spaarpot;Gespaard;Per maand\nNoodfonds;5000;150\nVakantiepot;800;50\n",
            "Spaarpot;Tegoed;Inleg\nNoodfonds;5.000,00;150\nVakantiepot;€ 800;50\n",
            "Spaarpot;Huidig bedrag;Maandinleg\nNoodfonds;5000;150\nVakantiepot;800;50\n"
        ]
        for text in variants {
            let draft = try csvDraft(text)
            XCTAssertEqual(lines(draft.activeRows), ["Noodfonds|spaarpot|150,00", "Vakantiepot|spaarpot|50,00"], text)
            XCTAssertEqual(row(draft, "Noodfonds").meaning, .perMaand, text)
            XCTAssertEqual(row(draft, "Noodfonds").balance, 5000, text)
            XCTAssertEqual(row(draft, "Vakantiepot").balance, 800, text)
        }
        let holdings = try csvDraft("Naam;Soort;Saldo;Inleg\nWereld ETF;Beleggingen;12000;250\n")
        XCTAssertEqual(lines(holdings.activeRows), ["Wereld ETF|belegging|250,00"])
        XCTAssertEqual(row(holdings, "Wereld ETF").meaning, .perMaand)
        XCTAssertEqual(row(holdings, "Wereld ETF").balance, 12000)
        // Aantal x koers naast een inleg per maand is ook een saldo.
        let priced = try csvDraft("Naam;Aantal;Koers;Maandinleg\nVWCE;10;120;100\n")
        XCTAssertEqual(row(priced, "VWCE").amount, 100)
        XCTAssertEqual(row(priced, "VWCE").balance, 1200)
        XCTAssertEqual(row(priced, "VWCE").meaning, .perMaand)
    }

    func testBalanceOnlyListsAndOtherRowsHaveNoSeparateBalance() throws {
        // Alleen een saldo: het bedrag is het saldo zelf, er is geen tweede getal.
        let onlyBalance = try csvDraft("Naam;Gespaard\nNoodfonds;2.500\nVakantie;800\n")
        XCTAssertEqual(lines(onlyBalance.activeRows), ["Noodfonds|spaarpot|2500,00", "Vakantie|spaarpot|800,00"])
        XCTAssertEqual(row(onlyBalance, "Noodfonds").meaning, .saldo)
        XCTAssertNil(row(onlyBalance, "Noodfonds").balance)
        // Een bankexport met "Saldo na mutatie" geeft lasten en inkomen geen saldo mee.
        let bank = try csvDraft("Datum;Naam / Omschrijving;Af Bij;Bedrag (EUR);Saldo na mutatie\n20261001;Albert Heijn;Af;45,67;1000,00\n20261002;Werkgever;Bij;2850,00;3850,00\n")
        XCTAssertTrue(bank.rows.allSatisfy { $0.balance == nil })
        // "Gespaard per maand" is wel een inleg.
        let monthly = try csvDraft("Naam;Gespaard per maand\nNoodfonds;100\n")
        XCTAssertEqual(row(monthly, "Noodfonds").meaning, .perMaand)
        XCTAssertNil(row(monthly, "Noodfonds").balance)
    }

    func testNegativeWarningOnlyForRealMinusSigns() throws {
        // Een kolom Uitgaven en Af/Bij maken bedragen negatief, maar er staat geen min-teken in het bestand.
        let columns = try csvDraft("Omschrijving;Inkomsten;Uitgaven\nSalaris;2800;\nHuur;;1050\nBoodschappen;;380\n")
        XCTAssertTrue(columns.warnings.isEmpty, "\(columns.warnings)")
        XCTAssertEqual(row(columns, "Huur").category, .vasteLasten)
        let bank = try csvDraft("Datum;Naam;Af Bij;Bedrag\n20261001;Albert Heijn;Af;45,67\n20261002;Werkgever BV;Bij;2850,00\n20261003;Vattenfall;Af;89,00\n")
        XCTAssertTrue(bank.warnings.isEmpty, "\(bank.warnings)")
        // Een echt min-teken geeft de melding wel, ook in een kolom Uitgaven.
        let minus = try csvDraft("Omschrijving;Inkomsten;Uitgaven\nSalaris;2800;\nHuur;;-1050\n")
        XCTAssertEqual(minus.warnings.count, 1)
        XCTAssertTrue(minus.warnings[0].contains("negatieve bedragen"))
        let plain = try csvDraft("Omschrijving;Bedrag\nHuur;-900\nSalaris;2500\n")
        XCTAssertEqual(plain.warnings.count, 1)
        // Een min-teken in de kolom Inkomsten maakt er geen uitgave van.
        let income = try csvDraft("Omschrijving;Inkomsten;Uitgaven\nTerugbetaling;-50;\nHuur;;900\n")
        XCTAssertEqual(row(income, "Terugbetaling").category, .inkomen)
        XCTAssertTrue(income.warnings.isEmpty, "\(income.warnings)")
    }

    func testAmountsWithDashCentsAreWholeEuros() throws {
        let draft = try csvDraft("Omschrijving;Bedrag\nWerk;€ 2.800,-\nHuur;€ 1.050,-\nInternet;55,-\nBoodschappen;-380,50\n")
        XCTAssertEqual(row(draft, "Werk").amount, 2800)
        XCTAssertEqual(row(draft, "Huur").amount, 1050)
        XCTAssertEqual(row(draft, "Internet").amount, 55)
        XCTAssertEqual(row(draft, "Boodschappen").amount, 380.5)
        // Alleen het echte min-teken geeft de melding, en maar één keer.
        XCTAssertEqual(draft.warnings.count, 1)
        // Zonder min-teken: geen melding en "Werk" is niet als uitgave gelezen.
        let clean = try csvDraft("Omschrijving;Bedrag\nSalaris;€ 2.800,-\nHuur;€ 1.050,-\n")
        XCTAssertTrue(clean.warnings.isEmpty, "\(clean.warnings)")
        XCTAssertEqual(row(clean, "Salaris").category, .inkomen)
    }

    func testMonthsInRowsAreReportedNotImported() throws {
        let text = "Maand;Salaris;Huur\njanuari;2800;1050\nfebruari;2800;1050\nmaart;2800;1050\n"
        let draft = try csvDraft(text)
        XCTAssertTrue(draft.rows.isEmpty, "\(lines(draft.rows))")
        XCTAssertTrue(draft.warnings.contains { $0.contains("maanden onder elkaar") }, "\(draft.warnings)")
        // Eén enkele regel die zo heet (een pot "Mei") is gewoon een regel.
        let single = try csvDraft("Naam;Bedrag\nMei;50\nHuur;900\nBoodschappen;300\n")
        XCTAssertEqual(single.rows.map(\.name), ["Mei", "Huur", "Boodschappen"])
        XCTAssertFalse(single.warnings.contains { $0.contains("maanden onder elkaar") })
    }

    func testStructuralHintOnlyForStrongKeywords() throws {
        // "Vakantie" is een zwak woord (variabele lasten) en hoort onder Sparen gewoon thuis.
        let draft = try csvDraft("Sparen;Bedrag\nVakantie;100\nAuto;50\nHypotheek;75\n")
        XCTAssertEqual(row(draft, "Vakantie").category, .spaarpot)
        XCTAssertEqual(row(draft, "Vakantie").confidence, .hoog)
        XCTAssertEqual(row(draft, "Vakantie").reason, "onder het kopje 'Sparen'")
        XCTAssertEqual(row(draft, "Auto").confidence, .hoog)
        // Een sterk woord dat iets anders zegt blijft een waarschuwing.
        XCTAssertEqual(row(draft, "Hypotheek").confidence, .middel)
        XCTAssertTrue(row(draft, "Hypotheek").reason.contains("let op"))
    }
}

final class ImportApplyTests: XCTestCase {

    private let now = day(oct2026, 8)

    private func plan(_ data: FinanceData, _ month: YearMonth = oct2026) -> MonthPlan { data.plan(for: month) }

    // MARK: Inkomen en lasten

    func testIncomeAndExpensesAreAddedAsRecurringLines() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [
            ImportRow(name: "Bonus", amount: 500, category: .inkomen, day: 15),
            ImportRow(name: "Zorgverzekering", amount: 145, category: .vasteLasten, day: 1),
            ImportRow(name: "Boodschappen", amount: 380, category: .variabeleLasten)
        ])
        let report = data.applyImport(draft, month: oct2026, now: now)

        XCTAssertEqual(report.addedCount, 3)
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.month, oct2026)

        let october = plan(data)
        let bonus = october.extraIncome.first { $0.name == "Bonus" }
        XCTAssertEqual(bonus?.amount, 500)
        XCTAssertEqual(bonus?.isRecurring, true)
        XCTAssertEqual(bonus?.day, 15)
        let insurance = october.expenses.first { $0.name == "Zorgverzekering" }
        XCTAssertEqual(insurance?.amount, 145)
        XCTAssertEqual(insurance?.kind, .fixed)
        XCTAssertEqual(insurance?.isRecurring, true)
        XCTAssertEqual(insurance?.day, 1)
        let groceries = october.expenses.first { $0.name == "Boodschappen" }
        XCTAssertEqual(groceries?.kind, .variable)
        XCTAssertNil(groceries?.day)

        // Wat al in de maand stond (huur en toeslag, terugkerend uit augustus) blijft staan.
        XCTAssertNotNil(october.expenses.first { $0.name == "Huur" })
        XCTAssertNotNil(october.extraIncome.first { $0.name == "Toeslag" })

        // Cijfers: inkomen 3000 + 100 + 500, vast 1000 + 145, variabel 380.
        let overview = data.expenseOverview(in: oct2026)
        XCTAssertEqual(overview.income, 3600)
        XCTAssertEqual(overview.fixed, 1145)
        XCTAssertEqual(overview.variable, 380)
        XCTAssertEqual(data.remaining(in: oct2026), 3600 - 1145 - 380)
    }

    func testRecurringLinesCarryOverToNextMonths() {
        var data = makeBaseData()
        data.applyImport(ImportDraft(rows: [ImportRow(name: "Zorgverzekering", amount: 145, category: .vasteLasten)]),
                         month: oct2026, now: now)
        let november = YearMonth(year: 2026, month: 11)
        XCTAssertEqual(plan(data, november).expenses.first { $0.name == "Zorgverzekering" }?.amount, 145)
        // Eerdere maanden veranderen niet.
        XCTAssertNil(plan(data, sep2026).expenses.first { $0.name == "Zorgverzekering" })
    }

    func testExistingNamesAreSkippedCaseInsensitively() {
        var data = makeBaseData()
        let before = data
        let draft = ImportDraft(rows: [
            ImportRow(name: "HUUR", amount: 1200, category: .vasteLasten),
            ImportRow(name: "  toeslag ", amount: 999, category: .inkomen),
            ImportRow(name: "Eenmalig", amount: 5, category: .variabeleLasten)
        ])
        let report = data.applyImport(draft, month: aug2026, now: now)
        XCTAssertEqual(report.addedCount, 0)
        XCTAssertEqual(report.skippedCount, 3)
        XCTAssertEqual(report.lines.map(\.outcome), [.skippedExisting, .skippedExisting, .skippedExisting])
        XCTAssertEqual(data.plan(for: aug2026), before.plan(for: aug2026))
        XCTAssertEqual(data.plan(for: aug2026).expenses.first { $0.name == "Huur" }?.amount, 1000)
    }

    func testUpdatePolicyChangesAmountOfExistingLines() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [
            ImportRow(name: "huur", amount: 1200, category: .vasteLasten, day: 3),
            ImportRow(name: "Toeslag", amount: 150, category: .inkomen),
            ImportRow(name: "Nieuw", amount: 20, category: .variabeleLasten)
        ])
        let report = data.applyImport(draft, month: aug2026, existing: .update, now: now)
        XCTAssertEqual(report.updatedCount, 2)
        XCTAssertEqual(report.addedCount, 1)
        XCTAssertEqual(report.summaryText, "1 toegevoegd, 2 bijgewerkt, 0 overgeslagen")
        let august = data.plan(for: aug2026)
        XCTAssertEqual(august.expenses.filter { $0.name.lowercased() == "huur" }.count, 1)
        XCTAssertEqual(august.expenses.first { $0.name == "Huur" }?.amount, 1200)
        XCTAssertEqual(august.expenses.first { $0.name == "Huur" }?.day, 3)
        XCTAssertEqual(august.extraIncome.first { $0.name == "Toeslag" }?.amount, 150)
    }

    func testApplyingTwiceDoesNotDuplicateAnything() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [
            ImportRow(name: "Bonus", amount: 500, category: .inkomen),
            ImportRow(name: "Zorgverzekering", amount: 145, category: .vasteLasten),
            ImportRow(name: "Noodfonds", amount: 100, category: .spaarpot, meaning: .saldo),
            ImportRow(name: "VWCE", amount: 250, category: .belegging, meaning: .perMaand)
        ])
        data.applyImport(draft, month: oct2026, now: now)
        let afterFirst = data
        let second = data.applyImport(draft, month: oct2026, now: now)
        XCTAssertEqual(second.addedCount, 0)
        XCTAssertEqual(second.skippedCount, 4)
        XCTAssertEqual(data, afterFirst)
    }

    func testSwitchedOffAndSkippedRowsAreNotImported() {
        var data = makeBaseData()
        let before = data
        let draft = ImportDraft(rows: [
            ImportRow(name: "Uit", amount: 10, category: .vasteLasten, isIncluded: false),
            ImportRow(name: "Totaal", amount: 10, category: .overslaan),
            ImportRow(name: "Nul", amount: 0, category: .variabeleLasten),
            ImportRow(name: "  ", amount: 10, category: .variabeleLasten)
        ])
        let report = data.applyImport(draft, month: oct2026, now: now)
        XCTAssertEqual(report.lines.count, 0)
        XCTAssertEqual(report.notSelected, 4)
        XCTAssertEqual(data, before)
        // Er is niets veranderd, dus ook geen opgeslagen plan voor oktober.
        XCTAssertNil(data.months[oct2026.key])
    }

    func testDaysAreClamped() {
        var data = makeBaseData()
        data.applyImport(ImportDraft(rows: [ImportRow(name: "Ver", amount: 5, category: .variabeleLasten, day: 40)]), month: oct2026, now: now)
        XCTAssertEqual(plan(data).expenses.first { $0.name == "Ver" }?.day, 31)
    }

    func testMonthBeforeStartMonthMovesToStartMonth() {
        var data = makeBaseData()
        let report = data.applyImport(ImportDraft(rows: [ImportRow(name: "Nieuw", amount: 5, category: .variabeleLasten)]),
                                      month: YearMonth(year: 2026, month: 1), now: now)
        XCTAssertEqual(report.month, aug2026)
        XCTAssertEqual(report.notes.count, 1)
        XCTAssertTrue(report.notes[0].contains("augustus 2026"))
        XCTAssertNotNil(data.plan(for: aug2026).expenses.first { $0.name == "Nieuw" })
    }

    // MARK: Spaarpotten

    func testSavingsWithBalanceBecomesOpeningBalance() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [ImportRow(name: "Noodfonds", amount: 2500.5, category: .spaarpot, meaning: .saldo)])
        let report = data.applyImport(draft, month: oct2026, now: now)
        XCTAssertEqual(report.addedCount, 1)
        guard let pot = data.pots.first else { return XCTFail("Geen spaarpot") }
        XCTAssertEqual(pot.name, "Noodfonds")
        XCTAssertEqual(pot.monthlyContribution, 0)
        XCTAssertEqual(pot.startMonth, oct2026)
        XCTAssertEqual(pot.symbol, "shield.lefthalf.filled")
        XCTAssertEqual(data.potEntries.count, 1)
        XCTAssertEqual(data.potEntries[0].kind, .opening)
        XCTAssertEqual(data.potEntries[0].amount, 2500.5)
        XCTAssertEqual(data.potBalance(pot.id, asOf: day(oct2026, 20)), 2500.5)
        XCTAssertEqual(data.allocation(pot.id, in: oct2026), 0)
    }

    func testSavingsPerMonthBecomesMonthlyContribution() {
        var data = makeBaseData()
        let remainingBefore = data.remaining(in: oct2026)
        let draft = ImportDraft(rows: [ImportRow(name: "Vakantiepot", amount: 150, category: .spaarpot, day: 26, meaning: .perMaand)])
        data.applyImport(draft, month: oct2026, now: now)
        guard let pot = data.pots.first else { return XCTFail("Geen spaarpot") }
        XCTAssertEqual(pot.monthlyContribution, 150)
        XCTAssertEqual(pot.transferDay, 26)
        XCTAssertEqual(pot.symbol, "airplane")
        XCTAssertTrue(data.potEntries.isEmpty)
        XCTAssertEqual(data.allocation(pot.id, in: oct2026), 150)
        // De inleg gaat van wat er over was af.
        XCTAssertEqual(data.remaining(in: oct2026), remainingBefore - 150)
        // En zit na de overschrijfdag in het saldo.
        XCTAssertEqual(data.potBalance(pot.id, asOf: day(oct2026, 28)), 150)
        XCTAssertEqual(data.potBalance(pot.id, asOf: day(oct2026, 20)), 0)
    }

    func testExistingPotIsSkippedOrUpdated() {
        var data = makeBaseData()
        let buffer = addBufferPot(&data)   // "Buffer", beginsaldo 500, inleg 200
        let skipped = data.applyImport(ImportDraft(rows: [ImportRow(name: "BUFFER", amount: 999, category: .spaarpot, meaning: .perMaand)]),
                                       month: oct2026, now: now)
        XCTAssertEqual(skipped.skippedCount, 1)
        XCTAssertEqual(data.pots.count, 1)
        XCTAssertEqual(data.pots[0].monthlyContribution, 200)

        let updated = data.applyImport(ImportDraft(rows: [ImportRow(name: "buffer", amount: 250, category: .spaarpot, meaning: .perMaand)]),
                                       month: oct2026, existing: .update, now: now)
        XCTAssertEqual(updated.updatedCount, 1)
        XCTAssertEqual(data.pots.count, 1)
        XCTAssertEqual(data.pots[0].monthlyContribution, 250)
        XCTAssertEqual(data.allocation(buffer.id, in: oct2026), 250)
    }

    func testUpdatingPotBalanceBooksTheDifference() {
        var data = makeBaseData()
        let buffer = addBufferPot(&data)
        let before = data.potBalance(buffer.id, asOf: now)
        data.applyImport(ImportDraft(rows: [ImportRow(name: "Buffer", amount: 1000, category: .spaarpot, meaning: .saldo)]),
                         month: oct2026, existing: .update, now: now)
        XCTAssertNotEqual(before, 1000)
        XCTAssertEqual(data.potBalance(buffer.id, asOf: now), 1000)
    }

    func testPotColorsRotate() {
        var data = makeBaseData()
        let rows = (0..<10).map { ImportRow(name: "Pot \($0)", amount: 10, category: .spaarpot, meaning: .saldo) }
        data.applyImport(ImportDraft(rows: rows), month: oct2026, now: now)
        XCTAssertEqual(data.pots.map(\.colorIndex), [0, 1, 2, 3, 4, 5, 6, 7, 0, 1])
    }

    // MARK: Beleggingen

    func testInvestmentWithValueGetsInvestedAndSnapshot() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [
            ImportRow(name: "Vanguard FTSE All-World", amount: 1612, category: .belegging, meaning: .saldo,
                      ticker: "VWCE.DE", units: 12.5, invested: 1400)
        ])
        data.applyImport(draft, month: oct2026, now: now)
        guard let holding = data.holdings.first else { return XCTFail("Geen belegging") }
        XCTAssertEqual(holding.name, "Vanguard FTSE All-World")
        XCTAssertEqual(holding.kind, .etf)
        XCTAssertEqual(holding.ticker, "VWCE.DE")
        XCTAssertEqual(holding.units, 12.5)
        XCTAssertEqual(holding.investedTotal, 1400)
        XCTAssertEqual(holding.monthlyContribution, 0)
        XCTAssertEqual(holding.expectedReturn, HoldingKind.etf.defaultReturn)
        XCTAssertEqual(holding.annualCost, HoldingKind.etf.defaultCost)
        XCTAssertEqual(holding.snapshots.count, 1)
        XCTAssertEqual(holding.snapshots[0].value, 1612)
        XCTAssertEqual(holding.snapshots[0].invested, 1400)
        let state = data.holdingStateNow(holding, current: oct2026)
        XCTAssertEqual(state?.value, 1612)
        XCTAssertEqual(state?.invested, 1400)
    }

    func testInvestmentWithoutSeparateInvestedUsesTheAmount() {
        var data = makeBaseData()
        data.applyImport(ImportDraft(rows: [ImportRow(name: "Bitcoin", amount: 950, category: .belegging, meaning: .saldo, ticker: "BTC-EUR")]),
                         month: oct2026, now: now)
        let holding = data.holdings[0]
        XCTAssertEqual(holding.kind, .crypto)
        XCTAssertEqual(holding.investedTotal, 950)
        XCTAssertEqual(data.holdingValueNow(holding, current: oct2026), 950)
    }

    func testInvestmentPerMonthIsAMonthlyContributionFromThisMonth() {
        var data = makeBaseData()
        let remainingBefore = data.remaining(in: oct2026)
        data.applyImport(ImportDraft(rows: [ImportRow(name: "VWCE (wereld-ETF)", amount: 250, category: .belegging, day: 27,
                                                      meaning: .perMaand, ticker: "VWCE.DE")]),
                         month: oct2026, now: now)
        let holding = data.holdings[0]
        XCTAssertEqual(holding.monthlyContribution, 250)
        XCTAssertEqual(holding.transferDay, 27)
        XCTAssertEqual(holding.investedTotal, 0)
        XCTAssertNil(holding.units)
        XCTAssertEqual(holding.startMonth, oct2026)
        XCTAssertEqual(data.allocation(holding.id, in: oct2026), 250)
        XCTAssertEqual(data.remaining(in: oct2026), remainingBefore - 250)
        // De inleg van oktober telt mee in de waarde van oktober (beginpunt 0 aan het eind van september).
        let state = data.holdingStateNow(holding, current: oct2026)
        XCTAssertEqual(state?.value, 250)
        XCTAssertEqual(state?.invested, 250)
    }

    func testExistingInvestmentIsSkippedOrUpdated() {
        var data = makeBaseData()
        data.applyImport(ImportDraft(rows: [ImportRow(name: "Bitcoin", amount: 100, category: .belegging, meaning: .saldo)]),
                         month: oct2026, now: now)
        let skipped = data.applyImport(ImportDraft(rows: [ImportRow(name: "bitcoin", amount: 500, category: .belegging, meaning: .saldo)]),
                                       month: oct2026, now: now)
        XCTAssertEqual(skipped.skippedCount, 1)
        XCTAssertEqual(data.holdings.count, 1)
        XCTAssertEqual(data.holdingValueNow(data.holdings[0], current: oct2026), 100)

        let updated = data.applyImport(ImportDraft(rows: [ImportRow(name: "bitcoin", amount: 500, category: .belegging, meaning: .saldo, invested: 300)]),
                                       month: oct2026, existing: .update, now: now)
        XCTAssertEqual(updated.updatedCount, 1)
        XCTAssertEqual(data.holdings.count, 1)
        XCTAssertEqual(data.holdingValueNow(data.holdings[0], current: oct2026), 500)
        XCTAssertEqual(data.holdings[0].investedTotal, 300)
    }

    // MARK: Herstel na de review

    /// Bij "bijwerken" worden de verdeling van een pot en een belegging aangepast door `updatePot` en `updateHolding`;
    /// het plan met de nieuwe inkomsten en lasten mag dat niet overschrijven.
    func testUpdatePolicyKeepsNewAllocationsWhenIncomeAndExpensesAreImportedToo() {
        var data = makeBaseData()
        let buffer = addBufferPot(&data)   // inleg 200
        let holding = Holding(name: "Wereld ETF", kind: .etf, monthlyContribution: 50, startMonth: aug2026)
        data.addHolding(holding, initialValue: 1000, now: day(aug2026, 5))
        XCTAssertEqual(data.allocation(buffer.id, in: oct2026), 200)
        XCTAssertEqual(data.allocation(holding.id, in: oct2026), 50)

        let draft = ImportDraft(rows: [
            ImportRow(name: "Bonus", amount: 500, category: .inkomen),
            ImportRow(name: "Zorgverzekering", amount: 145, category: .vasteLasten),
            ImportRow(name: "Buffer", amount: 250, category: .spaarpot, meaning: .perMaand),
            ImportRow(name: "Wereld ETF", amount: 80, category: .belegging, meaning: .perMaand)
        ])
        let report = data.applyImport(draft, month: oct2026, existing: .update, now: now)
        XCTAssertEqual(report.addedCount, 2)
        XCTAssertEqual(report.updatedCount, 2)

        let october = data.plan(for: oct2026)
        XCTAssertEqual(october.extraIncome.first { $0.name == "Bonus" }?.amount, 500)
        XCTAssertEqual(october.expenses.first { $0.name == "Zorgverzekering" }?.amount, 145)
        XCTAssertEqual(data.allocation(buffer.id, in: oct2026), 250)
        XCTAssertEqual(data.allocation(holding.id, in: oct2026), 80)
        XCTAssertEqual(october.allocations[buffer.id.uuidString], 250)
        XCTAssertEqual(october.allocations[holding.id.uuidString], 80)
        // En de maandcijfers kloppen: 3000 + 100 + 500 inkomen, 1000 + 145 lasten, 250 + 80 verdeeld.
        XCTAssertEqual(data.remaining(in: oct2026), 3600 - 1145 - 250 - 80)
    }

    func testUpdateKeepsOtherPlanFieldsOfTheMonth() {
        var data = makeBaseData()
        data.editPlan(oct2026) { $0.transferDay = 12 }
        data.applyImport(ImportDraft(rows: [ImportRow(name: "Bonus", amount: 500, category: .inkomen)]),
                         month: oct2026, existing: .update, now: now)
        XCTAssertEqual(data.plan(for: oct2026).transferDay, 12)
        XCTAssertEqual(data.plan(for: oct2026).extraIncome.first { $0.name == "Bonus" }?.amount, 500)
    }

    func testNewPotWithMonthlyAmountAndBalanceGetsAnOpeningBalance() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [
            ImportRow(name: "Noodfonds", amount: 150, category: .spaarpot, day: 26, meaning: .perMaand, balance: 5000),
            ImportRow(name: "Vakantiepot", amount: 50, category: .spaarpot, day: 26, meaning: .perMaand),
            // Het saldo geldt niet als het bedrag zelf het saldo is.
            ImportRow(name: "Autopot", amount: 700, category: .spaarpot, meaning: .saldo, balance: 5000)
        ])
        data.applyImport(draft, month: oct2026, now: now)
        guard data.pots.count == 3 else { return XCTFail("Verwacht 3 potten, kreeg \(data.pots.count)") }
        let emergency = data.pots[0], holiday = data.pots[1], car = data.pots[2]
        XCTAssertEqual(emergency.monthlyContribution, 150)
        XCTAssertEqual(data.potEntries.filter { $0.potID == emergency.id }.map(\.amount), [5000])
        XCTAssertEqual(data.potEntries.filter { $0.potID == emergency.id }.first?.kind, .opening)
        // Het beginsaldo staat er meteen; de inleg van oktober komt op de overschrijfdag (26e) erbij.
        XCTAssertEqual(data.potBalance(emergency.id, asOf: day(oct2026, 20)), 5000)
        XCTAssertEqual(data.potBalance(emergency.id, asOf: day(oct2026, 28)), 5150)
        XCTAssertTrue(data.potEntries.filter { $0.potID == holiday.id }.isEmpty)
        XCTAssertEqual(data.potBalance(holiday.id, asOf: day(oct2026, 20)), 0)
        XCTAssertEqual(car.monthlyContribution, 0)
        XCTAssertEqual(data.potEntries.filter { $0.potID == car.id }.map(\.amount), [700])
    }

    func testNewInvestmentWithMonthlyAmountAndValueStartsFromThatValue() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [
            ImportRow(name: "Wereld ETF", amount: 250, category: .belegging, meaning: .perMaand, balance: 12000),
            ImportRow(name: "Bitcoin", amount: 50, category: .belegging, meaning: .perMaand)
        ])
        data.applyImport(draft, month: oct2026, now: now)
        guard data.holdings.count == 2 else { return XCTFail("Verwacht 2 beleggingen") }
        let etf = data.holdings[0], bitcoin = data.holdings[1]
        XCTAssertEqual(etf.monthlyContribution, 250)
        XCTAssertEqual(etf.investedTotal, 12000)
        XCTAssertEqual(etf.snapshots.map(\.value), [12000])
        XCTAssertEqual(data.holdingStateNow(etf, current: oct2026)?.value, 12000)
        XCTAssertEqual(data.holdingStateNow(etf, current: oct2026)?.invested, 12000)
        // Een maand later komt de inleg erbij.
        let november = YearMonth(year: 2026, month: 11)
        XCTAssertEqual(data.holdingState(etf, at: november, current: november)?.value, 12250)
        // Zonder waarde in het bestand blijft het zoals het was: beginpunt 0, de inleg van deze maand telt mee.
        XCTAssertEqual(bitcoin.investedTotal, 0)
        XCTAssertEqual(data.holdingStateNow(bitcoin, current: oct2026)?.value, 50)
        // Een tweede keer importeren verandert niets.
        let afterFirst = data
        data.applyImport(draft, month: oct2026, now: now)
        XCTAssertEqual(data, afterFirst)
    }

    // MARK: Rapport

    func testReportCountsPerCategory() {
        var data = makeBaseData()
        let draft = ImportDraft(rows: [
            ImportRow(name: "Bonus", amount: 500, category: .inkomen),
            ImportRow(name: "Toeslag", amount: 100, category: .inkomen),
            ImportRow(name: "Zorgverzekering", amount: 145, category: .vasteLasten),
            ImportRow(name: "Huur", amount: 1000, category: .vasteLasten),
            ImportRow(name: "Noodfonds", amount: 100, category: .spaarpot),
            ImportRow(name: "Uit", amount: 1, category: .variabeleLasten, isIncluded: false)
        ])
        let report = data.applyImport(draft, month: oct2026, now: now)
        XCTAssertEqual(report.count(.added, in: .inkomen), 1)
        XCTAssertEqual(report.count(.skippedExisting, in: .inkomen), 1)
        XCTAssertEqual(report.count(.added, in: .vasteLasten), 1)
        XCTAssertEqual(report.count(.skippedExisting, in: .vasteLasten), 1)
        XCTAssertEqual(report.count(.added, in: .spaarpot), 1)
        XCTAssertEqual(report.count(.added, in: .belegging), 0)
        XCTAssertEqual(report.categories, [.inkomen, .vasteLasten, .spaarpot])
        XCTAssertEqual(report.notSelected, 1)
        XCTAssertEqual(report.summaryText, "3 toegevoegd, 2 overgeslagen")
        XCTAssertEqual(report.lines.first?.name, "Bonus")
    }

    // MARK: Van bestand tot gegevens

    func testBudgetFileEndToEnd() throws {
        let book = try SpreadsheetReader.read(XLSXFixtures.budget, fileName: "begroting.xlsx")
        let draft = ImportMapper.draft(from: book, preferredMonth: oct2026)
        var data = FinanceData(startMonth: oct2026)
        let report = data.applyImport(draft, month: oct2026, now: now)

        XCTAssertEqual(report.addedCount, 15)
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.notSelected, 4)   // drie totaalregels en "Overschot"

        let overview = data.expenseOverview(in: oct2026)
        XCTAssertEqual(overview.income, 3100)
        XCTAssertEqual(overview.fixed, 1470)
        XCTAssertEqual(overview.variable, 570)
        XCTAssertEqual(overview.toPots, 250)
        XCTAssertEqual(overview.toInvestments, 300)
        // 3100 - 1470 - 570 - 250 - 300
        XCTAssertEqual(data.remaining(in: oct2026), 510)
        XCTAssertEqual(data.pots.map(\.name), ["Noodfonds", "Vakantiepot"])
        XCTAssertEqual(data.holdings.map(\.name), ["VWCE (wereld-ETF)", "Bitcoin"])
        XCTAssertEqual(data.holdings.map(\.kind), [.etf, .crypto])
        XCTAssertEqual(data.holdings.map(\.ticker), ["VWCE.DE", "BTC-EUR"])

        // Nog een keer importeren verandert niets.
        let again = data.applyImport(draft, month: oct2026, now: now)
        XCTAssertEqual(again.addedCount, 0)
        XCTAssertEqual(again.skippedCount, 15)
    }

    func testImportedDataSurvivesSavingAndLoading() throws {
        let book = try SpreadsheetReader.read(XLSXFixtures.portfolio, fileName: "p.xlsx")
        let draft = ImportMapper.draft(from: book, preferredMonth: oct2026)
        var data = FinanceData(startMonth: oct2026)
        data.applyImport(draft, month: oct2026, now: now)
        let encoded = try FinanceStorage.makeEncoder().encode(data)
        let decoded = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: encoded)
        XCTAssertEqual(decoded, data)
        XCTAssertEqual(decoded.holdings.count, 3)
    }
}

// MARK: - Bedoeling gaat voor onderwerp

/// "Kinderopvangtoeslag" is geld dat binnenkomt, "Sparen voor vakantie" is sparen en "Huur garage" blijft huur: wat een regel
/// doet gaat voor waar hij over gaat, ongeacht hoe lang het onderwerpwoord is. De verwachte categorieën zijn bedacht
/// vanuit hoe een Nederlandse begroting gewoonlijk gelezen wordt, niet vanuit de code.
final class ImportKeywordIntentTests: XCTestCase {

    private func category(_ name: String) -> ImportCategory? { ImportKeywords.best(in: name)?.category }

    private func check(_ cases: [(String, ImportCategory)], file: StaticString = #filePath, line: UInt = #line) {
        for (name, expected) in cases {
            guard let hit = ImportKeywords.best(in: name) else {
                XCTFail("Geen trefwoord voor '\(name)'", file: file, line: line)
                continue
            }
            XCTAssertEqual(hit.category, expected, "'\(name)' kreeg woord '\(hit.word)'", file: file, line: line)
        }
    }

    // MARK: De gemelde voorbeelden

    func testToeslagIsIncomeWhateverTheSubjectIs() {
        check([("Kinderopvangtoeslag", .inkomen), ("Toeslag kinderopvang", .inkomen),
               ("Kinderopvang", .vasteLasten)])
        XCTAssertEqual(ImportKeywords.best(in: "Kinderopvangtoeslag")?.word, "toeslag")
        XCTAssertEqual(ImportKeywords.best(in: "Kinderopvangtoeslag")?.strong, true)
    }

    func testSavingWordsMakeASavingsPotWhateverTheSubjectIs() {
        check([("Sparen voor vakantie", .spaarpot), ("Vakantie sparen", .spaarpot),
               ("Maandelijks sparen vakantie", .spaarpot), ("Spaarbedrag vakantie", .spaarpot),
               ("Vakantie", .variabeleLasten), ("Vakantiepot", .spaarpot), ("Vakantiegeld", .inkomen)])
        // Bij een begin van een woord zie je in de reden het woord uit het bestand.
        XCTAssertEqual(ImportKeywords.best(in: "Spaarbedrag vakantie")?.word, "spaarbedrag")
        XCTAssertEqual(ImportKeywords.best(in: "Sparen voor vakantie")?.word, "sparen")
    }

    func testRentWithASubjectBehindItStaysAFixedCost() {
        check([("Huur garage", .vasteLasten), ("Huur", .vasteLasten), ("Huurwoning", .vasteLasten)])
        XCTAssertEqual(ImportKeywords.best(in: "Huur garage")?.word, "huur")
        XCTAssertEqual(ImportKeywords.best(in: "Huur garage")?.strong, true)
        // Zonder "huur" blijft een garage een variabele uitgave.
        check([("Garage", .variabeleLasten), ("Garage APK", .variabeleLasten)])
    }

    func testSavingsInterestIsIncomeButNotCertain() {
        // Onze keuze, vastgelegd: rente op spaargeld is een bijschrijving (inkomen), met lage zekerheid.
        let hit = ImportKeywords.best(in: "Spaarrente")
        XCTAssertEqual(hit?.category, .inkomen)
        XCTAssertEqual(hit?.uncertain, true)
        XCTAssertEqual(hit?.confidence, .laag)
        check([("Rente spaarrekening", .inkomen), ("Rente op spaargeld", .inkomen), ("Spaarrekening rente ING", .inkomen)])
        XCTAssertEqual(ImportKeywords.best(in: "Rente spaarrekening")?.confidence, .laag)
        // Rente die je betaalt blijft een last, en sparen zelf blijft sparen.
        check([("Hypotheekrente", .vasteLasten), ("Rente", .vasteLasten), ("Spaarrekening", .spaarpot)])
        XCTAssertEqual(ImportKeywords.best(in: "Huur")?.confidence, .hoog)
        XCTAssertEqual(ImportKeywords.best(in: "Gas")?.confidence, .middel)
    }

    // MARK: Meer realistische begrotingsregels

    func testIncomeWordsBeatSubjectWords() {
        check([
            ("Reiskostenvergoeding", .inkomen), ("Onkostenvergoeding werkgever", .inkomen),
            ("Teruggave inkomstenbelasting", .inkomen), ("Restitutie energierekening", .inkomen),
            ("Uitkering WW", .inkomen), ("Salaris partner", .inkomen), ("Loon parttime baan", .inkomen),
            ("Bonus december", .inkomen), ("Dividend ontvangen", .inkomen), ("Huur ontvangen garagebox", .inkomen),
            ("Alimentatie ontvangen", .inkomen), ("Zorgtoeslag", .inkomen), ("Huurtoeslag", .inkomen),
            ("Ontvangen rente spaarrekening", .inkomen), ("Huur inkomsten", .inkomen)
        ])
    }

    func testSavingWordsBeatSubjectWordsAndCompounds() {
        check([
            ("Spaarbedrag auto", .spaarpot), ("Reserveren voor weekendje weg", .spaarpot), ("Autosparen", .spaarpot),
            ("Vakantiesparen kinderen", .spaarpot), ("Bonus sparen", .spaarpot), ("Toeslag sparen", .spaarpot),
            ("Noodbuffer", .spaarpot), ("Reservering onderhoud woning", .spaarpot), ("Sparen voor nieuwe fiets", .spaarpot)
        ])
    }

    func testInvestingWordsStillWinOverSaving() {
        check([("Sparen voor pensioen", .belegging), ("ETF sparen", .belegging), ("Maandelijks sparen in aandelen", .belegging),
               ("Bonus beleggen", .belegging), ("Sparen en beleggen", .belegging)])
    }

    func testRentWithASubjectIsFixedButOtherCostsKeepTheirOwnWord() {
        check([
            ("Huur parkeerplaats", .vasteLasten), ("Huur kapsalon", .vasteLasten), ("Huur auto", .vasteLasten),
            ("Maandelijkse huur garagebox", .vasteLasten), ("Huur vastgoed", .belegging),
            ("Kapper", .variabeleLasten), ("Parkeren", .variabeleLasten)
        ])
    }

    func testWordsThatLookLikeIntentWordsAreLeftAlone() {
        check([
            ("Spaarhypotheek", .vasteLasten), ("Spaarlening", .vasteLasten), ("Spaarverzekering", .vasteLasten),
            ("Loonbelasting", .vasteLasten), ("Besparen op energie", .vasteLasten), ("Alimentatie kinderen", .vasteLasten),
            ("Boodschappen", .variabeleLasten), ("Netflix", .vasteLasten), ("Zorgverzekering", .vasteLasten)
        ])
        XCTAssertNil(ImportKeywords.best(in: "Iets heel onbekends"))
    }

    // MARK: In een bestand

    func testBudgetLinesGetTheRightCategoryAndConfidenceInADraft() throws {
        let text = """
        Omschrijving;Bedrag
        Salaris;2.850
        Kinderopvangtoeslag;320
        Toeslag kinderopvang;45
        Reiskostenvergoeding;90
        Huur;950
        Huur garage;75
        Kinderopvang;610
        Sparen voor vakantie;110
        Vakantie sparen;65
        Maandelijks sparen vakantie;35
        Spaarbedrag vakantie;25
        Spaarrente;12
        Boodschappen;420
        """
        let draft = try csvDraft(text)
        let expected: [(String, ImportCategory)] = [
            ("Salaris", .inkomen), ("Kinderopvangtoeslag", .inkomen), ("Toeslag kinderopvang", .inkomen),
            ("Reiskostenvergoeding", .inkomen), ("Huur", .vasteLasten), ("Huur garage", .vasteLasten),
            ("Kinderopvang", .vasteLasten), ("Sparen voor vakantie", .spaarpot), ("Vakantie sparen", .spaarpot),
            ("Maandelijks sparen vakantie", .spaarpot), ("Spaarbedrag vakantie", .spaarpot), ("Spaarrente", .inkomen),
            ("Boodschappen", .variabeleLasten)
        ]
        XCTAssertEqual(draft.rows.count, expected.count, "\(draft.rows.map(\.name))")
        for (name, category) in expected {
            XCTAssertEqual(row(draft, name).category, category, name)
        }
        // Een bedrag naast "maandelijks sparen" is de inleg per maand.
        XCTAssertEqual(row(draft, "Maandelijks sparen vakantie").meaning, .perMaand)
        XCTAssertEqual(row(draft, "Kinderopvangtoeslag").confidence, .hoog)
        XCTAssertEqual(row(draft, "Kinderopvangtoeslag").reason, "woord 'toeslag' herkend")
        XCTAssertEqual(row(draft, "Huur garage").confidence, .hoog)
        // Alleen rente op spaargeld is onzeker: het scherm vraagt dan om een controle.
        let uncertain = draft.rows.filter { $0.confidence == .laag }.map(\.name)
        XCTAssertEqual(uncertain, ["Spaarrente"])
        XCTAssertEqual(row(draft, "Spaarrente").amount, 12)
    }

    func testTheHeadingStillBeatsTheKeywordInADraft() throws {
        // Onder het kopje Vaste lasten blijft een regel een vaste last; de bedoeling telt alleen zonder structuur.
        let draft = try csvDraft("Vaste lasten;Bedrag\nSparen voor vakantie;100\nHuur;900\n")
        XCTAssertEqual(row(draft, "Huur").category, .vasteLasten)
        XCTAssertEqual(row(draft, "Sparen voor vakantie").category, .vasteLasten)
    }

    // MARK: Begrensde invoer

    func testOnlyTheFirst200CharactersOfATextAreLookedAt() {
        let long = String(repeating: "a", count: 1_000_000)
        XCTAssertEqual(ImportText.normalize(long).count, ImportText.maxInspectedCharacters)
        XCTAssertEqual(ImportText.maxInspectedCharacters, 200)
        XCTAssertEqual(ImportText.cleanName(long).count, 80)
        // Een woord ver achter de 200 tekens telt niet meer mee, een woord ervoor wel.
        let late = String(repeating: "x ", count: 150) + "huur"
        XCTAssertNil(ImportKeywords.best(in: late))
        XCTAssertEqual(ImportKeywords.best(in: "huur " + String(repeating: "x", count: 5_000))?.category, .vasteLasten)
        // Veel spaties en regeleinden zijn snel genoeg.
        let spaced = String(repeating: " \n\t ", count: 250_000)
        XCTAssertEqual(ImportText.normalize(spaced), "")
        XCTAssertEqual(ImportText.cleanName(spaced + "Huur"), "")
    }
}
