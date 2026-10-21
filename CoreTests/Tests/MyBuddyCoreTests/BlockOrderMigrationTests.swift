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

    // MARK: Volgorde uitrekenen (`order`)

    func testOrderWithoutStoredListIsTheDefault() {
        XCTAssertEqual(BlockOrderMigration.order(stored: nil, defaults: ["a", "b", "c"]), ["a", "b", "c"])
        XCTAssertEqual(BlockOrderMigration.order(stored: [], defaults: ["a", "b", "c"]), ["a", "b", "c"])
    }

    func testOrderFollowsTheStoredListAndAppendsNewBlocks() {
        XCTAssertEqual(BlockOrderMigration.order(stored: ["c", "a"], defaults: ["a", "b", "c", "d"]), ["c", "a", "b", "d"])
    }

    func testOrderIgnoresUnknownAndDuplicateIds() {
        XCTAssertEqual(BlockOrderMigration.order(stored: ["x", "b", "b", "a", "y"], defaults: ["a", "b", "c"]), ["b", "a", "c"])
    }

    func testOrderOfAMigratedLegacyOrderKeepsRelativeOrderAndAppendsTheRest() {
        // Savings stond op: doelen voor buffer, bank voor inkomen. Op de nieuwe pagina's komt dat terug.
        let stored: [String: [String]] = ["savings": ["goals", "buffer", "bank", "pots", "income", "portfolio", "period", "distribute"]]
        let migrated = BlockOrderMigration.migrate(stored)
        let month = BlockOrderMigration.order(stored: migrated[BlockPage.month.key], defaults: BlockPage.month.blocks.map { $0.id })
        // `expenses` en `days` zijn nieuw en komen achteraan, in de standaardvolgorde.
        XCTAssertEqual(month, ["bank", "income", "flow", "distribute", "expenses", "days"])
        let planning = BlockOrderMigration.order(stored: migrated[BlockPage.planning.key],
                                                 defaults: BlockPage.planning.blocks.map { $0.id })
        XCTAssertEqual(planning, ["goals", "buffer", "accelerators", "projection", "purchase"])
        // Sparen: potten en beleggingen in de oude volgorde (pots staat voor portfolio).
        let saving = BlockOrderMigration.order(stored: migrated[BlockPage.saving.key], defaults: BlockPage.saving.blocks.map { $0.id })
        XCTAssertEqual(saving, ["pots", "portfolio"])
    }

    // MARK: De pagina's en hun blok-id's (par. 2.7; de tabroots van pakket A en de kaarten koppelen hieraan)

    func testBlockIDsPerPageMatchThePlan() {
        XCTAssertEqual(BlockPage.overview.blocks.map { $0.id }, ["wealth", "pots", "invest", "upcoming"])
        XCTAssertEqual(BlockPage.month.blocks.map { $0.id }, ["flow", "income", "expenses", "distribute", "bank", "days"])
        XCTAssertEqual(BlockPage.saving.blocks.map { $0.id }, ["pots", "portfolio"])
        XCTAssertEqual(BlockPage.planning.blocks.map { $0.id }, ["goals", "buffer", "accelerators", "projection", "purchase"])
    }

    func testBlockTitlesAndSymbolsMatchThePlan() {
        let overview = BlockPage.overview.blocks
        XCTAssertEqual(overview.map { $0.title }, ["Vermogen", "Spaarpotten", "Beleggingen", "Komende dagen"])
        XCTAssertEqual(overview.map { $0.symbol }, ["chart.pie", "tray.full", "chart.line.uptrend.xyaxis", "calendar.badge.clock"])
        let month = BlockPage.month.blocks
        XCTAssertEqual(month.map { $0.title }, ["Waar gaat je geld heen", "Inkomen", "Uitgaven", "Verdelen", "Bankrekening", "Dag voor dag"])
        XCTAssertEqual(month.map { $0.symbol }, ["chart.bar.xaxis", "eurosign.circle", "creditcard", "square.split.2x2",
                                                  "building.columns", "list.bullet.rectangle"])
        let saving = BlockPage.saving.blocks
        XCTAssertEqual(saving.map { $0.title }, ["Spaarpotten", "Beleggingen"])
        XCTAssertEqual(saving.map { $0.symbol }, ["tray.full", "chart.line.uptrend.xyaxis"])
        let planning = BlockPage.planning.blocks
        XCTAssertEqual(planning.map { $0.title }, ["Doelen", "Noodbuffer", "Versnellers", "Toekomstschatting", "Aankoopcheck"])
        XCTAssertEqual(planning.map { $0.symbol }, ["flag.checkered", "shield.lefthalf.filled", "bolt", "calendar.badge.clock", "cart"])
    }

    func testBlockPageTitlesFollowTheTabNames() {
        XCTAssertEqual(BlockPage.overview.title, "Overzicht")
        XCTAssertEqual(BlockPage.month.title, "Maand")
        XCTAssertEqual(BlockPage.saving.title, "Sparen")
        XCTAssertEqual(BlockPage.planning.title, "Plannen")
    }

    func testOnlyPagesWithThreeOrMoreBlocksAllowOrdering() {
        XCTAssertTrue(BlockPage.overview.allowsOrdering)
        XCTAssertTrue(BlockPage.month.allowsOrdering)
        XCTAssertFalse(BlockPage.saving.allowsOrdering, "Sparen heeft twee blokken: ordenen is zinloos")
        XCTAssertTrue(BlockPage.planning.allowsOrdering)
    }

    func testAllCasesAreTheFourNewPagesInTabOrder() {
        XCTAssertEqual(BlockPage.allCases, [.overview, .month, .saving, .planning])
        XCTAssertEqual(BlockPage.allCases.map { $0.key }, ["overview", "month", "saving", "planning"])
        XCTAssertTrue(BlockPage.allCases.allSatisfy { !$0.isLegacy })
    }

    func testLegacyPagesKeepTheirOldKeysAndBlocks() {
        XCTAssertEqual(BlockPage.home.key, "home")
        XCTAssertEqual(BlockPage.savings.key, "savings")
        XCTAssertEqual(BlockPage.tools.key, "tools")
        XCTAssertTrue(BlockPage.home.isLegacy && BlockPage.savings.isLegacy && BlockPage.tools.isLegacy)
        XCTAssertEqual(BlockPage.home.blocks.map { $0.id }, ["overview", "pots", "invest"])
        XCTAssertEqual(BlockPage.savings.blocks.map { $0.id },
                       ["period", "income", "bank", "distribute", "pots", "buffer", "portfolio", "goals"])
        XCTAssertEqual(BlockPage.tools.blocks.map { $0.id }, ["accelerators", "projection", "purchase"])
        XCTAssertEqual(BlockPage(rawValue: "home"), .home)
        XCTAssertEqual(BlockPage(rawValue: "planning"), .planning)
        XCTAssertNil(BlockPage(rawValue: "onbekend"))
    }

    func testBlockIDsAreUniquePerPageAndEveryLegacyIDHasANewHome() {
        for page in [BlockPage.overview, .month, .saving, .planning, .home, .savings, .tools] {
            let ids = page.blocks.map { $0.id }
            XCTAssertEqual(Set(ids).count, ids.count, "dubbele blok-id's op \(page.key)")
            XCTAssertFalse(page.blocks.contains { $0.title.isEmpty || $0.symbol.isEmpty })
        }
        // Elk oud blok-id dat de migratie kent, wijst naar een bestaand blok van een nieuwe pagina (geen verloren blokken).
        for old in [BlockPage.home, .savings, .tools] {
            let migrated = BlockOrderMigration.migrate([old.key: old.blocks.map { $0.id }])
            let moved = migrated.values.flatMap { $0 }.count
            XCTAssertEqual(moved, old.blocks.count, "niet elk blok van \(old.key) komt op een nieuwe pagina terecht")
            for (key, ids) in migrated {
                guard let page = BlockPage(rawValue: key) else { return XCTFail("onbekende pagina \(key)") }
                let known = Set(page.blocks.map { $0.id })
                XCTAssertTrue(ids.allSatisfy { known.contains($0) }, "onbekend blok in \(key): \(ids)")
            }
        }
    }
}
