import XCTest
import Foundation

// Tests van de navigatieregels (App/Navigation/NavigationModel.swift, Foundation-only): tabs, bestemmingen, het afknippen
// van een pad bij een herhaalde bestemming (K16) en `go` met het ouderpad (par. 2.6 van docs/design/plan.md).

/// Hulp voor de tests van navigatie en zoeken: alle bestemmingen, en een uitputtende `switch` die bij een nieuwe case een
/// compileerfout geeft zodat de lijst en de verwachtingen worden bijgewerkt.
enum NavigationTestSupport {
    static let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    /// Een voorbeeld van elke case van `Destination` (en elke pagina van Instellingen).
    static func allDestinations() -> [Destination] {
        var list: [Destination] = [
            .overview,
            .income, .salary, .expenses, .distribute, .bank, .cashflow,
            .pots, .pot(idA), .portfolio, .holding(idB),
            .goals, .goal(idA), .savingsGoal, .accelerators, .buffer, .projection, .purchase
        ]
        for page in SettingsPage.allCases { list.append(.settings(page)) }
        return list
    }

    /// Het volgnummer van een case. De `switch` heeft geen `default`: een nieuwe case compileert pas als hij hier staat.
    static func ordinal(_ destination: Destination) -> Int {
        switch destination {
        case .overview: return 0
        case .income: return 1
        case .salary: return 2
        case .expenses: return 3
        case .distribute: return 4
        case .bank: return 5
        case .cashflow: return 6
        case .pots: return 7
        case .pot: return 8
        case .portfolio: return 9
        case .holding: return 10
        case .goals: return 11
        case .goal: return 12
        case .savingsGoal: return 13
        case .accelerators: return 14
        case .buffer: return 15
        case .projection: return 16
        case .purchase: return 17
        case .settings: return 18
        }
    }

    static let caseCount = 19

    /// De tab die par. 2.6 voor elke bestemming noemt, los van de implementatie.
    static func expectedTab(_ destination: Destination) -> AppTab {
        switch destination {
        case .overview: return .overview
        case .income, .salary, .expenses, .distribute, .bank, .cashflow: return .month
        case .pots, .pot, .portfolio, .holding: return .saving
        case .goals, .goal, .savingsGoal, .accelerators, .buffer, .projection, .purchase: return .planning
        case .settings: return .settings
        }
    }
}

final class NavigationRulesTests: XCTestCase {
    private let a = NavigationTestSupport.idA
    private let b = NavigationTestSupport.idB

    // MARK: Tabs

    func testTabsHaveFixedOrderTitlesAndSymbols() {
        XCTAssertEqual(AppTab.allCases, [.overview, .month, .saving, .planning, .settings])
        XCTAssertEqual(AppTab.allCases.map { $0.title }, ["Overzicht", "Maand", "Sparen", "Plannen", "Instellingen"])
        XCTAssertEqual(AppTab.allCases.map { $0.rawValue }, ["overview", "month", "saving", "planning", "settings"])
        let symbols = AppTab.allCases.map { $0.symbol }
        XCTAssertEqual(Set(symbols).count, symbols.count, "elke tab heeft een eigen symbool")
        XCTAssertTrue(symbols.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(AppTab.settings.id, "settings")
    }

    // MARK: Bestemmingen

    func testDestinationListCoversEveryCase() {
        let ordinals = Set(NavigationTestSupport.allDestinations().map { NavigationTestSupport.ordinal($0) })
        XCTAssertEqual(ordinals, Set(0..<NavigationTestSupport.caseCount))
    }

    func testDestinationTabIsTotalAndMatchesTheTable() {
        for destination in NavigationTestSupport.allDestinations() {
            XCTAssertEqual(destination.tab, NavigationTestSupport.expectedTab(destination), "\(destination)")
        }
    }

    func testEveryTabHasAtLeastOneDestination() {
        let tabs = Set(NavigationTestSupport.allDestinations().map { $0.tab })
        XCTAssertEqual(tabs, Set(AppTab.allCases))
    }

    // MARK: Instellingenpagina's

    func testSettingsPagesHaveTitlesSymbolsAndParents() {
        XCTAssertEqual(SettingsPage.allCases.count, 10)
        let titles = SettingsPage.allCases.map { $0.title }
        XCTAssertEqual(Set(titles).count, titles.count, "elke pagina heeft een eigen titel")
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(SettingsPage.allCases.allSatisfy { !$0.symbol.isEmpty })

        XCTAssertEqual(SettingsPage.password.parent, .account)
        XCTAssertEqual(SettingsPage.deleteAccount.parent, .account)
        XCTAssertEqual(SettingsPage.conflictBackups.parent, .account)
        XCTAssertEqual(SettingsPage.importReview.parent, .data)
        for page in SettingsPage.panes { XCTAssertNil(page.parent, "\(page) is een hoofdpagina") }
    }

    func testSettingsPanesAreTheSixMainPagesAndEverySubpageBelongsToOne() {
        XCTAssertEqual(SettingsPage.panes, [.account, .calculations, .prices, .data, .layout, .about])
        for page in SettingsPage.allCases {
            XCTAssertTrue(SettingsPage.panes.contains(page.pane), "\(page) hoort bij een pane")
        }
        XCTAssertEqual(SettingsPage.password.pane, .account)
        XCTAssertEqual(SettingsPage.importReview.pane, .data)
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

    // MARK: go

    func testGoGivesTheOwnTabAndAPathEndingInTheDestinationForEveryDestination() {
        for destination in NavigationTestSupport.allDestinations() {
            let result = NavigationRules.go(destination)
            XCTAssertEqual(result.tab, destination.tab, "\(destination)")
            if destination == .overview {
                XCTAssertTrue(result.path.isEmpty, "het Overzicht is een tabwortel")
            } else {
                XCTAssertEqual(result.path.last, destination, "\(destination)")
            }
            XCTAssertEqual(Set(result.path).count, result.path.count, "geen herhaling in \(result.path)")
            XCTAssertEqual(NavigationRules.normalize(result.path), result.path)
        }
    }

    func testGoBuildsTheParentPath() {
        XCTAssertEqual(NavigationRules.go(.pot(a)).path, [.pots, .pot(a)])
        XCTAssertEqual(NavigationRules.go(.pot(a)).tab, .saving)
        XCTAssertEqual(NavigationRules.go(.holding(b)).path, [.portfolio, .holding(b)])
        XCTAssertEqual(NavigationRules.go(.holding(b)).tab, .saving)
        XCTAssertEqual(NavigationRules.go(.goal(a)).path, [.goals, .goal(a)])
        XCTAssertEqual(NavigationRules.go(.goal(a)).tab, .planning)
        XCTAssertEqual(NavigationRules.go(.salary).path, [.income, .salary])
        XCTAssertEqual(NavigationRules.go(.salary).tab, .month)
        XCTAssertEqual(NavigationRules.go(.settings(.password)).path, [.settings(.account), .settings(.password)])
        XCTAssertEqual(NavigationRules.go(.settings(.deleteAccount)).path, [.settings(.account), .settings(.deleteAccount)])
        XCTAssertEqual(NavigationRules.go(.settings(.conflictBackups)).path, [.settings(.account), .settings(.conflictBackups)])
        XCTAssertEqual(NavigationRules.go(.settings(.importReview)).path, [.settings(.data), .settings(.importReview)])
        XCTAssertEqual(NavigationRules.go(.settings(.importReview)).tab, .settings)
    }

    func testGoToAPageWithoutAParentIsJustThatPage() {
        XCTAssertEqual(NavigationRules.go(.cashflow).path, [.cashflow])
        XCTAssertEqual(NavigationRules.go(.cashflow).tab, .month)
        XCTAssertEqual(NavigationRules.go(.income).path, [.income])
        XCTAssertEqual(NavigationRules.go(.buffer).path, [.buffer])
        XCTAssertEqual(NavigationRules.go(.buffer).tab, .planning)
        XCTAssertEqual(NavigationRules.go(.settings(.account)).path, [.settings(.account)])
        XCTAssertEqual(NavigationRules.go(.settings(.prices)).path, [.settings(.prices)])
    }

    func testGoToTheOverviewIsTheEmptyPathOfTheOverviewTab() {
        let result = NavigationRules.go(.overview)
        XCTAssertEqual(result.tab, .overview)
        XCTAssertEqual(result.path, [])
    }
}
