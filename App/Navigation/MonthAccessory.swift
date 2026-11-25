import SwiftUI

/// De balk boven de tabbalk (iOS 26, `tabViewBottomAccessory`), zoals de mini-speler van Apple Muziek: altijd binnen een tik het
/// getal waar de app om draait, "Nog te verdelen" van deze maand, met de volgende salarisdag. Een tik opent Verdelen op de huidige
/// maand op de stapel van de tab waar je bent. Het systeem tekent het glas en de vorm; als de tabbalk bij scrollen krimpt, zet het
/// de balk naast de tabs (`tabViewBottomAccessoryPlacement == .inline`) en toont hij alleen het getal. Het getal is hetzelfde als op
/// Home, Verdelen en in de Bibliotheek (`MonthBoard.left(current:)`).
@available(iOS 26.0, macOS 26.0, *)
struct MonthAccessory: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let d = store.data
        let month = store.now
        let board = MonthBoard(d, month: month)
        let left = board.left(current: month)
        let negative = board.leftIsNegative(current: month)
        let next = d.nextPayDate(after: store.today)
        Button {
            router.showCurrentMonth(month)
            router.open(.distribute)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: negative ? "exclamationmark.triangle.fill" : "chart.pie.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(negative ? Theme.negative : Theme.accent)
                    .accessibilityHidden(true)
                if placement == .inline {
                    Text(Fmt.euro(left))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(negative ? Theme.negative : Color.primary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(MoneyLabels.remaining) \(Fmt.euro(left))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(negative ? Theme.negative : Color.primary)
                            .lineLimit(1)
                        if let next {
                            Text("Volgende salaris \(DayText.short(next))")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("Verdelen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(MoneyLabels.remaining) deze maand \(Fmt.euro(left))" + (next.map { ", volgende salaris \(DayText.short($0))" } ?? ""))
        .accessibilityHint("Opent Verdelen")
        .accessibilityAddTraits(.isLink)
    }
}
