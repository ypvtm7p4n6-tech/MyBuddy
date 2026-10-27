import SwiftUI

// De twee korte bladen waarin je kiest welke potten (maximaal 3) en beleggingen (maximaal 4) op Home staan, in de volgorde waarin je
// tikt. Ze hebben `hasChanges`: met een niet-bewaarde keuze is veeg-om-te-sluiten uit. De keuze zelf
// (`FavoritePicker`) staat zonder SwiftUI in App/UI/PotDisplay.swift, met tests.

/// Het volgnummer van een gekozen rij, of een lege cirkel als de rij niet gekozen is (de keuze staat dus niet alleen in kleur).
private struct FavoriteOrderMark: View {
    let position: Int?
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 24

    var body: some View {
        if let position {
            Text("\(position + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: size, height: size)
                .background(Theme.accentFill, in: Circle())
                .accessibilityHidden(true)
        } else {
            Circle()
                .strokeBorder(Theme.textSecondary, lineWidth: 1)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Spaarpotten op Home

struct FavoritePotsSheet: View {
    @Environment(AppStore.self) private var store
    @State private var selected: [UUID] = []
    /// De keuze zoals ze was bij het openen, om te weten of er iets is veranderd.
    @State private var original: [UUID] = []

    init() {}

    var body: some View {
        SheetScaffold(title: "Spaarpotten op Home", hasChanges: selected != original, onSave: { save() }) {
            Section {
                ForEach(store.data.pots) { pot in
                    row(pot)
                }
            } header: {
                Text("Kies maximaal \(FavoritePicker.potLimit). De volgorde is de volgorde waarin je tikt.")
            }
        }
        .onAppear {
            let current = store.data.homePots().map { $0.id }
            selected = current
            original = current
        }
    }

    private func row(_ pot: Pot) -> some View {
        let position = selected.firstIndex(of: pot.id)
        let isFull = selected.count >= FavoritePicker.potLimit
        return Button {
            selected = FavoritePicker.toggled(pot.id, in: selected, limit: FavoritePicker.potLimit)
        } label: {
            HStack(spacing: 12) {
                ArtworkTile(symbol: pot.symbol, hue: Theme.hue(pot.colorIndex), size: .row)
                Text(pot.name)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                FavoriteOrderMark(position: position)
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .disabled(position == nil && isFull)
        .accessibilityAddTraits(position == nil ? [] : .isSelected)
        .accessibilityValue(position.map { "Gekozen, nummer \($0 + 1)" } ?? "Niet gekozen")
    }

    private func save() {
        let ids = selected
        store.mutate { $0.homePotIDs = ids }
    }
}

// MARK: - Beleggingen op Home

struct FavoriteHoldingsSheet: View {
    @Environment(AppStore.self) private var store
    @State private var selected: [UUID] = []
    /// De keuze zoals ze was bij het openen, om te weten of er iets is veranderd.
    @State private var original: [UUID] = []

    init() {}

    var body: some View {
        SheetScaffold(title: "Beleggingen op Home", hasChanges: selected != original, onSave: { save() }) {
            Section {
                ForEach(store.data.holdings) { holding in
                    row(holding)
                }
            } header: {
                Text("Kies maximaal \(FavoritePicker.holdingLimit). De volgorde is de volgorde waarin je tikt.")
            }
        }
        .onAppear {
            let current = store.data.homeHoldings().map { $0.id }
            selected = current
            original = current
        }
    }

    private func row(_ holding: Holding) -> some View {
        let position = selected.firstIndex(of: holding.id)
        let isFull = selected.count >= FavoritePicker.holdingLimit
        return Button {
            selected = FavoritePicker.toggled(holding.id, in: selected, limit: FavoritePicker.holdingLimit)
        } label: {
            HStack(spacing: 12) {
                ArtworkTile(symbol: holding.kind.symbol, hue: Theme.hue(holding.kind.colorIndex), size: .row)
                VStack(alignment: .leading, spacing: 1) {
                    Text(holding.name)
                        .foregroundStyle(Color.primary)
                    Text(holding.kind.title)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                FavoriteOrderMark(position: position)
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .disabled(position == nil && isFull)
        .accessibilityAddTraits(position == nil ? [] : .isSelected)
        .accessibilityValue(position.map { "Gekozen, nummer \($0 + 1)" } ?? "Niet gekozen")
    }

    private func save() {
        let ids = selected
        store.mutate { $0.homeHoldingIDs = ids }
    }
}
