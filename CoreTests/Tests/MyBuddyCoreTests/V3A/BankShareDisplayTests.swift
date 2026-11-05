import XCTest
import Foundation
@testable import MyBuddyCore

/// Het deel van de verdeling dat je aan de bankrekening toewees, op de schermen met maandcijfers (docs/work/plan2.md D3.3 en D3.7,
/// pakket V3A): elk scherm dat een getal bij "Nog te verdelen" of "Overgehouden" toont zegt hetzelfde als Verdelen, omdat één
/// functie (`MoneyLabels.left`) het getal bij het label kiest. `LibraryFigures` staat als symlink in deze map.
/// De zinnen van de grafiek staan in `StackedBarModelTests`, de cijfers van Bankrekening in `CashflowDisplayTests`.
final class BankShareDisplayTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)

    /// Salaris 3.000, huur 900, een spaarpot met 200 inleg en een banksaldo; "nu" is oktober 2026.
    private func base() -> FinanceData {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        d.addPot(Pot(name: "Vakantie", monthlyContribution: 200, startMonth: oct2026), openingBalance: 100, now: day(oct2026, 1))
        d.addBankSnapshot(balance: 1_000, note: "Begin", date: day(oct2026, 1))
        var plan = MonthPlan()
        plan.expenses = [MoneyLine(name: "Huur", amount: 900, isRecurring: true, day: 1)]
        d.months[oct2026.key] = plan
        return d
    }

    private func library(_ data: FinanceData) -> LibraryRowFigures {
        LibraryFigures(data: data, now: oct2026, today: day(oct2026, 14)).row(for: .distribute)
    }

    // MARK: Elk scherm zegt hetzelfde als Verdelen

    /// Voor elke maand en elk peilmoment: Verdelen (`MonthBoard`), Home, Bankrekening, het Maandoverzicht (tegel, "Maand voor
    /// maand" en de grafiek) geven het getal dat `MoneyLabels.left` kiest.
    func testEveryScreenSaysTheSameAsVerdelenOnRandomData() {
        var pairsWithBankShare = 0
        var pairs = 0
        for seed in 1...300 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let d = sc.data
            let today = YearMonth(date: sc.today)
            for month in sc.months {
                let figures = d.monthFigures(month)
                for current in [today, month, month.adding(1), month.adding(-1)] {
                    pairs += 1
                    let expected = MoneyLabels.left(figures, of: month, current: current)
                    let value = CentsMath.value(expected)
                    let context = "zaadwaarde \(seed) \(month.key) nu \(current.key)"
                    // Verdelen en Home (dezelfde `MonthBoard`).
                    XCTAssertEqual(MonthBoard(d, month: month).left(current: current), value, context)
                    XCTAssertEqual(MonthBoard(d, month: month).leftIsNegative(current: current), expected < 0, context)
                    // Binnen en eruit op Bankrekening.
                    XCTAssertEqual(BankFlowFigures(d, month: month).left(current: current), value, context)
                    // Het Maandoverzicht: "Maand voor maand" en de tegel van een maand.
                    let summary = d.summary(of: month, current: current)
                    XCTAssertEqual(summary.left(current: current), value, context)
                    XCTAssertEqual(MoneyLabels.left(PeriodSummary(months: [summary]).figures, of: month, current: current), expected, context)
                    // Een periode (Half jaar, Jaar) heet Overgehouden en toont wat er op de rekening bleef.
                    XCTAssertEqual(MoneyLabels.left(PeriodSummary(months: [summary]).figures, of: month, current: current, isPeriod: true),
                                   figures.remaining, context)
                    // De grafiek: de annotatie van een maand zegt hetzelfde getal.
                    let model = StackedBarModel.months([summary], startMonth: d.startMonth, current: current)
                    if let entry = model.entries.first {
                        XCTAssertEqual(entry.unassigned, value, accuracy: 0.001, "grafiek: \(context)")
                        if entry.shortfall == 0 && entry.toBank > 0 {
                            XCTAssertEqual(entry.detailRows.last?.label, "Nog te verdelen", "annotatie: \(context)")
                            XCTAssertEqual(entry.detailRows.last?.value ?? .nan, value, accuracy: 0.001, "annotatie: \(context)")
                        }
                        if month < current { XCTAssertEqual(entry.toBank, 0, "wat voorbij is noemt geen bankdeel: \(context)") }
                    }
                    if figures.toBank != 0 && month >= current { pairsWithBankShare += 1 }
                }
            }
        }
        XCTAssertGreaterThan(pairsWithBankShare, 200, "genoeg maanden met een bankdeel (van \(pairs) combinaties)")
    }

    /// Een periode (Half jaar of Jaar) toont "Overgehouden" met wat er op de rekening bleef; de maanden eronder elk hun eigen label.
    func testAPeriodShowsWhatStayedAndItsMonthsFollowTheirOwnLabel() {
        var d = base()
        d.materialize(upTo: oct2026)
        d.setContributionAmount(BankShare.id, amount: 300, current: oct2026)
        for mode in [PeriodMode.halfYear, PeriodMode.year] {
            let period = d.periodSummary(mode, containing: oct2026, current: oct2026)
            XCTAssertEqual(MoneyLabels.remainingLabel(of: oct2026, current: oct2026, isPeriod: true), "Overgehouden")
            XCTAssertEqual(MoneyLabels.left(period.figures, of: oct2026, current: oct2026, isPeriod: true), CentsMath.int(period.remaining))
            XCTAssertEqual(period.toBank, 300 * Double(period.months.filter { $0.month >= oct2026 }.count), accuracy: 0.001)
            for summary in period.months {
                let label = MoneyLabels.remainingLabel(of: summary.month, current: oct2026)
                let value = summary.left(current: oct2026)
                if label == "Overgehouden" {
                    XCTAssertEqual(value, summary.remaining, "\(summary.month.key)")
                } else {
                    XCTAssertEqual(label, "Nog te verdelen")
                    XCTAssertEqual(value, summary.unassigned, "\(summary.month.key)")
                    XCTAssertEqual(value, d.unassigned(in: summary.month), "\(summary.month.key)")
                }
            }
        }
    }

    // MARK: De Bibliotheek

    func testTheLibraryRowFollowsVerdelenWithABankShare() {
        var d = base()
        d.materialize(upTo: oct2026)
        // Zonder bankdeel: 3.000 - 900 - 200 = 1.900 nog te verdelen.
        var row = library(d)
        XCTAssertEqual(row.subtitle, "Nog te verdelen")
        XCTAssertEqual(row.value, Fmt.euro(1_900))
        XCTAssertEqual(row.tone, .normal)
        // Een bankdeel van 500: er blijft 1.900 op de rekening, 1.400 is nog niet toegewezen.
        d.setContributionAmount(BankShare.id, amount: 500, current: oct2026)
        row = library(d)
        XCTAssertEqual(row.subtitle, "Nog te verdelen")
        XCTAssertEqual(row.value, Fmt.euro(1_400))
        XCTAssertEqual(d.unassigned(in: oct2026), 1_400)
        XCTAssertEqual(row.value, Fmt.euro(MonthBoard(d, month: oct2026).left(current: oct2026)), "hetzelfde als Verdelen")
        // De rest naar de bankrekening: precies nul.
        d.sendRemainingToBank(in: oct2026)
        row = library(d)
        XCTAssertEqual(row.subtitle, "Nog te verdelen")
        XCTAssertEqual(row.value, Fmt.euro(0))
        XCTAssertEqual(row.tone, .normal)
        XCTAssertEqual(d.remaining(in: oct2026), 1_900, "wat er op de rekening blijft verandert niet")
    }

    func testTheLibraryRowSaysTooMuchIsDistributedWhenTheBankShareDoesNotFit() {
        var d = base()
        d.materialize(upTo: oct2026)
        d.setContributionAmount(BankShare.id, amount: 2_500, current: oct2026)
        XCTAssertGreaterThan(d.remaining(in: oct2026), 0, "er blijft geld op de rekening")
        let row = library(d)
        XCTAssertEqual(row.subtitle, "Je hebt te veel verdeeld")
        XCTAssertEqual(row.value, Fmt.euro(-600))
        XCTAssertEqual(row.tone, .negative)
        XCTAssertEqual(d.unassigned(in: oct2026), -600)
    }

    func testTheLibraryRowKeepsSayingSpendingIsTooHighWithoutIncome() {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 0, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var plan = MonthPlan()
        plan.expenses = [MoneyLine(name: "Huur", amount: 900, isRecurring: true, day: 1)]
        d.months[oct2026.key] = plan
        d.setContributionAmount(BankShare.id, amount: 100, current: oct2026)
        let row = library(d)
        XCTAssertEqual(row.subtitle, "Je uitgaven zijn hoger dan je inkomen")
        XCTAssertEqual(row.value, Fmt.euro(-1_000))
        XCTAssertEqual(row.tone, .negative)
    }

    /// De rij van de Bibliotheek zegt voor elke dataset hetzelfde getal als Verdelen (de huidige maand van elke dataset).
    func testTheLibraryRowSaysTheSameAsVerdelenOnRandomData() {
        var withBank = 0
        for seed in 1...300 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let now = YearMonth(date: sc.today)
            let figures = sc.data.monthFigures(now)
            let row = LibraryFigures(data: sc.data, now: now, today: sc.today).row(for: .distribute)
            let left = MoneyLabels.left(figures, of: now, current: now)
            XCTAssertEqual(row.value, Fmt.euro(CentsMath.value(left)), "zaadwaarde \(seed)")
            XCTAssertEqual(row.value, Fmt.euro(MonthBoard(sc.data, month: now).left(current: now)), "zaadwaarde \(seed)")
            XCTAssertEqual(row.tone == .negative, left < 0, "zaadwaarde \(seed)")
            if left >= 0 { XCTAssertEqual(row.subtitle, "Nog te verdelen", "zaadwaarde \(seed)") }
            else if figures.available < 0 { XCTAssertEqual(row.subtitle, "Je uitgaven zijn hoger dan je inkomen", "zaadwaarde \(seed)") }
            else { XCTAssertEqual(row.subtitle, "Je hebt te veel verdeeld", "zaadwaarde \(seed)") }
            if figures.toBank != 0 { withBank += 1 }
        }
        XCTAssertGreaterThan(withBank, 20, "genoeg datasets met een bankdeel in de huidige maand")
    }

    // MARK: Home

    /// Home toont altijd de huidige maand: het getal van de hero is `unassigned` en "te veel verdeeld" volgt het teken ervan.
    func testTheHomeNumberIsWhatIsStillUnassigned() {
        var d = base()
        d.materialize(upTo: oct2026)
        d.setContributionAmount(BankShare.id, amount: 2_500, current: oct2026)
        let board = MonthBoard(d, month: oct2026)
        XCTAssertEqual(board.left(current: oct2026), -600)
        XCTAssertTrue(board.leftIsNegative(current: oct2026), "te veel verdeeld: rood")
        XCTAssertFalse(board.isNegative, "wat er op de rekening blijft is niet negatief")
        XCTAssertFalse(board.spendingExceedsIncome, "het komt door het bankdeel, niet door te hoge uitgaven")
        XCTAssertEqual(board.toBank, 2_500)
        XCTAssertEqual(BankShareText.summaryNote(toBankCents: board.figures.toBank)?.contains(Fmt.euro(2_500)), true)
    }

    // MARK: Verdeeld op Verdelen

    /// De meter "Verdeeld" sluit met het getal: inkomen min uitgaven van de bank min verdeeld is het getal bij het label, ook met
    /// een bankdeel (nu en later) en zonder het bankdeel in het verleden.
    func testTheDistributedFigureClosesOnTheNumberAtTheLabel() {
        var checked = 0
        for seed in 1...300 {
            let sc = ledgerScenario(seed: UInt64(seed))
            let today = YearMonth(date: sc.today)
            for month in sc.months {
                let board = MonthBoard(sc.data, month: month)
                for current in [today, month, month.adding(1)] {
                    let closing = CentsMath.int(board.income) - CentsMath.int(board.expensesFromBank)
                        - CentsMath.int(board.distributedShown(current: current))
                    XCTAssertEqual(closing, CentsMath.int(board.left(current: current)), "zaadwaarde \(seed) \(month.key) nu \(current.key)")
                    if board.toBank != 0 { checked += 1 }
                }
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }
}
