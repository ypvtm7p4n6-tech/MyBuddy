import XCTest

/// De Mac-app (voorbeelddata): de zijbalk met de sectie Bibliotheek opent Spaarpotten, het Instellingen-venster (Cmd+komma) heeft de
/// pane Werkuren met de schakelaar "Uren uit je agenda", en de balk "Nog te verdelen" staat niet op de Mac (die is van iOS 26).
final class MacTouchPathUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-mybuddy-demo"]
        app.launch()
        app.activate()
    }

    private func any(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR title == %@ OR value == %@", text, text, text)).firstMatch
    }

    func testTheSidebarLibrarySectionOpensPots() {
        let item = any("Spaarpotten")
        XCTAssertTrue(item.waitForExistence(timeout: 15), "de zijbalk heeft Spaarpotten; venster: \(app.windows.firstMatch.debugDescription.prefix(3000))")
        item.click()
        let pot = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Vakantie'")).firstMatch
        XCTAssertTrue(pot.waitForExistence(timeout: 10), "Spaarpotten toont de pot Vakantie")
    }

    func testSettingsWindowHasWorkHours() {
        app.typeKey(",", modifierFlags: .command)
        let pane = any("Werkuren")
        XCTAssertTrue(pane.waitForExistence(timeout: 15), "het Instellingen-venster heeft de pane Werkuren")
        pane.click()
        let toggle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Uren uit je agenda' OR title BEGINSWITH 'Uren uit je agenda'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "de pane Werkuren toont de schakelaar Uren uit je agenda")
    }
}
