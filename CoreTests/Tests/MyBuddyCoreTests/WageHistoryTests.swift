import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van het loon per maand (App/Core/WageHistory.swift en de leesplekken in de rekenmotor, docs/work/plan2.md D6): een wijziging
/// geldt vanaf haar maand tot de volgende, het loon van een uitbetaling is dat van de maand waarin ze op je rekening komt, schattingen
/// rekenen met het loon van de maand die ze schatten, `setWage` legt het verleden niet vast en zonder wijzigingen is alles als vroeger.
final class WageHistoryTests: XCTestCase {
    private let sep = YearMonth(year: 2026, month: 9)
    private let oct = YearMonth(year: 2026, month: 10)
    private let nov = YearMonth(year: 2026, month: 11)
    private let dec = YearMonth(year: 2026, month: 12)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }

    /// Uurloon 14,35 bij 32 uur per week, salaris op de 25e, vanaf september 2026; eventueel om de vier weken vanaf 11 september.
    private func hourlyData(schedule: SalarySchedule = .monthly) -> FinanceData {
        var d = FinanceData(startMonth: sep)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 14.35, hoursPerWeek: 32, payDay: 25)
        if schedule == .weeks { d.salary.setSchedule(.weeks, interval: 4, anchor: day(2026, 9, 11)) }
        return d
    }

    private func settings(rate: Double, hours: Double = 32) -> SalarySettings {
        SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: rate, hoursPerWeek: hours, payDay: 25)
    }

    // MARK: Het loon van een maand

    func testWithoutChangesEverythingIsAsBefore() {
        let d = hourlyData()
        XCTAssertEqual(d.salarySettings(in: nov), d.salary)
        XCTAssertEqual(d.salarySettings(in: sep), d.salary)
        XCTAssertEqual(d.salarySettings(forPayoutOn: day(2026, 11, 25)), d.salary)
        XCTAssertEqual(d.latestSalarySettings, d.salary)
        XCTAssertEqual(d.salaryCents(in: nov, plan: d.plan(for: nov)), CentsMath.int(d.salary.payoutAmount()))
        XCTAssertNil(d.salaryChange(effectiveIn: nov))
        XCTAssertNil(d.salaryChange(startingIn: nov))
        XCTAssertTrue(d.salaryChanges.isEmpty)
    }

    func testANewHourlyRateFromNovember() {
        var d = hourlyData()
        let before = d.salaryAmount(in: oct)
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 15.20))
        // Eerdere maanden houden hun loon, vanaf november geldt het nieuwe uurloon.
        XCTAssertEqual(d.salaryAmount(in: oct), before)
        XCTAssertEqual(d.salaryAmount(in: sep), before)
        let raised = settings(rate: 15.20).payoutAmount()
        XCTAssertEqual(d.salaryAmount(in: nov), raised)
        XCTAssertEqual(d.salaryAmount(in: dec), raised)
        XCTAssertEqual(d.dayEvents(in: nov).filter { $0.kind == .salary }.map { $0.bankAmount }, [raised])
        XCTAssertEqual(d.scheduledSalary(in: nov), raised)
        XCTAssertEqual(d.scheduledSalary(in: oct), before)
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
        XCTAssertTrue(d.monthLedger(oct).allReconciles)
        // De salarissen van het verleden zijn niet vastgelegd.
        XCTAssertTrue(d.months.values.allSatisfy { $0.salaryOverride == nil })
        // Het loon zelf blijft het loon van het begin.
        XCTAssertEqual(d.salary.hourlyRate, 14.35)
    }

    func testAFixedAmountAndHoursChange() {
        var d = FinanceData(startMonth: sep)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 36, payDay: 25)
        d.setSalaryChange(SalaryChange(from: dec, fixedMonthly: 3_200, hoursPerWeek: 32))
        XCTAssertEqual(d.salaryAmount(in: nov), 3_000)
        XCTAssertEqual(d.salaryAmount(in: dec), 3_200)
        XCTAssertEqual(d.salaryHours(in: nov), d.salary.defaultMonthlyHours)
        XCTAssertEqual(d.salaryHours(in: dec), d.salarySettings(in: dec).defaultMonthlyHours)
        XCTAssertEqual(d.salarySettings(in: dec).hoursPerWeek, 32)
        XCTAssertEqual(d.salarySettings(in: dec).hourlyRate, 0, "een veld dat niet verandert blijft wat het was")
        XCTAssertEqual(d.effectiveHourlyWage(in: nov), (3_000 / (36 * 52 / 12.0)).cents)
        XCTAssertEqual(d.effectiveHourlyWage(in: dec), (3_200 / (32 * 52 / 12.0)).cents)
        XCTAssertEqual(d.effectiveHourlyWage(), d.effectiveHourlyWage(in: dec), "zonder maand het laatste loon")
    }

    func testTheNewestChangeInEffectWins() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 16))
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 15))
        XCTAssertEqual(d.salaryChanges.map { $0.from }, [nov, dec], "op maand gesorteerd, ook als je ze in een andere volgorde toevoegt")
        XCTAssertEqual(d.salarySettings(in: oct).hourlyRate, 14.35)
        XCTAssertEqual(d.salarySettings(in: nov).hourlyRate, 15)
        XCTAssertEqual(d.salarySettings(in: dec).hourlyRate, 16)
        XCTAssertEqual(d.salarySettings(in: YearMonth(year: 2030, month: 1)).hourlyRate, 16, "tot de volgende wijziging")
        XCTAssertEqual(d.latestSalarySettings.hourlyRate, 16)
        XCTAssertEqual(d.salaryChange(effectiveIn: YearMonth(year: 2027, month: 6))?.from, dec)
        XCTAssertEqual(d.salaryChange(effectiveIn: nov)?.from, nov)
        XCTAssertNil(d.salaryChange(effectiveIn: oct))
        XCTAssertEqual(d.salaryChange(startingIn: dec)?.hourlyRate, 16)
        XCTAssertNil(d.salaryChange(startingIn: YearMonth(year: 2027, month: 1)), "alleen de maand waarin ze ingaat")
    }

    func testTwoChangesInTheSameMonthReplaceEachOtherAndAnEmptyOneRemovesIt() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 15))
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 16))
        d.setSalaryChange(SalaryChange(from: nov, hoursPerWeek: 28))
        XCTAssertEqual(d.salaryChanges.count, 2)
        XCTAssertEqual(d.salaryChange(startingIn: nov), SalaryChange(from: nov, hoursPerWeek: 28), "vervangen, niet samengevoegd")
        XCTAssertEqual(d.salarySettings(in: nov).hourlyRate, 14.35)
        XCTAssertEqual(d.salarySettings(in: nov).hoursPerWeek, 28)
        d.setSalaryChange(SalaryChange(from: nov))
        XCTAssertEqual(d.salaryChanges.map { $0.from }, [dec], "een lege wijziging haalt die van de maand weg")
        XCTAssertEqual(d.salarySettings(in: nov).hourlyRate, 14.35)
        XCTAssertTrue(SalaryChange(from: nov).isEmpty)
        XCTAssertFalse(SalaryChange(from: nov, hourlyRate: 0).isEmpty, "nul is een ingevuld veld")
    }

    func testTheWageOfThePayoutMonthDecides() {
        // Om de 4 weken vanaf 11 september: 9 okt, 6 nov, 4 dec, ... De uitbetaling van 6 november krijgt het loon van november.
        var d = hourlyData(schedule: .weeks)
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 20))
        let october = d.salaryPayouts(in: oct, plan: d.plan(for: oct))
        let november = d.salaryPayouts(in: nov, plan: d.plan(for: nov))
        XCTAssertEqual(october.map { $0.day }, [9])
        XCTAssertEqual(november.map { $0.day }, [6])
        XCTAssertEqual(october.map { $0.cents }, [CentsMath.int(d.salary.payoutAmount())])
        XCTAssertEqual(november.map { $0.cents }, [CentsMath.int(SalarySettings.exactHourlyPay(rate: 20, hours: 32, multiplier: 4))])
        XCTAssertEqual(d.salarySettings(forPayoutOn: day(2026, 11, 6)).hourlyRate, 20)
        XCTAssertEqual(d.salarySettings(forPayoutOn: day(2026, 10, 30)).hourlyRate, 14.35)
        XCTAssertEqual(d.salarySettings(forPayoutOn: day(2026, 11, 1)).hourlyRate, 20, "de eerste van de maand hoort bij die maand")
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
    }

    func testAnOwnSalaryOrOwnHoursOfAMonthStillApply() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: oct, hourlyRate: 20))
        d.editPlan(oct) { $0.salaryOverride = 2_000 }
        d.editPlan(nov) { $0.hoursOverride = 100 }
        XCTAssertEqual(d.salaryAmount(in: oct), 2_000, "een eigen salaris gaat voor")
        XCTAssertEqual(d.salaryAmount(in: nov), 2_000, "eigen uren rekenen met het loon van die maand (100 uur keer 20)")
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 25))
        XCTAssertEqual(d.salaryAmount(in: nov), 2_500)
        XCTAssertEqual(d.salaryAmount(in: oct), 2_000)
        XCTAssertEqual(d.salaryHours(in: nov), 100)
    }

    func testOwnHoursOfAMonthWithAScheduleAreSharedAndUseTheWageOfThatMonth() {
        // Om de 2 weken vanaf 11 september: 9 en 23 oktober, 6 en 20 november. Eigen uren zijn het totaal van de maand, gelijk verdeeld.
        var d = hourlyData()
        d.salary.setSchedule(.weeks, interval: 2, anchor: day(2026, 9, 11))
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 20))
        XCTAssertEqual(d.salaryPayDays(in: oct), [9, 23])
        XCTAssertEqual(d.salaryPayDays(in: nov), [6, 20])
        d.editPlan(oct) { $0.hoursOverride = 100 }
        d.editPlan(nov) { $0.hoursOverride = 100 }
        XCTAssertEqual(d.salaryPayoutCents(in: oct, plan: d.plan(for: oct)).map { $0.cents }, [71_750, 71_750], "100 uur keer 14,35, over twee uitbetalingen")
        XCTAssertEqual(d.salaryPayoutCents(in: nov, plan: d.plan(for: nov)).map { $0.cents }, [100_000, 100_000], "100 uur keer 20, over twee uitbetalingen")
        XCTAssertEqual(d.salaryAmount(in: nov), 2_000)
        // Een eigen salaris verandert niet met het loon.
        d.editPlan(nov) { $0.hoursOverride = nil; $0.salaryOverride = 1_500 }
        XCTAssertEqual(d.salaryPayoutCents(in: nov, plan: d.plan(for: nov)).map { $0.cents }, [75_000, 75_000])
    }

    func testEstimatesUseTheWageOfTheEstimatedMonth() {
        var d = hourlyData(schedule: .weeks)
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 30))
        let low = d.salarySettings(in: nov).averageMonthlyAmount()
        let high = d.salarySettings(in: dec).averageMonthlyAmount()
        XCTAssertGreaterThan(high, low)
        XCTAssertEqual(d.estimatedFigures(nov).income, CentsMath.int(low))
        XCTAssertEqual(d.estimatedFigures(dec).income, CentsMath.int(high))
        XCTAssertEqual(d.estimatedIncomeBases(in: dec).salary, CentsMath.int(high))
        XCTAssertEqual(d.estimatedMonthlyIncome(in: dec), high)
        // Bij het maandelijkse schema volgt de schatting de maand zelf.
        var monthly = hourlyData()
        monthly.setSalaryChange(SalaryChange(from: dec, hourlyRate: 30))
        XCTAssertEqual(monthly.estimatedFigures(dec), monthly.monthFigures(dec))
        XCTAssertNotEqual(monthly.estimatedFigures(nov).income, monthly.estimatedFigures(dec).income)
    }

    func testFreezingTheHistoryUsesTheWageOfEachMonth() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: oct, hourlyRate: 20))
        let sepBefore = d.salaryAmount(in: sep)
        let octBefore = d.salaryAmount(in: oct)
        XCTAssertNotEqual(sepBefore, octBefore)
        // Een schemawijziging legt het verleden vast met het loon van elke maand.
        SalaryScheduleEdit.edit(&d, today: engTime(dec, 5, hour: 12)) { $0.payDay = 10 }
        XCTAssertEqual(d.months[sep.key]?.salaryOverride, sepBefore)
        XCTAssertEqual(d.months[oct.key]?.salaryOverride, octBefore)
        XCTAssertEqual(d.salaryAmount(in: sep), sepBefore)
        XCTAssertEqual(d.salaryAmount(in: oct), octBefore)
        XCTAssertEqual(d.salaryChanges.count, 1, "de wijzigingen blijven bestaan")
    }

    // MARK: Het loon veranderen

    func testSetWageKeepsThePastWithoutWritingOverrides() {
        var d = hourlyData()
        let past = [sep, oct].map { d.salaryAmount(in: $0) }
        d.setWage(current: nov, hourlyRate: 15.2)
        XCTAssertEqual(d.salaryChanges, [SalaryChange(from: nov, hourlyRate: 15.2)])
        XCTAssertEqual([sep, oct].map { d.salaryAmount(in: $0) }, past)
        XCTAssertEqual(d.salary.hourlyRate, 14.35)
        XCTAssertTrue(d.months.values.allSatisfy { $0.salaryOverride == nil })
        // Nogmaals in dezelfde maand vervangt de waarde van dat veld; een andere maand voegt er een toe.
        d.setWage(current: nov, hourlyRate: 15.5)
        XCTAssertEqual(d.salaryChanges.count, 1)
        d.setWage(current: nov, hoursPerWeek: 30)
        XCTAssertEqual(d.salaryChange(startingIn: nov), SalaryChange(from: nov, hourlyRate: 15.5, hoursPerWeek: 30), "de velden van de maand worden samengevoegd")
        d.setWage(current: dec, hoursPerWeek: 28)
        XCTAssertEqual(d.salaryChanges.map { $0.from }, [nov, dec])
        XCTAssertEqual(d.salarySettings(in: dec).hourlyRate, 15.5)
        XCTAssertEqual(d.salarySettings(in: dec).hoursPerWeek, 28)
    }

    func testSetWageOnFreshDataEditsTheBase() {
        // Er viel nog niets in het verleden: het loon zelf verandert, er komt geen wijziging in de lijst.
        var d = FinanceData(startMonth: nov)
        d.setWage(current: nov, hourlyRate: 14, hoursPerWeek: 30)
        XCTAssertTrue(d.salaryChanges.isEmpty)
        XCTAssertEqual(d.salary.hourlyRate, 14)
        XCTAssertEqual(d.salary.hoursPerWeek, 30)
        // Ook met een verleden zonder salaris (alles op 0): de basis.
        var e = FinanceData(startMonth: sep)
        XCTAssertFalse(e.hasSalary(before: nov), "nog geen salaris in het verleden")
        e.setWage(current: nov, fixedMonthly: 2_500)
        XCTAssertTrue(e.salaryChanges.isEmpty)
        XCTAssertEqual(e.salary.fixedMonthly, 2_500)
        XCTAssertTrue(e.hasSalary(before: nov), "wie zijn salaris voor het eerst invult krijgt het ook in de maanden sinds zijn start")
        XCTAssertEqual(e.salaryAmount(in: sep), 2_500)
    }

    func testSetWageWithASalaryInThePastMakesAChangeEvenForTheFirstTime() {
        var d = FinanceData(startMonth: sep)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        XCTAssertTrue(d.hasSalary(before: nov))
        d.setWage(current: nov, fixedMonthly: 2_100)
        XCTAssertEqual(d.salaryChanges, [SalaryChange(from: nov, fixedMonthly: 2_100)])
        XCTAssertEqual(d.salaryAmount(in: oct), 2_000)
        XCTAssertEqual(d.salaryAmount(in: nov), 2_100)
        // Een wijziging vanaf de eerste maand zonder verleden: de basis blijft, er is niets om te beschermen maar de lijst is al niet leeg.
        d.setWage(current: sep, fixedMonthly: 1_900)
        XCTAssertEqual(d.salaryChanges.map { $0.from }, [sep, nov])
        XCTAssertEqual(d.salaryAmount(in: sep), 1_900)
    }

    func testHasSalaryBeforeLooksAtTheMonthsFromTheStart() {
        var d = FinanceData(startMonth: oct)
        XCTAssertFalse(d.hasSalary(before: nov))
        d.salary.fixedMonthly = 1_000
        XCTAssertFalse(d.hasSalary(before: oct), "niets vóór de startmaand")
        XCTAssertFalse(d.hasSalary(before: sep))
        XCTAssertTrue(d.hasSalary(before: nov))
        d.setStart(day(2026, 10, 28))
        XCTAssertFalse(d.hasSalary(before: nov), "de salarisdag (25) valt vóór de startdag: dat salaris telt niet")
        XCTAssertTrue(d.hasSalary(before: dec))
    }

    func testNonsenseAmountsAreNotKept() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: -5, fixedMonthly: .nan, hoursPerWeek: .infinity))
        XCTAssertTrue(d.salaryChanges.isEmpty)
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 0))
        XCTAssertEqual(d.salaryChanges.count, 1, "nul is een geldig uurloon (onbetaald)")
        XCTAssertEqual(d.salaryAmount(in: nov), 0)
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 17, fixedMonthly: -1))
        XCTAssertEqual(d.salaryChange(startingIn: dec), SalaryChange(from: dec, hourlyRate: 17), "alleen het onzinnige veld valt weg")
    }

    func testRemovingAChangeRestoresThePreviousWage() {
        var d = hourlyData()
        let plain = d.salaryAmount(in: dec)
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 15.2))
        XCTAssertNotEqual(d.salaryAmount(in: dec), plain)
        d.removeSalaryChange(from: nov)
        XCTAssertEqual(d.salaryAmount(in: dec), plain)
        XCTAssertTrue(d.salaryChanges.isEmpty)
        d.removeSalaryChange(from: nov)   // nogmaals: niets
        XCTAssertTrue(d.salaryChanges.isEmpty)
        d.setSalaryChange(SalaryChange(from: oct, hourlyRate: 16))
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 17))
        d.removeSalaryChange(from: oct)
        XCTAssertEqual(d.salaryChanges.map { $0.from }, [dec])
    }

    // MARK: Samenspel met de startdatum

    func testAWageChangeInTheStartMonthOfAStartDate() {
        var d = hourlyData()
        d.setStart(day(2026, 11, 20))
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 20))
        // De salarisdag (25) valt na de startdag: de uitbetaling telt en rekent met het loon van november.
        XCTAssertEqual(d.salaryAmount(in: nov), settings(rate: 20).payoutAmount())
        // Een startdatum na de salarisdag: de uitbetaling telt niet mee.
        d.setStart(day(2026, 11, 28))
        XCTAssertEqual(d.salaryAmount(in: nov), 0)
        XCTAssertTrue(d.monthLedger(nov).allReconciles)
        // Een wijziging na de startmaand verandert niets aan de startmaand.
        d.setStart(day(2026, 11, 20))
        let startMonth = d.salaryAmount(in: nov)
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 30))
        XCTAssertEqual(d.salaryAmount(in: nov), startMonth)
        XCTAssertEqual(d.salaryAmount(in: dec), settings(rate: 30).payoutAmount())
    }

    func testAWageChangeBeforeTheStartMonthWorksFromTheStartMonth() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: YearMonth(year: 2026, month: 3), hourlyRate: 18))
        XCTAssertEqual(d.salarySettings(in: sep).hourlyRate, 18, "de wijziging vóór de startmaand geldt vanaf de startmaand")
        XCTAssertEqual(d.salaryAmount(in: sep), settings(rate: 18).payoutAmount())
        XCTAssertEqual(d.salaryAmount(in: YearMonth(year: 2026, month: 5)), 0, "vóór de startmaand telt niets")
        XCTAssertEqual(d.salaryChanges.count, 1, "de lijst toont haar nog wel")
    }

    // MARK: De plekken die het loon lezen

    func testThePurchaseCheckAndTheGoalsUseTheWageOfTheCurrentMonthByDefault() {
        let current = YearMonth.current()
        var d = hourlyData()
        let plainWage = d.effectiveHourlyWage()
        XCTAssertEqual(plainWage, 14.35)
        // Een wijziging die al gold: de aankoopcheck rekent met wat je nu verdient.
        d.setSalaryChange(SalaryChange(from: current.adding(-3), hourlyRate: 18, hoursPerWeek: 30))
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: 0, data: d), 18)
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: 25, data: d), 25, "een zelf ingevuld uurloon gaat voor")
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: 0, data: d, in: current.adding(-5)), 14.35, "een maand van voor de wijziging")
        // Een wijziging in de toekomst geldt nog niet voor de aankoopcheck van vandaag.
        d.setSalaryChange(SalaryChange(from: current.adding(2), hourlyRate: 22))
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: 0, data: d), 18)
        XCTAssertEqual(d.effectiveHourlyWage(in: current.adding(2)), 22)
        XCTAssertEqual(d.effectiveHourlyWage(), 22, "zonder maand het laatste loon")
        // Een nieuw parttime-doel begint bij de uren van de lopende maand.
        let template = d.goalTemplate(.partTime)
        XCTAssertEqual(template.hoursFrom, 30)
        XCTAssertEqual(template.hoursTo, 22)
    }

    func testTheIncomeGapOfAPartTimeGoalFollowsTheWageOfTheMonth() {
        var d = hourlyData()
        var goal = LifeGoal(name: "Vier dagen", kind: .partTime)
        goal.hoursFrom = 32
        goal.hoursTo = 24
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 20))
        let before = d.monthlyIncomeGap(for: goal, in: nov)
        let after = d.monthlyIncomeGap(for: goal, in: dec)
        XCTAssertEqual(before, d.salary.averageMonthly(perWeek: 14.35 * 8).cents)
        XCTAssertEqual(after, d.salary.averageMonthly(perWeek: 20 * 8).cents)
        XCTAssertEqual(d.monthlyIncomeGap(for: goal), after, "zonder maand het laatste loon")
        XCTAssertGreaterThan(after, before)
        // Het kapitaal dat nodig is volgt mee, en `goalInputs` rekent met de maand die het krijgt.
        XCTAssertGreaterThan(d.neededCapital(for: goal, drawdownReturn: 0.03, in: dec), d.neededCapital(for: goal, drawdownReturn: 0.03, in: nov))
        XCTAssertEqual(d.neededCapital(for: goal, drawdownReturn: 0.03), d.neededCapital(for: goal, drawdownReturn: 0.03, in: dec), "zonder maand het laatste loon")
        XCTAssertGreaterThan(d.goalInputs(for: goal, current: dec).target, d.goalInputs(for: goal, current: nov).target)
        XCTAssertEqual(d.goalInputs(for: goal, current: oct).target, d.goalInputs(for: goal, current: nov).target, "vóór de wijziging hetzelfde loon")
        // Een eigen bedrag voor het inkomensverlies gaat voor.
        goal.monthlyGapOverride = 111
        XCTAssertEqual(d.monthlyIncomeGap(for: goal, in: dec), 111)
    }

    func testTheExtraHoursAcceleratorUsesTheHourlyRateOfTheCurrentMonth() throws {
        let current = YearMonth.current()
        var d = FinanceData(startMonth: current.adding(-3))
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 32, payDay: 25)
        d.setSalaryChange(SalaryChange(from: current.adding(-1), hourlyRate: 30))
        var goal = LifeGoal(name: "Japan", kind: .vacation)
        goal.targetAmount = 20_000
        goal.inflationAdjusted = false
        goal.funding = .custom(start: 0, monthly: 100, annualReturn: 0)
        d.addGoal(goal)
        let list = d.accelerators(for: goal, current: current)
        let hours = try XCTUnwrap(list.first { $0.id == "hours" })
        let expected = d.salarySettings(in: current).averageMonthly(perWeek: 30 * 2).cents
        XCTAssertTrue(hours.detail.contains(Fmt.euroExact(30)), hours.detail)
        XCTAssertTrue(hours.detail.contains(Fmt.euro(expected)), hours.detail)
        XCTAssertFalse(hours.detail.contains(Fmt.euroExact(20)))
    }

    func testSalaryHoursAndTheScheduledSalaryUseTheHoursAndWageOfTheMonth() {
        var d = hourlyData(schedule: .weeks)
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 20, hoursPerWeek: 20))
        let oldPayouts = d.salaryPayDays(in: oct).count
        let newPayouts = d.salaryPayDays(in: nov).count
        XCTAssertEqual(d.salaryHours(in: oct), Double(oldPayouts) * 32 * 4)
        XCTAssertEqual(d.salaryHours(in: nov), Double(newPayouts) * 20 * 4)
        XCTAssertEqual(d.scheduledSalary(in: nov), CentsMath.value(newPayouts * CentsMath.int(settings(rate: 20, hours: 20).payoutAmountEveryFourWeeks)))
    }

    // MARK: Opslag

    func testWithoutChangesTheFileIsIdentical() throws {
        let d = hourlyData()
        let encoder = FinanceStorage.makeFileEncoder()
        XCTAssertFalse(String(decoding: try encoder.encode(d), as: UTF8.self).contains("salaryChanges"))
        var e = d
        e.setSalaryChange(SalaryChange(from: dec, hourlyRate: 16))
        e.setSalaryChange(SalaryChange(from: nov, fixedMonthly: 1))
        let text = String(decoding: try encoder.encode(e), as: UTF8.self)
        XCTAssertTrue(text.contains("\"salaryChanges\":[{\"fixedMonthly\":1,\"from\":\"2026-11\"},{\"from\":\"2026-12\",\"hourlyRate\":16}]"), text)
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: try encoder.encode(e))
        XCTAssertEqual(back.salaryChanges, e.salaryChanges)
        XCTAssertEqual(back, e)
        // Alle wijzigingen weghalen brengt het bestand byte voor byte terug.
        e.removeSalaryChange(from: nov)
        e.removeSalaryChange(from: dec)
        XCTAssertEqual(try encoder.encode(e), try encoder.encode(d))
    }

    func testTheLegacyFixtureStaysByteIdenticalAndAChangeOnlyAddsItsKey() throws {
        var d = verdelenFixtureLegacyData()
        XCTAssertEqual(String(decoding: try FinanceStorage.makeFileEncoder().encode(d), as: UTF8.self), VerdelenLegacyOutput.compact)
        d.setSalaryChange(SalaryChange(from: YearMonth(year: 2026, month: 6), hourlyRate: 19))
        let with = String(decoding: try FinanceStorage.makeFileEncoder().encode(d), as: UTF8.self)
        XCTAssertTrue(with.contains("\"salaryChanges\":[{\"from\":\"2026-06\",\"hourlyRate\":19}]"), with)
        d.removeSalaryChange(from: YearMonth(year: 2026, month: 6))
        XCTAssertEqual(String(decoding: try FinanceStorage.makeFileEncoder().encode(d), as: UTF8.self), VerdelenLegacyOutput.compact)
    }

    func testAnUnreadableChangeIsSkippedAndTheRestStays() throws {
        let d = hourlyData()
        let encoder = FinanceStorage.makeFileEncoder()
        var text = String(decoding: try encoder.encode(d), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"salary\":", with:
            "\"salaryChanges\":[{\"from\":\"kapot\"},{\"from\":\"2026-11\",\"hourlyRate\":\"veel\"},{\"from\":\"2026-12\",\"hourlyRate\":16},\"x\"],\"salary\":")
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(text.utf8))
        XCTAssertEqual(back.salaryChanges.map { $0.from }, [nov, dec])
        XCTAssertNil(back.salaryChanges[0].hourlyRate, "een onleesbaar veld is leeg")
        XCTAssertEqual(back.salaryChanges[1].hourlyRate, 16)
        XCTAssertTrue(back.salaryChanges[0].isEmpty, "zo'n wijziging verandert niets")
    }

    func testAnUnreadableListOfChangesGivesNoChangesAndTheFileLoads() throws {
        let d = hourlyData()
        let plain = String(decoding: try FinanceStorage.makeFileEncoder().encode(d), as: UTF8.self)
        for junk in ["\"kapot\"", "12", "null", "{\"from\":\"2026-11\"}", "[]"] {
            let text = plain.replacingOccurrences(of: "\"salary\":", with: "\"salaryChanges\":\(junk),\"salary\":")
            let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(text.utf8))
            XCTAssertTrue(back.salaryChanges.isEmpty, junk)
            XCTAssertEqual(back, d, junk)
        }
    }

    func testAFileWithDuplicatesOrNonsenseIsCleanedWhenRead() throws {
        let d = hourlyData()
        var text = String(decoding: try FinanceStorage.makeFileEncoder().encode(d), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"salary\":", with:
            "\"salaryChanges\":[{\"from\":\"2026-12\",\"hourlyRate\":17},{\"from\":\"2026-11\",\"hourlyRate\":15,\"fixedMonthly\":-4,\"hoursPerWeek\":28},{\"from\":\"2026-12\",\"hourlyRate\":18}],\"salary\":")
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(text.utf8))
        XCTAssertEqual(back.salaryChanges.map { $0.from }, [nov, dec], "op maand gesorteerd, één per maand")
        XCTAssertEqual(back.salaryChange(startingIn: dec)?.hourlyRate, 18, "bij twee van dezelfde maand wint de laatste in het bestand")
        XCTAssertNil(back.salaryChange(startingIn: nov)?.fixedMonthly, "een negatief bedrag is geen bedrag")
        XCTAssertEqual(back.salaryChange(startingIn: nov)?.hoursPerWeek, 28)
    }

    func testAFileWithManyChangesInAnyOrderIsReadSortedByMonth() throws {
        // Acht wijzigingen in omgekeerde en door elkaar gehusselde volgorde: een woordenboek geeft nooit toevallig de goede volgorde.
        let months = (0..<8).map { sep.adding($0 * 2) }
        let order = [5, 2, 7, 0, 4, 1, 6, 3]
        let list = order.map { index -> String in
            let month = months[index]
            return "{\"from\":\"\(month.key)\",\"hourlyRate\":\(10 + index)}"
        }.joined(separator: ",")
        var text = String(decoding: try FinanceStorage.makeFileEncoder().encode(hourlyData()), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"salary\":", with: "\"salaryChanges\":[\(list)],\"salary\":")
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(text.utf8))
        XCTAssertEqual(back.salaryChanges.map { $0.from }, months)
        XCTAssertEqual(back.salaryChanges.map { $0.hourlyRate }, (0..<8).map { Double(10 + $0) })
        // Het loon van elke maand is dat van de laatste wijziging die al gold.
        for (index, month) in months.enumerated() {
            XCTAssertEqual(back.salarySettings(in: month).hourlyRate, Double(10 + index))
            XCTAssertEqual(back.salarySettings(in: month.adding(1)).hourlyRate, Double(10 + index), "de maand erna houdt het loon")
        }
        // Opnieuw schrijven geeft dezelfde volgorde.
        let again = String(decoding: try FinanceStorage.makeFileEncoder().encode(back), as: UTF8.self)
        XCTAssertTrue(again.contains("\"2026-09\",\"hourlyRate\":10}"), again)
    }

    func testAChangeWritesOnlyTheFieldsItHas() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func text(_ change: SalaryChange) throws -> String { String(decoding: try encoder.encode(change), as: UTF8.self) }
        XCTAssertEqual(try text(SalaryChange(from: nov)), #"{"from":"2026-11"}"#)
        XCTAssertEqual(try text(SalaryChange(from: nov, hourlyRate: 15.2)), #"{"from":"2026-11","hourlyRate":15.2}"#)
        XCTAssertEqual(try text(SalaryChange(from: nov, fixedMonthly: 3_200, hoursPerWeek: 32)), #"{"fixedMonthly":3200,"from":"2026-11","hoursPerWeek":32}"#)
        XCTAssertNoThrow(try text(SalaryChange(from: nov, hourlyRate: .nan)), "een onmogelijk bedrag zet het bewaren niet stil")
        XCTAssertEqual(SalaryChange(from: nov).id, "2026-11")
    }

    func testTheLedgerClosesForEveryMonthWithChangesAndASchedule() {
        for schedule in [SalarySchedule.monthly, .weeks] {
            var d = hourlyData(schedule: schedule)
            d.addPot(Pot(name: "Spaar", monthlyContribution: 100, startMonth: sep), openingBalance: 200, now: engTime(sep, 12, hour: 12))
            d.setSalaryChange(SalaryChange(from: oct, hourlyRate: 18, hoursPerWeek: 36))
            d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 12))
            d.setWage(current: YearMonth(year: 2027, month: 2), hoursPerWeek: 20)
            for month in sep.range(count: 8) {
                XCTAssertTrue(d.monthLedger(month).allReconciles, "\(schedule) \(month.key)")
            }
        }
    }
}

private extension SalarySettings {
    /// Een uitbetaling van het schema om de vier weken: uurloon keer uren per week keer vier weken.
    var payoutAmountEveryFourWeeks: Double {
        var copy = self
        copy.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 9, day: 11))
        return copy.payoutAmount()
    }
}
