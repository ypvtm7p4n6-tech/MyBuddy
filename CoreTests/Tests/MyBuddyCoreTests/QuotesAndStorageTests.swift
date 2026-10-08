import XCTest
@testable import MyBuddyCore

final class QuotesTests: XCTestCase {
    // Vorm van de Yahoo-antwoorden, ingekort. Als Yahoo de vorm wijzigt, falen deze tests niet:
    // ze controleren alleen dat onze parser het bekende formaat goed leest.
    private let searchJSON = """
    {"explains":[],"count":3,"quotes":[
      {"exchange":"GER","shortname":"Vanguard FTSE All-World","quoteType":"ETF","symbol":"VWCE.DE","index":"quotes","score":20000.0,"typeDisp":"ETF","longname":"Vanguard FTSE All-World UCITS ETF USD Accumulation","exchDisp":"XETRA","isYahooFinance":true},
      {"exchange":"NMS","shortname":"Apple Inc.","quoteType":"EQUITY","symbol":"AAPL","typeDisp":"Equity","exchDisp":"NASDAQ"},
      {"quoteType":"NONE","shortname":"zonder symbool"}
    ],"news":[]}
    """

    private func chartJSON(symbol: String, currency: String, price: Double) -> String {
        """
        {"chart":{"result":[{"meta":{"currency":"\(currency)","symbol":"\(symbol)","regularMarketPrice":\(price),"regularMarketTime":1700000000,"longName":"Naam van \(symbol)"},
        "timestamp":[1699900000,1699986400,1700000000],
        "indicators":{"quote":[{"close":[\(price - 1.5),null,\(price)]}]}}],"error":null}}
        """
    }

    func testParseSearch() throws {
        let matches = try YahooParser.parseSearch(Data(searchJSON.utf8))
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].symbol, "VWCE.DE")
        XCTAssertEqual(matches[0].name, "Vanguard FTSE All-World UCITS ETF USD Accumulation")
        XCTAssertEqual(matches[0].exchange, "XETRA")
        XCTAssertEqual(matches[1].name, "Apple Inc.")
    }

    func testParseChartSkipsNullCloses() throws {
        let parsed = try YahooParser.parseChart(Data(chartJSON(symbol: "AAPL", currency: "USD", price: 190.5).utf8))
        XCTAssertEqual(parsed.meta.symbol, "AAPL")
        XCTAssertEqual(parsed.meta.currency, "USD")
        XCTAssertEqual(parsed.meta.price ?? 0, 190.5, accuracy: 0.0001)
        XCTAssertEqual(parsed.meta.time, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(parsed.meta.name, "Naam van AAPL")
        XCTAssertEqual(parsed.points.count, 2)
        XCTAssertEqual(parsed.points.last?.close ?? 0, 190.5, accuracy: 0.0001)
    }

    func testParseChartErrorPayload() {
        let json = #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#
        XCTAssertThrowsError(try YahooParser.parseChart(Data(json.utf8)))
    }

    func testURLsAreBuilt() {
        let url = YahooQuoteService.chartURL(symbol: "BTC-EUR", range: "1y", interval: "1mo")
        XCTAssertEqual(url?.host, "query1.finance.yahoo.com")
        XCTAssertTrue(url?.absoluteString.contains("/v8/finance/chart/BTC-EUR") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("range=1y") ?? false)
        let search = YahooQuoteService.searchURL("wereld etf")
        XCTAssertEqual(search?.host, "query2.finance.yahoo.com")
        XCTAssertTrue(search?.absoluteString.contains("q=wereld") ?? false)
    }

    func testQuoteIsConvertedToEuro() async throws {
        let client = FakeClient { url in
            let s = url.absoluteString
            if s.contains("USDEUR") { return (Data(self.chartJSON(symbol: "USDEUR=X", currency: "EUR", price: 0.9).utf8), 200) }
            return (Data(self.chartJSON(symbol: "AAPL", currency: "USD", price: 190.5).utf8), 200)
        }
        let service = YahooQuoteService(client: client)
        let quote = try await service.quoteInEUR(symbol: "AAPL")
        XCTAssertEqual(quote.nativeCurrency, "USD")
        XCTAssertEqual(quote.nativePrice, 190.5, accuracy: 0.0001)
        XCTAssertEqual(quote.priceEUR, 171.45, accuracy: 0.001)
    }

    func testEuroQuoteNeedsNoConversion() async throws {
        var requests = 0
        let client = FakeClient { _ in
            requests += 1
            return (Data(self.chartJSON(symbol: "VWCE.DE", currency: "EUR", price: 120).utf8), 200)
        }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VWCE.DE")
        XCTAssertEqual(quote.priceEUR, 120, accuracy: 0.0001)
        XCTAssertEqual(requests, 1)
    }

    func testPenceAreConvertedViaPound() async throws {
        let client = FakeClient { url in
            if url.absoluteString.contains("GBPEUR") { return (Data(self.chartJSON(symbol: "GBPEUR=X", currency: "EUR", price: 1.2).utf8), 200) }
            return (Data(self.chartJSON(symbol: "VOD.L", currency: "GBp", price: 100).utf8), 200)
        }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VOD.L")
        XCTAssertEqual(quote.priceEUR, 1.2, accuracy: 0.0001) // 100 pence = 1 pond = 1,20 euro
    }

    func testHttpErrorIsReported() async {
        let client = FakeClient { _ in (Data(), 429) }
        do {
            _ = try await YahooQuoteService(client: client).quoteInEUR(symbol: "AAPL")
            XCTFail("verwachtte een fout")
        } catch let error as QuoteError {
            if case .http(let code) = error { XCTAssertEqual(code, 429) } else { XCTFail("verkeerde fout: \(error)") }
        } catch {
            XCTFail("onverwachte fout: \(error)")
        }
    }

    func testShortSearchQueryDoesNotHitTheNetwork() async throws {
        var requests = 0
        let client = FakeClient { _ in requests += 1; return (Data(), 200) }
        let result = try await YahooQuoteService(client: client).search("a")
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(requests, 0)
    }
}

final class StorageTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mybuddy-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("finance.json")
    }

    func testSampleDataRoundTrip() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let storage = FinanceStorage(url: url)
        let original = FinanceData.sample(now: day(oct2026, 12))
        try storage.save(original)

        guard case .loaded(let loaded) = storage.load() else { return XCTFail("kon niet laden") }
        XCTAssertEqual(loaded.pots.count, original.pots.count)
        XCTAssertEqual(loaded.holdings.count, original.holdings.count)
        XCTAssertEqual(loaded.goals, original.goals)
        XCTAssertEqual(loaded.months.count, original.months.count)
        XCTAssertEqual(loaded.startMonth, original.startMonth)
        XCTAssertEqual(loaded.remaining(in: oct2026), original.remaining(in: oct2026), accuracy: 0.001)
        XCTAssertEqual(loaded.totalSaved(current: oct2026), original.totalSaved(current: oct2026), accuracy: 0.001)
        XCTAssertEqual(loaded.portfolioValue(current: oct2026), original.portfolioValue(current: oct2026), accuracy: 0.001)
    }

    func testMissingFileIsEmpty() {
        let storage = FinanceStorage(url: tempURL())
        if case .empty = storage.load() { } else { XCTFail("verwachtte .empty") }
    }

    func testCorruptFileIsKeptAside() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("dit is geen json".utf8).write(to: url)
        let storage = FinanceStorage(url: url)
        guard case .corrupt(let backup) = storage.load() else { return XCTFail("verwachtte .corrupt") }
        XCTAssertNotNil(backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup!.path))
    }

    func testOldFilesWithMissingFieldsStillLoad() throws {
        let json = #"{"startMonth":"2026-08"}"#
        let decoded = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.startMonth, aug2026)
        XCTAssertTrue(decoded.pots.isEmpty)
        XCTAssertEqual(decoded.settings, AppSettings())
        XCTAssertEqual(decoded.salary, SalarySettings())
    }

    func testGoalFundingSurvivesEncoding() throws {
        var d = FinanceData(startMonth: aug2026)
        var g1 = LifeGoal(name: "A", kind: .custom)
        g1.funding = .custom(start: 1, monthly: 2, annualReturn: 0.03)
        var g2 = LifeGoal(name: "B", kind: .custom)
        g2.funding = .pot(UUID())
        d.goals = [g1, g2, LifeGoal(name: "C", kind: .retirement)]
        let data = try FinanceStorage.makeEncoder().encode(d)
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: data)
        XCTAssertEqual(back.goals, d.goals)
    }
}

// MARK: - Hulpmiddelen voor de tests van de koersbronnen

/// Houdt bij welke verzoeken zijn gedaan.
private final class QuoteRequestLog {
    var requests: [URLRequest] = []
    var urls: [String] { requests.compactMap { $0.url?.absoluteString } }
}

/// Zoals FakeClient, maar onthoudt de verzoeken (met headers) en mag een fout gooien.
private struct QuoteRecordingClient: HTTPClient {
    let log: QuoteRequestLog
    let handler: (URL) throws -> (Data, Int)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.requests.append(request)
        guard let url = request.url else { throw QuoteError.badResponse }
        let (data, status) = try handler(url)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            throw QuoteError.badResponse
        }
        return (data, response)
    }
}

private func qJSON(_ value: Double?) -> String {
    guard let value = value else { return "null" }
    return String(value)
}

private func yahooChartJSON(symbol: String, currency: String?, price: Double?, stamps: [Int], closes: [Double?]) -> String {
    var meta = "\"symbol\":\"\(symbol)\""
    if let currency = currency { meta += ",\"currency\":\"\(currency)\"" }
    if let price = price { meta += ",\"regularMarketPrice\":\(price),\"regularMarketTime\":1700000000" }
    let stampText = stamps.map { String($0) }.joined(separator: ",")
    let closeText = closes.map { qJSON($0) }.joined(separator: ",")
    return "{\"chart\":{\"result\":[{\"meta\":{\(meta)},\"timestamp\":[\(stampText)],\"indicators\":{\"quote\":[{\"close\":[\(closeText)]}]}}],\"error\":null}}"
}

/// Een gewoon Yahoo-antwoord met twee dagkoersen en een actuele koers.
private func yahooSimple(_ symbol: String, _ currency: String?, _ price: Double) -> Data {
    let json = yahooChartJSON(symbol: symbol, currency: currency, price: price,
                              stamps: [1_699_900_000, 1_700_000_000], closes: [price, price])
    return Data(json.utf8)
}

private let yahooSearchFixture = """
{"quotes":[{"symbol":"VWCE.DE","shortname":"Vanguard FTSE All-World","longname":"Vanguard FTSE All-World UCITS ETF USD Accumulation","exchDisp":"XETRA","typeDisp":"ETF","quoteType":"ETF"},{"symbol":"AAPL","shortname":"Apple Inc.","exchDisp":"NASDAQ","typeDisp":"Equity","quoteType":"EQUITY"}]}
"""

private func stooqQuoteCSV(symbol: String, close: String) -> String {
    "Symbol,Date,Time,Open,High,Low,Close,Volume\r\n\(symbol),2026-10-07,17:36:00,1,2,0.5,\(close),12345\r\n"
}

private let stooqHistoryFixture = """
Date,Open,High,Low,Close,Volume
2025-01-15,9,11,9,10,100
2025-09-15,10,12,10,11,100
2025-10-07,11,13,11,12,100
2025-12-15,12,14,12,13,100
2026-01-15,13,15,13,14,100
2026-09-15,14,16,14,14.5,100
2026-10-03,N/D,N/D,N/D,N/D,N/D
2026-09-30,14,16,14,15,100
2026-10-07,15,17,15,16,100
"""

private let coinSearchFixture = """
{"coins":[{"id":"bitcoin","name":"Bitcoin","api_symbol":"bitcoin","symbol":"BTC","market_cap_rank":1,"thumb":"x","large":"y"},{"id":"wrapped-bitcoin","name":"Wrapped Bitcoin","api_symbol":"wrapped-bitcoin","symbol":"WBTC","market_cap_rank":15},{"id":"bitcoin-fake","name":"Bitcoin Fake","symbol":"BTC","market_cap_rank":null},{"name":"Zonder id","symbol":"NOID"}],"exchanges":[],"icos":[],"categories":[],"nfts":[]}
"""

private func qHTTPCode(_ error: Error?) -> Int? {
    guard let quoteError = error as? QuoteError, case .http(let code) = quoteError else { return nil }
    return code
}

private func qMessage(_ error: Error?) -> String? {
    guard let quoteError = error as? QuoteError, case .message(let text) = quoteError else { return nil }
    return text
}

private func qFailures(_ error: Error?) -> [String]? {
    guard let quoteError = error as? QuoteError, case .allFailed(let list) = quoteError else { return nil }
    return list
}

private func qIsBadResponse(_ error: Error?) -> Bool {
    guard let quoteError = error as? QuoteError, case .badResponse = quoteError else { return false }
    return true
}

private func qIsNoData(_ error: Error?) -> Bool {
    guard let quoteError = error as? QuoteError, case .noData = quoteError else { return false }
    return true
}

private func qCaptured(_ work: () async throws -> Void) async -> Error? {
    do {
        try await work()
        return nil
    } catch {
        return error
    }
}

// MARK: - Yahoo: hosts, uitwijkbereiken, ontbrekende velden

final class YahooResilienceTests: XCTestCase {
    func testSecondHostIsUsedWhenTheFirstIsRateLimited() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.host == "query1.finance.yahoo.com" { return (Data(), 429) }
            return (yahooSimple("VWCE.DE", "EUR", 120), 200)
        }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VWCE.DE")
        XCTAssertEqual(quote.priceEUR, 120, accuracy: 0.0001)
        guard log.urls.count == 2 else { return XCTFail("verwachtte 2 verzoeken, kreeg \(log.urls.count)") }
        XCTAssertTrue(log.urls[0].contains("query1.finance.yahoo.com"))
        XCTAssertTrue(log.urls[1].contains("query2.finance.yahoo.com"))
    }

    func testEmptyResultOnTheFirstHostIsRetried() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.host == "query1.finance.yahoo.com" { return (Data(#"{"chart":{"result":[],"error":null}}"#.utf8), 200) }
            return (yahooSimple("VWCE.DE", "EUR", 121.5), 200)
        }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VWCE.DE")
        XCTAssertEqual(quote.priceEUR, 121.5, accuracy: 0.0001)
        XCTAssertEqual(log.urls.count, 2)
    }

    func testServerErrorsAreRetriedOnTheNextHost() async throws {
        for status in [403, 500, 503] {
            let log = QuoteRequestLog()
            let client = QuoteRecordingClient(log: log) { url in
                if url.host == "query1.finance.yahoo.com" { return (Data(), status) }
                return (yahooSimple("VWCE.DE", "EUR", 99), 200)
            }
            let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VWCE.DE")
            XCTAssertEqual(quote.priceEUR, 99, accuracy: 0.0001, "status \(status)")
            XCTAssertEqual(log.urls.count, 2, "status \(status)")
        }
    }

    func testRangeFallbackIsTriedWhenFiveDaysHasNoData() async throws {
        let log = QuoteRequestLog()
        let empty = #"{"chart":{"result":[{"meta":{"symbol":"VWCE.DE","currency":"EUR"},"timestamp":[],"indicators":{"quote":[{"close":[]}]}}],"error":null}}"#
        let month = yahooChartJSON(symbol: "VWCE.DE", currency: "EUR", price: nil,
                                   stamps: [1_699_900_000, 1_700_000_000, 1_700_086_400], closes: [10, 11, 12])
        let client = QuoteRecordingClient(log: log) { url in
            if url.absoluteString.contains("range=5d") { return (Data(empty.utf8), 200) }
            return (Data(month.utf8), 200)
        }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VWCE.DE")
        XCTAssertEqual(quote.priceEUR, 12, accuracy: 0.0001) // regularMarketPrice ontbreekt: laatste slotkoers
        XCTAssertEqual(log.urls.count, 3)
        XCTAssertTrue(log.urls.last?.contains("range=1mo") ?? false)
    }

    func testNetworkFailureTriesBothHostsButNotTheRangeFallback() async {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in throw URLError(.notConnectedToInternet) }
        let error = await qCaptured { _ = try await YahooQuoteService(client: client).quoteInEUR(symbol: "AAPL") }
        XCTAssertEqual((error as? URLError)?.code.rawValue, URLError.Code.notConnectedToInternet.rawValue)
        XCTAssertEqual(log.urls.count, 2)
    }

    func testAllHostsFailingReportsTheFirstError() async {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            url.host == "query1.finance.yahoo.com" ? (Data(), 429) : (Data(), 503)
        }
        let error = await qCaptured { _ = try await YahooQuoteService(client: client).quoteInEUR(symbol: "AAPL") }
        XCTAssertEqual(qHTTPCode(error), 429)
    }

    func testRequestsLookLikeABrowser() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.host == "query1.finance.yahoo.com" { return (Data(), 429) }
            return (yahooSimple("VWCE.DE", "EUR", 120), 200)
        }
        _ = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VWCE.DE")
        XCTAssertEqual(log.requests.count, 2)
        for request in log.requests {
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Mozilla/5.0") ?? false)
            XCTAssertFalse((request.value(forHTTPHeaderField: "Accept") ?? "").isEmpty)
            XCTAssertTrue(request.value(forHTTPHeaderField: "Accept-Language")?.hasPrefix("nl") ?? false)
        }
        guard log.requests.count == 2 else { return }
        // Een tweede poging gebruikt een andere browser-identiteit.
        XCTAssertNotEqual(log.requests[0].value(forHTTPHeaderField: "User-Agent"),
                          log.requests[1].value(forHTTPHeaderField: "User-Agent"))
    }

    func testMissingMarketPriceFallsBackToLastClose() async throws {
        let json = yahooChartJSON(symbol: "VWCE.DE", currency: "EUR", price: nil,
                                  stamps: [1_699_900_000, 1_700_000_000, 1_700_086_400], closes: [118.5, nil, 119.25])
        let client = FakeClient { _ in (Data(json.utf8), 200) }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "VWCE.DE")
        XCTAssertEqual(quote.priceEUR, 119.25, accuracy: 0.0001)
        XCTAssertEqual(quote.date, Date(timeIntervalSince1970: 1_700_086_400))
    }

    func testMissingCurrencyIsEuroForEuroTickers() async throws {
        for symbol in ["VWCE.DE", "IWDA.AS", "MC.PA", "ENI.MI", "UCB.BR", "EDP.LS", "BTC-EUR"] {
            let client = FakeClient { _ in (yahooSimple(symbol, nil, 50), 200) }
            let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: symbol)
            XCTAssertEqual(quote.nativeCurrency, "EUR", symbol)
            XCTAssertEqual(quote.priceEUR, 50, accuracy: 0.0001, symbol)
        }
    }

    func testMissingCurrencyForOtherTickersIsAnError() async {
        let client = FakeClient { _ in (yahooSimple("AAPL", nil, 190.5), 200) }
        let error = await qCaptured { _ = try await YahooQuoteService(client: client).quoteInEUR(symbol: "AAPL") }
        XCTAssertNotNil(qMessage(error))
        XCTAssertTrue(qMessage(error)?.contains("valuta") ?? false)
    }

    func testExchangeRatePairWithoutCurrencyIsStillUsed() async throws {
        let client = FakeClient { url in
            if url.absoluteString.contains("USDEUR") { return (yahooSimple("USDEUR=X", nil, 0.9), 200) }
            return (yahooSimple("AAPL", "USD", 190.5), 200)
        }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "AAPL")
        XCTAssertEqual(quote.priceEUR, 171.45, accuracy: 0.001)
    }

    func testSearchFallsBackToTheOtherHost() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.host == "query2.finance.yahoo.com" { return (Data(), 500) }
            return (Data(yahooSearchFixture.utf8), 200)
        }
        let matches = try await YahooQuoteService(client: client).search("vwce")
        XCTAssertEqual(matches.map { $0.symbol }, ["VWCE.DE", "AAPL"])
        guard log.urls.count == 2 else { return XCTFail("verwachtte 2 verzoeken, kreeg \(log.urls.count)") }
        XCTAssertTrue(log.urls[0].contains("query2.finance.yahoo.com"))
        XCTAssertTrue(log.urls[1].contains("query1.finance.yahoo.com"))
    }

    func testSearchWithoutResultsIsEmptyNotAnError() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in (Data(#"{"quotes":[]}"#.utf8), 200) }
        let matches = try await YahooQuoteService(client: client).search("zzzzzz")
        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(log.urls.count, 2)
    }

    func testSearchOutageIsAnError() async {
        let client = FakeClient { _ in (Data(), 500) }
        let error = await qCaptured { _ = try await YahooQuoteService(client: client).search("vwce") }
        XCTAssertEqual(qHTTPCode(error), 500)
    }

    func testHistoryFallsBackToDailyDataAndThinsItOut() async throws {
        let log = QuoteRequestLog()
        let daily = yahooChartJSON(symbol: "AAPL", currency: "USD", price: nil,
                                   stamps: [1_787_918_400, 1_788_177_600, 1_788_264_000, 1_790_769_600, 1_790_856_000, 1_791_374_400],
                                   closes: [100, 101, 102, 103, 104, 105])
        let client = QuoteRecordingClient(log: log) { url in
            let text = url.absoluteString
            if text.contains("USDEUR") { return (yahooSimple("USDEUR=X", "EUR", 0.9), 200) }
            if text.contains("interval=1mo") { return (Data(), 404) }
            return (Data(daily.utf8), 200)
        }
        let points = try await YahooQuoteService(client: client).historyInEUR(symbol: "AAPL", range: "1y", interval: "1mo")
        XCTAssertEqual(points.count, 3)
        guard points.count == 3 else { return }
        XCTAssertEqual(points.map { $0.date }, [Date(timeIntervalSince1970: 1_788_177_600),
                                                Date(timeIntervalSince1970: 1_790_769_600),
                                                Date(timeIntervalSince1970: 1_791_374_400)])
        XCTAssertEqual(points[0].close, 90.9, accuracy: 0.0001)
        XCTAssertEqual(points[1].close, 92.7, accuracy: 0.0001)
        XCTAssertEqual(points[2].close, 94.5, accuracy: 0.0001)
        XCTAssertEqual(log.urls.filter { $0.contains("interval=1mo") }.count, 2) // beide hosts
    }

    func testHistoryInEuroNeedsNoFallbackWhenItWorks() async throws {
        let log = QuoteRequestLog()
        let json = yahooChartJSON(symbol: "VWCE.DE", currency: "EUR", price: nil,
                                  stamps: [1_787_918_400, 1_788_177_600, 1_790_769_600], closes: [100, nil, 103])
        let client = QuoteRecordingClient(log: log) { _ in (Data(json.utf8), 200) }
        let points = try await YahooQuoteService(client: client).historyInEUR(symbol: "VWCE.DE", range: "1y", interval: "1mo")
        XCTAssertEqual(points.map { $0.close }, [100, 103])
        XCTAssertEqual(log.urls.count, 1)
    }

    func testEmptyHistoryIsAnError() async {
        let json = yahooChartJSON(symbol: "VWCE.DE", currency: "EUR", price: 120, stamps: [], closes: [])
        let client = FakeClient { _ in (Data(json.utf8), 200) }
        let error = await qCaptured { _ = try await YahooQuoteService(client: client).historyInEUR(symbol: "VWCE.DE", range: "1y", interval: "1mo") }
        XCTAssertTrue(qIsNoData(error))
    }

    func testHostParameterIsUsedInUrls() {
        let chart = YahooQuoteService.chartURL(symbol: "VWCE.DE", range: "5d", interval: "1d", host: "query2.finance.yahoo.com")
        XCTAssertEqual(chart?.host, "query2.finance.yahoo.com")
        XCTAssertTrue(chart?.path.hasSuffix("/v8/finance/chart/VWCE.DE") ?? false)
        let search = YahooQuoteService.searchURL("etf", host: "query1.finance.yahoo.com")
        XCTAssertEqual(search?.host, "query1.finance.yahoo.com")
        XCTAssertEqual(YahooQuoteService.chartHosts, ["query1.finance.yahoo.com", "query2.finance.yahoo.com"])
        XCTAssertEqual(YahooQuoteService.chartURL(symbol: "AAPL", range: "5d", interval: "1d")?.host, "query1.finance.yahoo.com")
        XCTAssertEqual(YahooQuoteService.searchURL("apple")?.host, "query2.finance.yahoo.com")
    }

    func testParserToleratesUnexpectedFieldTypes() throws {
        let json = #"{"chart":{"result":[{"meta":{"currency":123,"symbol":"X","regularMarketPrice":"128.4","regularMarketTime":null},"timestamp":[1700000000,null,1700086400],"indicators":{"quote":[{"close":[1.5,2.5,null]}]}}],"error":null}}"#
        let parsed = try YahooParser.parseChart(Data(json.utf8))
        XCTAssertNil(parsed.meta.currency)
        XCTAssertEqual(parsed.meta.price ?? 0, 128.4, accuracy: 0.0001)
        XCTAssertNil(parsed.meta.time)
        XCTAssertEqual(parsed.points, [PricePoint(date: Date(timeIntervalSince1970: 1_700_000_000), close: 1.5)])
    }

    func testParserUsesAdjustedCloseWhenCloseIsMissing() throws {
        let json = #"{"chart":{"result":[{"meta":{"symbol":"X","currency":"EUR"},"timestamp":[1700000000,1700086400],"indicators":{"quote":[{}],"adjclose":[{"adjclose":[10.5,11.5]}]}}],"error":null}}"#
        let parsed = try YahooParser.parseChart(Data(json.utf8))
        XCTAssertEqual(parsed.points.map { $0.close }, [10.5, 11.5])
    }

    func testEmptyCurrencyCountsAsMissing() throws {
        let json = yahooChartJSON(symbol: "X", currency: "", price: 5, stamps: [1_700_000_000], closes: [5])
        let parsed = try YahooParser.parseChart(Data(json.utf8))
        XCTAssertNil(parsed.meta.currency)
    }

    func testGarbageIsReportedAsBadResponse() {
        XCTAssertThrowsError(try YahooParser.parseChart(Data("<html>Too Many Requests</html>".utf8))) { error in
            XCTAssertTrue(qIsBadResponse(error))
        }
        XCTAssertThrowsError(try YahooParser.parseSearch(Data("Too Many Requests".utf8))) { error in
            XCTAssertTrue(qIsBadResponse(error))
        }
        XCTAssertThrowsError(try YahooParser.parseChart(Data(#"{"chart":{"result":[],"error":null}}"#.utf8))) { error in
            XCTAssertTrue(qIsBadResponse(error))
        }
    }

    func testMoreCurrenciesAreConvertedViaTheirMajorUnit() async throws {
        let client = FakeClient { url in
            if url.absoluteString.contains("ZAREUR") { return (yahooSimple("ZAREUR=X", "EUR", 0.05), 200) }
            return (yahooSimple("X.JO", "ZAc", 2000), 200)
        }
        let quote = try await YahooQuoteService(client: client).quoteInEUR(symbol: "X.JO")
        XCTAssertEqual(quote.priceEUR, 1, accuracy: 0.0001) // 2000 cent = 20 rand = 1 euro
    }
}

// MARK: - Hulpfuncties

final class QuoteHelpersTests: XCTestCase {
    func testAssumedCurrency() {
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "VWCE.DE"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "vwce.de"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "IWDA.AS"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "MC.PA"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "ENI.MI"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "UCB.BR"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "EDP.LS"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "BTC-EUR"), "EUR")
        XCTAssertEqual(QuoteCurrency.assumed(forSymbol: "USDEUR=X"), "EUR")
        XCTAssertNil(QuoteCurrency.assumed(forSymbol: "AAPL"))
        XCTAssertNil(QuoteCurrency.assumed(forSymbol: "VOD.L"))
        XCTAssertNil(QuoteCurrency.assumed(forSymbol: "BTC-USD"))
        XCTAssertNil(QuoteCurrency.assumed(forSymbol: ""))
    }

    func testRangeInDays() {
        XCTAssertEqual(QuoteRange.days("1y"), 365)
        XCTAssertEqual(QuoteRange.days("6mo"), 180)
        XCTAssertEqual(QuoteRange.days("3mo"), 90)
        XCTAssertEqual(QuoteRange.days("1mo"), 30)
        XCTAssertEqual(QuoteRange.days("5d"), 5)
        XCTAssertEqual(QuoteRange.days("10y"), 3650)
        XCTAssertNil(QuoteRange.days("max"))
        XCTAssertNil(QuoteRange.days("onzin"))
    }

    func testDateParsingIsUTC() {
        XCTAssertEqual(QuoteDates.parse("2026-10-07", time: "17:36:00"), Date(timeIntervalSince1970: 1_791_394_560))
        XCTAssertEqual(QuoteDates.parse("2026-10-07", time: "17:36"), Date(timeIntervalSince1970: 1_791_394_560))
        XCTAssertEqual(QuoteDates.parse("2026-10-07", time: "17:36:30"), Date(timeIntervalSince1970: 1_791_394_590))
        XCTAssertEqual(QuoteDates.parse("2026-10-07"), Date(timeIntervalSince1970: 1_791_331_200))
        XCTAssertNil(QuoteDates.parse("N/D"))
        XCTAssertNil(QuoteDates.parse("2026-10"))
        XCTAssertNil(QuoteDates.parse(""))
    }

    func testDownsampleKeepsLastPointPerMonth() {
        let points = [
            PricePoint(date: Date(timeIntervalSince1970: 1_791_374_400), close: 5), // 7 okt (ongesorteerd)
            PricePoint(date: Date(timeIntervalSince1970: 1_787_918_400), close: 1), // 28 aug
            PricePoint(date: Date(timeIntervalSince1970: 1_788_177_600), close: 2), // 31 aug
            PricePoint(date: Date(timeIntervalSince1970: 1_790_769_600), close: 3), // 30 sep
            PricePoint(date: Date(timeIntervalSince1970: 1_790_856_000), close: 4)  // 1 okt
        ]
        let monthly = QuotePriceSeries.downsample(points, interval: "1mo")
        XCTAssertEqual(monthly.map { $0.close }, [2, 3, 5])
        XCTAssertEqual(QuotePriceSeries.downsample(points, interval: "1d").count, 5)
    }

    func testDownsampleByWeekStartsOnMonday() {
        // 5 okt 2026 is een maandag.
        let points = [
            PricePoint(date: Date(timeIntervalSince1970: 1_791_201_600), close: 1), // ma 5 okt
            PricePoint(date: Date(timeIntervalSince1970: 1_791_288_000), close: 2), // di 6 okt
            PricePoint(date: Date(timeIntervalSince1970: 1_791_720_000), close: 3), // zo 11 okt
            PricePoint(date: Date(timeIntervalSince1970: 1_791_806_400), close: 4)  // ma 12 okt
        ]
        XCTAssertEqual(QuotePriceSeries.downsample(points, interval: "1wk").map { $0.close }, [3, 4])
    }

    func testDownsampleByDayKeepsTheLastOfTheDay() {
        let points = [
            PricePoint(date: Date(timeIntervalSince1970: 1_791_367_200), close: 1), // 7 okt 10:00
            PricePoint(date: Date(timeIntervalSince1970: 1_791_385_200), close: 2), // 7 okt 15:00
            PricePoint(date: Date(timeIntervalSince1970: 1_791_806_400), close: 3)  // 12 okt
        ]
        XCTAssertEqual(QuotePriceSeries.downsample(points, interval: "1d").map { $0.close }, [2, 3])
    }

    func testUnknownIntervalAndEmptyInputAreLeftAlone() {
        let points = [
            PricePoint(date: Date(timeIntervalSince1970: 1_791_385_200), close: 2),
            PricePoint(date: Date(timeIntervalSince1970: 1_791_367_200), close: 1)
        ]
        XCTAssertEqual(QuotePriceSeries.downsample(points, interval: "5m").map { $0.close }, [1, 2])
        XCTAssertTrue(QuotePriceSeries.downsample([], interval: "1mo").isEmpty)
        XCTAssertTrue(QuotePriceSeries.trim([], range: "1y").isEmpty)
    }

    func testTrimIsRelativeToTheLastPoint() {
        let points = [
            PricePoint(date: Date(timeIntervalSince1970: 1_736_899_200), close: 10), // 2025-01-15
            PricePoint(date: Date(timeIntervalSince1970: 1_759_795_200), close: 12), // 2025-10-07 (precies 365 dagen eerder)
            PricePoint(date: Date(timeIntervalSince1970: 1_791_331_200), close: 16)  // 2026-10-07
        ]
        XCTAssertEqual(QuotePriceSeries.trim(points, range: "1y").map { $0.close }, [12, 16])
        XCTAssertEqual(QuotePriceSeries.trim(points, range: "1mo").map { $0.close }, [16])
        XCTAssertEqual(QuotePriceSeries.trim(points, range: "max").count, 3)
    }

    func testReasonTexts() {
        XCTAssertEqual(QuoteReason.describe(QuoteError.http(429)), "HTTP 429 (te veel verzoeken)")
        XCTAssertEqual(QuoteReason.describe(QuoteError.http(403)), "HTTP 403 (geweigerd)")
        XCTAssertEqual(QuoteReason.describe(QuoteError.http(503)), "HTTP 503 (serverfout)")
        XCTAssertEqual(QuoteReason.describe(QuoteError.http(404)), "HTTP 404")
        XCTAssertEqual(QuoteReason.describe(QuoteError.noData), "geen data")
        XCTAssertEqual(QuoteReason.describe(QuoteError.badResponse), "onverwacht antwoord")
        XCTAssertEqual(QuoteReason.describe(QuoteError.message("eigen tekst")), "eigen tekst")
        XCTAssertEqual(QuoteReason.describe(URLError(.notConnectedToInternet)), "geen internetverbinding")
        XCTAssertEqual(QuoteReason.describe(URLError(.timedOut)), "time-out")
    }

    func testErrorDescriptions() {
        XCTAssertEqual(QuoteError.message("hoi").errorDescription, "hoi")
        XCTAssertEqual(QuoteError.allFailed(["A: x", "B: y"]).errorDescription, "Koers ophalen mislukt. A: x, B: y")
        XCTAssertEqual(QuoteError.allFailed([]).errorDescription, "Geen koersdienst beschikbaar.")
        XCTAssertEqual(QuoteError.http(429).errorDescription, "De koersdienst gaf foutcode 429.")
    }

    func testEuroText() {
        XCTAssertEqual(QuoteDiagnostics.euroText(128.4), "€128,40")
        XCTAssertEqual(QuoteDiagnostics.euroText(91_250), "€91.250,00")
        XCTAssertEqual(QuoteDiagnostics.euroText(0.5), "€0,50")
        XCTAssertEqual(QuoteDiagnostics.euroText(1_234_567.891), "€1.234.567,89")
        XCTAssertEqual(QuoteDiagnostics.euroText(999.999), "€1.000,00")
        XCTAssertEqual(QuoteDiagnostics.euroText(-5.2), "-€5,20")
        XCTAssertEqual(QuoteDiagnostics.euroText(-0.004), "€0,00")
    }

    func testRequestBuilderRotatesUserAgents() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/x"))
        let first = QuoteHTTP.request(for: url, accept: "application/json", attempt: 0)
        let second = QuoteHTTP.request(for: url, accept: "application/json", attempt: 1)
        let wrapped = QuoteHTTP.request(for: url, accept: "application/json", attempt: QuoteHTTP.userAgents.count)
        XCTAssertNotEqual(first.value(forHTTPHeaderField: "User-Agent"), second.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertEqual(first.value(forHTTPHeaderField: "User-Agent"), wrapped.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertEqual(first.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(first.timeoutInterval, 15, accuracy: 0.001)
    }
}

// MARK: - Stooq

final class StooqTests: XCTestCase {
    func testSymbolMapping() {
        XCTAssertEqual(StooqSymbol.map("VWCE.DE"), StooqSymbol.Mapped(code: "vwce.de", currency: "EUR"))
        XCTAssertEqual(StooqSymbol.map(" vwce.de "), StooqSymbol.Mapped(code: "vwce.de", currency: "EUR"))
        XCTAssertEqual(StooqSymbol.map("AAPL"), StooqSymbol.Mapped(code: "aapl.us", currency: "USD"))
        XCTAssertEqual(StooqSymbol.map("AAPL.US"), StooqSymbol.Mapped(code: "aapl.us", currency: "USD"))
        XCTAssertEqual(StooqSymbol.map("BRK-B"), StooqSymbol.Mapped(code: "brk-b.us", currency: "USD"))
        XCTAssertEqual(StooqSymbol.map("ASML.AS"), StooqSymbol.Mapped(code: "asml.nl", currency: "EUR"))
        XCTAssertEqual(StooqSymbol.map("ASML.NL"), StooqSymbol.Mapped(code: "asml.nl", currency: "EUR"))
        XCTAssertEqual(StooqSymbol.map("MC.PA"), StooqSymbol.Mapped(code: "mc.fr", currency: "EUR"))
        XCTAssertEqual(StooqSymbol.map("ENI.MI"), StooqSymbol.Mapped(code: "eni.it", currency: "EUR"))
    }

    func testSymbolsWithoutCertainCurrencyAreNotMapped() {
        XCTAssertNil(StooqSymbol.map("BTC-EUR"))
        XCTAssertNil(StooqSymbol.map("ETH-USD"))
        XCTAssertNil(StooqSymbol.map("VOD.L"))
        XCTAssertNil(StooqSymbol.map("USDEUR=X"))
        XCTAssertNil(StooqSymbol.map("^GSPC"))
        XCTAssertNil(StooqSymbol.map(""))
        XCTAssertNil(StooqSymbol.map(".DE"))
        XCTAssertNil(StooqSymbol.map("VWCE."))
        XCTAssertNil(StooqSymbol.map("a b"))
    }

    func testUrls() {
        XCTAssertEqual(StooqQuoteService.quoteURL(code: "vwce.de")?.absoluteString,
                       "https://stooq.com/q/l/?s=vwce.de&f=sd2t2ohlcv&h&e=csv")
        XCTAssertEqual(StooqQuoteService.historyURL(code: "vwce.de")?.absoluteString,
                       "https://stooq.com/q/d/l/?s=vwce.de&i=d")
        XCTAssertNil(StooqQuoteService.quoteURL(code: "a&b"))
        XCTAssertNil(StooqQuoteService.historyURL(code: ""))
    }

    func testParseQuoteReadsCloseSymbolAndDate() throws {
        let row = try StooqParser.parseQuote(Data(stooqQuoteCSV(symbol: "VWCE.DE", close: "128.4").utf8))
        XCTAssertEqual(row.symbol, "VWCE.DE")
        XCTAssertEqual(row.close, 128.4, accuracy: 0.0001)
        XCTAssertEqual(row.date, Date(timeIntervalSince1970: 1_791_394_560))
    }

    func testParseQuoteFindsColumnsByHeaderName() throws {
        let csv = "Close,Symbol,Date,Time\n55.5,XYZ.DE,2026-10-07,17:36:00\n"
        let row = try StooqParser.parseQuote(Data(csv.utf8))
        XCTAssertEqual(row.close, 55.5, accuracy: 0.0001)
        XCTAssertEqual(row.symbol, "XYZ.DE")
    }

    func testParseQuoteWithoutHeaderUsesTheDefaultColumnOrder() throws {
        let csv = "VWCE.DE,2026-10-07,17:36:00,128.1,128.9,127.8,128.4,12345"
        let row = try StooqParser.parseQuote(Data(csv.utf8))
        XCTAssertEqual(row.close, 128.4, accuracy: 0.0001)
    }

    func testParseQuoteUnknownSymbolIsNoData() {
        let csv = "Symbol,Date,Time,Open,High,Low,Close,Volume\r\nXXX.DE,N/D,N/D,N/D,N/D,N/D,N/D,N/D\r\n"
        XCTAssertThrowsError(try StooqParser.parseQuote(Data(csv.utf8))) { error in
            XCTAssertTrue(qIsNoData(error))
        }
        XCTAssertThrowsError(try StooqParser.parseQuote(Data("No data".utf8))) { error in
            XCTAssertTrue(qIsNoData(error))
        }
        XCTAssertThrowsError(try StooqParser.parseQuote(Data())) { error in
            XCTAssertTrue(qIsNoData(error))
        }
    }

    func testParseQuoteReportsTheDailyLimitAndHtml() {
        XCTAssertThrowsError(try StooqParser.parseQuote(Data("Exceeded the daily hits limit".utf8))) { error in
            XCTAssertTrue(qMessage(error)?.contains("limiet") ?? false)
        }
        XCTAssertThrowsError(try StooqParser.parseQuote(Data("<html><body>blocked</body></html>".utf8))) { error in
            XCTAssertTrue(qIsBadResponse(error))
        }
    }

    func testParseHistorySkipsBadLinesAndSorts() throws {
        let points = try StooqParser.parseHistory(Data(stooqHistoryFixture.utf8))
        XCTAssertEqual(points.count, 8)
        XCTAssertEqual(points.map { $0.close }, [10, 11, 12, 13, 14, 14.5, 15, 16])
        XCTAssertEqual(points.first?.date, Date(timeIntervalSince1970: 1_736_899_200))
        XCTAssertEqual(points.last?.date, Date(timeIntervalSince1970: 1_791_331_200))
    }

    func testParseHistoryWithoutRowsIsNoData() {
        XCTAssertThrowsError(try StooqParser.parseHistory(Data("Date,Open,High,Low,Close,Volume\n".utf8))) { error in
            XCTAssertTrue(qIsNoData(error))
        }
        XCTAssertThrowsError(try StooqParser.parseHistory(Data("No data".utf8))) { error in
            XCTAssertTrue(qIsNoData(error))
        }
    }

    func testEuroQuote() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in (Data(stooqQuoteCSV(symbol: "VWCE.DE", close: "128.4").utf8), 200) }
        let quote = try await StooqQuoteService(client: client).quoteInEUR(symbol: "vwce.de")
        XCTAssertEqual(quote.priceEUR, 128.4, accuracy: 0.0001)
        XCTAssertEqual(quote.nativePrice, 128.4, accuracy: 0.0001)
        XCTAssertEqual(quote.nativeCurrency, "EUR")
        XCTAssertEqual(quote.symbol, "VWCE.DE")
        XCTAssertEqual(quote.date, Date(timeIntervalSince1970: 1_791_394_560))
        XCTAssertEqual(log.urls, ["https://stooq.com/q/l/?s=vwce.de&f=sd2t2ohlcv&h&e=csv"])
        XCTAssertEqual(log.requests.first?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Mozilla/5.0"), true)
    }

    func testUSDQuoteIsConvertedWithStooqExchangeRate() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.absoluteString.contains("s=usdeur") { return (Data(stooqQuoteCSV(symbol: "USDEUR", close: "0.9").utf8), 200) }
            return (Data(stooqQuoteCSV(symbol: "AAPL.US", close: "190.5").utf8), 200)
        }
        let quote = try await StooqQuoteService(client: client).quoteInEUR(symbol: "AAPL")
        XCTAssertEqual(quote.nativeCurrency, "USD")
        XCTAssertEqual(quote.nativePrice, 190.5, accuracy: 0.0001)
        XCTAssertEqual(quote.priceEUR, 171.45, accuracy: 0.001)
        XCTAssertEqual(log.urls.count, 2)
        XCTAssertTrue(log.urls[0].contains("s=aapl.us"))
        XCTAssertTrue(log.urls[1].contains("s=usdeur"))
    }

    func testUnsupportedSymbolsDoNotHitTheNetwork() async {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in (Data(), 200) }
        let service = StooqQuoteService(client: client)
        for symbol in ["BTC-EUR", "VOD.L", "USDEUR=X"] {
            let error = await qCaptured { _ = try await service.quoteInEUR(symbol: symbol) }
            XCTAssertEqual(qMessage(error), "ticker niet ondersteund", symbol)
            let historyError = await qCaptured { _ = try await service.historyInEUR(symbol: symbol, range: "1y", interval: "1mo") }
            XCTAssertEqual(qMessage(historyError), "ticker niet ondersteund", symbol)
        }
        XCTAssertTrue(log.urls.isEmpty)
    }

    func testSearchIsUnsupportedAndReturnsEmpty() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in (Data(), 200) }
        let service = StooqQuoteService(client: client)
        let matches = try await service.search("vwce")
        XCTAssertTrue(matches.isEmpty)
        XCTAssertFalse(service.supportsSearch)
        XCTAssertEqual(service.providerName, "Stooq")
        XCTAssertTrue(log.urls.isEmpty)
    }

    func testHttpErrorsArePassedOn() async {
        let client = FakeClient { _ in (Data(), 404) }
        let error = await qCaptured { _ = try await StooqQuoteService(client: client).quoteInEUR(symbol: "AAPL") }
        XCTAssertEqual(qHTTPCode(error), 404)
    }

    func testHistoryIsTrimmedToTheRange() async throws {
        let client = FakeClient { _ in (Data(stooqHistoryFixture.utf8), 200) }
        let service = StooqQuoteService(client: client)
        // 1 jaar voor 7 okt 2026 is 7 okt 2025: de punten van januari en september 2025 vallen af.
        let daily = try await service.historyInEUR(symbol: "VWCE.DE", range: "1y", interval: "1d")
        XCTAssertEqual(daily.map { $0.close }, [12, 13, 14, 14.5, 15, 16])
        let monthly = try await service.historyInEUR(symbol: "VWCE.DE", range: "1y", interval: "1mo")
        XCTAssertEqual(monthly.map { $0.close }, [12, 13, 14, 15, 16])
        let everything = try await service.historyInEUR(symbol: "VWCE.DE", range: "max", interval: "1d")
        XCTAssertEqual(everything.count, 8)
    }

    func testUSDHistoryIsConverted() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.absoluteString.contains("s=usdeur") { return (Data(stooqQuoteCSV(symbol: "USDEUR", close: "0.9").utf8), 200) }
            return (Data(stooqHistoryFixture.utf8), 200)
        }
        let points = try await StooqQuoteService(client: client).historyInEUR(symbol: "AAPL", range: "1mo", interval: "1d")
        XCTAssertEqual(points.count, 3)
        guard points.count == 3 else { return }
        XCTAssertEqual(points[0].close, 13.05, accuracy: 0.0001)
        XCTAssertEqual(points[1].close, 13.5, accuracy: 0.0001)
        XCTAssertEqual(points[2].close, 14.4, accuracy: 0.0001)
        XCTAssertTrue(log.urls[0].contains("/q/d/l/?s=aapl.us&i=d"))
    }
}

// MARK: - CoinGecko

final class CoinGeckoTests: XCTestCase {
    func testTickerParsing() {
        let btc = CoinGeckoQuoteService.parseTicker("BTC-EUR")
        XCTAssertEqual(btc?.base, "BTC")
        XCTAssertEqual(btc?.quote, "EUR")
        let eth = CoinGeckoQuoteService.parseTicker(" eth-usd ")
        XCTAssertEqual(eth?.base, "ETH")
        XCTAssertEqual(eth?.quote, "USD")
        XCTAssertNil(CoinGeckoQuoteService.parseTicker("VWCE.DE"))
        XCTAssertNil(CoinGeckoQuoteService.parseTicker("AAPL"))
        XCTAssertNil(CoinGeckoQuoteService.parseTicker("BRK-B"))
        XCTAssertNil(CoinGeckoQuoteService.parseTicker("A-B-EUR"))
        XCTAssertNil(CoinGeckoQuoteService.parseTicker("-EUR"))
        XCTAssertNil(CoinGeckoQuoteService.parseTicker(""))
    }

    func testStaticCoinTable() {
        XCTAssertGreaterThanOrEqual(CoinGeckoQuoteService.knownCoins.count, 15)
        XCTAssertEqual(CoinGeckoQuoteService.knownCoins["BTC"]?.id, "bitcoin")
        XCTAssertEqual(CoinGeckoQuoteService.knownCoins["ETH"]?.id, "ethereum")
        XCTAssertEqual(CoinGeckoQuoteService.knownCoins["SOL"]?.id, "solana")
        XCTAssertEqual(CoinGeckoQuoteService.knownCoins["BTC"]?.name, "Bitcoin")
    }

    func testUrls() {
        let price = CoinGeckoQuoteService.priceURL(id: "bitcoin")
        XCTAssertEqual(price?.host, "api.coingecko.com")
        XCTAssertEqual(price?.path, "/api/v3/simple/price")
        XCTAssertTrue(price?.absoluteString.contains("ids=bitcoin") ?? false)
        XCTAssertTrue(price?.absoluteString.contains("vs_currencies=eur") ?? false)
        let history = CoinGeckoQuoteService.historyURL(id: "avalanche-2", days: 365)
        XCTAssertEqual(history?.path, "/api/v3/coins/avalanche-2/market_chart")
        XCTAssertTrue(history?.absoluteString.contains("vs_currency=eur") ?? false)
        XCTAssertTrue(history?.absoluteString.contains("days=365") ?? false)
        let search = CoinGeckoQuoteService.searchURL("bit coin")
        XCTAssertEqual(search?.path, "/api/v3/search")
        XCTAssertTrue(search?.absoluteString.contains("query=bit") ?? false)
    }

    func testParsePrice() throws {
        let json = #"{"bitcoin":{"eur":91250.5,"last_updated_at":1700000000}}"#
        let reading = try CoinGeckoParser.parsePrice(Data(json.utf8), id: "bitcoin")
        XCTAssertEqual(reading.price, 91_250.5, accuracy: 0.0001)
        XCTAssertEqual(reading.date, Date(timeIntervalSince1970: 1_700_000_000))
        let withoutDate = try CoinGeckoParser.parsePrice(Data(#"{"bitcoin":{"eur":5}}"#.utf8), id: "bitcoin")
        XCTAssertNil(withoutDate.date)
    }

    func testParsePriceProblems() {
        XCTAssertThrowsError(try CoinGeckoParser.parsePrice(Data("{}".utf8), id: "bitcoin")) { error in
            XCTAssertTrue(qIsNoData(error))
        }
        XCTAssertThrowsError(try CoinGeckoParser.parsePrice(Data(#"{"bitcoin":{}}"#.utf8), id: "bitcoin")) { error in
            XCTAssertTrue(qIsNoData(error))
        }
        XCTAssertThrowsError(try CoinGeckoParser.parsePrice(Data("niet json".utf8), id: "bitcoin")) { error in
            XCTAssertTrue(qIsBadResponse(error))
        }
        let limited = #"{"status":{"error_code":429,"error_message":"You've exceeded the Rate Limit."}}"#
        XCTAssertThrowsError(try CoinGeckoParser.parsePrice(Data(limited.utf8), id: "bitcoin"))
    }

    func testParseHistorySkipsNullPrices() throws {
        let json = #"{"prices":[[1700000000000,35000.5],[1700086400000,36000.25],[1700172800000,null]],"market_caps":[],"total_volumes":[]}"#
        let points = try CoinGeckoParser.parseHistory(Data(json.utf8))
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.map { $0.date }, [Date(timeIntervalSince1970: 1_700_000_000), Date(timeIntervalSince1970: 1_700_086_400)])
        XCTAssertEqual(points.map { $0.close }, [35_000.5, 36_000.25])
        XCTAssertThrowsError(try CoinGeckoParser.parseHistory(Data(#"{"prices":[]}"#.utf8))) { error in
            XCTAssertTrue(qIsNoData(error))
        }
    }

    func testParseSearch() throws {
        let coins = try CoinGeckoParser.parseSearch(Data(coinSearchFixture.utf8))
        XCTAssertEqual(coins.map { $0.id }, ["bitcoin", "wrapped-bitcoin", "bitcoin-fake"]) // zonder id valt af
        XCTAssertEqual(coins.map { $0.symbol }, ["BTC", "WBTC", "BTC"])
        XCTAssertEqual(coins[0].rank, 1)
        XCTAssertNil(coins[2].rank)
    }

    func testSearchMapsToTickersWithoutDuplicates() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in (Data(coinSearchFixture.utf8), 200) }
        let matches = try await CoinGeckoQuoteService(client: client).search("bit")
        XCTAssertEqual(matches.map { $0.symbol }, ["BTC-EUR", "WBTC-EUR"])
        XCTAssertEqual(matches.first?.name, "Bitcoin")
        XCTAssertEqual(matches.first?.type, "Cryptocurrency")
        XCTAssertEqual(log.urls.count, 1)
        XCTAssertTrue(log.urls[0].contains("/api/v3/search?query=bit"))
        let short = try await CoinGeckoQuoteService(client: client).search("b")
        XCTAssertTrue(short.isEmpty)
        XCTAssertEqual(log.urls.count, 1)
    }

    func testQuote() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in
            (Data(#"{"bitcoin":{"eur":91250.5,"last_updated_at":1700000000}}"#.utf8), 200)
        }
        let quote = try await CoinGeckoQuoteService(client: client).quoteInEUR(symbol: "BTC-EUR")
        XCTAssertEqual(quote.symbol, "BTC-EUR")
        XCTAssertEqual(quote.name, "Bitcoin")
        XCTAssertEqual(quote.priceEUR, 91_250.5, accuracy: 0.0001)
        XCTAssertEqual(quote.nativeCurrency, "EUR")
        XCTAssertEqual(quote.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(log.urls.count, 1)
        XCTAssertTrue(log.urls[0].contains("ids=bitcoin"))
        XCTAssertTrue(log.urls[0].contains("vs_currencies=eur"))
    }

    func testUSDTickerStillGivesTheEuroPrice() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in
            (Data(#"{"ethereum":{"eur":2400.75}}"#.utf8), 200)
        }
        let quote = try await CoinGeckoQuoteService(client: client).quoteInEUR(symbol: "ETH-USD")
        XCTAssertEqual(quote.symbol, "ETH-USD")
        XCTAssertEqual(quote.priceEUR, 2_400.75, accuracy: 0.0001)
        XCTAssertEqual(log.urls.count, 1)
        XCTAssertTrue(log.urls.first?.contains("ids=ethereum") ?? false)
    }

    func testNonCryptoTickersAreRejectedWithoutRequest() async {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { _ in (Data(), 200) }
        let service = CoinGeckoQuoteService(client: client)
        let error = await qCaptured { _ = try await service.quoteInEUR(symbol: "VWCE.DE") }
        XCTAssertEqual(qMessage(error), "geen crypto-ticker (bijv. BTC-EUR)")
        let historyError = await qCaptured { _ = try await service.historyInEUR(symbol: "AAPL", range: "1y", interval: "1mo") }
        XCTAssertEqual(qMessage(historyError), "geen crypto-ticker (bijv. BTC-EUR)")
        XCTAssertTrue(log.urls.isEmpty)
    }

    func testUnknownCoinIsResolvedThroughSearchUsingTheBestRank() async throws {
        let log = QuoteRequestLog()
        let search = #"{"coins":[{"id":"xyz-wrapped","name":"Wrapped XYZ","symbol":"XYZ","market_cap_rank":900},{"id":"xyz","name":"XYZ Coin","symbol":"XYZ","market_cap_rank":120},{"id":"other","name":"Other","symbol":"XYZA","market_cap_rank":5}]}"#
        let client = QuoteRecordingClient(log: log) { url in
            if url.path.hasSuffix("/search") { return (Data(search.utf8), 200) }
            return (Data(#"{"xyz":{"eur":2.5}}"#.utf8), 200)
        }
        let quote = try await CoinGeckoQuoteService(client: client).quoteInEUR(symbol: "XYZ-EUR")
        XCTAssertEqual(quote.priceEUR, 2.5, accuracy: 0.0001)
        XCTAssertEqual(quote.name, "XYZ Coin")
        guard log.urls.count == 2 else { return XCTFail("verwachtte 2 verzoeken, kreeg \(log.urls.count)") }
        XCTAssertTrue(log.urls[0].contains("/api/v3/search?query=XYZ"))
        XCTAssertTrue(log.urls[1].contains("ids=xyz&"))
    }

    func testUnknownCoinWithoutExactSymbolMatchIsAnError() async {
        let client = FakeClient { _ in (Data(#"{"coins":[{"id":"zzzz","name":"ZZZZ","symbol":"ZZZZ","market_cap_rank":3}]}"#.utf8), 200) }
        let error = await qCaptured { _ = try await CoinGeckoQuoteService(client: client).quoteInEUR(symbol: "ZZZ-EUR") }
        XCTAssertEqual(qMessage(error), "onbekende munt ZZZ")
    }

    func testRateLimitIsReported() async {
        let client = FakeClient { _ in (Data(), 429) }
        let error = await qCaptured { _ = try await CoinGeckoQuoteService(client: client).quoteInEUR(symbol: "BTC-EUR") }
        XCTAssertEqual(qHTTPCode(error), 429)
    }

    func testHistoryIsThinnedToTheRequestedInterval() async throws {
        let log = QuoteRequestLog()
        let stamps = [1_787_918_400, 1_788_177_600, 1_788_264_000, 1_790_769_600, 1_790_856_000, 1_791_374_400]
        let closes = [100, 101, 102, 103, 104, 105]
        let pairs = zip(stamps, closes).map { "[\($0 * 1000),\($1).5]" }.joined(separator: ",")
        let json = "{\"prices\":[\(pairs)]}"
        let client = QuoteRecordingClient(log: log) { _ in (Data(json.utf8), 200) }
        let service = CoinGeckoQuoteService(client: client)

        let monthly = try await service.historyInEUR(symbol: "BTC-EUR", range: "1y", interval: "1mo")
        XCTAssertEqual(monthly.map { $0.close }, [101.5, 103.5, 105.5])
        XCTAssertTrue(log.urls[0].contains("/coins/bitcoin/market_chart"))
        XCTAssertTrue(log.urls[0].contains("days=365"))

        let daily = try await service.historyInEUR(symbol: "BTC-EUR", range: "3mo", interval: "1d")
        XCTAssertEqual(daily.count, 6)
        XCTAssertTrue(log.urls[1].contains("days=90"))

        _ = try await service.historyInEUR(symbol: "BTC-EUR", range: "max", interval: "1mo")
        XCTAssertTrue(log.urls[2].contains("days=365")) // gratis API: hooguit een jaar
    }
}

// MARK: - Keten van bronnen

private final class QuoteCallCounter {
    var quotes = 0
    var searches = 0
    var histories = 0
}

private let sampleEuroQuote = EuroQuote(symbol: "X", name: "X", priceEUR: 10, nativePrice: 10,
                                        nativeCurrency: "EUR", date: Date(timeIntervalSince1970: 1_700_000_000))

private struct StubQuoteService: NamedQuoteService {
    var providerName: String
    var counter: QuoteCallCounter
    var quoteOutcome: Result<EuroQuote, QuoteError> = .failure(.noData)
    var searchOutcome: Result<[SymbolMatch], QuoteError> = .success([])
    var historyOutcome: Result<[PricePoint], QuoteError> = .success([])
    var supportsSearch: Bool = true

    func search(_ query: String) async throws -> [SymbolMatch] {
        counter.searches += 1
        return try searchOutcome.get()
    }

    func quoteInEUR(symbol: String) async throws -> EuroQuote {
        counter.quotes += 1
        return try quoteOutcome.get()
    }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        counter.histories += 1
        return try historyOutcome.get()
    }
}

/// Een bron zonder naam, die altijd dezelfde fout geeft.
private struct PlainQuoteService: QuoteService {
    var error: Error
    var counter: QuoteCallCounter

    func search(_ query: String) async throws -> [SymbolMatch] {
        counter.searches += 1
        throw error
    }

    func quoteInEUR(symbol: String) async throws -> EuroQuote {
        counter.quotes += 1
        throw error
    }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        counter.histories += 1
        throw error
    }
}

final class FallbackQuoteTests: XCTestCase {
    private let match = SymbolMatch(symbol: "VWCE.DE", name: "Vanguard", exchange: "XETRA", type: "ETF")

    func testSecondProviderIsUsedWhenTheFirstFails() async throws {
        let counter = QuoteCallCounter()
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "Yahoo", counter: counter, quoteOutcome: .failure(.http(429))),
            StubQuoteService(providerName: "Stooq", counter: counter, quoteOutcome: .success(sampleEuroQuote))
        ])
        let quote = try await chain.quoteInEUR(symbol: "X")
        XCTAssertEqual(quote, sampleEuroQuote)
        XCTAssertEqual(counter.quotes, 2)
    }

    func testTheFirstSuccessStopsTheChain() async throws {
        let counter = QuoteCallCounter()
        let other = QuoteCallCounter()
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "Yahoo", counter: counter, quoteOutcome: .success(sampleEuroQuote)),
            StubQuoteService(providerName: "Stooq", counter: other, quoteOutcome: .success(sampleEuroQuote))
        ])
        _ = try await chain.quoteInEUR(symbol: "X")
        XCTAssertEqual(counter.quotes, 1)
        XCTAssertEqual(other.quotes, 0)
    }

    func testAllFailedListsEveryProviderWithItsReason() async {
        let counter = QuoteCallCounter()
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "Yahoo", counter: counter, quoteOutcome: .failure(.http(429))),
            StubQuoteService(providerName: "Stooq", counter: counter, quoteOutcome: .failure(.noData))
        ])
        let error = await qCaptured { _ = try await chain.quoteInEUR(symbol: "X") }
        XCTAssertEqual(qFailures(error), ["Yahoo: HTTP 429 (te veel verzoeken)", "Stooq: geen data"])
        let description = (error as? QuoteError)?.errorDescription ?? ""
        XCTAssertTrue(description.contains("Yahoo: HTTP 429 (te veel verzoeken), Stooq: geen data"), description)
        XCTAssertEqual(error?.localizedDescription, description)
    }

    func testProvidersWithoutNameGetGenericNames() async {
        let counter = QuoteCallCounter()
        let chain = FallbackQuoteService([
            PlainQuoteService(error: QuoteError.noData, counter: counter),
            PlainQuoteService(error: URLError(.timedOut), counter: counter)
        ])
        XCTAssertEqual(chain.providers.map { $0.name }, ["Bron 1", "Bron 2"])
        let error = await qCaptured { _ = try await chain.quoteInEUR(symbol: "X") }
        XCTAssertEqual(qFailures(error), ["Bron 1: geen data", "Bron 2: time-out"])
    }

    func testExplicitProviderNames() async {
        let counter = QuoteCallCounter()
        let chain = FallbackQuoteService(providers: [
            FallbackQuoteService.Provider(name: "Eerste", service: PlainQuoteService(error: QuoteError.badResponse, counter: counter))
        ])
        let error = await qCaptured { _ = try await chain.quoteInEUR(symbol: "X") }
        XCTAssertEqual(qFailures(error), ["Eerste: onverwacht antwoord"])
    }

    func testEmptyChainFails() async {
        let chain = FallbackQuoteService([])
        let error = await qCaptured { _ = try await chain.quoteInEUR(symbol: "X") }
        XCTAssertEqual(qFailures(error), [])
        XCTAssertEqual((error as? QuoteError)?.errorDescription, "Geen koersdienst beschikbaar.")
    }

    func testCancellationIsNotSwallowed() async {
        let first = QuoteCallCounter()
        let second = QuoteCallCounter()
        let chain = FallbackQuoteService([
            PlainQuoteService(error: CancellationError(), counter: first),
            StubQuoteService(providerName: "Stooq", counter: second, quoteOutcome: .success(sampleEuroQuote))
        ])
        let error = await qCaptured { _ = try await chain.quoteInEUR(symbol: "X") }
        XCTAssertNotNil(error as? CancellationError)
        XCTAssertEqual(second.quotes, 0)
    }

    func testSearchReturnsTheFirstNonEmptyResult() async throws {
        let first = QuoteCallCounter()
        let second = QuoteCallCounter()
        let third = QuoteCallCounter()
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "A", counter: first, searchOutcome: .success([])),
            StubQuoteService(providerName: "B", counter: second, searchOutcome: .success([match])),
            StubQuoteService(providerName: "C", counter: third, searchOutcome: .success([match]))
        ])
        let matches = try await chain.search("vwce")
        XCTAssertEqual(matches, [match])
        XCTAssertEqual(first.searches, 1)
        XCTAssertEqual(second.searches, 1)
        XCTAssertEqual(third.searches, 0)
    }

    func testSearchSkipsProvidersThatCannotSearch() async throws {
        let skipped = QuoteCallCounter()
        let used = QuoteCallCounter()
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "Stooq", counter: skipped, searchOutcome: .failure(.badResponse), supportsSearch: false),
            StubQuoteService(providerName: "Yahoo", counter: used, searchOutcome: .success([match]))
        ])
        let matches = try await chain.search("vwce")
        XCTAssertEqual(matches, [match])
        XCTAssertEqual(skipped.searches, 0)
    }

    func testSearchOutageIsNotShownAsNoResults() async {
        let counter = QuoteCallCounter()
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "Yahoo", counter: counter, searchOutcome: .failure(.http(429))),
            StubQuoteService(providerName: "CoinGecko", counter: counter, searchOutcome: .success([]))
        ])
        let error = await qCaptured { _ = try await chain.search("vwce") }
        XCTAssertEqual(qFailures(error), ["Yahoo: HTTP 429 (te veel verzoeken)"])
    }

    func testSearchWithoutAnyResultAndWithoutFailureIsEmpty() async throws {
        let counter = QuoteCallCounter()
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "Yahoo", counter: counter, searchOutcome: .success([])),
            StubQuoteService(providerName: "CoinGecko", counter: counter, searchOutcome: .success([]))
        ])
        let matches = try await chain.search("zzzzzz")
        XCTAssertTrue(matches.isEmpty)
        let short = try await chain.search("z")
        XCTAssertTrue(short.isEmpty)
        XCTAssertEqual(counter.searches, 2) // de korte zoekterm kost geen verzoek
    }

    func testEmptyHistoryCountsAsAFailure() async throws {
        let first = QuoteCallCounter()
        let second = QuoteCallCounter()
        let points = [PricePoint(date: Date(timeIntervalSince1970: 1_700_000_000), close: 5)]
        let chain = FallbackQuoteService([
            StubQuoteService(providerName: "Yahoo", counter: first, historyOutcome: .success([])),
            StubQuoteService(providerName: "Stooq", counter: second, historyOutcome: .success(points))
        ])
        let result = try await chain.historyInEUR(symbol: "X", range: "1y", interval: "1mo")
        XCTAssertEqual(result, points)
        XCTAssertEqual(first.histories, 1)
        XCTAssertEqual(second.histories, 1)

        let allEmpty = FallbackQuoteService([StubQuoteService(providerName: "Yahoo", counter: first, historyOutcome: .success([]))])
        let error = await qCaptured { _ = try await allEmpty.historyInEUR(symbol: "X", range: "1y", interval: "1mo") }
        XCTAssertEqual(qFailures(error), ["Yahoo: geen data"])
    }

    // MARK: De standaardketen met de echte bronnen en een nepnetwerk

    func testStandardChainFallsBackToStooqWhenYahooIsBlocked() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.host?.contains("yahoo") == true { return (Data(), 429) }
            if url.host == "stooq.com" { return (Data(stooqQuoteCSV(symbol: "VWCE.DE", close: "128.4").utf8), 200) }
            return (Data(), 404)
        }
        let quote = try await QuoteServices.standard(client: client).quoteInEUR(symbol: "VWCE.DE")
        XCTAssertEqual(quote.priceEUR, 128.4, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(log.urls.filter { $0.contains("yahoo") }.count, 2)
        XCTAssertEqual(log.urls.filter { $0.contains("stooq.com") }.count, 1)
        XCTAssertTrue(log.urls.filter { $0.contains("coingecko") }.isEmpty)
    }

    func testStandardChainUsesCoinGeckoForCryptoWhenYahooIsBlocked() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.host?.contains("yahoo") == true { return (Data(), 429) }
            if url.host == "api.coingecko.com" { return (Data(#"{"bitcoin":{"eur":91250.5}}"#.utf8), 200) }
            return (Data(), 404)
        }
        let quote = try await QuoteServices.standard(client: client).quoteInEUR(symbol: "BTC-EUR")
        XCTAssertEqual(quote.priceEUR, 91_250.5, accuracy: 0.0001)
        XCTAssertTrue(log.urls.filter { $0.contains("stooq.com") }.isEmpty) // Stooq kent geen crypto
    }

    func testStandardChainReportsEveryProviderWhenAllFail() async {
        let client = FakeClient { url in
            if url.host?.contains("yahoo") == true { return (Data(), 429) }
            return (Data(), 404)
        }
        let error = await qCaptured { _ = try await QuoteServices.standard(client: client).quoteInEUR(symbol: "VWCE.DE") }
        XCTAssertEqual(qFailures(error), ["Yahoo: HTTP 429 (te veel verzoeken)",
                                          "Stooq: HTTP 404",
                                          "CoinGecko: geen crypto-ticker (bijv. BTC-EUR)"])
    }

    func testStandardChainHistoryFallsBackToStooq() async throws {
        let client = FakeClient { url in
            if url.host == "stooq.com" { return (Data(stooqHistoryFixture.utf8), 200) }
            return (Data(), 429)
        }
        let points = try await QuoteServices.standard(client: client).historyInEUR(symbol: "VWCE.DE", range: "1y", interval: "1mo")
        XCTAssertEqual(points.map { $0.close }, [12, 13, 14, 15, 16])
    }

    func testStandardSearchFallsThroughToCoinGecko() async throws {
        let log = QuoteRequestLog()
        let client = QuoteRecordingClient(log: log) { url in
            if url.host?.contains("yahoo") == true { return (Data(#"{"quotes":[]}"#.utf8), 200) }
            if url.host == "api.coingecko.com" { return (Data(coinSearchFixture.utf8), 200) }
            return (Data(), 404)
        }
        let matches = try await QuoteServices.standard(client: client).search("bitcoin")
        XCTAssertEqual(matches.map { $0.symbol }, ["BTC-EUR", "WBTC-EUR"])
        XCTAssertTrue(log.urls.filter { $0.contains("stooq.com") }.isEmpty) // Stooq kan niet zoeken
    }

    func testStandardSearchOutageGivesAnError() async {
        let client = FakeClient { url in
            if url.host?.contains("yahoo") == true { return (Data(), 429) }
            return (Data(#"{"coins":[]}"#.utf8), 200)
        }
        let error = await qCaptured { _ = try await QuoteServices.standard(client: client).search("vwce") }
        XCTAssertEqual(qFailures(error), ["Yahoo: HTTP 429 (te veel verzoeken)"])
    }
}

// MARK: - Zelftest

final class QuoteDiagnosticsTests: XCTestCase {
    func testReportsEveryProviderAndSymbol() async {
        let client = FakeClient { url in
            let text = url.absoluteString
            guard text.contains("finance.yahoo.com") else { return (Data(), 404) }
            if text.contains("USDEUR") { return (yahooSimple("USDEUR=X", "EUR", 0.9), 200) }
            if text.contains("VWCE.DE") { return (yahooSimple("VWCE.DE", "EUR", 128.4), 200) }
            if text.contains("AAPL") { return (yahooSimple("AAPL", "USD", 190.5), 200) }
            if text.contains("BTC-EUR") { return (yahooSimple("BTC-EUR", "EUR", 91_250), 200) }
            return (Data(), 404)
        }
        let lines = await QuoteDiagnostics.run(client: client)
        XCTAssertEqual(lines, [
            "Yahoo • VWCE.DE • OK €128,40",
            "Yahoo • AAPL • OK €171,45",
            "Yahoo • BTC-EUR • OK €91.250,00",
            "Stooq • VWCE.DE • mislukt: HTTP 404",
            "Stooq • AAPL • mislukt: HTTP 404",
            "Stooq • BTC-EUR • mislukt: ticker niet ondersteund",
            "CoinGecko • VWCE.DE • mislukt: geen crypto-ticker (bijv. BTC-EUR)",
            "CoinGecko • AAPL • mislukt: geen crypto-ticker (bijv. BTC-EUR)",
            "CoinGecko • BTC-EUR • mislukt: HTTP 404"
        ])
    }

    func testWorksWhenTheNetworkIsDown() async {
        let client = QuoteRecordingClient(log: QuoteRequestLog()) { _ in throw URLError(.notConnectedToInternet) }
        let lines = await QuoteDiagnostics.run(client: client)
        XCTAssertEqual(lines.count, 9)
        XCTAssertTrue(lines.first?.hasPrefix("Yahoo • VWCE.DE • mislukt: geen internetverbinding") ?? false)
        XCTAssertTrue(lines.contains("Stooq • AAPL • mislukt: geen internetverbinding"))
        XCTAssertTrue(lines.contains("CoinGecko • BTC-EUR • mislukt: geen internetverbinding"))
    }

    func testStandardServiceIsAFallbackChainInTheRightOrder() throws {
        let service = QuoteServices.standard(client: FakeClient { _ in (Data(), 200) })
        let chain = try XCTUnwrap(service as? FallbackQuoteService)
        XCTAssertEqual(chain.providers.map { $0.name }, ["Yahoo", "Stooq", "CoinGecko"])
    }
}
