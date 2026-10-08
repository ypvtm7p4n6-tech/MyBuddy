import XCTest
@testable import MyBuddyCore

/// Echte netwerktests voor de koersdiensten. Ze draaien alleen met MYBUDDY_LIVE=1
/// (de CI-job "live-network") en printen wat elke bron teruggeeft, zodat de logs
/// laten zien waarom ophalen op een toestel zou falen.
final class LiveQuotesTests: XCTestCase {
    private func requireLive() throws {
        guard ProcessInfo.processInfo.environment["MYBUDDY_LIVE"] == "1" else {
            throw XCTSkip("Zet MYBUDDY_LIVE=1 om de echte koersdiensten te testen.")
        }
    }

    /// Voert `work` uit en print de uitkomst of de reden van falen.
    private func attempt<T>(_ label: String, _ work: () async throws -> T) async throws -> T {
        do {
            let value = try await work()
            print("[LIVE] \(label): \(value)")
            return value
        } catch {
            print("[LIVE] \(label): MISLUKT, \(QuoteReason.describe(error))")
            throw error
        }
    }

    /// Haalt een URL rechtstreeks op en print status en de eerste 300 tekens.
    private func printRaw(_ label: String, url: URL?) async {
        guard let url = url else {
            print("[LIVE] \(label): geen geldige URL")
            return
        }
        let request = QuoteHTTP.request(for: url, accept: "application/json, text/plain, */*")
        do {
            let (data, response) = try await URLSessionHTTPClient().data(for: request)
            let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes, geen UTF-8>"
            print("[LIVE] \(label) -> HTTP \(response.statusCode), \(data.count) bytes")
            print("[LIVE] \(label) begin: \(String(text.prefix(300)))")
        } catch {
            print("[LIVE] \(label) -> fout: \(QuoteReason.describe(error)) (\(error))")
        }
    }

    // MARK: Ruwe antwoorden

    func testRawPayloads() async throws {
        try requireLive()
        for host in YahooQuoteService.chartHosts {
            await printRaw("Yahoo chart \(host) VWCE.DE",
                           url: YahooQuoteService.chartURL(symbol: "VWCE.DE", range: "5d", interval: "1d", host: host))
        }
        await printRaw("Yahoo chart USDEUR=X",
                       url: YahooQuoteService.chartURL(symbol: "USDEUR=X", range: "5d", interval: "1d"))
        for host in YahooQuoteService.searchHosts {
            await printRaw("Yahoo search \(host) vwce", url: YahooQuoteService.searchURL("vwce", host: host))
        }
        await printRaw("Stooq quote vwce.de", url: StooqQuoteService.quoteURL(code: "vwce.de"))
        await printRaw("Stooq quote aapl.us", url: StooqQuoteService.quoteURL(code: "aapl.us"))
        await printRaw("Stooq quote usdeur", url: StooqQuoteService.quoteURL(code: "usdeur"))
        await printRaw("Stooq history vwce.de", url: StooqQuoteService.historyURL(code: "vwce.de"))
        await printRaw("CoinGecko price bitcoin", url: CoinGeckoQuoteService.priceURL(id: "bitcoin"))
        await printRaw("CoinGecko search bitcoin", url: CoinGeckoQuoteService.searchURL("bitcoin"))
    }

    // MARK: Zelftest per bron

    func testDiagnosticsPerProvider() async throws {
        try requireLive()
        let lines = await QuoteDiagnostics.run()
        print("[LIVE] Zelftest koersbronnen:")
        for line in lines { print("[LIVE]   \(line)") }
        for symbol in QuoteDiagnostics.symbols {
            XCTAssertTrue(lines.contains(where: { $0.contains("• \(symbol) • OK") }),
                          "Geen enkele bron gaf een koers voor \(symbol)")
        }
    }

    // MARK: De standaardketen

    func testSearch() async throws {
        try requireLive()
        let service = QuoteServices.standard()
        let matches = try await attempt("search('vwce')") {
            try await service.search("vwce")
        }
        for match in matches.prefix(5) { print("[LIVE]   \(match.symbol) | \(match.name) | \(match.exchange)") }
        XCTAssertFalse(matches.isEmpty)
    }

    func testQuoteVWCE() async throws {
        try requireLive()
        let quote = try await attempt("quoteInEUR('VWCE.DE')") {
            try await QuoteServices.standard().quoteInEUR(symbol: "VWCE.DE")
        }
        XCTAssertGreaterThan(quote.priceEUR, 50)
        XCTAssertLessThan(quote.priceEUR, 600)
    }

    func testQuoteAAPL() async throws {
        try requireLive()
        let quote = try await attempt("quoteInEUR('AAPL')") {
            try await QuoteServices.standard().quoteInEUR(symbol: "AAPL")
        }
        XCTAssertGreaterThan(quote.priceEUR, 30)
        XCTAssertLessThan(quote.priceEUR, 1500)
    }

    func testQuoteBitcoin() async throws {
        try requireLive()
        let quote = try await attempt("quoteInEUR('BTC-EUR')") {
            try await QuoteServices.standard().quoteInEUR(symbol: "BTC-EUR")
        }
        XCTAssertGreaterThan(quote.priceEUR, 5_000)
        XCTAssertLessThan(quote.priceEUR, 1_000_000)
    }

    func testHistoryVWCE() async throws {
        try requireLive()
        let points = try await attempt("historyInEUR('VWCE.DE', '1y', '1mo')") { () -> [PricePoint] in
            try await QuoteServices.standard().historyInEUR(symbol: "VWCE.DE", range: "1y", interval: "1mo")
        }
        print("[LIVE]   \(points.count) punten, van \(String(describing: points.first?.date)) tot \(String(describing: points.last?.date))")
        XCTAssertGreaterThanOrEqual(points.count, 6)
        XCTAssertLessThanOrEqual(points.count, 40)
        XCTAssertTrue(points.allSatisfy { $0.close > 20 && $0.close < 1000 })
        if let first = points.first, let last = points.last {
            XCTAssertLessThan(first.date, last.date)
        }
    }
}
