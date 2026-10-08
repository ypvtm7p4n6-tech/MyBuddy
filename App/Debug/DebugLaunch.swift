#if DEBUG
import Foundation

/// Alleen voor ontwikkelaars (debug-builds): start de app met voorbeelddata en opent direct een pagina,
/// zodat CI screenshots kan maken. Voorbeeld:
/// `-mybuddy-demo -mybuddy-tab savings -mybuddy-open pot0`
enum DebugLaunch {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isDemo: Bool { arguments.contains("-mybuddy-demo") }

    static func value(for key: String) -> String? {
        guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    @MainActor
    static func apply(to router: Router, store: AppStore) {
        if let raw = value(for: "-mybuddy-period"), let mode = PeriodMode(rawValue: raw) {
            router.periodMode = mode
        }
        if arguments.contains("-mybuddy-settings") { router.showSettings = true }
        guard let tabName = value(for: "-mybuddy-tab"), let tab = AppTab(rawValue: tabName) else { return }
        router.tab = tab
        guard let name = value(for: "-mybuddy-open"), let destination = destination(named: name, store: store) else { return }
        switch tab {
        case .home: router.homePath = [destination]
        case .savings: router.savingsPath = [destination]
        case .investing: router.investPath = [destination]
        }
    }

    @MainActor
    private static func destination(named name: String, store: AppStore) -> Destination? {
        let d = store.data
        switch name {
        case "overview": return .overview
        case "income": return .income
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
        case "pot0": return d.pots.first.map { .pot($0.id) }
        case "holding0": return d.holdings.first.map { .holding($0.id) }
        case "goal0": return d.goals.first.map { .goal($0.id) }
        case "goal1": return d.goals.dropFirst().first.map { .goal($0.id) }
        default: return nil
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
