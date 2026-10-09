import XCTest
import Foundation
@testable import MyBuddyCore

// Tests voor twee dingen in Accelerators.swift:
// 1. "Verlaag X met 10%" belooft alleen wat er van de bank afgaat (een deel uit een spaarpot levert niets op).
// 2. De bewaarde oude toestand van een toegepaste versneller blijft klein, herstelt precies de oude waarden, laat de
//    meetpunten en koersen van nu staan, en oude (volle) records laden en herstellen nog steeds.
// Alle bedragen zijn met de hand nagerekend; geen enkele test hangt van de klok af.

private let bkNow = day(oct2026, 12)
private let bkDec = YearMonth(year: 2026, month: 12)

private func bkJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    return try encoder.encode(value)
}

// MARK: - Fixtures

private struct PotGoalFixture {
    var data: FinanceData
    var vakantie: Pot
    var buffer: Pot
    var goal: LifeGoal
}

/// Salaris 3000, huur 1000 (terugkerend), pot "Vakantie" (inleg 300, beginsaldo 500) waaruit doel "Japan" (6000) wordt betaald,
/// en een pot "Buffer" met 5000 zonder inleg waaruit uitgaven betaald kunnen worden.
private func bkPotGoalFixture() -> PotGoalFixture {
    var d = makeBaseData()
    let vakantie = Pot(name: "Vakantie", symbol: "airplane", monthlyContribution: 300, startMonth: aug2026)
    let buffer = Pot(name: "Buffer", monthlyContribution: 0, startMonth: aug2026)
    d.addPot(vakantie, openingBalance: 500, now: day(aug2026, 2))
    d.addPot(buffer, openingBalance: 5000, now: day(aug2026, 2))
    var g = LifeGoal(name: "Japan", kind: .vacation)
    g.targetAmount = 6000
    g.inflationAdjusted = false
    g.funding = .pot(vakantie.id)
    d.addGoal(g)
    d.materialize(upTo: oct2026)
    return PotGoalFixture(data: d, vakantie: vakantie, buffer: buffer, goal: g)
}

private func bkAdd(_ d: inout FinanceData, name: String, amount: Double, fromPot pot: Pot? = nil, potAmount: Double = 0) {
    var line = MoneyLine(name: name, amount: amount, isRecurring: true, kind: .fixed)
    if let pot { line.potShares = [PotShare(potID: pot.id, amount: potAmount)] }
    d.upsertLine(line, kind: .expense, in: oct2026)
}

private func bkOffer(_ name: String, in d: FinanceData, goal: LifeGoal) -> Accelerator? {
    d.accelerators(for: goal, current: oct2026, today: bkNow).first { $0.title == "Verlaag \(name) met 10%" }
}

private struct PortfolioFixture {
    var data: FinanceData
    var goal: LifeGoal
}

/// Acht beleggingen met elk 60 meetpunten (dagelijks vanaf 1 augustus), een bankrekening met 10.000 en een doel dat uit de
/// beleggingen komt. December is al vastgelegd. De inleg is 50, 60, ... 120 per maand (samen 680).
private func bkPortfolioFixture() -> PortfolioFixture {
    var d = makeBaseData()
    for n in 0..<8 {
        let holding = Holding(name: "Fonds \(n)", kind: .etf, ticker: nil, units: nil, expectedReturn: 0.06, annualCost: 0.002,
                              monthlyContribution: 50 + Double(n) * 10, startMonth: aug2026)
        d.addHolding(holding, initialValue: 1000 + Double(n) * 100, now: day(aug2026, 1))
        for k in 1..<60 {
            d.addSnapshot(holdingID: holding.id, value: 1000 + Double(n) * 100 + Double(k) * 2.5,
                          invested: 1000 + Double(n) * 100, date: day(aug2026, 1).addingTimeInterval(Double(k) * 86_400))
        }
    }
    d.materialize(upTo: oct2026)
    d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
    d.editPlan(bkDec) { _ in }
    var g = LifeGoal(name: "Rust", kind: .custom)
    g.targetAmount = 500_000
    g.inflationAdjusted = false
    g.funding = .portfolio
    d.addGoal(g)
    return PortfolioFixture(data: d, goal: g)
}

private func bkPick(_ id: String, _ d: FinanceData, _ goal: LifeGoal) -> Accelerator? {
    d.accelerators(for: goal, current: oct2026, today: bkNow).first { $0.id == id }
}

final class AcceleratorExpenseCutOfferTests: XCTestCase {

    // MARK: Besparing is het bankdeel

    func testExpenseCompletelyPaidFromAPotIsNotOffered() throws {
        var f = bkPotGoalFixture()
        // 150 per maand, helemaal uit de buffer: 10% minder levert het maandbudget niets op.
        bkAdd(&f.data, name: "Abonnementen", amount: 150, fromPot: f.buffer, potAmount: 150)
        let list = f.data.accelerators(for: f.goal, current: oct2026, today: bkNow)
        XCTAssertNil(list.first { $0.title.contains("Abonnementen") }, "een uitgave uit een spaarpot levert niets vrij")
        // De huur (alles van de bank) wordt nog wel voorgesteld: 10% van 1000.
        let rent = try XCTUnwrap(bkOffer("Huur", in: f.data, goal: f.goal))
        XCTAssertEqual(rent.change.extraMonthly, 100, accuracy: 0.0001)
    }

    func testEveryOfferedExpenseCutAlsoAppliesAndDeliversWhatItPromised() throws {
        var f = bkPotGoalFixture()
        bkAdd(&f.data, name: "Abonnementen", amount: 150, fromPot: f.buffer, potAmount: 150)
        bkAdd(&f.data, name: "Sportschool", amount: 80)
        let offered = f.data.accelerators(for: f.goal, current: oct2026, today: bkNow).filter { $0.id.hasPrefix("expense-") }
        XCTAssertFalse(offered.isEmpty)
        for acc in offered {
            var copy = f.data
            let before = copy.pot(f.vakantie.id)?.monthlyContribution ?? 0
            XCTAssertNotNil(copy.apply(acc, for: f.goal, current: oct2026, now: bkNow), "\(acc.title) moet toe te passen zijn")
            let delta = (copy.pot(f.vakantie.id)?.monthlyContribution ?? 0) - before
            XCTAssertEqual(delta, acc.change.extraMonthly, accuracy: 0.0001, "\(acc.title): belofte en uitkomst verschillen")
        }
    }

    func testExpensePartlyFromAPotPromisesOnlyTheBankPart() throws {
        var f = bkPotGoalFixture()
        // 150 waarvan 140 uit de buffer: bank betaalt 10. Na 10% minder (135) betaalt de pot maximaal 135 en de bank 0.
        // Er komt dus 10 vrij, niet 15.
        bkAdd(&f.data, name: "Abonnementen", amount: 150, fromPot: f.buffer, potAmount: 140)
        let acc = try XCTUnwrap(bkOffer("Abonnementen", in: f.data, goal: f.goal))
        XCTAssertEqual(acc.change.extraMonthly, 10, accuracy: 0.0001)
        XCTAssertTrue(acc.detail.contains("\(Fmt.euro(10)) per maand voor je doel"), acc.detail)
        XCTAssertFalse(acc.detail.contains("\(Fmt.euro(15)) per maand"), acc.detail)
        XCTAssertTrue(acc.detail.contains("spaarpot"), "de uitleg zegt dat een deel uit een spaarpot niet meetelt: \(acc.detail)")

        let remainingBefore = f.data.remaining(in: oct2026)
        XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow))
        XCTAssertEqual(f.data.plan(for: oct2026).expenses.first { $0.name == "Abonnementen" }?.amount ?? 0, 135, accuracy: 0.0001)
        XCTAssertEqual(f.data.pot(f.vakantie.id)?.monthlyContribution ?? 0, 310, accuracy: 0.0001)
        XCTAssertEqual(f.data.remaining(in: oct2026), remainingBefore, accuracy: 0.0001)
    }

    func testExpenseFullyFromBankKeepsTheOriginalWording() throws {
        let f = bkPotGoalFixture()
        let acc = try XCTUnwrap(bkOffer("Huur", in: f.data, goal: f.goal))
        XCTAssertEqual(acc.detail, "Huur kost \(Fmt.euro(1000)) per maand. 10% minder is \(Fmt.euro(100)) per maand voor je doel.")
    }

    func testAPotPaidExpenseDoesNotTakeAPlaceInTheTopThree() throws {
        var f = bkPotGoalFixture()
        // Vier extra terugkerende uitgaven; de grootste (900) komt helemaal uit een pot. Met de huur (1000) zijn er vijf:
        // de drie grootste met een besparing zijn Huur, 800 en 700. De 900 uit de pot telt niet mee, de 600 valt buiten de top drie.
        bkAdd(&f.data, name: "Uit pot", amount: 900, fromPot: f.buffer, potAmount: 900)
        bkAdd(&f.data, name: "Achthonderd", amount: 800)
        bkAdd(&f.data, name: "Zevenhonderd", amount: 700)
        bkAdd(&f.data, name: "Zeshonderd", amount: 600)
        let titles = Set(f.data.accelerators(for: f.goal, current: oct2026, today: bkNow).filter { $0.id.hasPrefix("expense-") }.map(\.title))
        XCTAssertEqual(titles, ["Verlaag Huur met 10%", "Verlaag Achthonderd met 10%", "Verlaag Zevenhonderd met 10%"])
    }

    func testSmallOrOneOffExpensesAreStillNotOffered() throws {
        var f = bkPotGoalFixture()
        bkAdd(&f.data, name: "Klein", amount: 19)
        f.data.upsertLine(MoneyLine(name: "Tandarts", amount: 300, isRecurring: false), kind: .expense, in: oct2026)
        let titles = f.data.accelerators(for: f.goal, current: oct2026, today: bkNow).map(\.title)
        XCTAssertFalse(titles.contains { $0.contains("Klein") })
        XCTAssertFalse(titles.contains { $0.contains("Tandarts") })
    }
}

final class AcceleratorBackupSizeTests: XCTestCase {

    // MARK: Klein

    func testBackupOfThreeApplicationsOnEightHoldingsOf60PointsStaysUnder20KB() throws {
        var f = bkPortfolioFixture()
        let original = f.data
        let originalBytes = try bkJSON(original).count

        for id in ["income5", "free", "bank"] {
            let acc = try XCTUnwrap(bkPick(id, f.data, f.goal), id)
            let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow), id)
            XCTAssertEqual(record.before.holdings.count, 8, "\(id): alle acht beleggingen zijn aangepast")
            for kept in record.before.holdings {
                XCTAssertTrue(kept.snapshots.isEmpty, "\(id): de bewaarkopie van \(kept.name) heeft geen meetpunten")
                XCTAssertNil(kept.lastPrice)
            }
        }
        XCTAssertEqual(f.data.appliedAccelerators.count, 3)

        let appliedBytes = try bkJSON(f.data.appliedAccelerators).count
        XCTAssertLessThan(appliedBytes, 20_000, "de bewaarde records zijn \(appliedBytes) bytes")
        // De hele dataset groeit ook nauwelijks: drie records plus drie nieuwe meetpunten op acht beleggingen.
        let grown = try bkJSON(f.data).count - originalBytes
        XCTAssertLessThan(grown, 20_000, "finance.json groeide met \(grown) bytes")
    }

    func testTheOldFullBackupWasMuchBiggerSoTheTestMeasuresSomething() throws {
        // Controle op de testdata zelf: 8 beleggingen van 60 meetpunten zijn bij één volledige kopie al ruim 40 KB.
        let f = bkPortfolioFixture()
        var legacy = AcceleratorBackup()
        legacy.holdings = f.data.holdings
        XCTAssertGreaterThan(try bkJSON(legacy).count, 40_000)
    }

    func testBackupOfOnePlanOnlyHoldsWhatRestoreReads() throws {
        var f = bkPortfolioFixture()
        let acc = try XCTUnwrap(bkPick("income5", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow))
        let touched = Set(f.data.holdings.map(\.id.uuidString))
        XCTAssertEqual(Set(record.before.plans.keys), [oct2026.key, bkDec.key])
        for (key, plan) in record.before.plans {
            XCTAssertTrue(plan.extraIncome.isEmpty, key)
            XCTAssertTrue(plan.expenses.isEmpty, "\(key): een inleg-versneller leest geen uitgaven terug")
            XCTAssertTrue(Set(plan.allocations.keys).isSubset(of: touched), key)
            XCTAssertEqual(plan.allocations.count, 8, key)
        }
    }

    func testBackupOfAnExpenseCutKeepsOnlyTheCutLine() throws {
        var f = bkPotGoalFixture()
        bkAdd(&f.data, name: "Sportschool", amount: 80)
        let acc = try XCTUnwrap(bkOffer("Huur", in: f.data, goal: f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow))
        let kept = try XCTUnwrap(record.before.plans[oct2026.key])
        XCTAssertEqual(kept.expenses.map(\.name), ["Huur"])
        XCTAssertEqual(kept.expenses.first?.amount, 1000)
        XCTAssertEqual(kept.allocations, [f.vakantie.id.uuidString: 300])
    }

    // MARK: Herstellen

    func testRestoreGivesExactlyTheOldValuesBack() throws {
        var f = bkPortfolioFixture()
        let original = f.data
        for id in ["income5", "free", "bank"] {
            let acc = try XCTUnwrap(bkPick(id, f.data, f.goal), id)
            XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow), id)
        }
        XCTAssertNotEqual(f.data, original)
        // De inleg is omhoog gegaan: 680 + 155 (5% van 3100) + 1265 (de rest van het inkomen) = 2100 per maand.
        XCTAssertEqual(f.data.monthlyInvestment(current: oct2026), 2100, accuracy: 0.0001)

        f.data.restoreAllAccelerators()
        XCTAssertTrue(f.data.appliedAccelerators.isEmpty)
        XCTAssertEqual(f.data, original, "inleg, ingelegd bedrag, meetpunten en maandplannen zijn weer als voorheen")
        XCTAssertEqual(f.data.monthlyInvestment(current: oct2026), 680, accuracy: 0.0001)
        for (restored, old) in zip(f.data.holdings, original.holdings) {
            XCTAssertEqual(restored.snapshots.count, 60)
            XCTAssertEqual(restored.monthlyContribution, old.monthlyContribution)
            XCTAssertEqual(restored.investedTotal, old.investedTotal)
        }
    }

    func testRestoreEachApplicationOneByOneNewestFirst() throws {
        var f = bkPortfolioFixture()
        var states = [f.data]
        var records: [AppliedAccelerator] = []
        for id in ["income5", "free", "bank"] {
            let acc = try XCTUnwrap(bkPick(id, f.data, f.goal), id)
            records.append(try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow), id))
            states.append(f.data)
        }
        for index in stride(from: 2, through: 0, by: -1) {
            XCTAssertTrue(f.data.restoreAccelerator(records[index].id), "toepassing \(index)")
            XCTAssertEqual(f.data, states[index], "na herstel van toepassing \(index)")
        }
    }

    func testRestoreKeepsTheSnapshotsAndPricesThatCameAfterApplying() throws {
        var d = makeBaseData()
        // Een gevolgde belegging (5 stuks à 100 = 500) en een gewone van 4000.
        let tracked = Holding(name: "Gevolgd", kind: .etf, ticker: "VWCE.DE", units: 5, investedTotal: 400, expectedReturn: 0.06,
                              annualCost: 0.002, startMonth: aug2026, lastPrice: 100, lastPriceDate: day(oct2026, 10))
        let plain = Holding(name: "Spaar", kind: .savings, ticker: nil, units: nil, expectedReturn: 0.02, annualCost: 0,
                            monthlyContribution: 200, startMonth: aug2026)
        d.addHolding(tracked, initialValue: 500, now: day(sep2026, 1))
        d.addHolding(plain, initialValue: 4000, now: day(sep2026, 1))
        d.materialize(upTo: oct2026)
        d.addBankSnapshot(balance: 10_000, date: day(oct2026, 1))
        var g = LifeGoal(name: "Rust", kind: .custom)
        g.targetAmount = 30_000
        g.inflationAdjusted = false
        g.funding = .portfolio
        d.addGoal(g)

        let before = d
        let trackedBefore = try XCTUnwrap(before.holding(tracked.id))
        let acc = try XCTUnwrap(bkPick("bank", d, g))
        let record = try XCTUnwrap(d.apply(acc, for: g, current: oct2026, now: bkNow))
        let trackedAfter = try XCTUnwrap(d.holding(tracked.id))
        XCTAssertNotEqual(trackedAfter.units, trackedBefore.units, "de versneller zet geld in de gevolgde belegging")
        XCTAssertGreaterThan(trackedAfter.snapshots.count, trackedBefore.snapshots.count)

        // Na het toepassen komt er een nieuw meetpunt en een nieuwe koers bij (zoals bij het verversen van de koersen).
        let later = ValueSnapshot(date: day(oct2026, 20), value: 612, invested: trackedAfter.investedTotal)
        if let i = d.holdings.firstIndex(where: { $0.id == tracked.id }) {
            d.holdings[i].snapshots.append(later)
            d.holdings[i].lastPrice = 123.45
            d.holdings[i].lastPriceDate = day(oct2026, 20)
        }

        XCTAssertTrue(d.restoreAccelerator(record.id))
        let restored = try XCTUnwrap(d.holding(tracked.id))
        // Teruggezet: wat de versneller aanpaste.
        XCTAssertEqual(restored.units, 5)
        XCTAssertEqual(restored.investedTotal, 400)
        // Gebleven: de meetpunten van voor het toepassen, plus het nieuwe meetpunt, plus de koers van nu.
        XCTAssertEqual(restored.snapshots.map(\.id), trackedBefore.snapshots.map(\.id) + [later.id])
        XCTAssertEqual(restored.lastPrice, 123.45)
        XCTAssertEqual(restored.lastPriceDate, day(oct2026, 20))
        // Het meetpunt van de versneller zelf is weg.
        XCTAssertEqual(restored.snapshots.count, trackedBefore.snapshots.count + 1)
        let plainRestored = try XCTUnwrap(d.holding(plain.id))
        XCTAssertEqual(plainRestored, try XCTUnwrap(before.holding(plain.id)))
    }

    // MARK: Oude records

    /// Zo bewaarde de vorige versie een toepassing: volledige potten, beleggingen (met alle meetpunten) en maandplannen
    /// van alles wat veranderde. Dit bootst het oude formaat na; de verwachte uitkomst (herstellen geeft het origineel) is
    /// onafhankelijk van de implementatie.
    private func legacyBackup(from old: FinanceData, to new: FinanceData) -> AcceleratorBackup {
        var backup = AcceleratorBackup()
        for pot in new.pots {
            if let before = old.pots.first(where: { $0.id == pot.id }), before != pot { backup.pots.append(before) }
        }
        for holding in new.holdings {
            if let before = old.holdings.first(where: { $0.id == holding.id }), before != holding { backup.holdings.append(before) }
        }
        for goal in new.goals {
            if let before = old.goals.first(where: { $0.id == goal.id }), before != goal { backup.goals.append(before) }
        }
        for (key, plan) in new.months {
            if let before = old.months[key] {
                if before != plan { backup.plans[key] = before }
            } else {
                backup.newPlanKeys.append(key)
            }
        }
        backup.newPlanKeys.sort()
        if new.settings != old.settings { backup.settings = old.settings }
        if new.salary != old.salary { backup.salary = old.salary }
        return backup
    }

    func testOldFullRecordsStillLoadAndRestore() throws {
        var f = bkPortfolioFixture()
        let original = f.data
        let acc = try XCTUnwrap(bkPick("income5", f.data, f.goal))
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow))
        f.data.appliedAccelerators[0].before = legacyBackup(from: original, to: f.data)

        // Het oude formaat is groot, maar laadt zoals het was.
        let json = try bkJSON(f.data)
        XCTAssertGreaterThan(try bkJSON(f.data.appliedAccelerators).count, 40_000)
        var loaded = try JSONDecoder().decode(FinanceData.self, from: json)
        XCTAssertEqual(loaded, f.data)
        XCTAssertEqual(loaded.appliedAccelerators[0].before.holdings.first?.snapshots.count, 60)

        // Herstellen werkt rechtstreeks op een oud record.
        var direct = loaded
        XCTAssertTrue(direct.restoreAccelerator(record.id))
        XCTAssertEqual(direct, original)

        // En na het compact maken ook, met een veel kleiner record.
        XCTAssertTrue(loaded.compactAppliedAccelerators())
        XCTAssertLessThan(try bkJSON(loaded.appliedAccelerators).count, 20_000)
        XCTAssertTrue(loaded.appliedAccelerators[0].before.holdings.allSatisfy { $0.snapshots.isEmpty })
        XCTAssertFalse(loaded.compactAppliedAccelerators(), "nog een keer compact maken verandert niets meer")
        XCTAssertTrue(loaded.restoreAccelerator(record.id))
        XCTAssertEqual(loaded, original)
    }

    func testCompactRecordsSurviveAnEncodeDecodeRoundTripAndStillRestore() throws {
        var f = bkPortfolioFixture()
        let original = f.data
        for id in ["income5", "bank"] {
            let acc = try XCTUnwrap(bkPick(id, f.data, f.goal), id)
            XCTAssertNotNil(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow), id)
        }
        var loaded = try JSONDecoder().decode(FinanceData.self, from: try bkJSON(f.data))
        XCTAssertEqual(loaded, f.data)
        XCTAssertFalse(loaded.compactAppliedAccelerators(), "nieuwe records zijn al compact")
        loaded.restoreAllAccelerators()
        XCTAssertEqual(loaded, original)
    }

    func testOldRecordsWithAnExpenseAndExtraHoursStillRestoreAfterCompacting() throws {
        // Een uitgave-versneller leest zijn regel uit het bewaarde plan; extra uren voegen een inkomstenregel toe.
        var f = bkPotGoalFixture()
        f.data.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        f.data.editPlan(bkDec) { _ in }
        let original = f.data
        var legacyRecords: [AppliedAccelerator] = []
        for pick in ["expense", "hours"] {
            let acc = try XCTUnwrap(f.data.accelerators(for: f.goal, current: oct2026, today: bkNow)
                .first { $0.id == pick || $0.id.hasPrefix(pick + "-") }, pick)
            let old = f.data
            var record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow), pick)
            record.before = legacyBackup(from: old, to: f.data)
            legacyRecords.append(record)
        }
        var legacyData = f.data
        legacyData.appliedAccelerators = legacyRecords

        var direct = legacyData
        direct.restoreAllAccelerators()
        XCTAssertEqual(direct, original, "oude volle records herstellen exact")

        var compacted = legacyData
        XCTAssertTrue(compacted.compactAppliedAccelerators())
        compacted.restoreAllAccelerators()
        XCTAssertEqual(compacted, original, "na compact maken herstellen ze nog steeds exact")

        // Ook de nieuwe, compacte records herstellen deze combinatie exact.
        var fresh = f.data
        fresh.restoreAllAccelerators()
        XCTAssertEqual(fresh, original)
    }

    // MARK: Begrenzen

    private func dummyRecord(_ n: Int) -> AppliedAccelerator {
        AppliedAccelerator(acceleratorID: "target", goalID: UUID(), title: "Oud \(n)", date: day(aug2026, 1 + n % 28))
    }

    func testOnlyTheNewestTwentyRecordsAreKept() {
        var d = makeBaseData()
        d.appliedAccelerators = (0..<25).map(dummyRecord)
        XCTAssertTrue(d.compactAppliedAccelerators())
        XCTAssertEqual(d.appliedAccelerators.count, FinanceData.maxStoredAppliedAccelerators)
        XCTAssertEqual(FinanceData.maxStoredAppliedAccelerators, 20)
        XCTAssertEqual(d.appliedAccelerators.map(\.title), (5..<25).map { "Oud \($0)" }, "de nieuwste (laatste) blijven")
        XCTAssertFalse(d.compactAppliedAccelerators())
    }

    func testApplyingKeepsTheListWithinTheLimit() throws {
        var f = bkPotGoalFixture()
        f.data.appliedAccelerators = (0..<20).map(dummyRecord)
        let acc = try XCTUnwrap(f.data.accelerators(for: f.goal, current: oct2026, today: bkNow).first { $0.id == "income5" })
        let record = try XCTUnwrap(f.data.apply(acc, for: f.goal, current: oct2026, now: bkNow))
        XCTAssertEqual(f.data.appliedAccelerators.count, 20)
        XCTAssertEqual(f.data.appliedAccelerators.last?.id, record.id)
        XCTAssertEqual(f.data.appliedAccelerators.first?.title, "Oud 1", "alleen de oudste is afgevallen")
    }

    func testAnEmptyOrShortListIsLeftAlone() {
        var d = makeBaseData()
        XCTAssertFalse(d.compactAppliedAccelerators())
        d.appliedAccelerators = (0..<3).map(dummyRecord)
        XCTAssertFalse(d.compactAppliedAccelerators())
        XCTAssertEqual(d.appliedAccelerators.count, 3)
    }
}
