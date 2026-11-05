import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van de teksten van de werkuren (App/UI/WorkDisplay.swift, Foundation-only): uren, de zin bij een uitbetaling uit de agenda, de
/// periode, de toeslagen en pauzes, de melding bij de toegang tot de agenda en de uitleg bij een uitbetaling. De getallen komen uit de
/// rekenmotor; hier staat alleen of de woorden kloppen.
final class WorkDisplayTests: XCTestCase {
    private let cal = YearMonth.calendar
    private let oct = YearMonth(year: 2026, month: 10)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }
    private func shift(_ y: Int, _ m: Int, _ d: Int, from: Int, to: Int) -> WorkShift { engShift(engDate(cal, y, m, d, from), engDate(cal, y, m, d, to)) }

    private func octoberData() -> FinanceData {
        var d = FinanceData(startMonth: oct)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 15, hoursPerWeek: 24, payDay: 25)
        d.work.hoursSource = .calendar
        let shifts = [1, 2, 5, 6, 7, 8, 9, 12, 13, 14].map { shift(2026, 10, $0, from: 9, to: 17) } + [shift(2026, 10, 4, from: 10, to: 14)]
        d.work.snapshot = engSnapshot(shifts, fetched: day(2026, 10, 31))
        return d
    }

    // MARK: Uren

    func testHoursAreShownAsHoursWithAtMostTwoDecimals() {
        XCTAssertEqual(WorkText.hours(0), "0 uur")
        XCTAssertEqual(WorkText.hours(60), "1 uur")
        XCTAssertEqual(WorkText.hours(90), "1,5 uur")
        XCTAssertEqual(WorkText.hours(2_310), "38,5 uur")
        XCTAssertEqual(WorkText.hours(4_740), "79 uur")
        XCTAssertEqual(WorkText.hours(20), "0,33 uur")
        XCTAssertEqual(WorkText.hours(450), "7,5 uur")
        XCTAssertEqual(WorkText.hours(6_240), "104 uur")
        XCTAssertEqual(Fmt.hours(minutes: 61), "1,02 uur")
        XCTAssertEqual(Fmt.hours(minutes: 6), "0,1 uur")
        XCTAssertEqual(Fmt.hours(minutes: 3), "0,05 uur")
        XCTAssertEqual(Fmt.hours(minutes: 1), "0,02 uur")
        XCTAssertEqual(Fmt.hours(minutes: 600_000), "10000 uur", "geen duizendtallen")
        XCTAssertEqual(Fmt.hours(minutes: -90), "-1,5 uur")
        XCTAssertEqual(Fmt.hours(minutes: 59), "0,98 uur")
        XCTAssertEqual(Fmt.hours(minutes: 119), "1,98 uur")
    }

    func testHoursAgreeWithTheNumberFormatterOfTheOtherNumbers() {
        // `Fmt.hours` rekent zonder NumberFormatter en moet toch hetzelfde zeggen als `Fmt.input` (hoogstens twee decimalen, komma).
        for minutes in stride(from: 0, through: 3_000, by: 7) {
            XCTAssertEqual(Fmt.hours(minutes: minutes), "\(Fmt.input(Double(minutes) / 60)) uur", "\(minutes) minuten")
        }
    }

    func testThePayoutSentenceSaysWhereTheHoursCameFrom() {
        XCTAssertNil(WorkText.payoutDetail(nil))
        XCTAssertEqual(WorkText.payoutDetail(PayoutHours(paidMinutes: 2_310, expectedMinutes: 0)), "uit agenda: 38,5 uur")
        XCTAssertEqual(WorkText.payoutDetail(PayoutHours(paidMinutes: 2_310, expectedMinutes: 870)), "uit agenda: 24 uur, plus 14,5 uur uit je gemiddelde")
        XCTAssertEqual(WorkText.payoutDetail(PayoutHours(paidMinutes: 2_310, expectedMinutes: 2_310)), "verwacht uit je gemiddelde: 38,5 uur")
        XCTAssertEqual(WorkText.payoutDetail(PayoutHours(paidMinutes: 0, expectedMinutes: 0)), "uit agenda: 0 uur", "een maand zonder diensten")
        // De Core zegt hetzelfde (de salarisgebeurtenis bij Dag voor dag en Home).
        let hours = PayoutHours(paidMinutes: 2_310, expectedMinutes: 870)
        XCTAssertEqual(WorkText.payoutDetail(hours), hours.detailText)
    }

    func testPayoutHoursKeepsItsMinutesConsistent() {
        let hours = PayoutHours(paidMinutes: 100, expectedMinutes: 250)
        XCTAssertEqual(hours.expectedMinutes, 100, "nooit meer verwacht dan betaald")
        XCTAssertEqual(hours.agendaMinutes, 0)
        XCTAssertTrue(hours.isAllExpected)
        let negative = PayoutHours(paidMinutes: -5, expectedMinutes: -2)
        XCTAssertEqual(negative.paidMinutes, 0)
        XCTAssertEqual(negative.expectedMinutes, 0)
        XCTAssertFalse(negative.isAllExpected)
        XCTAssertEqual(PayoutHours(paidMinutes: 600, expectedMinutes: 100).agendaMinutes, 500)
    }

    // MARK: Perioden, toeslagen en pauzes

    func testAPeriodReadsLikeADateRange() {
        XCTAssertEqual(WorkText.periodText(day(2026, 10, 24).dayNumber...day(2026, 11, 20).dayNumber), "24 okt t/m 20 nov")
        XCTAssertEqual(WorkText.periodText(day(2026, 11, 1).dayNumber...day(2026, 11, 30).dayNumber), "1 nov t/m 30 nov")
        XCTAssertEqual(WorkText.periodText(day(2026, 12, 28).dayNumber...day(2027, 1, 24).dayNumber), "28 dec 2026 t/m 24 jan 2027", "over de jaargrens met het jaar")
        XCTAssertEqual(WorkText.periodText(day(2026, 3, 5).dayNumber...day(2026, 3, 5).dayNumber), "5 mrt t/m 5 mrt", "een periode van een dag")
    }

    func testFactorsReadAsMultiplications() {
        XCTAssertEqual(WorkText.factorText(1.5), "× 1,5")
        XCTAssertEqual(WorkText.factorText(2), "× 2")
        XCTAssertEqual(WorkText.factorText(1.25), "× 1,25")
        XCTAssertEqual(WorkText.factorText(0), "× 0")
        XCTAssertEqual(WorkText.factorText(.nan), "× 1", "geen onzin op het scherm")
        XCTAssertEqual(WorkText.factorText(hundredths: 150), "× 1,5")
        XCTAssertEqual(WorkText.factorText(hundredths: 100), "× 1")
        XCTAssertEqual(WorkText.factorText(hundredths: 250), "× 2,5")
    }

    func testRulesAndBreaksHaveTitlesLines() {
        XCTAssertEqual(WorkText.ruleTitle(PayRule(kind: .weekday(1), factor: 1.5)), "Zondag")
        XCTAssertEqual(WorkText.ruleTitle(PayRule(kind: .weekday(7), factor: 1.25)), "Zaterdag")
        XCTAssertEqual(WorkText.ruleTitle(PayRule(kind: .holiday, factor: 2)), "Feestdag")
        XCTAssertEqual(WorkText.ruleTitle(PayRule(kind: .date(day(2026, 12, 5)), factor: 1.25)), "5 december 2026")
        XCTAssertEqual(WorkText.ruleLine(PayRule(kind: .weekday(1), factor: 1.5)), "Zondag × 1,5")
        XCTAssertEqual(WorkText.ruleLine(PayRule(kind: .holiday, factor: 2)), "Feestdag × 2")
        XCTAssertEqual(WorkText.breakTitle(BreakRule(fromHours: 5.5, minutes: 30)), "Vanaf 5,5 uur: 30 min pauze")
        XCTAssertEqual(WorkText.breakTitle(BreakRule(fromHours: 10, minutes: 45)), "Vanaf 10 uur: 45 min pauze")
        XCTAssertEqual((1...7).map { WorkText.weekdayTitle($0) }, ["Zondag", "Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag"])
        XCTAssertEqual(WorkText.weekdayTitle(0), "Zondag", "geklemd")
        XCTAssertEqual(WorkText.weekdayTitle(9), "Zaterdag")
    }

    func testTheChoicesHaveTheirTitles() {
        XCTAssertEqual(HoursPeriodBasis.allCases.map { WorkText.periodBasisTitle($0) }, ["Deze periode", "De vorige periode"])
        XCTAssertEqual(PayCombine.allCases.map { WorkText.combineTitle($0) }, ["Hoogste telt", "Optellen"])
        XCTAssertEqual(HolidayKind.goodFriday.title, "Goede Vrijdag")
    }

    // MARK: Toegang tot de agenda

    func testAccessTextsNameTheProblemAndTheAction() {
        let notDetermined = WorkText.accessText(.notDetermined)
        XCTAssertEqual(notDetermined.title, "MyBuddy mag je agenda nog niet lezen")
        XCTAssertEqual(notDetermined.action, .requestAccess)
        XCTAssertEqual(notDetermined.action?.title, "Toegang geven")
        XCTAssertTrue(notDetermined.message.contains("Titels en notities worden niet gelezen"))
        for access in [CalendarAccess.denied, .restricted, .writeOnly] {
            let text = WorkText.accessText(access)
            XCTAssertEqual(text.action, .openSettings, "\(access)")
            XCTAssertEqual(text.action?.title, "Open Instellingen")
            XCTAssertTrue(text.needsAction)
            XCTAssertFalse(text.title.isEmpty)
            XCTAssertFalse(text.message.isEmpty)
        }
        XCTAssertEqual(WorkText.accessText(.writeOnly).title, "Zet de toegang op volledig")
        let granted = WorkText.accessText(.granted)
        XCTAssertFalse(granted.needsAction, "met toegang geen melding")
        XCTAssertNil(granted.action)
        XCTAssertEqual(Set([CalendarAccess.notDetermined, .denied, .restricted, .writeOnly].map { WorkText.accessText($0).title }).count, 4, "elke toestand zegt iets anders")
    }

    func testMatchedCalendarsAreNamedOrMissing() {
        XCTAssertEqual(WorkText.matchedText([], title: "werken"), "Geen agenda met de naam \u{201C}werken\u{201D} gevonden.")
        XCTAssertEqual(WorkText.matchedText([CalendarInfo(id: "1", title: "werken", sourceTitle: "iCloud")], title: "werken"), "Gevonden: 1 agenda (iCloud)")
        XCTAssertEqual(WorkText.matchedText([CalendarInfo(id: "1", title: "werken")], title: "werken"), "Gevonden: 1 agenda")
        let two = [CalendarInfo(id: "1", title: "werken"), CalendarInfo(id: "2", title: "Werken")]
        XCTAssertEqual(WorkText.matchedText(two, title: "werken"), "2 agenda's met deze naam: beide tellen mee")
        XCTAssertEqual(WorkText.matchedText(two + [CalendarInfo(id: "3", title: "WERKEN")], title: "werken"), "3 agenda's met deze naam: alle tellen mee")
    }

    func testWhatWasSkippedIsSaidInOneLine() {
        XCTAssertNil(WorkText.skippedText(CalendarFetch()))
        let fetch = CalendarFetch(skippedAllDay: 3, skippedDeclined: 2, skippedCanceled: 1, skippedTooLong: 1)
        XCTAssertEqual(WorkText.skippedText(fetch), "2 afgewezen, 1 geannuleerd, 3 hele dag, 1 langer dan 16 uur")
        XCTAssertEqual(WorkText.skippedText(CalendarFetch(skippedDeclined: 2)), "2 afgewezen")
        XCTAssertEqual(WorkText.shiftCountText(0), "geen diensten")
        XCTAssertEqual(WorkText.shiftCountText(1), "1 dienst")
        XCTAssertEqual(WorkText.shiftCountText(312), "312 diensten")
    }

    func testTheLastRefreshSaysWhenAndHowMany() {
        let shifts = (0..<312).map { index in WorkShift(startMinute: 30_000_000 + index * 600, endMinute: 30_000_000 + index * 600 + 480)! }
        let snapshot = engSnapshot(shifts, fetched: day(2026, 11, 4))
        let now = engDate(cal, 2026, 11, 4, 15)
        XCTAssertEqual(snapshot.shifts.count, 312)
        XCTAssertEqual(WorkText.lastRefreshText(nil, today: now), "Nog niet bijgewerkt")
        XCTAssertEqual(WorkText.lastRefreshText(snapshot, refreshedAt: engDate(cal, 2026, 11, 4, 14, 2), today: now), "Laatst bijgewerkt: vandaag 14:02, 312 diensten")
        XCTAssertEqual(WorkText.lastRefreshText(snapshot, refreshedAt: engDate(cal, 2026, 11, 4, 9, 5), today: now), "Laatst bijgewerkt: vandaag 09:05, 312 diensten")
        XCTAssertEqual(WorkText.lastRefreshText(snapshot, today: now), "Laatst bijgewerkt: vandaag, 312 diensten", "zonder bekend tijdstip alleen de dag")
        XCTAssertEqual(WorkText.lastRefreshText(snapshot, today: engDate(cal, 2026, 11, 5, 8)), "Laatst bijgewerkt: gisteren, 312 diensten")
        XCTAssertEqual(WorkText.lastRefreshText(snapshot, today: engDate(cal, 2026, 11, 20, 8)), "Laatst bijgewerkt: 4 november, 312 diensten")
        XCTAssertEqual(WorkText.lastRefreshText(snapshot, today: engDate(cal, 2027, 2, 3, 8)), "Laatst bijgewerkt: 4 november 2026, 312 diensten")
        // Een tijdstip van een andere dag dan de verversing wordt niet getoond.
        XCTAssertEqual(WorkText.lastRefreshText(snapshot, refreshedAt: engDate(cal, 2026, 11, 3, 14, 2), today: now), "Laatst bijgewerkt: vandaag, 312 diensten")
        XCTAssertEqual(WorkText.lastRefreshText(engSnapshot([], fetched: day(2026, 11, 4)), today: now), "Laatst bijgewerkt: vandaag, geen diensten")
    }

    func testTheSettingsRowSaysWhereTheHoursComeFrom() {
        var d = FinanceData(startMonth: oct)
        XCTAssertEqual(WorkText.settingsSummary(d), "Alleen bij een uurloon")
        d.salary.mode = .hourly
        XCTAssertEqual(WorkText.settingsSummary(d), "Uren per week invullen")
        d.work.hoursSource = .calendar
        XCTAssertEqual(WorkText.settingsSummary(d), "Uit je agenda \u{201C}werken\u{201D}")
        d.work.calendarTitle = "Rooster"
        XCTAssertEqual(WorkText.settingsSummary(d), "Uit je agenda \u{201C}Rooster\u{201D}")
        d.salary.mode = .fixed
        XCTAssertEqual(WorkText.settingsSummary(d), "Alleen bij een uurloon", "een vast salaris negeert de agenda")
    }

    // MARK: De uitleg bij een uitbetaling

    func testTheBreakdownOfAFullPeriodHasTheLinesInOrder() throws {
        let d = octoberData()
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 10, 25), asOf: engDate(cal, 2026, 10, 9, 12)))
        let lines = WorkText.breakdown(report, rules: d.work.rules)
        XCTAssertEqual(lines.map { $0.id }, ["hours", "worked", "planned", "factor-150", "break", "amount"])
        XCTAssertEqual(lines.map { $0.title }, ["Uren", "Gewerkt", "Gepland", "Toeslag × 1,5", "Pauze", "Bedrag"])
        XCTAssertEqual(lines[0].value, "79 uur")
        XCTAssertEqual(lines[1].value, WorkText.hours(report.workedMinutes))
        XCTAssertEqual(lines[2].value, WorkText.hours(report.plannedMinutes))
        XCTAssertEqual(lines[1].value + " + " + lines[2].value, "56,5 uur + 22,5 uur", "tot en met 9 oktober gewerkt (7 werkdagen en de zondag), daarna gepland (3 dagen)")
        XCTAssertEqual(lines[3].value, "4 uur")
        XCTAssertEqual(lines[3].note, "zondag", "welke toeslag het is")
        XCTAssertEqual(lines[4].value, "5 uur")
        XCTAssertEqual(lines[4].note, "onbetaald")
        XCTAssertEqual(lines[5].value, Fmt.euroExact(1_215))
        XCTAssertEqual(Set(lines.map { $0.id }).count, lines.count)
    }

    func testTheBreakdownOfAMixedAndAnExpectedPeriod() throws {
        var d = octoberData()
        d.work.snapshot = engSnapshot([shift(2026, 11, 2, from: 9, to: 17)], fetched: day(2026, 11, 15))
        let mixed = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25), asOf: engDate(cal, 2026, 11, 15, 12)))
        let lines = WorkText.breakdown(mixed, rules: d.work.rules)
        XCTAssertEqual(lines.map { $0.id }, ["hours", "worked", "expected", "break", "amount"])
        XCTAssertEqual(lines[0].value, "59,5 uur", "7,5 uur uit de agenda plus 52 uur uit je gemiddelde")
        XCTAssertEqual(lines[2].title, "Verwacht")
        XCTAssertEqual(lines[2].value, "52 uur")
        XCTAssertEqual(lines[2].note, "uit je gemiddelde")
        // Helemaal verwacht: alleen uren, verwacht en bedrag.
        d.work.snapshot = nil
        let expected = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(WorkText.breakdown(expected, rules: d.work.rules).map { $0.id }, ["hours", "expected", "amount"])
        XCTAssertEqual(WorkText.breakdown(expected, rules: d.work.rules).last?.value, Fmt.euroExact(Double(expected.amountCents) / 100))
        // Een maand zonder diensten in een ververste agenda: Uren 0 en een bedrag van 0.
        d.work.snapshot = engSnapshot([], fetched: day(2026, 11, 30))
        let none = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 11, 25)))
        XCTAssertEqual(WorkText.breakdown(none, rules: d.work.rules).map { $0.id }, ["hours", "amount"])
        XCTAssertEqual(WorkText.breakdown(none, rules: d.work.rules).first?.value, "0 uur")
    }

    func testTheBreakdownNamesTheRulesBehindEachFactor() throws {
        var d = octoberData()
        // Zondag en feestdag allebei 2,0: de factor 2,0 hoort bij beide toeslagen.
        d.work.rules.payRules[0].factor = 2
        let report = try XCTUnwrap(d.workReport(forPayoutOn: day(2026, 10, 25)))
        let factor = try XCTUnwrap(WorkText.breakdown(report, rules: d.work.rules).first { $0.id == "factor-200" })
        XCTAssertEqual(factor.title, "Toeslag × 2")
        XCTAssertEqual(factor.note, "zondag, feestdag")
        // Bij optellen kan een factor ontstaan die bij geen enkele toeslag hoort (1,0 + 0,5 + 1,0 = 2,5): dan geen naam.
        let line = WorkText.breakdown({
            var r = WorkHoursReport(period: 0...30)
            r.workedMinutes = 600
            r.byFactor = [WorkHoursReport.FactorMinutes(factor: 250, minutes: 600)]
            r.amountCents = 4_000
            return r
        }(), rules: WorkRules())
        XCTAssertEqual(line.first { $0.id == "factor-250" }?.title, "Toeslag × 2,5")
        XCTAssertNil(line.first { $0.id == "factor-250" }?.note)
        // Een uitgezette toeslag geeft zijn naam niet.
        var off = WorkRules()
        off.payRules[0].isEnabled = false
        let disabled = WorkText.breakdown({
            var r = WorkHoursReport(period: 0...30)
            r.workedMinutes = 600
            r.byFactor = [WorkHoursReport.FactorMinutes(factor: 150, minutes: 600)]
            return r
        }(), rules: off)
        XCTAssertNil(disabled.first { $0.id == "factor-150" }?.note)
    }

    func testTheNextHolidaysAreNamedWithTheirDates() {
        let settings = HolidaySettings()
        XCTAssertEqual(WorkText.nextHolidaysText(settings, from: day(2026, 12, 20)),
                       "De eerstvolgende feestdagen: Eerste Kerstdag (25 december), Tweede Kerstdag (26 december) en Nieuwjaarsdag (1 januari).")
        XCTAssertEqual(WorkText.nextHolidaysText(settings, from: day(2026, 12, 26), count: 1), "De eerstvolgende feestdagen: Tweede Kerstdag (26 december).",
                       "vandaag telt mee")
        XCTAssertEqual(WorkText.nextHolidaysText(settings, from: day(2026, 12, 27), count: 2),
                       "De eerstvolgende feestdagen: Nieuwjaarsdag (1 januari) en Eerste Paasdag (28 maart).",
                       "Goede Vrijdag (26 maart 2027) staat standaard uit, Pasen 2027 is 28 maart")
        var custom = HolidaySettings()
        custom.enabled = []
        XCTAssertNil(WorkText.nextHolidaysText(custom, from: day(2026, 12, 20)), "zonder feestdagen niets")
        custom.custom = [day(2026, 12, 31)]
        XCTAssertEqual(WorkText.nextHolidaysText(custom, from: day(2026, 12, 20)), "De eerstvolgende feestdagen: Eigen feestdag (31 december).")
        var optional = HolidaySettings()
        optional.enabled.insert(.newYearsEve)
        XCTAssertTrue(WorkText.nextHolidaysText(optional, from: day(2026, 12, 27), count: 1)?.contains("Oudejaarsdag") == true)
    }

    func testTheSectionTitlesOfThePageAreThere() {
        XCTAssertEqual([WorkText.rulesTitle, WorkText.breaksTitle, WorkText.holidaysTitle, WorkText.previewTitle, WorkText.managementTitle],
                       ["Toeslagen", "Pauzes", "Feestdagen", "Voorbeeld", "Beheer"])
        XCTAssertEqual(WorkText.upcomingTitle, "Uren van de volgende uitbetalingen")
        XCTAssertEqual(WorkText.manualHoursTitle, "Uren per week invullen")
        XCTAssertEqual([WorkText.addWeekdayTitle, WorkText.addHolidayRuleTitle, WorkText.addDateTitle], ["Weekdag", "Feestdag", "Eigen datum"])
        XCTAssertEqual([WorkText.factorTitle, WorkText.breakFromTitle, WorkText.breakMinutesTitle], ["Factor", "Vanaf", "Onbetaalde pauze"])
        XCTAssertTrue(WorkText.fixedSalaryNote.contains("uurloon"))
        XCTAssertTrue(WorkText.freezeMessage.hasSuffix("."))
    }

    func testTheFixedTextsFollowTheTermList() {
        XCTAssertEqual(WorkText.pageTitle, "Werkuren")
        XCTAssertEqual(WorkText.symbol, "clock")
        XCTAssertEqual(WorkText.sourceTitle, "Uren uit je agenda")
        XCTAssertEqual(WorkText.refreshTitle, "Nu verversen")
        XCTAssertEqual(WorkText.periodTitle, "Uren van")
        XCTAssertEqual(WorkText.fillAverageTitle, "Gemiddelde uit je agenda invullen")
        XCTAssertEqual(WorkText.freezeTitle, "Eerdere maanden vastleggen")
        XCTAssertEqual(WorkText.averageHoursTitle, "Gemiddeld aantal uren per week")
        XCTAssertEqual(WorkText.privacyFooter, "MyBuddy bewaart alleen begin en einde van je diensten, geen titels of notities.")
        XCTAssertEqual(WorkText.breakFooter, "De pauze is onbetaald en gaat van de dienst af.")
        XCTAssertEqual(WorkText.ownHoursNote, "Eigen uren rekenen uren × uurloon, zonder toeslagen.")
        XCTAssertTrue(WorkText.sourceFooter.contains("vanaf je startdatum"))
        let all = [WorkText.sourceFooter, WorkText.breakFooter, WorkText.holidaysFooter, WorkText.privacyFooter, WorkText.ownHoursNote,
                   WorkText.averageHoursNote, WorkText.formula, WorkText.nothingInCalendarNote, WorkText.sourceTitle, WorkText.allDayTitle]
        for text in all {
            XCTAssertFalse(text.lowercased().contains("meetpunt"), text)
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("  "), "geen dubbele spaties: \(text)")
        }
    }
}
