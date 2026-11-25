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
        // De zoektab heeft op iOS 26 een systeemlabel; de test gaat over de bladertegel, dus de app start op de zoektab.
        app.terminate()
        app.launchArguments = ["-mybuddy-demo", "-mybuddy-tab", "search"]
        app.launch()
        let tile = app.buttons["Inkomen"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "Blader toont de tegel Inkomen")
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

    func testTheDirectoryAtTheBottomOfHomeOpensAPage() {
        // Zoals de voettekst van apple.com: onderaan Home staat elke pagina als kleine link.
        let link = app.buttons["Toekomstschatting"].firstMatch
        var count = 0
        while !(link.exists && link.isHittable) && count < 15 { app.swipeUp(); count += 1 }
        XCTAssertTrue(link.waitForExistence(timeout: 5), "de gids onderaan Home heeft Toekomstschatting")
        link.tap()
        XCTAssertTrue(app.navigationBars["Toekomstschatting"].waitForExistence(timeout: 5), "de link opent Toekomstschatting")
    }

    func testTheChapterRowOnTopOfTheLibraryOpensAPage() {
        // Zoals apple.com/iphone: bovenaan de Bibliotheek een rij pictogrammen met elke pagina.
        app.terminate()
        app.launchArguments = ["-mybuddy-demo", "-mybuddy-tab", "library"]
        app.launch()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Alle pagina's")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "de Bibliotheek begint met de rij met alle pagina's")
        let doelen = row.buttons["Doelen"].firstMatch
        XCTAssertTrue(doelen.waitForExistence(timeout: 5))
        doelen.tap()
        XCTAssertTrue(app.navigationBars["Doelen"].waitForExistence(timeout: 5), "het pictogram opent Doelen")
    }
}
