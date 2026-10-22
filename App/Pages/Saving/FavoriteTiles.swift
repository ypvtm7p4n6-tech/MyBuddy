import SwiftUI

// De tegels van de gekozen potten en beleggingen op het Overzicht en bij Sparen: een pot met voortgangsring, een belegging met
// waarde, en de lege plek ("Kies pot"). Een tegel is een knop die naar de pagina van de pot of belegging leidt.

/// Legt tegels naast elkaar, even groot: zoveel als er passen, onder elkaar bij grote tekst. De kolombreedte schaalt mee met Dynamic Type.
struct FavoriteTileGrid<Content: View>: View {
    let wide: Bool
    private let content: Content
    @ScaledMetric(relativeTo: .body) private var baseWidth: CGFloat = 100

    init(wide: Bool = false, @ViewBuilder content: () -> Content) {
        self.wide = wide
        self.content = content()
    }

    var body: some View {
        EqualSizeGrid(minimumColumnWidth: wide ? baseWidth * 1.6 : baseWidth, spacing: 8) {
            content
        }
    }
}

// MARK: - Een spaarpot

/// Een gekozen spaarpot: ring met de voortgang naar het doel (zonder doel alleen het symbool), naam, saldo van vandaag en het doel.
struct FavoritePotTile: View {
    let pot: Pot
    @Environment(AppStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 56

    init(pot: Pot) {
        self.pot = pot
    }

    var body: some View {
        SavingLink(.pot(pot.id)) { tile }
            .buttonStyle(SavingPressStyle())
    }

    @ViewBuilder
    private var tile: some View {
        let d = store.data
        let balance = d.potBalanceNow(pot.id, current: store.now, today: store.today)
        // Dezelfde voortgang als op de pagina Spaarpotten en bij de pot zelf (`potProgress`, met het saldo van vandaag).
        let progress = d.potProgress(pot.id, current: store.now, today: store.today)
        let color = Theme.color(pot.colorIndex)
        VStack(spacing: 6) {
            ZStack {
                ProgressMeter(value: progress, tint: color, style: .ring(lineWidth: 4), label: "Voortgang \(pot.name)",
                              valueText: spokenProgress(balance: balance, progress: progress))
                SymbolBadge(symbol: pot.symbol, color: color, size: 36)
            }
            .frame(width: ringSize, height: ringSize)
            Text(pot.name)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(Fmt.euro(balance))
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animated(by: balance)
            Text(pot.goalAmount.map { $0 > 0 ? "Doel \(Fmt.euro($0))" : "Geen doel" } ?? "Geen doel")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .tile()
        .accessibilityElement(children: .combine)
    }

    private func spokenProgress(balance: Double, progress: Double?) -> String {
        guard let progress, let goal = pot.goalAmount, goal > 0 else { return "Geen doel ingesteld" }
        return PotFormat.progressSpeech(balance: balance, goal: goal, progress: progress)
    }
}

// MARK: - Een belegging

/// Een gekozen belegging: symbool in de kleur van de soort, naam, waarde van nu en de soort (met "geschat" als de waarde uit je inleg komt).
struct FavoriteHoldingTile: View {
    let holding: Holding
    @Environment(AppStore.self) private var store

    init(holding: Holding) {
        self.holding = holding
    }

    var body: some View {
        SavingLink(.holding(holding.id)) { tile }
            .buttonStyle(SavingPressStyle())
    }

    @ViewBuilder
    private var tile: some View {
        let figures = HoldingFigures(store.data.holdingStateNow(holding, current: store.now, today: store.today))
        HStack(spacing: 10) {
            SymbolBadge(symbol: holding.kind.symbol, color: Theme.color(holding.kind.colorIndex), size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(holding.name)
                    .font(.footnote.weight(.semibold))
                Text(Fmt.euro(figures.value))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animated(by: figures.value)
                Text(figures.isEstimated ? "\(holding.kind.title) · geschat" : holding.kind.title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.primary)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .tile()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - De lege plek

/// Een lege plek naast de gekozen potten: een omlijnde tegel met een plus en "Kies pot". Een tik opent het blad waarin je een pot
/// kiest (of, als er geen pot meer is om te kiezen, het blad voor een nieuwe pot).
struct FavoriteSlotTile: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 56

    init(title: String = "Kies pot", symbol: String = "plus", action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(Theme.textSecondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SavingPressStyle())
    }
}
