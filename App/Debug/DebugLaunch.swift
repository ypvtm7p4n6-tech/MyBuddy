#if DEBUG
import Foundation

/// Alleen voor ontwikkelaars (debug-builds): start de app met voorbeelddata en opent direct een pagina,
/// zodat CI screenshots kan maken. Voorbeelden:
/// `-mybuddy-demo -mybuddy-tab month -mybuddy-open income`
/// `-mybuddy-demo -mybuddy-open pot0` (gaat rechtstreeks naar de pagina, met de goede tab en het ouderpad)
/// `-mybuddy-demo -mybuddy-tab planning -mybuddy-open purchase`
/// `-mybuddy-demo -mybuddy-order month` (opent het blad "Volgorde aanpassen")
/// `-mybuddy-demo -mybuddy-settings` (tab Instellingen; op de Mac het Settings-venster)
/// `-mybuddy-demo -mybuddy-demo-holding only-invested` (een belegging zonder waarde-updates, zie `DemoHoldingScenario`)
/// `-mybuddy-demo -mybuddy-scroll-to <sectiekop>` (een lijstpagina scrolt naar die sectie)
/// Tabs: overview, month, saving, planning, settings; de oude namen home, savings en tools werken nog.
/// Pagina's: zie `destination(named:store:)`.
enum DebugLaunch {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isDemo: Bool { arguments.contains("-mybuddy-demo") }

    /// Schuift de inhoud omhoog, zodat screenshots ook lager gelegen delen van een pagina tonen.
    static var scrollOffset: Double {
        guard let raw = value(for: "-mybuddy-scroll"), let v = Double(raw) else { return 0 }
        return v
    }

    /// De kop van de sectie waar een lijstpagina naartoe scrolt (`-mybuddy-scroll-to`). `ListScaffold` leest dit.
    static var scrollTarget: String? { value(for: "-mybuddy-scroll-to") }

    /// Het scenario voor een belegging zonder waarde-updates (`-mybuddy-demo-holding`), of nil.
    static var demoHolding: DemoHoldingScenario? {
        guard let raw = value(for: "-mybuddy-demo-holding") else { return nil }
        return DemoHoldingScenario(rawValue: raw)
    }

    static func value(for key: String) -> String? {
        guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// De tab bij een naam op de opdrachtregel: de nieuwe namen en de oude (home, savings, tools).
    static func tab(named name: String) -> AppTab? {
        if let tab = AppTab(rawValue: name) { return tab }
        switch name {
        case "home": return .overview
        case "savings": return .month
        case "tools": return .planning
        default: return nil
        }
    }

    @MainActor
    static func apply(to router: Router, store: AppStore) {
        if let scenario = demoHolding { scenario.apply(to: store) }
        if let raw = value(for: "-mybuddy-period"), let mode = PeriodMode(rawValue: raw) {
            router.periodMode = mode
        }
        if let raw = value(for: "-mybuddy-order"), let page = blockPage(named: raw) {
            router.orderPage = page
        }
        let chosenTab: AppTab? = value(for: "-mybuddy-tab").flatMap { DebugLaunch.tab(named: $0) }
        let chosenPage: Destination? = value(for: "-mybuddy-open").flatMap { DebugLaunch.destination(named: $0, store: store) }
        if let chosenTab {
            // Met een tab erbij: de pagina komt op het pad van die tab (zoals voor de herbouw).
            router.select(chosenTab)
            if let chosenPage { router.paths[chosenTab] = [chosenPage] }
        } else if let chosenPage {
            // Zonder tab: rechtstreeks naar de pagina, op de goede tab en met het ouderpad.
            router.go(chosenPage)
        }
        if arguments.contains("-mybuddy-settings") {
            #if os(macOS)
            router.go(.settings(.account)) // opent het Settings-venster
            #else
            router.select(.settings)
            #endif
        }
    }

    /// De pagina bij een naam voor `-mybuddy-order`. De oude namen home, savings en tools zijn een alias voor overview,
    /// month en planning, zodra die pagina's bestaan (anders blijft het de oude pagina).
    private static func blockPage(named name: String) -> BlockPage? {
        let aliases = ["home": "overview", "savings": "month", "tools": "planning"]
        if let mapped = aliases[name], let page = BlockPage(rawValue: mapped) { return page }
        return BlockPage(rawValue: name)
    }

    @MainActor
    private static func destination(named name: String, store: AppStore) -> Destination? {
        let d = store.data
        switch name {
        case "overview": return .overview
        case "income": return .income
        case "salary": return .salary
        case "expenses": return .expenses
        case "distribute": return .distribute
        case "pots": return .pots
        case "bank": return .bank
        case "portfolio": return .portfolio
        case "projection": return .projection
        case "goals": return .goals
        case "accelerators": return .accelerators
        case "buffer": return .buffer
        case "savingsgoal": return .savingsGoal
        case "purchase": return .purchase
        case "cashflow": return .cashflow
        case "account": return .settings(.account)
        case "password": return .settings(.password)
        case "deleteaccount": return .settings(.deleteAccount)
        case "conflictbackups": return .settings(.conflictBackups)
        case "calculations", "rekenen": return .settings(.calculations)
        case "rates", "prices": return .settings(.prices)
        case "data": return .settings(.data)
        case "layout": return .settings(.layout)
        case "about": return .settings(.about)
        case "importreview": return .settings(.importReview)
        case "pot0": return d.pots.first.map { .pot($0.id) }
        case "holding0": return d.holdings.first.map { .holding($0.id) }
        case "goal0": return d.goals.first.map { .goal($0.id) }
        case "goal1": return d.goals.dropFirst().first.map { .goal($0.id) }
        default: return nil
        }
    }
}

/// Een belegging zonder waarde-updates, zoals de gebruiker die invult (`-mybuddy-demo-holding <scenario>`): het gemelde geval
/// "de grafiek bij Beleggingen doet het niet". Het scenario vervangt na de voorbeelddata alle beleggingen door een belegging
/// "Demo" (ETF, totaal ingelegd 3.000, inleg 200 per maand, belegd sinds 8 maanden geleden, geen waarde-updates). Die is
/// daarna als eerste belegging te openen (`-mybuddy-open holding0`).
enum DemoHoldingScenario: String {
    /// Alleen "Totaal ingelegd" en een inleg per maand, zonder ticker en zonder aantal.
    case onlyInvested = "only-invested"
    /// Een ticker maar geen aantal.
    case tickerNoUnits = "ticker-no-units"
    /// Een ticker en een aantal, maar er komt geen koers binnen (de demo-koersdienst meldt dan "geen internet").
    case trackedOffline = "tracked-offline"

    @MainActor
    func apply(to store: AppStore) {
        var holding = Holding(name: "Demo", startMonth: store.now.adding(-8))
        holding.kind = .etf
        holding.investedTotal = 3_000
        holding.monthlyContribution = 200
        switch self {
        case .onlyInvested:
            break
        case .tickerNoUnits:
            holding.ticker = "VWCE.DE"
        case .trackedOffline:
            holding.ticker = "VWCE.DE"
            holding.units = 12
        }
        let existing = store.data.holdings.map { $0.id }
        store.mutate { data in
            for id in existing { data.deleteHolding(id) }
            data.addHolding(holding)
            data.homeHoldingIDs = nil
        }
    }
}

/// Vaste koersen zonder netwerk, voor de demo-modus.
struct DemoQuoteService: QuoteService {
    func search(_ query: String) async throws -> [SymbolMatch] {
        [
            SymbolMatch(symbol: "VWCE.DE", name: "Vanguard FTSE All-World UCITS ETF", exchange: "XETRA", type: "ETF"),
            SymbolMatch(symbol: "IWDA.AS", name: "iShares Core MSCI World UCITS ETF", exchange: "Amsterdam", type: "ETF"),
            SymbolMatch(symbol: "BTC-EUR", name: "Bitcoin EUR", exchange: "CCC", type: "Cryptocurrency")
        ]
    }

    func quoteInEUR(symbol: String) async throws -> EuroQuote {
        // Scenario "tracked-offline": er komt geen koers binnen.
        if DebugLaunch.demoHolding == .trackedOffline { throw URLError(.notConnectedToInternet) }
        let price: Double
        switch symbol {
        case "VWCE.DE": price = 128.40
        case "BTC-EUR": price = 91_250
        default: price = 100
        }
        return EuroQuote(symbol: symbol, name: symbol, priceEUR: price, nativePrice: price, nativeCurrency: "EUR", date: Date())
    }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        let now = Date()
        return (0..<250).map { i in
            let t = Double(i)
            let value = 100 + t * 0.12 + sin(t / 9) * 3
            return PricePoint(date: now.addingTimeInterval(-Double(250 - i) * 86_400), close: value)
        }
    }
}
#endif
