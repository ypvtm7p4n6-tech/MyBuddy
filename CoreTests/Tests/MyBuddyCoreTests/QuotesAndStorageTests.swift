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
