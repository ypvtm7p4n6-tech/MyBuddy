import XCTest
import Foundation
@testable import MyBuddyCore

/// D3 (docs/work/plan2.md par. 2.3): de bankrekening als bestemming van de verdeling is een toewijzing zonder beweging. `remaining`
/// blijft wat er op de rekening blijft; `toBank` en `unassigned` (= `remaining - toBank`) komen erbij, en het getal bij het label
/// "Nog te verdelen" kiest één functie (`MoneyLabels.left`).
final class BankShareTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)

    private func without(_ data: FinanceData) -> FinanceData {
        var copy = data
        copy.bankShare = BankShare()
        for key in Array(copy.months.keys) {
            copy.months[key]?.allocations.removeValue(forKey: BankShare.key)
            copy.months[key]?.percentAllocations.removeValue(forKey: BankShare.key)
        }
        return copy
    }

    private func base() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let pot = Pot(name: "Vakantie", monthlyContribution: 200, startMonth: oct2026)
        d.addPot(pot, openingBalance: 100, now: day(oct2026, 1))
        d.addBankSnapshot(balance: 1_000, note: "Begin", date: day(oct2026, 1))
        var plan = MonthPlan()
        plan.expenses = [MoneyLine(name: "Huur", amount: 900, isRecurring: true, day: 1)]
        d.months[oct2026.key] = plan
        return (d, pot)
    }

    // MARK: D3

    func testTheBankShareMovesNoMoneyOnAnyDay() {
        var checked = 0
        var months = 0
        for seed in 1...300 {
            let scenario = ledgerScenario(seed: UInt64(seed))
            let d = scenario.data
            guard d.hasBankShare else { continue }
            checked += 1
            let d0 = without(d)
            for m in scenario.months {
                let l = d.monthLedger(m, asOf: scenario.today)
                let l0 = d0.monthLedger(m, asOf: scenario.today)
                XCTAssertTrue(l.allReconciles, "zaadwaarde \(seed) \(m.key)")
                XCTAssertEqual(l.days.map { $0.bankBalance }, l0.days.map { $0.bankBalance }, "bank: zaadwaarde \(seed) \(m.key)")
                XCTAssertEqual(l.days.map { $0.potsTotal }, l0.days.map { $0.potsTotal }, "potten: zaadwaarde \(seed) \(m.key)")
                XCTAssertEqual(l.days.map { $0.events.map { $0.id } }, l0.days.map { $0.events.map { $0.id } }, "gebeurtenissen: zaadwaarde \(seed) \(m.key)")
                let f = d.monthFigures(m), f0 = d0.monthFigures(m)
                XCTAssertEqual(f.remaining, f0.remaining, "remaining: zaadwaarde \(seed) \(m.key)")
                XCTAssertEqual(f.saved, f0.saved)
                XCTAssertEqual(f.invested, f0.invested)
                XCTAssertEqual(f.unassigned, f0.remaining - f.toBank, "nog te verdelen: zaadwaarde \(seed) \(m.key)")
                XCTAssertEqual(f0.toBank, 0)
                if f.toBank != 0 { months += 1 }
            }
            XCTAssertEqual(d.netWorthNow(current: scenario.start.adding(3), today: scenario.today).total,
                           d0.netWorthNow(current: scenario.start.adding(3), today: scenario.today).total, "vermogen: zaadwaarde \(seed)")
        }
        XCTAssertGreaterThan(checked, 40)
        XCTAssertGreaterThan(months, 150)
        print("PROEF bankdeel: \(checked) datasets, \(months) maanden met een bankdeel")
    }

    func testRemainingToTheBankReachesExactlyZero() {
        var reached = 0
        for seed in 1...200 {
            let scenario = ledgerScenario(seed: UInt64(seed))
            for m in scenario.months {
                var d = scenario.data
                let before = d.monthFigures(m)
                guard before.unassigned > 0 else { continue }
                d.sendRemainingToBank(in: m)
                let after = d.monthFigures(m)
                XCTAssertEqual(after.unassigned, 0, "zaadwaarde \(seed) \(m.key)")
                XCTAssertEqual(after.remaining, before.remaining)
                XCTAssertEqual(after.toBank, before.toBank + before.unassigned)
                XCTAssertTrue(d.monthLedger(m, asOf: scenario.today).allReconciles)
                XCTAssertEqual(d.allocationWarnings(in: m).filter { if case .overAllocated = $0 { return true } else { return false } }.count,
                               before.overAllocated > 0 ? 1 : 0)
                reached += 1
            }
        }
        XCTAssertGreaterThan(reached, 300)
    }

    func testABankShareLargerThanTheRemainderIsOverAllocated() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 5_000)
        let f = d.monthFigures(nov)
        XCTAssertEqual(f.toBank, 500_000)
        XCTAssertLessThan(f.unassigned, 0)
        XCTAssertGreaterThan(f.overAllocated, 0)
        XCTAssertTrue(d.allocationWarnings(in: nov).contains { if case .overAllocated = $0 { return true } else { return false } })
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
    }

    func testStandardBankShareAsPercentagePlusExtraAndPast() {
        var (d, _) = base()
        d.materialize(upTo: nov)
        d.setContributionPercent(BankShare.id, percent: 10, basis: .salary, extra: 25, current: nov)
        // Vanaf november 10% van het salaris plus 25; oktober (voor de lopende maand) blijft zoals het was: niets.
        XCTAssertEqual(d.monthFigures(nov).toBank, 32_500)
        XCTAssertEqual(d.monthFigures(oct2026).toBank, 0)
        XCTAssertEqual(d.monthFigures(engDec2026).toBank, 32_500)
        XCTAssertEqual(d.bankShare.contributionMode, .percentage)
        d.setContributionAmount(BankShare.id, amount: 400, current: engDec2026)
        XCTAssertEqual(d.monthFigures(nov).toBank, 32_500)
        XCTAssertEqual(d.monthFigures(engDec2026).toBank, 40_000)
        XCTAssertEqual(d.monthFigures(engJan2027).toBank, 40_000)
    }

    func testStandardDistributionAndZeroTheMonthIncludeTheBank() {
        var (d, _) = base()
        d.setContributionAmount(BankShare.id, amount: 300, current: oct2026)
        d.setAllocation(BankShare.id, in: nov, amount: 50)
        XCTAssertEqual(d.monthFigures(nov).toBank, 5_000)
        d.applyDefaultAllocations(in: nov)
        XCTAssertEqual(d.monthFigures(nov).toBank, 30_000)
        d.clearAllocations(in: nov)
        XCTAssertEqual(d.monthFigures(nov).toBank, 0)
        XCTAssertEqual(d.monthFigures(nov).saved, 0)
    }

    func testSpreadRemainingOverPotsLeavesTheBankShareAlone() {
        var (d, pot) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 500)
        let unassigned = d.monthFigures(nov).unassigned
        let potBefore = d.monthFigures(nov).saved
        d.spreadRemainingOverPots(in: nov)
        XCTAssertEqual(d.monthFigures(nov).unassigned, 0)
        XCTAssertEqual(d.monthFigures(nov).saved, potBefore + unassigned)
        XCTAssertEqual(d.monthFigures(nov).toBank, 50_000)
        _ = pot
    }

    func testTheLabelFigureFollowsTheMonth() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 500)
        let f = d.monthFigures(nov)
        XCTAssertEqual(MoneyLabels.left(f, of: nov, current: nov), f.unassigned)
        XCTAssertEqual(MoneyLabels.left(f, of: oct2026, current: nov), f.remaining)
        XCTAssertEqual(MoneyLabels.left(f, of: nov, current: nov, isPeriod: true), f.remaining)
        XCTAssertEqual(MoneyLabels.remainingLabel(of: nov, current: nov), "Nog te verdelen")
    }

    func testOldFilesWithoutABankShareStayIdenticalAndTheKeyIsInert() throws {
        var (d, _) = base()
        let encoder = FinanceStorage.makeFileEncoder()
        let plain = try encoder.encode(d)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("bankShare"))
        d.setContributionAmount(BankShare.id, amount: 100, current: oct2026)
        let text = String(decoding: try encoder.encode(d), as: UTF8.self)
        XCTAssertTrue(text.contains("\"bankShare\":{\"monthlyContribution\":100}"))
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: try encoder.encode(d))
        XCTAssertEqual(back.bankShare, d.bankShare)
        // Een onleesbaar bankdeel wordt genegeerd.
        let broken = text.replacingOccurrences(of: "{\"monthlyContribution\":100}", with: "\"kapot\"")
        XCTAssertEqual(try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(broken.utf8)).bankShare, BankShare())
    }

    func testTheBankShareCountsInTheWholeStartMonth() {
        var (d, _) = base()
        d.setStart(CalendarDay(year: 2026, month: 10, day: 28))   // na de salarisdag: het salaris telt niet mee
        d.setAllocation(BankShare.id, in: oct2026, amount: 100)
        XCTAssertEqual(d.monthFigures(oct2026).toBank, 10_000)
    }

    func testContentChecksSeeABankShare() {
        var d = FinanceData(startMonth: oct2026)
        XCTAssertTrue(d.isEmptyStart)
        XCTAssertFalse(CloudSync.hasContent(d))
        d.bankShare.monthlyContribution = 100
        XCTAssertFalse(d.isEmptyStart)
        XCTAssertTrue(CloudSync.hasContent(d))
        // Ook een regel voor de bankrekening in één maand telt als inhoud (een percentage staat niet in `allocations`).
        var e = FinanceData(startMonth: oct2026)
        e.setAllocationPercent(BankShare.id, in: nov, percent: 10, basis: .salary)
        XCTAssertTrue(e.hasBankShare)
        XCTAssertFalse(e.isEmptyStart)
        XCTAssertTrue(CloudSync.hasContent(e))
        var f = FinanceData(startMonth: oct2026)
        f.setAllocation(BankShare.id, in: nov, amount: 50)
        XCTAssertFalse(f.isEmptyStart)
        XCTAssertTrue(CloudSync.hasContent(f))
        // Het verdwijnen van de marktgegevens uit een bestand laat het bankdeel staan.
        XCTAssertEqual(CloudSync.withoutMarketData(d).bankShare, d.bankShare)
        // Een loonwijziging (Loon per maand) is ook inhoud, en blijft staan als de marktgegevens verdwijnen.
        var g = FinanceData(startMonth: oct2026)
        g.setSalaryChange(SalaryChange(from: nov, hourlyRate: 16))
        XCTAssertFalse(g.isEmptyStart)
        XCTAssertTrue(CloudSync.hasContent(g))
        XCTAssertEqual(CloudSync.withoutMarketData(g).salaryChanges, g.salaryChanges)
        g.removeSalaryChange(from: nov)
        XCTAssertTrue(g.isEmptyStart, "zonder wijziging is de start weer leeg")
        XCTAssertFalse(CloudSync.hasContent(g))
    }

    func testTheLedgerCarriesTheBankShareAsAFigureOnly() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 123)
        let ledger = d.monthLedger(nov)
        XCTAssertEqual(ledger.toBank, 123)
        XCTAssertEqual(ledger.unassigned, ledger.remaining - 123)
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertEqual(ledger.days.last?.remainingSoFar, ledger.remaining)
    }

    func testTheSampleWithDistributionShowsTheNewPossibilities() {
        let now = day(oct2026, 12)
        let d = FinanceData.sampleWithDistribution(now: now)
        XCTAssertEqual(d.monthFigures(oct2026).toBank, 30_000)
        let holiday = d.pots.first { $0.name == "Vakantie" }!
        XCTAssertEqual(holiday.extraTransfers, [TransferPart(day: 10, amount: 40)])
        XCTAssertEqual(holiday.contributionExtra, 25)
        XCTAssertEqual(d.transferSlices(for: holiday.id, in: oct2026).map { $0.day }.first, 10)
        for m in [oct2026, nov] { XCTAssertTrue(d.monthLedger(m).allReconciles) }
        // Het uurloon gaat vanaf volgende maand met een euro omhoog (Loon per maand); de maanden ervoor houden hun loon.
        XCTAssertEqual(d.salaryChanges, [SalaryChange(from: nov, hourlyRate: d.salary.hourlyRate + 1)])
        XCTAssertEqual(d.salarySettings(in: oct2026).hourlyRate, d.salary.hourlyRate)
        XCTAssertEqual(d.salarySettings(in: nov).hourlyRate, d.salary.hourlyRate + 1)
        XCTAssertGreaterThan(d.salaryAmount(in: nov), d.salaryAmount(in: oct2026))
        XCTAssertTrue(d.months.values.allSatisfy { $0.salaryOverride == nil }, "er is niets vastgelegd")
        // De gewone voorbeelddata blijft ongewijzigd.
        XCTAssertTrue(FinanceData.sample(now: now).salaryChanges.isEmpty)
        XCTAssertEqual(FinanceData.sample(now: now).bankShare, BankShare())
        XCTAssertTrue(FinanceData.sample(now: now).pots.allSatisfy { $0.extraTransfers.isEmpty && $0.contributionExtra == 0 })
    }

    // MARK: Aanvullingen

    func testANegativeBankShareCountsAsZero() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: -200)
        let f = d.monthFigures(nov)
        XCTAssertEqual(f.toBank, 0)
        XCTAssertEqual(d.bankShareAmount(in: nov), 0)
        XCTAssertEqual(f.unassigned, f.remaining)
        XCTAssertEqual(d.unassigned(in: nov), CentsMath.value(f.remaining))
        XCTAssertEqual(f.overAllocated, d.monthFigures(nov).overAllocated)
    }

    func testUnassignedFeedsThePurchaseCheckTheBufferAndTheAccelerators() throws {
        var (d, pot) = base()
        let now = day(oct2026, 12)
        var goal = LifeGoal(name: "Japan", kind: .vacation)
        goal.targetAmount = 60_000
        goal.inflationAdjusted = false
        goal.funding = .pot(pot.id)
        d.addGoal(goal)
        let setup = BufferSetup()
        let plainContext = PurchaseContext.make(from: d, current: oct2026, today: now)
        let plainBuffer = BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: oct2026)
        let plainFree = try XCTUnwrap(d.accelerators(for: goal, current: oct2026, today: now).first { $0.id == "free" })
        XCTAssertEqual(try XCTUnwrap(plainContext.remainingThisMonth), d.estimatedRemaining(in: oct2026), accuracy: 1e-9, "zonder bankdeel gelijk")
        XCTAssertEqual(plainBuffer, d.estimatedRemaining(in: oct2026), accuracy: 1e-9)
        XCTAssertEqual(plainFree.change.extraMonthly, d.estimatedRemaining(in: oct2026), accuracy: 1e-9)

        d.setAllocation(BankShare.id, in: oct2026, amount: 300)
        let context = PurchaseContext.make(from: d, current: oct2026, today: now)
        XCTAssertEqual(try XCTUnwrap(context.remainingThisMonth), try XCTUnwrap(plainContext.remainingThisMonth) - 300, accuracy: 1e-9)
        XCTAssertEqual(d.estimatedUnassigned(in: oct2026), d.estimatedRemaining(in: oct2026) - 300, accuracy: 1e-9)
        XCTAssertEqual(d.unassigned(in: oct2026), d.remaining(in: oct2026) - 300, accuracy: 1e-9)
        XCTAssertEqual(BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: oct2026), plainBuffer - 300, accuracy: 1e-9)
        let free = try XCTUnwrap(d.accelerators(for: goal, current: oct2026, today: now).first { $0.id == "free" })
        XCTAssertEqual(free.change.extraMonthly, plainFree.change.extraMonthly - 300, accuracy: 1e-9)
        // Wat geld verplaatst blijft op `remaining`.
        XCTAssertEqual(d.remaining(in: oct2026), CentsMath.value(d.monthFigures(oct2026).remaining), accuracy: 1e-9)
    }

    func testTheNumbersBehindTheLabels() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 500)
        let board = MonthBoard(d, month: nov)
        let f = d.monthFigures(nov)
        XCTAssertEqual(board.left(current: nov), CentsMath.value(f.unassigned))
        XCTAssertEqual(board.left(current: nov.adding(-1)), CentsMath.value(f.unassigned), "een toekomstige maand")
        XCTAssertEqual(board.left(current: nov.adding(1)), CentsMath.value(f.remaining), "het verleden")
        XCTAssertEqual(board.left(current: nov, isPeriod: true), CentsMath.value(f.remaining), "een periode")
        XCTAssertEqual(board.distributedShown(current: nov), board.distributed)
        XCTAssertEqual(board.distributedShown(current: nov.adding(1)), board.allocated)
        XCTAssertEqual(board.income - board.expensesFromBank - board.distributedShown(current: nov), board.left(current: nov), accuracy: 1e-9)
        XCTAssertFalse(board.roundingHidesLeftSum(current: nov))
        XCTAssertFalse(board.leftIsNegative(current: nov))
        d.setAllocation(BankShare.id, in: nov, amount: 5_000)
        let over = MonthBoard(d, month: nov)
        XCTAssertTrue(over.leftIsNegative(current: nov), "te veel aan de bankrekening toegewezen")
        XCTAssertFalse(over.leftIsNegative(current: nov.adding(1)), "in het verleden blijft wat er op de rekening bleef positief")
        let summary = d.summary(of: nov, current: nov)
        XCTAssertEqual(summary.left(current: nov), summary.unassigned)
        XCTAssertEqual(summary.left(current: nov.adding(1)), summary.remaining)
    }

    func testTheBoardWithoutABankShareReadsTheSameNumberEverywhere() {
        let (d, _) = base()
        let board = MonthBoard(d, month: nov)
        XCTAssertEqual(board.toBank, 0)
        XCTAssertEqual(board.unassigned, board.remaining)
        XCTAssertEqual(board.distributed, board.allocated)
        for current in [nov.adding(-2), nov, nov.adding(3)] {
            XCTAssertEqual(board.left(current: current), board.remaining, current.key)
            XCTAssertEqual(board.left(current: current, isPeriod: true), board.remaining, current.key)
            XCTAssertEqual(board.distributedShown(current: current), board.allocated, current.key)
        }
        XCTAssertEqual(board.closes, true)
    }

    func testThePeriodSummaryCarriesTheBankShare() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 250)
        d.setAllocation(BankShare.id, in: engDec2026, amount: 100)
        let period = d.periodSummary(.halfYear, containing: nov, current: nov)
        XCTAssertEqual(period.toBank, 350, accuracy: 1e-9)
        XCTAssertEqual(period.unassigned, period.remaining - 350, accuracy: 1e-9)
        let figures = period.figures
        XCTAssertEqual(figures.toBank, 35_000)
        XCTAssertEqual(MoneyLabels.left(figures, of: nov, current: nov, isPeriod: true), figures.remaining, "een periode toont Overgehouden")
    }

    func testTheLabelFigureForMonthFutureAndPastAndPeriod() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 400)
        let f = d.monthFigures(nov)
        XCTAssertNotEqual(f.unassigned, f.remaining)
        XCTAssertEqual(MoneyLabels.left(f, of: nov, current: nov), f.unassigned, "de huidige maand")
        XCTAssertEqual(MoneyLabels.left(f, of: nov, current: oct2026), f.unassigned, "een komende maand")
        XCTAssertEqual(MoneyLabels.left(f, of: nov, current: engDec2026), f.remaining, "een maand in het verleden")
        XCTAssertEqual(MoneyLabels.left(f, of: nov, current: oct2026, isPeriod: true), f.remaining, "een periode")
        XCTAssertEqual(MoneyLabels.remainingLabel(of: nov, current: oct2026), "Nog te verdelen")
        XCTAssertEqual(MoneyLabels.remainingLabel(of: nov, current: engDec2026), "Overgehouden")
        XCTAssertEqual(MoneyLabels.remainingLabel(of: nov, current: oct2026, isPeriod: true), "Overgehouden")
    }

    func testTheBankRowFollowsThePotRules() {
        var (d, _) = base()
        // Een percentage plus een extra bedrag, zoals een pot; de grondslag komt van de rij zelf.
        d.setAllocationPercent(BankShare.id, in: nov, percent: 10, basis: .allIncome, extra: 20)
        XCTAssertEqual(d.allocationRule(BankShare.id, in: nov), .percent(PercentRule(percent: 10, basis: .allIncome, extra: 20)))
        XCTAssertEqual(d.monthFigures(nov).toBank, 32_000)
        XCTAssertTrue(d.effectiveAllocation(BankShare.id, in: nov).isOverride)
        AllocationEdit.resetToStandard(&d, id: BankShare.id, month: nov)
        XCTAssertEqual(d.monthFigures(nov).toBank, 0)
        XCTAssertFalse(AllocationEdit.differsFromStandard(d, id: BankShare.id, month: nov))
        // De percentages van de bankrij tellen mee in de waarschuwing voor percentages boven 100%.
        d.setAllocationPercent(BankShare.id, in: nov, percent: 60, basis: .salary)
        var pot = d.pots[0]
        pot.contributionMode = .percentage
        pot.contributionPercent = 50
        d.updatePot(pot, current: oct2026)
        XCTAssertEqual(d.percentTotal(in: nov), 110)
        XCTAssertTrue(d.allocationWarnings(in: nov).contains { $0.isPercentageWarning })
        // De bankrij heeft geen overschrijfdag en geen delen: er is geen stuk om te verdelen.
        XCTAssertTrue(d.uncountedTransferSlices(for: BankShare.id, in: nov).isEmpty)
        XCTAssertEqual(d.standardTransferParts(of: BankShare.id), [])
        XCTAssertEqual(BankShare().extraTransfers, [])
    }

    func testANewStandardForTheBankShareKeepsThePast() {
        var (d, _) = base()
        d.materialize(upTo: nov)
        d.setContributionAmount(BankShare.id, amount: 100, current: nov)
        XCTAssertEqual(d.monthFigures(oct2026).toBank, 0, "oktober was al vastgelegd zonder bankdeel")
        XCTAssertEqual(d.monthFigures(nov).toBank, 10_000)
        XCTAssertEqual(d.monthFigures(engDec2026).toBank, 10_000)
        // Een tweede wijziging in december laat november staan.
        d.setContributionPercent(BankShare.id, percent: 5, basis: .salary, current: engDec2026)
        XCTAssertEqual(d.monthFigures(nov).toBank, 10_000)
        XCTAssertEqual(d.monthFigures(engDec2026).toBank, 15_000)
        // Zonder bankrij in een maand die later wordt vastgelegd zit de standaard er gewoon in.
        d.materialize(upTo: engJan2027)
        XCTAssertNotNil(d.months[engJan2027.key]?.percentAllocations[BankShare.key])
    }

    func testSendingTheRestToTheBankNeedsSomethingLeft() {
        var (d, _) = base()
        d.setAllocation(BankShare.id, in: nov, amount: 5_000)
        let before = d
        d.sendRemainingToBank(in: nov)
        XCTAssertEqual(d, before, "niets te verdelen (te veel toegewezen): er verandert niets")
        d.setAllocation(BankShare.id, in: nov, amount: 100)
        let unassigned = d.monthFigures(nov).unassigned
        d.sendRemainingToBank(in: nov)
        XCTAssertEqual(d.monthFigures(nov).toBank, 10_000 + unassigned, "het huidige bedrag plus wat nog te verdelen was")
        XCTAssertEqual(d.monthFigures(nov).unassigned, 0)
        XCTAssertTrue(d.effectiveAllocation(BankShare.id, in: nov).isOverride)
    }

    func testTheBankShareMovesTheBorderOfOverAllocation() {
        var (d, _) = base()
        // 3.000 − 900 huur − 200 pot = 1.900 over; 1.900 aan de bankrekening past precies, 1.901 is een cent te veel.
        d.setAllocation(BankShare.id, in: nov, amount: 1_800)
        XCTAssertEqual(d.monthFigures(nov).overAllocated, 0)
        XCTAssertTrue(d.allocationWarnings(in: nov).isEmpty)
        d.setAllocation(BankShare.id, in: nov, amount: 1_900.01)
        XCTAssertEqual(d.monthFigures(nov).overAllocated, 1)
        XCTAssertEqual(d.monthFigures(nov).unassigned, -1)
        XCTAssertEqual(d.allocationWarnings(in: nov).count, 1)
    }
}
