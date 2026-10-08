import SwiftUI

// MARK: - Gedeelde onderdelen

/// Toestand van één cijfer dat van internet wordt gehaald.
private enum MarketLoad {
    case idle
    case loading
    case loaded(RateReading)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Korte Nederlandse foutmelding voor in beeld.
private func marketErrorMessage(_ error: Error) -> String {
    let fallback = "Ophalen mislukt. Controleer je internetverbinding."
    if let known = error as? MarketDataError { return known.errorDescription ?? fallback }
    if let known = error as? MarketReturnError { return known.errorDescription ?? fallback }
    if let known = error as? QuoteError { return known.errorDescription ?? fallback }
    return fallback
}

/// Knoprij: icoon, titel en een draaiend rondje terwijl er wordt opgehaald.
private struct MarketFetchLabel: View {
    let title: String
    let symbol: String
    let loading: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(title)
            Spacer(minLength: 8)
            if loading {
                ProgressView().controlSize(.small)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Het opgehaalde cijfer met uitleg, bron en een knop om het over te nemen.
private struct MarketReadingCard: View {
    let reading: RateReading
    let actionTitle: String
    let applied: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Fmt.percent(reading.value, digits: 2))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(reading.label)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bron: \(reading.source)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ChipButton(title: applied ? "Overgenomen" : actionTitle,
                       symbol: applied ? "checkmark" : "arrow.down.circle") {
                onApply()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarketErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.negative)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Losse rij

/// Eén knop die een cijfer van internet haalt, het resultaat toont en een knop 'Overnemen' geeft.
/// Te gebruiken in een Form of in een GlassBlock; met `.chipStyle()` krijgt de knop het glazen capsule-uiterlijk
/// van de andere acties in een blok.
struct RateFetchRow: View {
    let title: String
    let systemImage: String
    let fetch: () async throws -> RateReading
    let apply: (Double) -> Void

    private var usesChips = false
    @State private var load: MarketLoad = .idle
    @State private var applied = false

    init(title: String, systemImage: String,
         fetch: @escaping () async throws -> RateReading,
         apply: @escaping (Double) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.fetch = fetch
        self.apply = apply
    }

    /// Zelfde knop in het uiterlijk van `ChipButton` (voor in een GlassBlock).
    func chipStyle(_ enabled: Bool = true) -> RateFetchRow {
        var copy = self
        copy.usesChips = enabled
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await run() }
            } label: {
                if usesChips {
                    ChipLabel(title: load.isLoading ? "Bezig met ophalen…" : title, symbol: systemImage)
                } else {
                    MarketFetchLabel(title: title, symbol: systemImage, loading: load.isLoading)
                }
            }
            .buttonStyle(.plain)
            .disabled(load.isLoading)

            switch load {
            case .loaded(let reading):
                MarketReadingCard(reading: reading, actionTitle: "Overnemen", applied: applied) {
                    apply(reading.value)
                    applied = true
                }
            case .failed(let message):
                MarketErrorText(message: message)
            case .idle, .loading:
                EmptyView()
            }
        }
    }

    @MainActor
    private func run() async {
        load = .loading
        applied = false
        do {
            let reading = try await fetch()
            load = .loaded(reading)
        } catch is CancellationError {
            load = .idle
        } catch {
            load = .failed(marketErrorMessage(error))
        }
    }
}

// MARK: - Sectie voor in Instellingen

/// Rijen voor in een Form (Instellingen): haalt inflatie en spaarrente van internet en laat de gebruiker kiezen of
/// de waarde wordt overgenomen. Levert Sections terug, dus nooit in een ScrollView zetten.
struct MarketDataSection: View {
    @Environment(AppStore.self) private var store
    @State private var inflation: MarketLoad = .idle
    @State private var savings: MarketLoad = .idle
    @State private var inflationApplied = false
    @State private var savingsApplied = false

    private var anyLoading: Bool { inflation.isLoading || savings.isLoading }

    /// Beide cijfers zijn opgehaald: dan kan alles in één keer worden overgenomen.
    private var bothReadings: (inflation: RateReading, savings: RateReading)? {
        if case .loaded(let first) = inflation, case .loaded(let second) = savings {
            return (first, second)
        }
        return nil
    }

    var body: some View {
        Section {
            Button {
                Task { await loadInflation() }
            } label: {
                MarketFetchLabel(title: "Inflatie ophalen", symbol: "chart.line.uptrend.xyaxis", loading: inflation.isLoading)
            }
            .buttonStyle(.plain)
            .disabled(inflation.isLoading)
            results(for: inflation, applied: inflationApplied) { useInflation($0) }

            Button {
                Task { await loadSavings() }
            } label: {
                MarketFetchLabel(title: "Spaarrente ophalen", symbol: "percent", loading: savings.isLoading)
            }
            .buttonStyle(.plain)
            .disabled(savings.isLoading)
            results(for: savings, applied: savingsApplied) { useSavings($0) }

            Button {
                Task { await loadInflation() }
                Task { await loadSavings() }
            } label: {
                MarketFetchLabel(title: "Alles ophalen", symbol: "arrow.triangle.2.circlepath", loading: anyLoading)
            }
            .buttonStyle(.plain)
            .disabled(anyLoading)

            if let both = bothReadings, !(inflationApplied && savingsApplied) {
                ChipButton(title: "Beide gebruiken", symbol: "checkmark.circle") {
                    useBoth(inflation: both.inflation.value, savings: both.savings.value)
                }
            }

            if let last = store.data.settings.lastMarketUpdate {
                LabeledContent("Laatst bijgewerkt", value: Fmt.dateTime(last))
            } else {
                Text("Nog niet bijgewerkt")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Cijfers van internet")
        } footer: {
            Text("Inflatie komt van de Wereldbank (laatst bekende jaar). De spaarrente is de depositorente van de Europese Centrale Bank: een richtpunt, want banken geven vaak iets minder. Een opgehaald cijfer wordt pas gebruikt als je op 'Gebruik' tikt.")
        }
    }

    @ViewBuilder
    private func results(for load: MarketLoad, applied: Bool, onApply: @escaping (Double) -> Void) -> some View {
        switch load {
        case .loaded(let reading):
            MarketReadingCard(reading: reading, actionTitle: "Gebruik", applied: applied) {
                onApply(reading.value)
            }
        case .failed(let message):
            MarketErrorText(message: message)
        case .idle, .loading:
            EmptyView()
        }
    }

    // MARK: Ophalen

    @MainActor
    private func loadInflation() async {
        inflation = .loading
        inflationApplied = false
        let market = store.market
        do {
            let reading = try await market.fetchInflation()
            inflation = .loaded(reading)
        } catch is CancellationError {
            inflation = .idle
        } catch {
            inflation = .failed(marketErrorMessage(error))
        }
    }

    @MainActor
    private func loadSavings() async {
        savings = .loading
        savingsApplied = false
        let market = store.market
        do {
            let reading = try await market.fetchSavingsBenchmarkRate()
            savings = .loaded(reading)
        } catch is CancellationError {
            savings = .idle
        } catch {
            savings = .failed(marketErrorMessage(error))
        }
    }

    // MARK: Overnemen

    @MainActor
    private func useInflation(_ value: Double) {
        store.mutate {
            $0.settings.inflation = value
            $0.settings.lastMarketUpdate = Date()
        }
        inflationApplied = true
    }

    @MainActor
    private func useSavings(_ value: Double) {
        store.mutate {
            $0.settings.savingsRate = value
            $0.settings.lastMarketUpdate = Date()
        }
        savingsApplied = true
    }

    @MainActor
    private func useBoth(inflation inflationValue: Double, savings savingsValue: Double) {
        store.mutate {
            $0.settings.inflation = inflationValue
            $0.settings.savingsRate = savingsValue
            $0.settings.lastMarketUpdate = Date()
        }
        inflationApplied = true
        savingsApplied = true
    }
}
