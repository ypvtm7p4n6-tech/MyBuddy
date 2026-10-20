import XCTest
import Foundation

// Tests van de migratie van de blokvolgorde (App/UI/BlockOrderMigration.swift, Foundation-only): de zeven rijen van par. 2.7 van
// docs/design/plan.md, behoud van de onderlinge volgorde, idempotentie, onbekende ids en een lege invoer.

final class BlockOrderMigrationTests: XCTestCase {

    // MARK: De zeven rijen van par. 2.7

    func testHomeOverviewGoesToMonthFlow() {
        XCTAssertEqual(BlockOrderMigration.migrate(["home": ["overview"]]), ["month": ["flow"]])
    }

    func testHomePotsAndInvestGoToOverview() {
        XCTAssertEqual(BlockOrderMigration.migrate(["home": ["invest", "pots"]]), ["overview": ["invest", "pots"]])
    }

    func testSavingsPeriodGoesToMonthFlow() {
        XCTAssertEqual(BlockOrderMigration.migrate(["savings": ["period"]]), ["month": ["flow"]])
    }

    func testSavingsIncomeBankDistributeGoToMonth() {
        XCTAssertEqual(BlockOrderMigration.migrate(["savings": ["distribute", "income", "bank"]]),
                       ["month": ["distribute", "income", "bank"]])
    }

    func testSavingsPotsAndPortfolioGoToSaving() {
        XCTAssertEqual(BlockOrderMigration.migrate(["savings": ["portfolio", "pots"]]),
                       ["saving": ["portfolio", "pots"]])
    }

    func testSavingsBufferAndGoalsGoToPlanning() {
        XCTAssertEqual(BlockOrderMigration.migrate(["savings": ["goals", "buffer"]]),
                       ["planning": ["goals", "buffer"]])
    }

    func testToolsGoToPlanning() {
        XCTAssertEqual(BlockOrderMigration.migrate(["tools": ["purchase", "accelerators", "projection"]]),
                       ["planning": ["purchase", "accelerators", "projection"]])
    }

    // MARK: Een volledige opgeslagen volgorde

    func testWholeStoredOrderKeepsRelativeOrderPerPage() {
        let stored: [String: [String]] = [
            "home": ["invest", "overview", "pots"],
            "savings": ["goals", "buffer", "bank", "pots", "income", "portfolio", "period", "distribute"],
            "tools": ["purchase", "projection", "accelerators"]
        ]
        let migrated = BlockOrderMigration.migrate(stored)
        // savings wordt eerst gelezen: de plek van `flow` komt van `period`, niet van `home.overview`.
        XCTAssertEqual(migrated["month"], ["bank", "income", "flow", "distribute"])
        XCTAssertEqual(migrated["overview"], ["invest", "pots"])
        XCTAssertEqual(migrated["saving"], ["pots", "portfolio"])
        XCTAssertEqual(migrated["planning"], ["goals", "buffer", "purchase", "projection", "accelerators"])
        XCTAssertEqual(Set(migrated.keys), ["month", "overview", "saving", "planning"])
    }

    func testSharedBlockCountsOnce() {
        let migrated = BlockOrderMigration.migrate(["home": ["overview", "pots"], "savings": ["income", "period"]])
        XCTAssertEqual(migrated["month"], ["income", "flow"])
        XCTAssertEqual(migrated["overview"], ["pots"])
    }

    func testDuplicateIdsCountOnce() {
        XCTAssertEqual(BlockOrderMigration.migrate(["tools": ["purchase", "purchase", "projection"]]),
                       ["planning": ["purchase", "projection"]])
    }

    // MARK: Idempotent

    func testMigrationIsIdempotent() {
        let inputs: [[String: [String]]] = [
            [:],
            ["home": ["pots", "overview", "invest"]],
            ["savings": ["goals", "buffer", "bank", "pots", "income", "portfolio", "period", "distribute"]],
            ["tools": ["purchase", "projection", "accelerators"], "month": ["days", "flow"]],
            ["home": ["pots"], "savings": ["buffer"], "tools": ["purchase"], "overview": ["upcoming", "wealth"]],
            ["home": ["onbekend"], "unknown": ["a", "b"]]
        ]
        for input in inputs {
            let once = BlockOrderMigration.migrate(input)
            XCTAssertEqual(BlockOrderMigration.migrate(once), once, "niet idempotent voor \(input)")
            XCTAssertFalse(BlockOrderMigration.hasLegacyKeys(once), "oude sleutel in de uitkomst van \(input)")
        }
    }

    // MARK: Onbekende ids, nieuwe sleutels en een lege invoer

    func testUnknownLegacyIdsAreIgnored() {
        let migrated = BlockOrderMigration.migrate(["home": ["bestaat-niet", "pots"], "tools": ["ook-niet"]])
        XCTAssertEqual(migrated, ["overview": ["pots"]])
    }

    func testIdOfAnotherLegacyPageIsIgnored() {
        // `period` hoort bij savings, niet bij home.
        XCTAssertEqual(BlockOrderMigration.migrate(["home": ["period"]]), [:])
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(BlockOrderMigration.migrate([:]), [:])
    }

    func testEmptyLegacyListsGiveNoKeys() {
        XCTAssertEqual(BlockOrderMigration.migrate(["home": [], "savings": [], "tools": []]), [:])
    }

    func testNewKeyWinsOverLegacy() {
        let stored: [String: [String]] = ["savings": ["income", "bank"], "month": ["days", "flow"]]
        XCTAssertEqual(BlockOrderMigration.migrate(stored)["month"], ["days", "flow"])
    }

    func testNewKeysPassThroughUnchanged() {
        let stored: [String: [String]] = ["overview": ["upcoming", "wealth", "pots", "invest"], "planning": []]
        XCTAssertEqual(BlockOrderMigration.migrate(stored), stored)
    }

    func testLegacyDoesNotOverwriteOtherPagesNewKey() {
        // De gebruiker herordende alleen Maand; Overzicht komt nog uit de oude sleutel.
        let stored: [String: [String]] = ["home": ["invest", "pots"], "month": ["bank", "flow"]]
        let migrated = BlockOrderMigration.migrate(stored)
        XCTAssertEqual(migrated["month"], ["bank", "flow"])
        XCTAssertEqual(migrated["overview"], ["invest", "pots"])
    }

    func testHasLegacyKeys() {
        XCTAssertFalse(BlockOrderMigration.hasLegacyKeys([:]))
        XCTAssertFalse(BlockOrderMigration.hasLegacyKeys(["month": ["flow"]]))
        XCTAssertTrue(BlockOrderMigration.hasLegacyKeys(["home": []]))
        XCTAssertTrue(BlockOrderMigration.hasLegacyKeys(["month": ["flow"], "tools": ["purchase"]]))
    }
}
