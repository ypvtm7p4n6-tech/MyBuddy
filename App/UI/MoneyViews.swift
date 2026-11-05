import SwiftUI

// Gedeelde onderdelen voor schermen die dezelfde bedragen tonen. De cijfers zelf komen uit `MoneyFigures.swift` en daarmee
// uit de rekenmotor: deze views rekenen niets uit.

/// Een waarschuwing over de verdeling van een maand (percentages samen boven 100%, of meer verdeeld dan er is). De tekst
/// komt van de rekenmotor (`AllocationWarning.message`). Het symbool en de tekst dragen de betekenis, de kleur versterkt hem.
struct AllocationWarningLabel: View {
    let warning: AllocationWarning

    var body: some View {
        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch warning {
        case .percentagesOver100: return Theme.warning
        case .overAllocated: return Theme.negative
        }
    }
}

/// De korte uitleg dat bedragen op hele euro's staan afgerond (zie `DisplayRounding`). Toon hem alleen als de getoonde bedragen
/// door de afronding niet precies optellen.
struct RoundingNote: View {
    var body: some View {
        Text(DisplayRounding.note)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// De regel die zegt op welke dag(en) de inleg van een maand over gaat: "Overschrijving: € 50 op de 10e en € 150 op de 25e". De dagen
/// en bedragen komen uit de rekenmotor (`TransferMath.slices`, `FinanceData.transferSlices`); de zin uit `TransferPartsText.summary`.
enum TransferPartsOverview {
    static let prefix = "Overschrijving: "

    /// Voor de stukken van een opgeslagen maand (`ContributionInfo.slices`).
    static func line(slices: [TransferSlice], standardDay: Int) -> String {
        prefix + TransferPartsText.summary(slices: slices, standardDay: standardDay)
    }

    /// Een tekst die gelijk blijft zolang de delen zoals ze worden bewaard gelijk blijven (voor `hasChanges` van een blad): een nieuw
    /// deel zonder bedrag telt niet mee, want het wordt niet bewaard.
    static func signature(_ parts: [TransferPart]) -> String {
        TransferMath.normalized(parts).map { "\($0.day):\($0.amount)" }.joined(separator: ",")
    }

    /// Voor een concept in een blad: de inleg van `month` (in centen) verdeeld over de standaarddelen die je nu invult. nil zonder
    /// delen of zonder inleg om te verdelen.
    static func line(parts: [TransferPart], totalCents: Int, standardDay: Int, month: YearMonth) -> String? {
        let clean = TransferMath.normalized(parts)
        guard !clean.isEmpty, totalCents > 0 else { return nil }
        let day = min(max(standardDay, 1), month.dayCount)
        let slices = TransferMath.slices(totalCents: totalCents, parts: clean, standardDay: day, month: month)
        return line(slices: slices, standardDay: day)
    }
}

/// De sectie "Extra overschrijfdagen" in het blad van een spaarpot of belegging: de editor van de delen van de standaardinleg
/// (`TransferPartsEditor`). `totalCents` is de inleg van de lopende maand, voor de waarschuwing als de delen samen meer zijn.
struct StandardTransferPartsSection: View {
    @Binding var parts: [TransferPart]
    let standardDay: Int
    let totalCents: Int

    var body: some View {
        Section {
            TransferPartsEditor(parts: $parts, standardDay: standardDay, totalCents: totalCents)
        } header: {
            Text(TransferPartsText.title)
        }
    }
}

/// Hoe de inleg van een spaarpot of belegging in deze maand is opgebouwd: de standaardregel (een vast bedrag of een
/// percentage van je inkomen), wat daar in deze maand uit volgt, en waar het van afhangt. Bij een percentage is het bedrag
/// van deze maand de actuele waarde: het rekent mee als je inkomen verandert.
struct ContributionSummary: View {
    let info: ContributionInfo

    private var monthName: String { Fmt.monthNames[min(max(info.month.month, 1), 12) - 1] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FigureRow {
                StatTile(title: "Standaard", value: info.standardValue, caption: info.standardCaption)
                StatTile(title: "In \(monthName)", value: Fmt.euro(info.amount), caption: info.amountCaption)
            }
            if info.hasParts {
                // De inleg gaat in delen over: op welke dagen.
                Text(TransferPartsOverview.line(slices: info.slices, standardDay: info.transferDay))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if info.isOverride {
                Text("In \(monthName) wijkt de inleg af van je standaard: \(info.ruleText). Je standaard is \(info.standardText).")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if info.isPercent {
                Text("Het bedrag volgt je inkomen van die maand: verandert je salaris of krijg je extra inkomsten, dan gaat de inleg vanzelf mee.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if info.hasNoBase {
                Label("Er is in \(monthName) geen inkomen om het percentage over te rekenen: het bedrag is € 0.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
            if let average = info.averageAmount {
                Text("Je salaris komt niet elke maand even vaak binnen. In een gemiddelde maand is de inleg \(Fmt.euro(average)); toekomstschattingen rekenen daarmee.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            // De waarschuwingen gaan over de hele verdeling; ze staan hier alleen als deze inleg meedoet.
            if info.amount != 0 {
                ForEach(info.warnings, id: \.message) { warning in
                    AllocationWarningLabel(warning: warning)
                }
            }
        }
        .animated(by: info)
    }
}
