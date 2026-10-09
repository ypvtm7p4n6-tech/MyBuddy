import XCTest
import Foundation
@testable import MyBuddyCore

/// Basisdata voor de buffertests. "Nu" is oktober 2026.
/// Oktober: salaris 3000 + toeslag 100, vast 1000 (huur), variabel 400 (boodschappen).
/// Met pot: saldo 900 op 9 oktober (500 + 2 x 200; de inleg van de 25e komt nog, aan het eind van de maand is het
/// 1100), verdeling 200 per maand, overschot 1500.
/// Met bank (beginsaldo 1500 in augustus): 4500 op 9 oktober met pot, 4900 zonder pot.
private func bufferTestData(pot: Bool = false, bank: Bool = false) -> (data: FinanceData, pot: Pot?) {
    var d = makeBaseData()
    d.upsertLine(MoneyLine(name: "Boodschappen", amount: 400, isRecurring: true, kind: .variable),
                 kind: .expense, in: aug2026)
    var created: Pot?
    if pot { created = addBufferPot(&d) }
    if bank { d.addBankSnapshot(balance: 1500, note: "Start", date: day(aug2026, 3)) }
    d.materialize(upTo: oct2026)
    return (d, created)
}

/// "Nu" in de tests: 9 oktober. Het salaris en de inleg van de 25e komen nog. (Zonder `today` rekent `BufferCalc`
/// met de klok, en die hoort niet in een test.)
private let bufferToday = day(oct2026, 9)

/// Invoer met vaste en variabele uitgaven die samen 1550 per maand noodzakelijk zijn (1200 + 70% van 500).
private func bufferSample(saving: Double = 400, within: Int = 12, rate: Double = 0) -> BufferInputs {
    BufferInputs(months: 4, fixedMonthly: 1200, variableMonthly: 500, variableShare: 0.7,
                 current: 2480, monthlySaving: saving, fillWithin: within, annualRate: rate)
}

final class BufferTests: XCTestCase {
    // MARK: Aanbevolen maanden

    func testBaseMonthsPerEmployment() {
        XCTAssertEqual(BufferSituation(employment: .permanent).recommendedMonths, 3)
        XCTAssertEqual(BufferSituation(employment: .flexible).recommendedMonths, 4)
        XCTAssertEqual(BufferSituation(employment: .selfEmployed).recommendedMonths, 6)
    }

    func testAdditionsForHouseholdChildrenAndHome() {
        // Partner zonder inkomen telt mee, partner met inkomen niet.
        XCTAssertEqual(BufferSituation(employment: .permanent, household: .partnerWithoutIncome).recommendedMonths, 4)
        XCTAssertEqual(BufferSituation(employment: .permanent, household: .partnerWithIncome).recommendedMonths, 3)
        // Kinderen: één maand extra, niet per kind.
        XCTAssertEqual(BufferSituation(employment: .permanent, children: 1).recommendedMonths, 4)
        XCTAssertEqual(BufferSituation(employment: .permanent, children: 3).recommendedMonths, 4)
        // Een negatief aantal telt als geen kinderen.
        XCTAssertEqual(BufferSituation(employment: .permanent, children: -2).recommendedMonths, 3)
        // Eigen woning.
        XCTAssertEqual(BufferSituation(employment: .permanent, isHomeowner: true).recommendedMonths, 4)
        // Alles samen.
        XCTAssertEqual(BufferSituation(employment: .permanent, household: .partnerWithoutIncome, children: 2, isHomeowner: true).recommendedMonths, 6)
        XCTAssertEqual(BufferSituation(employment: .flexible, household: .partnerWithoutIncome, children: 1).recommendedMonths, 6)
    }

    func testRecommendationStaysBetweenThreeAndNine() {
        let most = BufferSituation(employment: .selfEmployed, household: .partnerWithoutIncome, children: 4, isHomeowner: true)
        XCTAssertEqual(most.recommendedMonths, 9)
        XCTAssertEqual(BufferSituation().recommendedMonths, 3)
        for employment in BufferEmployment.allCases {
            for household in BufferHousehold.allCases {
                let months = BufferSituation(employment: employment, household: household, children: 2, isHomeowner: true).recommendedMonths
                XCTAssertGreaterThanOrEqual(months, BufferSituation.minMonths)
                XCTAssertLessThanOrEqual(months, BufferSituation.maxMonths)
            }
        }
    }

    func testRecommendationExplanationLines() {
        let plain = BufferSituation().recommendation
        XCTAssertEqual(plain.months, 3)
        XCTAssertEqual(plain.lines.count, 2) // basis en totaal
        XCTAssertTrue(plain.lines[0].contains("Vast contract"))
        XCTAssertTrue(plain.lines[1].contains("3"))

        let full = BufferSituation(employment: .selfEmployed, household: .partnerWithoutIncome, children: 1, isHomeowner: true).recommendation
        XCTAssertEqual(full.months, 9)
        XCTAssertEqual(full.lines.count, 5) // basis, partner, kinderen, woning, totaal
        XCTAssertTrue(full.lines[0].contains("Zzp"))
        XCTAssertTrue(full.lines[4].contains("9"))

        // Partner met inkomen krijgt wel een uitlegregel, maar geen extra maand.
        let withPartner = BufferSituation(employment: .permanent, household: .partnerWithIncome).recommendation
        XCTAssertEqual(withPartner.months, 3)
        XCTAssertEqual(withPartner.lines.count, 3)
    }

    // MARK: Noodzakelijke uitgaven

    func testEssentialExpensesWithShare() {
        XCTAssertEqual(BufferCalc.essentialPerMonth(fixed: 1200, variable: 500, variableShare: 0.7), 1550, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.essentialPerMonth(fixed: 1200, variable: 500, variableShare: 0), 1200, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.essentialPerMonth(fixed: 1200, variable: 500, variableShare: 1), 1700, accuracy: 0.001)
        // Aandeel buiten 0...1 wordt begrensd.
        XCTAssertEqual(BufferCalc.essentialPerMonth(fixed: 1200, variable: 500, variableShare: 1.5), 1700, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.essentialPerMonth(fixed: 1200, variable: 500, variableShare: -0.5), 1200, accuracy: 0.001)
        // Negatieve bedragen tellen niet mee.
        XCTAssertEqual(BufferCalc.essentialPerMonth(fixed: -5, variable: -5, variableShare: 0.7), 0, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.defaultVariableShare, 0.7, accuracy: 1e-12)
    }

    // MARK: Doel, tekort, voortgang en dekking

    func testTargetGapProgressAndCoverage() {
        let r = BufferCalc.calculate(bufferSample())
        XCTAssertEqual(r.months, 4)
        XCTAssertEqual(r.fixedPart, 1200, accuracy: 0.001)
        XCTAssertEqual(r.variablePart, 350, accuracy: 0.001)
        XCTAssertEqual(r.essentialMonthly, 1550, accuracy: 0.001)
        XCTAssertEqual(r.target, 6200, accuracy: 0.001)
        XCTAssertEqual(r.current, 2480, accuracy: 0.001)
        XCTAssertEqual(r.gap, 3720, accuracy: 0.001)
        XCTAssertEqual(r.progress, 0.4, accuracy: 0.0001)
        XCTAssertEqual(r.coverageMonths ?? -1, 1.6, accuracy: 0.0001)
        XCTAssertTrue(r.hasTarget)
        XCTAssertFalse(r.isFull)
    }

    func testNegativeCurrentCountsAsZero() {
        var input = bufferSample()
        input.current = -300
        let r = BufferCalc.calculate(input)
        XCTAssertEqual(r.current, 0, accuracy: 0.001)
        XCTAssertEqual(r.gap, 6200, accuracy: 0.001)
        XCTAssertEqual(r.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(r.coverageMonths ?? -1, 0, accuracy: 0.0001)
    }

    // MARK: Hoe snel

    func testMonthsToFill() {
        // 2480 + 400 per maand: na 10 maanden 6480, na 9 maanden 6080.
        XCTAssertEqual(BufferCalc.calculate(bufferSample(saving: 400)).monthsToFill, 10)
        // Zonder rente: 150 per maand geeft 25 maanden.
        XCTAssertEqual(BufferCalc.calculate(bufferSample(saving: 150)).monthsToFill, 25)
    }

    func testMonthsToFillWithInterestIsFasterOrEqual() {
        XCTAssertEqual(BufferCalc.calculate(bufferSample(saving: 150, rate: 0)).monthsToFill, 25)
        XCTAssertEqual(BufferCalc.calculate(bufferSample(saving: 150, rate: 0.02)).monthsToFill, 24)
    }

    func testZeroSavingNeverFillsWithoutInterest() {
        let none = BufferCalc.calculate(bufferSample(saving: 0))
        XCTAssertNil(none.monthsToFill)
        XCTAssertTrue(none.gap > 0)
        // Een negatief bedrag telt als nul.
        let negative = BufferCalc.calculate(bufferSample(saving: -50))
        XCTAssertNil(negative.monthsToFill)
        XCTAssertEqual(negative.monthlySaving, 0, accuracy: 0.001)
        // Alleen rente (2% per jaar) haalt het doel na 556 maanden.
        XCTAssertEqual(BufferCalc.calculate(bufferSample(saving: 0, rate: 0.02)).monthsToFill, 556)
    }

    func testMonthlyNeededToFillWithinMonths() {
        XCTAssertEqual(BufferCalc.calculate(bufferSample(within: 12)).monthlyNeeded, 310, accuracy: 0.011)
        XCTAssertEqual(BufferCalc.calculate(bufferSample(within: 7)).monthlyNeeded, 531.43, accuracy: 0.011)
        // Met 2% rente is er iets minder nodig.
        XCTAssertEqual(BufferCalc.calculate(bufferSample(within: 12, rate: 0.02)).monthlyNeeded, 303.10, accuracy: 0.02)
    }

    func testFillWithinIsClampedToSliderRange() {
        let low = BufferCalc.calculate(bufferSample(within: 0))
        XCTAssertEqual(low.fillWithin, 1)
        XCTAssertEqual(low.monthlyNeeded, 3720, accuracy: 0.011)
        let high = BufferCalc.calculate(bufferSample(within: 100))
        XCTAssertEqual(high.fillWithin, 60)
        XCTAssertEqual(high.monthlyNeeded, 62, accuracy: 0.011)
    }

    // MARK: Randgevallen

    func testZeroExpensesGivesNoTarget() {
        let input = BufferInputs(months: 3, fixedMonthly: 0, current: 0, monthlySaving: 0)
        let r = BufferCalc.calculate(input)
        XCTAssertEqual(r.target, 0, accuracy: 0.001)
        XCTAssertEqual(r.gap, 0, accuracy: 0.001)
        XCTAssertEqual(r.progress, 0, accuracy: 0.0001)
        XCTAssertNil(r.coverageMonths)
        XCTAssertEqual(r.monthsToFill, 0)
        XCTAssertEqual(r.monthlyNeeded, 0, accuracy: 0.001)
        XCTAssertFalse(r.hasTarget)
        XCTAssertFalse(r.isFull)

        // Met spaargeld maar zonder uitgaven blijft de dekking onbekend.
        let withSavings = BufferCalc.calculate(BufferInputs(months: 3, fixedMonthly: 0, current: 500, monthlySaving: 0))
        XCTAssertNil(withSavings.coverageMonths)
        XCTAssertFalse(withSavings.isFull)
    }

    func testAlreadyAboveTarget() {
        var input = bufferSample(saving: 400)
        input.current = 7000
        let r = BufferCalc.calculate(input)
        XCTAssertEqual(r.gap, 0, accuracy: 0.001)
        XCTAssertEqual(r.progress, 1, accuracy: 0.0001)
        XCTAssertTrue(r.isFull)
        XCTAssertEqual(r.monthsToFill, 0)
        XCTAssertEqual(r.monthlyNeeded, 0, accuracy: 0.001)
        XCTAssertEqual(r.coverageMonths ?? -1, 4.516129, accuracy: 0.0001)
    }

    func testExactlyAtTarget() {
        var input = bufferSample()
        input.current = 6200
        let r = BufferCalc.calculate(input)
        XCTAssertEqual(r.gap, 0, accuracy: 0.001)
        XCTAssertTrue(r.isFull)
        XCTAssertEqual(r.monthsToFill, 0)
    }

    // MARK: Reeks voor de grafiek

    func testSeriesHorizon() {
        XCTAssertEqual(BufferCalc.seriesHorizon(monthsToFill: 10), 16)
        XCTAssertEqual(BufferCalc.seriesHorizon(monthsToFill: 0), 12)
        XCTAssertEqual(BufferCalc.seriesHorizon(monthsToFill: nil), 24)
        XCTAssertEqual(BufferCalc.seriesHorizon(monthsToFill: 200), 120)
    }

    func testSeriesFollowsSavingAndTarget() {
        let r = BufferCalc.calculate(bufferSample(saving: 400))
        let points = BufferCalc.series(r, start: oct2026)
        XCTAssertEqual(points.count, 17) // 0...16
        XCTAssertEqual(points[0].month, oct2026)
        XCTAssertEqual(points[0].projected, 2480, accuracy: 0.001)
        XCTAssertEqual(points[1].projected, 2880, accuracy: 0.001)
        XCTAssertEqual(points[16].projected, 8880, accuracy: 0.001)
        XCTAssertEqual(points[16].month, oct2026.adding(16))
        let allOnTarget = points.allSatisfy { abs($0.target - 6200) < 0.001 }
        XCTAssertTrue(allOnTarget)
        // De verwachte buffer haalt het doel precies na `monthsToFill` maanden.
        let firstReached = points.firstIndex { $0.projected >= $0.target }
        XCTAssertEqual(firstReached, r.monthsToFill)
    }

    func testSeriesIsFlatWithoutSaving() {
        let r = BufferCalc.calculate(bufferSample(saving: 0))
        let points = BufferCalc.series(r, start: oct2026)
        XCTAssertEqual(points.count, 25) // 0...24
        let allFlat = points.allSatisfy { abs($0.projected - 2480) < 0.001 }
        XCTAssertTrue(allFlat)
    }

    func testSeriesWithInterest() {
        let r = BufferCalc.calculate(bufferSample(saving: 150, rate: 0.02))
        let points = BufferCalc.series(r, start: oct2026)
        XCTAssertEqual(points.count, 31) // monthsToFill 24, plus 6
        XCTAssertEqual(points[1].projected, 2634.10, accuracy: 0.011)
        XCTAssertEqual(points[2].projected, 2788.45, accuracy: 0.011)
    }

    // MARK: Gegevens uit de app

    func testHasExpenses() {
        XCTAssertFalse(BufferCalc.hasExpenses(in: FinanceData(startMonth: oct2026), current: oct2026))
        XCTAssertTrue(BufferCalc.hasExpenses(in: bufferTestData().data, current: oct2026))
    }

    func testInputsFromDataUseFixedAndVariableExpenses() {
        let d = bufferTestData().data
        var setup = BufferSetup()
        setup.source = .manual
        setup.manualCurrent = 960
        let input = BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 480, fillWithin: 12, today: bufferToday)
        XCTAssertEqual(input.months, 3)
        XCTAssertEqual(input.fixedMonthly, 1000, accuracy: 0.001)
        XCTAssertEqual(input.variableMonthly, 400, accuracy: 0.001)
        XCTAssertEqual(input.current, 960, accuracy: 0.001)
        XCTAssertEqual(input.annualRate, 0, accuracy: 1e-12)

        let r = BufferCalc.calculate(input)
        XCTAssertEqual(r.essentialMonthly, 1280, accuracy: 0.001)
        XCTAssertEqual(r.target, 3840, accuracy: 0.001)
        XCTAssertEqual(r.gap, 2880, accuracy: 0.001)
        XCTAssertEqual(r.progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(r.coverageMonths ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(r.monthsToFill, 6)
        XCTAssertEqual(r.monthlyNeeded, 240, accuracy: 0.011)
    }

    func testChangingSituationAndShareChangesTarget() {
        let d = bufferTestData().data
        var setup = BufferSetup()
        setup.source = .manual
        setup.manualCurrent = 960

        // De helft van de variabele uitgaven: 1000 + 200 = 1200 per maand, 3 maanden.
        setup.variableShare = 0.5
        let half = BufferCalc.calculate(BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 480, fillWithin: 12, today: bufferToday))
        XCTAssertEqual(half.essentialMonthly, 1200, accuracy: 0.001)
        XCTAssertEqual(half.target, 3600, accuracy: 0.001)

        // Zzp met partner zonder inkomen, kind en woning: 9 maanden van 1280.
        setup.variableShare = 0.7
        setup.situation = BufferSituation(employment: .selfEmployed, household: .partnerWithoutIncome, children: 1, isHomeowner: true)
        let nine = BufferCalc.calculate(BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 480, fillWithin: 12, today: bufferToday))
        XCTAssertEqual(nine.months, 9)
        XCTAssertEqual(nine.target, 11520, accuracy: 0.001)
        XCTAssertEqual(nine.monthsToFill, 22)
    }

    func testManualEssentialIsUsedWithoutExpenses() {
        let d = FinanceData(startMonth: oct2026)
        var setup = BufferSetup()
        setup.manualEssential = 900
        let input = BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 0, fillWithin: 12, today: bufferToday)
        XCTAssertEqual(input.fixedMonthly, 900, accuracy: 0.001)
        XCTAssertEqual(input.variableMonthly, 0, accuracy: 0.001)
        let r = BufferCalc.calculate(input)
        XCTAssertEqual(r.target, 2700, accuracy: 0.001)

        // Een negatief handmatig bedrag telt als nul.
        setup.manualEssential = -100
        let negative = BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 0, fillWithin: 12, today: bufferToday)
        XCTAssertEqual(negative.fixedMonthly, 0, accuracy: 0.001)
    }

    func testInterestFollowsSavingsRateSetting() {
        var d = bufferTestData().data
        d.settings.savingsRate = 0.03
        var setup = BufferSetup()
        XCTAssertEqual(BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 0, fillWithin: 12, today: bufferToday).annualRate, 0, accuracy: 1e-12)
        setup.useInterest = true
        XCTAssertEqual(BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 0, fillWithin: 12, today: bufferToday).annualRate, 0.03, accuracy: 1e-12)
    }

    func testCurrentAmountPerSource() {
        let fixture = bufferTestData(pot: true, bank: true)
        let d = fixture.data
        var setup = BufferSetup()
        setup.potID = fixture.pot?.id

        setup.source = .bank
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: bufferToday), 4500, accuracy: 0.001)
        setup.source = .pot
        // Het saldo van 9 oktober: de inleg van de 25e telt nog niet mee (500 + 200 + 200).
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: bufferToday), 900, accuracy: 0.001)
        setup.source = .bankAndPot
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: bufferToday), 5400, accuracy: 0.001)
        setup.source = .manual
        setup.manualCurrent = 250
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: bufferToday), 250, accuracy: 0.001)
        setup.manualCurrent = -40
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: bufferToday), 0, accuracy: 0.001)

        // Bank en pot samen is al boven het doel van 3 maanden (3840).
        setup.source = .bankAndPot
        let r = BufferCalc.summary(for: d, setup: setup, current: oct2026, today: bufferToday)
        XCTAssertTrue(r.isFull)
        XCTAssertEqual(r.monthsToFill, 0)
    }

    func testCurrentAmountIsTheBalanceOfNowAndNotOfTheMonthEnd() {
        let fixture = bufferTestData(pot: true, bank: true)
        let d = fixture.data
        var setup = BufferSetup()
        setup.potID = fixture.pot?.id

        // Pot: de inleg van 200 komt op de 25e (12:00). Daarvoor is het 900, vanaf dat moment 1100.
        setup.source = .pot
        let before = BufferCalc.potAmount(in: d, setup: setup, current: oct2026, today: day(oct2026, 24))
        XCTAssertEqual(before, 900, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: day(oct2026, 24)), 900, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.potAmount(in: d, setup: setup, current: oct2026, today: oct2026.date(day: 25)), 1100, accuracy: 0.001)
        // Valt vandaag in een andere maand dan `current`, dan geldt het eind van `current`.
        let december = day(YearMonth(year: 2026, month: 12), 3)
        XCTAssertEqual(BufferCalc.potAmount(in: d, setup: setup, current: oct2026, today: december), 1100, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.potAmount(in: d, setup: setup, current: oct2026, today: december),
                       d.potBalance(fixture.pot?.id ?? UUID(), at: oct2026), accuracy: 0.001)

        // Bank: 1500 (3 aug) + augustus 3100 - 200 + september -1400 + 2900 + 1 oktober -1400 = 4500; op de 25e komt 2900 erbij.
        setup.source = .bank
        XCTAssertEqual(BufferCalc.bankAmount(in: d, current: oct2026, today: day(oct2026, 24)), 4500, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.bankAmount(in: d, current: oct2026, today: oct2026.date(day: 25)), 7400, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.bankAmount(in: d, current: oct2026, today: december), 7400, accuracy: 0.001)

        // De samenvatting en de invoer volgen hetzelfde "nu".
        setup.source = .pot
        let early = BufferCalc.summary(for: d, setup: setup, current: oct2026, today: day(oct2026, 24))
        let late = BufferCalc.summary(for: d, setup: setup, current: oct2026, today: oct2026.date(day: 25))
        XCTAssertEqual(early.current, 900, accuracy: 0.001)
        XCTAssertEqual(late.current, 1100, accuracy: 0.001)
        let input = BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 100, fillWithin: 12,
                                      today: day(oct2026, 24))
        XCTAssertEqual(input.current, 900, accuracy: 0.001)
    }

    func testBankBelowZeroCountsAsZero() {
        var d = bufferTestData().data
        d.addBankSnapshot(balance: -2000, note: "Rood", date: day(oct2026, 20))
        var setup = BufferSetup()
        setup.source = .bank
        XCTAssertEqual(BufferCalc.bankAmount(in: d, current: oct2026, today: bufferToday), 0, accuracy: 0.001)
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: bufferToday), 0, accuracy: 0.001)
    }

    func testPotSourceWithoutPotsIsZero() {
        let d = bufferTestData().data
        var setup = BufferSetup()
        setup.source = .pot
        XCTAssertEqual(BufferCalc.currentAmount(in: d, setup: setup, current: oct2026, today: bufferToday), 0, accuracy: 0.001)
        XCTAssertNil(BufferCalc.resolvedPot(in: d, preferred: nil))
    }

    func testDefaultMonthlySaving() {
        let fixture = bufferTestData(pot: true)
        var d = fixture.data
        var setup = BufferSetup()
        setup.source = .pot
        setup.potID = fixture.pot?.id

        // Gekozen pot: de verdeling van deze maand (200).
        XCTAssertEqual(BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: oct2026), 200, accuracy: 0.001)
        // Bron zonder pot: wat er over is (3100 - 1400 - 200 = 1500).
        setup.source = .bank
        XCTAssertEqual(BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: oct2026), 1500, accuracy: 0.001)
        // Pot zonder verdeling deze maand: terug naar wat er over is (3100 - 1400 = 1700).
        setup.source = .pot
        d.setAllocation(fixture.pot?.id ?? UUID(), in: oct2026, amount: 0)
        XCTAssertEqual(BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: oct2026), 1700, accuracy: 0.001)
        // Tekort (salaris 500): nooit negatief.
        d.salary.fixedMonthly = 500
        setup.source = .bank
        XCTAssertEqual(BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: oct2026), 0, accuracy: 0.001)
    }

    func testSummaryUsesDefaultSaving() {
        let fixture = bufferTestData(pot: true)
        var setup = BufferSetup()
        setup.source = .pot
        setup.potID = fixture.pot?.id
        let r = BufferCalc.summary(for: fixture.data, setup: setup, current: oct2026, today: bufferToday)
        XCTAssertEqual(r.target, 3840, accuracy: 0.001)
        // Pot van nu (9 oktober): 500 + 200 + 200 = 900. Nog 3840 - 900 = 2940 te gaan: 14,7 maand, dus 15.
        XCTAssertEqual(r.current, 900, accuracy: 0.001)
        XCTAssertEqual(r.gap, 2940, accuracy: 0.001)
        XCTAssertEqual(r.monthlySaving, 200, accuracy: 0.001)
        XCTAssertEqual(r.progress, 900.0 / 3840.0, accuracy: 0.0001)
        XCTAssertEqual(r.coverageMonths ?? -1, 900.0 / 1280.0, accuracy: 0.0001)   // 1280 = 1000 + 70% van 400
        XCTAssertEqual(r.monthsToFill, 15)
    }

    // MARK: Spaarpot en eerste keuzes

    func testBufferPotMatchesNameLoosely() {
        var d = FinanceData(startMonth: aug2026)
        XCTAssertNil(BufferCalc.bufferPot(in: d))
        d.addPot(Pot(name: "Vakantie", startMonth: aug2026))
        XCTAssertNil(BufferCalc.bufferPot(in: d))
        d.addPot(Pot(name: "  buffer ", startMonth: aug2026))
        XCTAssertEqual(BufferCalc.bufferPot(in: d)?.name, "  buffer ")
    }

    func testResolvedPotFallsBack() {
        var d = FinanceData(startMonth: aug2026)
        let holiday = Pot(name: "Vakantie", startMonth: aug2026)
        let buffer = Pot(name: "Buffer", startMonth: aug2026)
        d.addPot(holiday)
        // Geen pot "Buffer": de eerste pot.
        XCTAssertEqual(BufferCalc.resolvedPot(in: d, preferred: nil)?.id, holiday.id)
        d.addPot(buffer)
        // Zonder keuze: de pot "Buffer".
        XCTAssertEqual(BufferCalc.resolvedPot(in: d, preferred: nil)?.id, buffer.id)
        // Met geldige keuze: die pot. Met onbekende keuze: terugval.
        XCTAssertEqual(BufferCalc.resolvedPot(in: d, preferred: holiday.id)?.id, holiday.id)
        XCTAssertEqual(BufferCalc.resolvedPot(in: d, preferred: UUID())?.id, buffer.id)
    }

    func testInitialSetupPicksSourceFromData() {
        // Niets bekend: zelf invullen.
        XCTAssertEqual(BufferCalc.initialSetup(for: makeBaseData(), current: oct2026).source, .manual)
        // Banksaldo bekend: bankrekening.
        XCTAssertEqual(BufferCalc.initialSetup(for: bufferTestData(bank: true).data, current: oct2026).source, .bank)
        // Pot "Buffer" gaat voor het banksaldo.
        let fixture = bufferTestData(pot: true, bank: true)
        let setup = BufferCalc.initialSetup(for: fixture.data, current: oct2026)
        XCTAssertEqual(setup.source, .pot)
        XCTAssertEqual(setup.potID, fixture.pot?.id)
    }

    // MARK: Bewaren van de keuzes

    func testSetupJSONRoundTrip() {
        var setup = BufferSetup()
        setup.situation = BufferSituation(employment: .selfEmployed, household: .partnerWithoutIncome, children: 2, isHomeowner: true)
        setup.variableShare = 0.5
        setup.manualEssential = 999
        setup.source = .bankAndPot
        setup.potID = UUID()
        setup.manualCurrent = 123.5
        setup.useInterest = true
        let text = setup.json
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(BufferSetup.fromJSON(text), setup)
    }

    func testSetupJSONRejectsGarbage() {
        XCTAssertNil(BufferSetup.fromJSON(""))
        XCTAssertNil(BufferSetup.fromJSON("geen json"))
        XCTAssertNil(BufferSetup.fromJSON("{\"situation\": 5}"))
        XCTAssertEqual(BufferSetup().variableShare, 0.7, accuracy: 1e-12)
        XCTAssertEqual(BufferSetup().source, .manual)
    }
}
