import XCTest
@testable import MyBuddyCore

/// Controle van de logica achter het scherm "Regels" (SavingsPages.swift): bewaren, verwijderen en de teksten.
final class LineSaveTests: XCTestCase {
    private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

    private func baseData() -> FinanceData {
        var d = FinanceData(startMonth: ym(2026, 8))
        d.salary.fixedMonthly = 3000
        d.salary.payDay = 25
        d.materialize(upTo: ym(2026, 10))
        return d
    }

    private func lines(_ d: FinanceData, _ month: YearMonth, kind: FinanceData.LineKind = .expense) -> [MoneyLine] {
        let plan = d.plan(for: month)
        return kind == .income ? plan.extraIncome : plan.expenses
    }

    // MARK: Nieuwe terugkerende regel

    func testNewRecurringLineShowsInLaterStoredAndFarFutureMonths() {
        var d = baseData()
        // Een latere maand is al opgeslagen en bewerkt: dit was de oorspronkelijke fout.
        d.editPlan(ym(2026, 12)) { $0.salaryOverride = 3100 }
        d.editPlan(ym(2027, 2)) { $0.transferDay = 5 }
        let rent = MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 3)
        LineSave.apply(&d, edited: rent, isNew: true, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        for (y, m) in [(2026, 10), (2026, 11), (2026, 12), (2027, 1), (2027, 2), (2030, 6)] {
            let found = lines(d, ym(y, m)).filter { $0.name == "Huur" }
            XCTAssertEqual(found.count, 1, "maand \(y)-\(m)")
            XCTAssertEqual(found.first?.amount, 900)
            XCTAssertEqual(found.first?.day, 3)
        }
        // Niet vóór de maand waarin hij begint.
        XCTAssertTrue(lines(d, ym(2026, 9)).filter { $0.name == "Huur" }.isEmpty)
    }

    func testNewOneOffLineStaysInOneMonth() {
        var d = baseData()
        let once = MoneyLine(name: "Fiets", amount: 400, isRecurring: false, kind: .variable, day: 12)
        LineSave.apply(&d, edited: once, isNew: true, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        XCTAssertEqual(lines(d, ym(2026, 10)).filter { $0.name == "Fiets" }.count, 1)
        XCTAssertTrue(lines(d, ym(2026, 11)).filter { $0.name == "Fiets" }.isEmpty)
    }

    // MARK: Bewerken met reikwijdte

    func testEditThisMonthOnlyKeepsSeriesUnchanged() throws {
        var d = baseData()
        let rent = MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 3)
        LineSave.apply(&d, edited: rent, isNew: true, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        var edited = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" })
        edited.amount = 950
        XCTAssertTrue(LineSave.needsScopeQuestion(existing: try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" }), edited: edited))
        LineSave.apply(&d, edited: edited, isNew: false, kind: .expense, month: ym(2026, 10), scope: .thisMonth)
        XCTAssertEqual(lines(d, ym(2026, 10)).first { $0.name == "Huur" }?.amount, 950)
        XCTAssertEqual(lines(d, ym(2026, 11)).first { $0.name == "Huur" }?.amount, 900)
        XCTAssertEqual(lines(d, ym(2027, 3)).first { $0.name == "Huur" }?.amount, 900)
        // De afwijkende maand krijgt een waarschuwing, de maand erna een gewone melding.
        let line = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" })
        let info = d.seriesInfo(of: line, in: ym(2026, 10))
        XCTAssertEqual(info?.isException, true)
        let note = RecurringText.rowNote(info: info, month: ym(2026, 10), current: ym(2026, 10))
        XCTAssertEqual(note?.isWarning, true)
    }

    func testEditThisAndFollowingChangesLaterMonths() throws {
        var d = baseData()
        let rent = MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 3)
        LineSave.apply(&d, edited: rent, isNew: true, kind: .expense, month: ym(2026, 9), scope: .thisAndFollowing)
        d.materialize(upTo: ym(2026, 10))
        var edited = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" })
        edited.amount = 975
        edited.day = 5
        LineSave.apply(&d, edited: edited, isNew: false, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        // Eerdere maand blijft, deze en alle volgende veranderen.
        XCTAssertEqual(lines(d, ym(2026, 9)).first { $0.name == "Huur" }?.amount, 900)
        for (y, m) in [(2026, 10), (2026, 11), (2027, 5)] {
            let l = lines(d, ym(y, m)).first { $0.name == "Huur" }
            XCTAssertEqual(l?.amount, 975, "maand \(y)-\(m)")
            XCTAssertEqual(l?.day, 5, "maand \(y)-\(m)")
        }
    }

    func testUnchangedRecurringLineNeedsNoQuestion() throws {
        var d = baseData()
        let rent = MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 3)
        LineSave.apply(&d, edited: rent, isNew: true, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        let existing = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" })
        XCTAssertFalse(LineSave.needsScopeQuestion(existing: existing, edited: existing))
        XCTAssertFalse(LineSave.needsScopeQuestion(existing: nil, edited: existing))
        var oneOff = existing
        oneOff.isRecurring = false
        // Terugkerend uitzetten is wel een vraag (alleen deze maand of stoppen).
        XCTAssertTrue(LineSave.needsScopeQuestion(existing: existing, edited: oneOff))
        let plain = MoneyLine(name: "Los", amount: 10)
        var changed = plain
        changed.amount = 20
        XCTAssertFalse(LineSave.needsScopeQuestion(existing: plain, edited: changed))
    }

    func testTurnRecurringOffWithScopes() throws {
        for scope in SeriesScope.allCases {
            var d = baseData()
            let rent = MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 3)
            LineSave.apply(&d, edited: rent, isNew: true, kind: .expense, month: ym(2026, 9), scope: .thisAndFollowing)
            d.materialize(upTo: ym(2026, 10))
            var edited = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" })
            edited.isRecurring = false
            LineSave.apply(&d, edited: edited, isNew: false, kind: .expense, month: ym(2026, 10), scope: scope)
            // Deze maand staat de regel er nog (eenmalig).
            XCTAssertEqual(lines(d, ym(2026, 10)).filter { $0.name == "Huur" }.count, 1, "\(scope)")
            let next = lines(d, ym(2026, 11)).filter { $0.name == "Huur" }
            switch scope {
            case .thisMonth: XCTAssertEqual(next.count, 1, "alleen deze maand: de reeks loopt door")
            case .thisAndFollowing: XCTAssertEqual(next.count, 0, "stoppen: niet meer terug")
            }
            // Vorige maand blijft staan.
            XCTAssertEqual(lines(d, ym(2026, 9)).filter { $0.name == "Huur" }.count, 1)
        }
    }

    // MARK: Verwijderen

    func testRemoveSkipVersusStop() throws {
        for scope in SeriesScope.allCases {
            var d = baseData()
            let sub = MoneyLine(name: "Sportschool", amount: 30, isRecurring: true, kind: .fixed, day: 28)
            LineSave.apply(&d, edited: sub, isNew: true, kind: .expense, month: ym(2026, 9), scope: .thisAndFollowing)
            d.materialize(upTo: ym(2026, 10))
            let target = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Sportschool" })
            d.removeLine(id: target.id, kind: .expense, in: ym(2026, 10), scope: scope)
            XCTAssertTrue(lines(d, ym(2026, 10)).filter { $0.name == "Sportschool" }.isEmpty, "\(scope)")
            XCTAssertEqual(lines(d, ym(2026, 9)).filter { $0.name == "Sportschool" }.count, 1)
            let later = lines(d, ym(2027, 1)).filter { $0.name == "Sportschool" }
            switch scope {
            case .thisMonth: XCTAssertEqual(later.count, 1, "overslaan: later weer terug")
            case .thisAndFollowing: XCTAssertEqual(later.count, 0, "stoppen: nooit meer terug")
            }
        }
    }

    // MARK: Een reeks die in deze maand ontbreekt

    func testReAddingSkippedSeriesDoesNotDuplicateAndAppliesTypedValues() throws {
        var d = baseData()
        let rent = MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 3)
        LineSave.apply(&d, edited: rent, isNew: true, kind: .expense, month: ym(2026, 9), scope: .thisAndFollowing)
        d.materialize(upTo: ym(2026, 10))
        let target = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" })
        d.removeLine(id: target.id, kind: .expense, in: ym(2026, 10), scope: .thisMonth)
        XCTAssertNotNil(d.resumableSeries(named: "huur", kind: .expense, in: ym(2026, 10)))
        // Opnieuw toevoegen met een ander bedrag: de reeks gaat door, er komt geen tweede naast.
        let again = MoneyLine(name: "huur", amount: 950, isRecurring: true, kind: .fixed, day: 3)
        LineSave.apply(&d, edited: again, isNew: true, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        for (y, m) in [(2026, 10), (2026, 11), (2027, 4)] {
            let found = lines(d, ym(y, m)).filter { $0.name.lowercased() == "huur" }
            XCTAssertEqual(found.count, 1, "maand \(y)-\(m)")
            XCTAssertEqual(found.first?.amount, 950, "maand \(y)-\(m)")
        }
    }

    // MARK: Aantekeningen in de lijst

    func testRowNoteForFutureMonthAndEndedSeries() throws {
        var d = baseData()
        let rent = MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 3)
        LineSave.apply(&d, edited: rent, isNew: true, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        // Toekomstige maand: komt vanzelf.
        let future = try XCTUnwrap(lines(d, ym(2026, 12)).first { $0.name == "Huur" })
        let futureInfo = d.seriesInfo(of: future, in: ym(2026, 12))
        XCTAssertNotNil(futureInfo)
        XCTAssertEqual(RecurringText.rowNote(info: futureInfo, month: ym(2026, 12), current: ym(2026, 10))?.text,
                       "Staat er vanzelf: komt elke maand terug")
        // De eerste maand zelf krijgt geen aantekening.
        let first = try XCTUnwrap(lines(d, ym(2026, 10)).first { $0.name == "Huur" })
        XCTAssertNil(RecurringText.rowNote(info: d.seriesInfo(of: first, in: ym(2026, 10)), month: ym(2026, 10), current: ym(2026, 10)))
        // Gestopt vanaf januari: tot en met december.
        let jan = try XCTUnwrap(lines(d, ym(2027, 1)).first { $0.name == "Huur" })
        d.removeLine(id: jan.id, kind: .expense, in: ym(2027, 1), scope: .thisAndFollowing)
        let dec = try XCTUnwrap(lines(d, ym(2026, 12)).first { $0.name == "Huur" })
        let endedInfo = d.seriesInfo(of: dec, in: ym(2026, 12))
        XCTAssertEqual(endedInfo?.lastMonth, ym(2026, 12))
        XCTAssertEqual(RecurringText.rowNote(info: endedInfo, month: ym(2026, 12), current: ym(2026, 10))?.text,
                       "Laatste keer: daarna stopt deze regel")
        let nov = try XCTUnwrap(lines(d, ym(2026, 11)).first { $0.name == "Huur" })
        XCTAssertEqual(RecurringText.rowNote(info: d.seriesInfo(of: nov, in: ym(2026, 11)), month: ym(2026, 11), current: ym(2026, 10))?.text,
                       "Loopt tot en met december 2026")
    }

    func testTextsMentionDayAndMonths() {
        XCTAssertEqual(RecurringText.dayPhrase(day: 25, defaultPhrase: "x"), "de 25e")
        XCTAssertEqual(RecurringText.dayPhrase(day: nil, defaultPhrase: "je salarisdag, de 25e"), "je salarisdag, de 25e")
        let text = RecurringText.newRecurring(dayPhrase: "de 31e", day: 31, month: ym(2026, 10), resumes: false)
        XCTAssertTrue(text.contains("Komt elke maand terug op de 31e"))
        XCTAssertTrue(text.contains("oktober 2026"))
        XCTAssertTrue(text.contains("laatste dag"))
        XCTAssertFalse(RecurringText.newRecurring(dayPhrase: "de 5e", day: 5, month: ym(2026, 10), resumes: false).contains("laatste dag"))
        XCTAssertTrue(RecurringText.newRecurring(dayPhrase: "de 5e", day: 5, month: ym(2026, 10), resumes: true).contains("geen tweede"))
        XCTAssertTrue(RecurringText.deleteMessage(name: "Huur", month: ym(2026, 10), current: ym(2026, 10)).contains("\"Huur\""))
        XCTAssertTrue(RecurringText.scopeMessage(name: "", month: ym(2026, 10), current: ym(2026, 10)).hasPrefix("Deze regel"))
        // Een maand in het verleden: de vraag waarschuwt dat ook voorbije maanden meeveranderen.
        XCTAssertTrue(RecurringText.scopeMessage(name: "Huur", month: ym(2026, 8), current: ym(2026, 10)).contains("al voorbij"))
        XCTAssertFalse(RecurringText.scopeMessage(name: "Huur", month: ym(2026, 10), current: ym(2026, 10)).contains("al voorbij"))
        XCTAssertTrue(RecurringText.deleteMessage(name: "Huur", month: ym(2026, 9), current: ym(2026, 10)).contains("al voorbij"))
        XCTAssertTrue(RecurringText.stopRecurringMessage(name: "Huur", month: ym(2026, 9), current: ym(2026, 10)).contains("al voorbij"))
    }

    // MARK: Een korte maand

    func testDay31StaysOnLastDayOfShortMonths() throws {
        var d = baseData()
        let line = MoneyLine(name: "Lening", amount: 120, isRecurring: true, kind: .fixed, day: 31)
        LineSave.apply(&d, edited: line, isNew: true, kind: .expense, month: ym(2026, 10), scope: .thisAndFollowing)
        for (y, m, last) in [(2026, 11, 30), (2027, 2, 28), (2028, 2, 29)] {
            let month = ym(y, m)
            let l = try XCTUnwrap(lines(d, month).first { $0.name == "Lening" }, "maand \(y)-\(m)")
            XCTAssertEqual(min(d.expenseDay(of: l), month.dayCount), last)
            let events = d.dayEvents(in: month).filter { $0.title == "Lening" }
            XCTAssertEqual(events.first?.day, last)
        }
    }
}
