import XCTest
import Foundation
@testable import MyBuddyCore

/// De teksten en keuzes bij geld uit of naar een spaarpot met een bestemming of herkomst (docs/work/plan2.md par. 3.5, D5).
final class PotMoveTextTests: XCTestCase {
    private func twoPots() -> (FinanceData, Pot, Pot) {
        var d = FinanceData(startMonth: oct2026)
        let a = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: oct2026)
        let b = Pot(name: "Buffer", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(a); d.addPot(b)
        return (d, a, b)
    }

    func testPotMoveChoicesAndTitles() {
        let (d, a, b) = twoPots()
        XCTAssertEqual(PotMoveText.choices(excluding: a.id, in: d), [.outside, .bank, .pot(b.id)])
        XCTAssertEqual(PotMoveText.title(.pot(b.id), in: d), "Buffer")
        XCTAssertEqual(PotMoveText.title(.bank, in: d), "Bankrekening")
        XCTAssertEqual(PotMoveText.title(.outside, in: d), "Nergens (uit je overzicht)")
        XCTAssertEqual(PotMoveText.question(.withdraw), "Waar gaat het naartoe?")
        XCTAssertEqual(PotMoveText.question(.deposit), "Waar komt het vandaan?")
        XCTAssertTrue(PotMoveText.footer(.withdraw, end: .pot(b.id), amount: 60, in: d).contains("Buffer"))
        XCTAssertTrue(PotMoveText.footer(.withdraw, end: .bank, amount: 60, in: d).contains(Fmt.euro(60)))
        XCTAssertTrue(PotMoveText.footer(.deposit, end: .outside, amount: 5, in: d).contains("Er verandert niets aan je bankrekening"))
        XCTAssertTrue(PotMoveText.bankUnknownNote(amount: 60).contains("nog niet ingevuld"))
    }

    func testTheDefaultChoiceIsNowhereLikeBefore() {
        let (d, a, _) = twoPots()
        XCTAssertEqual(PotMoveText.choices(excluding: a.id, in: d).first, .outside, "de standaardkeuze blijft wat Opnemen altijd deed")
        // Zonder andere pot: alleen buiten het overzicht en de bankrekening.
        var single = FinanceData(startMonth: oct2026)
        let only = Pot(name: "Los", monthlyContribution: 0, startMonth: oct2026)
        single.addPot(only)
        XCTAssertEqual(PotMoveText.choices(excluding: only.id, in: single), [.outside, .bank])
        XCTAssertEqual(PotMoveText.title(.pot(UUID()), in: single), "Spaarpot", "een pot die niet meer bestaat")
    }

    func testEveryCombinationOfDirectionAndEndHasAFooter() {
        let (d, a, b) = twoPots()
        for direction in [PotMoveDirection.withdraw, .deposit] {
            for end in [MoneyEnd.outside, .bank, .pot(b.id), .pot(UUID())] {
                let text = PotMoveText.footer(direction, end: end, amount: 12.5, in: d)
                XCTAssertTrue(text.contains(Fmt.euro(12.5)), text)
                XCTAssertFalse(text.contains("  "), text)
                XCTAssertTrue(text.hasSuffix("."), text)
            }
        }
        XCTAssertTrue(PotMoveText.footer(.withdraw, end: .outside, amount: 5, in: d).contains("nergens anders in je overzicht"))
        XCTAssertTrue(PotMoveText.footer(.deposit, end: .pot(a.id), amount: 5, in: d).contains("Vakantie"))
        XCTAssertTrue(PotMoveText.footer(.withdraw, end: .pot(UUID()), amount: 5, in: d).contains("de andere pot"))
        XCTAssertEqual(PotMoveText.outsideTitle, "Nergens (uit je overzicht)")
        XCTAssertEqual(PotMoveText.bankTitle, "Bankrekening")
    }
}
