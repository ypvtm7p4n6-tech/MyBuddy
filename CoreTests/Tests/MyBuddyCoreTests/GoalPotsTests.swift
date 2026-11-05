import XCTest
import Foundation
@testable import MyBuddyCore

/// D4 (docs/work/plan2.md par. 2.4): een doel uit meer spaarpotten. `funding` blijft `.pot(eerste)` en `LifeGoal.morePotIDs` houdt de rest
/// (geen nieuw geval in `GoalFunding`: een oudere app ziet dan het doel met de eerste pot en het bestand blijft leesbaar).
final class GoalPotsTests: XCTestCase {
    private let now = day(oct2026, 12)

    private func fixture() -> (data: FinanceData, a: Pot, b: Pot, goal: LifeGoal) {
        var d = makeBaseData()
        let a = Pot(name: "Vakantie", monthlyContribution: 300, startMonth: aug2026)
        var b = Pot(name: "Reis", monthlyContribution: 0, startMonth: aug2026)
        b.contributionMode = .percentage
        b.contributionPercent = 5
        b.contributionExtra = 20
        d.addPot(a, openingBalance: 500, now: day(aug2026, 2))
        d.addPot(b, openingBalance: 250, now: day(aug2026, 2))
        var g = LifeGoal(name: "Japan", kind: .vacation)
        g.targetAmount = 6_000
        g.inflationAdjusted = false
        g.setFundingPots([a.id, b.id])
        d.addGoal(g)
        d.materialize(upTo: oct2026)
        return (d, a, b, g)
    }

    func testAGoalSumsTheBalancesAndTheMonthlyContributionOfItsPots() {
        let (d, a, b, g) = fixture()
        let inputs = d.goalInputs(for: g, current: oct2026, today: now)
        let balanceA = CentsMath.int(d.potBalanceNow(a.id, current: oct2026, today: now))
        let balanceB = CentsMath.int(d.potBalanceNow(b.id, current: oct2026, today: now))
        XCTAssertEqual(CentsMath.int(inputs.start), balanceA + balanceB)
        // 300 vast plus 5% van het salaris (3000 = 150) plus 20 extra.
        XCTAssertEqual(inputs.monthly, 470)
        XCTAssertEqual(inputs.sourceName, "2 spaarpotten")
        XCTAssertEqual(inputs.nominalReturn, 0)
    }

    func testTheOutcomeEqualsOneGoalWithTheSummedValues() {
        let (d, _, _, g) = fixture()
        let inputs = d.goalInputs(for: g, current: oct2026, today: now)
        var custom = g
        custom.funding = .custom(start: inputs.start, monthly: inputs.monthly, annualReturn: 0)
        custom.morePotIDs = nil
        let viaPots = d.analyze(g, current: oct2026, today: now)
        let viaCustom = d.analyze(custom, current: oct2026, today: now)
        XCTAssertEqual(viaPots.monthsToGoal, viaCustom.monthsToGoal)
        XCTAssertEqual(viaPots.progress, viaCustom.progress, accuracy: 0.000_001)
        XCTAssertEqual(viaPots.requiredMonthlyForDeadline, viaCustom.requiredMonthlyForDeadline)
    }

    func testAGoalWithOnePotIsExactlyWhatItWas() throws {
        let (d, a, _, _) = fixture()
        var one = LifeGoal(name: "Een", kind: .vacation)
        one.targetAmount = 3_000
        one.inflationAdjusted = false
        one.setFundingPots([a.id])
        var direct = one
        direct.funding = .pot(a.id)
        direct.morePotIDs = nil
        XCTAssertEqual(one, direct)
        let encoder = FinanceStorage.makeFileEncoder()
        XCTAssertEqual(try encoder.encode(one), try encoder.encode(direct))
        XCTAssertFalse(String(decoding: try encoder.encode(one), as: UTF8.self).contains("morePotIDs"))
        let inputs = d.goalInputs(for: one, current: oct2026, today: now)
        XCTAssertEqual(inputs.start, d.potBalanceNow(a.id, current: oct2026, today: now))
        XCTAssertEqual(inputs.monthly, d.estimatedAllocation(a.id, in: oct2026))
        XCTAssertEqual(inputs.sourceName, "Vakantie")
    }

    func testAnOlderAppReadsAMultiPotGoalAsAGoalWithTheFirstPot() throws {
        let (_, a, b, g) = fixture()
        let encoder = FinanceStorage.makeFileEncoder()
        let text = String(decoding: try encoder.encode(g), as: UTF8.self)
        XCTAssertTrue(text.contains("\"funding\":{\"pot\":{\"_0\":\"\(a.id.uuidString)\"}}"))
        XCTAssertTrue(text.contains("\"morePotIDs\":[\"\(b.id.uuidString)\"]"))
        // Een oudere versie kent de sleutel niet: zonder hem is het een doel met één pot.
        let stripped = text.replacingOccurrences(of: ",\"morePotIDs\":[\"\(b.id.uuidString)\"]", with: "")
        XCTAssertFalse(stripped.contains("morePotIDs"))
        let old = try FinanceStorage.makeDecoder().decode(LifeGoal.self, from: Data(stripped.utf8))
        XCTAssertEqual(old.fundingPotIDs, [a.id])
        let new = try FinanceStorage.makeDecoder().decode(LifeGoal.self, from: Data(text.utf8))
        XCTAssertEqual(new, g)
        XCTAssertEqual(new.fundingPotIDs, [a.id, b.id])
    }

    func testDeletingAPotLeavesTheRestOfTheGoal() {
        var (d, a, b, g) = fixture()
        var first = d
        first.deletePot(b.id)
        XCTAssertEqual(first.goal(g.id)?.fundingPotIDs, [a.id])
        XCTAssertNil(first.goal(g.id)?.morePotIDs)
        XCTAssertEqual(first.goal(g.id)?.funding, .pot(a.id))
        var second = d
        second.deletePot(a.id)
        XCTAssertEqual(second.goal(g.id)?.fundingPotIDs, [b.id])
        XCTAssertEqual(second.goal(g.id)?.funding, .pot(b.id))
        d.deletePot(a.id)
        d.deletePot(b.id)
        XCTAssertEqual(d.goal(g.id)?.funding, .portfolio)
        XCTAssertNil(d.goal(g.id)?.morePotIDs)
    }

    func testAPotCanServeSeveralGoals() {
        var (d, a, _, g) = fixture()
        var other = LifeGoal(name: "Auto", kind: .custom)
        other.targetAmount = 9_000
        other.setFundingPots([a.id])
        d.addGoal(other)
        XCTAssertEqual(d.goals(usingPot: a.id).map { $0.name }, ["Japan", "Auto"])
        XCTAssertEqual(d.goals(usingPot: UUID()).count, 0)
        _ = g
    }

    func testSetFundingPotsNormalises() {
        var g = LifeGoal(name: "X", kind: .custom)
        let a = UUID(), b = UUID()
        g.setFundingPots([a, b, a])
        XCTAssertEqual(g.fundingPotIDs, [a, b])
        g.setFundingPots([])
        XCTAssertEqual(g.funding, .portfolio)
        XCTAssertEqual(g.fundingPotIDs, [])
        g.funding = .custom(start: 1, monthly: 2, annualReturn: 0)
        g.morePotIDs = [a]
        XCTAssertEqual(g.fundingPotIDs, [], "andere financiering: de extra potten tellen niet")
    }

    func testAcceleratorsDoNotOfferThePotsOfTheGoal() {
        var (d, a, b, g) = fixture()
        // Beide potten staan ver boven hun eigen doel, een derde pot ook; alleen de derde wordt aangeboden.
        d.pots[0].goalAmount = 100
        d.pots[1].goalAmount = 100
        var c = Pot(name: "Los", goalAmount: 100, monthlyContribution: 0, startMonth: aug2026)
        c.symbol = "banknote"
        d.addPot(c, openingBalance: 900, now: day(aug2026, 2))
        let ids = d.accelerators(for: g, current: oct2026, today: now).map { $0.id }
        XCTAssertFalse(ids.contains("pot-\(a.id.uuidString)"))
        XCTAssertFalse(ids.contains("pot-\(b.id.uuidString)"))
        XCTAssertTrue(ids.contains("pot-\(c.id.uuidString)"))
    }

    func testRestoringAnAcceleratorPutsTheMorePotsBack() throws {
        var (d, _, b, g) = fixture()
        // Een versneller die het doel aanpast bewaart het doel zoals het was (`before.goals`); herstellen zet de financiering terug,
        // ook de extra potten. Hier staat zo'n bewaard doel klaar terwijl het doel intussen zonder tweede pot is.
        var backup = AcceleratorBackup()
        backup.goals = [g]
        d.appliedAccelerators = [AppliedAccelerator(acceleratorID: "free", goalID: g.id, title: "Meer inleg", date: now,
                                                    summary: ["Inleg omhoog"], before: backup)]
        let record = d.appliedAccelerators[0]
        d.goals[0].setFundingPots([g.fundingPotIDs[0]])
        XCTAssertNil(d.goal(g.id)?.morePotIDs)
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertEqual(d.goal(g.id)?.morePotIDs, [b.id])
        XCTAssertEqual(d.goal(g.id)?.funding, g.funding)
        XCTAssertEqual(d.goal(g.id)?.fundingPotIDs, g.fundingPotIDs)
    }

    func testApplyingAnAcceleratorLeavesTheGoalWithItsPots() throws {
        var (d, a, b, g) = fixture()
        d.materialize(upTo: oct2026)
        let original = d
        let acc = try XCTUnwrap(d.accelerators(for: g, current: oct2026, today: now).first { $0.id == "free" })
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: now))
        // Een versneller werkt op de eerste pot: het doel zelf houdt al zijn potten.
        XCTAssertEqual(d.goal(g.id)?.fundingPotIDs, [a.id, b.id])
        XCTAssertGreaterThan(d.pot(a.id)?.monthlyContribution ?? 0, 300)
        XCTAssertEqual(d.pot(b.id), original.pot(b.id), "de tweede pot is niet aangeraakt")
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertEqual(d, original)
    }

    func testAGoalWithOnePotRoundTripsByteForByte() throws {
        let (_, a, _, _) = fixture()
        var one = LifeGoal(name: "Een", kind: .vacation)
        one.targetAmount = 3_000
        one.setFundingPots([a.id])
        let encoder = FinanceStorage.makeFileEncoder()
        let first = try encoder.encode(one)
        let back = try FinanceStorage.makeDecoder().decode(LifeGoal.self, from: first)
        XCTAssertEqual(back, one)
        XCTAssertEqual(try encoder.encode(back), first)
        XCTAssertNil(back.morePotIDs)
        // Een bestand van een oudere versie (zonder de sleutel) en een met een lege lijst lezen allebei als één pot.
        let text = String(decoding: first, as: UTF8.self)
        let withEmpty = text.replacingOccurrences(of: "\"name\"", with: "\"morePotIDs\":[],\"name\"")
        XCTAssertEqual(try FinanceStorage.makeDecoder().decode(LifeGoal.self, from: Data(withEmpty.utf8)).fundingPotIDs, [a.id])
    }

    func testTheFirstPotComesFirstAndDoublesAreIgnored() {
        var g = LifeGoal(name: "X", kind: .custom)
        let a = UUID(), b = UUID(), c = UUID()
        g.funding = .pot(a)
        g.morePotIDs = [b, a, c, b]
        XCTAssertEqual(g.fundingPotIDs, [a, b, c])
        XCTAssertTrue(g.isFunded(by: c))
        XCTAssertFalse(g.isFunded(by: UUID()))
        g.setFundingPots([c, a])
        XCTAssertEqual(g.funding, .pot(c))
        XCTAssertEqual(g.morePotIDs, [a])
    }

    func testAPotThatNoLongerExistsDoesNotCount() {
        var (d, a, b, g) = fixture()
        // Staat een pot nog in het doel maar bestaat hij niet meer (een bestand van een ander apparaat), dan telt hij niet mee.
        d.pots.removeAll { $0.id == b.id }
        let inputs = d.goalInputs(for: g, current: oct2026, today: now)
        XCTAssertEqual(inputs.start, d.potBalanceNow(a.id, current: oct2026, today: now))
        XCTAssertEqual(inputs.monthly, d.estimatedAllocation(a.id, in: oct2026))
        XCTAssertEqual(inputs.sourceName, "Vakantie")
        d.pots.removeAll()
        let none = d.goalInputs(for: g, current: oct2026, today: now)
        XCTAssertEqual(none.start, 0)
        XCTAssertEqual(none.monthly, 0)
        XCTAssertEqual(none.sourceName, "Spaarpot")
    }

    func testAPotUsedByTwoGoalsCountsFullyForEach() {
        var (d, a, _, g) = fixture()
        var other = LifeGoal(name: "Auto", kind: .custom)
        other.targetAmount = 9_000
        other.inflationAdjusted = false
        other.setFundingPots([a.id])
        d.addGoal(other)
        let both = d.goalInputs(for: g, current: oct2026, today: now)
        let single = d.goalInputs(for: other, current: oct2026, today: now)
        XCTAssertEqual(single.start, d.potBalanceNow(a.id, current: oct2026, today: now), "het hele saldo, geen verdeling")
        XCTAssertGreaterThan(both.start, single.start)
        XCTAssertEqual(d.goals(usingPot: a.id).count, 2)
    }
}
