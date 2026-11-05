import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van de logica van de pagina "Loon wijzigen" (`WageEdit` in App/UI/WageText.swift, zonder SwiftUI): waarmee het formulier begint,
/// welke velden een wijziging bewaart, wat een uitbetaling ervan verandert en welke maanden de kiezer aanbiedt.
final class WageEditTests: XCTestCase {
    private let sep = YearMonth(year: 2026, month: 9)
    private let oct = YearMonth(year: 2026, month: 10)
    private let nov = YearMonth(year: 2026, month: 11)
    private let dec = YearMonth(year: 2026, month: 12)

    private func hourlyData() -> FinanceData {
        var d = FinanceData(startMonth: sep)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 14.35, hoursPerWeek: 32, payDay: 25)
        return d
    }

    func testTheFormStartsAtTheWageThatHoldsInThatMonth() {
        var d = hourlyData()
        XCTAssertEqual(WageEdit.start(d, month: nov), d.salary)
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 16, hoursPerWeek: 28))
        XCTAssertEqual(WageEdit.start(d, month: oct).hourlyRate, 14.35)
        XCTAssertEqual(WageEdit.start(d, month: nov).hourlyRate, 16)
        XCTAssertEqual(WageEdit.start(d, month: dec).hoursPerWeek, 28, "de wijziging geldt ook in de maanden erna")
        XCTAssertEqual(WageEdit.start(d, month: nov), d.salarySettings(in: nov))
    }

    func testAFieldThatEqualsTheWageBeforeStaysNil() {
        let d = hourlyData()
        let unchanged = WageEdit.change(d, month: nov, hourlyRate: 14.35, fixedMonthly: 0, hoursPerWeek: 32)
        XCTAssertTrue(unchanged.isEmpty, "niets wijkt af van het loon van de maand ervoor")
        XCTAssertEqual(unchanged.from, nov)
        let raised = WageEdit.change(d, month: nov, hourlyRate: 15.2, fixedMonthly: 0, hoursPerWeek: 32)
        XCTAssertEqual(raised, SalaryChange(from: nov, hourlyRate: 15.2), "alleen het uurloon wijkt af")
        let both = WageEdit.change(d, month: nov, hourlyRate: 15.2, fixedMonthly: 2_500, hoursPerWeek: 28)
        XCTAssertEqual(both, SalaryChange(from: nov, hourlyRate: 15.2, fixedMonthly: 2_500, hoursPerWeek: 28))
    }

    func testTheComparisonIsOnCentsAndOnThousandthsOfAnHour() {
        let d = hourlyData()
        XCTAssertNil(WageEdit.change(d, month: nov, hourlyRate: 14.351, fixedMonthly: 0, hoursPerWeek: 32.0004).hourlyRate, "minder dan een cent")
        XCTAssertNil(WageEdit.change(d, month: nov, hourlyRate: 14.351, fixedMonthly: 0, hoursPerWeek: 32.0004).hoursPerWeek, "minder dan 0,001 uur")
        XCTAssertEqual(WageEdit.change(d, month: nov, hourlyRate: 14.36, fixedMonthly: 0, hoursPerWeek: 32).hourlyRate, 14.36, "een cent erbij is een verschil")
        XCTAssertEqual(WageEdit.change(d, month: nov, hourlyRate: 14.35, fixedMonthly: 0, hoursPerWeek: 32.5).hoursPerWeek, 32.5)
        XCTAssertEqual(WageEdit.change(d, month: nov, hourlyRate: 14.35, fixedMonthly: 0, hoursPerWeek: 31.999).hoursPerWeek, 31.999)
    }

    func testTheWageBeforeIncludesEarlierChangesButNotTheChangeOfThatMonth() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: oct, hourlyRate: 16))
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 18))
        // Je bewerkt november: 16 (van oktober) is het loon ervoor, niet 18 (de wijziging zelf).
        XCTAssertTrue(WageEdit.change(d, month: nov, hourlyRate: 16, fixedMonthly: 0, hoursPerWeek: 32).isEmpty, "terug naar het loon van oktober: lege wijziging")
        XCTAssertEqual(WageEdit.change(d, month: nov, hourlyRate: 18, fixedMonthly: 0, hoursPerWeek: 32).hourlyRate, 18)
        XCTAssertEqual(WageEdit.change(d, month: dec, hourlyRate: 18, fixedMonthly: 0, hoursPerWeek: 32).hourlyRate, nil, "december volgt november")
        // Een lege wijziging bewaren haalt de bestaande wijziging van die maand weg.
        d.setSalaryChange(WageEdit.change(d, month: nov, hourlyRate: 16, fixedMonthly: 0, hoursPerWeek: 32))
        XCTAssertEqual(d.salaryChanges.map { $0.from }, [oct])
    }

    func testThePayoutPreviewComparesBeforeAndAfter() {
        let d = hourlyData()
        let change = SalaryChange(from: nov, hourlyRate: 16)
        let preview = WageEdit.payoutPreview(d, month: nov, change: change)
        XCTAssertEqual(preview.old, d.salary.payoutAmount())
        XCTAssertEqual(preview.new, SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 16, hoursPerWeek: 32, payDay: 25).payoutAmount())
        XCTAssertGreaterThan(preview.new, preview.old)
        // Alleen de uren veranderen.
        let hours = WageEdit.payoutPreview(d, month: nov, change: SalaryChange(from: nov, hoursPerWeek: 16))
        XCTAssertEqual(hours.new, (14.35 * 16 * 52 / 12).cents)
        // Een vast bedrag per uitbetaling.
        var fixed = FinanceData(startMonth: sep)
        fixed.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 36, payDay: 25)
        let raised = WageEdit.payoutPreview(fixed, month: nov, change: SalaryChange(from: nov, fixedMonthly: 3_200))
        XCTAssertEqual(raised.old, 3_000)
        XCTAssertEqual(raised.new, 3_200)
        // Een lege wijziging verandert niets.
        let none = WageEdit.payoutPreview(d, month: nov, change: SalaryChange(from: nov))
        XCTAssertEqual(none.old, none.new)
        XCTAssertNil(WageText.effectNote(old: none.old, new: none.new, isMonthly: true))
    }

    func testThePreviewComparesWithTheMonthBeforeEvenWhenTheMonthHasAChange() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 20))
        // Je bewerkt de wijziging van november naar 22: oud is het loon van oktober (14,35), niet het huidige van november.
        let preview = WageEdit.payoutPreview(d, month: nov, change: SalaryChange(from: nov, hourlyRate: 22))
        XCTAssertEqual(preview.old, d.salarySettings(in: oct).payoutAmount())
        XCTAssertEqual(preview.new, SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 22, hoursPerWeek: 32, payDay: 25).payoutAmount())
    }

    func testTheMonthChoicesRunFromTheCurrentMonthForTwoYears() {
        let d = hourlyData()
        let choices = WageEdit.monthChoices(d, current: nov)
        XCTAssertEqual(choices.count, 25)
        XCTAssertEqual(choices.first, nov)
        XCTAssertEqual(choices.last, nov.adding(24), "24 maanden vooruit")
        XCTAssertEqual(choices, choices.sorted())
        XCTAssertEqual(Set(choices).count, choices.count)
    }

    func testTheMonthChoicesAlsoOfferTheMonthOfAnExistingChangeOutsideTheRange() {
        var d = hourlyData()
        d.setSalaryChange(SalaryChange(from: sep, hourlyRate: 16))   // in het verleden
        d.setSalaryChange(SalaryChange(from: nov.adding(30), hourlyRate: 17))   // ver in de toekomst
        d.setSalaryChange(SalaryChange(from: dec, hourlyRate: 18))   // binnen het bereik
        let choices = WageEdit.monthChoices(d, current: nov)
        XCTAssertEqual(choices.count, 27, "25 maanden plus de twee wijzigingen daarbuiten")
        XCTAssertTrue(choices.contains(sep))
        XCTAssertTrue(choices.contains(nov.adding(30)))
        XCTAssertEqual(choices.filter { $0 == dec }.count, 1, "geen dubbelen")
        XCTAssertEqual(choices, choices.sorted())
        // De maand die je opent staat er ook in.
        let extra = WageEdit.monthChoices(hourlyData(), current: nov, including: nov.adding(-4))
        XCTAssertEqual(extra.first, nov.adding(-4))
        XCTAssertEqual(extra.count, 26)
    }

    func testSavingAndRemovingThroughTheEditLogicGivesTheExpectedWage() {
        var d = hourlyData()
        d.setSalaryChange(WageEdit.change(d, month: nov, hourlyRate: 15.2, fixedMonthly: 0, hoursPerWeek: 32))
        XCTAssertEqual(d.salaryChanges, [SalaryChange(from: nov, hourlyRate: 15.2)])
        XCTAssertEqual(d.salaryAmount(in: nov), SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 15.2, hoursPerWeek: 32, payDay: 25).payoutAmount())
        // Een tweede wijziging in december: het formulier begint bij het loon van november.
        let start = WageEdit.start(d, month: dec)
        XCTAssertEqual(start.hourlyRate, 15.2)
        d.setSalaryChange(WageEdit.change(d, month: dec, hourlyRate: start.hourlyRate, fixedMonthly: 0, hoursPerWeek: 30))
        XCTAssertEqual(d.salaryChange(startingIn: dec), SalaryChange(from: dec, hoursPerWeek: 30), "het uurloon volgt dat van november")
        d.setSalaryChange(SalaryChange(from: nov, hourlyRate: 17))
        XCTAssertEqual(d.salarySettings(in: dec).hourlyRate, 17, "december volgt de gewijzigde november")
        d.removeSalaryChange(from: nov)
        XCTAssertEqual(d.salarySettings(in: dec).hourlyRate, 14.35)
        XCTAssertEqual(d.salarySettings(in: dec).hoursPerWeek, 30)
    }
}
