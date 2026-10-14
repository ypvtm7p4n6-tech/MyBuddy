import SwiftUI

// Gedeelde onderdelen voor schermen die dezelfde bedragen tonen. De cijfers zelf komen uit `MoneyFigures.swift` en daarmee
// uit de rekenmotor: deze views rekenen niets uit.

/// Een waarschuwing over de verdeling van een maand (percentages samen boven 100%, of meer verdeeld dan er is). De tekst
/// komt van de rekenmotor (`AllocationWarning.message`).
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

/// Hoe de inleg van een spaarpot of belegging in deze maand is opgebouwd: de standaardregel (een vast bedrag of een
/// percentage van je inkomen), wat daar in deze maand uit volgt, en waar het van afhangt. Bij een percentage is het bedrag
/// van deze maand de actuele waarde: het rekent mee als je inkomen verandert.
struct ContributionSummary: View {
    let info: ContributionInfo

    private var monthName: String { Fmt.monthNames[min(max(info.month.month, 1), 12) - 1] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EqualSizeGrid(minimumColumnWidth: 140, spacing: 8) {
                StatTile(title: "Standaard", value: info.standardValue, caption: info.standardCaption)
                StatTile(title: "In \(monthName)", value: Fmt.euro(info.amount), caption: info.amountCaption)
            }
            if info.isOverride {
                Text("In \(monthName) wijkt de inleg af van je standaard: \(info.ruleText). Je standaard is \(info.standardText).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if info.isPercent {
                Text("Het bedrag volgt je inkomen van die maand: verandert je salaris of krijg je extra inkomsten, dan gaat de inleg vanzelf mee.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            // De waarschuwingen gaan over de hele verdeling; ze staan hier alleen als deze inleg meedoet.
            if info.amount != 0 {
                ForEach(info.warnings, id: \.message) { warning in
                    AllocationWarningLabel(warning: warning)
                }
            }
        }
        .animation(Theme.motion, value: info)
    }
}
