import SwiftUI

// De secties van een belegging onder de kop en de grafiek: Samenvatting, Uitgangspunten, Inleg en Waarde-updates (de tracklijst),
// met onderaan Verwijderen. De grafiek staat in HoldingChartSection.swift, de kop in HoldingDetailPage.swift.

// MARK: - Samenvatting

/// Wat je inlegde en won, en (met een ticker) het aantal en de koers. De waarde van nu en de winst staan in de kop van de pagina.
/// Is de waarde geschat uit je inleg, dan zijn Winst en het percentage verborgen.
struct HoldingSummarySection: View {
    let holding: Holding
    @Environment(AppStore.self) private var store

    init(holding: Holding) {
        self.holding = holding
    }

    var body: some View {
        let state = store.data.holdingStateNow(holding, current: store.now, today: store.today)
        let figures = HoldingFigures(state)
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                FigureRow {
                    StatTile(title: "Ingelegd", value: Fmt.euro(figures.invested))
                    if figures.showsGain {
                        StatTile(title: "Winst", value: Fmt.euro(figures.gain),
                                 color: figures.gain >= 0 ? Theme.positive : Theme.negative)
                    }
                }
                if holding.hasTicker {
                    trackedInfo
                }
            }
        } header: {
            SectionHeader("Samenvatting", symbol: holding.kind.symbol, domain: .investing)
        }
    }

    /// Het aantal en de koers, met wanneer de koers voor het laatst is opgehaald. Zonder aantal staat er wat er nog nodig is.
    @ViewBuilder
    private var trackedInfo: some View {
        let units = holding.units ?? 0
        FigureRow {
            StatTile(title: "Aantal", value: units > 0 ? Fmt.input(units, maxDigits: 6) : "–")
            StatTile(title: "Koers", value: holding.lastPrice.map { Fmt.euroExact($0) } ?? "–", caption: holding.ticker)
        }
        if !(units > 0) {
            Text(HoldingForm.unitsHint)
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        priceStatus
    }

    @ViewBuilder
    private var priceStatus: some View {
        if store.isRefreshingPrices {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Koers ophalen…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else if let date = holding.lastPriceDate {
            Text("Bijgewerkt \(Fmt.dateTime(date))")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Uitgangspunten

struct HoldingAssumptionsSection: View {
    let holding: Holding
    @Environment(AppStore.self) private var store
    @State private var backfillMessage: String?

    init(holding: Holding) {
        self.holding = holding
    }

    var body: some View {
        Section {
            FigureRow {
                StatTile(title: "Rendement per jaar", value: Fmt.percent(holding.expectedReturn))
                StatTile(title: "Kosten per jaar", value: Fmt.percent(holding.annualCost, digits: 2))
            }
            AmountRow(title: "Belegd sinds", value: Fmt.month(holding.startMonth))
            if holding.isTracked {
                backfill
            }
        } header: {
            SectionHeader("Uitgangspunten", symbol: "slider.horizontal.3", domain: .investing)
        }
    }

    @ViewBuilder
    private var backfill: some View {
        ActionButton(title: "Historie aanvullen", symbol: "clock.arrow.circlepath") {
            let id = holding.id
            Task { backfillMessage = await store.backfillHistory(holdingID: id) }
        }
        if let backfillMessage {
            Text(backfillMessage)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        Text("Historie aanvullen neemt aan dat je het afgelopen jaar evenveel stuks had als nu.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Inleg

struct HoldingContributionSection: View {
    let holding: Holding
    let onEdit: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    init(holding: Holding, onEdit: @escaping () -> Void) {
        self.holding = holding
        self.onEdit = onEdit
    }

    var body: some View {
        // De opbouw van de maandelijkse inleg (een bedrag of een percentage van je inkomen), uit de rekenmotor.
        let info = ContributionInfo(store.data, id: holding.id, month: store.now)
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if let info {
                    ContributionSummary(info: info)
                }
                if let note = info?.transferNote(to: "van je rekening naar deze belegging") {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ActionGroup {
                    ActionButton(title: "Bewerken", symbol: "pencil") { onEdit() }
                    // De inleg hoort bij deze maand: de verdeelpagina opent op de huidige maand.
                    ActionButton(title: "Verdelen", symbol: "square.split.2x2") {
                        router.showCurrentMonth(store.now)
                        router.open(.distribute)
                    }
                }
            }
        } header: {
            SectionHeader("Inleg", symbol: "calendar", domain: .investing)
        }
    }
}

// MARK: - Waarde-updates

/// De waarde-updates van de belegging, de nieuwste eerst, als tracklijst met een kleine tegel per update. Swipe en contextmenu
/// verwijderen een update.
struct HoldingUpdatesSection: View {
    let holding: Holding
    let onValueUpdate: () -> Void
    @Environment(AppStore.self) private var store

    init(holding: Holding, onValueUpdate: @escaping () -> Void) {
        self.holding = holding
        self.onValueUpdate = onValueUpdate
    }

    var body: some View {
        let snapshots = Array(holding.snapshots.sorted { $0.date > $1.date }.prefix(24))
        Section {
            if snapshots.isEmpty {
                Text("Nog geen waarde-updates. Werk de waarde bij of ververs de koers.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(snapshots) { snapshot in
                updateRow(snapshot)
            }
            if !holding.isTracked {
                ActionButton(title: "Waarde bijwerken", symbol: "arrow.triangle.2.circlepath") { onValueUpdate() }
            }
        } header: {
            SectionHeader("Waarde-updates", symbol: "list.bullet.rectangle", domain: .investing)
        }
    }

    private func updateRow(_ snapshot: ValueSnapshot) -> some View {
        MediaRowLabel(symbol: "arrow.triangle.2.circlepath", hue: Theme.hue(holding.kind.colorIndex),
                      title: Fmt.date(snapshot.date), subtitle: "Ingelegd \(Fmt.euro(snapshot.invested))",
                      value: Fmt.euro(snapshot.value))
            .rowActions(delete: {
                let hid = holding.id
                let sid = snapshot.id
                store.mutate { $0.deleteSnapshot(holdingID: hid, snapshotID: sid) }
            })
    }
}

// MARK: - Verwijderen

/// Onderaan de pagina, rood, met de bevestiging aan de knop zelf.
struct HoldingDeleteSection: View {
    let holding: Holding
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(holding: Holding) {
        self.holding = holding
    }

    var body: some View {
        Section {
            ActionButton(title: "Belegging verwijderen", symbol: "trash", role: .destructive) { confirmDelete = true }
                .modifier(HoldingDeleteDialog(holding: holding, isPresented: $confirmDelete, onDeleted: { dismiss() }))
        }
    }
}
