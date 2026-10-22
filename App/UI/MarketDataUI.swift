import SwiftUI

// "Actuele cijfers" op de pagina Rekenen: inflatie en spaarrente van internet. Een knop haalt ze allebei op, elk cijfer heeft
// een eigen rij met "Gebruik", en "Beide gebruiken" neemt ze samen over. Een opgehaald cijfer wordt pas gebruikt als je dat kiest.

// MARK: - Toestand van een cijfer

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

// MARK: - Rijen

/// Een opgehaald cijfer met uitleg, bron en een knop om het over te nemen.
private struct MarketReadingRow: View {
    let title: String
    let reading: RateReading
    let applied: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmountRow(title: title,
                      value: Fmt.percent(reading.value, digits: 2),
                      detail: "\(reading.label). Bron: \(reading.source).")
            ActionButton(title: applied ? "Overgenomen" : "Gebruik",
                         symbol: applied ? "checkmark" : "arrow.down.circle") {
                onApply()
            }
        }
        .padding(.vertical, 4)
    }
}

/// De mislukte poging van een cijfer: symbool en tekst, zodat de betekenis niet alleen in de kleur zit.
private struct MarketErrorRow: View {
    let title: String
    let message: String

    var body: some View {
        Label("\(title): \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(Theme.negative)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Sectie voor de pagina Rekenen

/// Rijen voor in een `List` (Rekenen): haalt inflatie en spaarrente van internet en laat de gebruiker kiezen of de waarde wordt
/// overgenomen. Levert een `Section` terug, dus alleen in een lijst gebruiken.
struct MarketDataSection: View {
    @Environment(AppStore.self) private var store
    @State private var inflation: MarketLoad = .idle
    @State private var savings: MarketLoad = .idle
    @State private var inflationApplied = false
    @State private var savingsApplied = false
    @State private var fetchCount = 0
    @State private var failureCount = 0

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
            fetchRow
            inflationResult
            savingsResult
            bothRow
            updatedRow
        } header: {
            SectionHeader("Actuele cijfers")
        } footer: {
            SettingsFootnote("Inflatie komt van de Wereldbank (laatst bekende jaar), de spaarrente van de Europese Centrale Bank. Een opgehaald cijfer wordt pas gebruikt als je 'Gebruik' kiest.")
        }
        .sensoryFeedback(.success, trigger: fetchCount)
        .sensoryFeedback(.error, trigger: failureCount)
    }

    // MARK: Onderdelen

    private var fetchRow: some View {
        Button {
            Task { @MainActor in await loadBoth() }
        } label: {
            HStack(spacing: 8) {
                Label("Ophalen", systemImage: "arrow.triangle.2.circlepath")
                Spacer(minLength: 8)
                if anyLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .disabled(anyLoading)
    }

    @ViewBuilder
    private var inflationResult: some View {
        switch inflation {
        case .loaded(let reading):
            MarketReadingRow(title: "Inflatie per jaar", reading: reading, applied: inflationApplied) {
                useInflation(reading.value)
            }
        case .failed(let message):
            MarketErrorRow(title: "Inflatie", message: message)
        case .idle, .loading:
            EmptyView()
        }
    }

    @ViewBuilder
    private var savingsResult: some View {
        switch savings {
        case .loaded(let reading):
            MarketReadingRow(title: "Spaarrente", reading: reading, applied: savingsApplied) {
                useSavings(reading.value)
            }
        case .failed(let message):
            MarketErrorRow(title: "Spaarrente", message: message)
        case .idle, .loading:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bothRow: some View {
        if let both = bothReadings, !(inflationApplied && savingsApplied) {
            ActionButton(title: "Beide gebruiken", symbol: "checkmark.circle", prominent: true) {
                useBoth(inflation: both.inflation.value, savings: both.savings.value)
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var updatedRow: some View {
        if let last = store.data.settings.lastMarketUpdate {
            LabeledContent("Laatst bijgewerkt", value: Fmt.dateTime(last))
        } else {
            Text("Nog niet bijgewerkt")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Ophalen

    @MainActor
    private func loadBoth() async {
        inflation = .loading
        savings = .loading
        inflationApplied = false
        savingsApplied = false
        let market = store.market
        do {
            let reading = try await market.fetchInflation()
            inflation = .loaded(reading)
        } catch is CancellationError {
            inflation = .idle
        } catch {
            inflation = .failed(marketErrorMessage(error))
        }
        do {
            let reading = try await market.fetchSavingsBenchmarkRate()
            savings = .loaded(reading)
        } catch is CancellationError {
            savings = .idle
        } catch {
            savings = .failed(marketErrorMessage(error))
        }
        if case .failed = inflation {
            failureCount += 1
        } else if case .failed = savings {
            failureCount += 1
        } else {
            fetchCount += 1
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
