import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van de teksten van het loon per maand (App/UI/WageText.swift): de kaart "Loon per maand" op Salaris en de pagina "Loon wijzigen".
/// De bedragen komen uit de rekenmotor; hier staat of de woorden en de opmaak kloppen.
final class WageTextTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)
    private let dec = YearMonth(year: 2026, month: 12)

    func testTheTitlesFollowTheTermList() {
        XCTAssertEqual(WageText.sectionTitle, "Loon per maand")
        XCTAssertEqual(WageText.pageTitle, "Loon wijzigen")
        XCTAssertEqual(WageText.addTitle, "Loon wijzigen vanaf een maand")
        XCTAssertEqual(WageText.nowBadge, "Nu")
        for text in [WageText.footer, WageText.emptyHint, WageText.pastMonthWarning, WageText.currentMonthNote, WageText.calendarNote] {
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.lowercased().contains("meetpunt"))
            XCTAssertFalse(text.contains("  "), text)
            XCTAssertTrue(text.hasSuffix("."), text)
        }
        XCTAssertTrue(WageText.footer.contains("op je rekening komt"), "welk loon voor welke uitbetaling geldt")
        XCTAssertTrue(WageText.footer.contains("Eerdere maanden blijven zoals ze waren"))
        XCTAssertTrue(WageText.currentMonthNote.contains("Loon per maand"))
        XCTAssertTrue(WageText.pastMonthWarning.contains("eigen salaris"))
    }

    func testTheFromTitleNamesTheMonth() {
        XCTAssertEqual(WageText.fromTitle(nov), "Vanaf november 2026")
        XCTAssertEqual(WageText.fromTitle(YearMonth(year: 2027, month: 3)), "Vanaf maart 2027")
    }

    func testTheValueOfAnHourlyChangeNamesTheHourlyRateAndTheHours() {
        let change = SalaryChange(from: nov, hourlyRate: 15.2, hoursPerWeek: 32)
        XCTAssertEqual(WageText.valueText(change, mode: .hourly, isMonthly: true), "\(Fmt.euroExact(15.2)) per uur · 32 uur per week")
        XCTAssertEqual(WageText.valueText(SalaryChange(from: nov, hourlyRate: 15.2), mode: .hourly, isMonthly: true), "\(Fmt.euroExact(15.2)) per uur")
        XCTAssertEqual(WageText.valueText(SalaryChange(from: nov, hoursPerWeek: 28.5), mode: .hourly, isMonthly: false), "28,5 uur per week")
        // Een vast bedrag bij een uurloon of andersom telt niet mee in de tekst.
        XCTAssertEqual(WageText.valueText(SalaryChange(from: nov, hourlyRate: 15.2, fixedMonthly: 3_000), mode: .hourly, isMonthly: true), "\(Fmt.euroExact(15.2)) per uur")
    }

    func testTheValueOfAFixedChangeIsPerMonthOrPerPayout() {
        let change = SalaryChange(from: nov, fixedMonthly: 3_200, hoursPerWeek: 36)
        XCTAssertEqual(WageText.valueText(change, mode: .fixed, isMonthly: true), "\(Fmt.euro(3_200)) per maand · 36 uur per week")
        XCTAssertEqual(WageText.valueText(SalaryChange(from: nov, fixedMonthly: 800), mode: .fixed, isMonthly: false), "\(Fmt.euro(800)) per uitbetaling")
        XCTAssertEqual(WageText.valueText(SalaryChange(from: nov), mode: .fixed, isMonthly: true), "Geen verandering")
        XCTAssertEqual(WageText.valueText(SalaryChange(from: nov, hourlyRate: 15), mode: .fixed, isMonthly: true), "Geen verandering", "het uurloon doet er bij een vast bedrag niet toe")
    }

    func testARowReadsFromAMonthWithItsValue() {
        let change = SalaryChange(from: nov, hourlyRate: 15.2)
        XCTAssertEqual(WageText.rowLine(change, mode: .hourly, isMonthly: true), "Vanaf november 2026: \(Fmt.euroExact(15.2)) per uur")
        XCTAssertEqual(WageText.accessibilityLine(change, mode: .hourly, isMonthly: true, isCurrent: true),
                       "Vanaf november 2026: \(Fmt.euroExact(15.2)) per uur, geldt nu")
        XCTAssertEqual(WageText.accessibilityLine(change, mode: .hourly, isMonthly: true, isCurrent: false),
                       WageText.rowLine(change, mode: .hourly, isMonthly: true))
    }

    func testTheBaseLineSaysWhatHeldUntilTheFirstChange() {
        let hourly = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 14.35, hoursPerWeek: 32, payDay: 25)
        XCTAssertEqual(WageText.baseLine(settings: hourly, until: nov), "Tot november 2026: \(Fmt.euroExact(14.35)) per uur · 32 uur per week")
        let fixed = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        XCTAssertEqual(WageText.baseLine(settings: fixed, until: dec), "Tot december 2026: \(Fmt.euro(3_000)) per maand")
        var perPayout = fixed
        perPayout.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 9, day: 11))
        perPayout.hoursPerWeek = 36
        XCTAssertEqual(WageText.baseLine(settings: perPayout, until: dec), "Tot december 2026: \(Fmt.euro(3_000)) per uitbetaling · 36 uur per week")
    }

    func testTheEffectNoteSaysWhatAPayoutDoes() {
        XCTAssertEqual(WageText.effectNote(old: 1_990, new: 2_108, isMonthly: true), "Een uitbetaling gaat van \(Fmt.euro(1_990)) naar \(Fmt.euro(2_108)) per maand.")
        XCTAssertEqual(WageText.effectNote(old: 600, new: 650, isMonthly: false), "Een uitbetaling gaat van \(Fmt.euro(600)) naar \(Fmt.euro(650)).")
        XCTAssertNil(WageText.effectNote(old: 1_990, new: 1_990, isMonthly: true), "niets verandert")
        XCTAssertNil(WageText.effectNote(old: 1_990.001, new: 1_990.004, isMonthly: true), "minder dan een cent verschil is geen verschil")
        XCTAssertNotNil(WageText.effectNote(old: 1_990, new: 1_990.01, isMonthly: true))
    }

    func testTheDeleteMessageSaysWhichWageReturns() {
        XCTAssertEqual(WageText.deleteMessage(month: nov), "Vanaf november 2026 geldt weer het loon van daarvoor.")
    }
}
