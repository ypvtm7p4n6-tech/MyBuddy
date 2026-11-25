import XCTest
@testable import MyBuddyCore

/// Het kruimelpad onder de titel van een pagina (zoals op apple.com): welke niveaus erboven staan, hoe ze heten en hoe diep een keuze
/// het pad laat.
final class BreadcrumbTests: XCTestCase {
    func testASalaryPageInTheLibraryShowsLibraryAndIncome() {
        let path: [Destination] = [.income, .salary, .wageChange(YearMonth(year: 2026, month: 12))]
        let crumbs = Breadcrumbs.crumbs(above: 2, in: path, tab: .library, data: FinanceData.sample())
        XCTAssertEqual(crumbs.map(\.title), ["Bibliotheek", "Inkomen", "Salaris"])
        XCTAssertEqual(crumbs.map(\.depth), [0, 1, 2])
    }

    func testThePageItselfAndPagesBelowAreNotInTheMenu() {
        let path: [Destination] = [.income, .salary]
        XCTAssertEqual(Breadcrumbs.crumbs(above: 0, in: path, tab: .library, data: FinanceData(startMonth: YearMonth(year: 2026, month: 1))).map(\.title), ["Bibliotheek"])
        XCTAssertTrue(Breadcrumbs.crumbs(above: 5, in: path, tab: .library, data: FinanceData(startMonth: YearMonth(year: 2026, month: 1))).isEmpty)
    }

    func testAPotIsNamedAfterThePot() {
        let data = FinanceData.sample()
        guard let pot = data.pots.first else { return XCTFail("voorbeelddata zonder spaarpot") }
        let crumbs = Breadcrumbs.crumbs(above: 1, in: [.pot(pot.id), .flow], tab: .home, data: data)
        XCTAssertEqual(crumbs.map(\.title), ["Home", pot.name])
    }

    func testASidebarItemStartsAtItsOwnPage() {
        let data = FinanceData.sample()
        guard let pot = data.pots.first else { return XCTFail("voorbeelddata zonder spaarpot") }
        let crumbs = Breadcrumbs.crumbs(above: 0, in: [.pot(pot.id)], tab: .potsItem, data: data)
        XCTAssertEqual(crumbs.map(\.title), ["Spaarpotten"])
    }

    func testEveryPageOfTheCatalogHasATitle() {
        for info in PageCatalog.all where info.destination != .salary {
            XCTAssertEqual(Breadcrumbs.title(of: info.destination, data: FinanceData(startMonth: YearMonth(year: 2026, month: 1))), info.title)
        }
        XCTAssertEqual(Breadcrumbs.title(of: .salary, data: FinanceData(startMonth: YearMonth(year: 2026, month: 1))), "Salaris")
        XCTAssertEqual(Breadcrumbs.title(of: .settings(.workHours), data: FinanceData(startMonth: YearMonth(year: 2026, month: 1))), "Werkuren")
    }
}
