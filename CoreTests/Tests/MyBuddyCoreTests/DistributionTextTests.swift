import XCTest
import Foundation
@testable import MyBuddyCore

/// De teksten en weergavehulpen van Verdelen (docs/work/plan2.md par. 3.5): het extra bedrag (D1), de extra overschrijfdata (D2) en de
/// bankrekening (D3). Alleen tekst en keuzes: de bedragen en dagen komen uit de rekenmotor.
final class DistributionTextTests: XCTestCase {
    private let nov = YearMonth(year: 2026, month: 11)
    private let now = day(oct2026, 12)

    private func base() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        let pot = Pot(name: "Vakantie", monthlyContribution: 200, startMonth: oct2026)
        d.addPot(pot, openingBalance: 100, now: day(oct2026, 1))
        d.addBankSnapshot(balance: 1_000, note: "Begin", date: day(oct2026, 1))
        var plan = MonthPlan()
        plan.expenses = [MoneyLine(name: "Huur", amount: 900, isRecurring: true, day: 1)]
        d.months[oct2026.key] = plan
        return (d, pot)
    }

    func testExtraAmountBreakdown() {
        XCTAssertEqual(ExtraAmountText.breakdown(percentAmount: 300, extra: 50), "\(Fmt.euro(300)) uit het percentage plus \(Fmt.euro(50)) extra")
        XCTAssertNil(ExtraAmountText.breakdown(percentAmount: 300, extra: 0))
        XCTAssertNil(ExtraAmountText.breakdown(percentAmount: 300, extra: -5))
    }

    func testPartTitleAndSummary() {
        XCTAssertEqual(TransferPartsText.partTitle(TransferPart(day: 10, amount: 50)), "\(Fmt.euro(50)) op de 10e")
        let slices = TransferMath.slices(totalCents: 20_000, parts: [TransferPart(day: 10, amount: 50)], standardDay: 25, month: nov)
        XCTAssertEqual(TransferPartsText.summary(slices: slices, standardDay: 25), "\(Fmt.euro(50)) op de 10e en \(Fmt.euro(150)) op de 25e")
        XCTAssertEqual(TransferPartsText.summary(slices: [], standardDay: 25), "Alles op de 25e")
        XCTAssertEqual(TransferPartsText.summary(slices: [TransferSlice(day: 25, cents: 20_000, isStandard: true)], standardDay: 25), "Alles op de 25e")
    }

    func testWarningsAndNotes() {
        XCTAssertNil(TransferPartsText.overflowWarning(overflowCents: 0))
        XCTAssertTrue(TransferPartsText.overflowWarning(overflowCents: 4_000)?.contains(Fmt.euro(40)) ?? false)
        XCTAssertNil(TransferPartsText.shortMonthNote(parts: [TransferPart(day: 28, amount: 1)]))
        XCTAssertNotNil(TransferPartsText.shortMonthNote(parts: [TransferPart(day: 29, amount: 1)]))
        XCTAssertTrue(TransferPartsText.explanation(standardDay: 25).contains("de 25e"))
        XCTAssertEqual(TransferPartsText.title, "Extra overschrijfdagen")
    }

    func testBankShareTexts() {
        XCTAssertEqual(BankShareText.title, "Bankrekening")
        XCTAssertTrue(BankShareText.caption(toBankCents: 0).hasPrefix("Niets toegewezen"))
        XCTAssertTrue(BankShareText.caption(toBankCents: 50_000).contains(Fmt.euro(500)))
        XCTAssertNil(BankShareText.summaryNote(toBankCents: 0))
        XCTAssertTrue(BankShareText.summaryNote(toBankCents: 50_000)?.contains(Fmt.euro(500)) ?? false)
    }

    // MARK: Teksten

    func testContributionInfoShowsPartsAndTheExtraAmount() throws {
        var (d, pot) = base()
        d.setContributionPercent(pot.id, percent: 3.5, basis: .salary, extra: 25, current: oct2026)
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 10, amount: 40)], current: oct2026)
        let info = try XCTUnwrap(ContributionInfo(d, id: pot.id, month: oct2026))
        XCTAssertEqual(info.amount, 130, accuracy: 1e-9, "3,5% van 3000 is 105, plus 25")
        XCTAssertTrue(info.hasParts)
        XCTAssertEqual(info.slices.map { $0.day }, [10, 25])
        XCTAssertTrue(info.standardValue.hasSuffix("+ " + Fmt.euro(25)), info.standardValue)
        XCTAssertTrue(info.standardCaption.hasSuffix("plus een vast bedrag"), info.standardCaption)
        XCTAssertTrue(try XCTUnwrap(info.baseText).hasSuffix("plus " + Fmt.euro(25)))
        let note = try XCTUnwrap(info.transferNote(to: "naar deze pot"))
        XCTAssertTrue(note.contains(Fmt.euro(40) + " op de 10e") && note.contains(Fmt.euro(90) + " op de 25e"), note)
        XCTAssertTrue(note.hasSuffix("De overschrijfdag is je salarisdag."), note)
        // Zonder delen en zonder extra bedrag is alles zoals het was.
        var (plain, plainPot) = base()
        plain.setContributionPercent(plainPot.id, percent: 10, basis: .salary, current: oct2026)
        let plainInfo = try XCTUnwrap(ContributionInfo(plain, id: plainPot.id, month: oct2026))
        XCTAssertFalse(plainInfo.hasParts)
        XCTAssertEqual(plainInfo.standardValue, Fmt.percent(0.10, digits: 2))
        XCTAssertEqual(plainInfo.transferNote(to: "naar deze pot"), "De inleg gaat op de 25e naar deze pot, je salarisdag.")
    }

    func testThePreviewOfAPercentageIncludesTheExtraAmount() {
        let (d, _) = base()
        let plain = ContributionPreview.resolve(d, percent: 10, basis: .salary, month: oct2026)
        let withExtra = ContributionPreview.resolve(d, percent: 10, basis: .salary, extra: 25, month: oct2026)
        XCTAssertEqual(plain.amount, 300, accuracy: 1e-9)
        XCTAssertEqual(withExtra.amount, 325, accuracy: 1e-9)
        XCTAssertTrue(withExtra.note.hasSuffix("plus " + Fmt.euro(25)), withExtra.note)
        XCTAssertFalse(plain.note.contains("plus"))
    }

    func testTheTransferCaptionNamesEveryPart() {
        var (d, pot) = base()
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 10, amount: 40)], current: oct2026)
        // Op 12 oktober is de 10e al gebeurd en de 25e gepland.
        let caption = DistributeText.transferCaption(d, id: pot.id, month: oct2026, today: now)
        XCTAssertTrue(caption.hasPrefix("Deels overgeschreven:"), caption)
        XCTAssertTrue(caption.contains(Fmt.euro(40) + " op de 10e en " + Fmt.euro(160) + " op de 25e"), caption)
        XCTAssertTrue(caption.hasSuffix("salarisdag"), caption)
        XCTAssertTrue(DistributeText.transferCaption(d, id: pot.id, month: oct2026, today: day(oct2026, 1)).hasPrefix("Wordt overgeschreven:"))
        XCTAssertTrue(DistributeText.transferCaption(d, id: pot.id, month: oct2026, today: day(oct2026, 30)).hasPrefix("Overgeschreven:"))
    }

    func testTheNoteAboutPartsBeforeTheStartDate() {
        XCTAssertNil(TransferPartsText.beforeStartNote([]))
        XCTAssertEqual(TransferPartsText.beforeStartNote([TransferSlice(day: 3, cents: 10_000, isStandard: true)]),
                       StartDateText.transferBeforeStart(day: 3))
        let two = [TransferSlice(day: 3, cents: 5_000, isStandard: false), TransferSlice(day: 5, cents: 15_000, isStandard: true)]
        let note = TransferPartsText.beforeStartNote(two) ?? ""
        XCTAssertTrue(note.hasPrefix("Telt niet mee:") && note.contains(Fmt.euro(50) + " op de 3e") && note.contains(Fmt.euro(150) + " op de 5e"), note)
        // De rij op Verdelen: een startdatum midden in de maand laat de stukken vóór de startdag weg.
        var (d, pot) = base()
        d.setStandardTransferParts(pot.id, parts: [TransferPart(day: 10, amount: 40)], current: oct2026)
        d.setStart(CalendarDay(year: 2026, month: 10, day: 12))
        let uncounted = d.uncountedTransferSlices(for: pot.id, in: oct2026)
        XCTAssertEqual(uncounted.map { $0.day }, [10])
        XCTAssertTrue((TransferPartsText.beforeStartNote(uncounted) ?? "").contains(Fmt.euro(40) + " op de 10e"))
    }

    func testStandardPartsAndTheDraftOfTheEditor() {
        XCTAssertNil(TransferPartsText.standardParts([]))
        XCTAssertNil(TransferPartsText.standardParts([TransferPart(day: 3, amount: 0)]))
        XCTAssertEqual(TransferPartsText.standardParts([TransferPart(day: 10, amount: 40), TransferPart(day: 20, amount: 10)]),
                       "met " + Fmt.euro(40) + " op de 10e en " + Fmt.euro(10) + " op de 20e")
        // Een nieuwe rij met bedrag 0 bestaat alleen in het concept: de opslag laat hem weg en overschrijft het concept niet.
        let stored = [TransferPart(day: 10, amount: 40)]
        let draft = [TransferPart(day: 10, amount: 40), TransferPart(day: 15, amount: 0)]
        XCTAssertEqual(TransferPartsDraft.displayed(draft: draft, stored: stored), draft)
        // Een wijziging van buiten (een andere maand) vervangt het concept.
        XCTAssertEqual(TransferPartsDraft.displayed(draft: draft, stored: [TransferPart(day: 2, amount: 5)]), [TransferPart(day: 2, amount: 5)])
        XCTAssertEqual(TransferPartsDraft.displayed(draft: [], stored: []), [])
    }

    func testTheTitlesAndTermsFollowTheTermList() {
        XCTAssertEqual(ExtraAmountText.title, "Extra bedrag erbij")
        XCTAssertEqual(TransferPartsText.title, "Extra overschrijfdagen")
        XCTAssertEqual(TransferPartsText.addTitle, "Dag toevoegen")
        XCTAssertEqual(TransferPartsText.resetTitle, "Terug naar standaard")
        XCTAssertEqual(TransferPartsText.makeStandardTitle, "Maak dit je standaard")
        XCTAssertEqual(BankShareText.restTitle, "Rest naar bankrekening")
        XCTAssertEqual(BankShareText.subtitle, "Blijft op je rekening")
        XCTAssertEqual(BankShareText.symbol, "building.columns")
        // Geen woord dat de termenlijst verbiedt en geen spatie met de hand opgemaakt: "je", niet "u".
        let all = [ExtraAmountText.footer, TransferPartsText.explanation(standardDay: 25), BankShareText.explanation,
                   BankShareText.caption(toBankCents: 0), TransferPartsText.accessibilityLabel(TransferPart(day: 5, amount: 10))]
        for text in all {
            XCTAssertFalse(text.contains(" u "), text)
            XCTAssertFalse(text.lowercased().contains("meetpunt"), text)
            XCTAssertFalse(text.contains("  "), "dubbele spatie in: \(text)")
        }
    }

    func testThePartTitleIsRoundedToWholeCentsAndShowsTheClampedDay() {
        XCTAssertEqual(TransferPartsText.partTitle(TransferPart(day: 50, amount: 12.345)), "\(Fmt.euro(12.35)) op de 31e")
        XCTAssertEqual(TransferPartsText.partTitle(TransferPart(day: 0, amount: 5)), "\(Fmt.euro(5)) op de 1e")
        XCTAssertEqual(TransferPartsText.accessibilityLabel(TransferPart(day: 10, amount: 50)), "Deel van \(Fmt.euro(50)) op de 10e")
        XCTAssertEqual(TransferPartsText.accessibilityLabel(TransferPart(day: 10, amount: .nan)), "Deel van \(Fmt.euro(0)) op de 10e")
    }

    func testTheEditorDraftKeepsARowWithoutAnAmountUntilItGetsOne() {
        let stored: [TransferPart] = []
        let draft = [TransferPart(day: 5, amount: 0)]
        XCTAssertEqual(TransferPartsDraft.displayed(draft: draft, stored: stored), draft, "een nieuwe rij van 0 blijft staan")
        // Daarna krijgt de rij een bedrag: de opslag is gelijk aan het concept, dat blijft staan.
        let filled = [TransferPart(day: 5, amount: 20)]
        XCTAssertEqual(TransferPartsDraft.displayed(draft: filled, stored: TransferMath.normalized(filled)), filled)
        // Verandert de opslag buiten de editor (een andere maand, "Terug naar standaard"), dan wint de opslag.
        XCTAssertEqual(TransferPartsDraft.displayed(draft: filled, stored: []), [])
        XCTAssertEqual(TransferPartsDraft.displayed(draft: [], stored: filled), filled)
        // Twee rijen op dezelfde dag vallen samen in de opslag: het concept blijft zolang dat gelijk is.
        let doubled = [TransferPart(day: 5, amount: 10), TransferPart(day: 5, amount: 10)]
        XCTAssertEqual(TransferPartsDraft.displayed(draft: doubled, stored: TransferMath.normalized(doubled)), doubled)
    }
}
