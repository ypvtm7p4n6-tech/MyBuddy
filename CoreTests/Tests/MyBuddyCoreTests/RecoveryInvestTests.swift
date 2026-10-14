import XCTest
import Foundation
@testable import MyBuddyCore

// Herstelronde: beleggingen volgen een nieuwe inlegwijze (vast bedrag of percentage) ook in de lopende maand, ruimen hun
// overschrijvingen op bij verwijderen, en de waarde door de tijd blijft snel bij een inleg als percentage.

final class RecoveryInvestTests: XCTestCase {
    private func holdingData(percent: Bool = false) -> (FinanceData, Holding) {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        var h = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                        monthlyContribution: 200, startMonth: aug2026)
        if percent {
            h.contributionMode = .percentage
            h.contributionPercent = 10
            h.contributionBasis = .salary
        }
        d.addHolding(h, initialValue: 1000, now: day(aug2026, 1))
        d.materialize(upTo: oct2026)
        return (d, d.holdings[0])
    }

    /// Vast bedrag naar percentage via `updateHolding`: de lopende (vastgelegde) maand en de volgende geven hetzelfde bedrag.
    func testUpdateHoldingFixedToPercentageFollowsInCurrentMonth() {
        var (d, h) = holdingData()
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 200)
        h.contributionMode = .percentage
        h.contributionPercent = 10
        h.contributionBasis = .salary
        d.updateHolding(h, current: oct2026)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 300, "de lopende maand volgt het nieuwe percentage")
        XCTAssertEqual(d.allocation(h.id, in: YearMonth(year: 2026, month: 11)), 300)
        XCTAssertEqual(d.investedTotal(in: oct2026), 300)
        // Het verleden verandert niet.
        XCTAssertEqual(d.allocation(h.id, in: sep2026), 200)
    }

    func testUpdateHoldingPercentageToFixed() {
        var (d, h) = holdingData(percent: true)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 300)
        h.contributionMode = .fixed
        h.monthlyContribution = 50
        d.updateHolding(h, current: oct2026)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 50)
        XCTAssertEqual(d.allocation(h.id, in: YearMonth(year: 2026, month: 11)), 50)
    }

    func testUpdateHoldingPercentageChanged() {
        var (d, h) = holdingData(percent: true)
        h.contributionPercent = 20
        d.updateHolding(h, current: oct2026)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 600)
        // Ook een andere grondslag telt.
        h.contributionBasis = .allIncome
        d.updateHolding(h, current: oct2026)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 600)   // geen extra inkomsten: gelijk aan het salaris
    }

    /// Het verborgen vaste bedrag van een belegging op percentage wijzigen drukt het percentage niet weg.
    func testHiddenFixedAmountDoesNotOverridePercentage() {
        var (d, h) = holdingData(percent: true)
        h.monthlyContribution = 999
        d.updateHolding(h, current: oct2026)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 300)
        XCTAssertTrue(d.months[oct2026.key]?.allocations[h.id.uuidString] == nil)
    }

    /// Een wijziging die de inleg niet raakt (naam) laat een eigen bedrag van de lopende maand staan.
    func testRenameKeepsMonthOverride() {
        var (d, h) = holdingData()
        d.setAllocation(h.id, in: oct2026, amount: 123)
        h.name = "Wereld-ETF"
        d.updateHolding(h, current: oct2026)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 123)
    }

    /// Een nieuw vast bedrag werkt zoals vroeger: meteen voor de lopende maand.
    func testUpdateHoldingFixedAmountStillAppliesToCurrentMonth() {
        var (d, h) = holdingData()
        h.monthlyContribution = 250
        d.updateHolding(h, current: oct2026)
        XCTAssertEqual(d.allocation(h.id, in: oct2026), 250)
        XCTAssertEqual(d.allocation(h.id, in: sep2026), 200)
    }

    func testDeleteHoldingRemovesPercentOverrides() {
        var (d, h) = holdingData(percent: true)
        d.setAllocationPercent(h.id, in: YearMonth(year: 2026, month: 12), percent: 5)
        d.deleteHolding(h.id)
        for (key, plan) in d.months {
            XCTAssertNil(plan.percentAllocations[h.id.uuidString], "overschrijving blijft staan in \(key)")
            XCTAssertNil(plan.allocations[h.id.uuidString])
        }
        // Een belegging met hetzelfde id die later terugkomt erft geen oud percentage.
        var back = Holding(name: "Terug", kind: .etf, ticker: nil, units: nil, monthlyContribution: 25, startMonth: aug2026)
        back.id = h.id
        d.addHolding(back)
        XCTAssertEqual(d.allocation(back.id, in: YearMonth(year: 2026, month: 12)), 25)
    }

    // MARK: Waarde door de tijd bij percentage-inleg

    /// De waarde per maand klopt met een handberekening per maand, ook voor een percentage dat per maand verschilt.
    func testPortfolioSeriesWithPercentageMatchesHandCalculation() {
        var (d, h) = holdingData(percent: true)
        d.setAllocationPercent(h.id, in: YearMonth(year: 2026, month: 12), percent: 5)
        d.editPlan(YearMonth(year: 2027, month: 1)) { $0.salaryOverride = 4000 }
        h = d.holdings[0]
        let series = d.portfolioSeries(from: aug2026, count: 8, current: oct2026)
        var value = 1000.0
        var invested = 1000.0
        let rate = Growth.monthlyRate(annual: h.netReturn)
        var expected: [Double] = [1000]
        var expectedInvested: [Double] = [1000]
        for k in 1..<8 {
            let m = aug2026.adding(k)
            let a = d.allocation(h.id, in: m)
            if m <= oct2026 {
                value += a
            } else {
                value = value * (1 + rate) + a
            }
            invested += a
            expected.append(value.cents)
            expectedInvested.append(invested.cents)
        }
        XCTAssertEqual(series.map { $0.value }, expected)
        XCTAssertEqual(series.map { $0.invested }, expectedInvested)
        // De bedragen zelf: 10% van 3000, 5% in december, 10% van 4000 in januari.
        XCTAssertEqual(d.allocation(h.id, in: YearMonth(year: 2026, month: 12)), 150)
        XCTAssertEqual(d.allocation(h.id, in: YearMonth(year: 2027, month: 1)), 400)
    }

    /// Een lange reeks met percentage-beleggingen is niet merkbaar trager dan met vaste bedragen (voorheen ruim 40 keer).
    /// De verhouding is robuuster dan een vaste tijd op een trage machine.
    func testPortfolioSeriesWithPercentageIsNotMuchSlowerThanFixed() throws {
        try XCTSkipIf(MachineSpeed.skipsTiming, "tijdmetingen overgeslagen (SKIP_PERF_TESTS)")
        func data(percent: Bool) -> FinanceData {
            var d = FinanceData(startMonth: aug2026)
            d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
            var plan = MonthPlan()
            plan.expenses = (0..<8).map { MoneyLine(name: "Uitgave \($0)", amount: 20 + Double($0), isRecurring: true, day: 1 + $0) }
            plan.extraIncome = [MoneyLine(name: "Toeslag", amount: 100, isRecurring: true)]
            d.months[aug2026.key] = plan
            for i in 0..<3 {
                var h = Holding(name: "ETF \(i)", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                                monthlyContribution: 100, startMonth: aug2026)
                if percent {
                    h.contributionMode = .percentage
                    h.contributionPercent = 3
                    h.contributionBasis = i % 2 == 0 ? .salary : .allIncome
                }
                d.addHolding(h, initialValue: 1000, now: day(aug2026, 1))
            }
            d.materialize(upTo: oct2026)
            return d
        }
        func median(_ d: FinanceData) -> Double {
            var times: [Double] = []
            for _ in 0..<3 {
                let t0 = Date()
                _ = d.portfolioSeries(from: aug2026, count: 120, current: oct2026)
                times.append(Date().timeIntervalSince(t0))
            }
            return times.sorted()[1]
        }
        let fixed = median(data(percent: false))
        let percent = median(data(percent: true))
        XCTAssertLessThan(percent, fixed * 10 + 0.25, "percentage \(percent)s tegen vast \(fixed)s")
    }
}
