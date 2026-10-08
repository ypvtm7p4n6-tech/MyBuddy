import XCTest
import Foundation
@testable import MyBuddyCore

// Tests van de aankoopcheck: uurloon, uren nodig, goedkoper vinden, feedback, "kan het?" en zoeklinks.
// Verwachte waarden zijn met de hand nagerekend (zie de opmerkingen), niet uit de implementatie overgenomen.

/// Standaard: product van 100 euro bij 20 euro per uur = 5 uur werken.
private func purInput(_ price: Double, shipping: Double = 0, willing: Double, wage: Double = 20,
                      category: PurchaseCategory = .electronics,
                      cheaper: Double? = nil, cheaperShipping: Double? = nil) -> PurchaseInput {
    PurchaseInput(name: "Test", category: category, price: price, shipping: shipping, hoursWilling: willing,
                  hourlyWage: wage, cheaperPrice: cheaper, cheaperShipping: cheaperShipping)
}

private func purContext(remaining: Double? = nil, surplus: Double? = nil, balance: Double? = nil,
                        income: Double = 0, pots: [PurchasePotOption] = []) -> PurchaseContext {
    PurchaseContext(monthlyIncome: income, remainingThisMonth: remaining, bankBalance: balance,
                    bankSurplus: surplus, pots: pots)
}

private func purTexts(_ notes: [PurchaseNote], _ kind: PurchaseNoteKind? = nil) -> [String] {
    notes.filter { kind == nil || $0.kind == kind }.map(\.text)
}

private func purAnyContains(_ notes: [PurchaseNote], _ fragment: String, kind: PurchaseNoteKind? = nil) -> Bool {
    purTexts(notes, kind).contains { $0.contains(fragment) }
}

final class PurchaseTests: XCTestCase {

    // MARK: Uurloon

    func testHourlyModeUsesHourlyRate() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 18.5, hoursPerWeek: 32)
        XCTAssertEqual(d.effectiveHourlyWage(), 18.5)
    }

    func testHourlyModeWithoutRateIsNil() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 0, hoursPerWeek: 32)
        XCTAssertNil(d.effectiveHourlyWage())
    }

    func testFixedModeDividesByAverageMonthlyHours() {
        var d = FinanceData(startMonth: aug2026)
        // 36 uur per week = 36 × 52 / 12 = 156 uur per maand; 3000 / 156 = 19,2307... = 19,23
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 36)
        XCTAssertEqual(d.effectiveHourlyWage() ?? 0, 19.23, accuracy: 0.0001)
        // 40 uur per week = 173,33 uur per maand; 2600 / 173,33 = 15 (2600 × 12 / 2080)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2600, hourlyRate: 0, hoursPerWeek: 40)
        XCTAssertEqual(d.effectiveHourlyWage() ?? 0, 15, accuracy: 0.0001)
    }

    func testFixedModeWithZeroHoursIsNil() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
        XCTAssertNil(d.effectiveHourlyWage())
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 0, hourlyRate: 0, hoursPerWeek: 36)
        XCTAssertNil(d.effectiveHourlyWage())
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: -5)
        XCTAssertNil(d.effectiveHourlyWage())
    }

    func testManualWageGoesBeforeSalary() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 18, hoursPerWeek: 32)
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: 22.5, data: d), 22.5)
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: 0, data: d), 18)
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: -4, data: d), 18)
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: .nan, data: d), 18)
        let empty = FinanceData(startMonth: aug2026)
        XCTAssertNil(PurchaseCalc.resolvedWage(manual: 0, data: empty))
        XCTAssertEqual(PurchaseCalc.resolvedWage(manual: 12, data: empty), 12)
    }

    // MARK: Uren nodig

    func testHoursNeededIsPriceOverWage() {
        let r = PurchaseCalc.evaluate(purInput(100, willing: 8))
        XCTAssertEqual(r.hoursNeeded, 5.0)
        XCTAssertEqual(r.totalCost, 100)
        // Verzending telt mee: 90 + 10 = 100.
        let s = PurchaseCalc.evaluate(purInput(90, shipping: 10, willing: 8))
        XCTAssertEqual(s.totalCost, 100)
        XCTAssertEqual(s.hoursNeeded, 5.0)
    }

    func testHoursNeededRoundsToTenthOfAnHour() {
        // 33 / 20 = 1,65 uur: precies op de helft, rondt naar boven af naar 1,7.
        XCTAssertEqual(PurchaseCalc.hoursNeeded(total: 33, wage: 20), 1.7)
        // 32,90 / 20 = 1,645 uur, rondt af naar 1,6.
        XCTAssertEqual(PurchaseCalc.hoursNeeded(total: 32.9, wage: 20), 1.6)
        // 99,99 / 20 = 4,9995 uur, rondt af naar 5,0.
        XCTAssertEqual(PurchaseCalc.hoursNeeded(total: 99.99, wage: 20), 5.0)
        // 50 / 19,23 = 2,6001... uur
        XCTAssertEqual(PurchaseCalc.hoursNeeded(total: 50, wage: 19.23), 2.6)
        XCTAssertEqual(PurchaseCalc.hoursNeeded(total: 50, wage: 0), 0)
    }

    func testEqualHoursIsNotWorthIt() {
        // Kost 5 uur. Precies 5 gekozen: gelijk is niet waard.
        let equal = PurchaseCalc.evaluate(purInput(100, willing: 5))
        XCTAssertEqual(equal.hoursNeeded, 5)
        XCTAssertFalse(equal.isWorthIt)
        // Lager is ook niet waard.
        XCTAssertFalse(PurchaseCalc.evaluate(purInput(100, willing: 4.5)).isWorthIt)
        // Net erboven (halve uurstap) is wel waard.
        XCTAssertTrue(PurchaseCalc.evaluate(purInput(100, willing: 5.5)).isWorthIt)
    }

    func testBoundaryFollowsTheRoundedHoursShown() {
        // 101 / 20 = 5,05 uur wordt 5,1 getoond: 5 uur kiezen is dus te weinig, 5,5 genoeg.
        let r = PurchaseCalc.evaluate(purInput(101, willing: 5))
        XCTAssertEqual(r.hoursNeeded, 5.1)
        XCTAssertFalse(r.isWorthIt)
        XCTAssertTrue(PurchaseCalc.evaluate(purInput(101, willing: 5.5)).isWorthIt)
        // 100,01 / 20 = 5,0005 uur wordt als 5,0 getoond; 5,0 kiezen blijft "gelijk".
        let tiny = PurchaseCalc.evaluate(purInput(100.01, willing: 5))
        XCTAssertEqual(tiny.hoursNeeded, 5.0)
        XCTAssertFalse(tiny.isWorthIt)
        // 98 / 20 = 4,9 uur: 5 uur kiezen is net genoeg.
        XCTAssertTrue(PurchaseCalc.evaluate(purInput(98, willing: 5)).isWorthIt)
    }

    func testDaysOfWorkIsHoursOverEight() {
        // 800 / 20 = 40 uur = 5 werkdagen.
        let r = PurchaseCalc.evaluate(purInput(800, willing: 50))
        XCTAssertEqual(r.hoursNeeded, 40)
        XCTAssertEqual(r.daysOfWork, 5, accuracy: 0.0001)
    }

    func testMaxWorthPriceIsHoursTimesWage() {
        XCTAssertEqual(PurchaseCalc.evaluate(purInput(100, willing: 4)).maxWorthPrice, 80)
        // 19,23 × 5,5 = 105,765 uur: op centen 105,77.
        XCTAssertEqual(PurchaseCalc.evaluate(purInput(100, willing: 5.5, wage: 19.23)).maxWorthPrice, 105.77, accuracy: 0.0001)
    }

    // MARK: Goedkoper

    func testCheaperReplacesOriginalOnlyWhenTotalIsLower() {
        // Origineel 100 + 5 = 105. Goedkoper 90 + 10 = 100: lager, dus gebruikt.
        let lower = PurchaseCalc.evaluate(purInput(100, shipping: 5, willing: 8, cheaper: 90, cheaperShipping: 10))
        XCTAssertTrue(lower.usesCheaper)
        XCTAssertEqual(lower.totalCost, 100)
        XCTAssertEqual(lower.originalTotal, 105)
        XCTAssertEqual(lower.savedByCheaper, 5)
        XCTAssertEqual(lower.hoursNeeded, 5)
        XCTAssertEqual(lower.hoursNeededOriginal, 5.3)   // 105 / 20 = 5,25 -> 5,3

        // Zelfde totaal (100 + 5): niet goedkoper.
        let equal = PurchaseCalc.evaluate(purInput(100, shipping: 5, willing: 8, cheaper: 100, cheaperShipping: 5))
        XCTAssertFalse(equal.usesCheaper)
        XCTAssertEqual(equal.totalCost, 105)
        XCTAssertEqual(equal.savedByCheaper, 0)

        // Lagere prijs maar dure verzending (80 + 30 = 110): niet goedkoper.
        let shippingEatsIt = PurchaseCalc.evaluate(purInput(100, shipping: 5, willing: 8, cheaper: 80, cheaperShipping: 30))
        XCTAssertFalse(shippingEatsIt.usesCheaper)
        XCTAssertEqual(shippingEatsIt.totalCost, 105)
    }

    func testCheaperWithoutShippingCountsAsFreeShipping() {
        let r = PurchaseCalc.evaluate(purInput(100, shipping: 5, willing: 8, cheaper: 95, cheaperShipping: nil))
        XCTAssertTrue(r.usesCheaper)
        XCTAssertEqual(r.totalCost, 95)
        XCTAssertEqual(r.savedByCheaper, 10)
    }

    func testShippingWithoutCheaperPriceIsIgnored() {
        let r = PurchaseCalc.evaluate(purInput(100, shipping: 5, willing: 8, cheaper: nil, cheaperShipping: 0))
        XCTAssertFalse(r.usesCheaper)
        XCTAssertEqual(r.totalCost, 105)
    }

    func testCheaperCanMakeItWorthIt() {
        // Origineel 120 = 6 uur, goedkoper 100 = 5 uur. 5,5 uur gekozen.
        let r = PurchaseCalc.evaluate(purInput(120, willing: 5.5, cheaper: 100))
        XCTAssertEqual(r.hoursNeededOriginal, 6)
        XCTAssertEqual(r.hoursNeeded, 5)
        XCTAssertTrue(r.isWorthIt)
        XCTAssertTrue(purAnyContains(r.feedback, "Zo past het wel", kind: .positive))
        // Zonder goedkoper is het niet waard.
        XCTAssertFalse(PurchaseCalc.evaluate(purInput(120, willing: 5.5)).isWorthIt)
    }

    func testCheaperNotEnoughStillNotWorth() {
        let r = PurchaseCalc.evaluate(purInput(120, willing: 4, cheaper: 100))
        XCTAssertTrue(r.usesCheaper)
        XCTAssertFalse(r.isWorthIt)
        XCTAssertTrue(purAnyContains(r.feedback, "blijft meer dan je ervoor over hebt"))
        XCTAssertTrue(purAnyContains(r.feedback, Fmt.euro(20)))
    }

    // MARK: Randgevallen

    func testZeroPrice() {
        let r = PurchaseCalc.evaluate(purInput(0, willing: 3))
        XCTAssertEqual(r.totalCost, 0)
        XCTAssertEqual(r.hoursNeeded, 0)
        XCTAssertEqual(r.daysOfWork, 0)
        XCTAssertTrue(r.isWorthIt)            // 3 uur is meer dan 0 uur
        XCTAssertNil(r.costPerYear)
        XCTAssertEqual(r.feedback.count, 1)
        XCTAssertEqual(r.feedback.first?.kind, .neutral)
        XCTAssertFalse(PurchaseCalc.evaluate(purInput(0, willing: 0)).isWorthIt)
    }

    func testNegativeInputBecomesZero() {
        let r = PurchaseCalc.evaluate(purInput(-50, shipping: -5, willing: -2))
        XCTAssertEqual(r.totalCost, 0)
        XCTAssertEqual(r.originalTotal, 0)
        XCTAssertEqual(r.hoursWilling, 0)
        XCTAssertEqual(r.hoursNeeded, 0)
        XCTAssertFalse(r.isWorthIt)

        // Een negatieve goedkopere prijs is 0 en wint dus van 100.
        let c = PurchaseCalc.evaluate(purInput(100, willing: 8, cheaper: -30, cheaperShipping: -5))
        XCTAssertEqual(c.totalCost, 0)
        XCTAssertEqual(c.savedByCheaper, 100)

        // Een negatief uurloon is geen uurloon.
        let w = PurchaseCalc.evaluate(purInput(100, willing: 8, wage: -20))
        XCTAssertFalse(w.hasWage)
        XCTAssertEqual(w.hourlyWage, 0)
    }

    func testWithoutWageNothingIsWorthIt() {
        let r = PurchaseCalc.evaluate(purInput(100, willing: 50, wage: 0))
        XCTAssertFalse(r.hasWage)
        XCTAssertEqual(r.hoursNeeded, 0)
        XCTAssertFalse(r.isWorthIt)
        XCTAssertEqual(r.feedback.count, 1)
        XCTAssertEqual(r.feedback.first?.kind, .neutral)
        XCTAssertTrue(r.feedback.first?.text.contains("uurloon") ?? false)
    }

    func testVeryLargeAmounts() {
        let r = PurchaseCalc.evaluate(purInput(1e15, shipping: 1e15, willing: 200))
        XCTAssertEqual(r.totalCost, 1_000_000_000)     // het totaal wordt begrensd op 1 miljard
        XCTAssertEqual(r.hoursNeeded, 50_000_000)        // 1 miljard / 20
        XCTAssertFalse(r.isWorthIt)
        XCTAssertEqual(r.daysOfWork, 6_250_000, accuracy: 0.001)
        XCTAssertFalse(r.feedback.isEmpty)

        let inf = PurchaseCalc.evaluate(purInput(.infinity, willing: 200))
        XCTAssertEqual(inf.totalCost, PurchaseCalc.maxAmount)
        let nan = PurchaseCalc.evaluate(purInput(.nan, willing: .nan, wage: .nan))
        XCTAssertEqual(nan.totalCost, 0)
        XCTAssertEqual(nan.hoursWilling, 0)
        XCTAssertFalse(nan.hasWage)

        // Heel laag uurloon geeft een enorm aantal uren, zonder overflow.
        let low = PurchaseCalc.evaluate(purInput(1e9, willing: 200, wage: 0.01))
        XCTAssertEqual(low.hoursNeeded, 1e11)
        XCTAssertFalse(low.isWorthIt)
    }

    func testHoursWillingIsRoundedToTenths() {
        XCTAssertEqual(PurchaseCalc.evaluate(purInput(100, willing: 5.54)).hoursWilling, 5.5)
        XCTAssertEqual(PurchaseCalc.evaluate(purInput(100, willing: 1e12)).hoursWilling, PurchaseCalc.maxHours)
    }

    func testShareOfMonthlyIncome() {
        let r = PurchaseCalc.evaluate(purInput(600, willing: 50), context: purContext(income: 3000))
        XCTAssertEqual(r.shareOfMonthlyIncome ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertNil(PurchaseCalc.evaluate(purInput(600, willing: 50)).shareOfMonthlyIncome)
    }

    func testCostPerYearUsesCategoryLifespan() {
        // Elektronica: 4 jaar. 400 / 4 = 100 per jaar; 400 / 20 = 20 uur, dus 5 uur per jaar.
        let r = PurchaseCalc.evaluate(purInput(400, willing: 30, category: .electronics))
        XCTAssertEqual(r.costPerYear ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(r.hoursPerYear ?? 0, 5, accuracy: 0.0001)
        XCTAssertTrue(purAnyContains(r.feedback, "per jaar"))
        // Entertainment is verbruik: geen kosten per jaar.
        let e = PurchaseCalc.evaluate(purInput(400, willing: 30, category: .entertainment))
        XCTAssertNil(e.costPerYear)
        XCTAssertNil(e.hoursPerYear)
        XCTAssertFalse(purAnyContains(e.feedback, "per jaar"))
    }

    // MARK: Feedback

    func testNotWorthFeedbackSaysHowManyHoursTooMany() {
        let r = PurchaseCalc.evaluate(purInput(100, willing: 4))
        XCTAssertFalse(r.isWorthIt)
        XCTAssertEqual(r.feedback.first?.kind, .warning)
        let first = r.feedback.first?.text ?? ""
        XCTAssertTrue(first.contains("4 uur"), first)
        XCTAssertTrue(first.contains("5 uur"), first)
        XCTAssertTrue(first.contains("1 uur meer"), first)
        // Een prijs die wel past: 4 uur × 20 = 80.
        XCTAssertTrue(purAnyContains(r.feedback, Fmt.euro(80), kind: .neutral))
        // Niets positiefs over de aankoop zelf.
        XCTAssertTrue(purTexts(r.feedback, .positive).isEmpty)
    }

    func testEqualHoursFeedbackExplainsEqualIsNotEnough() {
        let r = PurchaseCalc.evaluate(purInput(100, willing: 5))
        XCTAssertEqual(r.feedback.first?.kind, .warning)
        XCTAssertTrue(r.feedback.first?.text.contains("precies") ?? false)
        XCTAssertTrue(r.feedback.first?.text.contains("niet waard") ?? false)
    }

    func testNoHoursChosenFeedback() {
        let r = PurchaseCalc.evaluate(purInput(100, willing: 0))
        XCTAssertFalse(r.isWorthIt)
        XCTAssertTrue(r.feedback.first?.text.contains("geen uur") ?? false)
        // Zonder gekozen uren geen "past bij"-prijs van 0 euro.
        XCTAssertFalse(purAnyContains(r.feedback, "Bij 0 uur"))
    }

    func testWorthFeedbackSaysWhyItCanBeDone() {
        let r = PurchaseCalc.evaluate(purInput(100, willing: 8))
        XCTAssertTrue(r.isWorthIt)
        XCTAssertEqual(r.feedback.first?.kind, .positive)
        let first = r.feedback.first?.text ?? ""
        XCTAssertTrue(first.contains("8 uur"), first)
        XCTAssertTrue(first.contains("5 uur"), first)
        XCTAssertTrue(first.contains("3 uur over"), first)
        XCTAssertTrue(purTexts(r.feedback, .warning).isEmpty)
    }

    func testToneFollowsHowNecessaryTheCategoryIs() {
        for category in PurchaseCategory.allCases {
            let worth = PurchaseCalc.evaluate(purInput(100, willing: 8, category: category))
            XCTAssertTrue(purTexts(worth.feedback).contains(category.needLevel.toneWhenWorth), category.title)
            XCTAssertFalse(purTexts(worth.feedback).contains(category.needLevel.toneWhenNotWorth), category.title)
            let notWorth = PurchaseCalc.evaluate(purInput(100, willing: 2, category: category))
            XCTAssertTrue(purTexts(notWorth.feedback).contains(category.needLevel.toneWhenNotWorth), category.title)
            XCTAssertFalse(purTexts(notWorth.feedback).contains(category.needLevel.toneWhenWorth), category.title)
        }
        // De drie niveaus hebben elk een eigen toon.
        let levels: [PurchaseNeedLevel] = [.need, .mixed, .want]
        XCTAssertEqual(Set(levels.map(\.toneWhenWorth)).count, 3)
        XCTAssertEqual(Set(levels.map(\.toneWhenNotWorth)).count, 3)
    }

    func testWaitTipOnlyForImpulseCategoriesAndRealAmounts() {
        let electronics = PurchaseCalc.evaluate(purInput(300, willing: 30, category: .electronics))
        XCTAssertTrue(purTexts(electronics.feedback).contains(PurchaseCategory.electronics.waitNote ?? "-"))
        XCTAssertTrue(PurchaseCategory.electronics.waitNote?.contains("7 dagen") ?? false)
        XCTAssertTrue(PurchaseCategory.clothing.waitNote?.contains("24 uur") ?? false)
        // Onder 25 euro is wachten overdreven.
        let cheap = PurchaseCalc.evaluate(purInput(10, willing: 5, category: .electronics))
        XCTAssertFalse(purTexts(cheap.feedback).contains(PurchaseCategory.electronics.waitNote ?? "-"))
        // Precies op de grens telt wel.
        let edge = PurchaseCalc.evaluate(purInput(25, willing: 5, category: .electronics))
        XCTAssertTrue(purTexts(edge.feedback).contains(PurchaseCategory.electronics.waitNote ?? "-"))
        // Gezondheid heeft geen wachttijd.
        XCTAssertNil(PurchaseCategory.health.waitNote)
        let health = PurchaseCalc.evaluate(purInput(300, willing: 30, category: .health))
        XCTAssertFalse(purAnyContains(health.feedback, "Wacht "))
    }

    func testIncomeShareWarningFromQuarterOfIncome() {
        // 300 van 1000 = 30%
        let big = PurchaseCalc.evaluate(purInput(300, willing: 30), context: purContext(income: 1000))
        XCTAssertTrue(purAnyContains(big.feedback, "30%", kind: .warning))
        // 250 van 1000 = 25%: precies op de grens.
        let edge = PurchaseCalc.evaluate(purInput(250, willing: 30), context: purContext(income: 1000))
        XCTAssertTrue(purAnyContains(edge.feedback, "25%", kind: .warning))
        // 200 van 1000 = 20%: geen waarschuwing.
        let small = PurchaseCalc.evaluate(purInput(200, willing: 30), context: purContext(income: 1000))
        XCTAssertFalse(purAnyContains(small.feedback, "maandinkomen"))
    }

    func testAffordabilityIsPartOfFeedbackOnlyWhenWorthIt() {
        let easy = purContext(remaining: 500)
        let worth = PurchaseCalc.evaluate(purInput(100, willing: 8), context: easy)
        XCTAssertTrue(purAnyContains(worth.feedback, "Kan zonder pijn", kind: .positive))
        // Niet waard: de uitspraak "kan het" staat apart in `affordability`, niet in de feedback.
        let notWorth = PurchaseCalc.evaluate(purInput(100, willing: 2), context: easy)
        XCTAssertFalse(purAnyContains(notWorth.feedback, "Kan zonder pijn"))
        XCTAssertEqual(notWorth.affordability.verdict, .easy)

        let broke = purContext(remaining: 20, surplus: 0, balance: 30)
        let blocked = PurchaseCalc.evaluate(purInput(100, willing: 8), context: broke)
        XCTAssertTrue(blocked.isWorthIt)
        XCTAssertTrue(purAnyContains(blocked.feedback, "Kan nu niet", kind: .warning))

        // Zonder gegevens zegt de feedback niets over geld.
        let unknown = PurchaseCalc.evaluate(purInput(100, willing: 8))
        XCTAssertEqual(unknown.affordability.verdict, .unknown)
        XCTAssertFalse(purAnyContains(unknown.feedback, "Kan "))
    }

    func testFeedbackNeverRepeatsALine() {
        for category in PurchaseCategory.allCases {
            for willing in [0.0, 2, 5, 5.5, 20] {
                for cheaper in [nil, 80.0] as [Double?] {
                    let r = PurchaseCalc.evaluate(purInput(100, willing: willing, category: category, cheaper: cheaper),
                                                  context: purContext(remaining: 500, income: 400))
                    let ids = r.feedback.map(\.id)
                    XCTAssertEqual(ids.count, Set(ids).count, "\(category) \(willing)")
                    XCTAssertFalse(r.feedback.isEmpty)
                }
            }
        }
    }

    // MARK: Kan het?

    func testNoDataMeansUnknown() {
        XCTAssertEqual(PurchaseCalc.affordability(totalCost: 300, context: PurchaseContext()).verdict, .unknown)
        // Ook bij een bedrag van nul: eerst de gegevens, dan pas het bedrag.
        XCTAssertEqual(PurchaseCalc.affordability(totalCost: 0, context: PurchaseContext()).verdict, .unknown)
        XCTAssertEqual(PurchaseVerdict.easy.title, "Kan zonder pijn")
        XCTAssertEqual(PurchaseVerdict.tight.title, "Kan, maar het gaat ten koste van je buffer of spaarpot")
        XCTAssertEqual(PurchaseVerdict.notNow.title, "Kan nu niet")
    }

    func testFitsInWhatIsLeftThisMonth() {
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 500))
        XCTAssertEqual(a.verdict, .easy)
        XCTAssertTrue(a.summary.contains("deze maand"))
        XCTAssertTrue(purAnyContains(a.details, Fmt.euro(200), kind: .positive))   // 500 - 300 blijft over
        // Precies genoeg is ook genoeg.
        let exact = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 300))
        XCTAssertEqual(exact.verdict, .easy)
        XCTAssertTrue(purAnyContains(exact.details, "precies genoeg"))
        // Een cent te weinig niet (en geen andere bron).
        let short = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 299.99))
        XCTAssertEqual(short.verdict, .notNow)
    }

    func testFitsAboveTheBankBuffer() {
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 100, surplus: 350, balance: 900))
        XCTAssertEqual(a.verdict, .easy)
        XCTAssertTrue(a.summary.contains("boven je buffer"))
        XCTAssertTrue(purAnyContains(a.details, "boven je buffer", kind: .positive))
        XCTAssertTrue(purAnyContains(a.details, "Je hebt deze maand nog", kind: .warning))   // maand zelf is te weinig
    }

    func testTightWhenOnlyAPotCanPay() {
        let vakantie = PurchasePotOption(name: "Vakantie", balance: 800, goalAmount: 1000, monthlyContribution: 100)
        let ctx = purContext(remaining: 100, surplus: 0, balance: 50, pots: [vakantie])
        let a = PurchaseCalc.affordability(totalCost: 300, context: ctx)
        XCTAssertEqual(a.verdict, .tight)
        XCTAssertEqual(a.potName, "Vakantie")
        XCTAssertEqual(a.potID, vakantie.id)
        XCTAssertTrue(a.summary.contains("Vakantie"))
        // Doel: nog 200 te gaan = 2 maanden; na de aankoop 500 te gaan = 5 maanden: 3 maanden later.
        XCTAssertEqual(a.goalDelayMonths, 3)
        XCTAssertTrue(purAnyContains(a.details, Fmt.duration(months: 3), kind: .warning))
    }

    func testTightWhenOnlyTheBufferOfTheBankPays() {
        // Saldo 400 is genoeg voor 300, maar er staat maar 20 boven de buffer: 280 onder de buffer.
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 0, surplus: 20, balance: 400))
        XCTAssertEqual(a.verdict, .tight)
        XCTAssertTrue(a.summary.contains("bankbuffer"))
        XCTAssertTrue(purAnyContains(a.details, Fmt.euro(280), kind: .warning))
        XCTAssertNil(a.potID)
    }

    func testNotNowWhenNothingHasEnough() {
        let pot = PurchasePotOption(name: "Reis", balance: 200)
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 50, surplus: 0, balance: 100, pots: [pot]))
        XCTAssertEqual(a.verdict, .notNow)
        XCTAssertNil(a.potID)
        XCTAssertTrue(purAnyContains(a.details, "Geen enkele spaarpot heeft genoeg", kind: .warning))
        XCTAssertTrue(purAnyContains(a.details, Fmt.euro(200)))   // de grootste pot
        XCTAssertTrue(purAnyContains(a.details, "te weinig", kind: .warning))
    }

    func testOverspentMonthIsNotFree() {
        let a = PurchaseCalc.affordability(totalCost: 50, context: purContext(remaining: -100))
        XCTAssertEqual(a.verdict, .notNow)
        XCTAssertTrue(purAnyContains(a.details, "meer verdeeld dan je hebt"))
        let zero = PurchaseCalc.affordability(totalCost: 50, context: purContext(remaining: 0))
        XCTAssertEqual(zero.verdict, .notNow)
        XCTAssertTrue(purAnyContains(zero.details, "alles al verdeeld"))
    }

    func testSeveralPotsTogetherCanPayButNoSingleOne() {
        let pots = [PurchasePotOption(name: "A", balance: 200), PurchasePotOption(name: "B", balance: 150)]
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 0, pots: pots))
        XCTAssertEqual(a.verdict, .tight)
        XCTAssertNil(a.potID)
        XCTAssertTrue(a.summary.contains("meerdere spaarpotten"))
        XCTAssertTrue(purAnyContains(a.details, Fmt.euro(350)))
    }

    func testPrefersAPotThatIsNotTheBuffer() {
        let buffer = PurchasePotOption(name: "Buffer", balance: 1000, isBuffer: true)
        let reis = PurchasePotOption(name: "Reis", balance: 400)
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 0, pots: [buffer, reis]))
        XCTAssertEqual(a.potName, "Reis")
        XCTAssertFalse(purAnyContains(a.details, "dit is je buffer"))
    }

    func testBufferIsLastResortAndComesWithAWarning() {
        let buffer = PurchasePotOption(name: "Buffer", balance: 1000, isBuffer: true)
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 0, pots: [buffer]))
        XCTAssertEqual(a.verdict, .tight)
        XCTAssertEqual(a.potName, "Buffer")
        XCTAssertTrue(a.summary.contains("buffer"))
        XCTAssertTrue(purAnyContains(a.details, "dit is je buffer", kind: .warning))
    }

    func testPrefersPotWithLeastEffectOnItsGoal() {
        // A: 500 van 800, inleg 50. Nu 6 maanden te gaan, na 300 uitgeven 12: 6 maanden later.
        let a = PurchasePotOption(name: "A", balance: 500, goalAmount: 800, monthlyContribution: 50)
        // B: groter, zonder doel: geen gevolgen.
        let b = PurchasePotOption(name: "B", balance: 600)
        let result = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 0, pots: [a, b]))
        XCTAssertEqual(result.potName, "B")
        XCTAssertNil(result.goalDelayMonths)
        // Zonder doelen: de kleinste pot die genoeg heeft.
        let c = PurchasePotOption(name: "C", balance: 350)
        let small = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 0, pots: [b, c]))
        XCTAssertEqual(small.potName, "C")
    }

    func testNegativePotBalanceCountsAsEmpty() {
        let pot = PurchasePotOption(name: "Min", balance: -50)
        let a = PurchaseCalc.affordability(totalCost: 10, context: purContext(remaining: 0, pots: [pot]))
        XCTAssertEqual(a.verdict, .notNow)
    }

    func testZeroCostIsAlwaysEasyWithData() {
        let a = PurchaseCalc.affordability(totalCost: 0, context: purContext(remaining: -500))
        XCTAssertEqual(a.verdict, .easy)
    }

    func testGoalImpactEstimates() {
        // Geen doel.
        XCTAssertEqual(PurchaseCalc.goalImpact(of: PurchasePotOption(name: "x", balance: 500), spending: 100), PurchaseGoalImpact.none)
        // Ver boven het doel, blijft erboven.
        let high = PurchasePotOption(name: "x", balance: 1500, goalAmount: 1000, monthlyContribution: 100)
        XCTAssertEqual(PurchaseCalc.goalImpact(of: high, spending: 300), .unaffected)
        // Net boven het doel, zakt eronder: nog 200 te gaan bij 100 per maand = 2 maanden.
        let edge = PurchasePotOption(name: "x", balance: 1100, goalAmount: 1000, monthlyContribution: 100)
        XCTAssertEqual(PurchaseCalc.goalImpact(of: edge, spending: 300), .delayed(months: 2))
        // Zonder inleg haal je het doel daarna niet meer.
        let noSaving = PurchasePotOption(name: "x", balance: 1100, goalAmount: 1000, monthlyContribution: 0)
        XCTAssertEqual(PurchaseCalc.goalImpact(of: noSaving, spending: 300), .unreachable)
        // Onder het doel zonder inleg: er was al geen einde in zicht.
        let stuck = PurchasePotOption(name: "x", balance: 500, goalAmount: 1000, monthlyContribution: 0)
        XCTAssertEqual(PurchaseCalc.goalImpact(of: stuck, spending: 100), PurchaseGoalImpact.none)
        // Afronden naar boven: 400 te gaan = 4 maanden; na 250 uitgeven 650 te gaan = 6,5 -> 7 maanden: 3 later.
        let round = PurchasePotOption(name: "x", balance: 600, goalAmount: 1000, monthlyContribution: 100)
        XCTAssertEqual(PurchaseCalc.goalImpact(of: round, spending: 250), .delayed(months: 3))
        // Doel met doelbedrag 0 telt niet.
        let zeroGoal = PurchasePotOption(name: "x", balance: 500, goalAmount: 0, monthlyContribution: 100)
        XCTAssertEqual(PurchaseCalc.goalImpact(of: zeroGoal, spending: 100), PurchaseGoalImpact.none)
    }

    // MARK: Gegevens uit de app

    func testContextFromEmptyData() {
        let d = FinanceData(startMonth: aug2026)
        let ctx = PurchaseContext.make(from: d, current: oct2026, today: day(oct2026, 15))
        XCTAssertEqual(ctx.monthlyIncome, 0)
        XCTAssertNil(ctx.remainingThisMonth)
        XCTAssertNil(ctx.bankBalance)
        XCTAssertNil(ctx.bankSurplus)
        XCTAssertTrue(ctx.pots.isEmpty)
        XCTAssertEqual(PurchaseCalc.affordability(totalCost: 100, context: ctx).verdict, .unknown)
    }

    func testContextFromRealData() {
        var d = makeBaseData()
        let buffer = addBufferPot(&d, opening: 500, goal: 2000)
        d.addBankSnapshot(balance: 4000, date: day(aug2026, 1))
        let today = day(oct2026, 15)
        let ctx = PurchaseContext.make(from: d, current: oct2026, today: today)

        // Oktober: salaris 3000 + toeslag 100 = 3100. Uitgaven: huur 1000. Inleg buffer: 200.
        // Nog te verdelen: 3100 - 1000 - 200 = 1900.
        XCTAssertEqual(ctx.monthlyIncome, 3100, accuracy: 0.001)
        XCTAssertEqual(ctx.remainingThisMonth ?? 0, 1900, accuracy: 0.001)

        XCTAssertEqual(ctx.bankBalance, d.bankBalanceNow(current: oct2026, today: today))
        XCTAssertEqual(ctx.bankSurplus, d.bankSurplusAboveBuffer(current: oct2026, today: today))
        XCTAssertNotNil(ctx.bankBalance)

        XCTAssertEqual(ctx.pots.count, 1)
        let option = ctx.pots[0]
        XCTAssertEqual(option.id, buffer.id)
        XCTAssertEqual(option.name, "Buffer")
        XCTAssertTrue(option.isBuffer)
        XCTAssertEqual(option.goalAmount, 2000)
        XCTAssertEqual(option.monthlyContribution, 200, accuracy: 0.001)
        XCTAssertEqual(option.balance, d.potBalanceNow(buffer.id, current: oct2026, today: today), accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(option.balance, 500)
    }

    func testOtherPotsAreNotMarkedAsBuffer() {
        var d = makeBaseData()
        d.addPot(Pot(name: "Vakantie", monthlyContribution: 0, startMonth: aug2026), openingBalance: 300, now: day(aug2026, 1))
        let ctx = PurchaseContext.make(from: d, current: oct2026, today: day(oct2026, 15))
        XCTAssertEqual(ctx.pots.count, 1)
        XCTAssertFalse(ctx.pots[0].isBuffer)
        XCTAssertEqual(ctx.pots[0].balance, 300, accuracy: 0.001)
    }

    func testWholeCheckFromRealData() {
        var d = makeBaseData()
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 36)
        let today = day(oct2026, 15)
        let wage = PurchaseCalc.resolvedWage(manual: 0, data: d)
        XCTAssertEqual(wage ?? 0, 19.23, accuracy: 0.0001)
        let ctx = PurchaseContext.make(from: d, current: oct2026, today: today)
        // Laptop van 600 + 10 verzending = 610; 610 / 19,23 = 31,72 -> 31,7 uur.
        let r = PurchaseCalc.evaluate(purInput(600, shipping: 10, willing: 32, wage: wage ?? 0), context: ctx)
        XCTAssertEqual(r.hoursNeeded, 31.7, accuracy: 0.0001)
        XCTAssertTrue(r.isWorthIt)            // 32 > 31,7
        XCTAssertEqual(r.affordability.verdict, .easy)   // 3100 - 1000 = 2100 vrij deze maand
        let tooLittle = PurchaseCalc.evaluate(purInput(600, shipping: 10, willing: 31.5, wage: wage ?? 0), context: ctx)
        XCTAssertFalse(tooLittle.isWorthIt)
        // 610 van 3100 = 19,7% van het maandinkomen.
        XCTAssertEqual(r.shareOfMonthlyIncome ?? 0, 610.0 / 3100.0, accuracy: 1e-9)
    }

    // MARK: Herstel na review: bank, afronding, buffer, sleutel

    func testPlanFitsButBankCannotPayIsNotEasy() {
        // Vlak voor de uitbetaaldag: 1900 nog te verdelen in het plan, maar er staat maar 100 op de rekening.
        let ctx = purContext(remaining: 1900, surplus: 0, balance: 100)
        let a = PurchaseCalc.affordability(totalCost: 300, context: ctx)
        XCTAssertEqual(a.verdict, .notNow)
        XCTAssertTrue(a.summary.contains("maandplan"), a.summary)
        XCTAssertTrue(a.summary.contains("banksaldo"), a.summary)
        XCTAssertFalse(a.summary.contains("spaar er eerst voor"), a.summary)
        XCTAssertTrue(purAnyContains(a.details, "Je hebt deze maand nog", kind: .positive))
        XCTAssertTrue(purAnyContains(a.details, "Je banksaldo is", kind: .warning))
        XCTAssertNil(a.potID)

        // Met een gewone pot die genoeg heeft kan het nu wel, uit die pot.
        let reis = PurchasePotOption(name: "Reis", balance: 500)
        let withPot = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 1900, surplus: 0, balance: 100, pots: [reis]))
        XCTAssertEqual(withPot.verdict, .tight)
        XCTAssertEqual(withPot.potName, "Reis")
        XCTAssertTrue(withPot.summary.contains("maandplan"), withPot.summary)
        XCTAssertTrue(withPot.summary.contains("Reis"), withPot.summary)

        // De buffer is geen uitweg als het plan het ook gewoon later kan betalen.
        let buffer = PurchasePotOption(name: "Buffer", balance: 1000, isBuffer: true)
        let withBuffer = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 1900, surplus: 0, balance: 100, pots: [buffer]))
        XCTAssertEqual(withBuffer.verdict, .notNow)
        XCTAssertNil(withBuffer.potID)

        // Zonder bekend banksaldo blijft het maandplan genoeg.
        XCTAssertEqual(PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 1900)).verdict, .easy)
    }

    func testBankCoversAndPlanFitsStaysEasyWithoutWarning() {
        // Saldo 400 is genoeg voor 300 en het past in het plan, ook al komt het 280 onder de bankbuffer.
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 1900, surplus: 20, balance: 400))
        XCTAssertEqual(a.verdict, .easy)
        XCTAssertTrue(purAnyContains(a.details, "onder je bankbuffer", kind: .neutral))
        XCTAssertTrue(purAnyContains(a.details, "maandplan", kind: .neutral))
        XCTAssertTrue(purTexts(a.details, .warning).isEmpty, "geen waarschuwing naast 'kan zonder pijn'")
    }

    func testFeedbackSaysNotNowWhenPlanFitsButBankIsShort() {
        let ctx = purContext(remaining: 1900, surplus: 0, balance: 100)
        let r = PurchaseCalc.evaluate(purInput(300, willing: 30), context: ctx)
        XCTAssertTrue(r.isWorthIt)
        XCTAssertTrue(purAnyContains(r.feedback, "Kan nu niet", kind: .warning))
        XCTAssertFalse(purAnyContains(r.feedback, "Kan zonder pijn"))
    }

    func testSmallAmountsNeverShowAsZeroEuro() {
        XCTAssertEqual(PurchaseCalc.moneyText(0.4), Fmt.euroExact(0.4))
        XCTAssertEqual(PurchaseCalc.moneyText(0.99), Fmt.euroExact(0.99))
        XCTAssertEqual(PurchaseCalc.moneyText(1), Fmt.euro(1))
        XCTAssertEqual(PurchaseCalc.moneyText(250.4), Fmt.euro(250.4))
        XCTAssertEqual(PurchaseCalc.moneyText(0), Fmt.euro(0))

        // 299,60 tegenover 300: "€ 0,40 te weinig" en niet "€ 0 te weinig".
        let a = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 299.6))
        XCTAssertEqual(a.verdict, .notNow)
        XCTAssertTrue(purAnyContains(a.details, Fmt.euroExact(0.4) + " te weinig", kind: .warning), a.details.map(\.text).joined(separator: " | "))
        XCTAssertFalse(purAnyContains(a.details, Fmt.euro(0) + " te weinig"))

        // Onder de bankbuffer met minder dan een euro.
        let b = PurchaseCalc.affordability(totalCost: 300, context: purContext(remaining: 0, surplus: 299.5, balance: 400))
        XCTAssertEqual(b.verdict, .tight)
        XCTAssertTrue(purAnyContains(b.details, Fmt.euroExact(0.5) + " onder je bankbuffer", kind: .warning))

        // Goedkoper met 40 cent verschil: "scheelt € 0,40".
        let r = PurchaseCalc.evaluate(purInput(100, willing: 8, cheaper: 99.6))
        XCTAssertTrue(r.usesCheaper)
        XCTAssertEqual(r.savedByCheaper, 0.4, accuracy: 1e-9)
        XCTAssertTrue(purAnyContains(r.feedback, "scheelt " + Fmt.euroExact(0.4)))
        XCTAssertFalse(purAnyContains(r.feedback, "scheelt " + Fmt.euro(0) + "."))   // eindigt dus niet op "€ 0."
    }

    func testTinyPriceSaysLessThanATenthOfAnHour() {
        XCTAssertEqual(PurchaseCalc.costHoursText(0), "minder dan 0,1 uur")
        XCTAssertEqual(PurchaseCalc.costHoursText(1.5), "1,5 uur")
        // 50 cent bij 20 euro per uur: 0,025 uur, afgerond 0,0.
        let worth = PurchaseCalc.evaluate(purInput(0.5, willing: 2))
        XCTAssertEqual(worth.hoursNeeded, 0)
        XCTAssertTrue(worth.isWorthIt)
        let text = worth.feedback.first?.text ?? ""
        XCTAssertTrue(text.contains("het kost minder dan 0,1 uur"), text)
        XCTAssertFalse(text.contains("kost 0 uur"), text)
        let none = PurchaseCalc.evaluate(purInput(0.5, willing: 0))
        let noneText = none.feedback.first?.text ?? ""
        XCTAssertTrue(noneText.contains("minder dan 0,1 uur"), noneText)
        XCTAssertFalse(noneText.contains("kost 0 uur"), noneText)
    }

    func testWorkdaysCaptionOnlySaysApproximatelyFromOneDay() {
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 0), "minder dan een werkdag")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 0.04), "minder dan een werkdag")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 0.1), "minder dan een werkdag")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 0.94), "minder dan een werkdag")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 0.96), "ongeveer 1 werkdag")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 1), "ongeveer 1 werkdag")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 2.5), "ongeveer 2,5 werkdagen")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: 20), "ongeveer 20 werkdagen")
        XCTAssertEqual(PurchaseCalc.workdaysCaption(days: -3), "minder dan een werkdag")
    }

    func testIncomeShareTextHidesNothingWorthMentioning() {
        XCTAssertNil(PurchaseCalc.incomeShareText(0))
        XCTAssertNil(PurchaseCalc.incomeShareText(0.004))
        XCTAssertNil(PurchaseCalc.incomeShareText(0.0099))
        XCTAssertNil(PurchaseCalc.incomeShareText(.nan))
        XCTAssertEqual(PurchaseCalc.incomeShareText(0.01), "Dat is 1% van je maandinkomen.")
        XCTAssertEqual(PurchaseCalc.incomeShareText(0.2), "Dat is 20% van je maandinkomen.")
    }

    func testPerYearLineSkipsAmountsUnderOneEuroAndEmptyHours() {
        // Elektronica gaat 4 jaar mee. 3 euro is 0,75 per jaar: geen regel.
        let tiny = PurchaseCalc.evaluate(purInput(3, willing: 5, category: .electronics))
        XCTAssertFalse(purAnyContains(tiny.feedback, "per jaar"))
        // 4 euro is precies 1 euro per jaar. Bij 1000 euro per uur is dat 0,0 uur per jaar: dat laten we weg.
        let small = PurchaseCalc.evaluate(purInput(4, willing: 1, wage: 1000, category: .electronics))
        let line = small.feedback.first { $0.text.contains("per jaar") }?.text ?? ""
        XCTAssertTrue(line.contains("per jaar"), line)
        XCTAssertFalse(line.contains("werken per jaar"), line)
        XCTAssertFalse(line.contains("0 uur"), line)
        // Bij 400 euro blijft de regel zoals hij was.
        let normal = PurchaseCalc.evaluate(purInput(400, willing: 30, category: .electronics))
        XCTAssertTrue(purAnyContains(normal.feedback, "werken per jaar"))
    }

    func testChosenBufferPotIsMarkedAsBuffer() {
        var d = makeBaseData()
        let named = addBufferPot(&d, opening: 500, goal: 2000)   // heet "Buffer"
        let fonds = Pot(name: "Noodfonds", monthlyContribution: 0, startMonth: aug2026)
        d.addPot(fonds, openingBalance: 300, now: day(aug2026, 3))
        let today = day(oct2026, 15)

        // Zonder keuze: de pot die "Buffer" heet.
        let byName = PurchaseContext.make(from: d, current: oct2026, today: today)
        XCTAssertEqual(byName.pots.first { $0.id == named.id }?.isBuffer, true)
        XCTAssertEqual(byName.pots.first { $0.id == fonds.id }?.isBuffer, false)

        // De gebruiker koos "Noodfonds" op de Buffer-pagina: alleen die telt als buffer.
        let chosen = PurchaseContext.make(from: d, current: oct2026, today: today, bufferPotID: fonds.id)
        XCTAssertEqual(chosen.pots.first { $0.id == fonds.id }?.isBuffer, true)
        XCTAssertEqual(chosen.pots.first { $0.id == named.id }?.isBuffer, false)
        XCTAssertEqual(chosen.pots.filter(\.isBuffer).count, 1)

        // Een gekozen pot die niet meer bestaat valt terug op de naam.
        let gone = PurchaseContext.make(from: d, current: oct2026, today: today, bufferPotID: UUID())
        XCTAssertEqual(gone.pots.first { $0.id == named.id }?.isBuffer, true)
        XCTAssertEqual(gone.pots.filter(\.isBuffer).count, 1)

        // En de waarschuwing volgt de keuze: 250 uit het Noodfonds krijgt "dit is je buffer".
        let a = PurchaseCalc.affordability(totalCost: 250, context: PurchaseContext(
            monthlyIncome: 0, remainingThisMonth: 0, bankBalance: nil, bankSurplus: nil,
            pots: chosen.pots.filter { $0.id == fonds.id }))
        XCTAssertTrue(purAnyContains(a.details, "dit is je buffer", kind: .warning))
    }

    func testManualWageKeyIsPerAccount() {
        XCTAssertEqual(PurchaseCalc.accountWageKey(nil), PurchaseCalc.wageStorageKey + ".demo")
        XCTAssertEqual(PurchaseCalc.accountWageKey("A1"), PurchaseCalc.wageStorageKey + ".A1")
        XCTAssertNotEqual(PurchaseCalc.accountWageKey("A1"), PurchaseCalc.accountWageKey("B2"))
        XCTAssertNotEqual(PurchaseCalc.accountWageKey("A1"), PurchaseCalc.accountWageKey(nil))
    }

    // MARK: Soorten aankopen

    func testCategoriesAreComplete() {
        let all = PurchaseCategory.allCases
        XCTAssertGreaterThanOrEqual(all.count, 10)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for category in all {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.shortTitle.isEmpty)
            XCTAssertFalse(category.symbol.isEmpty)
            XCTAssertGreaterThan(category.tip.count, 30, category.title)
            XCTAssertTrue((0.0...1.0).contains(category.need), category.title)
            if let life = category.lifespanYears { XCTAssertGreaterThan(life, 0, category.title) }
            XCTAssertEqual(category.waitText == nil, category.waitDays == 0, category.title)
            XCTAssertEqual(category.waitNote == nil, category.waitDays == 0, category.title)
        }
        let titles = Set(all.map(\.title))
        for expected in ["Elektronica", "Kleding en schoenen", "Huis en inrichting", "Hobby en sport",
                         "Entertainment en uitgaan", "Vervoer", "Gezondheid en verzorging", "Cadeaus",
                         "Eten en drinken", "Overig"] {
            XCTAssertTrue(titles.contains(expected), expected)
        }
    }

    func testNeedLevelsMatchTheTone() {
        XCTAssertEqual(PurchaseCategory.health.needLevel, .need)
        XCTAssertEqual(PurchaseCategory.transport.needLevel, .need)
        XCTAssertEqual(PurchaseCategory.electronics.needLevel, .mixed)
        XCTAssertEqual(PurchaseCategory.entertainment.needLevel, .want)
        XCTAssertEqual(PurchaseCategory.hobby.needLevel, .want)
        XCTAssertEqual(PurchaseCategory.electronics.waitDays, 7)
        XCTAssertEqual(PurchaseCategory.clothing.waitDays, 1)
        XCTAssertTrue(PurchaseCategory.electronics.tip.contains("refurbished"))
        XCTAssertTrue(PurchaseCategory.clothing.tip.contains("per keer dragen"))
    }

    // MARK: Zoeklinks

    private func link(_ id: String, in links: [PurchaseSearchLink]) -> String? {
        links.first { $0.id == id }?.url.absoluteString
    }

    func testSearchLinksEncodeSpaces() {
        let links = PurchaseSearch.links(for: "iPhone 15 Pro")
        XCTAssertEqual(link("beslist", in: links), "https://www.beslist.nl/products/r/iPhone%2015%20Pro/")
        XCTAssertEqual(link("google", in: links), "https://www.google.com/search?tbm=shop&hl=nl&gl=nl&q=iPhone%2015%20Pro")
        XCTAssertEqual(link("kieskeurig", in: links), "https://www.kieskeurig.nl/zoeken?q=iPhone%2015%20Pro")
        XCTAssertEqual(links.count, 3)
        for l in links {
            XCTAssertFalse(l.title.isEmpty)
            XCTAssertFalse(l.symbol.isEmpty)
            XCTAssertEqual(l.url.scheme, "https")
        }
    }

    func testElectronicsGetsTweakersOthersGetKieskeurig() {
        let tech = PurchaseSearch.links(for: "laptop", category: .electronics)
        XCTAssertEqual(tech.map(\.id), ["beslist", "google", "tweakers"])
        XCTAssertEqual(link("tweakers", in: tech), "https://tweakers.net/pricewatch/zoeken/?keyword=laptop")
        XCTAssertEqual(tech.last?.title, "Tweakers Pricewatch")
        let other = PurchaseSearch.links(for: "laptop", category: .home)
        XCTAssertEqual(other.map(\.id), ["beslist", "google", "kieskeurig"])
        XCTAssertEqual(PurchaseSearch.links(for: "laptop", category: nil).map(\.id), ["beslist", "google", "kieskeurig"])
    }

    func testSearchLinksEncodeAmpersandsAndSpecialCharacters() {
        let amp = PurchaseSearch.links(for: "Tom & Jerry")
        XCTAssertTrue(link("google", in: amp)?.hasSuffix("&q=Tom%20%26%20Jerry") ?? false)
        XCTAssertTrue(link("beslist", in: amp)?.hasSuffix("/Tom%20%26%20Jerry/") ?? false)
        // Een gewone & in de naam mag nooit een extra queryveld worden.
        XCTAssertEqual(link("kieskeurig", in: amp)?.components(separatedBy: "&").count, 1)

        let special = PurchaseSearch.links(for: "C++ boek 50% korting #1 a/b?x=1")
        XCTAssertTrue(link("google", in: special)?.hasSuffix("q=C%2B%2B%20boek%2050%25%20korting%20%231%20a%2Fb%3Fx%3D1") ?? false)
    }

    func testSearchLinksEncodeDiacriticsAsUTF8() {
        let links = PurchaseSearch.links(for: "café crème")
        XCTAssertTrue(link("google", in: links)?.hasSuffix("q=caf%C3%A9%20cr%C3%A8me") ?? false)
        // Dezelfde letters met losse accenten (e + accent) geven hetzelfde adres.
        let decomposed = PurchaseSearch.links(for: "cafe\u{301} cre\u{300}me")
        XCTAssertEqual(link("google", in: decomposed), link("google", in: links))
        let emoji = PurchaseSearch.links(for: "🎧 koptelefoon")
        XCTAssertTrue(link("google", in: emoji)?.hasSuffix("q=%F0%9F%8E%A7%20koptelefoon") ?? false)
        let umlaut = PurchaseSearch.links(for: "Müller")
        XCTAssertTrue(link("beslist", in: umlaut)?.contains("M%C3%BCller") ?? false)
    }

    func testSearchLinksCleanWhitespaceAndLength() {
        XCTAssertEqual(PurchaseSearch.cleanedQuery("  koptelefoon \n  sony\t "), "koptelefoon sony")
        XCTAssertTrue(PurchaseSearch.links(for: "").isEmpty)
        XCTAssertTrue(PurchaseSearch.links(for: "   \n ").isEmpty)
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(PurchaseSearch.cleanedQuery(long).count, PurchaseSearch.maxQueryLength)
        XCTAssertEqual(PurchaseSearch.links(for: long).count, 3)
    }

    func testSearchLinkQueryDecodesBackToTheName() {
        let name = "Dyson V15 & accessoires (zwart)"
        let links = PurchaseSearch.links(for: name)
        for l in links where l.id != "beslist" {
            let text = l.url.absoluteString
            let tail = text.components(separatedBy: "q=").last ?? text
            XCTAssertEqual(tail.removingPercentEncoding, name, l.id)
        }
        XCTAssertEqual(PurchaseSearch.encode("a b"), "a%20b")
        XCTAssertEqual(PurchaseSearch.encode("a-b_c.d~e"), "a-b_c.d~e")
        XCTAssertEqual(PurchaseSearch.encode(""), "")
    }

    func testSearchLinksHostsAreTheExpectedSites() {
        let tech = PurchaseSearch.links(for: "monitor", category: .electronics)
        XCTAssertEqual(tech.map { $0.url.host ?? "" }, ["www.beslist.nl", "www.google.com", "tweakers.net"])
        let rest = PurchaseSearch.links(for: "monitor")
        XCTAssertEqual(rest.map { $0.url.host ?? "" }, ["www.beslist.nl", "www.google.com", "www.kieskeurig.nl"])
    }
}
