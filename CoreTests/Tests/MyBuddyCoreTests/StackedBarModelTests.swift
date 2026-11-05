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

    // MARK: Het deel dat aan de bankrekening is toegewezen (docs/work/plan2.md D3.7)

    /// Een maand met 3.000 inkomen, 1.000 uitgaven en 500 gespaard: 1.500 blijft op de rekening, `toBank` daarvan is toegewezen.
    private func bankSummary(_ month: YearMonth, toBank: Double, projected: Bool, saved: Double = 500) -> MonthSummary {
        MonthSummary(month: month, income: 3_000, expenses: 1_000, fromPots: 0, saved: saved, invested: 0,
                     isProjected: projected, toBank: toBank)
    }

    func testAnExpectedMonthWithABankShareSaysWhatIsStillToDistributeAndWhatIsAssigned() {
        let model = StackedBarModel.months([bankSummary(oct2026, toBank: 300, projected: true)], startMonth: aug2026)
        let entry = model.entries[0]
        XCTAssertEqual(entry.toBank, 300, accuracy: 0.001)
        XCTAssertEqual(entry.free, 1_500, accuracy: 0.001, "de staaf sluit op het inkomen: het bankdeel zit in 'over'")
        XCTAssertEqual(entry.unassigned, 1_200, accuracy: 0.001)
        XCTAssertTrue(entry.text.contains("(verwacht)"), entry.text)
        XCTAssertTrue(entry.text.contains("nog te verdelen 1.200 euro"), entry.text)
        XCTAssertTrue(entry.text.contains("aan je bankrekening toegewezen 300 euro"), entry.text)
        XCTAssertFalse(entry.text.contains("overgehouden"), entry.text)
        // De stapel van de staaf blijft precies het inkomen.
        let stack = model.bars.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(stack, 3_000, accuracy: 0.001)
    }

    func testTheDetailRowsOfAnExpectedMonthWithABankShare() {
        let entry = StackedBarModel.months([bankSummary(oct2026, toBank: 300, projected: true)], startMonth: aug2026).entries[0]
        XCTAssertEqual(entry.detailRows.map { $0.label },
                       ["Inkomen", "Uitgaven", "Gespaard", "Belegd", "Aan bankrekening toegewezen", "Nog te verdelen"])
        XCTAssertEqual(entry.detailRows.map { $0.value }, [3_000, 1_000, 500, 0, 300, 1_200])
        XCTAssertEqual(Set(entry.detailRows.map { $0.id }).count, entry.detailRows.count, "elke rij heeft een eigen id")
    }

    func testTheCurrentMonthWithABankShareSaysTheSameWhenTheCallerNamesIt() {
        let summaries = [bankSummary(sep2026, toBank: 300, projected: false), bankSummary(oct2026, toBank: 300, projected: false)]
        let model = StackedBarModel.months(summaries, startMonth: aug2026, current: oct2026)
        let past = model.entries[0], current = model.entries[1]
        XCTAssertEqual(current.toBank, 300, accuracy: 0.001)
        XCTAssertTrue(current.text.contains("nog te verdelen 1.200 euro"), current.text)
        XCTAssertTrue(current.text.contains("aan je bankrekening toegewezen 300 euro"), current.text)
        XCTAssertFalse(current.text.contains("(verwacht)"), "de huidige maand is niet verwacht: \(current.text)")
        XCTAssertEqual(current.detailRows.suffix(2).map { $0.label }, ["Aan bankrekening toegewezen", "Nog te verdelen"])
        XCTAssertEqual(current.detailRows.last?.value ?? 0, 1_200, accuracy: 0.001)
        // Een maand die voorbij is zegt niets over het bankdeel, ook met `current`.
        XCTAssertEqual(past.toBank, 0)
        XCTAssertTrue(past.text.contains("overgehouden 1.500 euro"), past.text)
        XCTAssertFalse(past.text.contains("bankrekening"), past.text)
        XCTAssertEqual(past.detailRows.last?.label, "Overgehouden")
        XCTAssertEqual(past.detailRows.last?.value ?? 0, 1_500, accuracy: 0.001)
    }

    func testWithoutTheCurrentMonthOrWithoutABankShareNothingChanges() {
        // Zonder `current` weet het model niet welke maand de huidige is: alleen een verwachte maand noemt het bankdeel.
        let noCurrent = StackedBarModel.months([bankSummary(oct2026, toBank: 300, projected: false)], startMonth: aug2026).entries[0]
        XCTAssertEqual(noCurrent.toBank, 0)
        XCTAssertTrue(noCurrent.text.contains("overgehouden 1.500 euro"), noCurrent.text)
        XCTAssertEqual(noCurrent.detailRows.last?.label, "Overgehouden")
        // De huidige maand zonder bankdeel blijft "overgehouden", zoals altijd.
        let plain = StackedBarModel.months([bankSummary(oct2026, toBank: 0, projected: false)], startMonth: aug2026, current: oct2026).entries[0]
        XCTAssertTrue(plain.text.contains("overgehouden 1.500 euro"), plain.text)
        XCTAssertEqual(plain.detailRows.map { $0.label }, ["Inkomen", "Uitgaven", "Gespaard", "Belegd", "Overgehouden"])
        // Een verwachte maand zonder bankdeel zegt wat ze altijd zei.
        let future = StackedBarModel.months([bankSummary(engNov2026, toBank: 0, projected: true)], startMonth: aug2026, current: oct2026).entries[0]
        XCTAssertTrue(future.text.contains("nog te verdelen 1.500 euro"), future.text)
        XCTAssertEqual(future.detailRows.last?.label, "Nog te verdelen")
        XCTAssertEqual(future.unassigned, 1_500, accuracy: 0.001)
    }

    func testAMonthInThePastNeverMentionsTheBankShare() {
        let model = StackedBarModel.months([bankSummary(sep2026, toBank: 300, projected: false)], startMonth: aug2026, current: oct2026)
        let entry = model.entries[0]
        XCTAssertEqual(entry.toBank, 0, "wat voorbij is heet Overgehouden en toont wat er op de rekening bleef")
        XCTAssertTrue(entry.text.contains("overgehouden 1.500 euro"), entry.text)
        XCTAssertEqual(entry.detailRows.last?.label, "Overgehouden")
        XCTAssertEqual(entry.unassigned, 1_500, accuracy: 0.001)
    }

    func testABankShareLargerThanWhatIsLeftIsSaidSo() {
        let model = StackedBarModel.months([bankSummary(oct2026, toBank: 1_800, projected: true)], startMonth: aug2026)
        let entry = model.entries[0]
        XCTAssertEqual(entry.free, 1_500, accuracy: 0.001)
        XCTAssertEqual(entry.unassigned, -300, accuracy: 0.001)
        XCTAssertTrue(entry.text.contains("aan je bankrekening toegewezen 1.800 euro"), entry.text)
        XCTAssertTrue(entry.text.contains("300 euro meer dan er over is"), entry.text)
        XCTAssertEqual(entry.detailRows.last?.label, "Nog te verdelen")
        XCTAssertEqual(entry.detailRows.last?.value ?? 0, -300, accuracy: 0.001)
    }

    func testAShortfallStaysAShortfallWithABankShare() {
        let summary = MonthSummary(month: oct2026, income: 3_000, expenses: 3_200, fromPots: 0, saved: 100, invested: 0,
                                   isProjected: true, toBank: 200)
        let entry = StackedBarModel.months([summary], startMonth: aug2026).entries[0]
        XCTAssertEqual(entry.shortfall, 300, accuracy: 0.001)
        XCTAssertTrue(entry.text.contains("tekort 300 euro"), entry.text)
        XCTAssertEqual(entry.detailRows.last?.label, "Tekort")
        XCTAssertEqual(entry.detailRows.last?.value ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(entry.unassigned, -500, accuracy: 0.001, "het tekort plus het bankdeel dat niet past")
    }

    func testTheModelFollowsTheEngineForCurrentAndExpectedMonthsWithABankShare() {
        var d = makeBaseData()
        _ = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        d.setContributionAmount(BankShare.id, amount: 300, current: oct2026)
        let summaries = d.summaries(from: sep2026, count: 4, current: oct2026)
        let model = StackedBarModel.months(summaries, startMonth: d.startMonth, current: oct2026)
        XCTAssertEqual(model.entries.map { $0.id }, ["2026-09", "2026-10", "2026-11", "2026-12"])
        for entry in model.entries {
            let month = YearMonth(key: entry.id) ?? oct2026
            let figures = d.monthFigures(month)
            if month < oct2026 {
                XCTAssertEqual(entry.toBank, 0, entry.id)
                XCTAssertEqual(entry.free, CentsMath.value(max(0, figures.remaining)), accuracy: 0.001, entry.id)
            } else {
                XCTAssertEqual(entry.toBank, 300, accuracy: 0.001, entry.id)
                XCTAssertEqual(entry.unassigned, d.unassigned(in: month), accuracy: 0.001, "hetzelfde getal als op Verdelen: \(entry.id)")
                XCTAssertEqual(entry.unassigned, CentsMath.value(MoneyLabels.left(figures, of: month, current: oct2026)), accuracy: 0.001, entry.id)
                XCTAssertEqual(entry.detailRows.last?.value ?? 0, entry.unassigned, accuracy: 0.001, entry.id)
            }
            XCTAssertEqual(entry.shortfall, 0, entry.id)
            XCTAssertEqual(entry.expenses + entry.saved + entry.invested + entry.free, entry.income, accuracy: 0.001,
                           "de staaf sluit op het inkomen: \(entry.id)")
        }
    }
}
