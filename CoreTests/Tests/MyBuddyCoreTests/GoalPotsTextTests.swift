import XCTest
import Foundation
@testable import MyBuddyCore

/// De teksten van een doel dat uit meer spaarpotten wordt gefinancierd (docs/work/plan2.md par. 3.5, D4).
final class GoalPotsTextTests: XCTestCase {
    func testGoalPotsTexts() {
        XCTAssertEqual(GoalPotsText.potNames(["Vakantie", "Reis", "Auto"]), "Vakantie, Reis en Auto")
        XCTAssertNil(GoalPotsText.sharedWarning(otherGoalNames: []))
        XCTAssertEqual(GoalPotsText.sharedWarning(otherGoalNames: ["Auto"]), "Deze spaarpot telt ook mee voor Auto.")
        XCTAssertNil(GoalPotsText.potLine(goalNames: []))
        XCTAssertEqual(GoalPotsText.potLine(goalNames: ["Japan"]), "Telt mee voor het doel Japan.")
        XCTAssertEqual(GoalPotsText.potLine(goalNames: ["Japan", "Auto"]), "Telt mee voor de doelen Japan en Auto.")
        XCTAssertEqual(GoalPotsText.sourceLine(potNames: ["Vakantie", "Reis"]), "Uit Vakantie en Reis")
        XCTAssertEqual(GoalPotsText.sourceLine(potNames: ["A", "B", "C"]), "Uit 3 spaarpotten")
    }

    func testTheFixedTexts() {
        XCTAssertEqual(GoalPotsText.pickerTitle, "Spaarpotten")
        XCTAssertEqual(GoalPotsText.needsOnePot, "Kies minstens één spaarpot.")
        XCTAssertTrue(GoalPotsText.pickerFooter.contains("tellen samen"))
        XCTAssertTrue(GoalPotsText.pickerFooter.contains("voor elk doel"))
        XCTAssertTrue(GoalPotsText.acceleratorNote.contains("eerste spaarpot"))
        XCTAssertEqual(GoalPotsText.potNames(["Vakantie"]), "Vakantie")
        XCTAssertEqual(GoalPotsText.potNames(["Vakantie", "Reis"]), "Vakantie en Reis")
        XCTAssertEqual(GoalPotsText.sourceLine(potNames: ["Vakantie"]), "Uit Vakantie")
        XCTAssertEqual(GoalPotsText.sharedWarning(otherGoalNames: ["Auto", "Japan"]), "Deze spaarpot telt ook mee voor Auto en Japan.")
    }
}
