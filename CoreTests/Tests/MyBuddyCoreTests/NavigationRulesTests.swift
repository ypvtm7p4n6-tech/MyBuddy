import XCTest
import Foundation

// Tests van de navigatieregels (App/Navigation/NavigationModel.swift, Foundation-only): de drie tabs, de bestemmingen met hun
// ouders, het afknippen van een pad bij een herhaalde bestemming (K16) en `go` (B5 en par. 1.2 van docs/design2/plan.md).

/// Hulp voor de tests van navigatie en zoeken: alle bestemmingen, en een uitputtende `switch` die bij een nieuwe case een
/// compileerfout geeft zodat de lijst en de verwachtingen worden bijgewerkt.
enum NavigationTestSupport {
    static let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    /// Een voorbeeld van elke case van `Destination` (en elke pagina van Instellingen).
    static func allDestinations() -> [Destination] {
        var list: [Destination] = [
            .home, .library, .flow,
            .income, .salary, .expenses, .distribute, .bank, .cashflow,
            .pots, .pot(idA), .portfolio, .holding(idB),
            .goals, .goal(idA), .savingsGoal, .accelerators, .buffer, .projection, .purchase,
            .tools, .settingsRoot
        ]
        for page in SettingsPage.allCases { list.append(.settings(page)) }
        return list
    }

    /// Het volgnummer van een case. De `switch` heeft geen `default`: een nieuwe case compileert pas als hij hier staat.
    static func ordinal(_ destination: Destination) -> Int {
        switch destination {
        case .home: return 0
        case .library: return 1
        case .flow: return 2
        case .income: return 3
        case .salary: return 4
        case .expenses: return 5
        case .distribute: return 6
        case .bank: return 7
        case .cashflow: return 8
        case .pots: return 9
        case .pot: return 10
        case .portfolio: return 11
        case .holding: return 12
        case .goals: return 13
        case .goal: return 14
        case .savingsGoal: return 15
        case .accelerators: return 16
        case .buffer: return 17
        case .projection: return 18
        case .purchase: return 19
        case .tools: return 20
        case .settingsRoot: return 21
        case .settings: return 22
        }
    }

    static let caseCount = 23

    /// De ouders die par. 1.2 van docs/design2/plan.md voor elke bestemming noemt, los van de implementatie.
    static func expectedParents(_ destination: Destination) -> [Destination] {
        switch destination {
        case .pot: return [.pots]
        case .holding: return [.portfolio]
        case .goal: return [.goals]
        case .salary: return [.income]
        case .settings(let page):
            if let parent = page.parent { return [.settingsRoot, .settings(parent)] }
            return [.settingsRoot]
        case .home, .library, .flow, .income, .expenses, .distribute, .bank, .cashflow,
             .pots, .portfolio, .goals, .savingsGoal, .accelerators, .buffer, .projection, .purchase,
             .tools, .settingsRoot:
            return []
        }
    }
}

final class NavigationRulesTests: XCTestCase {
    private let a = NavigationTestSupport.idA
    private let b = NavigationTestSupport.idB

    // MARK: Tabs

    func testTabsAreHomeLibraryAndSearchWithTitlesAndSymbols() {
        XCTAssertEqual(AppTab.allCases, [.home, .library, .search])
        XCTAssertEqual(AppTab.allCases.map { $0.title }, ["Home", "Bibliotheek", "Zoeken"])
        XCTAssertEqual(AppTab.allCases.map { $0.rawValue }, ["home", "library", "search"])
        XCTAssertEqual(AppTab.allCases.map { $0.symbol }, ["house", "books.vertical", "magnifyingglass"])
        let symbols = AppTab.allCases.map { $0.symbol }
        XCTAssertEqual(Set(symbols).count, symbols.count, "elke tab heeft een eigen symbool")
        XCTAssertEqual(AppTab.search.id, "search")
    }

    func testThereIsNoSettingsTabAndNoOverviewWord() {
        XCTAssertNil(AppTab(rawValue: "settings"))
        XCTAssertNil(AppTab(rawValue: "overview"))
        XCTAssertFalse(AppTab.allCases.map { $0.title }.contains("Overzicht"))
        XCTAssertFalse(AppTab.allCases.map { $0.title }.contains("Instellingen"))
    }

    // MARK: Bestemmingen

    func testDestinationListCoversEveryCase() {
        let ordinals = Set(NavigationTestSupport.allDestinations().map { NavigationTestSupport.ordinal($0) })
        XCTAssertEqual(ordinals, Set(0..<NavigationTestSupport.caseCount))
    }

    func testDestinationParentsAreTotalAndMatchTheTable() {
        for destination in NavigationTestSupport.allDestinations() {
            XCTAssertEqual(destination.parents, NavigationTestSupport.expectedParents(destination), "\(destination)")
        }
    }

    func testOnlyHomeAndLibraryAreTabRoots() {
        for destination in NavigationTestSupport.allDestinations() {
            let expected = destination == .home || destination == .library
            XCTAssertEqual(destination.isTabRoot, expected, "\(destination)")
        }
    }

    func testAParentIsNeverARootOrItself() {
        for destination in NavigationTestSupport.allDestinations() {
            for parent in destination.parents {
                XCTAssertNotEqual(parent, destination)
                XCTAssertFalse(parent.isTabRoot, "\(destination) staat onder een wortel")
            }
        }
    }

    // MARK: Instellingenpagina's

    func testSettingsPagesHaveTitlesSymbolsAndParents() {
        XCTAssertEqual(SettingsPage.allCases.count, 11)
        let titles = SettingsPage.allCases.map { $0.title }
        XCTAssertEqual(Set(titles).count, titles.count, "elke pagina heeft een eigen titel")
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(SettingsPage.allCases.allSatisfy { !$0.symbol.isEmpty })

        XCTAssertEqual(SettingsPage.password.parent, .account)
        XCTAssertEqual(SettingsPage.deleteAccount.parent, .account)
        XCTAssertEqual(SettingsPage.conflictBackups.parent, .account)
        XCTAssertEqual(SettingsPage.importReview.parent, .data)
        XCTAssertEqual(SettingsPage.startDate.parent, .data, "de startdatum is een subpagina van Gegevens")
        XCTAssertEqual(SettingsPage.startDate.title, "Startdatum")
        XCTAssertEqual(SettingsPage.startDate.symbol, "calendar.badge.plus")
        for page in SettingsPage.panes { XCTAssertNil(page.parent, "\(page) is een hoofdpagina") }
    }

    func testSettingsPanesAreTheSixMainPagesAndEverySubpageBelongsToOne() {
        XCTAssertEqual(SettingsPage.panes, [.account, .calculations, .prices, .data, .layout, .about])
        for page in SettingsPage.allCases {
            XCTAssertTrue(SettingsPage.panes.contains(page.pane), "\(page) hoort bij een pane")
        }
        XCTAssertEqual(SettingsPage.password.pane, .account)
        XCTAssertEqual(SettingsPage.importReview.pane, .data)
        XCTAssertEqual(SettingsPage.startDate.pane, .data, "op de Mac een push in de pane Gegevens")
        XCTAssertEqual(SettingsPage.prices.pane, .prices)
    }

    // MARK: normalize

    func testNormalizeLeavesPathWithoutRepeatUntouched() {
        XCTAssertEqual(NavigationRules.normalize([]), [])
        XCTAssertEqual(NavigationRules.normalize([.pots]), [.pots])
        let path: [Destination] = [.pots, .pot(a), .cashflow, .pot(b)]
        XCTAssertEqual(NavigationRules.normalize(path), path)
    }

    func testNormalizeCutsAtRepeatedDestination() {
        // Spaarpot, Dag voor dag, Spaarpot wordt Spaarpot.
        XCTAssertEqual(NavigationRules.normalize([.pot(a), .cashflow, .pot(a)]), [.pot(a)])
        XCTAssertEqual(NavigationRules.normalize([.pots, .pot(a), .cashflow, .pot(a), .bank]), [.pots, .pot(a)])
        XCTAssertEqual(NavigationRules.normalize([.bank, .bank]), [.bank])
        XCTAssertEqual(NavigationRules.normalize([.income, .salary, .income]), [.income])
        XCTAssertEqual(NavigationRules.normalize([.settingsRoot, .settings(.data), .settingsRoot]), [.settingsRoot])
    }

    func testNormalizeTreatsDifferentIDsAsDifferentDestinations() {
        let path: [Destination] = [.pot(a), .pot(b)]
        XCTAssertEqual(NavigationRules.normalize(path), path)
        XCTAssertEqual(NavigationRules.normalize([.pot(a), .pot(b), .pot(a)]), [.pot(a)])
    }

    func testNormalizeIsIdempotentAndNeverLeavesARepeat() {
        let paths: [[Destination]] = [
            [], [.pots], [.pot(a), .cashflow, .pot(a)], [.bank, .bank, .bank],
            [.goals, .goal(a), .accelerators, .goal(a), .goals], [.income, .salary, .income, .salary]
        ]
        for path in paths {
            let once = NavigationRules.normalize(path)
            XCTAssertEqual(NavigationRules.normalize(once), once)
            XCTAssertEqual(Set(once).count, once.count, "geen herhaling in \(once)")
            XCTAssertEqual(once, Array(path.prefix(once.count)), "het resultaat is een begin van het pad")
        }
    }

    // MARK: push

    func testPushAppendsANewDestination() {
        XCTAssertEqual(NavigationRules.push(.pots, onto: []), [.pots])
        XCTAssertEqual(NavigationRules.push(.pot(a), onto: [.pots]), [.pots, .pot(a)])
    }

    func testPushOfADestinationAlreadyInThePathGoesBackToIt() {
        XCTAssertEqual(NavigationRules.push(.pot(a), onto: [.pots, .pot(a), .cashflow]), [.pots, .pot(a)])
        XCTAssertEqual(NavigationRules.push(.bank, onto: [.bank]), [.bank])
    }

    func testAPageMayStandOnTwoStacksBecausePushIgnoresTheOtherTab() {
        // B5: dezelfde pagina mag op het pad van Home en op dat van de Bibliotheek staan (elk pad is een eigen stapel).
        let home = NavigationRules.push(.pots, onto: [])
        let library = NavigationRules.push(.pots, onto: [.flow])
        XCTAssertEqual(home, [.pots])
        XCTAssertEqual(library, [.flow, .pots])
    }

    // MARK: go

    func testGoNeverLeavesARepeatAndEndsInTheDestinationForEveryPage() {
        for destination in NavigationTestSupport.allDestinations() {
            for current in AppTab.allCases {
                let result = NavigationRules.go(destination, from: current, path: [])
                XCTAssertEqual(Set(result.path).count, result.path.count, "geen herhaling in \(result.path)")
                XCTAssertEqual(NavigationRules.normalize(result.path), result.path)
                if destination.isTabRoot {
                    XCTAssertTrue(result.path.isEmpty, "\(destination) is een tabwortel")
                } else {
                    XCTAssertEqual(result.path.last, destination, "\(destination)")
                    XCTAssertEqual(Array(result.path.dropLast()), destination.parents, "\(destination)")
                }
            }
        }
    }

    func testGoToARootSelectsThatTabWithAnEmptyPath() {
        let home = NavigationRules.go(.home, from: .library, path: [.pots])
        XCTAssertEqual(home.tab, .home)
        XCTAssertEqual(home.path, [])
        let library = NavigationRules.go(.library, from: .home, path: [.tools])
        XCTAssertEqual(library.tab, .library)
        XCTAssertEqual(library.path, [])
    }

    func testGoOpensEveryPageInTheLibraryWithItsParents() {
        let pages: [Destination] = [.flow, .income, .expenses, .distribute, .bank, .cashflow, .pots, .portfolio,
                                    .goals, .savingsGoal, .accelerators, .buffer, .projection, .purchase, .tools]
        for destination in pages {
            for current in AppTab.allCases {
                let result = NavigationRules.go(destination, from: current, path: [.bank, .income])
                XCTAssertEqual(result.tab, .library, "\(destination) vanaf \(current)")
                XCTAssertEqual(result.path, [destination], "een bestaand pad wordt vervangen")
            }
        }
    }

    func testGoBuildsTheParentPath() {
        XCTAssertEqual(NavigationRules.go(.pot(a), from: .home, path: []).path, [.pots, .pot(a)])
        XCTAssertEqual(NavigationRules.go(.pot(a), from: .home, path: []).tab, .library)
        XCTAssertEqual(NavigationRules.go(.holding(b), from: .search, path: []).path, [.portfolio, .holding(b)])
        XCTAssertEqual(NavigationRules.go(.holding(b), from: .search, path: []).tab, .library)
        XCTAssertEqual(NavigationRules.go(.goal(a), from: .library, path: []).path, [.goals, .goal(a)])
        XCTAssertEqual(NavigationRules.go(.salary, from: .home, path: []).path, [.income, .salary])
        XCTAssertEqual(NavigationRules.go(.salary, from: .home, path: []).tab, .library)
    }

    func testGoToAPageWithoutAParentIsJustThatPage() {
        XCTAssertEqual(NavigationRules.go(.cashflow, from: .home, path: []).path, [.cashflow])
        XCTAssertEqual(NavigationRules.go(.income, from: .home, path: []).path, [.income])
        XCTAssertEqual(NavigationRules.go(.buffer, from: .home, path: []).path, [.buffer])
        XCTAssertEqual(NavigationRules.go(.flow, from: .home, path: []).path, [.flow])
        XCTAssertEqual(NavigationRules.go(.tools, from: .library, path: []).path, [.tools])
    }

    func testGoToSettingsStaysOnTheCurrentStackAndAddsTheMissingParents() {
        // Zonder pad: Instellingen, dan de hoofdpagina, dan de pagina.
        XCTAssertEqual(NavigationRules.go(.settingsRoot, from: .home, path: []).path, [.settingsRoot])
        XCTAssertEqual(NavigationRules.go(.settingsRoot, from: .home, path: []).tab, .home)
        XCTAssertEqual(NavigationRules.go(.settings(.account), from: .library, path: []).path,
                       [.settingsRoot, .settings(.account)])
        XCTAssertEqual(NavigationRules.go(.settings(.account), from: .library, path: []).tab, .library)
        XCTAssertEqual(NavigationRules.go(.settings(.password), from: .search, path: []).path,
                       [.settingsRoot, .settings(.account), .settings(.password)])
        XCTAssertEqual(NavigationRules.go(.settings(.password), from: .search, path: []).tab, .search)
        XCTAssertEqual(NavigationRules.go(.settings(.importReview), from: .home, path: []).path,
                       [.settingsRoot, .settings(.data), .settings(.importReview)])
        XCTAssertEqual(NavigationRules.go(.settings(.prices), from: .home, path: []).path, [.settingsRoot, .settings(.prices)])
        // De startdatum (ook vanuit de lege start van Home) staat onder Gegevens.
        XCTAssertEqual(NavigationRules.go(.settings(.startDate), from: .home, path: []).path,
                       [.settingsRoot, .settings(.data), .settings(.startDate)])
        XCTAssertEqual(NavigationRules.go(.settings(.startDate), from: .home, path: []).tab, .home)
    }

    func testGoToSettingsKeepsTheExistingPathBelowInstellingen() {
        // Het pad blijft staan: terug brengt je naar waar je was.
        let result = NavigationRules.go(.settings(.data), from: .library, path: [.pots, .pot(a)])
        XCTAssertEqual(result.tab, .library)
        XCTAssertEqual(result.path, [.pots, .pot(a), .settingsRoot, .settings(.data)])
    }

    func testGoToSettingsWhenInstellingenIsAlreadyOpenCutsBackToIt() {
        let open: [Destination] = [.pots, .settingsRoot, .settings(.data), .settings(.importReview)]
        let toAccount = NavigationRules.go(.settings(.account), from: .home, path: open)
        XCTAssertEqual(toAccount.path, [.pots, .settingsRoot, .settings(.account)])
        let toRoot = NavigationRules.go(.settingsRoot, from: .home, path: open)
        XCTAssertEqual(toRoot.path, [.pots, .settingsRoot])
        let same = NavigationRules.go(.settings(.importReview), from: .home, path: open)
        XCTAssertEqual(same.path, open)
        let sub = NavigationRules.go(.settings(.password), from: .home, path: [.settingsRoot, .settings(.account)])
        XCTAssertEqual(sub.path, [.settingsRoot, .settings(.account), .settings(.password)])
    }

    func testGoToSettingsNeverLeavesARepeat() {
        let paths: [[Destination]] = [
            [], [.settingsRoot], [.settingsRoot, .settings(.account)], [.pots, .settingsRoot, .settings(.data)],
            [.settingsRoot, .settings(.account), .settings(.password)]
        ]
        for path in paths {
            for page in SettingsPage.allCases {
                for current in AppTab.allCases {
                    let result = NavigationRules.go(.settings(page), from: current, path: path)
                    XCTAssertEqual(result.tab, current)
                    XCTAssertEqual(Set(result.path).count, result.path.count, "\(result.path)")
                    XCTAssertEqual(result.path.last, .settings(page))
                    XCTAssertTrue(result.path.contains(.settingsRoot))
                }
            }
        }
    }
}
