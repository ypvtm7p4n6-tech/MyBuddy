import XCTest
import Foundation
@testable import MyBuddyCore

// Versnellers die een inleg verhogen, op potten en beleggingen die een percentage van het inkomen inleggen (wens 3).
//
// Een versneller verhoogt een vast bedrag per maand. Staat de inleg als percentage van je inkomen, dan wordt het daardoor
// een vast bedrag: wat het percentage in de lopende maand opleverde plus de verhoging. Zo klopt de verhoging op de cent
// en blijft "te verdelen" gelijk. Herstellen zet het percentage (en de grondslag) terug, ook in vastgelegde maanden en in
// maanden die na het toepassen zijn begonnen.

private let apNov = YearMonth(year: 2026, month: 11)
private let apDec = YearMonth(year: 2026, month: 12)
private let apNow = day(oct2026, 12)

private struct PercentFixture {
    var data: FinanceData
    var pot: Pot
    var goal: LifeGoal
}

/// Salaris 3000, huur 1000 en toeslag 100 (beide terugkerend), pot "Vakantie" met 10% van het salaris (300) en beginsaldo
/// 500 vanaf augustus. Doel "Japan" (60000) wordt uit die pot betaald. Alle maanden t/m oktober zijn vastgelegd.
private func percentPotFixture(basis: IncomeBasis = .salary, percent: Double = 10) -> PercentFixture {
    var d = makeBaseData()
    var pot = Pot(name: "Vakantie", symbol: "airplane", monthlyContribution: 0, startMonth: aug2026)
    pot.contributionMode = .percentage
    pot.contributionPercent = percent
    pot.contributionBasis = basis
    d.addPot(pot, openingBalance: 500, now: day(aug2026, 2))
    var g = LifeGoal(name: "Japan", kind: .vacation)
    g.targetAmount = 60_000
    g.inflationAdjusted = false
    g.funding = .pot(pot.id)
    d.addGoal(g)
    d.materialize(upTo: oct2026)
    return PercentFixture(data: d, pot: pot, goal: g)
}

private func pick(_ prefix: String, _ d: FinanceData, _ goal: LifeGoal) -> Accelerator? {
    d.accelerators(for: goal, current: oct2026, today: apNow).first { $0.id == prefix || $0.id.hasPrefix(prefix + "-") }
}

final class AcceleratorPercentTests: XCTestCase {
    func testFreeSpaceTurnsThePercentageIntoAFixedAmountAndRestoreBringsItBack() throws {
        var f = percentPotFixture()
        f.data.editPlan(apDec) { _ in }   // december is al vastgelegd (met het percentage erin)
        let original = f.data
        let acc = try XCTUnwrap(pick("free", f.data, f.goal))
        XCTAssertEqual(acc.change.extraMonthly, 1_800, accuracy: 1e-9)   // 3100 - 1000 - 300
        let plan = f.data.applyPlan(acc, for: f.goal, current: oct2026, now: apNow)
        XCTAssertTrue(plan.notes.contains { $0.contains("percentage") }, "de bevestiging zegt dat het een vast bedrag wordt: \(plan.notes)")
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: apNow))

        let pot = try XCTUnwrap(f.data.pot(f.pot.id))
        XCTAssertEqual(pot.contributionMode, .fixed)
        XCTAssertEqual(pot.monthlyContribution, 2_100, accuracy: 1e-9)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: oct2026), 2_100, accuracy: 1e-9)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: apDec), 2_100, accuracy: 1e-9, "vastgelegde maand erna: 300 + 1800")
        XCTAssertEqual(f.data.allocation(f.pot.id, in: apNov), 2_100, accuracy: 1e-9, "nog niet vastgelegd: de nieuwe standaard")
        XCTAssertEqual(f.data.allocation(f.pot.id, in: sep2026), 300, accuracy: 1e-9, "het verleden blijft zoals het was")
        XCTAssertEqual(f.data.remaining(in: oct2026), 0, accuracy: 1e-9)
        XCTAssertEqual(record.summary[0], "Inleg Vakantie gaat van \(Fmt.euro(300)) naar \(Fmt.euro(2_100)) per maand, vanaf \(Fmt.month(oct2026)).")

        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertEqual(f.data, original, "terug naar het percentage, in alle maanden")
        XCTAssertEqual(f.data.pot(f.pot.id)?.contributionMode, .percentage)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: oct2026), 300, accuracy: 1e-9)
    }

    func testRestoreAlsoCleansTheMonthThatStartedAfterApplying() throws {
        for id in ["free", "expense", "hours", "income5", "stepup"] {
            var f = percentPotFixture()
            f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
            var expected = f.data
            expected.materialize(upTo: apNov)
            let acc = try XCTUnwrap(pick(id, f.data, f.goal), id)
            let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: apNow), id)
            f.data.materialize(upTo: apNov)   // de app wordt in november geopend
            XCTAssertNotEqual(f.data, expected, id)
            XCTAssertTrue(f.data.restoreAccelerator(record.id), id)
            XCTAssertEqual(f.data, expected, "\(id): november hoort ook terug te zijn")
            XCTAssertEqual(f.data.allocation(f.pot.id, in: apNov), f.data.percentAmount(10, of: .salary, in: apNov), accuracy: 1e-9, id)
        }
    }

    func testExtraHoursKeepTheBudgetEvenWhenThePercentageIsOverAllIncome() throws {
        var f = percentPotFixture(basis: .allIncome)
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        f.data.editPlan(apDec) { _ in }
        let original = f.data
        // 156 uur x 20 = 3120, plus toeslag 100 = 3220; 10% daarvan = 322.
        XCTAssertEqual(f.data.allocation(f.pot.id, in: oct2026), 322, accuracy: 1e-9)
        let remainingBefore = [oct2026, apNov, apDec].map { f.data.remaining(in: $0) }
        let acc = try XCTUnwrap(pick("hours", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: apNow))
        // Extra uren: 173,33 erbij. De inleg gaat met precies zoveel omhoog (niet met nog eens 10% van de extra uren).
        XCTAssertEqual(f.data.income(in: oct2026), 3_220 + 173.33, accuracy: 1e-9)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: oct2026), 322 + 173.33, accuracy: 1e-9)
        for (index, m) in [oct2026, apNov, apDec].enumerated() {
            XCTAssertEqual(f.data.remaining(in: m), remainingBefore[index], accuracy: 1e-9, m.key)
        }
        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertEqual(f.data, original)
    }

    func testExpenseCutWithAPercentagePotReturnsToTheOriginal() throws {
        var f = percentPotFixture()
        f.data.editPlan(apDec) { _ in }
        let original = f.data
        let remainingBefore = [oct2026, apNov, apDec].map { f.data.remaining(in: $0) }
        let acc = try XCTUnwrap(pick("expense", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: apNow))
        func rent(_ m: YearMonth) -> Double? { f.data.plan(for: m).expenses.first { $0.name == "Huur" }?.amount }
        XCTAssertEqual(rent(sep2026), 1_000)
        XCTAssertEqual(rent(oct2026), 900)
        XCTAssertEqual(rent(apNov), 900)
        XCTAssertEqual(rent(apDec), 900)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: oct2026), 400, accuracy: 1e-9)
        XCTAssertEqual(f.data.allocation(f.pot.id, in: apDec), 400, accuracy: 1e-9)
        XCTAssertEqual(f.data.pot(f.pot.id)?.contributionMode, .fixed)
        for (index, m) in [oct2026, apNov, apDec].enumerated() {
            XCTAssertEqual(f.data.remaining(in: m), remainingBefore[index], accuracy: 1e-9, m.key)
        }
        XCTAssertTrue(f.data.restoreAccelerator(record.id))
        XCTAssertEqual(f.data, original)
    }

    func testPortfolioFundingWithPercentageHoldings() throws {
        var d = makeBaseData()
        var etf = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002, startMonth: aug2026)
        etf.contributionMode = .percentage
        etf.contributionPercent = 5
        etf.contributionBasis = .allIncome
        var bonds = Holding(name: "Obligaties", kind: .bonds, ticker: nil, units: nil, expectedReturn: 0.03, annualCost: 0.003,
                            monthlyContribution: 100, startMonth: aug2026)
        bonds.contributionMode = .fixed
        d.addHolding(etf, initialValue: 4_000, now: day(sep2026, 1))
        d.addHolding(bonds, initialValue: 2_000, now: day(sep2026, 1))
        var g = LifeGoal(name: "Pensioen", kind: .custom)
        g.targetAmount = 500_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)
        d.materialize(upTo: oct2026)
        d.editPlan(apDec) { _ in }
        let original = d
        // ETF: 5% van 3100 = 155; obligaties 100. Vrij: 3100 - 1000 - 255 = 1845.
        XCTAssertEqual(d.allocation(etf.id, in: oct2026), 155, accuracy: 1e-9)
        let acc = try XCTUnwrap(pick("free", d, g))
        XCTAssertEqual(acc.change.extraMonthly, 1_845, accuracy: 1e-9)
        let remainingBefore = d.remaining(in: oct2026)
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: apNow))
        // Naar verhouding van de huidige inleg (155 : 100), tot op de cent: 1845 x 155/255 = 1121,47 en 723,53.
        let etfNow = d.allocation(etf.id, in: oct2026)
        let bondsNow = d.allocation(bonds.id, in: oct2026)
        XCTAssertEqual(etfNow + bondsNow, 255 + 1_845, accuracy: 1e-9, "er blijft geen cent liggen")
        XCTAssertGreaterThan(etfNow, 155)
        XCTAssertEqual(d.holding(etf.id)?.contributionMode, .fixed)
        XCTAssertEqual(d.remaining(in: oct2026), remainingBefore - 1_845, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(etf.id, in: apDec), etfNow, accuracy: 1e-9, "december is vastgelegd: 155 + zijn aandeel")
        XCTAssertTrue(d.restoreAccelerator(record.id))
        XCTAssertEqual(d, original)
        XCTAssertEqual(d.holding(etf.id)?.contributionMode, .percentage)
    }

    /// Willekeurige toepassingen op potten met een percentage, met tussendoor een nieuwe maand: alles herstellen geeft het
    /// origineel terug (met of zonder de nieuwe maand).
    func testRandomApplicationsOnPercentagePotsRestoreToTheOriginal() throws {
        var applied = 0
        for seed in 1...40 {
            var r = EngRandom(seed: UInt64(seed) &+ 700)
            var f = percentPotFixture(basis: r.chance(50) ? .salary : .allIncome, percent: Double(r.int(2...40)))
            if r.chance(50) { f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36) }
            let second = Pot(name: "Reserve", monthlyContribution: 50, startMonth: aug2026)
            f.data.addPot(second, openingBalance: 100, now: day(aug2026, 2))
            f.data.materialize(upTo: oct2026)
            if r.chance(60) { f.data.editPlan(apDec) { _ in } }
            let withNovember = r.chance(50)
            var expected = f.data
            if withNovember { expected.materialize(upTo: apNov) }
            let start = f.data
            for _ in 0..<r.int(1...4) {
                let list = f.data.accelerators(for: f.goal, current: oct2026, today: apNow)
                    .filter { ["free", "income5", "hours", "stepup"].contains($0.id) || $0.id.hasPrefix("expense-") }
                guard !list.isEmpty else { continue }
                if f.data.apply(list[r.int(0...list.count - 1)], for: f.goal, current: oct2026, now: apNow) != nil { applied += 1 }
                if withNovember, r.chance(40) { f.data.materialize(upTo: apNov) }
            }
            if withNovember { f.data.materialize(upTo: apNov) }
            f.data.restoreAllAccelerators()
            XCTAssertEqual(f.data, expected, "seed \(seed)")
            if !withNovember { XCTAssertEqual(f.data, start, "seed \(seed)") }
        }
        XCTAssertGreaterThan(applied, 40)
    }
}
