import SwiftUI

/// De pagina Koersen (`.settings(.prices)`): automatisch ophalen, nu vernieuwen en, onder "Geavanceerd", de koersverbinding testen.
struct PricesPage: View {
    @Environment(AppStore.self) private var store
    @State private var diagnostics: [String] = []
    @State private var isTesting = false
    @State private var successCount = 0
    @State private var failureCount = 0

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: keyPath] },
                set: { value in store.mutate { $0.settings[keyPath: keyPath] = value } })
    }

    var body: some View {
        ListScaffold(title: "Koersen") {
            pricesSection
            advancedSection
        }
        .sensoryFeedback(.success, trigger: successCount)
        .sensoryFeedback(.error, trigger: failureCount)
    }

    // MARK: Koersen

    private var pricesSection: some View {
        Section {
            Toggle("Koersen automatisch ophalen", isOn: setting(\.autoRefreshPrices))
                .frame(minHeight: Theme.minTapTarget)
            refreshRow
            if let last = store.lastPriceRefresh {
                LabeledContent("Laatst bijgewerkt", value: Fmt.dateTime(last))
            }
            if let message = store.priceMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
            }
        } header: {
            SectionHeader("Koersen")
        } footer: {
            SettingsFootnote("Koersen komen van Yahoo Finance, met Stooq en CoinGecko als reserve. Het zijn gratis, onofficiële bronnen: gebruik de cijfers als indicatie.")
        }
    }

    private var refreshRow: some View {
        Button {
            Task { @MainActor in
                await store.refreshPrices(force: true)
                if store.priceMessage == nil {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
        } label: {
            HStack {
                Label("Nu vernieuwen", systemImage: "arrow.clockwise")
                Spacer(minLength: 8)
                if store.isRefreshingPrices {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .disabled(store.isRefreshingPrices)
    }

    // MARK: Geavanceerd

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Geavanceerd") {
                testRow
                ForEach(diagnostics, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var testRow: some View {
        Button {
            isTesting = true
            Task { @MainActor in
                diagnostics = await QuoteDiagnostics.run()
                isTesting = false
            }
        } label: {
            HStack {
                Label("Koersverbinding testen", systemImage: "network")
                Spacer(minLength: 8)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .disabled(isTesting)
    }
}
