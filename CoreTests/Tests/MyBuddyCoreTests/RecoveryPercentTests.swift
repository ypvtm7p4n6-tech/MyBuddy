import XCTest
import Foundation
@testable import MyBuddyCore

// Herstelronde: percentage-inleg.
//
// - De waarschuwing "samen meer dan 100%" telt bij een mengeling van beide grondslagen wat de percentages van het inkomen
//   werkelijk vragen (geen valse waarschuwing, en geen gemiste).
// - Een percentage dat geen getal is (NaN, oneindig) laat opslaan, back-up en synchroniseren niet falen.
// - Een onbekende inlegwijze of grondslag (nieuwere app) laat het bestand niet falen.
// - Vóór de startmaand van de gegevens is de verdeling van een pot nul, ook als de pot zelf eerder begon.

final class RecoveryPercentTests: XCTestCase {
    private func data(salary: Double = 1_000, bonus: Double = 0) -> FinanceData {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: salary, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        if bonus > 0 {
            var plan = MonthPlan()
            plan.extraIncome = [MoneyLine(name: "Bonus", amount: bonus, isRecurring: true, kind: .fixed)]
            d.months[aug2026.key] = plan
        }
        return d
    }

    private func addPercentPot(_ d: inout FinanceData, _ name: String, percent: Double, basis: IncomeBasis) {
        var pot = Pot(name: name, monthlyContribution: 0, startMonth: aug2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = percent
        pot.contributionBasis = basis
        d.addPot(pot)
    }

    private func overHundred(_ d: FinanceData, _ month: YearMonth) -> Double? {
        for warning in d.allocationWarnings(in: month) {
            if case .percentagesOver100(let total) = warning { return total }
        }
        return nil
    }

    // MARK: Waarschuwing bij een mengeling van grondslagen

    /// Salaris 1000 en bonus 9000: 60% van het salaris (600) en 50% van alle inkomsten (5000) is samen 56% van 10.000. Geen
    /// waarschuwing, ook al zijn de ingestelde percentages samen 110.
    func testMixedBasesWithBigBonusAreNotOverOneHundredPercent() {
        var d = data(salary: 1_000, bonus: 9_000)
        addPercentPot(&d, "A", percent: 60, basis: .salary)
        addPercentPot(&d, "B", percent: 50, basis: .allIncome)
        XCTAssertEqual(d.percentTotal(in: oct2026), 110, accuracy: 1e-9)
        XCTAssertNil(overHundred(d, oct2026))
        XCTAssertEqual(d.saved(of: d.pots[0], in: oct2026) + d.saved(of: d.pots[1], in: oct2026), 5_600, accuracy: 1e-9)
    }

    /// Zonder bonus is dezelfde verdeling echt te veel: 600 + 500 van 1000 is 110%.
    func testMixedBasesWithoutBonusAreOver() {
        var d = data(salary: 1_000)
        addPercentPot(&d, "A", percent: 60, basis: .salary)
        addPercentPot(&d, "B", percent: 50, basis: .allIncome)
        XCTAssertEqual(overHundred(d, oct2026) ?? 0, 110, accuracy: 0.011)
    }

    /// 60% van alle inkomsten en 60% van het salaris: bij een bonus van 1000 op salaris 1000 vragen ze 600 + 1200 van 2000 = 90%.
    func testMixedBasesTheOtherWayAround() {
        var d = data(salary: 1_000, bonus: 1_000)
        addPercentPot(&d, "A", percent: 60, basis: .allIncome)
        addPercentPot(&d, "B", percent: 60, basis: .salary)
        XCTAssertNil(overHundred(d, oct2026))
        // En met 80% van alle inkomsten: 1600 + 600 = 2200 van 2000 = 110%.
        d.setContributionPercent(d.pots[0].id, percent: 80, basis: .allIncome, current: oct2026)
        XCTAssertEqual(overHundred(d, oct2026) ?? 0, 110, accuracy: 0.011)
    }

    /// Eén grondslag blijft zoals het was: de som van de percentages, ook met extra inkomsten.
    func testSingleBasisStillUsesTheSumOfThePercentages() {
        var d = data(salary: 1_000, bonus: 500)
        addPercentPot(&d, "A", percent: 70, basis: .salary)
        addPercentPot(&d, "B", percent: 50, basis: .salary)
        XCTAssertEqual(overHundred(d, oct2026), 120)
        var e = data(salary: 1_000, bonus: 500)
        addPercentPot(&e, "A", percent: 70, basis: .allIncome)
        addPercentPot(&e, "B", percent: 30, basis: .allIncome)
        XCTAssertNil(overHundred(e, oct2026), "precies 100% is geen overschrijding")
        e.setContributionPercent(e.pots[1].id, percent: 30.01, basis: .allIncome, current: oct2026)
        XCTAssertEqual(overHundred(e, oct2026), 100.01)
    }

    /// Zonder inkomen valt de waarschuwing terug op de som van de percentages.
    func testMixedBasesWithoutIncomeFallBackToTheSum() {
        var d = data(salary: 0)
        addPercentPot(&d, "A", percent: 60, basis: .salary)
        addPercentPot(&d, "B", percent: 60, basis: .allIncome)
        XCTAssertEqual(overHundred(d, oct2026), 120)
    }

    // MARK: Geen getal en onbekende keuzes

    func testNonFinitePercentagesDoNotBreakSaving() throws {
        var d = data(salary: 3_000)
        var pot = Pot(name: "P", monthlyContribution: 0, startMonth: aug2026)
        pot.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        pot.contributionMode = .percentage
        pot.contributionPercent = .nan
        d.addPot(pot)
        var holding = Holding(name: "H", kind: .etf, ticker: nil, units: nil, startMonth: aug2026)
        holding.contributionMode = .percentage
        holding.contributionPercent = .infinity
        d.addHolding(holding)
        // Ook een eigen percentage van een maand dat geen getal is (rechtstreeks in het plan gezet).
        var plan = MonthPlan()
        plan.percentAllocations[pot.id.uuidString] = PercentRule(percent: .nan, basis: .allIncome)
        d.months[oct2026.key] = plan
        for encoder in [FinanceStorage.makeEncoder(), FinanceStorage.makeFileEncoder()] {
            let raw = try encoder.encode(d)
            let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: raw)
            XCTAssertEqual(back.pots[0].contributionPercent, 0)
            XCTAssertEqual(back.holdings[0].contributionPercent, 0)
            XCTAssertEqual(back.months[oct2026.key]?.percentAllocations[pot.id.uuidString]?.percent, 0)
            XCTAssertEqual(back.months[oct2026.key]?.percentAllocations[pot.id.uuidString]?.basis, .allIncome)
            // Het bedrag was al 0 en blijft 0: de waarde "geen getal" rekent als 0%.
            XCTAssertEqual(back.allocation(pot.id, in: oct2026), 0)
        }
    }

    func testUnknownContributionModeAndBasisLoadAsDefaults() throws {
        var d = data(salary: 3_000)
        var pot = Pot(name: "P", monthlyContribution: 40, startMonth: aug2026)
        pot.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        pot.contributionMode = .percentage
        pot.contributionPercent = 5
        pot.contributionBasis = .allIncome
        d.addPot(pot)
        var holding = Holding(name: "H", kind: .etf, ticker: nil, units: nil, monthlyContribution: 25, startMonth: aug2026)
        holding.contributionMode = .percentage
        holding.contributionPercent = 5
        holding.contributionBasis = .allIncome
        d.addHolding(holding)
        var plan = MonthPlan()
        plan.percentAllocations[pot.id.uuidString] = PercentRule(percent: 7, basis: .allIncome)
        d.months[oct2026.key] = plan
        var text = String(decoding: try FinanceStorage.makeEncoder().encode(d), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"percentage\"", with: "\"toekomst\"")
        text = text.replacingOccurrences(of: "\"allIncome\"", with: "\"nieuweGrondslag\"")
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(text.utf8))
        XCTAssertEqual(back.pots[0].contributionMode, .fixed)
        XCTAssertEqual(back.pots[0].contributionBasis, .salary)
        XCTAssertEqual(back.pots[0].monthlyContribution, 40)
        XCTAssertEqual(back.holdings[0].contributionMode, .fixed)
        XCTAssertEqual(back.holdings[0].monthlyContribution, 25)
        XCTAssertEqual(back.months[oct2026.key]?.percentAllocations[pot.id.uuidString]?.percent, 7)
        XCTAssertEqual(back.months[oct2026.key]?.percentAllocations[pot.id.uuidString]?.basis, .salary)
        // Een bekende waarde blijft precies zoals hij was.
        let same = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: FinanceStorage.makeEncoder().encode(d))
        XCTAssertEqual(same.pots[0].contributionMode, .percentage)
        XCTAssertEqual(same.pots[0].contributionBasis, .allIncome)
    }

    // MARK: Vóór de startmaand

    /// Een pot die al in juli begon terwijl de gegevens pas in oktober beginnen: de verdeling in augustus en september is nul,
    /// precies zoals de maandcijfers en het totaal gespaard.
    func testAllocationBeforeDataStartIsZero() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var fixed = Pot(name: "Vast", monthlyContribution: 50, startMonth: YearMonth(year: 2026, month: 7))
        fixed.id = StableID.uuid("recovery-fixed")
        var percent = Pot(name: "Procent", monthlyContribution: 0, startMonth: YearMonth(year: 2026, month: 7))
        percent.contributionMode = .percentage
        percent.contributionPercent = 10
        percent.id = StableID.uuid("recovery-percent")
        d.addPot(fixed)
        d.addPot(percent)
        for month in [YearMonth(year: 2026, month: 7), YearMonth(year: 2026, month: 8), sep2026] {
            XCTAssertEqual(d.allocation(fixed.id, in: month), 0, month.key)
            XCTAssertEqual(d.allocation(percent.id, in: month), 0, month.key)
            XCTAssertEqual(d.allocationCents(fixed.id, in: month), 0)
            XCTAssertEqual(d.effectiveAllocation(percent.id, in: month).amount, 0)
            XCTAssertFalse(d.effectiveAllocation(percent.id, in: month).isOverride)
            XCTAssertEqual(d.savedTotal(in: month), 0)
            XCTAssertEqual(d.defaultAllocation(fixed.id, in: month), 0)
        }
        // Vanaf de startmaand gewoon.
        XCTAssertEqual(d.allocation(fixed.id, in: oct2026), 50)
        XCTAssertEqual(d.allocation(percent.id, in: oct2026), 300)
        XCTAssertEqual(d.savedTotal(in: oct2026), 350)
        // Een eigen verdeling vóór de start telt ook niet.
        d.months[sep2026.key] = { var p = MonthPlan(); p.allocations[fixed.id.uuidString] = 99; return p }()
        XCTAssertEqual(d.allocation(fixed.id, in: sep2026), 0)
        XCTAssertEqual(d.savedTotal(in: sep2026), 0)
    }
}

private extension FinanceData {
    /// Wat een pot in een maand spaart (hele euro's zoals `allocation`).
    func saved(of pot: Pot, in month: YearMonth) -> Double { allocation(pot.id, in: month) }
}
