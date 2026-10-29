import XCTest
import Foundation
@testable import MyBuddyCore

// Tests van het zoeken in MyBuddy (App/Navigation/SearchIndex.swift, Foundation-only), uitputtend over de bestemmingen
// en de pagina's van Instellingen (par. 2.9 van docs/design/plan.md), de groepen en de tinten (par. 2.3 van docs/design2/plan.md).

final class SearchIndexTests: XCTestCase {
    private let october = YearMonth(year: 2026, month: 10)

    private func emptyData() -> FinanceData {
        FinanceData(startMonth: october)
    }

    private func destinations(_ results: [SearchEntry]) -> [Destination] {
        results.map { $0.destination }
    }

    /// Of een bestemming een eigen zoekregel moet hebben: de pagina's zonder id wel, een spaarpot, belegging of doel niet
    /// (die komen uit de gegevens van de gebruiker). Geen `default`: een nieuwe case moet hier worden ingedeeld.
    private func requiresPageEntry(_ destination: Destination) -> Bool {
        switch destination {
        case .home, .library, .flow, .income, .salary, .expenses, .distribute, .bank, .cashflow,
             .pots, .portfolio,
             .goals, .savingsGoal, .accelerators, .buffer, .projection, .purchase,
             .tools, .settingsRoot:
            return true
        case .pot, .holding, .goal:
            return false
        case .settings:
            return true
        }
    }

    // MARK: Uitputtend over de pagina's

    func testEveryPageDestinationHasAnEntryAndNoOtherDestinationHasOne() {
        let pageDestinations = Set(SearchIndex.pages.map { $0.destination })
        for destination in NavigationTestSupport.allDestinations() {
            if requiresPageEntry(destination) {
                XCTAssertTrue(pageDestinations.contains(destination), "geen zoekregel voor \(destination)")
            } else {
                XCTAssertFalse(pageDestinations.contains(destination), "\(destination) hoort bij de gegevens, niet in de vaste lijst")
            }
        }
    }

    func testPageEntryCountMatchesPageDestinations() {
        let required = NavigationTestSupport.allDestinations().filter { requiresPageEntry($0) }
        XCTAssertEqual(SearchIndex.pages.count, required.count)
        XCTAssertEqual(SearchIndex.pages.count, 30)
        XCTAssertEqual(SearchIndex.pages.count, PageCatalog.all.count + SettingsPage.allCases.count)
        // Elke bestemming heeft precies een regel.
        XCTAssertEqual(Set(SearchIndex.pages.map { $0.destination }).count, SearchIndex.pages.count)
    }

    func testEveryPageEntryHasTitleSymbolAndAnAlternativeName() {
        for entry in SearchIndex.pages {
            XCTAssertFalse(entry.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(entry.id) heeft geen titel")
            XCTAssertFalse(entry.symbol.isEmpty, "\(entry.id) heeft geen symbool")
            XCTAssertFalse(entry.terms.isEmpty, "\(entry.id) heeft geen alternatieve naam")
            XCTAssertTrue(entry.terms.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(entry.id)")
        }
    }

    func testPageEntryIDsAreUnique() {
        let ids = SearchIndex.pages.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEverySettingsPageEntryUsesThePageTitleOrAMoreSpecificOne() {
        for page in SettingsPage.allCases {
            let entry = SearchIndex.pages.first { $0.destination == .settings(page) }
            XCTAssertNotNil(entry, "geen zoekregel voor \(page)")
            XCTAssertEqual(entry?.title, page.title, "de titel van \(page) in het zoeken is die van de pagina")
            XCTAssertEqual(entry?.symbol, page.symbol)
        }
    }

    // MARK: Zoekopdrachten

    func testEmptyOrBlankQueryGivesNoResults() {
        XCTAssertTrue(SearchIndex.results(for: "", in: emptyData()).isEmpty)
        XCTAssertTrue(SearchIndex.results(for: "   ", in: emptyData()).isEmpty)
        XCTAssertTrue(SearchIndex.results(for: "\n", in: emptyData()).isEmpty)
    }

    func testQueryWithoutMatchGivesNoResults() {
        XCTAssertTrue(SearchIndex.results(for: "zzzzqq", in: emptyData()).isEmpty)
    }

    func testFindsAPageByItsTitleIgnoringCaseAndAccents() {
        let data = emptyData()
        XCTAssertEqual(SearchIndex.results(for: "uitgaven", in: data).first?.destination, .expenses)
        XCTAssertEqual(SearchIndex.results(for: "UITGAVEN", in: data).first?.destination, .expenses)
        XCTAssertEqual(SearchIndex.results(for: "  Uitgaven  ", in: data).first?.destination, .expenses)
        XCTAssertEqual(destinations(SearchIndex.results(for: "spaarpotten", in: data)),
                       destinations(SearchIndex.results(for: "SPAARPÖTTEN", in: data)))
        XCTAssertFalse(SearchIndex.results(for: "spaarpotten", in: data).isEmpty)
        // "é" en "e" zijn hetzelfde.
        XCTAssertTrue(destinations(SearchIndex.results(for: "ETF", in: data)).contains(.portfolio))
        XCTAssertTrue(destinations(SearchIndex.results(for: "ÉTF", in: data)).contains(.portfolio))
    }

    func testFindsPagesByTheAlternativeNamesOfPar29() {
        let data = emptyData()
        func found(_ query: String) -> [Destination] { destinations(SearchIndex.results(for: query, in: data)) }

        XCTAssertEqual(found("Uitgaven").first, .expenses)
        XCTAssertEqual(found("Dag voor dag").first, .cashflow)
        XCTAssertEqual(found("Noodbuffer").first, .buffer)
        XCTAssertTrue(found("Rente").contains(.pots))
        XCTAssertTrue(found("Rente").contains(.settings(.calculations)))
        XCTAssertTrue(found("Back-up").contains(.settings(.data)))
        XCTAssertTrue(found("Wachtwoord").contains(.settings(.password)))
        XCTAssertTrue(found("Salaris").contains(.salary))
        XCTAssertTrue(found("Salaris").contains(.income))
        XCTAssertEqual(found("Koersen").first, .settings(.prices))
        XCTAssertTrue(found("Koersen").contains(.portfolio))
        XCTAssertEqual(found("Account").first, .settings(.account))
        XCTAssertTrue(found("Belegd sinds").contains(.portfolio))
        XCTAssertTrue(found("Minimumsaldo").contains(.bank))
    }

    func testFindsTheStartDatePageByItsTerms() {
        let data = emptyData()
        func found(_ query: String) -> [Destination] { destinations(SearchIndex.results(for: query, in: data)) }
        // De termen van docs/work/plan.md par. 2.3: beginnen, startdatum, begindatum, vanaf, opnieuw beginnen, eerste dag, beginsaldo.
        for term in ["beginnen", "startdatum", "begindatum", "vanaf", "opnieuw beginnen", "eerste dag", "beginsaldo", "Startdatum"] {
            XCTAssertTrue(found(term).contains(.settings(.startDate)), "'\(term)' vindt de startdatum niet")
        }
        XCTAssertEqual(found("Startdatum").first, .settings(.startDate), "de titel begint ermee")
        let entry = SearchIndex.pages.first { $0.destination == .settings(.startDate) }
        XCTAssertEqual(entry?.id, "settings-startDate")
        XCTAssertEqual(entry?.title, "Startdatum")
        XCTAssertEqual(entry?.group, .settings)
        XCTAssertEqual(entry?.hue, .sage)
    }

    func testTitlePrefixComesBeforeTitleContainsBeforeOtherNames() {
        let data = emptyData()
        // "bank": de titel Bankrekening begint ermee.
        XCTAssertEqual(SearchIndex.results(for: "bank", in: data).first?.destination, .bank)
        // "saldo": geen titel bevat het, de pagina's met "saldo" als andere naam volgen in vaste volgorde.
        let saldo = destinations(SearchIndex.results(for: "saldo", in: data))
        XCTAssertTrue(saldo.contains(.bank))
        XCTAssertTrue(saldo.contains(.cashflow))
        // "gegevens" staat in de titel van een pagina: die komt vóór pagina's met alleen een andere naam.
        let gegevens = destinations(SearchIndex.results(for: "gegevens", in: data))
        XCTAssertEqual(gegevens.first, .settings(.data))
    }

    func testMultiWordQueryNeedsEveryWord() {
        let data = emptyData()
        let found = destinations(SearchIndex.results(for: "nog verdelen", in: data))
        XCTAssertTrue(found.contains(.distribute))
        XCTAssertTrue(found.contains(.home))
        XCTAssertFalse(found.contains(.pots))
        XCTAssertTrue(SearchIndex.results(for: "nog bankrekening", in: data).isEmpty)
    }

    func testResultsHaveUniqueIDs() {
        let results = SearchIndex.results(for: "e", in: emptyData())
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(Set(results.map { $0.id }).count, results.count)
    }

    // MARK: De gegevens van de gebruiker

    func testFindsPotsHoldingsGoalsAndLines() {
        var data = emptyData()
        let pot = Pot(name: "Vakantiepot", startMonth: october)
        let holding: Holding = {
            var h = Holding(name: "Wereldfonds", startMonth: october)
            h.ticker = "VWCE.DE"
            return h
        }()
        let goal = LifeGoal(name: "Pensioen 2050", kind: .retirement)
        data.pots.append(pot)
        data.holdings.append(holding)
        data.goals.append(goal)
        var plan = MonthPlan()
        plan.extraIncome = [MoneyLine(name: "Bijbaan", amount: 150)]
        plan.expenses = [MoneyLine(name: "Sportschool", amount: 30)]
        data.months[october.key] = plan

        XCTAssertEqual(SearchIndex.results(for: "vakantiepot", in: data).first?.destination, .pot(pot.id))
        XCTAssertEqual(SearchIndex.results(for: "wereldfonds", in: data).first?.destination, .holding(holding.id))
        XCTAssertEqual(SearchIndex.results(for: "vwce", in: data).first?.destination, .holding(holding.id))
        XCTAssertEqual(SearchIndex.results(for: "pensioen 2050", in: data).first?.destination, .goal(goal.id))
        XCTAssertEqual(SearchIndex.results(for: "bijbaan", in: data).first?.destination, .income)
        XCTAssertEqual(SearchIndex.results(for: "sportschool", in: data).first?.destination, .expenses)
        XCTAssertEqual(SearchIndex.results(for: "SPORTSCHOOL", in: data).first?.title, "Sportschool")
    }

    func testAnEntryOfTheUsersDataShowsTheNameAndTheSymbolOfItsKind() {
        var data = emptyData()
        var pot = Pot(name: "Auto", startMonth: october)
        pot.symbol = "car"
        data.pots.append(pot)
        let entry = SearchIndex.results(for: "auto", in: data).first { $0.destination == .pot(pot.id) }
        XCTAssertEqual(entry?.title, "Auto")
        XCTAssertEqual(entry?.symbol, "car")
    }

    func testARepeatedLineIsListedOnce() {
        var data = emptyData()
        for offset in 0..<3 {
            var plan = MonthPlan()
            plan.expenses = [MoneyLine(name: "Huur", amount: 1_000, isRecurring: true)]
            data.months[october.adding(offset).key] = plan
        }
        let rent = SearchIndex.results(for: "huur", in: data).filter { $0.destination == .expenses }
        XCTAssertEqual(rent.count, 1)
    }

    func testBlankNamesAreIgnored() {
        var data = emptyData()
        data.pots.append(Pot(name: "   ", startMonth: october))
        data.holdings.append(Holding(name: "", startMonth: october))
        data.goals.append(LifeGoal(name: " ", kind: .custom))
        let all = SearchIndex.results(for: "spaarpot", in: data)
        XCTAssertTrue(all.allSatisfy { entry in
            if case .pot = entry.destination { return false }
            return true
        })
        XCTAssertTrue(SearchIndex.results(for: "belegging", in: data).allSatisfy { entry in
            if case .holding = entry.destination { return false }
            return true
        })
    }

    func testDataEntriesFollowThePagesForTheSameQuery() {
        // "Spaarpotten" geeft de pagina en daarna de potten waarvan de naam of soort erbij past, nooit andersom bij een titel
        // die er niet mee begint.
        var data = emptyData()
        data.pots.append(Pot(name: "Spaarpotje voor later", startMonth: october))
        let results = SearchIndex.results(for: "spaarpot", in: data)
        XCTAssertEqual(results.first?.destination, .pots)
        XCTAssertTrue(results.contains { entry in
            if case .pot = entry.destination { return true }
            return false
        })
    }

    func testResultsAreCapped() {
        var data = emptyData()
        for index in 0..<80 {
            data.pots.append(Pot(name: "Pot \(index)", startMonth: october))
        }
        let results = SearchIndex.results(for: "pot", in: data)
        XCTAssertEqual(results.count, SearchIndex.maxResults)
        XCTAssertEqual(Set(results.map { $0.id }).count, results.count)
    }

    func testEmptyDataStillFindsThePages() {
        let results = SearchIndex.results(for: "doel", in: emptyData())
        XCTAssertTrue(destinations(results).contains(.goals))
        XCTAssertTrue(destinations(results).contains(.savingsGoal))
    }

    // MARK: De catalogus als bron

    func testEveryCatalogPageIsFoundByItsTitleWithItsOwnSymbolAndHue() {
        for info in PageCatalog.all {
            let entry = SearchIndex.pages.first { $0.destination == info.destination }
            XCTAssertNotNil(entry, "\(info.title) staat niet in het zoeken")
            XCTAssertEqual(entry?.title, info.title)
            XCTAssertEqual(entry?.symbol, info.symbol)
            XCTAssertEqual(entry?.hue, info.hue)
            XCTAssertEqual(entry?.terms, info.terms)
            XCTAssertEqual(entry?.id, info.id)
            let found = SearchIndex.results(for: info.title, in: emptyData())
            XCTAssertTrue(found.contains { $0.destination == info.destination }, "\(info.title) is niet te vinden")
        }
    }

    func testTheNewPagesAreFoundByTheirTerms() {
        let data = emptyData()
        func found(_ query: String) -> [Destination] { destinations(SearchIndex.results(for: query, in: data)) }
        XCTAssertEqual(found("Maandoverzicht").first, .flow)
        XCTAssertTrue(found("Waar gaat je geld heen").contains(.flow))
        XCTAssertTrue(found("Half jaar").contains(.flow))
        XCTAssertEqual(found("Hulpmiddelen").first, .tools)
        XCTAssertTrue(found("Calculators").contains(.tools))
        XCTAssertTrue(found("Rekenhulp").contains(.tools))
        XCTAssertEqual(found("Home").first, .home)
        XCTAssertEqual(found("Bibliotheek").first, .library)
        XCTAssertEqual(found("Instellingen").first, .settingsRoot)
    }

    func testTheOldTabNameDoesNotComeBack() {
        let titles = SearchIndex.pages.map { $0.title }
        XCTAssertFalse(titles.contains("Overzicht"))
        XCTAssertTrue(SearchIndex.results(for: "Overzicht", in: emptyData()).allSatisfy { $0.title != "Overzicht" })
    }

    // MARK: Groepen

    func testSearchGroupsHaveTheTitlesOfThePlan() {
        XCTAssertEqual(SearchGroup.allCases, [.pages, .pots, .holdings, .goals, .lines, .settings])
        XCTAssertEqual(SearchGroup.allCases.map { $0.title },
                       ["Pagina's", "Spaarpotten", "Beleggingen", "Doelen", "Inkomen en uitgaven", "Instellingen"])
        XCTAssertEqual(Set(SearchGroup.allCases.map { $0.id }).count, 6)
    }

    func testEveryPageEntryIsInAPagesOrSettingsGroup() {
        for entry in SearchIndex.pages {
            switch entry.destination {
            case .settingsRoot, .settings:
                XCTAssertEqual(entry.group, .settings, "\(entry.id)")
            default:
                XCTAssertEqual(entry.group, .pages, "\(entry.id)")
            }
        }
    }

    private func richData() -> (data: FinanceData, pot: Pot, holding: Holding, goal: LifeGoal) {
        var data = emptyData()
        var pot = Pot(name: "Vakantiepot", startMonth: october)
        pot.colorIndex = 3
        var holding = Holding(name: "Wereldfonds", startMonth: october)
        holding.kind = .crypto
        let goal = LifeGoal(name: "Pensioen 2050", kind: .retirement)
        data.pots.append(pot)
        data.holdings.append(holding)
        data.goals.append(goal)
        var plan = MonthPlan()
        plan.extraIncome = [MoneyLine(name: "Bijbaan", amount: 150)]
        plan.expenses = [MoneyLine(name: "Sportschool", amount: 30)]
        data.months[october.key] = plan
        return (data, pot, holding, goal)
    }

    func testResultsFallInTheRightGroups() {
        let rich = richData()
        func group(_ query: String, _ destination: Destination) -> SearchGroup? {
            SearchIndex.results(for: query, in: rich.data).first { $0.destination == destination }?.group
        }
        XCTAssertEqual(group("vakantiepot", .pot(rich.pot.id)), .pots)
        XCTAssertEqual(group("wereldfonds", .holding(rich.holding.id)), .holdings)
        XCTAssertEqual(group("pensioen 2050", .goal(rich.goal.id)), .goals)
        XCTAssertEqual(group("bijbaan", .income), .lines)
        XCTAssertEqual(group("sportschool", .expenses), .lines)
        // De pagina's Inkomen en Uitgaven blijven pagina's, ook al hebben de regels dezelfde bestemming.
        XCTAssertEqual(group("inkomen", .income), .pages)
        XCTAssertEqual(group("uitgaven", .expenses), .pages)
        XCTAssertEqual(group("wachtwoord", .settings(.password)), .settings)
        XCTAssertEqual(group("instellingen", .settingsRoot), .settings)
    }

    func testResultsHaveTheHueOfTheirSource() {
        let rich = richData()
        func hue(_ query: String, _ destination: Destination) -> TileHue? {
            SearchIndex.results(for: query, in: rich.data).first { $0.destination == destination }?.hue
        }
        XCTAssertEqual(hue("vakantiepot", .pot(rich.pot.id)), TileHue.forIndex(3))
        XCTAssertEqual(hue("wereldfonds", .holding(rich.holding.id)), TileHue.forIndex(HoldingKind.crypto.colorIndex))
        XCTAssertEqual(hue("pensioen 2050", .goal(rich.goal.id)), .mustard)
        XCTAssertEqual(hue("bijbaan", .income), .terracotta)
        XCTAssertEqual(hue("wachtwoord", .settings(.password)), .sage)
        XCTAssertEqual(hue("spaarpotten", .pots), .teal)
    }

    func testGroupedKeepsGroupOrderAndRelevanceAndOnlyListsGroupsWithResults() {
        let rich = richData()
        let groups = SearchIndex.grouped(for: "pot", in: rich.data)
        XCTAssertFalse(groups.isEmpty)
        let order = groups.map { $0.group.rawValue }
        XCTAssertEqual(order, order.sorted(), "groepen staan in de volgorde van SearchGroup")
        XCTAssertEqual(Set(order).count, order.count, "elke groep hoogstens een keer")
        for item in groups {
            XCTAssertFalse(item.entries.isEmpty, "alleen groepen met resultaat")
            XCTAssertTrue(item.entries.allSatisfy { $0.group == item.group })
        }
        // Samen zijn het precies de resultaten van results(for:).
        let flat = groups.flatMap { $0.entries.map { $0.id } }
        XCTAssertEqual(Set(flat), Set(SearchIndex.results(for: "pot", in: rich.data).map { $0.id }))
        XCTAssertEqual(flat.count, SearchIndex.results(for: "pot", in: rich.data).count)
        // Binnen de groep Spaarpotten staat de pot na de pagina? De pagina zit in Pagina's, de pot in Spaarpotten.
        XCTAssertEqual(groups.first?.group, .pages)
        XCTAssertTrue(groups.contains { $0.group == .pots })
    }

    func testGroupedForABlankQueryOrNoMatchIsEmpty() {
        XCTAssertTrue(SearchIndex.grouped(for: "", in: emptyData()).isEmpty)
        XCTAssertTrue(SearchIndex.grouped(for: "   ", in: emptyData()).isEmpty)
        XCTAssertTrue(SearchIndex.grouped(for: "zzzzqq", in: emptyData()).isEmpty)
    }

    func testGroupedWithOnlyPagesHasOneOrTwoGroups() {
        let groups = SearchIndex.grouped(for: "rente", in: emptyData())
        // "Rente" staat bij Spaarpotten (pagina) en Rekenen (Instellingen).
        XCTAssertEqual(groups.map { $0.group }, [.pages, .settings])
    }

    func testEveryBrowseTileCanBeFoundAsAPageOrSettings() {
        for destination in PageCatalog.browse {
            XCTAssertTrue(SearchIndex.pages.contains { $0.destination == destination }, "\(destination)")
        }
    }
}
