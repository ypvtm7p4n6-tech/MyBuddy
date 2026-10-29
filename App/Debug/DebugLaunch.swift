#if DEBUG
import Foundation

/// Alleen voor ontwikkelaars (debug-builds): start de app met voorbeelddata en opent direct een pagina,
/// zodat CI screenshots kan maken. Voorbeelden:
/// `-mybuddy-demo -mybuddy-tab library -mybuddy-open income`
/// `-mybuddy-demo -mybuddy-open pot0` (gaat rechtstreeks naar de pagina, in de Bibliotheek met het ouderpad)
/// `-mybuddy-demo -mybuddy-open flow` (Maandoverzicht), `-mybuddy-open tools` (Hulpmiddelen)
/// `-mybuddy-demo -mybuddy-hero 1` (Home opent op hero-kaart 0, 1 of 2: Nog te verdelen, Vermogen, Saldo vandaag)
/// `-mybuddy-demo -mybuddy-order home` (opent het blad "Volgorde aanpassen" van Home)
/// `-mybuddy-demo -mybuddy-settings` (pusht Instellingen op de huidige stapel; op de Mac het Settings-venster)
/// `-mybuddy-demo -mybuddy-demo-holding only-invested` (een belegging zonder waarde-updates, zie `DemoHoldingScenario`)
/// `-mybuddy-demo -mybuddy-scroll-to <sectiekop>` (een lijstpagina scrolt naar die sectie)
/// Tabs: home, library, search. De oude namen werken nog als alias: overview wordt home; month, saving, planning, savings en
/// tools worden library; settings is geen tab meer (gebruik `-mybuddy-settings`).
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

    /// De hero-kaart waar Home op opent (`-mybuddy-hero 0|1|2`), of nil. Home (`HomeTab`) leest dit voor zijn eerste selectie.
    static var heroIndex: Int? {
        guard let raw = value(for: "-mybuddy-hero"), let index = Int(raw), (0...2).contains(index) else { return nil }
        return index
    }

    /// Het scenario voor een belegging zonder waarde-updates (`-mybuddy-demo-holding`), of nil.
    static var demoHolding: DemoHoldingScenario? {
        guard let raw = value(for: "-mybuddy-demo-holding") else { return nil }
        return DemoHoldingScenario(rawValue: raw)
    }

    static func value(for key: String) -> String? {
        guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// De tab bij een naam op de opdrachtregel: de drie tabs en de oude namen als alias (overview is home; month, saving, planning,
    /// savings en tools zijn de Bibliotheek).
    static func tab(named name: String) -> AppTab? {
        if let tab = AppTab(rawValue: name) { return tab }
        switch name {
        case "overview": return .home
        case "month", "saving", "planning", "savings", "tools": return .library
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
            // Met een tab erbij: de pagina komt op het pad van die tab (de eerste pagina op een lege stapel).
            router.select(chosenTab)
            if let chosenPage { router.open(chosenPage) }
        } else if let chosenPage {
            // Zonder tab: rechtstreeks naar de pagina, in de Bibliotheek en met het ouderpad.
            router.go(chosenPage)
        }
        if arguments.contains("-mybuddy-settings") {
            // iPhone en iPad: Instellingen op de stapel van de huidige tab; Mac: het Settings-venster.
            router.go(.settingsRoot)
        }
    }

    /// De pagina bij een naam voor `-mybuddy-order`: alleen Home heeft een volgorde om aan te passen (`overview`, met `home` als
    /// alias). Een andere naam geeft nil.
    private static func blockPage(named name: String) -> BlockPage? {
        BlockPage(rawValue: name == "home" ? "overview" : name)
    }

    @MainActor
    private static func destination(named name: String, store: AppStore) -> Destination? {
        let d = store.data
        switch name {
        case "overview", "home": return .home
        case "library": return .library
        case "flow": return .flow
        case "tools": return .tools
        case "settings": return .settingsRoot
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
        case "startdate": return .settings(.startDate)
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
