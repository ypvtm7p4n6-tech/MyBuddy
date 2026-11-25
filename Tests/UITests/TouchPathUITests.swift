import XCTest

/// De aanraakpaden van de app in de echte app (simulator, voorbeelddata): een tegel op Home opent zijn pagina (zoom, zoals Apple TV en
/// Apple Muziek), terug brengt je naar Home, de balk boven de tabbalk opent Verdelen (iOS 26), een bladertegel in Zoeken opent zijn
/// pagina, en Instellingen heeft Werkuren met de bijbehorende pagina.
final class TouchPathUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-mybuddy-demo"]
        app.launch()
    }

    /// Scrolt tot een element bestaat en raakbaar is (planken staan lager op Home).
    private func reveal(_ element: XCUIElement, swipes: Int = 8) {
        var count = 0
        while !(element.exists && element.isHittable) && count < swipes {
            app.swipeUp()
            count += 1
        }
    }

    private func button(startingWith text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    func testAPotTileOnHomeOpensThePotAndBackReturnsHome() {
        let tile = button(startingWith: "Vakantie")
        reveal(tile)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "de tegel Vakantie staat op Home")
        tile.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Storten'")).firstMatch.waitForExistence(timeout: 5),
                      "de pagina van de pot opent met Storten")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "terug op Home staat de tegel er weer")
    }

    func testTheBarAboveTheTabBarOpensDistribute() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("de balk boven de tabbalk bestaat vanaf iOS 26") }
        let bar = button(startingWith: "Nog te verdelen deze maand")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "de balk Nog te verdelen staat boven de tabbalk")
        bar.tap()
        XCTAssertTrue(app.navigationBars["Verdelen"].waitForExistence(timeout: 5), "de balk opent Verdelen")
    }

    func testABrowseTileInSearchOpensItsPage() {
        let search = app.buttons.matching(NSPredicate(format: "label IN %@", ["Zoeken", "Search"])).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let tile = app.buttons["Inkomen"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Blader toont de tegel Inkomen")
        tile.tap()
        XCTAssertTrue(app.navigationBars["Inkomen"].waitForExistence(timeout: 5), "de tegel opent Inkomen")
    }

    func testSettingsLeadsToWorkHours() {
        let profile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'instellingen'")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5), "de profielknop staat op Home")
        profile.tap()
        let row = button(startingWith: "Werkuren")
        reveal(row)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Instellingen heeft de rij Werkuren")
        row.tap()
        XCTAssertTrue(app.navigationBars["Werkuren"].waitForExistence(timeout: 5), "de rij opent Werkuren")
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Uren uit je agenda'")).firstMatch.exists)
    }
}
