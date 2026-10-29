import XCTest
import Foundation
@testable import MyBuddyCore

/// De teksten van de startdatum (App/UI/StartDateText.swift, Foundation-only): zinnen met de goede datums en getallen, de termenlijst
/// ("ingevulde saldi", nooit "meetpunt") en geen hoofdletters of verboden woorden.
final class StartDateTextTests: XCTestCase {
    private func started(_ day: Int) -> FinanceData {
        var d = FinanceData(startMonth: oct2026)
        d.setStart(startOct(day))
        return d
    }

    // MARK: Datums

    func testLongDates() {
        XCTAssertEqual(Fmt.longDate(CalendarDay(year: 2026, month: 11, day: 3)), "3 november 2026")
        XCTAssertEqual(Fmt.longDate(CalendarDay(year: 2027, month: 1, day: 31)), "31 januari 2027")
        XCTAssertEqual(Fmt.longDate(CalendarDay(year: 2028, month: 2, day: 29)), "29 februari 2028")
        XCTAssertEqual(Fmt.longDayMonth(CalendarDay(year: 2026, month: 11, day: 3)), "3 november")
        XCTAssertEqual(Fmt.longDayMonth(CalendarDay(year: 2026, month: 12, day: 24)), "24 december")
    }

    // MARK: De pagina

    func testSummaryWithAndWithoutAStartDate() {
        XCTAssertEqual(StartDateText.summary(for: started(3)),
                       "Je begint op 3 oktober 2026. Wat daarvoor valt telt niet mee.")
        XCTAssertEqual(StartDateText.summary(for: FinanceData(startMonth: oct2026)),
                       "Je hebt geen startdatum ingesteld. Alles telt vanaf 1 oktober 2026, het begin van je startmaand.")
    }

    func testRowSubtitle() {
        XCTAssertEqual(StartDateText.rowSubtitle(for: started(15)), "15 oktober 2026")
        XCTAssertEqual(StartDateText.rowSubtitle(for: FinanceData(startMonth: oct2026)), "Niet ingesteld")
    }

    func testTheFixedTexts() {
        XCTAssertEqual(StartDateText.pageTitle, "Startdatum")
        XCTAssertEqual(StartDateText.explanation,
                       "Alles begint op deze dag. Wat je daarvoor invulde telt niet mee, ook al blijft het bewaard.")
        XCTAssertEqual(StartDateText.keepChoice, "Alleen de startdatum instellen")
        XCTAssertEqual(StartDateText.eraseChoice, "Alles wissen en opnieuw beginnen vanaf deze datum")
        XCTAssertEqual(StartDateText.actionTitle(erases: false), "Startdatum instellen")
        XCTAssertEqual(StartDateText.actionTitle(erases: true), "Wissen en opnieuw beginnen")
        XCTAssertEqual(StartDateText.openingFootnote, "Het saldo op deze dag, met alles wat die dag al gebeurd is.")
        XCTAssertNotEqual(StartDateText.choiceFootnote(erases: true), StartDateText.choiceFootnote(erases: false))
        XCTAssertTrue(StartDateText.choiceFootnote(erases: false).contains("blijven bewaard"))
        XCTAssertTrue(StartDateText.choiceFootnote(erases: true).contains("wist"))
    }

    func testWhatChangesLines() {
        let none = StartDateCounts()
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(StartDateText.countLines(none), [])
        let counts = StartDateCounts(bankEntries: 4, potEntries: 2, balances: 1, months: 3)
        XCTAssertFalse(counts.isEmpty)
        XCTAssertEqual(counts.entryTotal, 7)
        XCTAssertEqual(StartDateText.countLines(counts).map { $0.title },
                       ["Boekingen op je bankrekening", "Boekingen in spaarpotten", "Ingevulde saldi", "Maanden die niet meer meetellen"])
        XCTAssertEqual(StartDateText.countLines(counts).map { $0.count }, [4, 2, 1, 3])
        // Een regel zonder aantal staat er niet.
        let some = StartDateCounts(bankEntries: 0, potEntries: 2, balances: 0, months: 1)
        XCTAssertEqual(StartDateText.countLines(some).map { $0.count }, [2, 1])
        XCTAssertEqual(StartDateText.countLines(some).map { $0.id }, ["Boekingen in spaarpotten", "Maanden die niet meer meetellen"])
    }

    func testCountsFromTheData() {
        var d = FinanceData(startMonth: oct2026)
        d.addBankEntry(amount: 10, date: startMoment(oct2026, 3))
        d.addBankEntry(amount: 20, date: startMoment(oct2026, 20))
        d.addBankSnapshot(balance: 5, date: startMoment(oct2026, 4))
        let pot = Pot(name: "P", monthlyContribution: 0, startMonth: oct2026)
        d.pots = [pot]
        d.addPotEntry(potID: pot.id, amount: 7, kind: .deposit, date: startMoment(oct2026, 5))
        let counts = StartDateCounts(d, before: CalendarDay(year: 2026, month: 12, day: 3))
        XCTAssertEqual(counts, StartDateCounts(bankEntries: 2, potEntries: 1, balances: 1, months: 2))
        let mid = StartDateCounts(d, before: startOct(10))
        XCTAssertEqual(mid, StartDateCounts(bankEntries: 1, potEntries: 1, balances: 1, months: 0))
        XCTAssertEqual(StartDateCounts(d, before: startOct(1)), StartDateCounts())
    }

    func testWarning() {
        let day = CalendarDay(year: 2026, month: 11, day: 3)
        XCTAssertEqual(StartDateText.warning(StartDateCounts(), day: day),
                       "Er valt niets vóór 3 november 2026: er verandert niets aan wat meetelt.")
        let text = StartDateText.warning(StartDateCounts(bankEntries: 1, potEntries: 0, balances: 0, months: 0), day: day)
        XCTAssertTrue(text.contains("3 november 2026"))
        XCTAssertTrue(text.contains("blijft bewaard"))
        XCTAssertTrue(text.contains("eerdere startdatum"))
    }

    func testEraseMessageMentionsTheCloudOnlyWhenThereIsOne() {
        let day = CalendarDay(year: 2026, month: 11, day: 3)
        let local = StartDateText.eraseMessage(day: day, cloud: false)
        XCTAssertEqual(local, "Dit wist al je gegevens en je begint opnieuw op 3 november 2026. Het kan niet ongedaan worden gemaakt.")
        XCTAssertFalse(local.contains("cloud"))
        let cloud = StartDateText.eraseMessage(day: day, cloud: true)
        XCTAssertTrue(cloud.contains("cloud"))
        XCTAssertTrue(cloud.contains("andere apparaten"))
        XCTAssertTrue(cloud.contains("3 november 2026"))
        XCTAssertTrue(cloud.hasSuffix("Het kan niet ongedaan worden gemaakt."))
        XCTAssertEqual(StartDateText.eraseTitle(day: day), "Alles wissen en beginnen op 3 november 2026?")
    }

    func testOpeningBalanceTexts() {
        XCTAssertEqual(StartDateText.openingTitle(day: CalendarDay(year: 2026, month: 11, day: 3)), "Beginsaldo op 3 november 2026")
        XCTAssertEqual(StartDateText.startSaved(day: startOct(5)), "Startdatum ingesteld op 5 oktober 2026.")
        XCTAssertEqual(StartDateText.restarted(day: startOct(5)), "Alles is gewist. Je begint opnieuw op 5 oktober 2026.")
    }

    // MARK: Home

    func testWelcomeLine() {
        let today = startMoment(oct2026, 27)
        XCTAssertNil(StartDateText.welcomeLine(for: FinanceData(startMonth: oct2026), today: today))
        var d = FinanceData(startMonth: YearMonth(year: 2026, month: 11))
        d.setStart(CalendarDay(year: 2026, month: 11, day: 3))
        XCTAssertEqual(StartDateText.welcomeLine(for: d, today: today), "Je begint op 3 november.")
        var next = FinanceData(startMonth: YearMonth(year: 2027, month: 1))
        next.setStart(CalendarDay(year: 2027, month: 1, day: 4))
        XCTAssertEqual(StartDateText.welcomeLine(for: next, today: today), "Je begint op 4 januari 2027.")
    }

    // MARK: Maandpagina's

    func testBeforeStartNoteNamesTheStartDateOrTheStartMonth() {
        let plain = FinanceData(startMonth: oct2026)
        XCTAssertEqual(StartDateText.beforeStartNote(plain, .fillIn),
                       "Maanden vóór je startmaand (oktober 2026) tellen niet mee: daar vul je niets in.")
        XCTAssertEqual(StartDateText.beforeStartNote(plain, .distribute),
                       "Maanden vóór je startmaand (oktober 2026) tellen niet mee: daar verdeel je niets.")
        let d = started(15)
        XCTAssertEqual(StartDateText.beforeStartNote(d, .fillIn),
                       "Maanden vóór je startdatum (15 oktober 2026) tellen niet mee: daar vul je niets in.")
        XCTAssertEqual(StartDateText.beforeStartNote(d, .distribute),
                       "Maanden vóór je startdatum (15 oktober 2026) tellen niet mee: daar verdeel je niets.")
        XCTAssertEqual(StartDateText.beforeStartSalaryNote(plain), "Voor je startmaand telt er geen salaris mee")
        XCTAssertEqual(StartDateText.beforeStartSalaryNote(d), "Voor je startdatum telt er geen salaris mee")
        XCTAssertEqual(StartDateText.countsFromNote(plain), "Telt mee vanaf je startmaand (oktober 2026)")
        XCTAssertEqual(StartDateText.countsFromNote(d), "Telt mee vanaf 15 oktober 2026")
    }

    func testPartialMonthNoteOnlyInTheStartMonthAfterTheFirst() {
        let d = started(15)
        let note = StartDateText.partialMonthNote(d, month: oct2026)
        XCTAssertEqual(note, "Je begint op 15 oktober. In deze maand telt alleen mee wat op of na die dag valt; wat daarvoor valt zit al in je beginsaldo.")
        XCTAssertNil(StartDateText.partialMonthNote(d, month: oct2026.adding(1)))
        XCTAssertNil(StartDateText.partialMonthNote(d, month: oct2026.adding(-1)))
        XCTAssertNil(StartDateText.partialMonthNote(started(1), month: oct2026), "startdag 1 is een hele maand")
        XCTAssertNil(StartDateText.partialMonthNote(FinanceData(startMonth: oct2026), month: oct2026))
    }

    func testLineTexts() {
        XCTAssertEqual(StartDateText.lineBeforeStart, "Telt niet mee (vóór je startdatum)")
        XCTAssertEqual(StartDateText.transferBeforeStart(day: 5), "Telt niet mee: de overschrijfdag (de 5e) valt vóór je startdatum.")
        XCTAssertEqual(StartDateText.payoutsBeforeStart, "De uitbetalingen van deze maand vallen vóór je startdatum en tellen niet mee.")
    }

    // MARK: Lijsten met boekingen

    func testHiddenEntriesNote() {
        let day = startOct(15)
        XCTAssertNil(StartDateText.hiddenEntriesNote(count: 0, startDay: day))
        XCTAssertEqual(StartDateText.hiddenEntriesNote(count: 1, startDay: day),
                       "1 boeking van vóór je startdatum (15 oktober 2026) telt niet mee.")
        XCTAssertEqual(StartDateText.hiddenEntriesNote(count: 3, startDay: day),
                       "3 boekingen van vóór je startdatum (15 oktober 2026) tellen niet mee.")
    }

    func testHiddenNotesFromTheData() {
        var d = FinanceData(startMonth: oct2026)
        let pot = Pot(name: "P", monthlyContribution: 0, startMonth: oct2026)
        d.pots = [pot]
        d.addBankEntry(amount: 10, date: startMoment(oct2026, 3))
        d.addBankSnapshot(balance: 5, date: startMoment(oct2026, 4))
        d.addPotEntry(potID: pot.id, amount: 7, kind: .deposit, date: startMoment(oct2026, 5))
        XCTAssertNil(StartDateText.hiddenBankNote(d), "zonder startdatum is niets verborgen")
        XCTAssertNil(StartDateText.hiddenPotNote(d, potID: pot.id))
        XCTAssertNil(StartDateText.hiddenRecentNote(d))
        d.setStart(startOct(15))
        XCTAssertEqual(StartDateText.hiddenRecentNote(d), "3 boekingen van vóór je startdatum (15 oktober 2026) tellen niet mee.",
                       "bank (boeking en ingevuld saldo) en spaarpotten samen")
        XCTAssertEqual(StartDateText.hiddenBankNote(d), "2 boekingen van vóór je startdatum (15 oktober 2026) tellen niet mee.")
        XCTAssertEqual(StartDateText.hiddenPotNote(d, potID: pot.id), "1 boeking van vóór je startdatum (15 oktober 2026) telt niet mee.")
        XCTAssertEqual(StartDateText.hiddenPotNote(d, potID: nil), "1 boeking van vóór je startdatum (15 oktober 2026) telt niet mee.")
        XCTAssertNil(StartDateText.hiddenPotNote(d, potID: UUID()))
    }

    func testEntryBeforeStartWarning() {
        let d = started(15)
        let warning = StartDateText.entryBeforeStartWarning(d, at: startMoment(oct2026, 3))
        XCTAssertEqual(warning, "Je startdatum is 15 oktober 2026. Wat je nu invult valt daarvoor en telt niet mee.")
        XCTAssertNil(StartDateText.entryBeforeStartWarning(d, at: startMoment(oct2026, 15, hour: 0)), "het begin van de startdag telt")
        XCTAssertNil(StartDateText.entryBeforeStartWarning(d, at: startMoment(oct2026, 20)))
        XCTAssertNil(StartDateText.entryBeforeStartWarning(FinanceData(startMonth: oct2026), at: startMoment(oct2026, 3)))
    }

    // MARK: Datumkiezer

    func testPickerRange() {
        let range = StartDateText.pickerRange(today: startMoment(oct2026, 27))
        let cal = YearMonth.calendar
        XCTAssertEqual(CalendarDay(date: range.lowerBound, calendar: cal), CalendarDay(year: 2000, month: 1, day: 1))
        XCTAssertEqual(CalendarDay(date: range.upperBound, calendar: cal), CalendarDay(year: 2027, month: 10, day: 27))
        XCTAssertTrue(range.contains(startMoment(oct2026, 1)))
    }

    // MARK: Termenlijst

    func testNoForbiddenTermsAndNoShoutingText() {
        var texts: [String] = [
            StartDateText.pageTitle, StartDateText.explanation, StartDateText.pickerTitle, StartDateText.keepChoice,
            StartDateText.eraseChoice, StartDateText.choiceFootnote(erases: true), StartDateText.choiceFootnote(erases: false),
            StartDateText.actionTitle(erases: true), StartDateText.actionTitle(erases: false), StartDateText.sameDayNote,
            StartDateText.eraseTitle(day: startOct(1)), StartDateText.eraseMessage(day: startOct(1), cloud: true),
            StartDateText.eraseMessage(day: startOct(1), cloud: false), StartDateText.eraseConfirm,
            StartDateText.openingTitle(day: startOct(1)), StartDateText.openingFootnote, StartDateText.openingSave,
            StartDateText.bankRowTitle, StartDateText.openingSaved, StartDateText.startSaved(day: startOct(1)),
            StartDateText.restarted(day: startOct(1)), StartDateText.lineBeforeStart, StartDateText.transferBeforeStart(day: 3),
            StartDateText.payoutsBeforeStart, StartDateText.summary(for: started(3)),
            StartDateText.summary(for: FinanceData(startMonth: oct2026)),
            StartDateText.beforeStartNote(started(3), .fillIn), StartDateText.beforeStartNote(started(3), .distribute),
            StartDateText.beforeStartSalaryNote(started(3)), StartDateText.countsFromNote(started(3)),
            StartDateText.warning(StartDateCounts(), day: startOct(3)),
            StartDateText.warning(StartDateCounts(bankEntries: 2, potEntries: 0, balances: 0, months: 0), day: startOct(3))
        ]
        texts.append(contentsOf: StartDateText.countLines(StartDateCounts(bankEntries: 1, potEntries: 1, balances: 1, months: 1)).map { $0.title })
        texts.append(StartDateText.partialMonthNote(started(3), month: oct2026) ?? "")
        texts.append(StartDateText.hiddenEntriesNote(count: 2, startDay: startOct(3)) ?? "")
        for text in texts {
            XCTAssertFalse(text.isEmpty)
            let lowered = text.lowercased()
            XCTAssertFalse(lowered.contains("meetpunt"), "'meetpunt' is verboden (termenlijst): \(text)")
            XCTAssertFalse(lowered.contains("firebase"), text)
            XCTAssertNotEqual(text, text.uppercased(), "geen HOOFDLETTERS: \(text)")
            XCTAssertEqual(text, text.trimmingCharacters(in: .whitespacesAndNewlines), "geen spaties aan de rand: '\(text)'")
            XCTAssertFalse(text.contains("  "), "geen dubbele spaties: '\(text)'")
        }
    }
}
