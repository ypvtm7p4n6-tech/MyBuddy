import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Types

struct SymbolMatch: Identifiable, Equatable {
    var symbol: String
    var name: String
    var exchange: String
    var type: String
    var id: String { symbol }
}

/// Koers in de eigen valuta van de notering.
struct Quote: Equatable {
    var symbol: String
    var name: String
    var price: Double
    var currency: String
    var date: Date
}

/// Koers omgerekend naar euro.
struct EuroQuote: Equatable {
    var symbol: String
    var name: String
    var priceEUR: Double
    var nativePrice: Double
    var nativeCurrency: String
    var date: Date
}

struct PricePoint: Equatable {
    var date: Date
    var close: Double
}

enum QuoteError: Error, LocalizedError {
    case badResponse
    case noData
    case http(Int)
    /// Eigen, Nederlandstalige reden van één koersbron (bijvoorbeeld "ticker niet ondersteund").
    case message(String)
    /// Alle bronnen faalden. Elke regel is "Bron: reden".
    case allFailed([String])

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Onverwacht antwoord van de koersdienst."
        case .noData: return "Geen koers gevonden voor deze ticker."
        case .http(let code): return "De koersdienst gaf foutcode \(code)."
        case .message(let text): return text
        case .allFailed(let reasons):
            if reasons.isEmpty { return "Geen koersdienst beschikbaar." }
            return "Koers ophalen mislukt. " + reasons.joined(separator: ", ")
        }
    }
}

// MARK: - Netwerk

protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    /// Eigen sessie zonder cookies en cache, zodat een eerder geweigerd verzoek niet blijft hangen.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = Self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: QuoteError.badResponse)
                    return
                }
                continuation.resume(returning: (data, http))
            }
            task.resume()
        }
    }
}

/// Bron van koersen. Standaard is dat een keten van meerdere diensten (zie `QuoteServices.standard`).
protocol QuoteService {
    func search(_ query: String) async throws -> [SymbolMatch]
    func quoteInEUR(symbol: String) async throws -> EuroQuote
    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint]
}

/// Een koersdienst met een naam, zodat foutmeldingen kunnen zeggen welke bron faalde.
protocol NamedQuoteService: QuoteService {
    var providerName: String { get }
    /// Bronnen die niet kunnen zoeken (Stooq) worden bij het zoeken overgeslagen.
    var supportsSearch: Bool { get }
}

extension NamedQuoteService {
    var supportsSearch: Bool { true }
}

// MARK: - Gedeelde hulpmiddelen

/// Verzoeken zoals een browser ze stuurt, en korte Nederlandse foutteksten.
enum QuoteHTTP {
    static let userAgents = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    ]

    /// `attempt` kiest een andere User-Agent bij een nieuwe poging.
    static func request(for url: URL, accept: String, attempt: Int = 0) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgents[abs(attempt) % userAgents.count], forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("nl-NL,nl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        return request
    }

    static func get(_ client: HTTPClient, _ url: URL,
                    accept: String = "application/json, text/plain, */*",
                    attempt: Int = 0) async throws -> Data {
        let (data, response) = try await client.data(for: request(for: url, accept: accept, attempt: attempt))
        guard (200..<300).contains(response.statusCode) else { throw QuoteError.http(response.statusCode) }
        return data
    }

    /// Een geannuleerde taak is geen reden om de volgende bron te proberen.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

/// Zet een fout om in een korte reden, bijvoorbeeld "HTTP 429 (te veel verzoeken)".
enum QuoteReason {
    static func describe(_ error: Error) -> String {
        if let quoteError = error as? QuoteError {
            switch quoteError {
            case .http(let code): return http(code)
            case .noData: return "geen data"
            case .badResponse: return "onverwacht antwoord"
            case .message(let text): return text
            case .allFailed(let reasons): return reasons.joined(separator: ", ")
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "geen internetverbinding"
            case .timedOut: return "time-out"
            case .cannotFindHost, .cannotConnectToHost: return "server niet bereikbaar"
            case .networkConnectionLost: return "verbinding verbroken"
            case .secureConnectionFailed: return "beveiligde verbinding mislukt"
            default: return "netwerkfout (code \(urlError.code.rawValue))"
            }
        }
        return error.localizedDescription
    }

    static func http(_ code: Int) -> String {
        switch code {
        case 429: return "HTTP 429 (te veel verzoeken)"
        case 403: return "HTTP 403 (geweigerd)"
        case 401: return "HTTP 401 (geen toegang)"
        case 500..<600: return "HTTP \(code) (serverfout)"
        default: return "HTTP \(code)"
        }
    }
}

/// Welke valuta mag je aannemen als de dienst er geen meldt? Alleen als het zeker is.
enum QuoteCurrency {
    private static let euroSuffixes = [".DE", ".AS", ".PA", ".MI", ".BR", ".LS", ".MC", ".HE", ".VI", ".IR", ".F", "-EUR", "EUR=X"]

    static func assumed(forSymbol symbol: String) -> String? {
        let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if euroSuffixes.contains(where: { s.hasSuffix($0) }) { return "EUR" }
        return nil
    }
}

/// Datums uit tekstbestanden (Stooq), altijd als UTC gelezen zodat het resultaat niet van de regio afhangt.
enum QuoteDates {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }

    /// "2026-10-07" en optioneel "17:36:00".
    static func parse(_ dateText: String, time timeText: String? = nil) -> Date? {
        let dateParts = dateText.split(separator: "-").compactMap { Int($0) }
        guard dateParts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = dateParts[0]
        components.month = dateParts[1]
        components.day = dateParts[2]
        components.hour = 0
        components.minute = 0
        components.second = 0
        if let timeText = timeText {
            let timeParts = timeText.split(separator: ":").compactMap { Int($0) }
            if timeParts.count >= 2 {
                components.hour = timeParts[0]
                components.minute = timeParts[1]
                components.second = timeParts.count > 2 ? timeParts[2] : 0
            }
        }
        return utcCalendar.date(from: components)
    }

    static func month(of date: Date) -> Int? {
        let c = utcCalendar.dateComponents([.year, .month], from: date)
        guard let year = c.year, let month = c.month else { return nil }
        return year * 12 + month
    }
}

/// Yahoo-bereiken ("1y", "6mo") in dagen, voor bronnen die zelf een aantal dagen willen.
enum QuoteRange {
    static func days(_ range: String) -> Int? {
        switch range.lowercased() {
        case "1d": return 1
        case "5d": return 5
        case "1mo": return 30
        case "3mo": return 90
        case "6mo": return 180
        case "1y": return 365
        case "2y": return 730
        case "5y": return 1825
        case "10y": return 3650
        default: return nil
        }
    }
}

/// Koersreeksen inkorten en uitdunnen (voor bronnen die alleen dagkoersen geven).
enum QuotePriceSeries {
    /// Houdt alleen de punten binnen `range` voor het laatste punt. Onbekend bereik laat alles staan.
    static func trim(_ points: [PricePoint], range: String) -> [PricePoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard let days = QuoteRange.days(range), let last = sorted.last else { return sorted }
        let cutoff = last.date.addingTimeInterval(-Double(days) * 86_400)
        return sorted.filter { $0.date >= cutoff }
    }

    /// Houdt per dag ("1d"), week ("1wk") of maand ("1mo") het laatste punt. Andere intervallen blijven ongemoeid.
    static func downsample(_ points: [PricePoint], interval: String) -> [PricePoint] {
        let sorted = points.sorted { $0.date < $1.date }
        let kind = interval.lowercased()
        guard kind == "1d" || kind == "1wk" || kind == "1mo" else { return sorted }

        var result: [PricePoint] = []
        var lastBucket: Int?
        for point in sorted {
            guard let key = bucket(of: point.date, kind: kind) else { continue }
            if let previous = lastBucket, previous == key {
                result[result.count - 1] = point
            } else {
                result.append(point)
                lastBucket = key
            }
        }
        return result
    }

    private static func bucket(of date: Date, kind: String) -> Int? {
        let days = date.timeIntervalSince1970 / 86_400
        switch kind {
        case "1d": return Int(days.rounded(.down))
        case "1wk": return Int(((days - 4) / 7).rounded(.down)) // 1 januari 1970 was een donderdag; weken starten op maandag
        default: return QuoteDates.month(of: date)
        }
    }
}

/// Leest tolerant: een veld met een onverwacht type wordt nil in plaats van dat het hele antwoord faalt.
private extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key), let value = Double(text) { return value }
        return nil
    }
}

// MARK: - Yahoo Finance

struct YahooQuoteService: NamedQuoteService {
    var client: HTTPClient = URLSessionHTTPClient()

    var providerName: String { "Yahoo" }

    /// Volgorde waarin de hosts voor koersen en historie worden geprobeerd.
    static let chartHosts = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
    /// Volgorde voor zoeken.
    static let searchHosts = ["query2.finance.yahoo.com", "query1.finance.yahoo.com"]

    private struct ChartData {
        var meta: YahooParser.ChartMeta
        var points: [PricePoint]
        var interval: String
    }

    private func fetch(_ url: URL, attempt: Int = 0) async throws -> Data {
        try await QuoteHTTP.get(client, url, attempt: attempt)
    }

    static func searchURL(_ query: String) -> URL? {
        searchURL(query, host: searchHosts[0])
    }

    static func searchURL(_ query: String, host: String) -> URL? {
        var comps = URLComponents(string: "https://\(host)/v1/finance/search")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: "10"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "lang", value: "nl-NL")
        ]
        return comps?.url
    }

    static func chartURL(symbol: String, range: String, interval: String) -> URL? {
        chartURL(symbol: symbol, range: range, interval: interval, host: chartHosts[0])
    }

    static func chartURL(symbol: String, range: String, interval: String, host: String) -> URL? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var comps = URLComponents(string: "https://\(host)/v8/finance/chart/\(encoded)")
        comps?.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "includePrePost", value: "false")
        ]
        return comps?.url
    }

    func search(_ query: String) async throws -> [SymbolMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }

        var firstError: Error?
        var answeredEmpty = false
        for (index, host) in Self.searchHosts.enumerated() {
            guard let url = Self.searchURL(q, host: host) else { continue }
            do {
                let matches = try YahooParser.parseSearch(try await fetch(url, attempt: index))
                if !matches.isEmpty { return matches }
                answeredEmpty = true
            } catch {
                if QuoteHTTP.isCancellation(error) { throw error }
                if firstError == nil { firstError = error }
            }
        }
        if answeredEmpty { return [] }
        throw firstError ?? QuoteError.badResponse
    }

    /// Probeert eerst alle hosts met het gevraagde bereik, daarna (alleen als de dienst wel antwoordde,
    /// maar zonder bruikbare data) de uitwijkbereiken op de eerste host.
    private func nativeChart(symbol: String, range: String, interval: String,
                             fallbacks: [(range: String, interval: String)],
                             requirePoints: Bool) async throws -> ChartData {
        var attempts: [(host: String, range: String, interval: String)] = []
        for host in Self.chartHosts {
            attempts.append((host: host, range: range, interval: interval))
        }
        let primaryCount = attempts.count
        for fallback in fallbacks {
            attempts.append((host: Self.chartHosts[0], range: fallback.range, interval: fallback.interval))
        }

        var firstError: Error?
        var serviceAnswered = false
        for (index, attempt) in attempts.enumerated() {
            if index >= primaryCount && !serviceAnswered { break }
            guard let url = Self.chartURL(symbol: symbol, range: attempt.range, interval: attempt.interval, host: attempt.host) else {
                throw QuoteError.badResponse
            }
            do {
                let parsed = try YahooParser.parseChart(try await fetch(url, attempt: index))
                let usable = requirePoints
                    ? !parsed.points.isEmpty
                    : (parsed.meta.price != nil || !parsed.points.isEmpty)
                if !usable { throw QuoteError.noData }
                return ChartData(meta: parsed.meta, points: parsed.points, interval: attempt.interval)
            } catch {
                if QuoteHTTP.isCancellation(error) { throw error }
                if error is QuoteError { serviceAnswered = true }
                if firstError == nil { firstError = error }
            }
        }
        throw firstError ?? QuoteError.badResponse
    }

    private func resolveCurrency(of chart: ChartData, symbol: String) throws -> String {
        if let reported = chart.meta.currency { return reported }
        if let assumed = QuoteCurrency.assumed(forSymbol: symbol) { return assumed }
        throw QuoteError.message("valuta onbekend voor \(symbol)")
    }

    private func quote(symbol: String) async throws -> Quote {
        let chart = try await nativeChart(symbol: symbol, range: "5d", interval: "1d",
                                          fallbacks: [(range: "1mo", interval: "1d")],
                                          requirePoints: false)
        guard let price = chart.meta.price ?? chart.points.last?.close, price > 0, price.isFinite else {
            throw QuoteError.noData
        }
        return Quote(symbol: chart.meta.symbol ?? symbol,
                     name: chart.meta.name ?? symbol,
                     price: price,
                     currency: try resolveCurrency(of: chart, symbol: symbol),
                     date: chart.meta.time ?? chart.points.last?.date ?? Date())
    }

    /// Hoeveel euro is één eenheid van `currency` waard?
    func rateToEUR(_ currency: String) async throws -> Double {
        switch currency {
        case "GBp", "GBX":
            let pound = try await rateToEUR("GBP")
            return pound / 100
        case "ZAc":
            let rand = try await rateToEUR("ZAR")
            return rand / 100
        case "ILA":
            let shekel = try await rateToEUR("ILS")
            return shekel / 100
        default:
            let code = currency.uppercased()
            if code == "EUR" { return 1 }
            let pair = try await quote(symbol: "\(code)EUR=X")
            return pair.price
        }
    }

    func quoteInEUR(symbol: String) async throws -> EuroQuote {
        let q = try await quote(symbol: symbol)
        let rate = try await rateToEUR(q.currency)
        return EuroQuote(symbol: q.symbol, name: q.name, priceEUR: q.price * rate,
                         nativePrice: q.price, nativeCurrency: q.currency, date: q.date)
    }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        var fallbacks: [(range: String, interval: String)] = []
        if interval != "1d" { fallbacks.append((range: range, interval: "1d")) }
        let chart = try await nativeChart(symbol: symbol, range: range, interval: interval,
                                          fallbacks: fallbacks, requirePoints: true)
        let rate = try await rateToEUR(try resolveCurrency(of: chart, symbol: symbol))
        var points = chart.points.map { PricePoint(date: $0.date, close: $0.close * rate) }
        // Kwam de data van het uitwijkinterval (dagkoersen), dun het dan uit tot het gevraagde interval.
        if chart.interval != interval {
            points = QuotePriceSeries.downsample(points, interval: interval)
        }
        return points
    }
}

// MARK: - Parser (los, zodat het zonder netwerk te testen is)

enum YahooParser {
    struct ChartMeta: Equatable {
        var symbol: String?
        var currency: String?
        var price: Double?
        var time: Date?
        var name: String?
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let symbol: String?
            let shortname: String?
            let longname: String?
            let exchDisp: String?
            let quoteType: String?
            let typeDisp: String?

            private enum CodingKeys: String, CodingKey {
                case symbol, shortname, longname, exchDisp, quoteType, typeDisp
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                symbol = c.lenientString(.symbol)
                shortname = c.lenientString(.shortname)
                longname = c.lenientString(.longname)
                exchDisp = c.lenientString(.exchDisp)
                quoteType = c.lenientString(.quoteType)
                typeDisp = c.lenientString(.typeDisp)
            }
        }
        let quotes: [Item]?
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable {
            let result: [ChartResult]?
            let error: APIError?
        }
        struct APIError: Decodable {
            let code: String?
            let description: String?
        }
        struct ChartResult: Decodable {
            let meta: Meta
            let timestamp: [Double?]?
            let indicators: Indicators?
        }
        struct Meta: Decodable {
            let currency: String?
            let symbol: String?
            let regularMarketPrice: Double?
            let regularMarketTime: Double?
            let longName: String?
            let shortName: String?

            private enum CodingKeys: String, CodingKey {
                case currency, symbol, regularMarketPrice, regularMarketTime, longName, shortName
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                currency = c.lenientString(.currency)
                symbol = c.lenientString(.symbol)
                regularMarketPrice = c.lenientDouble(.regularMarketPrice)
                regularMarketTime = c.lenientDouble(.regularMarketTime)
                longName = c.lenientString(.longName)
                shortName = c.lenientString(.shortName)
            }
        }
        struct Indicators: Decodable {
            let quote: [Series]?
            let adjclose: [AdjustedSeries]?
        }
        struct Series: Decodable {
            let close: [Double?]?
        }
        struct AdjustedSeries: Decodable {
            let adjclose: [Double?]?
        }
        let chart: Chart
    }

    static func parseSearch(_ data: Data) throws -> [SymbolMatch] {
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw QuoteError.badResponse
        }
        return (response.quotes ?? []).compactMap { item in
            guard let symbol = item.symbol, !symbol.isEmpty else { return nil }
            return SymbolMatch(symbol: symbol,
                               name: item.longname ?? item.shortname ?? symbol,
                               exchange: item.exchDisp ?? "",
                               type: item.typeDisp ?? item.quoteType ?? "")
        }
    }

    static func parseChart(_ data: Data) throws -> (meta: ChartMeta, points: [PricePoint]) {
        let response: ChartResponse
        do {
            response = try JSONDecoder().decode(ChartResponse.self, from: data)
        } catch {
            throw QuoteError.badResponse
        }
        guard let result = response.chart.result?.first else {
            if response.chart.error != nil { throw QuoteError.noData }
            throw QuoteError.badResponse
        }
        var currency = result.meta.currency?.trimmingCharacters(in: .whitespaces)
        if currency?.isEmpty == true { currency = nil }
        let meta = ChartMeta(symbol: result.meta.symbol,
                             currency: currency,
                             price: result.meta.regularMarketPrice,
                             time: result.meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) },
                             name: result.meta.longName ?? result.meta.shortName)
        var points: [PricePoint] = []
        let stamps = result.timestamp ?? []
        var closes = result.indicators?.quote?.first?.close ?? []
        if closes.isEmpty {
            closes = result.indicators?.adjclose?.first?.adjclose ?? []
        }
        for (i, stamp) in stamps.enumerated() where i < closes.count {
            if let stamp = stamp, let close = closes[i], close.isFinite {
                points.append(PricePoint(date: Date(timeIntervalSince1970: stamp), close: close))
            }
        }
        return (meta, points)
    }
}

// MARK: - Stooq (gratis dagkoersen als tweede bron)

struct StooqQuoteService: NamedQuoteService {
    var client: HTTPClient = URLSessionHTTPClient()

    var providerName: String { "Stooq" }
    var supportsSearch: Bool { false }

    private static let accept = "text/csv,text/plain;q=0.9,*/*;q=0.8"

    static func quoteURL(code: String) -> URL? {
        guard StooqSymbol.isSafeCode(code) else { return nil }
        return URL(string: "https://stooq.com/q/l/?s=\(code)&f=sd2t2ohlcv&h&e=csv")
    }

    static func historyURL(code: String) -> URL? {
        guard StooqSymbol.isSafeCode(code) else { return nil }
        return URL(string: "https://stooq.com/q/d/l/?s=\(code)&i=d")
    }

    /// Stooq kan niet zoeken.
    func search(_ query: String) async throws -> [SymbolMatch] {
        []
    }

    private func fetchRow(code: String) async throws -> StooqParser.Row {
        guard let url = Self.quoteURL(code: code) else { throw QuoteError.badResponse }
        return try StooqParser.parseQuote(try await QuoteHTTP.get(client, url, accept: Self.accept))
    }

    func quoteInEUR(symbol: String) async throws -> EuroQuote {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mapped = StooqSymbol.map(trimmed) else { throw QuoteError.message("ticker niet ondersteund") }
        let row = try await fetchRow(code: mapped.code)
        let rate: Double
        switch mapped.currency {
        case "EUR": rate = 1
        case "USD": rate = try await fetchRow(code: "usdeur").close
        default: throw QuoteError.message("valuta niet ondersteund")
        }
        guard rate > 0, rate.isFinite else { throw QuoteError.noData }
        return EuroQuote(symbol: trimmed.uppercased(), name: trimmed.uppercased(),
                         priceEUR: row.close * rate, nativePrice: row.close,
                         nativeCurrency: mapped.currency, date: row.date)
    }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mapped = StooqSymbol.map(trimmed) else { throw QuoteError.message("ticker niet ondersteund") }
        guard let url = Self.historyURL(code: mapped.code) else { throw QuoteError.badResponse }
        let all = try StooqParser.parseHistory(try await QuoteHTTP.get(client, url, accept: Self.accept))
        let trimmedRange = QuotePriceSeries.trim(all, range: range)
        let points = QuotePriceSeries.downsample(trimmedRange, interval: interval)
        guard !points.isEmpty else { throw QuoteError.noData }
        switch mapped.currency {
        case "EUR":
            return points
        case "USD":
            let rate = try await fetchRow(code: "usdeur").close
            guard rate > 0, rate.isFinite else { throw QuoteError.noData }
            return points.map { PricePoint(date: $0.date, close: $0.close * rate) }
        default:
            throw QuoteError.message("valuta niet ondersteund")
        }
    }
}

/// Vertaalt een ticker (Yahoo-stijl) naar een Stooq-code, alleen als de valuta zeker is.
enum StooqSymbol {
    struct Mapped: Equatable {
        var code: String
        var currency: String
    }

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")

    /// Yahoo- of Stooq-achtervoegsel naar Stooq-achtervoegsel. Alles hier noteert in euro.
    private static let euroSuffixes: [String: String] = [
        "de": "de", "nl": "nl", "as": "nl", "fr": "fr", "pa": "fr",
        "it": "it", "mi": "it", "br": "be", "ls": "pt", "pt": "pt", "es": "es", "mc": "es"
    ]

    /// Tickers als BTC-EUR of BTC-USD zijn crypto of wisselkoersen: die kent Stooq niet op deze manier.
    private static let quoteCurrencies: Set<String> = ["eur", "usd", "usdt", "gbp", "btc", "eth", "jpy", "chf", "cad", "aud"]

    static func isSafeCode(_ code: String) -> Bool {
        !code.isEmpty && code.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func map(_ symbol: String) -> Mapped? {
        let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isSafeCode(s), !s.hasPrefix("."), !s.hasSuffix("."), !s.hasPrefix("-") else { return nil }
        if let dash = s.lastIndex(of: "-") {
            let tail = String(s[s.index(after: dash)...])
            if quoteCurrencies.contains(tail) { return nil }
        }
        guard let dot = s.lastIndex(of: ".") else {
            return Mapped(code: s + ".us", currency: "USD")
        }
        let base = String(s[s.startIndex..<dot])
        let suffix = String(s[s.index(after: dot)...])
        guard !base.isEmpty, !suffix.isEmpty else { return nil }
        if suffix == "us" { return Mapped(code: base + ".us", currency: "USD") }
        if let stooqSuffix = euroSuffixes[suffix] { return Mapped(code: base + "." + stooqSuffix, currency: "EUR") }
        return nil
    }
}

enum StooqParser {
    struct Row: Equatable {
        var symbol: String
        var date: Date
        var close: Double
    }

    /// Zoekt de kolommen via de koprij; zonder koprij geldt de volgorde van `f=sd2t2ohlcv`.
    static func parseQuote(_ data: Data) throws -> Row {
        let all = try lines(from: data)
        var columns: [String: Int] = [:]
        var body = all
        if let first = all.first, isHeader(first) {
            for (index, name) in fields(first).enumerated() {
                columns[name.lowercased()] = index
            }
            body = Array(all.dropFirst())
        }
        guard let line = body.first else { throw QuoteError.noData }
        let cells = fields(line)
        let symbolIndex = columns["symbol"] ?? 0
        let dateIndex = columns["date"] ?? 1
        let timeIndex = columns["time"] ?? 2
        let closeIndex = columns["close"] ?? 6
        guard closeIndex < cells.count, let close = Double(cells[closeIndex]), close.isFinite, close > 0 else {
            throw QuoteError.noData
        }
        let dateText = dateIndex < cells.count ? cells[dateIndex] : ""
        let timeText: String? = timeIndex < cells.count ? cells[timeIndex] : nil
        let date = QuoteDates.parse(dateText, time: timeText) ?? QuoteDates.parse(dateText) ?? Date()
        let symbol = symbolIndex < cells.count ? cells[symbolIndex] : ""
        return Row(symbol: symbol, date: date, close: close)
    }

    /// Dagkoersen (Date,Open,High,Low,Close,Volume). Regels met "N/D" worden overgeslagen.
    static func parseHistory(_ data: Data) throws -> [PricePoint] {
        let all = try lines(from: data)
        var dateIndex = 0
        var closeIndex = 4
        var body = all
        if let first = all.first, isHeader(first) {
            let names = fields(first).map { $0.lowercased() }
            if let found = names.firstIndex(of: "date") { dateIndex = found }
            if let found = names.firstIndex(of: "close") { closeIndex = found }
            body = Array(all.dropFirst())
        }
        var points: [PricePoint] = []
        for line in body {
            let cells = fields(line)
            guard dateIndex < cells.count, closeIndex < cells.count,
                  let date = QuoteDates.parse(cells[dateIndex]),
                  let close = Double(cells[closeIndex]), close.isFinite, close > 0 else { continue }
            points.append(PricePoint(date: date, close: close))
        }
        guard !points.isEmpty else { throw QuoteError.noData }
        return points.sorted { $0.date < $1.date }
    }

    private static func lines(from data: Data) throws -> [String] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw QuoteError.badResponse
        }
        text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lower = text.lowercased()
        if lower.contains("daily hits limit") || lower.contains("przekroczony dzienny limit") {
            throw QuoteError.message("dagelijkse limiet van Stooq bereikt")
        }
        let rows = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = rows.first else { throw QuoteError.noData }
        if first.hasPrefix("<") { throw QuoteError.badResponse }
        if first.lowercased().hasPrefix("no data") { throw QuoteError.noData }
        return rows
    }

    private static func isHeader(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("close") || lower.hasPrefix("symbol,") || lower.hasPrefix("date,")
    }

    private static func fields(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
        }
    }
}

// MARK: - CoinGecko (crypto)

struct QuoteCoin: Equatable {
    var id: String
    var name: String
}

struct CoinGeckoQuoteService: NamedQuoteService {
    var client: HTTPClient = URLSessionHTTPClient()

    var providerName: String { "CoinGecko" }

    /// Ticker-symbool (zonder -EUR) naar CoinGecko-id, voor de grootste munten. Andere munten worden gezocht.
    static let knownCoins: [String: QuoteCoin] = [
        "BTC": QuoteCoin(id: "bitcoin", name: "Bitcoin"),
        "ETH": QuoteCoin(id: "ethereum", name: "Ethereum"),
        "USDT": QuoteCoin(id: "tether", name: "Tether"),
        "BNB": QuoteCoin(id: "binancecoin", name: "BNB"),
        "XRP": QuoteCoin(id: "ripple", name: "XRP"),
        "SOL": QuoteCoin(id: "solana", name: "Solana"),
        "USDC": QuoteCoin(id: "usd-coin", name: "USDC"),
        "ADA": QuoteCoin(id: "cardano", name: "Cardano"),
        "DOGE": QuoteCoin(id: "dogecoin", name: "Dogecoin"),
        "TRX": QuoteCoin(id: "tron", name: "TRON"),
        "DOT": QuoteCoin(id: "polkadot", name: "Polkadot"),
        "LTC": QuoteCoin(id: "litecoin", name: "Litecoin"),
        "AVAX": QuoteCoin(id: "avalanche-2", name: "Avalanche"),
        "LINK": QuoteCoin(id: "chainlink", name: "Chainlink"),
        "XLM": QuoteCoin(id: "stellar", name: "Stellar"),
        "BCH": QuoteCoin(id: "bitcoin-cash", name: "Bitcoin Cash"),
        "XMR": QuoteCoin(id: "monero", name: "Monero"),
        "ATOM": QuoteCoin(id: "cosmos", name: "Cosmos")
    ]

    private static let supportedQuoteCurrencies = ["EUR", "USD", "GBP", "USDT"]
    private static let notCryptoText = "geen crypto-ticker (bijv. BTC-EUR)"

    /// "BTC-EUR" wordt (base: "BTC", quote: "EUR"). Alles wat geen crypto-paar lijkt geeft nil.
    static func parseTicker(_ symbol: String) -> (base: String, quote: String)? {
        let parts = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .split(separator: "-")
            .map { String($0) }
        guard parts.count == 2, supportedQuoteCurrencies.contains(parts[1]) else { return nil }
        let base = parts[0]
        guard !base.isEmpty, base.count <= 10, base.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return (base: base, quote: parts[1])
    }

    static func priceURL(id: String) -> URL? {
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")
        comps?.queryItems = [
            URLQueryItem(name: "ids", value: id),
            URLQueryItem(name: "vs_currencies", value: "eur"),
            URLQueryItem(name: "include_last_updated_at", value: "true")
        ]
        return comps?.url
    }

    static func historyURL(id: String, days: Int) -> URL? {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(encoded)/market_chart")
        comps?.queryItems = [
            URLQueryItem(name: "vs_currency", value: "eur"),
            URLQueryItem(name: "days", value: String(days))
        ]
        return comps?.url
    }

    static func searchURL(_ query: String) -> URL? {
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/search")
        comps?.queryItems = [URLQueryItem(name: "query", value: query)]
        return comps?.url
    }

    private func fetch(_ url: URL) async throws -> Data {
        try await QuoteHTTP.get(client, url, accept: "application/json")
    }

    private func resolveCoin(_ base: String) async throws -> QuoteCoin {
        if let known = Self.knownCoins[base] { return known }
        guard let url = Self.searchURL(base) else { throw QuoteError.badResponse }
        let coins = try CoinGeckoParser.parseSearch(try await fetch(url))
        let matching = coins.filter { $0.symbol == base }
        guard let best = matching.min(by: { ($0.rank ?? Int.max) < ($1.rank ?? Int.max) }) else {
            throw QuoteError.message("onbekende munt \(base)")
        }
        return QuoteCoin(id: best.id, name: best.name)
    }

    func search(_ query: String) async throws -> [SymbolMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let url = Self.searchURL(q) else { return [] }
        let coins = try CoinGeckoParser.parseSearch(try await fetch(url))
        var seen = Set<String>()
        var matches: [SymbolMatch] = []
        for coin in coins {
            guard !coin.symbol.isEmpty, seen.insert(coin.symbol).inserted else { continue }
            matches.append(SymbolMatch(symbol: coin.symbol + "-EUR", name: coin.name,
                                       exchange: "CoinGecko", type: "Cryptocurrency"))
            if matches.count >= 10 { break }
        }
        return matches
    }

    func quoteInEUR(symbol: String) async throws -> EuroQuote {
        guard let pair = Self.parseTicker(symbol) else { throw QuoteError.message(Self.notCryptoText) }
        let coin = try await resolveCoin(pair.base)
        guard let url = Self.priceURL(id: coin.id) else { throw QuoteError.badResponse }
        let reading = try CoinGeckoParser.parsePrice(try await fetch(url), id: coin.id)
        return EuroQuote(symbol: pair.base + "-" + pair.quote, name: coin.name,
                         priceEUR: reading.price, nativePrice: reading.price, nativeCurrency: "EUR",
                         date: reading.date ?? Date())
    }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        guard let pair = Self.parseTicker(symbol) else { throw QuoteError.message(Self.notCryptoText) }
        let coin = try await resolveCoin(pair.base)
        // De gratis API geeft hooguit 365 dagen.
        let days = min(max(QuoteRange.days(range) ?? 365, 1), 365)
        guard let url = Self.historyURL(id: coin.id, days: days) else { throw QuoteError.badResponse }
        let points = try CoinGeckoParser.parseHistory(try await fetch(url))
        let thinned = QuotePriceSeries.downsample(points, interval: interval)
        guard !thinned.isEmpty else { throw QuoteError.noData }
        return thinned
    }
}

enum CoinGeckoParser {
    struct Coin: Equatable {
        var id: String
        var name: String
        /// Hoofdletters, zonder -EUR.
        var symbol: String
        var rank: Int?
    }

    struct PriceReading: Equatable {
        var price: Double
        var date: Date?
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let id: String?
            let name: String?
            let symbol: String?
            let rank: Int?

            private enum CodingKeys: String, CodingKey {
                case id, name, symbol
                case rank = "market_cap_rank"
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = c.lenientString(.id)
                name = c.lenientString(.name)
                symbol = c.lenientString(.symbol)
                if let value = try? c.decode(Int.self, forKey: .rank) {
                    rank = value
                } else {
                    rank = nil
                }
            }
        }
        let coins: [Item]?
    }

    private struct MarketChart: Decodable {
        let prices: [[Double?]]?
    }

    static func parseSearch(_ data: Data) throws -> [Coin] {
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw QuoteError.badResponse
        }
        return (response.coins ?? []).compactMap { item in
            guard let id = item.id, !id.isEmpty, let symbol = item.symbol, !symbol.isEmpty else { return nil }
            return Coin(id: id, name: item.name ?? symbol, symbol: symbol.uppercased(), rank: item.rank)
        }
    }

    /// Antwoord van simple/price: {"bitcoin":{"eur":91250.5,"last_updated_at":1700000000}}
    static func parsePrice(_ data: Data, id: String) throws -> PriceReading {
        let table: [String: [String: Double]]
        do {
            table = try JSONDecoder().decode([String: [String: Double]].self, from: data)
        } catch {
            throw QuoteError.badResponse
        }
        guard let entry = table[id], let price = entry["eur"], price > 0, price.isFinite else {
            throw QuoteError.noData
        }
        let date = entry["last_updated_at"].map { Date(timeIntervalSince1970: $0) }
        return PriceReading(price: price, date: date)
    }

    /// Antwoord van market_chart: {"prices":[[1700000000000,35000.5],...]} (tijd in milliseconden).
    static func parseHistory(_ data: Data) throws -> [PricePoint] {
        let chart: MarketChart
        do {
            chart = try JSONDecoder().decode(MarketChart.self, from: data)
        } catch {
            throw QuoteError.badResponse
        }
        var points: [PricePoint] = []
        for pair in chart.prices ?? [] where pair.count >= 2 {
            if let millis = pair[0], let price = pair[1], price.isFinite, price > 0 {
                points.append(PricePoint(date: Date(timeIntervalSince1970: millis / 1000), close: price))
            }
        }
        guard !points.isEmpty else { throw QuoteError.noData }
        return points.sorted { $0.date < $1.date }
    }
}

// MARK: - Keten van bronnen

/// Probeert de bronnen op volgorde. Slaagt er geen, dan komt er één `QuoteError.allFailed`
/// met per bron de reden, zodat te zien is waar het misging.
struct FallbackQuoteService: QuoteService {
    struct Provider {
        var name: String
        var service: QuoteService
    }

    let providers: [Provider]

    /// Namen komen uit `NamedQuoteService`; anders "Bron 1", "Bron 2", ...
    init(_ services: [QuoteService]) {
        var list: [Provider] = []
        for (index, service) in services.enumerated() {
            let name = (service as? NamedQuoteService)?.providerName ?? "Bron \(index + 1)"
            list.append(Provider(name: name, service: service))
        }
        providers = list
    }

    init(providers: [Provider]) {
        self.providers = providers
    }

    private func firstSuccess<T>(_ operation: (QuoteService) async throws -> T) async throws -> T {
        var failures: [String] = []
        for provider in providers {
            do {
                return try await operation(provider.service)
            } catch {
                if QuoteHTTP.isCancellation(error) { throw error }
                failures.append("\(provider.name): \(QuoteReason.describe(error))")
            }
        }
        throw QuoteError.allFailed(failures)
    }

    func quoteInEUR(symbol: String) async throws -> EuroQuote {
        try await firstSuccess { (service: QuoteService) async throws -> EuroQuote in
            try await service.quoteInEUR(symbol: symbol)
        }
    }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        try await firstSuccess { (service: QuoteService) async throws -> [PricePoint] in
            let points = try await service.historyInEUR(symbol: symbol, range: range, interval: interval)
            if points.isEmpty { throw QuoteError.noData }
            return points
        }
    }

    /// Eerste bron met resultaten wint. Zonder resultaat maar met een mislukte bron volgt een fout,
    /// zodat een storing niet als "niets gevonden" verschijnt.
    func search(_ query: String) async throws -> [SymbolMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        var failures: [String] = []
        for provider in providers {
            if let named = provider.service as? NamedQuoteService, !named.supportsSearch { continue }
            do {
                let matches = try await provider.service.search(q)
                if !matches.isEmpty { return matches }
            } catch {
                if QuoteHTTP.isCancellation(error) { throw error }
                failures.append("\(provider.name): \(QuoteReason.describe(error))")
            }
        }
        if failures.isEmpty { return [] }
        throw QuoteError.allFailed(failures)
    }
}

enum QuoteServices {
    /// De ketting die de app standaard gebruikt: Yahoo, dan Stooq, dan CoinGecko.
    static func standard(client: HTTPClient = URLSessionHTTPClient()) -> QuoteService {
        FallbackQuoteService([
            YahooQuoteService(client: client),
            StooqQuoteService(client: client),
            CoinGeckoQuoteService(client: client)
        ])
    }
}

// MARK: - Zelftest

enum QuoteDiagnostics {
    static let symbols = ["VWCE.DE", "AAPL", "BTC-EUR"]

    /// Test elke bron los met elke testticker. Regels als "Yahoo • VWCE.DE • OK €128,40"
    /// of "Stooq • AAPL • mislukt: HTTP 404".
    static func run(client: HTTPClient = URLSessionHTTPClient()) async -> [String] {
        let providers: [NamedQuoteService] = [
            YahooQuoteService(client: client),
            StooqQuoteService(client: client),
            CoinGeckoQuoteService(client: client)
        ]
        var lines: [String] = []
        for provider in providers {
            for symbol in symbols {
                do {
                    let quote = try await provider.quoteInEUR(symbol: symbol)
                    lines.append("\(provider.providerName) • \(symbol) • OK \(euroText(quote.priceEUR))")
                } catch {
                    lines.append("\(provider.providerName) • \(symbol) • mislukt: \(QuoteReason.describe(error))")
                }
            }
        }
        return lines
    }

    /// "€128,40", "€91.250,00". Vaste opmaak, onafhankelijk van de taalinstelling.
    static func euroText(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "€\(value)" }
        let cents = Int((abs(value) * 100).rounded())
        let whole = String(cents / 100)
        let fraction = cents % 100
        var grouped = ""
        for (offset, character) in whole.reversed().enumerated() {
            if offset > 0 && offset % 3 == 0 { grouped.append(".") }
            grouped.append(character)
        }
        let integerPart = String(grouped.reversed())
        let sign = value < 0 && cents > 0 ? "-" : ""
        return sign + "€" + integerPart + "," + (fraction < 10 ? "0" : "") + String(fraction)
    }
}
