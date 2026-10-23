import XCTest
import Foundation

// Tests van de paginacatalogus (App/Navigation/PageCatalog.swift, Foundation-only): elke bestemming staat erin of is een wortel of
// heeft een ouder, elke pagina is bereikbaar vanaf een Bibliotheekrij of een wortel (zonder lus), de Bibliotheek heeft 13 rijen
// in 3 groepen en de bladertegels zijn de tien van par. 1.2 van docs/design2/plan.md (par. 5.3: niets mag verloren gaan).

final class PageCatalogTests: XCTestCase {
    private let a = NavigationTestSupport.idA

    // MARK: De tabel

    func testTheTableHasNineteenPagesInOrder() {
        XCTAssertEqual(PageCatalog.all.map { $0.destination }, [
            .home, .library, .flow, .income, .salary, .expenses, .distribute, .bank, .cashflow,
            .pots, .portfolio, .goals, .savingsGoal, .buffer, .accelerators, .projection, .purchase,
            .tools, .settingsRoot
        ])
    }

    func testTitlesSymbolsAndHuesMatchThePlan() {
        let expected: [(Destination, String, String, TileHue)] = [
            (.home, "Home", "house", .olive),
            (.library, "Bibliotheek", "books.vertical", .olive),
            (.flow, "Maandoverzicht", "chart.bar.xaxis", .terracotta),
            (.income, "Inkomen", "eurosign.circle", .terracotta),
            (.salary, "Salaris instellen", "eurosign.circle", .terracotta),
            (.expenses, "Uitgaven", "creditcard", .terracotta),
            (.distribute, "Verdelen", "square.split.2x2", .terracotta),
            (.bank, "Bankrekening", "building.columns", .terracotta),
            (.cashflow, "Dag voor dag", "list.bullet.rectangle", .terracotta),
            (.pots, "Spaarpotten", "tray.full", .teal),
            (.portfolio, "Beleggingen", "chart.line.uptrend.xyaxis", .slate),
            (.goals, "Doelen", "flag.checkered", .mustard),
            (.savingsGoal, "Spaardoel berekenen", "function", .mustard),
            (.buffer, "Noodbuffer", "shield.lefthalf.filled", .mustard),
            (.accelerators, "Versnellers", "bolt", .mustard),
            (.projection, "Toekomstschatting", "calendar.badge.clock", .plum),
            (.purchase, "Aankoopcheck", "cart", .plum),
            (.tools, "Hulpmiddelen", "wrench.and.screwdriver", .plum),
            (.settingsRoot, "Instellingen", "gearshape", .sage)
        ]
        XCTAssertEqual(PageCatalog.all.count, expected.count)
        for row in expected {
            let info = PageCatalog.info(row.0)
            XCTAssertNotNil(info, "\(row.0)")
            XCTAssertEqual(info?.title, row.1)
            XCTAssertEqual(info?.symbol, row.2, row.1)
            XCTAssertEqual(info?.hue, row.3, row.1)
        }
    }

    func testIDsTitlesAreUniqueAndEveryPageHasTerms() {
        let ids = PageCatalog.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        let titles = PageCatalog.all.map { $0.title }
        XCTAssertEqual(Set(titles).count, titles.count)
        for info in PageCatalog.all {
            XCTAssertFalse(info.terms.isEmpty, info.title)
            XCTAssertTrue(info.terms.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, info.title)
            XCTAssertFalse(info.title.isEmpty)
            XCTAssertFalse(info.symbol.isEmpty)
        }
        XCTAssertEqual(PageCatalog.info(.flow)?.id, "flow")
        XCTAssertEqual(PageCatalog.info(.settingsRoot)?.id, "settingsRoot")
    }

    func testThePagesWithAnIDAndTheSettingsPagesAreNotInTheCatalog() {
        XCTAssertNil(PageCatalog.info(.pot(a)))
        XCTAssertNil(PageCatalog.info(.holding(a)))
        XCTAssertNil(PageCatalog.info(.goal(a)))
        for page in SettingsPage.allCases { XCTAssertNil(PageCatalog.info(.settings(page))) }
    }

    func testTheOldWordOverzichtIsGone() {
        for info in PageCatalog.all {
            XCTAssertNotEqual(info.title, "Overzicht")
            XCTAssertFalse(info.terms.contains { $0.lowercased() == "overzicht" }, info.title)
        }
    }

    func testTheNewTermsOfFlowAndToolsAreThere() {
        XCTAssertTrue(PageCatalog.info(.flow)?.terms.contains("waar gaat je geld heen") == true)
        XCTAssertTrue(PageCatalog.info(.flow)?.terms.contains("periode") == true)
        XCTAssertTrue(PageCatalog.info(.flow)?.terms.contains("half jaar") == true)
        XCTAssertTrue(PageCatalog.info(.tools)?.terms.contains("rekenhulp") == true)
        XCTAssertTrue(PageCatalog.info(.tools)?.terms.contains("calculators") == true)
        // De termen van de oude zoekregels zijn bewaard.
        XCTAssertTrue(PageCatalog.info(.home)?.terms.contains("nog te verdelen") == true)
        XCTAssertTrue(PageCatalog.info(.bank)?.terms.contains("minimumsaldo") == true)
        XCTAssertTrue(PageCatalog.info(.portfolio)?.terms.contains("kies beleggingen") == true)
    }

    // MARK: De Bibliotheek

    func testTheLibraryHasThirteenRowsInThreeGroups() {
        XCTAssertEqual(PageCatalog.library.count, 13)
        XCTAssertEqual(LibrarySection.allCases, [.month, .saving, .planning])
        XCTAssertEqual(LibrarySection.allCases.map { $0.title }, ["Deze maand", "Sparen en beleggen", "Plannen"])
        XCTAssertEqual(PageCatalog.library(in: .month).map { $0.destination },
                       [.flow, .income, .expenses, .distribute, .bank, .cashflow])
        XCTAssertEqual(PageCatalog.library(in: .saving).map { $0.destination }, [.pots, .portfolio])
        XCTAssertEqual(PageCatalog.library(in: .planning).map { $0.destination },
                       [.goals, .buffer, .accelerators, .projection, .purchase])
        let all = LibrarySection.allCases.flatMap { PageCatalog.library(in: $0) }
        XCTAssertEqual(all, PageCatalog.library, "de groepen samen zijn de lijst, in tabelvolgorde")
    }

    func testEveryLibraryRowIsReachedFromTheLibrary() {
        for info in PageCatalog.library {
            XCTAssertEqual(info.reachableFrom, .library, info.title)
        }
    }

    func testNoPageOutsideTheLibraryHasASection() {
        for info in PageCatalog.all where info.section == nil {
            XCTAssertFalse(PageCatalog.library.contains(info), info.title)
        }
        XCTAssertEqual(PageCatalog.all.filter { $0.section == nil }.map { $0.destination },
                       [.home, .library, .salary, .savingsGoal, .tools, .settingsRoot])
    }

    // MARK: Bereikbaarheid

    func testEveryDestinationIsInTheCatalogOrHasAParent() {
        for destination in NavigationTestSupport.allDestinations() {
            if PageCatalog.info(destination) != nil { continue }
            XCTAssertFalse(destination.parents.isEmpty, "\(destination) staat niet in de catalogus en heeft geen ouder")
            for parent in destination.parents {
                let known = PageCatalog.info(parent) != nil || parent.parents.isEmpty == false
                XCTAssertTrue(known, "de ouder \(parent) van \(destination) is onbekend")
            }
        }
    }

    func testEveryPageThatIsNotARootIsReachableWithoutALoop() {
        for info in PageCatalog.all {
            var seen: Set<Destination> = [info.destination]
            var current = info
            var steps = 0
            while let next = current.reachableFrom {
                XCTAssertFalse(seen.contains(next), "lus bij \(info.title)")
                seen.insert(next)
                guard let parent = PageCatalog.info(next) else {
                    XCTFail("\(info.title) is bereikbaar via \(next), dat niet in de catalogus staat")
                    break
                }
                current = parent
                steps += 1
                XCTAssertLessThan(steps, 5, "te diep bij \(info.title)")
            }
            // Het eind van de keten is een tabwortel of een Bibliotheekrij die vanaf de Bibliotheek te bereiken is.
            let isRootOrLibraryRow = current.destination.isTabRoot || current.section != nil
            XCTAssertTrue(isRootOrLibraryRow, "\(info.title) eindigt niet bij een wortel of Bibliotheekrij")
        }
    }

    func testRootsHaveNoParentAndEveryOtherPageHasOne() {
        for info in PageCatalog.all {
            if info.destination.isTabRoot {
                XCTAssertNil(info.reachableFrom, info.title)
            } else {
                XCTAssertNotNil(info.reachableFrom, info.title)
            }
        }
    }

    func testThePagesWithoutALibraryRowKeepTheirRoute() {
        // Par. 1.2: Salaris via Inkomen, Spaardoel berekenen via Doelen, Hulpmiddelen en Instellingen via Home.
        XCTAssertEqual(PageCatalog.info(.salary)?.reachableFrom, .income)
        XCTAssertEqual(PageCatalog.info(.savingsGoal)?.reachableFrom, .goals)
        XCTAssertEqual(PageCatalog.info(.tools)?.reachableFrom, .home)
        XCTAssertEqual(PageCatalog.info(.settingsRoot)?.reachableFrom, .home)
        // De ouder van Salaris en Spaardoel berekenen heeft een eigen Bibliotheekrij.
        XCTAssertNotNil(PageCatalog.info(.income)?.section)
        XCTAssertNotNil(PageCatalog.info(.goals)?.section)
    }

    func testEveryPageIsAlsoFoundThroughSearch() {
        // Zoeken is de vangnetroute: elke catalogusrij staat in de zoekregels (SearchIndexTests bewaakt de rest).
        for info in PageCatalog.all {
            XCTAssertTrue(SearchIndex.pages.contains { $0.destination == info.destination }, info.title)
        }
    }

    // MARK: Bladertegels

    func testBrowseHasTheTenTilesOfThePlan() {
        XCTAssertEqual(PageCatalog.browse, [.income, .expenses, .distribute, .bank, .cashflow,
                                            .pots, .portfolio, .goals, .tools, .settingsRoot])
        XCTAssertEqual(PageCatalog.browse.count, 10)
        XCTAssertEqual(Set(PageCatalog.browse).count, 10)
        XCTAssertEqual(PageCatalog.browsePages.map { $0.destination }, PageCatalog.browse)
    }

    func testEveryBrowseTileIsAPageOfTheCatalog() {
        for destination in PageCatalog.browse {
            XCTAssertNotNil(PageCatalog.info(destination), "\(destination)")
        }
    }
}
