import XCTest
import Foundation
@testable import MyBuddyCore

/// De bevindingen van de drie onafhankelijke controleurs, voor zover ze de rekenmotor raken:
/// een vast bedrag staat overal op hele centen, een nieuwe standaardinleg bereikt ook maanden na de lopende maand die al zijn
/// vastgelegd, en een wijziging van de salarisinstellingen laat het verleden met rust (`freezeSalaryHistory`).
/// De verwachte waarden zijn met de hand uitgerekend. Niets hangt van de klok af.
final class ReviewFixesTests: XCTestCase {
    private let jul2026 = YearMonth(year: 2026, month: 7)

    // MARK: Een vast bedrag op hele centen

    func testFixedAmountWithMoreThanTwoDecimalsIsWholeCentsEverywhere() {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        // Direct ingesteld, zoals een import of een oud bestand dat kan hebben: 100,496 is op hele centen 100,50.
        let pot = Pot(name: "Vakantie", monthlyContribution: 100.496, startMonth: engNov2026)
        d.addPot(pot, openingBalance: 0, now: engTime(engNov2026, 1, hour: 8))
        let today = engTime(engNov2026, 30, hour: 20)

        XCTAssertEqual(d.allocation(pot.id, in: engNov2026), 100.5)
        XCTAssertEqual(d.allocation(pot.id, in: engNov2026, cache: d.incomeBasesCache()), 100.5)
        XCTAssertEqual(d.effectiveAllocation(pot.id, in: engNov2026).amount, 100.5)
        XCTAssertEqual(d.amount(of: .amount(100.496), in: engNov2026), 100.5)
        XCTAssertEqual(d.defaultAllocation(pot.id, in: engNov2026), 100.5)
        XCTAssertEqual(d.savedTotal(in: engNov2026), 100.5)
        XCTAssertEqual(d.allocationCents(pot.id, in: engNov2026), 10_050)
        XCTAssertEqual(d.monthLedger(engNov2026, asOf: today).planToPots, 100.5)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: engNov2026, today: today), 100.5)
        // Ook bij een gemiddelde maand (salaris om de 4 weken) hetzelfde bedrag.
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 11, day: 6))
        XCTAssertEqual(d.estimatedAllocation(pot.id, in: engNov2026), 100.5)
        XCTAssertEqual(d.estimatedAmount(of: .amount(100.496), in: engNov2026), 100.5)
    }

    // MARK: Een nieuwe standaard bereikt ook vastgelegde maanden na de lopende maand

    /// Start november 2026, salaris 3000 op de 25e. Pot Vakantie legt 100 in. November is vastgelegd. December krijgt een eigen
    /// salaris van 3500, februari een eenmalige uitgave (beide bewerkingen leggen de inleg van dat moment vast), maart een
    /// eigen bedrag voor de pot (250) en januari blijft onaangeroerd.
    private func futureData() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: engNov2026)
        d.addPot(pot, openingBalance: 0, now: engTime(engNov2026, 1, hour: 8))
        d.materialize(upTo: engNov2026)
        d.editPlan(engDec2026) { $0.salaryOverride = 3_500 }
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 80, day: 5), kind: .expense, in: engFeb2027)
        d.setAllocation(pot.id, in: engMar2027, amount: 250)
        return (d, pot)
    }

    func testStoredFutureMonthsFollowANewPercentageStandard() {
        var (d, pot) = futureData()
        // Voor de wijziging: elke maand 100, ook in de vastgelegde maanden.
        for month in [engNov2026, engDec2026, engJan2027, engFeb2027] {
            XCTAssertEqual(d.allocation(pot.id, in: month), 100, month.key)
        }
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        pot.contributionBasis = .salary
        d.updatePot(pot, current: engNov2026)

        XCTAssertEqual(d.allocation(pot.id, in: engNov2026), 300)
        XCTAssertEqual(d.allocation(pot.id, in: engDec2026), 350, "december heeft een eigen salaris van 3500")
        XCTAssertEqual(d.allocation(pot.id, in: engJan2027), 300)
        XCTAssertEqual(d.allocation(pot.id, in: engFeb2027), 300, "februari was vastgelegd met de oude 100")
        XCTAssertEqual(d.allocation(pot.id, in: engMar2027), 250, "een eigen bedrag van de gebruiker blijft")
        // Alleen maart is een afwijking; de rest volgt de standaard.
        for month in [engNov2026, engDec2026, engJan2027, engFeb2027] {
            XCTAssertFalse(d.effectiveAllocation(pot.id, in: month).isOverride, month.key)
        }
        XCTAssertTrue(d.effectiveAllocation(pot.id, in: engMar2027).isOverride)
        // Alles sluit nog.
        let today = engTime(engNov2026, 30, hour: 20)
        for month in [engNov2026, engDec2026, engJan2027, engFeb2027, engMar2027] {
            XCTAssertTrue(d.monthLedger(month, asOf: today).allReconciles, month.key)
            XCTAssertEqual(d.savedTotal(in: month), d.allocation(pot.id, in: month), month.key)
        }
    }

    func testStoredFutureMonthsFollowANewFixedAmountToo() {
        var (d, pot) = futureData()
        pot.monthlyContribution = 160
        d.updatePot(pot, current: engNov2026)
        for month in [engNov2026, engDec2026, engJan2027, engFeb2027] {
            XCTAssertEqual(d.allocation(pot.id, in: month), 160, month.key)
        }
        XCTAssertEqual(d.allocation(pot.id, in: engMar2027), 250)
        // Het verleden (maanden voor de lopende maand) wordt niet aangeraakt: een bedrag van een vorige maand blijft staan.
        var past = FinanceData(startMonth: engNov2026)
        past.salary = d.salary
        let pastPot = Pot(name: "Oud", monthlyContribution: 100, startMonth: engNov2026)
        past.addPot(pastPot, openingBalance: 0, now: engTime(engNov2026, 1, hour: 8))
        past.materialize(upTo: engDec2026)
        var changed = pastPot
        changed.monthlyContribution = 40
        past.updatePot(changed, current: engDec2026)
        XCTAssertEqual(past.allocation(pastPot.id, in: engNov2026), 100, "een vorige maand blijft zoals ze was")
        XCTAssertEqual(past.allocation(pastPot.id, in: engDec2026), 40)
        XCTAssertEqual(past.allocation(pastPot.id, in: engJan2027), 40)
    }

    func testAChangeThatKeepsTheStandardLeavesStoredMonthsAlone() {
        var (d, pot) = futureData()
        let before = d
        pot.name = "Zomervakantie"
        d.updatePot(pot, current: engNov2026)
        XCTAssertEqual(d.months, before.months)
    }

    // MARK: Een wijziging van de salarisinstellingen laat het verleden met rust

    /// Vanaf juli 2026 een vast salaris van 2100 op de 25e, een pot met 10% van het salaris en een belegging met 5%; een
    /// ingevuld banksaldo in juli. "Nu" is 15 oktober 2026 (de maanden juli, augustus en september liggen achter ons).
    private func historyData() -> (data: FinanceData, pot: Pot, holding: Holding, today: Date) {
        var d = FinanceData(startMonth: jul2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_100, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: jul2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.addPot(pot, openingBalance: 500, now: engTime(jul2026, 1, hour: 8))
        var holding = Holding(name: "ETF", kind: .etf, monthlyContribution: 0, startMonth: jul2026)
        holding.contributionMode = .percentage
        holding.contributionPercent = 5
        d.holdings.append(holding)
        d.addBankSnapshot(balance: 1_000, note: "", date: engTime(jul2026, 1, hour: 8))
        d.materialize(upTo: oct2026)
        return (d, pot, holding, engTime(oct2026, 15, hour: 10))
    }

    /// Wat de maanden van het verleden laten zien, op de cent.
    private func pastFigures(_ d: FinanceData, pot: Pot, today: Date) -> [String] {
        [jul2026, aug2026, sep2026].map { month in
            let ledger = d.monthLedger(month, asOf: today)
            return [month.key, "\(engCents(d.income(in: month)))", "\(engCents(d.savedTotal(in: month)))",
                    "\(engCents(d.investedTotal(in: month)))", "\(engCents(d.remaining(in: month)))",
                    "\(engCents(d.potBalance(pot.id, at: month)))", "\(d.bankBalance(at: month).map(engCents) ?? -1)",
                    "\(ledger.allReconciles)"].joined(separator: "|")
        }
    }

    func testFreezingKeepsThePastWhenTheScheduleChanges() {
        let (start, pot, _, today) = historyData()
        let reference = pastFigures(start, pot: pot, today: today)
        XCTAssertEqual(start.income(in: aug2026), 2_100)

        var frozen = start
        frozen.freezeSalaryHistory(before: oct2026)
        frozen.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 25))
        XCTAssertEqual(pastFigures(frozen, pot: pot, today: today), reference, "het verleden is niet veranderd")
        // De maanden vanaf de lopende maand volgen het nieuwe schema: om de 2 weken vanaf 25 oktober is 11 en 25 oktober, en in
        // november 8 en 22 november.
        XCTAssertEqual(frozen.salaryPayDays(in: oct2026), [11, 25])
        XCTAssertEqual(frozen.income(in: oct2026), 4_200)
        XCTAssertEqual(frozen.income(in: engNov2026), 4_200)
        XCTAssertEqual(frozen.savedTotal(in: engNov2026), 420)
        XCTAssertEqual(frozen.investedTotal(in: engNov2026), 210)
        XCTAssertTrue(frozen.monthLedger(engNov2026, asOf: today).allReconciles)

        // Zonder vastleggen zouden juli, augustus en september wel meeveranderen (dit is wat de controleur aantoonde).
        var control = start
        control.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 25))
        XCTAssertNotEqual(pastFigures(control, pot: pot, today: today), reference)
        XCTAssertEqual(control.income(in: aug2026), 6_300)
    }

    func testFreezingKeepsThePastWhenTheAmountOrTheHoursChange() {
        var (d, pot, _, today) = historyData()
        let reference = pastFigures(d, pot: pot, today: today)
        d.freezeSalaryHistory(before: oct2026)
        d.salary.fixedMonthly = 2_400
        XCTAssertEqual(pastFigures(d, pot: pot, today: today), reference)
        XCTAssertEqual(d.income(in: oct2026), 2_400)
        XCTAssertEqual(d.income(in: engNov2026), 2_400)

        // Uurloon: andere uren per week.
        var h = FinanceData(startMonth: jul2026)
        h.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 32, payDay: 25)
        h.materialize(upTo: oct2026)
        let augBefore = h.income(in: aug2026)
        XCTAssertEqual(augBefore, 2_773.33)   // 20 x 32 x 52 / 12 = 2773,33
        h.freezeSalaryHistory(before: oct2026)
        h.salary.hoursPerWeek = 36
        XCTAssertEqual(h.income(in: aug2026), augBefore)
        XCTAssertEqual(h.income(in: oct2026), 3_120)   // 20 x 36 x 52 / 12
    }

    func testFreezingTwiceChangesNothingAndAnOwnSalaryOfAMonthStays() {
        var (d, _, _, _) = historyData()
        d.editPlan(aug2026) { $0.salaryOverride = 2_500 }
        d.freezeSalaryHistory(before: oct2026)
        XCTAssertEqual(d.salaryAmount(in: aug2026, plan: d.plan(for: aug2026)), 2_500, "een eigen salaris blijft")
        XCTAssertEqual(d.salaryAmount(in: jul2026, plan: d.plan(for: jul2026)), 2_100)
        XCTAssertEqual(d.plan(for: oct2026).salaryOverride, nil, "de lopende maand wordt niet vastgelegd")
        let once = d
        d.freezeSalaryHistory(before: oct2026)
        XCTAssertEqual(d, once)
    }

    func testFreezingDoesNothingWhenThereIsNoSalaryYet() {
        // Wie nu pas zijn salaris invult, krijgt het ook in de maanden sinds de start (zoals altijd).
        var d = FinanceData(startMonth: jul2026)
        d.materialize(upTo: oct2026)
        let before = d
        d.freezeSalaryHistory(before: oct2026)
        XCTAssertEqual(d, before)
        d.salary.fixedMonthly = 1_800
        XCTAssertEqual(d.income(in: aug2026), 1_800)
        // En zonder maanden voor de lopende maand valt er niets vast te leggen.
        var fresh = FinanceData(startMonth: oct2026)
        fresh.salary.fixedMonthly = 2_000
        let freshBefore = fresh
        fresh.freezeSalaryHistory(before: oct2026)
        XCTAssertEqual(fresh, freshBefore)
    }

    func testFrozenHistorySurvivesBackupAndLenientDecoding() throws {
        var (d, pot, _, today) = historyData()
        let reference = pastFigures(d, pot: pot, today: today)
        d.freezeSalaryHistory(before: oct2026)
        d.salary.setSchedule(.days, interval: 14, anchor: CalendarDay(year: 2026, month: 10, day: 23))
        let encoder = FinanceStorage.makeEncoder()
        let data = try encoder.encode(d)
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: data)
        // Hetzelfde na de rondreis (tijdstippen staan in de JSON op de seconde, dus vergelijk de opgeslagen tekst).
        XCTAssertEqual(try encoder.encode(back), data)
        XCTAssertEqual(pastFigures(back, pot: pot, today: today), reference)
    }

    // MARK: De ankerdatum als eerste uitbetaling

    func testAnchorAsFirstPayoutStartsTheScheduleThere() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_100, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        // Om de 4 weken met een uitbetaling op vrijdag 30 oktober 2026: ook terug zijn dat 2 oktober en 4 september.
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 30))
        XCTAssertEqual(d.salaryPayDays(in: oct2026), [2, 30])
        XCTAssertEqual(d.income(in: oct2026), 4_200)

        d.salary.anchorIsFirst = true
        XCTAssertEqual(d.salaryPayDays(in: oct2026), [30], "er valt niets voor de eerste uitbetaling")
        XCTAssertEqual(d.income(in: oct2026), 2_100)
        XCTAssertEqual(d.salaryPayDays(in: engNov2026), [27])
        XCTAssertEqual(d.salaryPayDays(in: engDec2026), [25])
        XCTAssertEqual(d.salaryPayDays(in: engJan2027), [22])
        // Alles sluit: de dagen, het overzicht en de salarisgebeurtenissen.
        let today = engTime(oct2026, 15, hour: 10)
        let ledger = d.monthLedger(oct2026, asOf: today)
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertEqual(ledger.planInflow, 2_100)
        XCTAssertEqual(ledger.days.flatMap { $0.events }.filter { $0.kind == .salary }.map { $0.day }, [30])
        // De eerstvolgende uitbetaling vanaf vandaag is het anker zelf; een anker ver in de toekomst blijft de eerste.
        XCTAssertEqual(d.nextPayDate(after: today).map { CalendarDay(date: $0) }, CalendarDay(year: 2026, month: 10, day: 30))
        d.salary.anchor = CalendarDay(year: 2026, month: 12, day: 4)
        XCTAssertEqual(d.nextPayDate(after: today).map { CalendarDay(date: $0) }, CalendarDay(year: 2026, month: 12, day: 4))
        XCTAssertEqual(d.salaryPayDays(in: engNov2026), [])
        d.salary.anchorIsFirst = false
        XCTAssertEqual(d.nextPayDate(after: today).map { CalendarDay(date: $0) }, CalendarDay(year: 2026, month: 11, day: 6))
    }

    func testAnchorAsFirstPayoutSurvivesStorageAndOldFilesStayTheSame() throws {
        var salary = SalarySettings(mode: .fixed, fixedMonthly: 1_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        salary.setSchedule(.days, interval: 14, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        let encoder = FinanceStorage.makeEncoder()
        let plain = String(decoding: try encoder.encode(salary), as: UTF8.self)
        XCTAssertFalse(plain.contains("anchorIsFirst"), "uit is de standaard en komt niet in het bestand")

        salary.anchorIsFirst = true
        let data = try encoder.encode(salary)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("anchorIsFirst"))
        XCTAssertEqual(try FinanceStorage.makeDecoder().decode(SalarySettings.self, from: data), salary)

        // Een bestand zonder het veld, of met onzin erin, laadt als "uit".
        let old = Data(#"{"mode":"fixed","fixedMonthly":1000,"hourlyRate":0,"hoursPerWeek":0,"payDay":25}"#.utf8)
        XCTAssertEqual(try FinanceStorage.makeDecoder().decode(SalarySettings.self, from: old).anchorIsFirst, false)
        let junk = Data(#"{"mode":"fixed","fixedMonthly":1000,"anchorIsFirst":"misschien","anchor":"2026-10-02","schedule":"weeks","interval":2}"#.utf8)
        let loaded = try FinanceStorage.makeDecoder().decode(SalarySettings.self, from: junk)
        XCTAssertEqual(loaded.anchorIsFirst, false)
        XCTAssertEqual(loaded.schedule, .weeks)
    }

    // MARK: "Deze maand" of "een gemiddelde maand"

    func testPurchaseTextsSayAverageMonthForASalaryEveryFewWeeks() {
        var context = PurchaseContext()
        context.remainingThisMonth = 500
        let monthly = PurchaseCalc.affordability(totalCost: 200, context: context)
        XCTAssertTrue(monthly.details.contains { $0.text.hasPrefix("Je hebt deze maand nog") }, "\(monthly.details)")
        XCTAssertTrue(monthly.summary.contains("deze maand"))

        context.isAverageMonth = true
        let average = PurchaseCalc.affordability(totalCost: 200, context: context)
        XCTAssertTrue(average.details.contains { $0.text.hasPrefix("In een gemiddelde maand heb je nog") }, "\(average.details)")
        XCTAssertTrue(average.summary.contains("gemiddelde maand"))
        XCTAssertFalse(average.details.contains { $0.text.contains("deze maand") })
        for remaining in [-50.0, 0, 100] {
            context.remainingThisMonth = remaining
            let texts = PurchaseCalc.affordability(totalCost: 200, context: context).details.map { $0.text }
            XCTAssertTrue(texts.contains { $0.contains("gemiddelde maand") }, "\(remaining): \(texts)")
            XCTAssertFalse(texts.contains { $0.contains("deze maand") }, "\(remaining): \(texts)")
        }

        // De context uit de app weet het ook.
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        XCTAssertFalse(PurchaseContext.make(from: d, current: oct2026).isAverageMonth)
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 9))
        XCTAssertTrue(PurchaseContext.make(from: d, current: oct2026).isAverageMonth)
    }

    // MARK: Afronding van de getoonde bedragen

    func testRoundingNoteOnlyWhenTheShownFiguresDoNotAddUp() {
        // 5120,40 - 1370,50 - 1268,90 = 2481,00. Getoond: 5.120 - 1.371 - 1.269 = 2.480, maar "nog te verdelen" toont 2.481.
        let off = MonthBoard(month: oct2026, figures: MonthFigures(income: 512_040, expenses: 137_050, fromPots: 0,
                                                                  saved: 100_000, invested: 26_890))
        XCTAssertEqual(CentsMath.int(off.remaining), 248_100)
        XCTAssertTrue(off.closes, "in centen klopt het altijd")
        XCTAssertTrue(off.roundingHidesSum)
        XCTAssertEqual(DisplayRounding.shown(137_050), 1_371)
        XCTAssertEqual(DisplayRounding.shown(-137_050), -1_371)
        // Hele bedragen: de getoonde cijfers tellen precies op, dus geen uitleg.
        let exact = MonthBoard(month: oct2026, figures: MonthFigures(income: 300_000, expenses: 100_000, fromPots: 0,
                                                                    saved: 40_000, invested: 10_000))
        XCTAssertFalse(exact.roundingHidesSum)
        // Uitgaven uit een spaarpot tellen niet mee in wat van de bank gaat.
        let pots = MonthBoard(month: oct2026, figures: MonthFigures(income: 300_000, expenses: 120_000, fromPots: 20_000,
                                                                   saved: 40_000, invested: 10_000))
        XCTAssertFalse(pots.roundingHidesSum)
        XCTAssertTrue(DisplayRounding.note.contains("afgerond"))
    }

    /// Over echte data: een maand met een percentage-inleg heeft vaak bedragen met centen. Het oordeel hangt alleen van
    /// de getoonde bedragen af en is dus nooit "waar" als alles op hele euro's klopt.
    func testRoundingNoteAgreesWithTheShownFiguresOverManyMonths() {
        var flagged = 0
        var checked = 0
        for seed in 1...200 {
            let sc = ledgerScenario(seed: UInt64(seed))
            for month in sc.months {
                let board = MonthBoard(sc.data, month: month)
                let f = board.figures
                let shownSum = DisplayRounding.shown(f.income) - DisplayRounding.shown(f.expenses - f.fromPots)
                    - DisplayRounding.shown(CentsMath.add(f.saved, f.invested))
                XCTAssertEqual(board.roundingHidesSum, shownSum != DisplayRounding.shown(f.remaining), "seed \(seed) \(month.key)")
                checked += 1
                if board.roundingHidesSum { flagged += 1 }
            }
        }
        XCTAssertGreaterThan(checked, 500)
        XCTAssertGreaterThan(flagged, 0, "de reeks bevat maanden waar de afronding het verschil maakt")
    }
}
