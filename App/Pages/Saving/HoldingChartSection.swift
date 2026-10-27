import SwiftUI

// De grafiek van een belegging (Koers en waarde), de eerste sectie onder de kop van de pagina. De grafiek zelf is ongewijzigd:
// `TrendChart` met `PortfolioTrend` en `PriceTrend`.

/// De grafiek van de belegging: de waarde (afgeleid uit je inleg of uit je waarde-updates) en, met een ticker, de koers van het
/// afgelopen jaar. Bij elke ticker begint de koershistorie leeg; laden en een fout zijn lege staten met "Probeer opnieuw".
struct HoldingChartSection: View {
    let holding: Holding
    let onAction: (ChartEmpty.Action) -> Void
    @Environment(AppStore.self) private var store
    @State private var kind: ChartKind = .value
    @State private var history: [PricePoint] = []
    @State private var historyState: PriceTrend.LoadState = .loading

    /// Wat de grafiek toont.
    private enum ChartKind: String, CaseIterable, Identifiable {
        case value
        case price

        var id: String { rawValue }

        var title: String {
            switch self {
            case .value: return "Waarde"
            case .price: return "Koers"
            }
        }
    }

    init(holding: Holding, onAction: @escaping (ChartEmpty.Action) -> Void) {
        self.holding = holding
        self.onAction = onAction
    }

    var body: some View {
        // Zonder ticker is er geen koers: dan is er alleen de waarde.
        let shown: ChartKind = holding.hasTicker ? kind : .value
        Section {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if holding.hasTicker {
                    kindPicker(shown: shown)
                }
                chart(shown: shown)
            }
            .task(id: holding.ticker ?? "") { await loadHistory() }
        } header: {
            SectionHeader(holding.hasTicker ? "Koers en waarde" : "Waarde", symbol: "chart.xyaxis.line", domain: .investing)
        }
    }

    private func kindPicker(shown: ChartKind) -> some View {
        Picker("Grafiek", selection: Binding(get: { shown }, set: { kind = $0 })) {
            ForEach(ChartKind.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: shown)
    }

    @ViewBuilder
    private func chart(shown: ChartKind) -> some View {
        switch shown {
        case .price:
            TrendChart(model: PriceTrend.model(history: history, ticker: holding.ticker ?? "", state: historyState),
                       size: .regular, onAction: { action in handlePriceAction(action) })
        case .value:
            TrendChart(model: PortfolioTrend.model(store.data, window: .all, current: store.now, today: store.today,
                                                   only: [holding.id]),
                       size: .regular, nonNegative: true, onAction: onAction)
        }
    }

    private func handlePriceAction(_ action: ChartEmpty.Action) {
        if action == .retry {
            Task { await loadHistory() }
        } else {
            onAction(action)
        }
    }

    /// Haalt de koers van het afgelopen jaar op. De oude koers verdwijnt eerst, zodat een mislukte poging nooit de koers van een
    /// vorige ticker laat staan.
    private func loadHistory() async {
        history = []
        guard holding.hasTicker, let ticker = holding.ticker else {
            historyState = .loaded
            return
        }
        historyState = .loading
        do {
            let points = try await store.priceHistory(ticker: ticker, range: "1y", interval: "1d")
            if Task.isCancelled { return }
            history = points
            historyState = .loaded
        } catch {
            if Task.isCancelled { return }
            history = []
            historyState = .failed(failureReason(error))
        }
    }

    private func failureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Er is geen internetverbinding."
            case .timedOut:
                return "De verbinding duurde te lang."
            default:
                break
            }
        }
        return PriceHistoryText.failure("Ophalen mislukt: \(error.localizedDescription)")
    }
}
