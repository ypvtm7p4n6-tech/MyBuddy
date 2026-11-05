import XCTest
import Foundation
@testable import MyBuddyCore

/// D1 (docs/work/plan2.md par. 2.1): een percentage plus een extra bedrag. Het bedrag van de maand is het percentage van het inkomen
/// plus het extra bedrag, elk op hele centen, in ÉÉN functie (`AllocationMath.cents(of:bases:)`).
final class ExtraAmountTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)

    private func dataWithPot(monthly: Double = 200, transferDay: Int? = 25) -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Vakantie", monthlyContribution: monthly, startMonth: oct2026)
        pot.transferDay = transferDay
        d.addPot(pot, openingBalance: 0, now: day(oct2026, 1))
        return (d, pot)
    }

    private func isOverAllocated(_ warning: AllocationWarning) -> Bool {
        if case .overAllocated = warning { return true }
        return false
    }

    private func isPercentagesOver100(_ warning: AllocationWarning) -> Bool {
        if case .percentagesOver100 = warning { return true }
        return false
    }

    // MARK: Het bedrag

    func testPercentagePlusExtraIsOneAmount() {
        var (d, pot) = dataWithPot()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 50, current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 35_000)
        XCTAssertEqual(d.allocation(pot.id, in: nov), 350)
        XCTAssertEqual(d.monthFigures(nov).saved, 35_000)
        XCTAssertEqual(d.effectiveAllocation(pot.id, in: nov).amount, 350)
        XCTAssertEqual(d.defaultAllocationRule(pot.id, in: nov)?.summary, "10% van je salaris plus " + Fmt.euro(50))
    }

    func testPercentageZeroWithExtraWorksAsAFixedAmount() {
        var (d, pot) = dataWithPot()
        d.setContributionPercent(pot.id, percent: 0, basis: .salary, extra: 75, current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 7_500)
        XCTAssertEqual(d.pots[0].contributionMode, .percentage, "de modus blijft Percentage")
    }

    func testExtraWithoutIncomeKeepsOnlyTheExtra() {
        var d = FinanceData(startMonth: oct2026)
        var pot = Pot(name: "Spaar", monthlyContribution: 0, startMonth: oct2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = 20
        pot.contributionExtra = 40
        d.addPot(pot)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 4_000)
    }

    func testExtraAlsoWorksForAMonthOverride() {
        var (d, pot) = dataWithPot()
        d.setAllocationPercent(pot.id, in: nov, percent: 5, basis: .salary, extra: 25)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 17_500)
        // Alleen het percentage wijzigen laat het extra bedrag van de maand staan.
        AllocationEdit.setPercent(&d, id: pot.id, month: nov, percent: 6)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 20_500)
        AllocationEdit.setExtra(&d, id: pot.id, month: nov, extra: 0)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 18_000)
        XCTAssertTrue(d.effectiveAllocation(pot.id, in: nov).isOverride)
    }

    func testExtraSurvivesMakeStandardAndModeSwitch() {
        var (d, pot) = dataWithPot()
        d.setAllocationPercent(pot.id, in: nov, percent: 5, basis: .salary, extra: 25)
        AllocationEdit.makeStandard(&d, id: pot.id, month: nov, current: oct2026)
        XCTAssertEqual(d.pots[0].contributionExtra, 25)
        XCTAssertEqual(d.pots[0].contributionPercent, 5)
        // Naar een vast bedrag: het bedrag van nu blijft staan (percentage plus extra).
        AllocationEdit.setMode(&d, id: pot.id, month: nov, to: .fixed)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 17_500)
    }

    func testNonsenseExtraIsIgnored() {
        var (d, pot) = dataWithPot()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: -40, current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 30_000)
        d.pots[0].contributionExtra = .nan
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 30_000)
        d.pots[0].contributionExtra = .infinity
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 30_000)
        XCTAssertEqual(AllocationMath.extraCents(0.004), 0, "minder dan een halve cent telt niet")
        XCTAssertEqual(AllocationMath.extraCents(12.345), 1_235, "half omhoog op hele centen")
        XCTAssertEqual(AllocationMath.cleanExtra(12.345), 12.35)
    }

    func testOldFilesEncodeByteIdenticalWithoutAnExtra() throws {
        let rule = PercentRule(percent: 10, basis: .salary)
        let encoder = FinanceStorage.makeFileEncoder()
        XCTAssertEqual(String(decoding: try encoder.encode(rule), as: UTF8.self), "{\"basis\":\"salary\",\"percent\":10}")
        let withExtra = PercentRule(percent: 10, basis: .salary, extra: 12.5)
        XCTAssertEqual(String(decoding: try encoder.encode(withExtra), as: UTF8.self), "{\"basis\":\"salary\",\"extra\":12.5,\"percent\":10}")
        let back = try FinanceStorage.makeDecoder().decode(PercentRule.self, from: try encoder.encode(withExtra))
        XCTAssertEqual(back, withExtra)
        // Een onleesbaar extra bedrag wordt genegeerd.
        let broken = Data("{\"basis\":\"salary\",\"extra\":\"veel\",\"percent\":10}".utf8)
        XCTAssertEqual(try FinanceStorage.makeDecoder().decode(PercentRule.self, from: broken).extra, 0)
    }

    // MARK: Randgevallen en samenspel

    func testTheExtraAmountCountsInOverAllocatedButNotInThePercentTotal() {
        var (d, pot) = dataWithPot()
        // 10% van 3.000 is 300; met 3.000 extra wordt er 3.300 verdeeld terwijl er 3.000 te verdelen is.
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 3_000, current: oct2026)
        let f = d.monthFigures(oct2026)
        XCTAssertEqual(f.saved, 330_000)
        XCTAssertEqual(f.overAllocated, 30_000, "het extra bedrag zit in wat er is verdeeld")
        let warnings = d.allocationWarnings(in: oct2026)
        XCTAssertTrue(warnings.contains { isOverAllocated($0) })
        XCTAssertFalse(warnings.contains { isPercentagesOver100($0) }, "de waarschuwing voor percentages telt alleen percentages")
        XCTAssertEqual(d.percentTotal(in: oct2026), 10)
        // Een percentage boven 100% met extra bedrag blijft toegestaan.
        d.setContributionPercent(pot.id, percent: 100, basis: .salary, extra: 10, current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 301_000)
    }

    func testEstimatesOfAnAverageMonthIncludeTheExtraAmount() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 1_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 9))
        var pot = Pot(name: "Spaar", monthlyContribution: 0, startMonth: oct2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.addPot(pot)
        let plain = d.estimatedAllocation(pot.id, in: nov)
        XCTAssertGreaterThan(plain, 0)
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 25, current: oct2026)
        let withExtra = d.estimatedAllocation(pot.id, in: nov)
        XCTAssertEqual(CentsMath.int(withExtra) - CentsMath.int(plain), 2_500, "een gemiddelde maand telt het extra bedrag mee")
        XCTAssertEqual(d.estimatedDefaultAllocation(pot.id, in: nov), withExtra, accuracy: 1e-9)
        let rule = PercentRule(percent: 10, basis: .salary, extra: 25)
        XCTAssertEqual(d.estimatedAmount(of: .percent(rule), in: nov), withExtra, accuracy: 1e-9)
        // Het bedrag van een maand met één uitbetaling verschilt van de gemiddelde maand, het extra bedrag niet.
        XCTAssertEqual(CentsMath.int(d.percentAmount(10, of: .salary, extra: 25, in: nov)) - CentsMath.int(d.percentAmount(10, of: .salary, in: nov)), 2_500)
    }

    func testAnAcceleratorThatRaisesAPercentageTurnsPercentageAndExtraIntoOneFixedAmount() throws {
        var (d, pot) = dataWithPot()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 25, current: oct2026)
        var goal = LifeGoal(name: "Japan", kind: .vacation)
        goal.targetAmount = 60_000
        goal.inflationAdjusted = false
        goal.funding = .pot(pot.id)
        d.addGoal(goal)
        d.materialize(upTo: oct2026)
        let original = d
        let now = day(oct2026, 12)
        let acc = try XCTUnwrap(d.accelerators(for: goal, current: oct2026, today: now).first { $0.id == "free" })
        let record = try XCTUnwrap(d.apply(acc, for: goal, current: oct2026, now: now))
        let changed = try XCTUnwrap(d.pot(pot.id))
        XCTAssertEqual(changed.contributionMode, .fixed)
        XCTAssertEqual(changed.monthlyContribution, 325 + acc.change.extraMonthly, accuracy: 1e-9, "10% van 3000 plus 25 plus de verhoging")
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertEqual(d, original)
        XCTAssertEqual(d.pot(pot.id)?.contributionExtra, 25, "herstellen zet het extra bedrag terug")
    }

    func testTheExtraAmountInAStartMonthIsNotReducedProportionally() {
        // Salarisdag op de 5e, startdatum de 12e: het salaris van oktober telt niet mee (het zit in je beginsaldo), de inleg op de 20e
        // wel: het percentage rekent over het inkomen dat meetelt (0), het extra bedrag blijft helemaal staan.
        var (d, pot) = dataWithPot(monthly: 0, transferDay: 20)
        d.salary.payDay = 5
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 40, current: oct2026)
        d.setStart(CalendarDay(year: 2026, month: 10, day: 12))
        XCTAssertEqual(d.incomeBases(in: oct2026).salary, 0)
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 4_000)
        XCTAssertEqual(d.monthFigures(oct2026).saved, 4_000)
        // Een gewone maand: het hele salaris en het hele extra bedrag.
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 34_000)
        // Valt de overschrijfdag vóór de startdag, dan telt de hele inleg niet mee, ook het extra bedrag niet.
        d.pots[0].transferDay = 8
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 0)
        XCTAssertTrue(d.monthLedger(oct2026).allReconciles)
    }

    func testThePercentageSummaryNamesTheExtraAmount() {
        XCTAssertEqual(AllocationRule.percent(PercentRule(percent: 3.5, basis: .allIncome)).summary, "3,5% van al je inkomsten")
        XCTAssertEqual(AllocationRule.percent(PercentRule(percent: 3.5, basis: .allIncome, extra: 25)).summary,
                       "3,5% van al je inkomsten plus " + Fmt.euro(25))
        // Een extra bedrag onder een halve cent zegt niets.
        XCTAssertEqual(AllocationRule.percent(PercentRule(percent: 10, basis: .salary, extra: 0.004)).summary, "10% van je salaris")
    }

    func testAFutureMonthThatStillHasTheOldStandardFollowsTheNewExtraAmount() {
        var (d, pot) = dataWithPot()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 25, current: oct2026)
        // Een maand na de lopende maand die al is vastgelegd met de oude standaard krijgt de nieuwe standaard, ook als alleen het extra
        // bedrag verschilt; een eigen afwijking van de gebruiker blijft.
        d.materialize(upTo: engJan2027)
        d.setAllocationPercent(pot.id, in: engJan2027, percent: 10, basis: .salary, extra: 99)
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 60, current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 36_000, "vastgelegd met de oude standaard: volgt de nieuwe")
        XCTAssertEqual(d.allocationCents(pot.id, in: engJan2027), 39_900, "een eigen afwijking blijft")
    }

    func testChangingTheExtraAmountOfTheStandardGoesAlongWithTheCurrentMonth() {
        var (d, pot) = dataWithPot()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 25, current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 32_500)
        // Alleen het extra bedrag verandert: de lopende maand volgt (de regel is anders), eerdere maanden niet.
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 60, current: nov)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 36_000)
        XCTAssertEqual(d.allocationCents(pot.id, in: engDec2026), 36_000)
        XCTAssertFalse(d.effectiveAllocation(pot.id, in: nov).isOverride)
    }
}
