import XCTest

/// De functies van fase 3 in de echte app (simulator, voorbeelddata): een loonwijziging bewaren en terugzien op Salaris, de uren uit de
/// (demo-)agenda op Salaris en Inkomen, en het kruimelpad onder de titel (zoals op apple.com).
final class FeatureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = ["-mybuddy-demo"] + arguments
        app.launch()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func reveal(_ element: XCUIElement, swipes: Int = 10) {
        var count = 0
        while !(element.exists && element.isHittable) && count < swipes {
            app.swipeUp()
            count += 1
        }
    }

    func testAWageChangeIsSavedAndShownOnSalary() {
        launch(["-mybuddy-tab", "library", "-mybuddy-open", "salary"])
        let add = app.buttons["Loon wijzigen vanaf een maand"]
        reveal(add)
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Salaris heeft de knop Loon wijzigen vanaf een maand")
        add.tap()
        XCTAssertTrue(app.navigationBars["Loon wijzigen"].waitForExistence(timeout: 5), "de pagina Loon wijzigen opent")
        let rate = app.textFields["Uurloon"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        // Het getal staat rechts in het veld: tik daar, zodat de cursor achter het getal staat en wissen werkt.
        rate.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        rate.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "31")
        let save = app.buttons["Bewaar"]
        XCTAssertTrue(save.isEnabled, "een ander uurloon kan bewaard worden")
        save.tap()
        XCTAssertTrue(app.navigationBars["Salaris"].waitForExistence(timeout: 5), "Bewaar gaat terug naar Salaris")
        // De kaart Loon per maand staat boven de knop: de rij bestaat (ook buiten beeld) zodra de wijziging bewaard is.
        let row = element(containing: "31,00 per uur")
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "de nieuwe wijziging staat bij Loon per maand; gevonden: \(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Vanaf'")).allElementsBoundByIndex.map(\.label))")
    }

    func testCalendarHoursShowOnSalaryAndIncome() {
        launch(["-mybuddy-demo-hours", "-mybuddy-tab", "library", "-mybuddy-open", "salary"])
        let card = element(containing: "Uren van de volgende uitbetalingen")
        reveal(card)
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Salaris toont de uren van de volgende uitbetalingen")
        XCTAssertTrue(element(containing: "Uitbetaling").waitForExistence(timeout: 10), "met een uitbetaling uit de agenda")

        app.terminate()
        launch(["-mybuddy-demo-hours", "-mybuddy-tab", "library", "-mybuddy-open", "income"])
        let detail = element(containing: "agenda")
        reveal(detail)
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "Inkomen zegt bij het salaris dat de uren uit de agenda komen")
    }

    func testTheTitleMenuJumpsToALevelAbove() {
        // Zonder tab: rechtstreeks naar Loon wijzigen in de Bibliotheek, met Inkomen en Salaris erboven op het pad.
        launch(["-mybuddy-open", "wagechange"])
        let bar = app.navigationBars["Loon wijzigen"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        // Met een titelmenu is de titel een knop (met een pijltje); het label begint met de titel.
        let title = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Loon wijzigen' AND NOT (label CONTAINS 'vanaf')")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "de titel is een menu; de balk: \(bar.debugDescription)")
        title.tap()
        let income = app.buttons["Inkomen"]
        XCTAssertTrue(income.waitForExistence(timeout: 5), "het titelmenu toont Inkomen als niveau erboven")
        income.tap()
        XCTAssertTrue(app.navigationBars["Inkomen"].waitForExistence(timeout: 5), "de keuze springt naar Inkomen")
    }
}

/// iPad: de onderdelen van de Bibliotheek in de zijbalk openen hun pagina (zoals Apple TV en Apple Muziek). Alleen op een iPad.
final class SidebarUITests: XCTestCase {
    func testASidebarItemOpensItsPage() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("de zijbalksectie bestaat alleen op iPad en Mac") }
        let app = XCUIApplication()
        app.launchArguments = ["-mybuddy-demo", "-mybuddy-tab", "sidebar-pots"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Spaarpotten"].waitForExistence(timeout: 10), "het zijbalkitem Spaarpotten opent Spaarpotten")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Bibliotheek'")).count <= 1, true,
                       "Bibliotheek staat hooguit één keer in de bovenbalk")
    }
}

/// Legt de zoomovergang vast in beelden (alleen als `SHOT_DIR` is gezet, in de screenshot-job van CI).
final class ZoomFramesUITests: XCTestCase {
    func testZoomFromATileFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"], !dir.isEmpty else { throw XCTSkip("alleen in de screenshot-job") }
        let app = XCUIApplication()
        app.launchArguments = ["-mybuddy-demo"]
        app.launch()
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vakantie'")).firstMatch
        var count = 0
        while !(tile.exists && tile.isHittable) && count < 8 { app.swipeUp(); count += 1 }
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        func shot(_ name: String) {
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("zoom-\(name).png"))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "zoom-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        shot("0-voor")
        tile.tap()
        shot("1-tijdens")
        shot("2-tijdens")
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Storten'")).firstMatch.waitForExistence(timeout: 5)
        shot("3-pagina")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        shot("4-terug")
        _ = tile.waitForExistence(timeout: 5)
        shot("5-home")
    }
}
