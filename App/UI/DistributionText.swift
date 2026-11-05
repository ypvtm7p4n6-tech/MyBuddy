import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in
// DistributionTextTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Het extra bedrag bij een percentage (D1)

/// Teksten rond het extra bedrag dat bovenop een percentage komt. Alleen tekst: alle bedragen komen uit de rekenmotor.
enum ExtraAmountText {
    static let title = "Extra bedrag erbij"
    static let footer = "Dit bedrag komt elke maand bovenop het percentage in dezelfde pot."

    /// "€ 300 uit het percentage plus € 50 extra". nil zonder extra bedrag.
    static func breakdown(percentAmount: Double, extra: Double) -> String? {
        let cents = AllocationMath.extraCents(extra)
        guard cents > 0 else { return nil }
        return "\(Fmt.euro(percentAmount)) uit het percentage plus \(Fmt.euro(CentsMath.value(cents))) extra"
    }
}

// MARK: - Extra overschrijfdata (D2)

/// Teksten rond de delen van de inleg die op een eigen dag worden overgeschreven.
enum TransferPartsText {
    static let title = "Extra overschrijfdagen"
    static let addTitle = "Dag toevoegen"
    static let resetTitle = "Terug naar standaard"
    static let makeStandardTitle = "Maak dit je standaard"

    /// "€ 50 op de 10e".
    static func partTitle(_ part: TransferPart) -> String {
        "\(Fmt.euro(CentsMath.value(AllocationMath.extraCents(part.amount)))) op \(DayText.ordinal(YearMonth.clampedDay(part.day)))"
    }

    /// De samenvatting op de kop van het kader: "Alles op de 25e" of "€ 50 op de 10e en € 150 op de 25e". `slices` zijn de stukken
    /// van de maand (`FinanceData.transferSlices`), `standardDay` de standaarddag.
    static func summary(slices: [TransferSlice], standardDay: Int) -> String {
        guard !slices.isEmpty else { return "Alles op \(DayText.ordinal(standardDay))" }
        if slices.count == 1 { return "Alles op \(DayText.ordinal(slices[0].day))" }
        let items = slices.map { "\(Fmt.euro(CentsMath.value($0.cents))) op \(DayText.ordinal($0.day))" }
        return DayText.list(items)
    }

    /// Uitleg onder de lijst met delen.
    static func explanation(standardDay: Int) -> String {
        "Een deel gaat op zijn eigen dag over en telt pas vanaf die dag mee in het saldo van de pot. Wat overblijft gaat op \(DayText.ordinal(standardDay)), de overschrijfdag. Het totaal van de maand verandert niet."
    }

    /// De waarschuwing als de delen samen meer zijn dan de inleg van de maand (`TransferMath.overflowCents`). nil als alles past.
    static func overflowWarning(overflowCents: Int) -> String? {
        guard overflowCents > 0 else { return nil }
        return "De extra dagen zijn samen \(Fmt.euro(CentsMath.value(overflowCents))) meer dan de inleg van deze maand. Het teveel telt niet mee."
    }

    /// Een dag vanaf de 29e bestaat niet in elke maand.
    static func shortMonthNote(parts: [TransferPart]) -> String? {
        guard parts.contains(where: { $0.day >= 29 }) else { return nil }
        return "Is een maand korter, dan geldt de laatste dag van die maand."
    }

    /// De rij van een deel voor VoiceOver: "Deel van 50 euro op de 10e".
    static func accessibilityLabel(_ part: TransferPart) -> String {
        "Deel van \(Fmt.euro(CentsMath.value(AllocationMath.extraCents(part.amount)))) op \(DayText.ordinal(YearMonth.clampedDay(part.day)))"
    }

    /// De melding bij een startdatum als een deel van de inleg vóór de startdag valt en dus niet meetelt (`uncountedTransferSlices`).
    /// nil als alles meetelt. Eén stuk op de standaarddag zegt hetzelfde als altijd (`StartDateText.transferBeforeStart`).
    static func beforeStartNote(_ slices: [TransferSlice]) -> String? {
        guard !slices.isEmpty else { return nil }
        if slices.count == 1, let only = slices.first, only.isStandard { return StartDateText.transferBeforeStart(day: only.day) }
        let items = slices.map { "\(Fmt.euro(CentsMath.value($0.cents))) op \(DayText.ordinal($0.day))" }
        return "Telt niet mee: \(DayText.list(items)) valt vóór je startdatum."
    }

    /// De standaarddelen van een pot of belegging als regel onder "Standaard: …": "met € 40 op de 10e". nil zonder delen.
    static func standardParts(_ parts: [TransferPart]) -> String? {
        let clean = TransferMath.normalized(parts)
        guard !clean.isEmpty else { return nil }
        return "met " + DayText.list(clean.map { partTitle($0) })
    }
}

/// De lijst die de editor van de extra overschrijfdata toont: een concept naast wat er is opgeslagen. De opslag normaliseert (een deel
/// van 0 valt weg), dus een nieuwe rij met bedrag 0 bestaat alleen in het concept en mag niet worden overschreven door de opslag
/// zolang die er gelijk aan is.
enum TransferPartsDraft {
    /// De lijst die de editor nu toont: het concept zolang het (genormaliseerd) gelijk is aan wat is opgeslagen, anders wat is opgeslagen
    /// (een wijziging van buiten: een andere maand, "Terug naar standaard").
    static func displayed(draft: [TransferPart], stored: [TransferPart]) -> [TransferPart] {
        TransferMath.normalized(draft) == TransferMath.normalized(stored) ? draft : stored
    }
}

// MARK: - De bankrekening in de verdeling (D3)

/// Teksten rond de bankrekening als bestemming van de verdeling.
enum BankShareText {
    static let title = "Bankrekening"
    static let subtitle = "Blijft op je rekening"
    static let symbol = "building.columns"
    static let restTitle = "Rest naar bankrekening"
    static let explanation = "Dit deel van je inkomen blijft op je bankrekening. Het telt als verdeeld, maar er wordt niets overgeschreven: je saldo en je spaarpotten veranderen niet."

    /// De regel onder de rij: wat de rij van deze maand doet.
    static func caption(toBankCents: Int) -> String {
        toBankCents == 0
            ? "Niets toegewezen. Wat je hier invult blijft op je rekening en telt als verdeeld."
            : "\(Fmt.euro(CentsMath.value(toBankCents))) blijft op je rekening. Er wordt niets overgeschreven."
    }

    /// De regel bij Nog te verdelen en Verdeeld: "€ 500 is aan je bankrekening toegewezen en telt als verdeeld." nil zonder bankdeel.
    static func summaryNote(toBankCents: Int) -> String? {
        guard toBankCents != 0 else { return nil }
        return "\(Fmt.euro(CentsMath.value(toBankCents))) is aan je bankrekening toegewezen en telt als verdeeld."
    }
}
