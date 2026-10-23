import XCTest
import Foundation
@testable import MyBuddyCore

// Tests van de migratie van de blokvolgorde (App/UI/BlockOrderMigration.swift, Foundation-only): de zeven rijen van par. 2.7 van
// docs/design/plan.md, behoud van de onderlinge volgorde, idempotentie, onbekende ids en een lege invoer; de blokken van Home
// (B16 van docs/design2/plan.md) en het laden van een opgeslagen volgorde uit elke eerdere ronde.

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

    // MARK: De pagina's en hun blok-id's (B16 van docs/design2/plan.md)

    func testHomeHasFiveShelvesInTheDefaultOrder() {
        XCTAssertEqual(BlockPage.overview.blocks.map { $0.id }, ["upcoming", "pots", "invest", "goals", "tools"])
        XCTAssertEqual(BlockPage.overview.blocks.map { $0.title },
                       ["Komende dagen", "Spaarpotten", "Beleggingen", "Doelen", "Hulpmiddelen"])
        XCTAssertEqual(BlockPage.overview.blocks.map { $0.symbol },
                       ["calendar.badge.clock", "tray.full", "chart.line.uptrend.xyaxis", "flag.checkered", "wrench.and.screwdriver"])
    }

    func testOldPagesKeepTheirBlocksUntilTheyAreRemoved() {
        XCTAssertEqual(BlockPage.month.blocks.map { $0.id }, ["flow", "income", "expenses", "distribute", "bank", "days"])
        XCTAssertEqual(BlockPage.saving.blocks.map { $0.id }, ["pots", "portfolio"])
        XCTAssertEqual(BlockPage.planning.blocks.map { $0.id }, ["goals", "buffer", "accelerators", "projection", "purchase"])
        let month = BlockPage.month.blocks
        XCTAssertEqual(month.map { $0.title }, ["Waar gaat je geld heen", "Inkomen", "Uitgaven", "Verdelen", "Bankrekening", "Dag voor dag"])
        XCTAssertEqual(month.map { $0.symbol }, ["chart.bar.xaxis", "eurosign.circle", "creditcard", "square.split.2x2",
                                                  "building.columns", "list.bullet.rectangle"])
        let planning = BlockPage.planning.blocks
        XCTAssertEqual(planning.map { $0.title }, ["Doelen", "Noodbuffer", "Versnellers", "Toekomstschatting", "Aankoopcheck"])
        XCTAssertEqual(planning.map { $0.symbol }, ["flag.checkered", "shield.lefthalf.filled", "bolt", "calendar.badge.clock", "cart"])
    }

    func testBlockPageTitlesUseTheNewNames() {
        XCTAssertEqual(BlockPage.overview.title, "Home")
        XCTAssertEqual(BlockPage.home.title, "Home")
        XCTAssertEqual(BlockPage.month.title, "Maand")
        XCTAssertEqual(BlockPage.saving.title, "Sparen")
        XCTAssertEqual(BlockPage.planning.title, "Plannen")
        for page in [BlockPage.overview, .month, .saving, .planning, .home, .savings, .tools] {
            XCTAssertNotEqual(page.title, "Overzicht", "het woord Overzicht vervalt (B2)")
            XCTAssertFalse(page.blocks.contains { $0.title == "Overzicht" }, "\(page.key)")
        }
    }

    func testOnlyPagesWithThreeOrMoreBlocksAllowOrdering() {
        XCTAssertTrue(BlockPage.overview.allowsOrdering)
        XCTAssertTrue(BlockPage.month.allowsOrdering)
        XCTAssertFalse(BlockPage.saving.allowsOrdering, "Sparen heeft twee blokken: ordenen is zinloos")
        XCTAssertTrue(BlockPage.planning.allowsOrdering)
    }

    func testOnlyHomeIsAListedPage() {
        XCTAssertEqual(BlockPage.allCases, [.overview])
        XCTAssertEqual(BlockPage.allCases.map { $0.key }, ["overview"])
        XCTAssertTrue(BlockPage.allCases.allSatisfy { !$0.isLegacy })
        XCTAssertTrue(BlockPage.allCases.allSatisfy { $0.allowsOrdering })
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
        // Elk oud blok-id dat de migratie kent, wijst naar een bestaand blok van een pagina (geen verloren blokken).
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

    // MARK: Een opgeslagen volgorde laadt gewoon (B16, par. 5.3)

    /// Decodeert de instellingen zoals ze op schijf staan: alleen de sleutel `blockOrder`, de rest krijgt zijn standaard.
    private func settings(blockOrder: [String: [String]]) throws -> AppSettings {
        let data = try JSONEncoder().encode(["blockOrder": blockOrder])
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    func testAStoredOrderWithWealthStillLoadsAndWealthIsSkipped() throws {
        // Uit de vorige ronde: Overzicht met `wealth`, `upcoming`, `pots` en `invest` in een eigen volgorde.
        let loaded = try settings(blockOrder: ["overview": ["upcoming", "wealth", "invest", "pots"]])
        XCTAssertEqual(loaded.blockIDs(for: .overview), ["upcoming", "invest", "pots", "goals", "tools"])
        XCTAssertEqual(loaded.orderedBlocks(for: .overview).map { $0.title },
                       ["Komende dagen", "Beleggingen", "Spaarpotten", "Doelen", "Hulpmiddelen"])
    }

    func testAnOldBlockOrderWithEveryKeyLoadsOnHome() throws {
        let stored: [String: [String]] = [
            "home": ["invest", "overview", "pots"],
            "savings": ["goals", "buffer", "bank", "pots", "income", "portfolio", "period", "distribute"],
            "tools": ["purchase", "projection", "accelerators"],
            "overview": ["upcoming", "wealth", "pots", "invest"],
            "month": ["days", "flow"]
        ]
        let loaded = try settings(blockOrder: stored)
        // Een nieuwe sleutel wint van een oude: Home volgt `overview`; `wealth` valt weg, de nieuwe planken komen achteraan.
        XCTAssertEqual(loaded.blockIDs(for: .overview), ["upcoming", "pots", "invest", "goals", "tools"])
        // De oude sleutels zelf blijven ongemoeid in de gegevens.
        XCTAssertEqual(loaded.blockOrder, stored)
        // De oude pagina's lezen nog steeds hun eigen volgorde (tot ze verdwijnen).
        XCTAssertEqual(loaded.blockIDs(for: .month), ["days", "flow", "income", "expenses", "distribute", "bank"])
    }

    func testAnOldHomeKeyGivesTheOrderOfPotsAndInvestOnHome() throws {
        // Alleen de oudste sleutel: `invest` stond voor `pots`.
        let loaded = try settings(blockOrder: ["home": ["invest", "pots"]])
        XCTAssertEqual(loaded.blockIDs(for: .overview), ["invest", "pots", "upcoming", "goals", "tools"])
        XCTAssertEqual(loaded.blockOrder, ["home": ["invest", "pots"]], "lezen schrijft niets terug")
    }

    func testNoStoredOrderGivesTheDefaultShelves() throws {
        let loaded = try settings(blockOrder: [:])
        XCTAssertEqual(loaded.blockIDs(for: .overview), ["upcoming", "pots", "invest", "goals", "tools"])
        XCTAssertEqual(AppSettings().blockIDs(for: .overview), ["upcoming", "pots", "invest", "goals", "tools"])
    }

    func testUnknownIdsInAStoredOrderAreIgnored() throws {
        let loaded = try settings(blockOrder: ["overview": ["bestaat-niet", "tools", "tools", "wealth", "goals"]])
        XCTAssertEqual(loaded.blockIDs(for: .overview), ["tools", "goals", "upcoming", "pots", "invest"])
    }

    func testOrderedBlocksOfALegacyPageReadTheLegacyKeyDirectly() throws {
        let loaded = try settings(blockOrder: ["home": ["invest", "pots", "overview"]])
        XCTAssertEqual(loaded.blockIDs(for: .home), ["invest", "pots", "overview"])
    }
}
