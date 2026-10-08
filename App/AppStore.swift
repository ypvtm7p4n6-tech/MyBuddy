import SwiftUI
import Observation

/// Houdt alle gegevens vast, slaat ze op en haalt koersen op.
/// Alle wijzigingen lopen via `mutate`, zodat opslaan nooit vergeten wordt.
@MainActor
@Observable
final class AppStore {
    private(set) var data: FinanceData
    /// De huidige maand. Wordt vernieuwd als de app weer actief wordt.
    private(set) var now: YearMonth

    var isRefreshingPrices = false
    var lastPriceRefresh: Date?
    /// Melding over het ophalen van koersen (leeg als alles goed ging).
    var priceMessage: String?
    /// Melding bij het opstarten (bijv. een onleesbaar opslagbestand).
    var startupNotice: String?
    var saveFailed = false

    @ObservationIgnored private let storage: FinanceStorage?
    @ObservationIgnored private let quotes: any QuoteService
    @ObservationIgnored let market: any MarketDataService

    init(storage: FinanceStorage? = FinanceStorage.standard(),
         quotes: any QuoteService = QuoteServices.standard(),
         market: any MarketDataService = LiveMarketDataService()) {
        self.storage = storage
        self.quotes = quotes
        self.market = market
        let today = YearMonth.current()
        var loaded: FinanceData
        var notice: String?
        switch storage?.load() ?? .empty {
        case .loaded(let existing):
            loaded = existing
        case .empty:
            loaded = FinanceData(startMonth: today)
        case .corrupt(let backup):
            loaded = FinanceData(startMonth: today)
            if let backup {
                notice = "Je opgeslagen gegevens waren onleesbaar. Het oude bestand is bewaard als \(backup.lastPathComponent)."
            } else {
                notice = "Je opgeslagen gegevens waren onleesbaar en konden niet worden veiliggesteld."
            }
        }
        loaded.materialize(upTo: today)
        self.data = loaded
        self.now = today
        self.startupNotice = notice
    }

    // MARK: Wijzigen en opslaan

    func mutate(_ change: (inout FinanceData) -> Void) {
        var copy = data
        change(&copy)
        data = copy
        persist()
    }

    private func persist() {
        guard let storage else { return }
        do {
            try storage.save(data)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    /// Controleert of er een nieuwe maand is begonnen.
    func refreshClock() {
        let today = YearMonth.current()
        guard today != now else { return }
        now = today
        mutate { $0.materialize(upTo: today) }
    }

    // MARK: Handige afgeleide waarden

    var remainingNow: Double { data.remaining(in: now) }

    // MARK: Koersen

    var hasTrackedHoldings: Bool { data.holdings.contains { $0.hasTicker } }

    /// Haalt de koersen van alle gevolgde beleggingen op.
    func refreshPrices(force: Bool = false) async {
        guard !isRefreshingPrices else { return }
        if !force {
            if !data.settings.autoRefreshPrices { return }
            if let last = lastPriceRefresh, Date().timeIntervalSince(last) < 600 { return }
        }
        let tracked = data.holdings.filter { $0.hasTicker }
        guard !tracked.isEmpty else { return }

        isRefreshingPrices = true
        var failed: [String] = []
        var firstError: String?
        for holding in tracked {
            guard let ticker = holding.ticker?.trimmingCharacters(in: .whitespaces) else { continue }
            do {
                let quote = try await quotes.quoteInEUR(symbol: ticker)
                let id = holding.id
                mutate { $0.recordPrice(holdingID: id, price: quote.priceEUR, currency: quote.nativeCurrency, date: Date()) }
            } catch {
                failed.append(holding.name)
                if firstError == nil { firstError = error.localizedDescription }
            }
        }
        isRefreshingPrices = false
        lastPriceRefresh = Date()
        priceMessage = failed.isEmpty ? nil : "Koers ophalen mislukt voor: " + failed.joined(separator: ", ") + ". " + (firstError ?? "Controleer je internet en de ticker.")
    }

    func searchSymbols(_ query: String) async throws -> [SymbolMatch] {
        try await quotes.search(query)
    }

    func previewQuote(ticker: String) async throws -> EuroQuote {
        try await quotes.quoteInEUR(symbol: ticker.trimmingCharacters(in: .whitespaces))
    }

    func priceHistory(ticker: String, range: String, interval: String) async throws -> [PricePoint] {
        try await quotes.historyInEUR(symbol: ticker.trimmingCharacters(in: .whitespaces), range: range, interval: interval)
    }

    /// Vult de historie aan met maandkoersen van het afgelopen jaar. Geeft een melding terug.
    func backfillHistory(holdingID: UUID) async -> String {
        guard let holding = data.holding(holdingID), holding.isTracked, let ticker = holding.ticker else {
            return "Alleen mogelijk voor beleggingen met ticker en aantal."
        }
        do {
            let points = try await priceHistory(ticker: ticker, range: "1y", interval: "1mo")
            let before = holding.snapshots.count
            mutate { $0.importHistory(holdingID: holdingID, prices: points.map { (date: $0.date, price: $0.close) }) }
            let added = (data.holding(holdingID)?.snapshots.count ?? before) - before
            return added > 0 ? "\(added) meetpunten toegevoegd." : "Er waren geen oudere koersen om toe te voegen."
        } catch {
            return "Historie ophalen mislukt: \(error.localizedDescription)"
        }
    }

    // MARK: Hele dataset

    func loadSampleData() {
        var sample = FinanceData.sample()
        sample.materialize(upTo: now)
        data = sample
        persist()
        lastPriceRefresh = nil
    }

    /// Vervangt alle gegevens, bijvoorbeeld bij het importeren van een back-up.
    func replaceData(_ newData: FinanceData) {
        var restored = newData
        restored.materialize(upTo: now)
        data = restored
        persist()
        lastPriceRefresh = nil
    }

    func eraseEverything() {
        var fresh = FinanceData(startMonth: now)
        fresh.materialize(upTo: now)
        data = fresh
        persist()
        lastPriceRefresh = nil
    }
}
