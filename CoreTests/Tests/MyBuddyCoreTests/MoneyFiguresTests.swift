import XCTest
import Foundation
@testable import MyBuddyCore

/// De hulpjes voor de schermen (`App/UI/MoneyFigures.swift`): de cijfers van Home sluiten, de inleg als percentage komt overal
/// op hetzelfde uit, en de komende boekingen van een spaarpot lopen door tot precies het saldo van de motor.
final class MoneyFiguresTests: XCTestCase {
    // MARK: Hulpmiddelen

    /// Start oktober 2026, salaris 3000 op de 25e, huur 1000 op de 1e, een bonus van 500 op de 20e. Eén pot Vakantie met
    /// beginsaldo 400 en een vaste inleg van 200 (op de 25e).
    private func baseData() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.upsertLine(MoneyLine(name: "Huur", amount: 1_000, isRecurring: true, day: 1), kind: .expense, in: oct2026)
        d.upsertLine(MoneyLine(name: "Bonus", amount: 500, day: 20), kind: .income, in: oct2026)
        let pot = Pot(name: "Vakantie", monthlyContribution: 200, startMonth: oct2026)
        d.addPot(pot, openingBalance: 400, now: engTime(oct2026, 1, hour: 8))
        return (d, pot)
    }

    private func cents(_ value: Double) -> Int { engCents(value) }

    // MARK: Home: de cijfers van een maand

    func testMonthBoardMatchesTheEngineAndCloses() {
        var (d, pot) = baseData()
        // Een uitgave van 300 waarvan 120 uit de pot komt, en een deel van het inkomen als percentage naar een belegging.
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 300, day: 12, potShares: [PotShare(potID: pot.id, amount: 120)]),
                     kind: .expense, in: oct2026)
        let holding = Holding(name: "Wereld", monthlyContribution: 0, startMonth: oct2026)
        d.addHolding(holding)
        d.setContributionPercent(holding.id, percent: 12.5, basis: .salary, current: oct2026)

        let board = MonthBoard(d, month: oct2026)
        XCTAssertEqual(board.income, d.income(in: oct2026))
        XCTAssertEqual(board.income, 3_500)
        XCTAssertEqual(board.expensesTotal, d.expensesTotal(in: oct2026))
        XCTAssertEqual(board.expensesTotal, 1_300)
        XCTAssertEqual(board.fromPots, d.expensesFromPots(in: oct2026))
        XCTAssertEqual(board.fromPots, 120)
        XCTAssertEqual(board.expensesFromBank, d.expensesFromBank(in: oct2026))
        XCTAssertEqual(board.expensesFromBank, 1_180)
        XCTAssertEqual(board.saved, d.savedTotal(in: oct2026))
        XCTAssertEqual(board.invested, d.investedTotal(in: oct2026))
        XCTAssertEqual(board.invested, 375, "12,5% van het salaris van 3000")
        XCTAssertEqual(board.allocated, 575)
        XCTAssertEqual(board.remaining, d.remaining(in: oct2026))
        XCTAssertEqual(board.remaining, 3_500 - 1_180 - 575)
        XCTAssertEqual(board.available, 3_500 - 1_180)
        XCTAssertTrue(board.closes)
        XCTAssertTrue(board.hasPotExpenses)
        XCTAssertFalse(board.isNegative)
        XCTAssertEqual(cents(board.income) - cents(board.expensesFromBank) - cents(board.allocated), cents(board.remaining),
                       "inkomen min uitgaven van de bank min verdeeld is nog te verdelen")
        // Hetzelfde getal als in het maandoverzicht en in het dagboek.
        XCTAssertEqual(d.summary(of: oct2026, current: oct2026).remaining, board.remaining)
        XCTAssertEqual(d.monthLedger(oct2026, asOf: engTime(oct2026, 10, hour: 9)).remaining, board.remaining)
    }

    func testMonthBoardNegativeAndOverAllocated() {
        var (d, pot) = baseData()
        // Meer verdeeld dan er is: 200 vast + 100% van het salaris.
        d.setContributionPercent(pot.id, percent: 100, basis: .salary, current: oct2026)
        d.addHolding(Holding(name: "Extra", monthlyContribution: 500, startMonth: oct2026))
        let board = MonthBoard(d, month: oct2026)
        XCTAssertTrue(board.isNegative)
        XCTAssertFalse(board.spendingExceedsIncome, "de uitgaven passen in het inkomen: er is te veel verdeeld")
        XCTAssertGreaterThan(board.overAllocated, 0)
        XCTAssertTrue(board.closes)
        XCTAssertEqual(board.remaining, d.remaining(in: oct2026))

        // Alleen te hoge uitgaven.
        var e = FinanceData(startMonth: oct2026)
        e.upsertLine(MoneyLine(name: "Huur", amount: 900, isRecurring: true, day: 1), kind: .expense, in: oct2026)
        let spent = MonthBoard(e, month: oct2026)
        XCTAssertTrue(spent.isNegative)
        XCTAssertTrue(spent.spendingExceedsIncome)
        XCTAssertEqual(spent.overAllocated, 0)
        XCTAssertTrue(spent.closes)
    }

    func testMonthBoardBeforeTheStartMonthIsEmpty() {
        let (d, _) = baseData()
        let board = MonthBoard(d, month: oct2026.adding(-1))
        XCTAssertEqual(board.figures, MonthFigures())
        XCTAssertEqual(board.remaining, 0)
        XCTAssertTrue(board.closes)
    }

    func testMonthBoardClosesForEveryScenario() {
        var checked = 0
        for seed in 0..<150 {
            let s = ledgerScenario(seed: UInt64(seed))
            for month in s.months {
                let board = MonthBoard(s.data, month: month)
                XCTAssertTrue(board.closes, "zaad \(seed) \(month.key)")
                XCTAssertEqual(cents(board.remaining), cents(s.data.remaining(in: month)), "zaad \(seed) \(month.key)")
                XCTAssertEqual(cents(board.income) - cents(board.expensesFromBank) - cents(board.allocated),
                               cents(board.remaining), "zaad \(seed) \(month.key)")
                XCTAssertEqual(cents(board.remaining), cents(s.data.summary(of: month, current: month).remaining),
                               "zaad \(seed) \(month.key)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 500)
    }

    func testHomeFiguresEqualTheDayBookForEveryScenario() {
        // Home leest de maand uit `MonthBoard`, de pagina Dag voor dag uit het dagboek: zelfde cijfers, op de cent.
        var checked = 0
        for seed in 0..<70 {
            let s = ledgerScenario(seed: UInt64(seed))
            for month in s.months.prefix(3) {
                let board = MonthBoard(s.data, month: month)
                let ledger = s.data.monthLedger(month, asOf: s.today)
                let tag = "zaad \(seed) \(month.key)"
                XCTAssertEqual(cents(board.income), cents(ledger.income), "inkomen: \(tag)")
                XCTAssertEqual(cents(board.expensesTotal), cents(ledger.expensesTotal), "uitgaven: \(tag)")
                XCTAssertEqual(cents(board.expensesFromBank), cents(ledger.expensesFromBank), "bankuitgaven: \(tag)")
                XCTAssertEqual(cents(board.fromPots), cents(ledger.expensesFromPots), "uit potten: \(tag)")
                XCTAssertEqual(cents(board.saved), cents(ledger.saved), "gespaard: \(tag)")
                XCTAssertEqual(cents(board.invested), cents(ledger.invested), "belegd: \(tag)")
                XCTAssertEqual(cents(board.remaining), cents(ledger.remaining), "over: \(tag)")
                XCTAssertTrue(ledger.overviewReconciles, "het dagboek sluit met het maandoverzicht: \(tag)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 150)
    }

    // MARK: Perioden

    func testPeriodFiguresEqualThePeriodSummary() {
        var (d, pot) = baseData()
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 300, day: 12, potShares: [PotShare(potID: pot.id, amount: 120)]),
                     kind: .expense, in: oct2026)
        d.materialize(upTo: oct2026.adding(2))
        for mode in PeriodMode.allCases {
            let period = d.periodSummary(mode, containing: oct2026, current: oct2026)
            let f = period.figures
            XCTAssertEqual(CentsMath.value(f.remaining), period.remaining, "\(mode)")
            XCTAssertEqual(CentsMath.value(f.income), period.income, "\(mode)")
            XCTAssertEqual(CentsMath.value(f.expenses - f.fromPots), CentsMath.value(CentsMath.int(period.expenses) - CentsMath.int(period.fromPots)), "\(mode)")
            XCTAssertEqual(CentsMath.value(f.available), CentsMath.value(CentsMath.int(period.income) - CentsMath.int(period.expenses) + CentsMath.int(period.fromPots)), "\(mode)")
        }
        // Eén maand: dezelfde cijfers als `MonthBoard`.
        let month = d.periodSummary(.month, containing: oct2026, current: oct2026)
        XCTAssertEqual(month.figures, MonthBoard(d, month: oct2026).figures)
    }

    func testSalaryOfSeveralMonthsWithAnEveryFourWeeksSalary() {
        var (d, _) = baseData()
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        d.materialize(upTo: oct2026.adding(3))
        let months = oct2026.range(count: 4)
        let salary = CentsMath.sum(months.map { CentsMath.int(d.salaryAmount(in: $0)) })
        // Elke 4 weken vanaf 2 oktober: 2 okt, 30 okt, 27 nov, 25 dec en 22 jan. Oktober telt twee uitbetalingen, de andere
        // drie maanden elk één: vijf van 3000.
        XCTAssertEqual(CentsMath.value(salary), 3_000 * 5)
    }

    func testSalaryNoteNamesTheDaysOfAnEveryFourWeeksSalary() {
        var (d, _) = baseData()
        XCTAssertNil(MonthBoard(d, month: oct2026).salaryNote, "bij het maandelijkse schema valt er niets te melden")
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        // 2 en 30 oktober, dan 27 november.
        XCTAssertEqual(MonthBoard(d, month: oct2026).salaryNote, "Salaris komt binnen op de 2e en de 30e.")
        XCTAssertEqual(MonthBoard(d, month: oct2026.adding(1)).salaryNote, "Salaris komt binnen op de 27e.")
        XCTAssertEqual(MonthBoard(d, month: oct2026).income, 6_500, "twee uitbetalingen van 3000 plus de bonus van 500")
        XCTAssertEqual(MonthBoard(d, month: oct2026).income, d.income(in: oct2026))
        // Elke 6 weken heeft januari geen uitbetaling.
        d.salary.setSchedule(.weeks, interval: 6, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        let january = YearMonth(year: 2027, month: 1)
        XCTAssertEqual(MonthBoard(d, month: january).salaryNote, "Deze maand komt er geen salaris binnen.")
        XCTAssertEqual(MonthBoard(d, month: january).income, d.income(in: january))
        // Vóór de startmaand telt niets, ook geen melding.
        XCTAssertNil(MonthBoard(d, month: oct2026.adding(-1)).salaryNote)
    }

    func testNetWorthLabelNamesTheMonth() {
        XCTAssertEqual(MoneyLabels.netWorthEnd(of: oct2026), "Vermogen eind oktober")
        XCTAssertEqual(MoneyLabels.netWorthEnd(of: YearMonth(year: 2027, month: 1)), "Vermogen eind januari")
    }

    func testRemainingLabelsFollowTheTermList() {
        // Termenlijst: "Nog te verdelen" voor nu en komende maanden, "Overgehouden" voor het verleden en voor periodes. Nooit kaal "Over".
        XCTAssertEqual(MoneyLabels.remaining, "Nog te verdelen")
        XCTAssertEqual(MoneyLabels.leftOver, "Overgehouden")
        XCTAssertEqual(MoneyLabels.remainingLabel(of: oct2026, current: oct2026), "Nog te verdelen")
        XCTAssertEqual(MoneyLabels.remainingLabel(of: oct2026.adding(2), current: oct2026), "Nog te verdelen")
        XCTAssertEqual(MoneyLabels.remainingLabel(of: oct2026.adding(-1), current: oct2026), "Overgehouden")
        XCTAssertEqual(MoneyLabels.remainingLabel(of: oct2026, current: oct2026, isPeriod: true), "Overgehouden")
    }

    // MARK: Inleg als bedrag of percentage

    func testContributionInfoForAFixedAmount() {
        let (d, pot) = baseData()
        let info = ContributionInfo(d, id: pot.id, month: oct2026)
        XCTAssertNotNil(info)
        guard let info else { return }
        XCTAssertFalse(info.isPercent)
        XCTAssertFalse(info.isOverride)
        XCTAssertEqual(info.amount, 200)
        XCTAssertEqual(info.amount, d.allocation(pot.id, in: oct2026))
        XCTAssertEqual(info.standardText, Fmt.euro(200))
        XCTAssertNil(info.base)
        XCTAssertNil(info.baseText)
        XCTAssertNil(info.averageAmount)
        XCTAssertFalse(info.hasNoBase)
        XCTAssertNil(ContributionInfo(d, id: UUID(), month: oct2026), "geen pot of belegging")
    }

    func testContributionInfoForAPercentage() {
        var (d, pot) = baseData()
        d.setContributionPercent(pot.id, percent: 10, basis: .allIncome, current: oct2026)
        let info = ContributionInfo(d, id: pot.id, month: oct2026)!
        XCTAssertTrue(info.isPercent)
        XCTAssertEqual(info.base, 3_500, "salaris plus de bonus van oktober")
        XCTAssertEqual(info.amount, 350)
        XCTAssertEqual(info.amount, d.allocation(pot.id, in: oct2026))
        XCTAssertEqual(info.baseText, "10% van \(Fmt.euro(3_500)) inkomsten in oktober")
        XCTAssertEqual(info.standardText, "10% van al je inkomsten")
        XCTAssertFalse(info.isOverride)
        XCTAssertNil(info.averageAmount, "bij het maandelijkse schema is deze maand de maat")
        // November heeft geen bonus: een ander bedrag, hetzelfde percentage.
        let nov = ContributionInfo(d, id: pot.id, month: oct2026.adding(1))!
        XCTAssertEqual(nov.base, 3_000)
        XCTAssertEqual(nov.amount, 300)
    }

    func testContributionInfoForAMonthOverride() {
        var (d, pot) = baseData()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, current: oct2026)
        d.setAllocationPercent(pot.id, in: oct2026.adding(1), percent: 20)
        let nov = ContributionInfo(d, id: pot.id, month: oct2026.adding(1))!
        XCTAssertTrue(nov.isOverride)
        XCTAssertEqual(nov.amount, 600)
        XCTAssertEqual(nov.ruleText, "20% van je salaris")
        XCTAssertEqual(nov.standardText, "10% van je salaris")
        d.setAllocation(pot.id, in: oct2026.adding(2), amount: 75)
        let dec = ContributionInfo(d, id: pot.id, month: oct2026.adding(2))!
        XCTAssertTrue(dec.isOverride)
        XCTAssertFalse(dec.isPercent)
        XCTAssertEqual(dec.amount, 75)
    }

    func testListLineOnlyForPercentages() {
        var (d, pot) = baseData()
        XCTAssertNil(ContributionInfo.listLine(d, id: pot.id, month: oct2026), "een vast bedrag krijgt geen extra regel")
        XCTAssertNil(ContributionInfo.listLine(d, id: UUID(), month: oct2026))
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, current: oct2026)
        XCTAssertEqual(ContributionInfo.listLine(d, id: pot.id, month: oct2026), "Inleg 10% van je salaris, \(Fmt.euro(300)) deze maand")
        // Een eigen percentage in november.
        d.setAllocationPercent(pot.id, in: oct2026.adding(1), percent: 20)
        XCTAssertEqual(ContributionInfo.listLine(d, id: pot.id, month: oct2026.adding(1)),
                       "Inleg 20% van je salaris, \(Fmt.euro(600)) deze maand")
        // Een eigen bedrag in december bij een standaard percentage.
        d.setAllocation(pot.id, in: oct2026.adding(2), amount: 75)
        XCTAssertEqual(ContributionInfo.listLine(d, id: pot.id, month: oct2026.adding(2)),
                       "Deze maand een eigen bedrag van \(Fmt.euro(75))")
        // Het bedrag in de regel is dat van de verdeling.
        for offset in 0..<3 {
            let month = oct2026.adding(offset)
            XCTAssertTrue(ContributionInfo.listLine(d, id: pot.id, month: month)!.contains(Fmt.euro(d.allocation(pot.id, in: month))))
        }
        // Een belegging werkt hetzelfde.
        let holding = Holding(name: "Wereld", monthlyContribution: 0, startMonth: oct2026)
        d.addHolding(holding)
        XCTAssertNil(ContributionInfo.listLine(d, id: holding.id, month: oct2026))
        d.setContributionPercent(holding.id, percent: 12.5, basis: .allIncome, current: oct2026)
        XCTAssertEqual(ContributionInfo.listLine(d, id: holding.id, month: oct2026),
                       "Inleg 12,5% van al je inkomsten, \(Fmt.euro(d.allocation(holding.id, in: oct2026))) deze maand")
    }

    func testContributionInfoWithoutIncomeAndWarnings() {
        var d = FinanceData(startMonth: oct2026)
        let pot = Pot(name: "Spaar", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot)
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, current: oct2026)
        let info = ContributionInfo(d, id: pot.id, month: oct2026)!
        XCTAssertTrue(info.hasNoBase)
        XCTAssertEqual(info.amount, 0)

        // Samen meer dan 100% van het inkomen: de motor waarschuwt, het scherm toont het.
        var (e, p) = baseData()
        e.setContributionPercent(p.id, percent: 70, basis: .salary, current: oct2026)
        let q = Pot(name: "Tweede", monthlyContribution: 0, startMonth: oct2026)
        e.addPot(q)
        e.setContributionPercent(q.id, percent: 50, basis: .salary, current: oct2026)
        let warned = ContributionInfo(e, id: p.id, month: oct2026)!
        XCTAssertFalse(warned.warnings.isEmpty)
        XCTAssertEqual(warned.warnings, e.allocationWarnings(in: oct2026))
    }

    func testContributionInfoWithAnEveryFourWeeksSalaryHasAnAverageMonth() {
        var (d, pot) = baseData()
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, current: oct2026)
        let info = ContributionInfo(d, id: pot.id, month: oct2026)!
        // Oktober heeft twee uitbetalingen (2 en 30 oktober): 10% van 6000.
        XCTAssertEqual(info.base, 6_000)
        XCTAssertEqual(info.amount, 600)
        XCTAssertNotNil(info.averageAmount)
        XCTAssertEqual(info.averageAmount, d.estimatedAllocation(pot.id, in: oct2026))
        XCTAssertNotEqual(info.averageAmount, info.amount, "een gemiddelde maand is niet deze maand met twee uitbetalingen")
    }

    func testContributionPreviewMatchesTheAllocationAfterSaving() {
        var (d, pot) = baseData()
        for (percent, basis) in [(10.0, IncomeBasis.salary), (12.5, .allIncome), (33.33, .salary), (0, .salary), (100, .allIncome)] {
            let preview = ContributionPreview.resolve(d, percent: percent, basis: basis, month: oct2026)
            d.setContributionPercent(pot.id, percent: percent, basis: basis, current: oct2026)
            XCTAssertEqual(preview.amount, d.allocation(pot.id, in: oct2026), "\(percent)% \(basis)")
            XCTAssertEqual(preview.amount, d.percentAmount(percent, of: basis, in: oct2026))
            XCTAssertNil(preview.footnote, "met salaris en het maandelijkse schema valt er niets te melden")
        }
        let preview = ContributionPreview.resolve(d, percent: 10, basis: .salary, month: oct2026)
        XCTAssertEqual(preview.note, "Per maand: 10% van \(Fmt.euro(3_000)) salaris in oktober")
        pot.contributionPercent = 10
    }

    func testFormWarningsMatchTheEngineAfterSaving() {
        var (d, pot) = baseData()
        let second = Pot(name: "Tweede", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(second)
        d.setContributionPercent(second.id, percent: 50, basis: .salary, current: oct2026)

        // Een bestaande pot die op 70% wordt gezet: samen 120%.
        var draft = pot
        draft.contributionMode = .percentage
        draft.contributionPercent = 70
        draft.contributionBasis = .salary
        let before = ContributionPreview.warnings(d, pot: draft, month: oct2026)
        XCTAssertTrue(before.contains(.percentagesOver100(total: 120)), "\(before)")
        // De proef verandert de gegevens niet.
        XCTAssertEqual(d.pot(pot.id)?.contributionMode, .fixed)
        // Na bewaren meldt de motor hetzelfde.
        d.updatePot(draft, current: oct2026)
        XCTAssertEqual(d.allocationWarnings(in: oct2026), before)

        // Een nieuwe pot die er nog niet is: ook die telt mee.
        var fresh = FinanceData(startMonth: oct2026)
        fresh.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let first = Pot(name: "Eerste", monthlyContribution: 0, startMonth: oct2026)
        fresh.addPot(first)
        fresh.setContributionPercent(first.id, percent: 60, basis: .salary, current: oct2026)
        var newPot = Pot(name: "Nieuw", monthlyContribution: 0, startMonth: oct2026)
        newPot.contributionMode = .percentage
        newPot.contributionPercent = 60
        XCTAssertEqual(ContributionPreview.warnings(fresh, pot: newPot, month: oct2026).first, .percentagesOver100(total: 120))
        XCTAssertNil(fresh.pot(newPot.id), "de proef voegt niets toe")
        newPot.contributionPercent = 40
        XCTAssertEqual(ContributionPreview.warnings(fresh, pot: newPot, month: oct2026), [])

        // Een belegging, nieuw en bestaand.
        var holding = Holding(name: "Wereld", monthlyContribution: 0, startMonth: oct2026)
        holding.contributionMode = .percentage
        holding.contributionPercent = 50
        XCTAssertEqual(ContributionPreview.warnings(fresh, holding: holding, month: oct2026).first, .percentagesOver100(total: 110))
        fresh.addHolding(holding)
        holding.contributionPercent = 30
        XCTAssertEqual(ContributionPreview.warnings(fresh, holding: holding, month: oct2026), [])
        fresh.updateHolding(holding, current: oct2026)
        XCTAssertEqual(fresh.allocationWarnings(in: oct2026), [])
    }

    func testContributionPreviewExplainsMissingIncomeAndAverageMonths() {
        var d = FinanceData(startMonth: oct2026)
        let none = ContributionPreview.resolve(d, percent: 10, basis: .salary, month: oct2026)
        XCTAssertEqual(none.amount, 0)
        XCTAssertNotNil(none.footnote)
        XCTAssertTrue(none.footnote!.contains("geen salaris"))
        XCTAssertTrue(ContributionPreview.resolve(d, percent: 10, basis: .allIncome, month: oct2026).footnote!.contains("geen inkomen"))

        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 1_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 5))
        let preview = ContributionPreview.resolve(d, percent: 10, basis: .salary, month: oct2026)
        // Oktober: 5, 19 (twee uitbetalingen van 1000 vanaf de 5e: 5, 19; de volgende is 2 november).
        XCTAssertEqual(preview.amount, 200)
        XCTAssertTrue(preview.footnote!.contains("gemiddelde maand"))
        XCTAssertEqual(preview.footnote!.contains("geen salaris"), false)
    }

    // MARK: Overschrijfdag van de inleg

    func testTransferNoteFollowsTheEngineForEveryOrigin() {
        var (d, pot) = baseData()
        // Het maandelijkse schema: de salarisdag (de 25e).
        var info = ContributionInfo(d, id: pot.id, month: oct2026)!
        XCTAssertEqual(info.transferDay, d.transferDay(for: pot.id, in: oct2026))
        XCTAssertEqual(info.transferDay, 25)
        XCTAssertEqual(info.transferOrigin, .salaryDay)
        XCTAssertEqual(info.transferNote(to: "naar deze pot"), "De inleg gaat op de 25e naar deze pot, je salarisdag.")

        // Een eigen overschrijfdag van de pot.
        var own = pot
        own.transferDay = 3
        d.updatePot(own, current: oct2026)
        info = ContributionInfo(d, id: pot.id, month: oct2026)!
        XCTAssertEqual(info.transferDay, 3)
        XCTAssertEqual(info.transferOrigin, .own)
        XCTAssertEqual(info.transferNote(to: "naar deze pot"), "De inleg gaat op de 3e naar deze pot.")

        // De dag van de verdeling van de maand gaat voor.
        d.editPlan(oct2026) { $0.transferDay = 10 }
        info = ContributionInfo(d, id: pot.id, month: oct2026)!
        XCTAssertEqual(info.transferDay, 10)
        XCTAssertEqual(info.transferOrigin, .month)
        XCTAssertEqual(info.transferDay, d.transferDay(for: pot.id, in: oct2026))
        // Een andere maand houdt de eigen dag van de pot.
        XCTAssertEqual(ContributionInfo(d, id: pot.id, month: oct2026.adding(1))!.transferOrigin, .own)

        // Een belegging krijgt dezelfde tekst, met haar eigen bestemming.
        var e = FinanceData(startMonth: oct2026)
        e.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 31)
        let holding = Holding(name: "Wereld", monthlyContribution: 100, startMonth: oct2026)
        e.addHolding(holding)
        let hinfo = ContributionInfo(e, id: holding.id, month: oct2026)!
        XCTAssertEqual(hinfo.transferDay, 31)
        XCTAssertEqual(hinfo.transferNote(to: "van je rekening naar deze belegging"),
                       "De inleg gaat op de 31e van je rekening naar deze belegging, je salarisdag.")
        let short = ContributionInfo(e, id: holding.id, month: YearMonth(year: 2026, month: 11))!
        XCTAssertEqual(short.transferDay, 30, "31 in een korte maand is de laatste dag")
    }

    func testTransferNoteStaysQuietWithoutAContribution() {
        var d = FinanceData(startMonth: oct2026)
        let pot = Pot(name: "Leeg", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot)
        let info = ContributionInfo(d, id: pot.id, month: oct2026)!
        XCTAssertFalse(info.hasContribution)
        XCTAssertNil(info.transferNote(to: "naar deze pot"))
        // Een bedrag in alleen deze maand telt wel.
        d.setAllocation(pot.id, in: oct2026, amount: 40)
        XCTAssertTrue(ContributionInfo(d, id: pot.id, month: oct2026)!.hasContribution)
    }

    func testTransferNoteWithAnEveryFourWeeksSalary() {
        var (d, pot) = baseData()
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        let info = ContributionInfo(d, id: pot.id, month: oct2026)!
        // De eerste uitbetaling van oktober is de 2e.
        XCTAssertEqual(info.transferDay, 2)
        XCTAssertEqual(info.transferDay, d.transferDay(for: pot.id, in: oct2026))
        XCTAssertEqual(info.transferOrigin, .firstSalaryDay)
        XCTAssertEqual(info.transferNote(to: "naar deze pot"),
                       "De inleg gaat op de 2e naar deze pot, de eerste salarisdag van de maand.")

        // Elke 6 weken vanaf 2 oktober: 2 okt, 13 nov, 25 dec, 5 feb. Januari 2027 heeft geen uitbetaling.
        d.salary.setSchedule(.weeks, interval: 6, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        let january = YearMonth(year: 2027, month: 1)
        XCTAssertEqual(d.salaryPayDays(in: january), [])
        let quiet = ContributionInfo(d, id: pot.id, month: january)!
        XCTAssertEqual(quiet.transferOrigin, .salaryDayFallback)
        XCTAssertEqual(quiet.transferDay, 25, "zonder uitbetaling geldt de ingestelde salarisdag")
        XCTAssertEqual(quiet.transferDay, d.transferDay(for: pot.id, in: january))
        XCTAssertEqual(quiet.transferNote(to: "naar deze pot"),
                       "De inleg gaat op de 25e naar deze pot, je ingestelde salarisdag. Deze maand komt er geen salaris binnen.")
    }

    // MARK: Komende boekingen van een spaarpot

    func testUpcomingListsInlegExpensesAndInterestOfThePotOnly() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Vakantie", monthlyContribution: 200, startMonth: oct2026)
        pot.interestRate = 0.024
        pot.interestPayout = .monthly
        pot.interestPayoutDay = 28
        let other = Pot(name: "Auto", monthlyContribution: 50, startMonth: oct2026)
        d.addPot(pot, openingBalance: 1_000, now: engTime(oct2026, 1, hour: 8))
        d.addPot(other, openingBalance: 100, now: engTime(oct2026, 1, hour: 8))
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 100, day: 27,
                               potShares: [PotShare(potID: pot.id, amount: 60), PotShare(potID: other.id, amount: 10)]),
                     kind: .expense, in: oct2026)
        let today = engTime(oct2026, 10, hour: 9)

        let items = PotUpcoming.items(d, potID: pot.id, current: oct2026, today: today)
        XCTAssertEqual(items.map(\.kind), [.toPot, .expense, .interest])
        XCTAssertEqual(items.map(\.title), ["Inleg", "Tandarts", "Rente"])
        XCTAssertEqual(items.map { engDayNumber($0.date) }, [25, 27, 28])
        XCTAssertEqual(items.map(\.daysAhead), [15, 17, 18])
        XCTAssertEqual(items[0].amount, 200)
        XCTAssertEqual(items[1].amount, -60, "alleen het deel uit deze pot")
        XCTAssertEqual(items[2].kind, .interest)
        XCTAssertGreaterThan(items[2].amount, 0)

        let now = d.potBalanceNow(pot.id, current: oct2026, today: today)
        XCTAssertEqual(items[0].balanceAfter, now + 200)
        XCTAssertEqual(items[1].balanceAfter, now + 200 - 60)
        XCTAssertEqual(cents(items[2].balanceAfter), cents(now + 200 - 60 + items[2].amount))
        // Op het eind van de lijst is het saldo het saldo aan het eind van die dag.
        XCTAssertEqual(items[2].balanceAfter, d.potBalance(pot.id, asOf: items[2].date))
        XCTAssertEqual(items[0].balanceAfter, d.potBalance(pot.id, asOf: items[0].date))
        XCTAssertEqual(items[1].balanceAfter, d.potBalance(pot.id, asOf: items[1].date))
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertTrue(items.allSatisfy { $0.detail == nil || $0.detail == "Uitgave uit deze pot" })

        // De andere pot krijgt zijn eigen boekingen.
        let others = PotUpcoming.items(d, potID: other.id, current: oct2026, today: today)
        XCTAssertEqual(others.map(\.kind), [.toPot, .expense])
        XCTAssertEqual(others.map(\.amount), [50, -10])
        XCTAssertEqual(PotUpcoming.items(d, potID: UUID(), current: oct2026, today: today), [])
    }

    func testUpcomingUsesWholeCalendarDays() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let pot = Pot(name: "Vakantie", monthlyContribution: 200, startMonth: oct2026)
        d.addPot(pot, openingBalance: 0, now: engTime(oct2026, 1, hour: 8))

        // De inleg van de 25e: op de 24e nog gepland (morgen), op de 25e zelf al verwerkt (ook om 00:30), daarna weg.
        let eve = PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 24, hour: 23.5))
        XCTAssertEqual(eve.first?.title, "Inleg")
        XCTAssertEqual(eve.first?.daysAhead, 1)
        XCTAssertEqual(eve.first?.balanceAfter, 200)
        for hour in [0.5, 8, 12, 23.9] {
            let that = PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 25, hour: hour))
            XCTAssertFalse(that.contains { engDayNumber($0.date) == 25 && $0.kind == .toPot && $0.date < engTime(oct2026, 26, hour: 0) },
                           "vandaag telt al mee in het saldo van nu (\(hour) uur)")
            XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: engTime(oct2026, 25, hour: hour)), 200)
        }
        // Precies 30 dagen vooruit telt nog mee, 31 niet: vanaf 26 oktober is dat 25 november (de volgende inleg).
        let edge = PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 26, hour: 10))
        XCTAssertEqual(edge.map { engDayNumber($0.date) }, [25])
        XCTAssertEqual(edge.first?.daysAhead, 30)
        XCTAssertEqual(edge.first?.balanceAfter, 400)
        let beyond = PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 27, hour: 10))
        XCTAssertEqual(beyond.first.map { engDayNumber($0.date) }, 25)
        XCTAssertEqual(PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 26, hour: 10), days: 29), [])
        XCTAssertEqual(PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 26, hour: 10), days: 0), [])
    }

    func testUpcomingIncludesNextMonthsRecurringExpenseFromThePot() {
        // Een terugkerende uitgave die deels uit de pot komt, staat ook in de volgende maand op zijn eigen dag.
        var (d, pot) = baseData()
        d.upsertLine(MoneyLine(name: "Sportclub", amount: 40, isRecurring: true, day: 3,
                               potShares: [PotShare(potID: pot.id, amount: 25)]),
                     kind: .expense, in: oct2026)
        let today = engTime(oct2026, 20, hour: 9)
        let items = PotUpcoming.items(d, potID: pot.id, current: oct2026, today: today)
        XCTAssertEqual(items.map(\.title), ["Inleg", "Sportclub"])
        XCTAssertEqual(items.map { YearMonth(date: $0.date).key + "-" + String(engDayNumber($0.date)) }, ["2026-10-25", "2026-11-3"])
        XCTAssertEqual(items.map(\.amount), [200, -25])
        XCTAssertEqual(items.map(\.daysAhead), [5, 14])
        let now = d.potBalanceNow(pot.id, current: oct2026, today: today)
        XCTAssertEqual(items.last?.balanceAfter, now + 200 - 25)
        XCTAssertEqual(items.last?.balanceAfter, d.potBalance(pot.id, asOf: items.last!.date))
        // De regel is ook zichtbaar voor een pot die er niets mee te maken heeft: niet.
        let other = Pot(name: "Auto", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(other)
        XCTAssertEqual(PotUpcoming.items(d, potID: other.id, current: oct2026, today: today), [])
    }

    func testUpcomingShowsAPercentageInlegWithItsMonthlyAmount() {
        var (d, pot) = baseData()
        d.setContributionPercent(pot.id, percent: 10, basis: .salary, current: oct2026)
        // In november een eigen percentage.
        d.setAllocationPercent(pot.id, in: oct2026.adding(1), percent: 20)
        let items = PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 20, hour: 9), days: 40)
        XCTAssertEqual(items.map(\.amount), [300, 600])
        XCTAssertEqual(items.map(\.detail), ["10% van je salaris", "20% van je salaris"])
        XCTAssertEqual(items.map { YearMonth(date: $0.date).key }, ["2026-10", "2026-11"])
        XCTAssertEqual(items.map(\.amount), [d.allocation(pot.id, in: oct2026), d.allocation(pot.id, in: oct2026.adding(1))])
    }

    func testUpcomingIsEmptyWithoutPlannedBookings() {
        var d = FinanceData(startMonth: oct2026)
        let pot = Pot(name: "Leeg", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot, openingBalance: 50, now: engTime(oct2026, 1, hour: 8))
        XCTAssertEqual(PotUpcoming.items(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 10, hour: 9)), [])
    }

    func testUpcomingRunningBalanceEqualsThePotBalanceForEveryScenario() {
        var potsChecked = 0
        var itemsChecked = 0
        for seed in 0..<160 {
            let s = ledgerScenario(seed: UInt64(seed))
            let current = YearMonth(date: s.today)
            for pot in s.data.pots {
                // Een handmatige boeking na vandaag telt wel mee in het saldo van een latere dag maar staat niet in de
                // dagboekhouding: die potten slaan we over (in de app kun je geen boeking in de toekomst maken).
                if s.data.potEntries.contains(where: { $0.potID == pot.id && $0.date > s.today }) { continue }
                let items = PotUpcoming.items(s.data, potID: pot.id, current: current, today: s.today)
                potsChecked += 1
                var lastOfDay: [Date: PotUpcomingItem] = [:]
                var previous = s.data.potBalanceNow(pot.id, current: current, today: s.today)
                for item in items {
                    XCTAssertEqual(cents(item.balanceAfter), cents(previous + item.amount), "zaad \(seed) \(pot.name)")
                    previous = item.balanceAfter
                    lastOfDay[YearMonth.calendar.startOfDay(for: item.date)] = item
                    XCTAssertGreaterThan(item.daysAhead, 0)
                    XCTAssertLessThanOrEqual(item.daysAhead, PotUpcoming.horizonDays)
                }
                for (_, item) in lastOfDay {
                    XCTAssertEqual(cents(item.balanceAfter), cents(s.data.potBalance(pot.id, asOf: item.date)),
                                   "zaad \(seed) \(pot.name) \(item.date)")
                    itemsChecked += 1
                }
            }
        }
        XCTAssertGreaterThan(potsChecked, 100)
        XCTAssertGreaterThan(itemsChecked, 50)
    }

    // MARK: Een spaarpot verwijderen

    func testDeleteEffectMatchesTheRealDeletion() {
        var (d, pot) = baseData()
        d.addBankSnapshot(balance: 2_000, note: "Meting", date: engTime(oct2026, 3, hour: 9))
        let today = engTime(oct2026, 28, hour: 9)
        let effect = PotDeleteEffect(d, potID: pot.id, current: oct2026, today: today)
        XCTAssertNotNil(effect)
        guard let effect else { return }
        XCTAssertEqual(effect.potName, "Vakantie")
        XCTAssertEqual(effect.balance, d.potBalanceNow(pot.id, current: oct2026, today: today))
        XCTAssertEqual(effect.bankNow, d.bankBalanceNowIfKnown(current: oct2026, today: today))
        XCTAssertTrue(effect.hasBalance)

        var returned = d
        returned.deletePot(pot.id, returningBalanceToBank: true, current: oct2026, today: today)
        XCTAssertEqual(effect.bankIfReturned, returned.bankBalanceNowIfKnown(current: oct2026, today: today))
        var discarded = d
        discarded.deletePot(pot.id)
        XCTAssertEqual(effect.bankIfDiscarded, discarded.bankBalanceNowIfKnown(current: oct2026, today: today))
        // Het echte verwijderen verandert de gegevens niet door deze proef.
        XCTAssertNotNil(d.pot(pot.id))
        XCTAssertNil(PotDeleteEffect(d, potID: UUID(), current: oct2026, today: today))
    }

    func testDeleteEffectWithoutBalanceOrBank() {
        var d = FinanceData(startMonth: oct2026)
        let pot = Pot(name: "Leeg", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot)
        let effect = PotDeleteEffect(d, potID: pot.id, current: oct2026, today: engTime(oct2026, 10, hour: 9))!
        XCTAssertFalse(effect.hasBalance)
        XCTAssertNil(effect.bankNow, "nog geen banksaldo bekend")
        XCTAssertNil(effect.bankIfReturned)
        XCTAssertNil(effect.bankIfDiscarded)
    }
}
