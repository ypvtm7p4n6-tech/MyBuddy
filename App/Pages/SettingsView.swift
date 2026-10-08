import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSample = false
    @State private var confirmErase = false

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: keyPath] },
                set: { value in store.mutate { $0.settings[keyPath: keyPath] = value } })
    }

    var body: some View {
        NavigationStack {
            Form {
                AccountSection()

                Section {
                    NumberRow(title: "Inflatie per jaar", value: setting(\.inflation), unit: .percent, maxDigits: 2)
                    NumberRow(title: "Opnamepercentage", value: setting(\.defaultWithdrawalRate), unit: .percent, maxDigits: 2)
                    NumberRow(title: "Spaarrente", value: setting(\.savingsRate), unit: .percent, maxDigits: 2)
                    NumberRow(title: "Buffer op bankrekening", value: setting(\.bankBufferMonths), unit: .plain("mnd"), maxDigits: 1)
                } header: {
                    Text("Rekenen")
                } footer: {
                    Text("Inflatie gebruikt de app voor 'koopkracht van vandaag'. Het opnamepercentage is het deel van je kapitaal dat je per jaar opneemt (4% is gebruikelijk). De buffer is het aantal maanden aan uitgaven dat op je rekening blijft staan.")
                }

                MarketDataSection()

                Section {
                    Toggle("Koersen automatisch ophalen", isOn: setting(\.autoRefreshPrices))
                    Button {
                        Task { await store.refreshPrices(force: true) }
                    } label: {
                        HStack {
                            Text("Nu vernieuwen")
                            Spacer()
                            if store.isRefreshingPrices { ProgressView().controlSize(.small) }
                        }
                    }
                    if let last = store.lastPriceRefresh {
                        Text("Laatst bijgewerkt: \(Fmt.dateTime(last))").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let message = store.priceMessage {
                        Text(message).font(.footnote).foregroundStyle(Theme.negative)
                    }
                } header: {
                    Text("Koersen")
                } footer: {
                    Text("Koersen komen van Yahoo Finance. Dat is een gratis, onofficiële bron zonder garantie op beschikbaarheid of juistheid. Gebruik de cijfers als indicatie.")
                }

                BackupSection()

                Section {
                    Button("Voorbeelddata laden") { confirmSample = true }
                    Button("Alles wissen", role: .destructive) { confirmErase = true }
                    if store.saveFailed {
                        Label("Opslaan is mislukt. Controleer of er ruimte is op je apparaat.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.negative)
                    }
                } header: {
                    Text("Gegevens")
                } footer: {
                    Text("Alles wordt alleen op dit apparaat bewaard. Er is geen account en geen server.")
                }

                Section("Over") {
                    HStack {
                        Text("MyBuddy")
                        Spacer()
                        Text("Versie 1.0").foregroundStyle(.secondary)
                    }
                    Text("Een persoonlijke indicatie, geen financieel advies. Rendementen uit het verleden zijn geen garantie voor de toekomst.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background { MeshBackground() }
            .navigationTitle("Instellingen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .confirmationDialog("Voorbeelddata laden?", isPresented: $confirmSample, titleVisibility: .visible) {
                Button("Vervang mijn gegevens door voorbeelddata", role: .destructive) {
                    store.loadSampleData()
                    Task { await store.refreshPrices(force: true) }
                }
            } message: {
                Text("Je huidige gegevens worden vervangen.")
            }
            .confirmationDialog("Alles wissen?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Wis alle gegevens", role: .destructive) { store.eraseEverything() }
            } message: {
                Text("Dit kan niet ongedaan worden gemaakt.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}
