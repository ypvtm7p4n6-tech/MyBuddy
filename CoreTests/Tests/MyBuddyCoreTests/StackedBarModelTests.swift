import XCTest
@testable import MyBuddyCore

/// "Waar gaat je geld heen": maanden vóór de start zijn er niet, een tekort steekt boven de inkomenslijn uit, en elke maand heeft
/// zijn zin voor VoiceOver (met "(verwacht)" voor een toekomstige maand).
final class StackedBarModelTests: XCTestCase {
    private func summary(_ month: YearMonth, income: Double, expenses: Double, saved: Double = 0, invested: Double = 0,
                         fromPots: Double = 0, projected: Bool = false) -> MonthSummary {
        MonthSummary(month: month, income: income, expenses: expenses, fromPots: fromPots, saved: saved, invested: invested,
                     isProjected: projected)
    }

    func testMonthsBeforeTheStartAreLeftOut() {
        let list = [summary(YearMonth(year: 2026, month: 6), income: 0, expenses: 0),
                    summary(YearMonth(year: 2026, month: 7), income: 0, expenses: 0),
                    summary(aug2026, income: 3_000, expenses: 1_000, saved: 500, invested: 200),
                    summary(sep2026, income: 3_000, expenses: 1_000, saved: 500, invested: 200)]
        let model = StackedBarModel.months(list, startMonth: aug2026)
        XCTAssertNil(model.empty)
        XCTAssertEqual(model.entries.map { $0.id }, ["2026-08", "2026-09"])
        XCTAssertEqual(Set(model.bars.map { $0.monthID }), ["2026-08", "2026-09"])
        XCTAssertEqual(model.incomeMarks.count, 2)
    }

    func testAShortfallStaysAboveTheIncomeLineAndIsNamedInTheText() {
        let model = StackedBarModel.months([summary(aug2026, income: 3_000, expenses: 3_700, saved: 200, invested: 200)], startMonth: aug2026)
        let stack = model.bars.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(stack, 4_100, accuracy: 0.001)
        XCTAssertGreaterThan(stack, model.incomeMarks[0].income)
        XCTAssertFalse(model.bars.contains { $0.kind == .free })
        XCTAssertEqual(model.entries[0].shortfall, 1_100, accuracy: 0.001)
        XCTAssertEqual(model.entries[0].free, 0)
        XCTAssertTrue(model.entries[0].text.contains("tekort 1.100 euro"), model.entries[0].text)
        XCTAssertTrue(model.summary.contains("In 1 maand is er een tekort."), model.summary)
        XCTAssertEqual(model.kinds, [.expenses, .saved, .invested])
    }

    func testWhatIsLeftIsGivenAsLeftOrStillToDistribute() {
        let past = StackedBarModel.months([summary(aug2026, income: 3_000, expenses: 1_000, saved: 500)], startMonth: aug2026)
        XCTAssertEqual(past.entries[0].free, 1_500, accuracy: 0.001)
        XCTAssertTrue(past.entries[0].text.contains("overgehouden 1.500 euro"), past.entries[0].text)
        XCTAssertFalse(past.entries[0].text.contains("(verwacht)"))
        let future = StackedBarModel.months([summary(oct2026, income: 3_000, expenses: 1_000, saved: 500, projected: true)], startMonth: aug2026)
        XCTAssertTrue(future.entries[0].text.contains("(verwacht)"))
        XCTAssertTrue(future.entries[0].text.contains("nog te verdelen 1.500 euro"), future.entries[0].text)
        XCTAssertTrue(future.bars.allSatisfy { $0.isProjected })
        // De legenda gebruikt de vaste namen uit de termenlijst.
        XCTAssertEqual(FlowKind.allCases.map { $0.title }, ["Uitgaven", "Gespaard", "Belegd", "Overgehouden"])
    }

    func testOnlyTheShareOfTheExpensesFromYourIncomeIsDrawn() {
        // Wat uit een spaarpot wordt betaald staat al in de pot en maakt de balk niet hoger dan je inkomen.
        let model = StackedBarModel.months([summary(aug2026, income: 3_000, expenses: 1_200, saved: 300, fromPots: 200)], startMonth: aug2026)
        XCTAssertEqual(model.entries[0].expenses, 1_000, accuracy: 0.001)
        XCTAssertEqual(model.bars.first { $0.kind == .expenses }?.amount ?? 0, 1_000, accuracy: 0.001)
    }

    func testNoDataIsAnEmptyStateWithAnAction() {
        let list = [summary(aug2026, income: 0, expenses: 0), summary(sep2026, income: 0, expenses: 0)]
        let model = StackedBarModel.months(list, startMonth: aug2026)
        XCTAssertEqual(model.empty?.action, .openSalary)
        XCTAssertEqual(model.empty?.actionTitle, "Salaris instellen")
        XCTAssertTrue(model.bars.isEmpty)
        XCTAssertFalse(model.summary.isEmpty)
        // Alles vóór de start: ook leeg.
        let before = StackedBarModel.months([summary(YearMonth(year: 2026, month: 6), income: 3_000, expenses: 100)], startMonth: aug2026)
        XCTAssertNotNil(before.empty)
        XCTAssertNotNil(StackedBarModel.months([], startMonth: aug2026).empty)
    }

    func testTicksFollowTheCalendarAndEveryMonthKeepsItsID() {
        let months = YearMonth(year: 2026, month: 1).range(count: 12).map { summary($0, income: 3_000, expenses: 1_000) }
        let model = StackedBarModel.months(months, startMonth: YearMonth(year: 2026, month: 1))
        XCTAssertEqual(model.entries.count, 12)
        XCTAssertEqual(Set(model.entries.map { $0.id }).count, 12)
        // Twaalf maanden: om de twee maanden een label (januari, maart, mei, ...).
        XCTAssertEqual(model.tickIDs, ["2026-01", "2026-03", "2026-05", "2026-07", "2026-09", "2026-11"])
        XCTAssertEqual(model.entries[0].label, "jan '26")
        XCTAssertEqual(model.entries[1].label, "feb")
        let few = StackedBarModel.months(Array(months.prefix(3)), startMonth: YearMonth(year: 2026, month: 1))
        XCTAssertEqual(few.tickIDs.count, 3)
    }

    func testRealSummariesFromTheEngineGiveAConsistentModel() {
        var d = makeBaseData()
        _ = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        let model = StackedBarModel.months(d.summaries(from: YearMonth(year: 2026, month: 5), count: 8, current: oct2026), startMonth: d.startMonth)
        XCTAssertNil(model.empty)
        // Mei t/m juli liggen vóór de startmaand (augustus).
        XCTAssertEqual(model.entries.count, 5)
        XCTAssertEqual(model.entries.map { $0.isProjected }, [false, false, false, true, true])
        for entry in model.entries { XCTAssertFalse(entry.text.isEmpty) }
        XCTAssertTrue(model.bars.allSatisfy { $0.amount > 0 && $0.amount.isFinite })
        XCTAssertEqual(Set(model.bars.map { $0.id }).count, model.bars.count)
    }
}
