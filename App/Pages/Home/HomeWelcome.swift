import SwiftUI

// De meldingen bovenaan Home en de lege start. De meldingen zijn dezelfde als op de oude Home (opslaan mislukt, startmelding,
// synchronisatie, "De cijfers sluiten niet"); de lege start is een welkomstkaart in plaats van hero en planken.

// MARK: - Meldingen

/// Welke meldingen er nu zijn. `HomeTab` bouwt dit één keer per `body` en laat de meldingen alleen een plek innemen als er een
/// is: een lege weergave zou anders toch ruimte tussen de onderdelen van Home laten staan.
struct HomeNoticeState {
    let startupNotice: String?
    let saveFailed: Bool
    let needsSyncAttention: Bool
    let check: LedgerCheck

    /// Is er iets te melden?
    var hasAny: Bool {
        startupNotice != nil || saveFailed || needsSyncAttention || !check.isOK
    }

    /// De toestand van nu. De dagboekhouding van de huidige maand komt van `LedgerBook`, dezelfde als op Dag voor dag.
    @MainActor
    static func current(store: AppStore, sync: SyncController?) -> HomeNoticeState {
        let book = LedgerBook(store.data, today: store.today)
        let check = LedgerCheck(book.ledger(store.now))
        // Dezelfde voorwaarden als `SyncAttentionBanner` en de stip op de profielknop.
        let attention = sync?.importOffer != nil || sync?.conflict != nil
        return HomeNoticeState(startupNotice: store.startupNotice, saveFailed: store.saveFailed,
                               needsSyncAttention: attention, check: check)
    }
}

/// De meldingen boven de hero, onder elkaar.
struct HomeNotices: View {
    let state: HomeNoticeState
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            if let notice = state.startupNotice {
                NoticeCard(text: notice, symbol: "exclamationmark.triangle.fill")
            }
            // Opslaan is mislukt: anders zie je dit pas veel later, terwijl wijzigingen verloren kunnen gaan.
            if state.saveFailed {
                NoticeCard(text: "Opslaan is mislukt. Je laatste wijzigingen zijn mogelijk niet bewaard.",
                           symbol: "exclamationmark.triangle.fill",
                           actionTitle: "Opnieuw proberen",
                           action: { store.retrySave() })
                    .transition(.opacity)
            }
            if state.needsSyncAttention {
                SyncAttentionBanner()
            }
            if !state.check.isOK {
                CashflowCheckBanner(check: state.check)
            }
        }
        .homeMargin()
        .animated(by: state.saveFailed)
    }
}

// MARK: - Lege start

/// Wat je ziet zolang er niets is ingevuld: uitleg, "Salaris instellen" (de ene vervolgstap) en "Voorbeelddata laden". Het
/// vervangt de hero en de planken. Voorbeelddata vervangt alles, ook in de cloud en op andere apparaten: eerst vragen.
struct HomeWelcome: View {
    @Environment(AppStore.self) private var store
    @State private var confirmSample = false

    var body: some View {
        HeroCard(hue: .olive, eyebrow: "Welkom bij MyBuddy", symbol: "sparkles") {
            Text("Begin met je salaris. Daarna maak je spaarpotten, voeg je beleggingen toe en verdeel je elke maand je geld.")
                .font(.body)
                .foregroundStyle(Theme.onTile)
                .fixedSize(horizontal: false, vertical: true)
        } pills: {
            PillRow {
                PillLink("Salaris instellen", symbol: "eurosign.circle", style: .onTile, destination: .salary,
                         showsCurrentMonth: true)
                PillButton("Voorbeelddata laden", symbol: "wand.and.stars", style: .onTile) {
                    confirmSample = true
                }
            }
        }
        .frame(maxWidth: Theme.readableWidth)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeMargin()
        .confirmationDialog("Voorbeelddata laden?", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("Vervang mijn gegevens door voorbeelddata", role: .destructive) {
                store.loadSampleData()
            }
        } message: {
            if FirebaseConfig.isConfigured {
                Text("Je huidige gegevens worden vervangen, ook in de cloud en op je andere apparaten.")
            } else {
                Text("Je huidige gegevens worden vervangen.")
            }
        }
    }
}
