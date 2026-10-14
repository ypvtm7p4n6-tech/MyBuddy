import XCTest
@testable import MyBuddyCore

/// Eigenschapstest: voor willekeurige (maar herhaalbare) datasets sluiten de dagboekhouding, het maandoverzicht, de
/// spaarpotten en de bankrekening op elke dag van elke maand op precies dezelfde cijfers. Elke dataset heeft een
/// vaste zaadwaarde; een fout noemt die zaadwaarde, de maand en de dag.
final class LedgerConsistencyTests: XCTestCase {
    /// Wat de willekeurige datasets samen hebben bestreken, om te zien dat de test echt iets controleert.
    private struct Coverage {
        var days = 0
        var daysWithBank = 0
        var corrections = 0
        var paidFromPots = 0
        var interest = 0
        var manualTransfers = 0
        var negativeToPots = 0
        var potEntries = 0
        var holdings = 0
        var shortMonths = 0
        var monthsWithSnapshotInside = 0
        var todayChecks = 0
        var daysWithSeveralInflows = 0
        var scenariosWithFeature: [String: Int] = [:]
        var percentMonths = 0
        var percentMonthsWithBothBases = 0
        var scheduleMonths = 0
        var monthsWithSeveralPayouts = 0
        var monthsWithoutPayout = 0
        var overriddenSalaryMonths = 0
    }

    private func cents(_ value: Double) -> Int { CentsMath.int(value) }

    // MARK: De test

    func testRandomDatasetsReconcileOnEveryDay() {
        var coverage = Coverage()
        // Voor een grotere speurtocht naar fouten: LEDGER_SEEDS=1500 swift test --filter LedgerConsistencyTests.
        let seeds = max(200, Int(ProcessInfo.processInfo.environment["LEDGER_SEEDS"] ?? "") ?? 200)
        for seed in 1...seeds {
            let scenario = ledgerScenario(seed: UInt64(seed))
            for feature in scenario.features { coverage.scenariosWithFeature[feature, default: 0] += 1 }
            verify(scenario, exhaustive: seed % 11 == 0, coverage: &coverage)
        }
        // De datasets raken alles waar het om gaat.
        XCTAssertGreaterThan(coverage.days, 15_000)
        XCTAssertGreaterThan(coverage.daysWithBank, 5_000)
        XCTAssertGreaterThan(coverage.corrections, 30, "ingevulde saldi die afwijken van de berekening")
        XCTAssertGreaterThan(coverage.paidFromPots, 100, "dagen met een uitgave deels uit een pot")
        XCTAssertGreaterThan(coverage.interest, 100, "dagen met rente")
        XCTAssertGreaterThan(coverage.manualTransfers, 30, "dagen met een handmatige overboeking")
        XCTAssertGreaterThan(coverage.negativeToPots, 5, "dagen waarop er meer van een pot naar de bank gaat dan andersom")
        XCTAssertGreaterThan(coverage.potEntries, 100, "dagen met een handmatige potboeking")
        XCTAssertGreaterThan(coverage.holdings, 200, "dagen met inleg naar beleggingen")
        XCTAssertGreaterThan(coverage.shortMonths, 300, "maanden van 28, 29 of 30 dagen")
        XCTAssertGreaterThan(coverage.monthsWithSnapshotInside, 100, "maanden met een ingevuld saldo erin")
        XCTAssertGreaterThan(coverage.todayChecks, 150, "controles van de saldi van nu")
        XCTAssertGreaterThan(coverage.daysWithSeveralInflows, 40, "dagen met meer dan één inkomst")
        for feature in ["meer uitbetalingen", "pot van voor de start", "boekingen op de randen van een dag",
                        "saldo op de rand van een dag", "potsaldo gezet", "plan in één keer veranderd", "pot verwijderd",
                        "percentage-inleg", "percentage per maand", "reeks overgeslagen", "reeks gestopt", "reeks bewerkt",
                        "reeks later toegevoegd", "salaris om de zoveel weken of dagen", "salarisoverschrijving"] {
            XCTAssertGreaterThan(coverage.scenariosWithFeature[feature] ?? 0, 8, "datasets met: \(feature)")
        }
        XCTAssertGreaterThan(coverage.scheduleMonths, 600, "maanden met een salaris om de zoveel weken of dagen")
        XCTAssertGreaterThan(coverage.monthsWithSeveralPayouts, 150, "maanden met meer dan één uitbetaling van het salaris")
        XCTAssertGreaterThan(coverage.monthsWithoutPayout, 30, "maanden zonder uitbetaling van het salaris (bij een schema)")
        XCTAssertGreaterThan(coverage.overriddenSalaryMonths, 20, "schemamaanden met een eigen salaris of eigen uren")
        XCTAssertGreaterThan(coverage.percentMonths, 300, "pot- of beleggingsmaanden met een inleg als percentage")
        XCTAssertGreaterThan(coverage.percentMonthsWithBothBases, 20, "maanden met extra inkomsten naast een percentage")
    }

    /// Verzamelt mislukte vergelijkingen zonder per vergelijking de XCTest-machinerie aan te roepen (dat is in een
    /// debug-build zo traag dat de test er minuten over zou doen) en meldt ze aan het eind.
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
                XCTFail("\(list.count) van \(count) vergelijkingen mislukt, de eerste:\n" + list.prefix(12).joined(separator: "\n"))
            }
        }
    }

    // MARK: Controle van één dataset

    private func verify(_ scenario: LedgerScenario, exhaustive: Bool, coverage: inout Coverage) {
        let f = Failures()
        defer { f.report() }
        let d = scenario.data
        let today = scenario.today
        let cal = YearMonth.calendar
        let tag = "zaadwaarde \(scenario.seed)"
        let todayMonth = YearMonth(date: today, calendar: cal)
        let todayStart = cal.startOfDay(for: today)
        var rng = EngRandom(seed: scenario.seed &+ 99)

        var eventCache: [YearMonth: [DayEvent]] = [:]
        func events(_ month: YearMonth) -> [DayEvent] {
            if let cached = eventCache[month] { return cached }
            let list = d.dayEvents(in: month, asOf: today)
            eventCache[month] = list
            return list
        }

        let ledgers = scenario.months.map { d.monthLedger($0, asOf: today) }
        let snapshotDays = Set(d.bankSnapshots.map { cal.startOfDay(for: $0.date) })

        // De dagreeks van de motor over de hele periode in één keer (1 punt per dag, vanaf de eerste bekende dag).
        var seriesByDate: [Date: BankDayPoint] = [:]
        if let first = scenario.months.first, let last = scenario.months.last {
            for point in d.bankDailySeries(from: first.firstDay, to: last.date(day: last.dayCount), asOf: today) {
                seriesByDate[point.date] = point
            }
        }
        var summaries: [MonthSummary] = []
        var previous: MonthLedger?

        for ledger in ledgers {
            let month = ledger.month
            let n = month.dayCount
            let what = "\(tag), \(month.key)"
            coverage.days += n
            if n < 31 { coverage.shortMonths += 1 }

            // De controles van de motor zelf.
            f.eq(ledger.days.count, n, what)
            f.ok(ledger.bankReconciles, "bank sluit niet: \(what)")
            f.ok(ledger.potsReconciles, "potten sluiten niet: \(what)")
            f.ok(ledger.overviewReconciles, "overzicht sluit niet: \(what)")
            f.ok(ledger.allReconciles, what)

            // Maand tegenover maand: het eind van de vorige maand is het begin van deze.
            if let previous {
                f.eq(ledger.openingBank, previous.closingBank, "begin bank = eind vorige maand: \(what)")
                f.eq(cents(ledger.openingPots), cents(previous.closingPots), "begin potten = eind vorige maand: \(what)")
            }

            // Het maandoverzicht (MonthSummary) komt overeen met het dagboek.
            let summary = d.summary(of: month, current: todayMonth)
            summaries.append(summary)
            f.eq(summary.income, ledger.income, what)
            f.eq(summary.expenses, ledger.expensesTotal, what)
            f.eq(summary.fromPots, ledger.paidFromPots, what)
            f.eq(summary.saved, ledger.planToPots, what)
            f.eq(summary.invested, ledger.toHoldings, what)
            f.eq(summary.remaining, ledger.remaining, what)
            f.eq(d.remaining(in: month), ledger.remaining, what)
            f.eq(d.income(in: month), ledger.income, what)
            f.eq(d.expensesTotal(in: month), ledger.expensesTotal, what)
            f.eq(d.expensesFromBank(in: month), ledger.planOutflow, what)
            f.eq(d.expensesFromPots(in: month), ledger.paidFromPots, what)
            f.eq(d.savedTotal(in: month), ledger.planToPots, what)
            f.eq(d.investedTotal(in: month), ledger.toHoldings, what)
            let overview = d.expenseOverview(in: month)
            f.eq(overview.leftAfterTransfers, ledger.remaining, what)
            f.eq(overview.income, ledger.income, what)
            f.eq(overview.expenses, ledger.expensesTotal, what)
            f.eq(overview.expensesFromBank, ledger.planOutflow, what)
            f.eq(overview.fromPots, ledger.paidFromPots, what)
            f.eq(overview.toPots, ledger.planToPots, what)
            f.eq(overview.toInvestments, ledger.toHoldings, what)
            f.eq(cents(ledger.planInflow), cents(ledger.income), "inkomen volgens de dagen: \(what)")

            // De som van de dagen is het totaal.
            func sum(_ value: (DayTotals) -> Double) -> Int { CentsMath.sum(ledger.days.map { cents(value($0)) }) }
            f.eq(sum { $0.inflow }, cents(ledger.inflow), what)
            f.eq(sum { $0.outflow }, cents(ledger.outflow), what)
            f.eq(sum { $0.toPots }, cents(ledger.toPots), what)
            f.eq(sum { $0.toHoldings }, cents(ledger.toHoldings), what)
            f.eq(sum { $0.paidFromPots }, cents(ledger.paidFromPots), what)
            f.eq(sum { $0.interest }, cents(ledger.interest), what)
            f.eq(sum { $0.potEntriesNet }, cents(ledger.potEntriesNet), what)
            f.eq(sum { $0.bankCorrection }, cents(ledger.bankCorrections), what)
            f.eq(cents(ledger.inflow), cents(ledger.planInflow) + cents(ledger.manualInflow), what)
            f.eq(cents(ledger.outflow), cents(ledger.planOutflow) + cents(ledger.manualOutflow), what)
            f.eq(cents(ledger.toPots), cents(ledger.planToPots) + cents(ledger.manualToPots), what)

            // De dagen opgebouwd uit de gebeurtenissen, op een andere manier opgeteld (op soort).
            let list = events(month)
            func eventSum(_ kinds: [DayEventKind], _ amount: (DayEvent) -> Double) -> Int {
                CentsMath.sum(list.filter { kinds.contains($0.kind) }.map { cents(amount($0)) })
            }
            f.eq(eventSum([.salary, .income]) { $0.bankAmount }, cents(ledger.planInflow), what)
            f.eq(eventSum([.expense]) { $0.bankAmount }, -cents(ledger.planOutflow), what)
            f.eq(eventSum([.expense]) { $0.potAmount }, -cents(ledger.paidFromPots), what)
            f.eq(eventSum([.toPot]) { $0.potAmount }, cents(ledger.planToPots), what)
            f.eq(eventSum([.toHolding]) { $0.bankAmount }, -cents(ledger.toHoldings), what)
            f.eq(eventSum([.interest]) { $0.potAmount }, cents(ledger.interest), what)

            // Elke pot en belegging: de overschrijving op de overschrijfdag is hetzelfde bedrag als de verdeling van de maand,
            // ook bij een percentage. Het percentage is hier onafhankelijk nagerekend (hele centen, half omhoog).
            if month >= d.startMonth {
                let salaryCents = cents(d.salaryAmount(in: month))
                let incomeCents = cents(ledger.income)
                for id in d.pots.map(\.id) + d.holdings.map(\.id) {
                    let allocated = cents(d.allocation(id, in: month))
                    let transfers = list.filter { ($0.kind == .toPot && $0.potID == id) || ($0.kind == .toHolding && $0.holdingID == id) }
                    f.eq(CentsMath.sum(transfers.map { $0.kind == .toPot ? cents($0.potAmount) : -cents($0.bankAmount) }), allocated,
                         "overschrijving = verdeling: \(what)")
                    f.ok(transfers.allSatisfy { $0.day == d.transferDay(for: id, in: month) }, "overschrijfdag: \(what)")
                    f.eq(d.allocationCents(id, in: month), allocated, "allocationCents: \(what)")
                    f.ok(allocated >= 0 || d.months[month.key]?.allocations[id.uuidString] != nil, "geen negatief percentage: \(what)")
                    if case .percent(let rule) = d.allocationRule(id, in: month) {
                        let hundredths = Int((min(max(rule.percent, 0), 100) * 100).rounded())
                        let base = max(0, rule.basis == .salary ? salaryCents : incomeCents)
                        f.eq(allocated, (base * hundredths + 5_000) / 10_000, "percentage van het inkomen: \(what)")
                        coverage.percentMonths += 1
                        if rule.basis == .allIncome && incomeCents != salaryCents { coverage.percentMonthsWithBothBases += 1 }
                    }
                }
                // Een waarschuwing bij te veel verdeeld is een berekende eigenschap, geen crash.
                let warnings = d.allocationWarnings(in: month)
                f.eq(warnings.isEmpty, d.allocationWarning(in: month) == nil, "waarschuwing: \(what)")
                if d.percentTotal(in: month) > 100 {
                    f.ok(warnings.contains { if case .percentagesOver100 = $0 { return true } else { return false } }, "meer dan 100%: \(what)")
                }
            }

            // Het salaris: de uitbetalingen vallen op hun eigen dag, met het bedrag dat een onafhankelijke berekening geeft (stap
            // voor stap met `Calendar`, in hele centen), en het maandtotaal is hun som, overal hetzelfde.
            if month >= d.startMonth {
                let plan = d.plan(for: month)
                let expected = referenceSalaryPayouts(d.salary, start: d.startMonth, month: month,
                                                      salaryOverride: plan.salaryOverride, hoursOverride: plan.hoursOverride)
                let payouts = d.salaryPayouts(in: month, plan: plan)
                f.eq(payouts.map(\.day), expected.map(\.day), "dagen van de uitbetalingen: \(what)")
                f.eq(payouts.map(\.cents), expected.map(\.cents), "bedragen van de uitbetalingen: \(what)")
                let expectedTotal = expected.reduce(0) { $0 + $1.cents }
                f.eq(cents(d.salaryAmount(in: month)), expectedTotal, "salaris van de maand: \(what)")
                f.eq(d.salaryCents(in: month, plan: plan), expectedTotal, "salaris in centen: \(what)")
                f.eq(CentsMath.sum(list.filter { $0.kind == .salary }.map { cents($0.bankAmount) }), expectedTotal,
                     "salaris volgens de gebeurtenissen: \(what)")
                f.eq(list.filter { $0.kind == .salary }.map(\.day), expected.filter { $0.cents != 0 }.map(\.day),
                     "dagen van de salarisgebeurtenissen: \(what)")
                let salaryIDs = list.filter { $0.kind == .salary }.map(\.id)
                f.eq(Set(salaryIDs).count, salaryIDs.count, "elke uitbetaling heeft een eigen id: \(what)")
                f.eq(d.salaryPayDays(in: month), referencePayDays(d.salary, start: d.startMonth, month: month), "schema: \(what)")
                // De overschrijfdag zonder eigen dag is de eerste uitbetaling van de maand, anders de salarisdag.
                f.eq(d.salaryDay(in: month), d.salary.schedule == .monthly ? d.salaryDay()
                        : (referencePayDays(d.salary, start: d.startMonth, month: month).first ?? d.salaryDay()),
                     "salarisdag: \(what)")
                if d.salary.schedule != .monthly {
                    coverage.scheduleMonths += 1
                    if expected.count > 1 { coverage.monthsWithSeveralPayouts += 1 }
                    if referencePayDays(d.salary, start: d.startMonth, month: month).isEmpty { coverage.monthsWithoutPayout += 1 }
                    if plan.salaryOverride != nil || plan.hoursOverride != nil { coverage.overriddenSalaryMonths += 1 }
                }
            }

            // Het banksaldo per dag: de dagreeks van de motor geeft voor elke dag hetzelfde.
            for day in ledger.days {
                let at = "\(what)-\(day.day)"
                let point = seriesByDate[day.date]
                f.eq(day.bankBalance, point?.balance, "saldo per dag: \(at)")
                f.eq(day.events.map(\.id), point?.events.map(\.id) ?? day.events.map(\.id), at)
            }

            // Per dag.
            var idsByDay: [Int: [String]] = [:]
            for event in list { idsByDay[event.day, default: []].append(event.id) }
            var snapshotInside = false
            for (index, day) in ledger.days.enumerated() {
                let at = "\(what)-\(day.day)"
                f.eq(day.day, index + 1, at)
                f.eq(DayMath.dayNumber(of: day.date, calendar: cal), day.day, at)
                f.eq(YearMonth(date: day.date, calendar: cal), month, at)
                f.eq(cal.component(.hour, from: day.date), 12, at)
                f.ok(day.bankReconciles, "bank sluit niet op de dag: \(at)")
                f.ok(day.potsReconciles, "potten sluiten niet op de dag: \(at)")

                // Begin en eind van de dag hangen aan elkaar.
                if index == 0 {
                    f.eq(day.openingBank, ledger.openingBank, at)
                    f.eq(cents(day.openingPots), cents(ledger.openingPots), at)
                } else {
                    f.eq(day.openingBank, ledger.days[index - 1].bankBalance, at)
                    f.eq(cents(day.openingPots), cents(ledger.days[index - 1].potsTotal), at)
                }
                if let opening = day.openingBank, let closing = day.bankBalance {
                    f.eq(cents(closing), cents(opening) + cents(day.bankChange), "dagsaldo bank: \(at)")
                }
                f.eq(cents(day.potsTotal), cents(day.openingPots) + cents(day.potsChange), "dagsaldo potten: \(at)")
                f.eq(cents(day.inflow), cents(day.planInflow) + cents(day.manualInflow), at)
                f.eq(cents(day.outflow), cents(day.planOutflow) + cents(day.manualOutflow), at)
                f.eq(cents(day.toPots), cents(day.planToPots) + cents(day.manualToPots), at)
                f.ok(day.paidFromPots >= 0, at)

                // De gebeurtenissen van de dag zijn die van de motor.
                f.eq(day.events.map(\.id), idsByDay[day.day] ?? [], at)
                f.ok(day.events.allSatisfy { $0.day == day.day }, at)

                // Vandaag en gepland, per kalenderdag.
                let dayStart = cal.startOfDay(for: day.date)
                f.eq(day.isToday, dayStart == todayStart, "vandaag: \(at)")
                f.eq(day.isPlanned, dayStart > todayStart, "gepland: \(at)")
                f.ok(day.events.allSatisfy { $0.isPlanned == day.isPlanned }, "gebeurtenissen gepland: \(at)")

                // De cijfers tegenover de rest van de motor.
                if exhaustive || index == n / 2 {
                    f.eq(cents(day.potsTotal), cents(d.totalSaved(asOf: day.date)), "potten per dag: \(at)")
                    f.eq(day.bankBalance, d.bankBalance(on: day.date), "saldo per dag: \(at)")
                    let reference = referenceBankBalanceCents(d, endOfDay: day.date, events: events)
                    f.eq(day.bankBalance.map { cents($0) }, reference, "saldo volgens de gebeurtenissen: \(at)")
                    if day.bankBalance != nil { coverage.daysWithBank += 1 }
                } else if day.bankBalance != nil {
                    coverage.daysWithBank += 1
                }
                if day.bankCorrection != 0 { coverage.corrections += 1 }
                if day.paidFromPots > 0 { coverage.paidFromPots += 1 }
                if day.interest > 0 { coverage.interest += 1 }
                if day.manualToPots != 0 { coverage.manualTransfers += 1 }
                if day.toPots < 0 { coverage.negativeToPots += 1 }
                if day.potEntriesNet != 0 { coverage.potEntries += 1 }
                if day.toHoldings != 0 { coverage.holdings += 1 }
                if day.events.filter({ $0.kind == .salary || $0.kind == .income }).count > 1 { coverage.daysWithSeveralInflows += 1 }
                if day.bankCorrection != 0 || snapshotDays.contains(dayStart) {
                    snapshotInside = true
                }
            }
            if snapshotInside { coverage.monthsWithSnapshotInside += 1 }

            // De nog te verdelen loopt op en eindigt op de motor.
            f.eq(cents(ledger.days[n - 1].remainingSoFar), cents(d.remaining(in: month)), "te verdelen aan het eind: \(what)")
            var runningRemaining = 0
            for day in ledger.days {
                runningRemaining += cents(day.planInflow) - cents(day.planOutflow) - cents(day.planToPots) - cents(day.toHoldings)
                f.eq(cents(day.remainingSoFar), runningRemaining, "te verdelen t/m de dag: \(what)-\(day.day)")
            }

            // Eind van de maand: de andere wegen in de motor.
            f.eq(ledger.closingBank, d.bankBalance(at: month), what)
            f.eq(ledger.closingBank, ledger.days[n - 1].bankBalance, what)
            f.eq(cents(ledger.closingPots), cents(d.totalSaved(asOf: month.date(day: n))), what)
            f.eq(cents(ledger.closingPots), cents(ledger.days[n - 1].potsTotal), what)
            if exhaustive || month == todayMonth {
                let worth = d.netWorth(at: month, current: todayMonth)
                f.eq(cents(worth.bank), cents(ledger.closingBank ?? 0), "vermogen, bank: \(what)")
                f.eq(cents(worth.pots), cents(ledger.closingPots), "vermogen, potten: \(what)")
                let monthly = d.bankSeries(from: month, count: 1, current: todayMonth)
                f.eq(monthly.first?.balance, ledger.closingBank, "maandreeks: \(what)")
                if let lowest = d.lowestBankPoint(in: month) {
                    let known = ledger.days.compactMap { $0.bankBalance }
                    f.eq(lowest.balance, known.min(), "laagste punt: \(what)")
                } else {
                    f.ok(ledger.days.allSatisfy { $0.bankBalance == nil }, "laagste punt: \(what)")
                }
            }

            // Eén dag los opvragen geeft hetzelfde als de hele maand.
            if exhaustive {
                let day = ledger.days[rng.int(0...n - 1)]
                f.eq(d.dayTotals(on: day.date, asOf: today), day, "dayTotals: \(what)-\(day.day)")
            }

            // "Nu": de saldi van vandaag zijn die van de dag van vandaag.
            if month == todayMonth, let index = ledger.days.firstIndex(where: { $0.isToday }) {
                coverage.todayChecks += 1
                verifyNow(d, scenario: scenario, ledger: ledger, todayIndex: index, tag: what, f)
            }

            previous = ledger
        }

        // De periode is de som van de maanden.
        let period = PeriodSummary(months: summaries)
        f.eq(period.income, centsToValue(ledgers.map { cents($0.income) }), tag)
        f.eq(period.expenses, centsToValue(ledgers.map { cents($0.expensesTotal) }), tag)
        f.eq(period.fromPots, centsToValue(ledgers.map { cents($0.paidFromPots) }), tag)
        f.eq(period.saved, centsToValue(ledgers.map { cents($0.planToPots) }), tag)
        f.eq(period.invested, centsToValue(ledgers.map { cents($0.toHoldings) }), tag)
        f.eq(period.remaining, centsToValue(ledgers.map { cents($0.remaining) }), tag)
        let half = d.periodSummary(.halfYear, containing: todayMonth, current: todayMonth)
        let halfLedgers = PeriodMode.halfYear.months(containing: todayMonth).map { d.monthLedger($0, asOf: today) }
        f.eq(half.income, centsToValue(halfLedgers.map { cents($0.income) }), tag)
        f.eq(half.remaining, centsToValue(halfLedgers.map { cents($0.remaining) }), tag)
        f.eq(half.saved, centsToValue(halfLedgers.map { cents($0.planToPots) }), tag)
        f.eq(half.expenses, centsToValue(halfLedgers.map { cents($0.expensesTotal) }), tag)
    }

    private func centsToValue(_ list: [Int]) -> Double { CentsMath.value(CentsMath.sum(list)) }

    /// De saldi van nu (bank, potten, vermogen, geschiedenis van een pot) op het eind van vandaag en op het moment zelf.
    private func verifyNow(_ d: FinanceData, scenario: LedgerScenario, ledger: MonthLedger, todayIndex: Int, tag: String,
                           _ f: Failures) {
        let cal = YearMonth.calendar
        let today = scenario.today
        let month = ledger.month
        let day = ledger.days[todayIndex]
        let endOfToday = DayMath.lastMoment(before: DayMath.nextDayStart(after: today, calendar: cal))

        // Het eind van vandaag: precies het saldo van de dag.
        f.eq(d.bankBalanceNow(current: month, today: endOfToday), day.bankBalance ?? 0, "bank nu (eind van de dag): \(tag)")
        f.eq(d.bankBalance(atMoment: endOfToday), day.bankBalance, "bank op het eind van de dag: \(tag)")
        f.eq(cents(d.totalSaved(current: month, today: endOfToday)), cents(day.potsTotal), "potten nu (eind van de dag): \(tag)")
        let worth = d.netWorthNow(current: month, today: endOfToday)
        f.eq(worth.bank, day.bankBalance ?? 0, "vermogen, bank: \(tag)")
        f.eq(cents(worth.pots), cents(day.potsTotal), "vermogen, potten: \(tag)")
        for pot in d.pots {
            let flows = d.potFlows(pot, throughMonth: month)
            f.eq(cents(d.potBalanceNow(pot.id, current: month, today: endOfToday)),
                           cents(d.potBalance(pot.id, asOf: endOfToday)), "pot nu: \(tag)")
            // De geschiedenis van de pot: wat niet gepland is, is het saldo van nu.
            let timeline = d.potTimeline(pot.id, current: month, asOf: endOfToday)
            let done = timeline.filter { !$0.isPlanned }.reduce(0) { $0 + cents($1.amount) }
            f.eq(done, cents(d.potBalanceNow(pot.id, current: month, today: endOfToday)), "geschiedenis pot: \(tag)")
            _ = flows
        }

        // Het moment zelf: boekingen van de dag die later vallen dan nu (alleen mogelijk in deze testdata) tellen nog niet.
        let lateBank = d.bankEntries.filter { cal.isDate($0.date, inSameDayAs: today) && $0.date > today }
        let lateSnapshot = d.bankSnapshots.contains { cal.isDate($0.date, inSameDayAs: today) && $0.date > today }
        if !lateSnapshot, d.bankBalance(atMoment: today) != nil, let closing = day.bankBalance {
            let late = CentsMath.sum(lateBank.map { cents($0.amount) })
            f.eq(d.bankBalanceNow(current: month, today: today), CentsMath.value(cents(closing) - late), "bank nu: \(tag)")
        }
        var latePots = 0
        for pot in d.pots {
            let managed = d.potFlows(pot, throughMonth: month).managedIDs
            latePots += CentsMath.sum(d.potEntries.filter {
                $0.potID == pot.id && cal.isDate($0.date, inSameDayAs: today) && $0.date > today && !managed.contains($0.id)
            }.map { cents($0.amount) })
        }
        f.eq(cents(d.totalSaved(current: month, today: today)), cents(day.potsTotal) - latePots, "potten nu: \(tag)")
    }
}
