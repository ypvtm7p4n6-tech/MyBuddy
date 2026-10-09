import XCTest
@testable import MyBuddyCore

/// De vaste id's mogen nooit veranderen: opgeslagen boekingen (rente) en overgenomen regels zijn eraan herkenbaar.
/// De verwachte waarden komen uit een onafhankelijke berekening van het oorspronkelijke algoritme.
final class StableIDPinTests: XCTestCase {
    func testStableIDsStayExactlyTheSame() {
        XCTAssertEqual(StableID.uuid("").uuidString, "C3817C01-6BA4-5F30-93E9-1B507A4E8B38")
        XCTAssertEqual(StableID.uuid("a").uuidString, "5F29C2AA-DD9B-5527-9E8E-89141CA09289")
        XCTAssertEqual(StableID.uuid("interest|00000000-0000-0000-0000-000000000001|2026-10").uuidString,
                       "31277BFC-83E4-5A61-8548-FEF2A06ABFA7")
        XCTAssertEqual(StableID.uuid("line|3F2504E0-4F89-41D3-9A0C-0305E82C3301|2026-11").uuidString,
                       "79DFA0AB-058E-5AA8-9DF2-638AD3DA5573")
        let pot = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        XCTAssertEqual(InterestRules.entryID(for: pot, month: YearMonth(year: 1, month: 1)).uuidString,
                       "CA084E26-A81D-5839-A6BF-8C8F1D3333A9")
        XCTAssertEqual(InterestRules.entryID(for: pot, month: YearMonth(year: 9_999, month: 12)).uuidString,
                       "8FF33BA7-8A54-50FB-9F14-605E031D3A4D")
    }

    func testPrefixAndMonthShortcutsGiveTheSameIDs() {
        let pot = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        let prefix = StableID.Prefix("interest|\(pot.uuidString)|")
        XCTAssertEqual(prefix.uuid(adding: "2026-10"), StableID.uuid("interest|\(pot.uuidString)|2026-10"))
        let months = YearMonth(year: 1999, month: 11).range(count: 400) + [YearMonth(year: 0, month: 1), YearMonth(year: 9_999, month: 12)]
        for month in months {
            XCTAssertEqual(prefix.uuid(addingKeyOf: month), InterestRules.entryID(for: pot, month: month), month.key)
            XCTAssertEqual(prefix.uuid(addingKeyOf: month), StableID.uuid("interest|\(pot.uuidString)|\(month.key)"), month.key)
        }
        XCTAssertEqual(InterestRules.entryIDs(for: pot, months: months), months.map { InterestRules.entryID(for: pot, month: $0) })
    }

    func testMonthKeysRoundTripAndKeepTheirOldMeaning() {
        for month in YearMonth(year: 0, month: 1).range(count: 12 * 120) + YearMonth(year: 9_900, month: 1).range(count: 12 * 100) {
            XCTAssertEqual(YearMonth(key: month.key), month, month.key)
        }
        XCTAssertEqual(YearMonth(year: 2026, month: 3).key, "2026-03")
        XCTAssertEqual(YearMonth(year: 5, month: 11).key, "0005-11")
        XCTAssertEqual(YearMonth(year: 0, month: 1).key, "0000-01")
        // Sleutels die niet van de vaste vorm zijn, lopen via de zorgvuldige weg.
        XCTAssertEqual(YearMonth(key: "2026-9"), YearMonth(year: 2026, month: 9))
        XCTAssertEqual(YearMonth(key: "26-09"), YearMonth(year: 26, month: 9))
        XCTAssertNil(YearMonth(key: "2026-13"))
        XCTAssertNil(YearMonth(key: "2026-00"))
        XCTAssertNil(YearMonth(key: "2026-09-01"))
        XCTAssertNil(YearMonth(key: "20x6-09"))
        XCTAssertNil(YearMonth(key: "2026/09"))
        XCTAssertNil(YearMonth(key: ""))
        XCTAssertNil(YearMonth(key: "kapot"))
        XCTAssertNil(YearMonth(key: "10000-01"))
    }
}
