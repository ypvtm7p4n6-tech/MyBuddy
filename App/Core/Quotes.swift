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

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Onverwacht antwoord van de koersdienst."
        case .noData: return "Geen koers gevonden voor deze ticker."
        case .http(let code): return "De koersdienst gaf foutcode \(code)."
        }
    }
}

// MARK: - Netwerk

protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
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

/// Bron van koersen. Nu Yahoo Finance; vervang de implementatie om van bron te wisselen.
protocol QuoteService {
    func search(_ query: String) async throws -> [SymbolMatch]
    func quoteInEUR(symbol: String) async throws -> EuroQuote
    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint]
}

// MARK: - Yahoo Finance

struct YahooQuoteService: QuoteService {
    var client: HTTPClient = URLSessionHTTPClient()

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await client.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw QuoteError.http(response.statusCode) }
        return data
    }

    static func searchURL(_ query: String) -> URL? {
        var comps = URLComponents(string: "https://query2.finance.yahoo.com/v1/finance/search")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: "10"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "lang", value: "nl-NL")
        ]
        return comps?.url
    }

    static func chartURL(symbol: String, range: String, interval: String) -> URL? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)")
        comps?.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "includePrePost", value: "false")
        ]
        return comps?.url
    }

    func search(_ query: String) async throws -> [SymbolMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let url = Self.searchURL(q) else { return [] }
        return try YahooParser.parseSearch(try await fetch(url))
    }

    private func nativeChart(symbol: String, range: String, interval: String) async throws -> (meta: YahooParser.ChartMeta, points: [PricePoint]) {
        guard let url = Self.chartURL(symbol: symbol, range: range, interval: interval) else { throw QuoteError.badResponse }
        return try YahooParser.parseChart(try await fetch(url))
    }

    private func quote(symbol: String) async throws -> Quote {
        let chart = try await nativeChart(symbol: symbol, range: "5d", interval: "1d")
        guard let price = chart.meta.price ?? chart.points.last?.close else { throw QuoteError.noData }
        return Quote(symbol: chart.meta.symbol ?? symbol,
                     name: chart.meta.name ?? symbol,
                     price: price,
                     currency: chart.meta.currency ?? "EUR",
                     date: chart.meta.time ?? Date())
    }

    /// Hoeveel euro is één eenheid van `currency` waard?
    func rateToEUR(_ currency: String) async throws -> Double {
        switch currency {
        case "EUR": return 1
        case "GBp", "GBX": return try await rateToEUR("GBP") / 100
        default:
            let pair = try await quote(symbol: "\(currency.uppercased())EUR=X")
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
        let chart = try await nativeChart(symbol: symbol, range: range, interval: interval)
        let rate = try await rateToEUR(chart.meta.currency ?? "EUR")
        return chart.points.map { PricePoint(date: $0.date, close: $0.close * rate) }
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
            let timestamp: [Double]?
            let indicators: Indicators?
        }
        struct Meta: Decodable {
            let currency: String?
            let symbol: String?
            let regularMarketPrice: Double?
            let regularMarketTime: Double?
            let longName: String?
            let shortName: String?
        }
        struct Indicators: Decodable {
            let quote: [Series]?
        }
        struct Series: Decodable {
            let close: [Double?]?
        }
        let chart: Chart
    }

    static func parseSearch(_ data: Data) throws -> [SymbolMatch] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (response.quotes ?? []).compactMap { item in
            guard let symbol = item.symbol, !symbol.isEmpty else { return nil }
            return SymbolMatch(symbol: symbol,
                               name: item.longname ?? item.shortname ?? symbol,
                               exchange: item.exchDisp ?? "",
                               type: item.typeDisp ?? item.quoteType ?? "")
        }
    }

    static func parseChart(_ data: Data) throws -> (meta: ChartMeta, points: [PricePoint]) {
        let response = try JSONDecoder().decode(ChartResponse.self, from: data)
        guard let result = response.chart.result?.first else {
            if response.chart.error != nil { throw QuoteError.noData }
            throw QuoteError.badResponse
        }
        let meta = ChartMeta(symbol: result.meta.symbol,
                             currency: result.meta.currency,
                             price: result.meta.regularMarketPrice,
                             time: result.meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) },
                             name: result.meta.longName ?? result.meta.shortName)
        var points: [PricePoint] = []
        let stamps = result.timestamp ?? []
        let closes = result.indicators?.quote?.first?.close ?? []
        for (i, stamp) in stamps.enumerated() where i < closes.count {
            if let close = closes[i] {
                points.append(PricePoint(date: Date(timeIntervalSince1970: stamp), close: close))
            }
        }
        return (meta, points)
    }
}
