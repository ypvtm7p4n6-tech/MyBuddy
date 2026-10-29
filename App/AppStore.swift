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
    /// Wordt aangeroepen na elke lokale wijziging die is opgeslagen (voor synchronisatie met de cloud).
    /// Niet aangeroepen bij `applyRemote`, anders zou een binnenkomende wijziging meteen terugkaatsen.
    @ObservationIgnored var onDataChanged: ((FinanceData) -> Void)?

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
        // Rente die inmiddels is uitbetaald, komt nu in de spaarpot (herhaald aanroepen boekt nooit dubbel).
        _ = loaded.applyDueInterest(upTo: Date())
        loaded.compactAppliedAccelerators()
        self.data = loaded
        self.now = today
        self.startupNotice = notice
    }

    // MARK: Wijzigen en opslaan

    func mutate(_ change: (inout FinanceData) -> Void) {
        var copy = data
        change(&copy)
        guard copy != data else { return }
        copy.modifiedAt = Date()
        data = copy
        persist()
        onDataChanged?(copy)
    }

    /// Teller die oploopt zodra er iets verandert dat "nu"-bedragen beinvloedt: een nieuwe kalenderdag. Views die `today`
    /// lezen tekenen daardoor vanzelf opnieuw.
    private(set) var clockTick = 0
    @ObservationIgnored private var clockBucket = AppStore.bucket(for: Date())

    /// Vandaag, op de seconde nauwkeurig. Dagbedragen (saldo van nu) rekenen hiermee.
    var today: Date {
        _ = clockTick
        return Date()
    }

    /// De kalenderdag van `date`: tussen twee emmers veranderen de "nu"-bedragen. De rekenmotor werkt per KALENDERDAG
    /// (een geplande boeking op dag D telt mee zodra D <= vandaag, de hele dag), dus er is geen splitsing meer op 12:00:
    /// alleen een nieuwe dag verandert de bedragen van nu.
    private static func bucket(for date: Date) -> Int {
        let c = YearMonth.calendar.dateComponents([.year, .month, .day], from: date)
        return ((c.year ?? 0) * 12 + (c.month ?? 0)) * 32 + (c.day ?? 0)
    }

    /// Neemt gegevens van een ander apparaat over zonder ze meteen weer terug te sturen.
    func applyRemote(_ remote: FinanceData) {
        var incoming = remote
        incoming.materialize(upTo: now)
        incoming.compactAppliedAccelerators()
        data = incoming
        persist()
    }

    /// Probeert de gegevens nog een keer op te slaan, bijvoorbeeld na een mislukte poging.
    func retrySave() {
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
        let bucket = AppStore.bucket(for: Date())
        if bucket != clockBucket {
            clockBucket = bucket
            clockTick += 1
        }
        let today = YearMonth.current()
        guard today != now else {
            bookDueInterest()
            return
        }
        now = today
        mutate { $0.materialize(upTo: today) }
        bookDueInterest()
    }

    /// Schrijft rente bij die op of voor dit moment is uitbetaald.
    func bookDueInterest() {
        mutate { _ = $0.applyDueInterest(upTo: Date()) }
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
            return added > 0 ? "\(added) waarde-updates toegevoegd." : "Er waren geen oudere koersen om toe te voegen."
        } catch {
            return "Historie ophalen mislukt: \(error.localizedDescription)"
        }
    }

    // MARK: Hele dataset

    func loadSampleData() {
        var sample = FinanceData.sample()
        sample.materialize(upTo: now)
        sample.modifiedAt = Date()
        data = sample
        persist()
        lastPriceRefresh = nil
        onDataChanged?(sample)
    }

    /// Vervangt alle gegevens, bijvoorbeeld bij het importeren van een back-up.
    func replaceData(_ newData: FinanceData) {
        var restored = newData
        restored.materialize(upTo: now)
        restored.modifiedAt = Date()
        data = restored
        persist()
        lastPriceRefresh = nil
        onDataChanged?(restored)
    }

    func eraseEverything() {
        replaceWithFresh(FinanceData(startMonth: now))
    }

    /// Wist alles en begint opnieuw op `day`: nieuwe, lege gegevens met die startdatum (docs/work/plan.md par. 2.2). Wat dit
    /// apparaat voor dit account onthoudt (`AccountPrefs`) wist de aanroeper, zoals bij `eraseEverything()`.
    func eraseEverything(startingOn day: CalendarDay) {
        var fresh = FinanceData(startMonth: day.yearMonth)
        fresh.startDay = day
        replaceWithFresh(fresh)
    }

    private func replaceWithFresh(_ empty: FinanceData) {
        var fresh = empty
        fresh.materialize(upTo: now)
        fresh.modifiedAt = Date()
        data = fresh
        persist()
        lastPriceRefresh = nil
        onDataChanged?(fresh)
    }

    // MARK: Startdatum

    /// Zet de startdatum: alles begint op die dag. Wat ervoor valt telt niet meer mee maar blijft bewaard. De maanden vanaf de
    /// (nieuwe) startmaand worden vastgelegd, zoals bij het opstarten.
    func setStart(_ day: CalendarDay) {
        let current = now
        mutate { draft in
            draft.setStart(day)
            draft.materialize(upTo: current)
        }
    }

    /// Zet het beginsaldo op de startdag: het banksaldo (nil laat de bank met rust) en het saldo per spaarpot, beide aan het eind
    /// van die dag. Zie `FinanceData.setOpeningBalances(on:bank:pots:now:)`.
    func setOpeningBalances(on day: CalendarDay, bank: Double?, pots: [UUID: Double]) {
        mutate { $0.setOpeningBalances(on: day, bank: bank, pots: pots, now: Date()) }
    }
}
