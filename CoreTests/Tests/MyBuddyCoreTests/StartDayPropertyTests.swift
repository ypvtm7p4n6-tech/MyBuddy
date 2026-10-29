import XCTest
import Foundation
@testable import MyBuddyCore

/// Eigenschapstest voor de startdatum (docs/work/plan.md par. 2.4): voor willekeurige (maar herhaalbare) datasets met een startdatum,
/// ook midden in een maand en met boekingen en saldi van vóór die dag, sluiten de dagboekhouding, het maandoverzicht, de spaarpotten
/// en de bankrekening op elke dag, en klopt de startmaand met een onafhankelijk orakel: de gebeurtenissen van dezelfde gegevens
/// met startdag 1, min wat vóór de startdag valt. De datasets komen uit `ledgerScenario`, waarvan de vijfde reeks (zaadwaarde
/// + 29.000) de startdatum zet. Een fout noemt de zaadwaarde, de startdatum en de maand.
final class StartDayPropertyTests: XCTestCase {
    private struct Coverage {
        var scenarios = 0
        var withStartDay = 0
        var partialMonths = 0
        var hiddenEntries = 0
        var withPercent = 0
        var withOverride = 0
        var scheduleStarts = 0
        var days = 0
        var features: [String: Int] = [:]
    }

    /// Verzamelt mislukte vergelijkingen zonder per vergelijking de XCTest-machinerie aan te roepen (dat is in een debug-build zo traag
    /// dat de test er minuten over zou doen) en meldt ze aan het eind.
    private final class Failures {
        private(set) var list: [String] = []
        var count = 0

        func eq<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String) {
            count += 1
            if a != b { list.append("\(message()): \(a) is niet gelijk aan \(b)") }
        }

        func ok(_ condition: Bool, _ message: @autoclosure () -> String) {
            count += 1
            if !condition { list.append(message()) }
        }

        func report() {
            if !list.isEmpty {
                XCTFail("\(list.count) van \(count) vergelijkingen mislukt, de eerste:\n" + list.prefix(15).joined(separator: "\n"))
            }
        }
    }

    private func cents(_ value: Double) -> Int { CentsMath.int(value) }

    func testRandomScenariosWithAStartDay() {
        var coverage = Coverage()
        // Voor een grotere speurtocht: START_DAY_SEEDS=1500 swift test --filter StartDayPropertyTests.
        let seeds = max(300, Int(ProcessInfo.processInfo.environment["START_DAY_SEEDS"] ?? "") ?? 300)
        for seed in 1...seeds {
            let scenario = ledgerScenario(seed: UInt64(seed))
            coverage.scenarios += 1
            for feature in scenario.features { coverage.features[feature, default: 0] += 1 }
            verify(scenario, coverage: &coverage)
        }
        XCTAssertGreaterThan(coverage.withStartDay, 80, "datasets met een startdatum")
        XCTAssertGreaterThan(coverage.partialMonths, 50, "datasets met een gedeeltelijke startmaand")
        XCTAssertGreaterThan(coverage.hiddenEntries, 30, "datasets met boekingen of saldi van vóór de start")
        XCTAssertGreaterThan(coverage.withPercent, 8, "datasets met een inleg als percentage")
        XCTAssertGreaterThan(coverage.withOverride, 8, "datasets met een eigen salaris of eigen uren in de startmaand")
        XCTAssertGreaterThan(coverage.scheduleStarts, 8, "datasets met een salaris om de zoveel weken of dagen")
        XCTAssertGreaterThan(coverage.days, 5_000)
        for feature in ["startdatum midden in de maand", "startdatum op de eerste", "boekingen vóór de start"] {
            XCTAssertGreaterThan(coverage.features[feature] ?? 0, 20, "datasets met: \(feature)")
        }
    }

    // MARK: Controle van één dataset

    private func verify(_ scenario: LedgerScenario, coverage: inout Coverage) {
        let f = Failures()
        defer { f.report() }
        let d = scenario.data
        guard let start = d.effectiveStartDay else {
            // Zonder startdatum rekent alles zoals altijd: alleen controleren dat het dagboek sluit.
            for m in scenario.months {
                let ledger = d.monthLedger(m, asOf: scenario.today)
                f.ok(ledger.allReconciles, "zaadwaarde \(scenario.seed) \(m.key): sluit niet zonder startdatum")
            }
            return
        }
        coverage.withStartDay += 1
        let cal = YearMonth.calendar
        let month = start.yearMonth
        let tag = "zaadwaarde \(scenario.seed) start \(start.key)"
        let cutoff = cal.startOfDay(for: start.date())
        var d1 = d
        d1.setStart(CalendarDay(month: month, day: 1))
        let plan = d.plan(for: month)
        let hasPercent = d.pots.contains { $0.contributionMode == .percentage } || d.holdings.contains { $0.contributionMode == .percentage }
            || !plan.percentAllocations.isEmpty
        let hasOverride = plan.salaryOverride != nil || plan.hoursOverride != nil
        if hasPercent { coverage.withPercent += 1 }
        if hasOverride { coverage.withOverride += 1 }
        if !d.salary.isMonthly { coverage.scheduleStarts += 1 }
        let hidden = d.entriesBefore(start)
        if hidden.bank + hidden.pots + hidden.balances > 0 { coverage.hiddenEntries += 1 }
        f.eq(d.bankEntries.count, d.countedBankEntries.count + hidden.bank, "\(tag): bankboekingen tellen op")
        f.eq(d.potEntries.count, d.countedPotEntries.count + hidden.pots, "\(tag): potboekingen tellen op")
        f.eq(d.bankSnapshots.count, d.countedBankSnapshots.count + hidden.balances, "\(tag): saldi tellen op")
        f.ok(d.countedBankEntries.allSatisfy { $0.date >= cutoff }, "\(tag): een bankboeking van voor de start telt")
        f.ok(d.countedPotEntries.allSatisfy { $0.date >= cutoff }, "\(tag): een potboeking van voor de start telt")
        f.ok(d.countedBankSnapshots.allSatisfy { $0.date >= cutoff }, "\(tag): een saldo van voor de start telt")

        for m in scenario.months {
            let ledger = d.monthLedger(m, asOf: scenario.today)
            coverage.days += m.dayCount
            let what = "\(tag), \(m.key)"
            f.ok(ledger.bankReconciles, "\(what): bank sluit niet")
            f.ok(ledger.potsReconciles, "\(what): potten sluiten niet")
            f.ok(ledger.overviewReconciles, "\(what): overzicht sluit niet")
            f.ok(ledger.allReconciles, what)
            // Geen gebeurtenis van vóór de startdag.
            for day in ledger.days {
                for event in day.events where event.date < cutoff {
                    f.ok(false, "\(what): gebeurtenis \(event.title) op \(event.date) voor de start")
                }
            }
            if m < month {
                f.eq(d.monthFigures(m), MonthFigures(), "\(what): cijfers voor de startmaand")
                f.eq(ledger.days.compactMap { $0.bankBalance }.count, 0, "\(what): banksaldo voor de startmaand")
                f.eq(cents(ledger.closingPots), 0, "\(what): potten voor de startmaand")
            }
            if m > month {
                f.eq(d.monthFigures(m), d1.monthFigures(m), "\(what): maand na de start wijkt af van startdag 1")
                f.eq(d.expenseOverview(in: m), d1.expenseOverview(in: m), "\(what): uitgaven na de start wijken af van startdag 1")
            }
            // De maandcijfers komen overeen met het dagboek, ook in de startmaand.
            let figures = d.monthFigures(m)
            f.eq(figures.income, cents(ledger.income), "\(what): inkomen tegenover het dagboek")
            f.eq(figures.expenses, cents(ledger.expensesTotal), "\(what): uitgaven tegenover het dagboek")
            f.eq(figures.saved, cents(ledger.planToPots), "\(what): gespaard tegenover het dagboek")
            f.eq(figures.invested, cents(ledger.toHoldings), "\(what): belegd tegenover het dagboek")
            let overview = d.expenseOverview(in: m)
            f.eq(overview.leftAfterTransfers, ledger.remaining, "\(what): nog te verdelen tegenover het dagboek")
            f.eq(d.income(in: m), ledger.income, "\(what): income(in:)")
            f.eq(cents(d.salaryAmount(in: m)) + cents(d.extraIncomeTotal(in: m)), cents(ledger.income),
                 "\(what): salaris en extra inkomsten")
        }

        // De startmaand tegenover het orakel van startdag 1.
        if start.day > 1 {
            coverage.partialMonths += 1
            f.eq(d.monthFigures(month), expectedFigures(d1: d1, d: d, month: month, startDay: start.day),
                 "\(tag): de cijfers van de startmaand")
            let expectedSalary = expectedSalaryCents(d1: d1, d: d, month: month, startDay: start.day)
            f.eq(d.salaryCents(in: month, plan: plan), expectedSalary, "\(tag): salaris van de startmaand")
        } else {
            f.eq(d.monthFigures(month), d1.monthFigures(month), "\(tag): startdag 1 is een hele maand")
        }

        // Vóór de startdag: geen banksaldo en niets in de potten; erna het pad van de dagen en de losse vragen gelijk.
        let probe = cal.date(byAdding: .hour, value: -12, to: cutoff) ?? cutoff
        f.ok(d.bankBalance(on: probe) == nil, "\(tag): banksaldo voor de start")
        f.ok(d.bankBalance(atMoment: probe) == nil, "\(tag): banksaldo op een moment voor de start")
        for pot in d.pots {
            f.eq(d.potBalance(pot.id, asOf: probe), 0, "\(tag): potsaldo voor de start (\(pot.name))")
            f.eq(d.potBalance(pot.id, atMoment: probe), 0, "\(tag): potsaldo op een moment voor de start (\(pot.name))")
        }
        let ledger = d.monthLedger(month, asOf: scenario.today)
        for day in ledger.days where day.date >= cutoff {
            if let b = d.bankBalance(on: day.date), let c = day.bankBalance, b != c {
                f.ok(false, "\(tag) \(day.date): bankBalance \(b) != dag \(c)")
            }
            f.eq(cents(d.totalSaved(asOf: day.date)), cents(day.potsTotal), "\(tag) \(day.date): potten tegenover het dagboek")
        }

        // Een eerdere startdatum brengt de boekingen terug; dezelfde startdatum nogmaals zetten verandert niets.
        var again = d
        again.setStart(start)
        f.ok(again == d, "\(tag): setStart is idempotent")
        var earlier = d
        earlier.setStart(CalendarDay(year: start.year - 1, month: start.month, day: 1))
        f.eq(earlier.countedBankEntries.count, earlier.bankEntries.count, "\(tag): een eerdere start brengt de bankboekingen terug")
        f.eq(earlier.countedPotEntries.count, earlier.potEntries.count, "\(tag): een eerdere start brengt de potboekingen terug")
        f.eq(earlier.countedBankSnapshots.count, earlier.bankSnapshots.count, "\(tag): een eerdere start brengt de saldi terug")
    }

    // MARK: Het orakel van de startmaand

    private func sum(_ events: [DayEvent], kinds: Set<DayEventKind>, fromDay: Int, _ value: (DayEvent) -> Double) -> Int {
        CentsMath.sum(events.filter { kinds.contains($0.kind) && $0.day >= fromDay }.map { cents(value($0)) })
    }

    /// Het salaris dat in de startmaand telt: zonder eigen salaris of eigen uren de uitbetalingen op of na de startdag (uit de
    /// gebeurtenissen van startdag 1); met een eigen salaris of eigen uren het totaal van de maand, gelijk verdeeld over de
    /// uitbetalingen vanaf de startdag (de terugvaldag van het schema als die er niet zijn, en alleen als die telt).
    private func expectedSalaryCents(d1: FinanceData, d: FinanceData, month: YearMonth, startDay: Int) -> Int {
        let plan = d.plan(for: month)
        let events = d1.planEvents(in: month)
        let counted = sum(events, kinds: [.salary], fromDay: startDay) { $0.bankAmount }
        let schemaDays = d.salaryPayDays(in: month).filter { $0 >= startDay }
        var total: Int?
        if let override = plan.salaryOverride {
            total = cents(override)
        } else if d.salary.mode == .hourly, let hours = plan.hoursOverride {
            total = cents(SalarySettings.exactHourlyPay(rate: d.salary.hourlyRate, hours: hours))
        }
        guard let total else { return counted }
        if d.salary.isMonthly {
            return min(d.salaryDay(), month.dayCount) >= startDay ? total : 0
        }
        if !schemaDays.isEmpty { return total }
        // Geen uitbetaling vanaf de startdag: een eigen salaris komt op de terugvaldag binnen, eigen uren betalen niets.
        guard plan.salaryOverride != nil, total != 0 else { return 0 }
        return min(d.salaryDay(), month.dayCount) >= startDay ? total : 0
    }

    /// De cijfers van de startmaand volgens de gebeurtenissen van startdag 1: alles op of na de startdag, met het salaris en een
    /// inleg als percentage opnieuw berekend over het inkomen dat meetelt.
    private func expectedFigures(d1: FinanceData, d: FinanceData, month: YearMonth, startDay: Int) -> MonthFigures {
        let events = d1.planEvents(in: month)
        var f = MonthFigures()
        let salary = expectedSalaryCents(d1: d1, d: d, month: month, startDay: startDay)
        let extra = sum(events, kinds: [.income], fromDay: startDay) { $0.bankAmount }
        f.income = CentsMath.add(salary, extra)
        f.expenses = sum(events, kinds: [.expense], fromDay: startDay) { -($0.bankAmount + $0.potAmount) }
        f.fromPots = sum(events, kinds: [.expense], fromDay: startDay) { -$0.potAmount }
        let bases = IncomeBases(salary: salary, all: f.income)
        func contribution(_ id: UUID, transferDay: Int) -> Int {
            guard transferDay >= startDay else { return 0 }
            switch d1.allocationRule(id, in: month) {
            case .amount(let value): return CentsMath.int(value)
            case .percent(let rule): return AllocationMath.cents(of: rule, bases: bases)
            }
        }
        for pot in d.pots {
            f.saved = CentsMath.add(f.saved, contribution(pot.id, transferDay: d1.transferDay(for: pot.id, in: month)))
        }
        for holding in d.holdings {
            f.invested = CentsMath.add(f.invested, contribution(holding.id, transferDay: d1.transferDay(for: holding.id, in: month)))
        }
        return f
    }
}
