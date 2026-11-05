import XCTest
import Foundation
@testable import MyBuddyCore

/// D2 (docs/work/plan2.md par. 2.2): extra overschrijfdata. Een deel van de inleg gaat op een eigen dag over; `TransferMath.slices` is
/// de ENIGE plek die een inleg over dagen verdeelt, en het geld beweegt pas op die dag (bank, pot, belegging, dagboek).
final class TransferPartsTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)
    private let feb = YearMonth(year: 2027, month: 2)

    private func dataWithPot(monthly: Double = 200, transferDay: Int? = 25) -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Vakantie", monthlyContribution: monthly, startMonth: oct2026)
        pot.transferDay = transferDay
        d.addPot(pot, openingBalance: 0, now: day(oct2026, 1))
        return (d, pot)
    }

    // MARK: D2: de stukken

    private func slices(_ total: Int, _ parts: [(Int, Double)], standard: Int, in month: YearMonth) -> [[Int]] {
        TransferMath.slices(totalCents: total, parts: parts.map { TransferPart(day: $0.0, amount: $0.1) },
                            standardDay: standard, month: month).map { [$0.day, $0.cents] }
    }

    func testSlicesWithoutPartsAreOneTransfer() {
        XCTAssertEqual(slices(20_000, [], standard: 25, in: nov), [[25, 20_000]])
        XCTAssertEqual(slices(0, [(10, 50)], standard: 25, in: nov), [])
    }

    func testSlicesCarvePartsOutOfTheTotal() {
        XCTAssertEqual(slices(20_000, [(10, 50)], standard: 25, in: nov), [[10, 5_000], [25, 15_000]])
        XCTAssertEqual(slices(20_000, [(10, 50), (3, 20)], standard: 25, in: nov), [[3, 2_000], [10, 5_000], [25, 13_000]])
    }

    func testPartsOnTheStandardDayMergeIntoOneTransfer() {
        let result = TransferMath.slices(totalCents: 20_000, parts: [TransferPart(day: 25, amount: 50)], standardDay: 25, month: nov)
        XCTAssertEqual(result, [TransferSlice(day: 25, cents: 20_000, isStandard: true)])
    }

    func testPartsLargerThanTheTotalAreCutAndNothingRemains() {
        XCTAssertEqual(slices(10_000, [(10, 70), (20, 70)], standard: 25, in: nov), [[10, 7_000], [20, 3_000]])
        XCTAssertEqual(slices(10_000, [(10, 500)], standard: 25, in: nov), [[10, 10_000]])
        XCTAssertEqual(TransferMath.overflowCents(totalCents: 10_000, parts: [TransferPart(day: 10, amount: 70), TransferPart(day: 20, amount: 70)]), 4_000)
    }

    func testDay31InAShortMonthIsTheLastDay() {
        XCTAssertEqual(slices(20_000, [(31, 50), (30, 10)], standard: 15, in: feb), [[15, 14_000], [28, 6_000]])
        XCTAssertEqual(slices(20_000, [(31, 50)], standard: 31, in: feb), [[28, 20_000]])
    }

    func testNegativeAndZeroTotalsHaveNoParts() {
        XCTAssertEqual(slices(-5_000, [(10, 50)], standard: 25, in: nov), [[25, -5_000]])
        XCTAssertEqual(slices(5_000, [(10, 0), (12, -3)], standard: 25, in: nov), [[25, 5_000]])
    }

    func testNormalizedMergesSortsAndLimits() {
        let parts = TransferMath.normalized([TransferPart(day: 20, amount: 10), TransferPart(day: 5, amount: 5),
                                             TransferPart(day: 20, amount: 2.5), TransferPart(day: 40, amount: 1),
                                             TransferPart(day: 7, amount: 0)])
        XCTAssertEqual(parts, [TransferPart(day: 5, amount: 5), TransferPart(day: 20, amount: 12.5), TransferPart(day: 31, amount: 1)])
        let many = (1...20).map { TransferPart(day: min($0, 31), amount: 1) }
        XCTAssertEqual(TransferMath.normalized(many).count, TransferMath.maxParts)
    }

    // MARK: D2: het geld beweegt pas op de dag

    func testPotAndBankMoveOnlyOnTheDayOfAPart() {
        var (d, pot) = dataWithPot(monthly: 200, transferDay: 25)
        d.pots[0].extraTransfers = [TransferPart(day: 10, amount: 50)]
        d.addBankSnapshot(balance: 1_000, note: "Begin", date: day(oct2026, 1))
        func potBalance(_ n: Int) -> Double { d.potBalance(pot.id, asOf: day(nov, n)) }
        func bank(_ n: Int) -> Double? { d.bankBalance(on: day(nov, n)) }
        XCTAssertEqual(potBalance(9), 200)        // oktober is al overgeschreven (200 op de 25e)
        XCTAssertEqual(potBalance(10), 250)       // het deel van 50 op de 10e
        XCTAssertEqual(potBalance(24), 250)
        XCTAssertEqual(potBalance(25), 400)       // de rest van 150 op de 25e
        let before = bank(9)!
        XCTAssertEqual(bank(10)!, before - 50 + 0)  // alleen het deel gaat van de bank
        XCTAssertEqual(d.eventsOnDay(day(nov, 10)).filter { $0.kind == .toPot }.map { $0.bankAmount }, [-50])
        XCTAssertEqual(d.eventsOnDay(day(nov, 25)).filter { $0.kind == .toPot }.map { $0.potAmount }, [150])
        let ids = d.dayEvents(in: nov).filter { $0.kind == .toPot }.map { $0.id }
        XCTAssertEqual(ids, ["toPot-\(pot.id.uuidString)-2026-11-10", "toPot-\(pot.id.uuidString)-2026-11"])
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
    }

    func testTheMonthTotalDoesNotDependOnTheParts() {
        var (d, pot) = dataWithPot()
        let plain = d.monthFigures(nov)
        d.pots[0].extraTransfers = [TransferPart(day: 3, amount: 30), TransferPart(day: 31, amount: 40)]
        XCTAssertEqual(d.monthFigures(nov), plain)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 20_000)
        XCTAssertEqual(d.potBalance(pot.id, at: nov), 400)
    }

    func testAMonthOverrideReplacesTheStandardAndAnEmptyListClearsIt() {
        var (d, pot) = dataWithPot()
        d.pots[0].extraTransfers = [TransferPart(day: 10, amount: 50)]
        d.setTransferParts(pot.id, in: nov, parts: [TransferPart(day: 5, amount: 80)])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov, totalCents: 20_000).map { [$0.day, $0.cents] }, [[5, 8_000], [25, 12_000]])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: engDec2026, totalCents: 20_000).map { [$0.day, $0.cents] }, [[10, 5_000], [25, 15_000]])
        d.setTransferParts(pot.id, in: nov, parts: [])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov, totalCents: 20_000).map { [$0.day, $0.cents] }, [[25, 20_000]])
        d.clearTransferParts(pot.id, in: nov)
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov, totalCents: 20_000).map { [$0.day, $0.cents] }, [[10, 5_000], [25, 15_000]])
    }

    func testChangingTheStandardPartsKeepsThePast() {
        var (d, pot) = dataWithPot()
        d.materialize(upTo: nov)
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 10, amount: 50)], current: nov)
        // Oktober (vóór de lopende maand) houdt zijn oude, lege lijst; november en later volgen de nieuwe standaard.
        XCTAssertEqual(d.transferSlices(for: pot.id, in: oct2026, totalCents: 20_000).map { [$0.day, $0.cents] }, [[25, 20_000]])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov, totalCents: 20_000).map { [$0.day, $0.cents] }, [[10, 5_000], [25, 15_000]])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: engDec2026, totalCents: 20_000).count, 2)
        // Daarna weer wijzigen: november blijft zoals het was in december.
        d.setStandardTransferParts(pot.id, parts: [], current: engDec2026)
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov, totalCents: 20_000).count, 2)
        XCTAssertEqual(d.transferSlices(for: pot.id, in: engDec2026, totalCents: 20_000).count, 1)
    }

    func testTheStartDateDropsEarlyPartsOnly() {
        var (d, pot) = dataWithPot()
        d.pots[0].extraTransfers = [TransferPart(day: 10, amount: 50), TransferPart(day: 20, amount: 30)]
        d.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        // Oktober: het deel van de 10e telt niet, dat van de 20e en de rest op de 25e wel.
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 15_000)
        XCTAssertEqual(d.monthFigures(oct2026).saved, 15_000)
        XCTAssertEqual(d.dayEvents(in: oct2026).filter { $0.kind == .toPot }.map { $0.day }, [20, 25])
        XCTAssertTrue(d.monthLedger(oct2026).allReconciles)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 20_000)
    }

    func testAStartDateAfterTheStandardDayButBeforeAPartKeepsOnlyThePart() {
        var (d, pot) = dataWithPot(monthly: 200, transferDay: 5)
        d.pots[0].extraTransfers = [TransferPart(day: 20, amount: 60)]
        d.setStart(CalendarDay(year: 2026, month: 10, day: 12))
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 6_000)
        XCTAssertEqual(d.dayEvents(in: oct2026).filter { $0.kind == .toPot }.map { $0.day }, [20])
        XCTAssertTrue(d.monthLedger(oct2026).allReconciles)
    }

    func testPercentageLinesSplitToo() {
        var (d, pot) = dataWithPot()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 50, current: oct2026)
        d.pots[0].extraTransfers = [TransferPart(day: 1, amount: 100)]
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov, totalCents: d.allocationCents(pot.id, in: nov)).map { [$0.day, $0.cents] },
                       [[1, 10_000], [25, 25_000]])
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
    }

    func testHoldingValueCountsAPartFromItsDay() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var h = Holding(name: "Wereld", kind: .etf, monthlyContribution: 300, startMonth: oct2026)
        h.transferDay = 25
        h.extraTransfers = [TransferPart(day: 10, amount: 100)]
        d.holdings = [h]
        d.addSnapshot(holdingID: h.id, value: 1_000, invested: 1_000, date: day(oct2026, 1))
        h = d.holdings[0]
        // Het meetpunt van 1 oktober bevat de inleg van oktober al; november telt per dag: op de 10e komt 100 erbij, op de 25e de rest.
        XCTAssertEqual(d.holdingStateNow(h, current: nov, today: day(nov, 9))?.value, 1_000)
        XCTAssertEqual(d.holdingStateNow(h, current: nov, today: day(nov, 10))?.value, 1_100)
        XCTAssertEqual(d.holdingStateNow(h, current: nov, today: day(nov, 25))?.value, 1_300)
        XCTAssertEqual(d.holdingStateNow(h, current: nov)?.value, 1_300)
    }

    func testPotTimelineShowsEachPartOnItsDate() {
        var (d, pot) = dataWithPot()
        d.pots[0].extraTransfers = [TransferPart(day: 10, amount: 50)]
        let items = d.potTimeline(pot.id, current: nov, asOf: day(nov, 12)).filter { $0.kind == .allocation && YearMonth(date: $0.date) == nov }
        XCTAssertEqual(items.map { $0.amount }.sorted(), [50, 150])
        XCTAssertEqual(items.first { $0.amount == 50 }?.isPlanned, false)
        XCTAssertEqual(items.first { $0.amount == 150 }?.isPlanned, true)
    }

    func testDeletingAPotRemovesItsMonthParts() {
        var (d, pot) = dataWithPot()
        d.setTransferParts(pot.id, in: nov, parts: [TransferPart(day: 5, amount: 10)])
        d.deletePot(pot.id)
        XCTAssertTrue(d.months[nov.key]?.transferParts.isEmpty ?? true)
    }

    func testMakeStandardAndResetCoverTheParts() {
        var (d, pot) = dataWithPot()
        d.setTransferParts(pot.id, in: nov, parts: [TransferPart(day: 5, amount: 80)])
        XCTAssertTrue(AllocationEdit.differsFromStandard(d, id: pot.id, month: nov))
        AllocationEdit.resetToStandard(&d, id: pot.id, month: nov)
        XCTAssertFalse(AllocationEdit.differsFromStandard(d, id: pot.id, month: nov))
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov, totalCents: 20_000).count, 1)
        d.setTransferParts(pot.id, in: engDec2026, parts: [TransferPart(day: 7, amount: 60)])
        AllocationEdit.makeStandard(&d, id: pot.id, month: engDec2026, current: oct2026)
        XCTAssertEqual(d.pots[0].extraTransfers, [TransferPart(day: 7, amount: 60)])
        XCTAssertFalse(d.hasTransferPartsOverride(pot.id, in: engDec2026), "een maand na de lopende maand volgt de standaard")
        XCTAssertEqual(d.transferSlices(for: pot.id, in: engJan2027, totalCents: 20_000).map { $0.day }, [7, 25])
    }

    func testUncountedSlicesListWhatTheStartDateDrops() {
        var (d, pot) = dataWithPot()
        d.pots[0].extraTransfers = [TransferPart(day: 10, amount: 50), TransferPart(day: 20, amount: 30)]
        XCTAssertTrue(d.uncountedTransferSlices(for: pot.id, in: oct2026).isEmpty)
        d.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(d.uncountedTransferSlices(for: pot.id, in: oct2026).map { [$0.day, $0.cents] }, [[10, 5_000]])
        XCTAssertTrue(d.uncountedTransferSlices(for: pot.id, in: nov).isEmpty)
        XCTAssertEqual(d.transferSlices(for: pot.id, in: oct2026).map { $0.day }, [10, 20, 25])
    }

    func testUpcomingBookingsShowEachPartInOrder() {
        var (d, pot) = dataWithPot()
        d.pots[0].extraTransfers = [TransferPart(day: 10, amount: 50)]
        let today = day(nov, 1)
        let items = PotUpcoming.items(d, potID: pot.id, current: nov, today: today, days: 30)
        XCTAssertEqual(items.map { $0.amount }, [50, 150])
        XCTAssertEqual(items.map { $0.daysAhead }, [9, 24])
        XCTAssertEqual(items.last?.balanceAfter, d.potBalance(pot.id, asOf: day(nov, 25)))
    }

    func testOldFilesWithoutPartsReencodeIdentically() throws {
        let (d, _) = dataWithPot()
        let encoder = FinanceStorage.makeFileEncoder()
        let text = String(decoding: try encoder.encode(d), as: UTF8.self)
        XCTAssertFalse(text.contains("extraTransfers"))
        XCTAssertFalse(text.contains("transferParts"))
        XCTAssertFalse(text.contains("contributionExtra"))
        XCTAssertFalse(text.contains("bankShare"))
        var withParts = d
        withParts.pots[0].extraTransfers = [TransferPart(day: 10, amount: 50)]
        withParts.setTransferParts(withParts.pots[0].id, in: nov, parts: [TransferPart(day: 5, amount: 10)])
        let round = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: try encoder.encode(withParts))
        XCTAssertEqual(round.pots[0].extraTransfers, withParts.pots[0].extraTransfers)
        XCTAssertEqual(round.months[nov.key]?.transferParts, withParts.months[nov.key]?.transferParts)
    }

    // MARK: Randgevallen

    func testSetTransferPartsEqualToTheStandardClearsTheOverride() {
        var (d, pot) = dataWithPot()
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 10, amount: 40)], current: oct2026)
        d.setTransferParts(pot.id, in: nov, parts: [TransferPart(day: 5, amount: 30)])
        XCTAssertTrue(d.hasTransferPartsOverride(pot.id, in: nov))
        d.setTransferParts(pot.id, in: nov, parts: [TransferPart(day: 10, amount: 40), TransferPart(day: 20, amount: 0)])
        XCTAssertFalse(d.hasTransferPartsOverride(pot.id, in: nov), "gelijk aan de standaard (een deel van 0 telt niet): geen afwijking")
        // De maand volgt de standaard, ook als die later verandert.
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 12, amount: 20)], current: nov)
        XCTAssertEqual(d.transferParts(for: pot.id, in: nov), [TransferPart(day: 12, amount: 20)])
        // Een lege lijst terwijl de standaard delen heeft is wel een afwijking: deze maand alles op de standaarddag.
        d.setTransferParts(pot.id, in: engDec2026, parts: [])
        XCTAssertTrue(d.hasTransferPartsOverride(pot.id, in: engDec2026))
        XCTAssertEqual(d.transferSlices(for: pot.id, in: engDec2026).count, 1)
        // Zonder delen en zonder standaard bestaat een lege lijst niet als afwijking.
        var (e, other) = dataWithPot()
        e.setTransferParts(other.id, in: nov, parts: [])
        XCTAssertFalse(e.hasTransferPartsOverride(other.id, in: nov))
    }

    func testFebruaryInALeapYearAndAShortMonth() {
        let parts = [TransferPart(day: 31, amount: 10)]
        func partDay(_ month: YearMonth) -> Int? {
            TransferMath.slices(totalCents: 5_000, parts: parts, standardDay: 25, month: month).first { !$0.isStandard }?.day
        }
        XCTAssertEqual(partDay(YearMonth(year: 2028, month: 2)), 29, "schrikkeljaar")
        XCTAssertEqual(partDay(YearMonth(year: 2027, month: 2)), 28)
        XCTAssertEqual(partDay(YearMonth(year: 2026, month: 4)), 30)
        XCTAssertEqual(partDay(YearMonth(year: 2026, month: 3)), 31)
        // De standaarddag zelf wordt ook geklemd: een deel op dag 28 in februari valt dan met de rest samen.
        let merged = TransferMath.slices(totalCents: 5_000, parts: [TransferPart(day: 28, amount: 10)], standardDay: 31,
                                         month: YearMonth(year: 2027, month: 2))
        XCTAssertEqual(merged.map { $0.day }, [28])
        XCTAssertEqual(merged.map { $0.cents }, [5_000])
        // Het opgeslagen deel blijft dag 31: het volgt elke maand zijn eigen lengte.
        var (d, pot) = dataWithPot()
        d.setStandardTransferParts(pot.id, parts: parts, current: oct2026)
        XCTAssertEqual(d.transferParts(for: pot.id, in: feb), [TransferPart(day: 31, amount: 10)])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: feb).map { $0.day }, [25, 28])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov).map { $0.day }, [25, 30])
        XCTAssertEqual(d.transferSlices(for: pot.id, in: engDec2026).map { $0.day }, [25, 31])
    }

    func testAPartOnTheFirstOfTheMonthAndInterest() throws {
        // De rente rekent met het saldo aan het eind van de eerste dag van de maand: een deel op de 1e telt dus al mee voor de rente
        // van die maand, de inleg op de 25e pas voor de maand erna.
        func interest(_ d: FinanceData, _ pot: Pot, _ month: YearMonth) -> Double {
            d.interestPayments(for: pot.id, from: month.firstDay, to: day(month, month.dayCount), asOf: day(oct2026, 1)).first?.amount ?? 0
        }
        var (plain, plainPot) = dataWithPot()
        plain.pots[0].interestRate = 0.12
        plain.pots[0].interestPayout = .monthly
        plain.pots[0].interestPayoutDay = 28
        var (withPart, partPot) = dataWithPot()
        withPart.pots[0].interestRate = 0.12
        withPart.pots[0].interestPayout = .monthly
        withPart.pots[0].interestPayoutDay = 28
        withPart.pots[0].extraTransfers = [TransferPart(day: 1, amount: 50)]
        XCTAssertEqual(interest(plain, plainPot, oct2026), 0, "niets op de eerste dag van oktober: geen rente")
        XCTAssertEqual(interest(withPart, partPot, oct2026), 0.5, accuracy: 1e-9, "50 op de 1e: 12% per jaar is 1% per maand")
        XCTAssertEqual(interest(plain, plainPot, nov), 2, accuracy: 1e-9, "de inleg van oktober (200) staat er op 1 november")
        XCTAssertEqual(interest(withPart, partPot, nov), 2.51, accuracy: 1e-9,
                       "200 uit oktober, het deel van 50 op 1 november en de rente van oktober (0,50) die op de 28e is bijgeschreven")
        XCTAssertTrue(withPart.monthLedger(nov).allReconciles)
        XCTAssertEqual(withPart.potBalance(partPot.id, asOf: day(nov, 1)), plain.potBalance(plainPot.id, asOf: day(nov, 1)) + 50 + 0.5,
                       accuracy: 1e-9)
    }

    func testAnExtraDateBeforeTheStartDateInsideTheStartMonth() {
        // 10% van 3.000 plus 50 is 350; een deel van 100 op de 3e valt vóór de startdatum (15 oktober) en telt niet mee.
        var (d, pot) = dataWithPot(monthly: 0)
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, extra: 50, current: oct2026)
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 3, amount: 100)], current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 35_000)
        d.setStart(CalendarDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(d.allocationCents(pot.id, in: oct2026), 25_000, "alleen de rest op de 25e telt")
        XCTAssertEqual(d.allocationTotalCents(d.pots[0], key: pot.id.uuidString, in: oct2026, storedPlan: d.months[oct2026.key],
                                              basesFor: { d.incomeBases(in: oct2026) }), 35_000, "het geheel zonder startfilter")
        XCTAssertEqual(d.monthFigures(oct2026).saved, 25_000)
        XCTAssertEqual(d.dayEvents(in: oct2026).filter { $0.kind == .toPot }.map { $0.day }, [25])
        let uncounted = d.uncountedTransferSlices(for: pot.id, in: oct2026)
        XCTAssertEqual(uncounted.map { [$0.day, $0.cents] }, [[3, 10_000]])
        XCTAssertEqual(TransferPartsText.beforeStartNote(uncounted), "Telt niet mee: " + Fmt.euro(100) + " op de 3e valt vóór je startdatum.")
        XCTAssertTrue(d.monthLedger(oct2026).allReconciles)
        // De maand erna rekent gewoon met beide stukken.
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 35_000)
        XCTAssertEqual(d.dayEvents(in: nov).filter { $0.kind == .toPot }.map { $0.day }, [3, 25])
    }

    func testTwelvePartsAreTheLimit() {
        let many = (1...15).map { TransferPart(day: $0, amount: 1) }
        var (d, pot) = dataWithPot()
        d.setStandardTransferParts(pot.id, parts: many, current: oct2026)
        XCTAssertEqual(d.pots[0].extraTransfers.count, TransferMath.maxParts, "de standaard bewaart hoogstens twaalf delen")
        XCTAssertEqual(d.pots[0].extraTransfers.map { $0.day }, Array(1...12))
        d.setTransferParts(pot.id, in: engDec2026, parts: (10...30).map { TransferPart(day: $0, amount: 1) })
        XCTAssertEqual(d.transferParts(for: pot.id, in: engDec2026).count, 12)
        // Twaalf delen van 1 euro en een rest van 188: dertien overschrijvingen, samen precies de inleg.
        let slices = d.transferSlices(for: pot.id, in: nov)
        XCTAssertEqual(slices.count, 13)
        XCTAssertEqual(slices.reduce(0) { $0 + $1.cents }, 20_000)
        XCTAssertEqual(d.dayEvents(in: nov).filter { $0.kind == .toPot }.count, 13)
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
        XCTAssertEqual(TransferMath.overflowCents(totalCents: 20_000, parts: many), 0)
    }

    func testPartsWithAZeroPercentageAndAnExtraAmount() {
        var (d, pot) = dataWithPot(monthly: 0)
        d.setContributionPercent(pot.id, percent: 0, basis: .salary, extra: 80, current: oct2026)
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 10, amount: 30)], current: oct2026)
        XCTAssertEqual(d.allocationCents(pot.id, in: nov), 8_000)
        XCTAssertEqual(d.transferSlices(for: pot.id, in: nov).map { [$0.day, $0.cents] }, [[10, 3_000], [25, 5_000]])
        // Zonder inkomen blijft alleen het extra bedrag over en ook dat verdeelt zich over de dagen.
        var empty = FinanceData(startMonth: oct2026)
        var potNoIncome = Pot(name: "Spaar", monthlyContribution: 0, startMonth: oct2026)
        potNoIncome.contributionMode = .percentage
        potNoIncome.contributionPercent = 20
        potNoIncome.contributionExtra = 80
        potNoIncome.extraTransfers = [TransferPart(day: 10, amount: 30)]
        empty.addPot(potNoIncome)
        XCTAssertEqual(empty.transferSlices(for: potNoIncome.id, in: nov).map { $0.cents }.reduce(0, +), 8_000)
        XCTAssertEqual(empty.transferSlices(for: potNoIncome.id, in: nov).map { $0.day }.first, 10)
    }

    func testTheEventIDsOfTheStandardDayStayTheSameAndAPartAddsTheDay() {
        var (d, pot) = dataWithPot()
        let plain = d.dayEvents(in: nov).filter { $0.kind == .toPot }.map { $0.id }
        XCTAssertEqual(plain, ["toPot-\(pot.id.uuidString)-2026-11"])
        d.pots[0].extraTransfers = [TransferPart(day: 5, amount: 20), TransferPart(day: 12, amount: 20)]
        let ids = d.dayEvents(in: nov).filter { $0.kind == .toPot }.map { $0.id }
        XCTAssertEqual(ids, ["toPot-\(pot.id.uuidString)-2026-11-05", "toPot-\(pot.id.uuidString)-2026-11-12", "toPot-\(pot.id.uuidString)-2026-11"])
        XCTAssertTrue(ids.contains(plain[0]), "het id van de standaarddag blijft")
        XCTAssertEqual(FinanceData.transferEventID(prefix: "toHolding", id: pot.id, month: nov, slice: TransferSlice(day: 7, cents: 1, isStandard: false)),
                       "toHolding-\(pot.id.uuidString)-2026-11-07")
    }

    func testAPotWithPartsKeepsTheSumsOfTheMonthAndTheWholeLedgerClosed() {
        var (d, pot) = dataWithPot()
        d.addBankSnapshot(balance: 2_000, note: "Begin", date: day(oct2026, 1))
        d.pots[0].extraTransfers = [TransferPart(day: 3, amount: 50), TransferPart(day: 31, amount: 25)]
        let plain = d.monthFigures(nov)
        for month in [oct2026, nov, engDec2026, engJan2027, feb] {
            let ledger = d.monthLedger(month, asOf: day(oct2026, 1))
            XCTAssertTrue(ledger.allReconciles, month.key)
            XCTAssertEqual(ledger.planToPots, 200, accuracy: 1e-9, month.key)
        }
        XCTAssertEqual(d.monthFigures(nov), plain)
        XCTAssertEqual(d.potBalance(pot.id, at: feb), 1_000, accuracy: 1e-9, "vijf maanden van 200")
    }
}
