import XCTest
@testable import MyBuddyCore

/// De sectie Bibliotheek in de zijbalk (iPad en Mac): elk item opent zijn pagina en heet zoals die pagina in `PageCatalog`; de
/// tabbalk van de iPhone houdt zijn drie tabs.
final class SidebarItemTests: XCTestCase {
    func testTheTabBarKeepsThreeTabs() {
        XCTAssertEqual(AppTab.allCases, [.home, .library, .search])
        XCTAssertTrue(AppTab.allCases.allSatisfy { $0.rootDestination == nil })
    }

    func testEverySidebarItemOpensItsPageWithTheSameNameAndSymbol() {
        XCTAssertEqual(AppTab.sidebarItems.compactMap(\.rootDestination), [.flow, .pots, .portfolio, .goals])
        for item in AppTab.sidebarItems {
            guard let destination = item.rootDestination, let info = PageCatalog.info(destination) else {
                return XCTFail("\(item) heeft geen pagina in de catalogus")
            }
            XCTAssertEqual(item.title, info.title)
            XCTAssertEqual(item.symbol, info.symbol)
            XCTAssertFalse(destination.isTabRoot)
        }
    }

    func testSidebarItemsHaveUniqueIdentifiersThatAreNoOldTabNames() {
        let ids = (AppTab.allCases + AppTab.sidebarItems).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for old in ["overview", "month", "saving", "planning", "savings", "tools", "settings"] {
            XCTAssertNil(AppTab(rawValue: old))
        }
    }
}
