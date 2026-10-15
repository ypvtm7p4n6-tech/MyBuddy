import XCTest
import Foundation
@testable import MyBuddyCore

// Tests van de pure logica uit CashflowPages.swift (zonder SwiftUI), tegen de echte rekenmotor.
// Elke verwachte waarde komt uit de motor zelf (dayTotals, monthLedger, bankBalance, summary) of is op papier nagerekend.

private let cal = YearMonth.calendar

/// Eén dag met alleen een datum en een saldo, voor de tests van de waarschuwing.
private func plainDay(_ date: Date, balance: Double?) -> DayTotals {
    DayTotals(date: date, day: engDayNumber(date), inflow: 0, outflow: 0, toPots: 0, toHoldings: 0, paidFromPots: 0,
              interest: 0, bankBalance: balance, potsTotal: 0, remainingSoFar: 0, events: [], isPlanned: false,
              isToday: false, hasActivity: false)
}

/// Gegevens met een salaris, huur, een pot met inleg en een banksaldo, "vandaag" is 14 oktober 2026.
private func sampleData() -> (data: FinanceData, today: Date) {
    var d = makeBaseData()
    _ = addBufferPot(&d)
    d.addBankSnapshot(balance: 1_000, note: "Begin", date: day(aug2026, 1))
    return (d, engTime(oct2026, 14, hour: 15))
}

final class CashflowDisplayTests: XCTestCase {
    // MARK: LedgerBook = de motor

    func testBookIsTheEngineLedger() {
        for seed in 1...150 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let book = LedgerBook(sc.data, today: sc.today)
            for month in sc.months {
                let direct = sc.data.monthLedger(month, asOf: sc.today)
                XCTAssertEqual(book.ledger(month), direct, "seed \(seed) \(month.key)")
                XCTAssertEqual(book.ledger(month), direct, "uit de cache: seed \(seed) \(month.key)")
            }
        }
    }

    func testBookDayIsTheEngineDay() {
        for seed in 1...50 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let book = LedgerBook(sc.data, today: sc.today)
            for month in sc.months.prefix(5) {
                for number in [1, 2, 14, month.dayCount - 1, month.dayCount] {
                    // Het tijdstip van de dag doet er niet toe: dezelfde kalenderdag.
                    for hour in [0.0, 0.01, 12, 23.99] {
                        let date = engTime(month, number, hour: hour)
                        XCTAssertEqual(book.day(date), sc.data.dayTotals(on: date, asOf: sc.today),
                                       "seed \(seed) \(month.key)-\(number) \(hour)u")
                    }
                }
            }
        }
    }

    func testDaysSpanMonthBoundaries() {
        let (d, today) = sampleData()
        let book = LedgerBook(d, today: today)
        let days = book.days(from: engTime(aug2026, 30, hour: 20), to: engTime(sep2026, 2, hour: 3))
        XCTAssertEqual(days.map { $0.day }, [30, 31, 1, 2])
        XCTAssertEqual(days.map { YearMonth(date: $0.date).key }, ["2026-08", "2026-08", "2026-09", "2026-09"])
        XCTAssertEqual(days[0], d.dayTotals(on: engTime(aug2026, 30, hour: 12), asOf: today))
        XCTAssertEqual(days[3], d.dayTotals(on: engTime(sep2026, 2, hour: 12), asOf: today))
        // De dagen sluiten op elkaar aan: het begin van een dag is het eind van de dag ervoor.
        for (a, b) in zip(days, days.dropFirst()) {
            XCTAssertEqual(b.openingBank, a.bankBalance)
            XCTAssertEqual(b.openingPots, a.potsTotal)
        }
        // Een jaargrens en een schrikkeljaar.
        let across = book.days(from: engTime(engDec2026, 30, hour: 12), to: engTime(engJan2027, 2, hour: 12))
        XCTAssertEqual(across.map { $0.day }, [30, 31, 1, 2])
        let leap = LedgerBook(d, today: today).days(from: engTime(engFeb2028, 27, hour: 12), to: engTime(engMar2027.adding(12), 1, hour: 12))
        XCTAssertEqual(leap.map { $0.day }, [27, 28, 29, 1])
        // Een omgekeerd bereik is leeg en de limiet werkt.
        XCTAssertTrue(book.days(from: engTime(sep2026, 5, hour: 12), to: engTime(sep2026, 4, hour: 12)).isEmpty)
        XCTAssertEqual(book.days(from: engTime(aug2026, 1, hour: 0), to: engTime(oct2026, 31, hour: 0), limit: 3).count, 3)
        XCTAssertEqual(book.days(from: engTime(aug2026, 1, hour: 0), to: engTime(oct2026, 31, hour: 0)).count, 31 + 30 + 31)
    }

    // MARK: Het getoonde overzicht sluit

    func testRowsCloseTheBankAndPotsEverywhere() {
        var checkedBank = 0
        var checkedPots = 0
        for seed in 1...300 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let book = LedgerBook(sc.data, today: sc.today)
            for month in sc.months {
                let l = book.ledger(month)

                let bank = CashflowSummary.bankRows(l)
                XCTAssertEqual(bank.first?.kind, .begin)
                XCTAssertEqual(bank.last?.kind, .end)
                XCTAssertEqual(bank.first?.amount, l.openingBank)
                XCTAssertEqual(bank.last?.amount, l.closingBank)
                XCTAssertEqual(Set(bank.map { $0.id }).count, bank.count, "id's van de bankregels zijn uniek")
                for row in bank where row.style != .line { XCTAssertEqual(row.effectCents, 0, "begin, eind en details doen niets") }
                if let open = l.openingBank, let close = l.closingBank {
                    let effects = bank.reduce(0) { $0 + $1.effectCents }
                    XCTAssertEqual(CentsMath.int(open) + effects, CentsMath.int(close), "bank seed \(seed) \(month.key)")
                    checkedBank += 1
                }

                let pots = CashflowSummary.potsRows(l)
                XCTAssertEqual(pots.first?.kind, .begin)
                XCTAssertEqual(pots.last?.kind, .end)
                XCTAssertEqual(Set(pots.map { $0.id }).count, pots.count)
                let potEffects = pots.reduce(0) { $0 + $1.effectCents }
                XCTAssertEqual(CentsMath.int(l.openingPots) + potEffects, CentsMath.int(l.closingPots), "potten seed \(seed) \(month.key)")
                checkedPots += 1

                // En de controle van de pagina is het eens met de motor.
                let check = LedgerCheck(l)
                XCTAssertTrue(l.allReconciles, "seed \(seed) \(month.key)")
                XCTAssertEqual(check.isOK, l.allReconciles)
                XCTAssertTrue(check.issues.isEmpty)
            }
        }
        XCTAssertGreaterThan(checkedBank, 1_000)
        XCTAssertGreaterThan(checkedPots, 1_000)
    }

    func testBankRowsShowManualMovementsApart() {
        var (d, today) = sampleData()
        d.addBankEntry(amount: 250, note: "Cadeau", date: engTime(sep2026, 10, hour: 9))
        d.addBankEntry(amount: -80, note: "Pinnen", date: engTime(sep2026, 11, hour: 9))
        let pot = d.pots[0]
        d.transferBankToPot(potID: pot.id, amount: 120, date: engTime(sep2026, 12, hour: 9))
        d.transferPotToBank(potID: pot.id, amount: 20, date: engTime(sep2026, 13, hour: 9))
        let l = d.monthLedger(sep2026, asOf: today)
        let rows = CashflowSummary.bankRows(l)
        func row(_ kind: CashflowRow.Kind) -> CashflowRow? { rows.first { $0.kind == kind } }
        XCTAssertEqual(row(.inflowManual)?.amount, 250)
        XCTAssertEqual(row(.inflowPlan)?.amount, 3_100)
        XCTAssertEqual(row(.outflowManual)?.amount, 80)
        XCTAssertEqual(row(.outflowPlan)?.amount, 1_000)
        XCTAssertEqual(row(.toPotsManual)?.amount, 100)
        XCTAssertEqual(row(.toPotsManual)?.showsSign, true)
        XCTAssertEqual(row(.toPotsPlan)?.amount, 200)
        XCTAssertEqual(row(.toPots)?.amount, 300)
        XCTAssertEqual(row(.toPots)?.sign, "−")
        XCTAssertEqual(row(.toPots)?.title, "Overgeschreven naar spaarpotten")
        XCTAssertEqual(row(.inflow)?.amount, 3_350)
        XCTAssertEqual(row(.outflow)?.amount, 1_080)
        XCTAssertNil(row(.correction))
        XCTAssertNil(row(.toHoldings))
        let opening = l.openingBank ?? 0
        XCTAssertEqual(CentsMath.int(opening) + rows.reduce(0) { $0 + $1.effectCents }, CentsMath.int(l.closingBank ?? 0))
        // De potten krijgen het handmatige deel erbij.
        let pots = CashflowSummary.potsRows(l)
        XCTAssertEqual(pots.first { $0.kind == .potsManual }?.amount, 100)
        XCTAssertEqual(pots.first { $0.kind == .potsPlan }?.amount, 200)
    }

    func testBankRowsWhenMoreComesBackFromPotsThanGoesThere() {
        var (d, today) = sampleData()
        let pot = d.pots[0]
        d.transferPotToBank(potID: pot.id, amount: 500, date: engTime(sep2026, 12, hour: 9))
        let l = d.monthLedger(sep2026, asOf: today)
        // De inleg is 200, er komt 500 terug: netto 300 geld erbij op de bankrekening.
        XCTAssertEqual(l.toPots, -300)
        let rows = CashflowSummary.bankRows(l)
        let r = rows.first { $0.kind == .toPots }
        XCTAssertEqual(r?.title, "Teruggeboekt van spaarpotten")
        XCTAssertEqual(r?.sign, "+")
        XCTAssertEqual(r?.amount, 300)
        XCTAssertEqual(r?.effectCents, 30_000)
        XCTAssertEqual(CentsMath.int(l.openingBank ?? 0) + rows.reduce(0) { $0 + $1.effectCents }, CentsMath.int(l.closingBank ?? 0))
    }

    func testBankRowsShowTheSalaryPayoutsAndCorrections() {
        var (d, today) = sampleData()
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 500, hourlyRate: 0, hoursPerWeek: 0)
        d.salary.setSchedule(.weeks, interval: 1, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        // Een saldo dat afwijkt van wat de app verwachtte.
        d.addBankSnapshot(balance: 9_999, note: "Meting", date: engTime(oct2026, 8, hour: 10))
        let l = d.monthLedger(oct2026, asOf: today)
        XCTAssertEqual(l.salaryPayoutCount, 5, "vrijdagen: 2, 9, 16, 23, 30")
        let rows = CashflowSummary.bankRows(l)
        XCTAssertEqual(rows.first { $0.kind == .inflow }?.note, "Met 5 salarisuitbetalingen")
        let correction = rows.first { $0.kind == .correction }
        XCTAssertNotNil(correction)
        XCTAssertEqual(correction?.sign, "±")
        XCTAssertEqual(correction?.showsSign, true)
        XCTAssertEqual(correction?.effectCents, CentsMath.int(l.bankCorrections))
        XCTAssertEqual(CentsMath.int(l.openingBank ?? 0) + rows.reduce(0) { $0 + $1.effectCents }, CentsMath.int(l.closingBank ?? 0))
        XCTAssertTrue(LedgerCheck(l).isOK)
    }

    func testBankRowsWithoutAKnownBalance() {
        var d = makeBaseData()
        d.bankSnapshots = []
        let l = d.monthLedger(sep2026, asOf: engTime(oct2026, 14, hour: 15))
        let rows = CashflowSummary.bankRows(l)
        XCTAssertNil(rows.first?.amount, "begin onbekend")
        XCTAssertNil(rows.last?.amount, "eind onbekend")
        XCTAssertTrue(LedgerCheck(l).isOK)
    }

    // MARK: De controle

    func testCheckExplainsEveryKindOfBreak() {
        let (d, today) = sampleData()
        let base = d.monthLedger(sep2026, asOf: today)
        XCTAssertTrue(base.allReconciles)
        XCTAssertTrue(LedgerCheck(base).isOK)

        // Het eindsaldo van de bank wijkt af.
        var bank = base
        bank.closingBank = (bank.closingBank ?? 0) + 12.34
        bank.bankReconciles = false
        var c = LedgerCheck(bank)
        XCTAssertFalse(c.isOK)
        XCTAssertEqual(c.issues.count, 1)
        let bankText = c.issues.first?.text ?? ""
        XCTAssertTrue(bankText.hasPrefix("Bankrekening: het eindsaldo wijkt"), bankText)
        XCTAssertTrue(bankText.contains("12,34"), bankText)

        // Eén dag sluit niet.
        var dayBreak = base
        dayBreak.days[4].bankBalance = (dayBreak.days[4].bankBalance ?? 0) - 1
        dayBreak.days[4].bankReconciles = false
        dayBreak.bankReconciles = false
        c = LedgerCheck(dayBreak)
        XCTAssertTrue(c.issues.contains { $0.text.hasPrefix("Bankrekening op \(DayText.weekdayShort(base.days[4].date))") && $0.text.contains("1,00") },
                      c.issues.map { $0.text }.joined(separator: "|"))

        // Het totaal van de spaarpotten wijkt af.
        var pots = base
        pots.closingPots += 5
        pots.potsReconciles = false
        c = LedgerCheck(pots)
        let potsText = c.issues.first?.text ?? ""
        XCTAssertTrue(potsText.hasPrefix("Spaarpotten: het eindsaldo wijkt"), potsText)
        XCTAssertTrue(potsText.contains("5,00"), potsText)

        var potDay = base
        potDay.days[2].potsTotal += 2.5
        potDay.days[2].potsReconciles = false
        potDay.potsReconciles = false
        c = LedgerCheck(potDay)
        XCTAssertTrue(c.issues.contains { $0.text.hasPrefix("Spaarpotten op") && $0.text.contains("2,50") }, c.issues.map { $0.text }.joined(separator: "|"))

        // Het overzicht wijkt af van de dagen.
        var overview = base
        overview.income += 7.5
        overview.overviewReconciles = false
        c = LedgerCheck(overview)
        XCTAssertTrue(c.issues.contains { $0.text.hasPrefix("Inkomen:") && $0.text.contains("7,50") }, c.issues.map { $0.text }.joined(separator: "|"))
        var saved = base
        saved.saved += 1
        saved.overviewReconciles = false
        XCTAssertTrue(LedgerCheck(saved).issues.contains { $0.text.hasPrefix("Gespaard:") && $0.text.contains("1,00") })
        var left = base
        left.remaining += 3
        left.overviewReconciles = false
        let leftIssues = LedgerCheck(left).issues.map { $0.text }
        XCTAssertTrue(leftIssues.contains { $0.hasPrefix("Nog te verdelen:") && $0.contains("3,00") }, leftIssues.joined(separator: "|"))
        XCTAssertTrue(leftIssues.contains { $0.hasPrefix("Nog te verdelen op de laatste dag:") }, leftIssues.joined(separator: "|"))
        var fromPots = base
        fromPots.expensesFromPots += 2
        fromPots.overviewReconciles = false
        XCTAssertTrue(LedgerCheck(fromPots).issues.contains { $0.text.hasPrefix("Uitgaven uit spaarpotten:") })
        var invested = base
        invested.invested += 4
        invested.overviewReconciles = false
        XCTAssertTrue(LedgerCheck(invested).issues.contains { $0.text.hasPrefix("Belegd:") && $0.text.contains("4,00") })
        var outgoing = base
        outgoing.expensesFromBank += 6
        outgoing.overviewReconciles = false
        XCTAssertTrue(LedgerCheck(outgoing).issues.contains { $0.text.hasPrefix("Uitgaven van je rekening:") && $0.text.contains("6,00") })

        // Alleen de vlag: een algemene melding, nooit een lege lijst.
        for (name, mutate) in [("bank", { (l: inout MonthLedger) in l.bankReconciles = false }),
                               ("potten", { (l: inout MonthLedger) in l.potsReconciles = false }),
                               ("overzicht", { (l: inout MonthLedger) in l.overviewReconciles = false })] {
            var flagged = base
            mutate(&flagged)
            let issues = LedgerCheck(flagged).issues
            XCTAssertEqual(issues.count, 1, name)
            XCTAssertFalse(issues.first?.text.isEmpty ?? true, name)
        }

        // Alles tegelijk: drie soorten meldingen, met unieke id's.
        var all = base
        all.bankReconciles = false
        all.potsReconciles = false
        all.overviewReconciles = false
        let ids = LedgerCheck(all).issues.map { $0.id }
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
    }

    // MARK: Filter, laagste punt, overgeschreven, uitbetalingen

    func testFilterKeepsDaysWithEntriesAndToday() {
        for seed in 1...120 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let book = LedgerBook(sc.data, today: sc.today)
            for month in sc.months {
                let l = book.ledger(month)
                XCTAssertEqual(CashflowDayFilter.all.days(of: l), l.days)
                let busy = CashflowDayFilter.withEntries.days(of: l)
                XCTAssertEqual(busy.map { $0.day }, l.days.filter { $0.hasActivity || $0.isToday }.map { $0.day })
                for day in l.days where !day.events.isEmpty { XCTAssertTrue(busy.contains { $0.day == day.day }) }
                if let today = l.days.first(where: { $0.isToday }) { XCTAssertTrue(busy.contains { $0.day == today.day }) }
                XCTAssertEqual(CashflowScroll.todayTarget(in: l), l.days.first(where: { $0.isToday })?.day)
            }
        }
        XCTAssertEqual(CashflowDayFilter.all.title, "Alle dagen")
        XCTAssertEqual(CashflowDayFilter.withEntries.title, "Alleen met boekingen")
    }

    func testTodayTargetOnlyInTheCurrentMonth() {
        let (d, today) = sampleData()
        let book = LedgerBook(d, today: today)
        XCTAssertEqual(CashflowScroll.todayTarget(in: book.ledger(oct2026)), 14)
        XCTAssertNil(CashflowScroll.todayTarget(in: book.ledger(sep2026)))
        XCTAssertNil(CashflowScroll.todayTarget(in: book.ledger(engNov2026)))
        // Per kalenderdag: vlak na middernacht en vlak voor middernacht is het dezelfde dag.
        for hour in [0.0, 0.01, 23.99] {
            let other = LedgerBook(d, today: engTime(oct2026, 14, hour: hour))
            XCTAssertEqual(CashflowScroll.todayTarget(in: other.ledger(oct2026)), 14)
        }
    }

    func testLowestPointAgreesWithTheEngine() {
        var compared = 0
        for seed in 1...200 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let book = LedgerBook(sc.data, today: sc.today)
            for month in sc.months {
                let ours = CashflowLowPoint.lowest(in: book.ledger(month).days)
                let theirs = sc.data.lowestBankPoint(in: month)
                XCTAssertEqual(ours?.bankBalance, theirs?.balance, "seed \(seed) \(month.key)")
                if let ours, let theirs { XCTAssertTrue(DayText.isSameDay(ours.date, theirs.date)); compared += 1 }
                else { XCTAssertNil(ours); XCTAssertNil(theirs) }
            }
        }
        XCTAssertGreaterThan(compared, 500)
        XCTAssertNil(CashflowLowPoint.lowest(in: []))
        let a = plainDay(day(oct2026, 1), balance: 50), b = plainDay(day(oct2026, 2), balance: 10)
        let c = plainDay(day(oct2026, 3), balance: 10), unknown = plainDay(day(oct2026, 4), balance: nil)
        XCTAssertEqual(CashflowLowPoint.lowest(in: [a, b, c, unknown])?.day, 2, "bij gelijke saldi de eerste")
        XCTAssertNil(CashflowLowPoint.lowest(in: [unknown]))
    }

    func testTotalTransferredAddsPotsAndHoldingsInCents() {
        var day = plainDay(day(oct2026, 1), balance: 0)
        day.toPots = 0.1
        day.toHoldings = 0.2
        XCTAssertEqual(day.totalTransferred, 0.3, "0,1 + 0,2 is precies 0,30, geen 0,30000000000000004")
        XCTAssertTrue(day.totalTransferred == 0.3)
        day.toPots = -250
        day.toHoldings = 100
        XCTAssertEqual(day.totalTransferred, -150)
        for seed in 1...80 {
            let sc = ledgerScenario(seed: UInt64(seed))
            for month in sc.months.prefix(6) {
                for d in sc.data.monthLedger(month, asOf: sc.today).days {
                    XCTAssertEqual(CentsMath.int(d.totalTransferred), CentsMath.int(d.toPots) + CentsMath.int(d.toHoldings))
                }
            }
        }
    }

    func testSalaryPayoutCountIsTheNumberOfPayoutsWithAnAmount() {
        for seed in 1...200 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let book = LedgerBook(sc.data, today: sc.today)
            for month in sc.months {
                let expected = month < sc.data.startMonth ? 0
                    : sc.data.salaryPayouts(in: month, plan: sc.data.plan(for: month)).filter { $0.cents != 0 }.count
                XCTAssertEqual(book.ledger(month).salaryPayoutCount, expected, "seed \(seed) \(month.key)")
            }
        }
    }

    func testOverviewFiguresAreTheOverviewFigures() {
        for seed in 1...120 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let book = LedgerBook(sc.data, today: sc.today)
            let current = YearMonth(date: sc.today)
            for month in sc.months {
                let l = book.ledger(month)
                let s = sc.data.summary(of: month, current: current)
                XCTAssertEqual(l.income, s.income)
                XCTAssertEqual(l.expensesTotal, s.expenses)
                XCTAssertEqual(l.expensesFromPots, s.fromPots)
                XCTAssertEqual(l.saved, s.saved)
                XCTAssertEqual(l.invested, s.invested)
                XCTAssertEqual(l.remaining, s.remaining)
                XCTAssertEqual(l.remaining, sc.data.remaining(in: month))
                XCTAssertEqual(l.closingBank, sc.data.bankBalance(at: month))
                XCTAssertEqual(l.closingPots, CentsMath.value(CentsMath.sum(sc.data.pots.map { CentsMath.int(sc.data.potBalance($0.id, at: month)) })))
            }
        }
    }

    // MARK: Grafiek en bereiken

    func testChartItemsAreTheDaysWithABalance() {
        let (d, today) = sampleData()
        let book = LedgerBook(d, today: today)
        let l = book.ledger(oct2026)
        let items = DayChartItem.items(from: l.days)
        XCTAssertEqual(items.count, 31)
        XCTAssertEqual(items.map { $0.value }, l.days.compactMap { $0.bankBalance })
        XCTAssertEqual(items.map { $0.planned }, l.days.map { $0.isPlanned })
        XCTAssertEqual(items.filter { !$0.planned }.count, 14, "t/m vandaag (14 oktober) is gebeurd")
        XCTAssertEqual(Set(items.map { $0.id }).count, 31)
        // Zonder saldo geen punten.
        var empty = makeBaseData()
        empty.bankSnapshots = []
        XCTAssertTrue(DayChartItem.items(from: empty.monthLedger(oct2026, asOf: today).days).isEmpty)
        // Een saldo dat pas later in de maand bekend is: alleen vanaf die dag.
        var late = makeBaseData()
        late.addBankSnapshot(balance: 100, note: "Laat", date: engTime(oct2026, 20, hour: 10))
        let lateItems = DayChartItem.items(from: late.monthLedger(oct2026, asOf: today).days)
        XCTAssertEqual(lateItems.count, 12)
        XCTAssertTrue(DayText.isSameDay(lateItems[0].date, engTime(oct2026, 20, hour: 12)))
    }

    func testChartRangeWindows() {
        let today = engTime(oct2026, 14, hour: 15)
        let next = DayChartRange.next30.window(focus: sep2026, today: today)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour], from: next.from), DateComponents(year: 2026, month: 10, day: 14, hour: 0))
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: next.to), DateComponents(year: 2026, month: 11, day: 12))
        let book = LedgerBook(makeBaseData(), today: today)
        XCTAssertEqual(book.days(from: next.from, to: next.to).count, 30)
        let month = DayChartRange.month.window(focus: engFeb2028, today: today)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: month.from), DateComponents(month: 2, day: 1))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: month.to), DateComponents(month: 2, day: 29))
        XCTAssertEqual(LedgerBook(makeBaseData(), today: today).days(from: month.from, to: month.to).count, 29)
        XCTAssertEqual(DayChartRange.allCases.count, 2)
    }

    func testDayBoundsContainTodayAndTheStart() {
        let today = engTime(oct2026, 14, hour: 15)
        let range = BankDayBounds.range(startMonth: aug2026, today: today)
        XCTAssertEqual(range.lowerBound, aug2026.firstDay)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: range.upperBound), DateComponents(year: 2028, month: 10, day: 14))
        XCTAssertTrue(range.contains(today))
        // Een startmaand in de toekomst (na een import): vandaag blijft kiesbaar.
        let late = BankDayBounds.range(startMonth: engDec2026, today: today)
        XCTAssertEqual(late.lowerBound, cal.startOfDay(for: today))
        XCTAssertTrue(late.contains(today))
        XCTAssertEqual(BankDayBounds.clamp(Date.distantPast, to: range), range.lowerBound)
        XCTAssertEqual(BankDayBounds.clamp(Date.distantFuture, to: range), range.upperBound)
        XCTAssertEqual(BankDayBounds.clamp(today, to: range), today)
    }

    func testLowPointWindow() {
        let today = engTime(oct2026, 14, hour: 15)
        let current = BankLowPointWindow.range(for: oct2026, current: oct2026, today: today)
        XCTAssertEqual(current.from, cal.startOfDay(for: today), "vanaf vandaag: een dip in het verleden verbergt niets")
        XCTAssertEqual(cal.dateComponents([.month, .day], from: current.to), DateComponents(month: 11, day: 13), "30 dagen vooruit")
        let late = BankLowPointWindow.range(for: oct2026, current: oct2026, today: engTime(oct2026, 31, hour: 8))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: late.to), DateComponents(month: 11, day: 30))
        let early = BankLowPointWindow.range(for: oct2026, current: oct2026, today: engTime(oct2026, 1, hour: 8))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: early.to), DateComponents(month: 10, day: 31), "minstens tot het eind van de maand")
        let past = BankLowPointWindow.range(for: sep2026, current: oct2026, today: today)
        XCTAssertEqual(past.from, sep2026.firstDay)
        XCTAssertTrue(DayText.isSameDay(past.to, engTime(sep2026, 30, hour: 12)))
        let future = BankLowPointWindow.range(for: engDec2026, current: oct2026, today: today)
        XCTAssertEqual(future.from, engDec2026.firstDay)
        XCTAssertTrue(DayText.isSameDay(future.to, engTime(engDec2026, 31, hour: 12)))
    }

    func testLowPointNote() {
        let today = engTime(oct2026, 14, hour: 15)
        let future = plainDay(engTime(oct2026, 20, hour: 12), balance: -40)
        let note = BankLowPointNote.make(low: future, buffer: 1_000, balanceNow: 2_000, today: today)
        XCTAssertEqual(note?.severe, true)
        XCTAssertTrue(note?.text.hasPrefix("Let op: op di 20 okt staat je saldo onder nul") ?? false, note?.text ?? "nil")
        XCTAssertTrue(note?.text.contains("40") ?? false, note?.text ?? "nil")

        let now = plainDay(engTime(oct2026, 14, hour: 12), balance: -1)
        XCTAssertTrue(BankLowPointNote.make(low: now, buffer: 0, balanceNow: nil, today: today)?.text.hasPrefix("Let op: vandaag staat je saldo onder nul") ?? false)

        let past = plainDay(engTime(oct2026, 5, hour: 12), balance: -10)
        let pastNote = BankLowPointNote.make(low: past, buffer: 0, balanceNow: nil, today: today)
        XCTAssertEqual(pastNote?.severe, true)
        XCTAssertTrue(pastNote?.text.hasPrefix("Op ma 5 okt stond je saldo onder nul") ?? false, pastNote?.text ?? "nil")

        // Onder de buffer, terwijl je er nu boven zit: een zachte melding.
        let dip = plainDay(engTime(oct2026, 25, hour: 12), balance: 400)
        let soft = BankLowPointNote.make(low: dip, buffer: 1_000, balanceNow: 1_500, today: today)
        XCTAssertEqual(soft?.severe, false)
        XCTAssertTrue(soft?.text.hasPrefix("Op zo 25 okt zakt je saldo naar") ?? false, soft?.text ?? "nil")
        XCTAssertTrue(soft?.text.contains("gewenste bankbuffer") ?? false)
        let todayDip = plainDay(engTime(oct2026, 14, hour: 12), balance: 400)
        XCTAssertTrue(BankLowPointNote.make(low: todayDip, buffer: 1_000, balanceNow: 1_500, today: today)?.text.hasPrefix("Vandaag zakt je saldo naar") ?? false)

        // Geen melding: nu al onder de buffer, saldo van nu onbekend, geen buffer, boven de buffer, een dip in het verleden,
        // of geen saldo op die dag.
        XCTAssertNil(BankLowPointNote.make(low: dip, buffer: 1_000, balanceNow: 900, today: today))
        XCTAssertNil(BankLowPointNote.make(low: dip, buffer: 1_000, balanceNow: nil, today: today))
        XCTAssertNil(BankLowPointNote.make(low: dip, buffer: 0, balanceNow: 1_500, today: today))
        XCTAssertNil(BankLowPointNote.make(low: plainDay(engTime(oct2026, 25, hour: 12), balance: 1_000), buffer: 1_000, balanceNow: 1_500, today: today))
        XCTAssertNil(BankLowPointNote.make(low: plainDay(engTime(oct2026, 5, hour: 12), balance: 400), buffer: 1_000, balanceNow: 1_500, today: today))
        XCTAssertNil(BankLowPointNote.make(low: plainDay(engTime(oct2026, 25, hour: 12), balance: nil), buffer: 1_000, balanceNow: 1_500, today: today))
    }

    // MARK: Teksten en opzoeken

    func testTexts() {
        XCTAssertEqual(DayText.ordinal(25), "de 25e")
        XCTAssertEqual(DayText.short(engTime(oct2026, 5, hour: 12)), "5 okt")
        XCTAssertEqual(DayText.weekdayShort(engTime(oct2026, 14, hour: 12)), "wo 14 okt")
        XCTAssertEqual(DayText.weekdayShort(engTime(oct2026, 18, hour: 0.5)), "zo 18 okt")
        XCTAssertEqual(DayText.weekdayShort(engTime(oct2026, 17, hour: 23.9)), "za 17 okt")
        XCTAssertEqual(DayText.list([]), "")
        XCTAssertEqual(DayText.list(["A"]), "A")
        XCTAssertEqual(DayText.list(["A", "B"]), "A en B")
        XCTAssertEqual(DayText.list(["A", "B", "C"]), "A, B en C")
        XCTAssertTrue(DayText.isSameDay(engTime(oct2026, 5, hour: 0.01), engTime(oct2026, 5, hour: 23.99)))
        XCTAssertFalse(DayText.isSameDay(engTime(oct2026, 5, hour: 23.99), engTime(oct2026, 6, hour: 0.01)))
        XCTAssertEqual(CashflowText.signed(3_000), "+ " + Fmt.euro(3_000))
        XCTAssertEqual(CashflowText.signed(-1_000), "− " + Fmt.euro(1_000))
        XCTAssertEqual(CashflowText.signed(0), Fmt.euro(0))
        XCTAssertEqual(CashflowText.signed(-0.0), Fmt.euro(0))
        XCTAssertEqual(CashflowText.days(0), "0 dagen")
        XCTAssertEqual(CashflowText.days(1), "1 dag")
        XCTAssertEqual(CashflowText.days(31), "31 dagen")
    }

    /// Rente onder de 10 euro toont centen (de afspraak van de app): "+ € 1,25", niet "+ € 1". Daarboven hele euro's.
    func testInterestShowsCentsUnderTenEuro() {
        XCTAssertEqual(CashflowText.signedInterest(1.25), "+ " + Fmt.euroExact(1.25))
        XCTAssertEqual(CashflowText.signedInterest(9.99), "+ " + Fmt.euroExact(9.99))
        XCTAssertEqual(CashflowText.signedInterest(12.24), "+ " + Fmt.euro(12.24))
        XCTAssertEqual(CashflowText.signedInterest(-3.5), "− " + Fmt.euroExact(3.5))
        XCTAssertEqual(CashflowText.signedInterest(0), Fmt.euro(0))
        XCTAssertNotEqual(CashflowText.signedInterest(1.25), CashflowText.signed(1.25), "signed rondt 1,25 af op 1")

        // In het overzicht van de spaarpotten van een maand: de rij "Rente" gebruikt dezelfde opmaak als de pagina van de pot.
        let (d, pot) = engInterestData(rate: 0.12, payoutDay: 28, opening: 100)   // 1% per maand van 100: 1,00 euro
        let book = LedgerBook(d, today: engTime(oct2026, 29, hour: 10))
        let rows = CashflowSummary.potsRows(book.ledger(sep2026))
        let interest = try? XCTUnwrap(rows.first { $0.kind == .interest })
        XCTAssertEqual(interest?.amountText, PotFormat.interest(interest?.amount ?? -1))
        XCTAssertEqual(interest?.amountText, Fmt.euroExact(1.01), "september: 101 x 1% is 1,01 euro, met centen")
        XCTAssertEqual(PotFormat.interest(d.interestPayments(for: pot.id, from: sep2026.firstDay, to: sep2026.date(day: 30)).first?.amount ?? 0),
                       interest?.amountText)
        // Andere regels: een bedrag met teken, een bedrag zonder teken, en onbekend.
        let plain = CashflowRow(kind: .end, title: "Eind", sign: "=", amount: 1_234.5)
        XCTAssertEqual(plain.amountText, Fmt.euro(1_234.5))
        let signed = CashflowRow(kind: .correction, title: "Verschil", sign: "±", amount: -40, showsSign: true)
        XCTAssertEqual(signed.amountText, CashflowText.signed(-40))
        XCTAssertNil(CashflowRow(kind: .begin, title: "Begin", sign: "", amount: nil).amountText)
    }

    func testPrintedFormats() {
        // Alleen om te zien hoe de bedragen in de meldingen eruitzien.
        print("euroExact:", Fmt.euroExact(12.34), "euro:", Fmt.euro(1234.5), "signed:", CashflowText.signed(-40.2))
    }

    func testLineLookupSurvivesDuplicateIDs() {
        var plan = MonthPlan()
        let line = MoneyLine(name: "Huur", amount: 1_000, isRecurring: true)
        var copy = line
        copy.amount = 5
        plan.expenses = [line, copy]
        plan.extraIncome = [MoneyLine(name: "Toeslag", amount: 100)]
        let lookup = CashflowLineLookup(plan: plan)
        XCTAssertEqual(lookup.expenses[line.id]?.amount, 1_000, "bij een dubbel id wint de eerste")
        XCTAssertEqual(lookup.expenses.count, 1)
        XCTAssertEqual(lookup.income.count, 1)
        XCTAssertNil(lookup.income[line.id])
    }
}
