import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MyBuddyCore

// MARK: - Vaste tijden en hulpjes (alleen in dit bestand)

/// 1 januari 2010, 00:00 UTC.
private let mdT0 = 1_262_304_000.0
/// Een jaar van 365,25 dagen, zoals de parser rekent.
private let mdYear = 31_557_600.0
/// 365,25 / 12 dagen in seconden: precies een gemiddelde maand.
private let mdMonth = 2_629_800.0

private func mdPoint(_ seconds: Double, _ close: Double) -> PricePoint {
    PricePoint(date: Date(timeIntervalSince1970: seconds), close: close)
}

/// Een rij zoals de Wereldbank hem teruggeeft. `value` is ruwe JSON (bijv. `3.2` of `null`).
private func worldBankRow(year: String, value: String) -> String {
    """
    {"indicator":{"id":"FP.CPI.TOTL.ZG","value":"Inflation, consumer prices (annual %)"},"country":{"id":"NL","value":"Netherlands"},"countryiso3code":"NLD","date":"\(year)","value":\(value),"unit":"","obs_status":"","decimal":1}
    """
}

private func worldBankJSON(_ rows: [(year: String, value: String)]) -> String {
    let body = rows.map { worldBankRow(year: $0.year, value: $0.value) }.joined(separator: ",\n")
    return """
    [{"page":1,"pages":7,"per_page":10,"total":65,"sourceid":"2","lastupdated":"2025-07-01"},
    [\(body)]]
    """
}

private func ecbTimeValue(_ id: String) -> String {
    """
    {"id":"\(id)","name":"\(id)","start":"\(id)T00:00:00.000+00:00","end":"\(id)T23:59:59.999+00:00"}
    """
}

/// `value` is ruwe JSON (bijv. `3.75` of `null`).
private func ecbObservations(_ entries: [(index: Int, value: String)]) -> String {
    entries.map { "\"\($0.index)\":[\($0.value),0,0,null]" }.joined(separator: ",")
}

private func ecbJSON(observations: String, times: [String]) -> String {
    let values = times.map { ecbTimeValue($0) }.joined(separator: ",")
    return """
    {"header":{"id":"3f5a1d0e","test":false,"prepared":"2024-07-01T09:00:00.000+00:00","sender":{"id":"ECB"}},
    "dataSets":[{"action":"Replace","validFrom":"2024-07-01T09:00:00.000+00:00","series":{"0:0:0:0:0:0:0":{"attributes":[0,0,null,0,0],"observations":{\(observations)}}}}],
    "structure":{"name":"Key interest rates","dimensions":{"series":[{"id":"FREQ","name":"Frequency","values":[{"id":"B","name":"Daily - businessweek"}]},{"id":"REF_AREA","name":"Reference area","values":[{"id":"U2","name":"Euro area"}]}],
    "observation":[{"id":"TIME_PERIOD","name":"Time period or range","role":"time","values":[\(values)]}]},"attributes":{"series":[],"observation":[]}}}
    """
}

private func isParseError(_ error: Error?) -> Bool {
    if let market = error as? MarketDataError, case .parse = market { return true }
    return false
}

private func isUnavailableError(_ error: Error?) -> Bool {
    if let market = error as? MarketDataError, case .unavailable = market { return true }
    return false
}

private func expectParseError(file: StaticString = #filePath, line: UInt = #line, _ work: () throws -> Any) {
    do {
        _ = try work()
        XCTFail("verwachtte een parse-fout", file: file, line: line)
    } catch {
        XCTAssertTrue(isParseError(error), "verwachtte .parse, kreeg \(error)", file: file, line: line)
    }
}

private func capturedError(file: StaticString = #filePath, line: UInt = #line,
                           _ work: () async throws -> RateReading) async -> Error? {
    do {
        _ = try await work()
        XCTFail("verwachtte een fout", file: file, line: line)
        return nil
    } catch {
        return error
    }
}

private struct MDThrowingClient: HTTPClient {
    let error: Error
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

/// Neppe koersdienst: geeft vaste punten (of een fout) terug en onthoudt wat er gevraagd is.
private final class MDFakeQuotes: QuoteService {
    var points: [PricePoint] = []
    var error: Error?
    var calls: [(symbol: String, range: String, interval: String)] = []

    func search(_ query: String) async throws -> [SymbolMatch] { [] }

    func quoteInEUR(symbol: String) async throws -> EuroQuote { throw QuoteError.noData }

    func historyInEUR(symbol: String, range: String, interval: String) async throws -> [PricePoint] {
        calls.append((symbol: symbol, range: range, interval: interval))
        if let error = error { throw error }
        return points
    }
}

// MARK: - Wereldbank

final class WorldBankParserTests: XCTestCase {
    func testUsesNewestYearWithAValue() throws {
        // 2025 is nog niet bekend (null), dus 2024 geldt.
        let json = worldBankJSON([("2025", "null"), ("2024", "3.2"), ("2023", "4.1"), ("2022", "11.6")])
        let reading = try MarketDataParsers.worldBankInflation(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.032, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "Inflatie Nederland, 2024")
        XCTAssertEqual(reading.source, "Wereldbank")
        XCTAssertEqual(reading.asOf, Date(timeIntervalSince1970: 1_735_646_400)) // 31 dec 2024, 12:00 UTC
    }

    func testDoesNotDependOnRowOrder() throws {
        let json = worldBankJSON([("2022", "11.6"), ("2024", "3.2"), ("2023", "4.1")])
        let reading = try MarketDataParsers.worldBankInflation(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.032, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "Inflatie Nederland, 2024")
    }

    func testNegativeIntegerAndTextValues() throws {
        let negative = try MarketDataParsers.worldBankInflation(Data(worldBankJSON([("2021", "-0.5")]).utf8))
        XCTAssertEqual(negative.value, -0.005, accuracy: 1e-12)

        let integer = try MarketDataParsers.worldBankInflation(Data(worldBankJSON([("2020", "2")]).utf8))
        XCTAssertEqual(integer.value, 0.02, accuracy: 1e-12)

        let text = try MarketDataParsers.worldBankInflation(Data(worldBankJSON([("2019", "\"2.5\"")]).utf8))
        XCTAssertEqual(text.value, 0.025, accuracy: 1e-12)
    }

    func testZeroInflationIsAValidValue() throws {
        let reading = try MarketDataParsers.worldBankInflation(Data(worldBankJSON([("2024", "0"), ("2023", "4.1")]).utf8))
        XCTAssertEqual(reading.value, 0, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "Inflatie Nederland, 2024")
    }

    func testRowsWithoutUsableYearAreSkipped() throws {
        let json = worldBankJSON([("abc", "9.9"), ("2022", "5.0")])
        let reading = try MarketDataParsers.worldBankInflation(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.05, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "Inflatie Nederland, 2022")
    }

    func testOnlyNullValuesIsAParseError() {
        let json = worldBankJSON([("2025", "null"), ("2024", "null")])
        expectParseError { try MarketDataParsers.worldBankInflation(Data(json.utf8)) }
    }

    func testEmptyAndMalformedAnswersAreParseErrors() {
        let answers = [
            #"[{"page":1,"pages":0,"per_page":10,"total":0},[]]"#,
            #"[{"page":0,"pages":0,"per_page":50,"total":0},null]"#,
            #"[{"message":[{"id":"120","key":"Invalid value","value":"The provided parameter value is not valid"}]}]"#,
            #"{"value":3.2}"#,
            "[]",
            "not json at all",
            "[{\"page\":1},"
        ]
        for answer in answers {
            expectParseError { try MarketDataParsers.worldBankInflation(Data(answer.utf8)) }
        }
        expectParseError { try MarketDataParsers.worldBankInflation(Data()) }
    }
}

// MARK: - ECB

final class ECBParserTests: XCTestCase {
    func testReadsRateAndDate() throws {
        let json = ecbJSON(observations: ecbObservations([(0, "3.75")]), times: ["2024-06-12"])
        let reading = try MarketDataParsers.ecbDepositRate(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.0375, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "ECB-depositorente per 12 jun 2024")
        XCTAssertEqual(reading.source, "Europese Centrale Bank")
        XCTAssertEqual(reading.asOf, Date(timeIntervalSince1970: 1_718_193_600)) // 12 jun 2024, 12:00 UTC
    }

    func testTakesNewestObservationThatHasAValue() throws {
        // Index 2 is het nieuwste maar leeg: index 1 (11 juni) geldt.
        let json = ecbJSON(observations: ecbObservations([(0, "4.0"), (1, "3.75"), (2, "null")]),
                           times: ["2024-06-10", "2024-06-11", "2024-06-12"])
        let reading = try MarketDataParsers.ecbDepositRate(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.0375, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "ECB-depositorente per 11 jun 2024")
        XCTAssertEqual(reading.asOf, Date(timeIntervalSince1970: 1_718_107_200))
    }

    func testObservationOrderInTheDocumentDoesNotMatter() throws {
        let json = ecbJSON(observations: ecbObservations([(2, "3.5"), (0, "4.0"), (1, "3.75")]),
                           times: ["2024-06-10", "2024-06-11", "2024-06-12"])
        let reading = try MarketDataParsers.ecbDepositRate(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.035, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "ECB-depositorente per 12 jun 2024")
    }

    func testZeroAndNegativeRatesAreValid() throws {
        let zero = try MarketDataParsers.ecbDepositRate(
            Data(ecbJSON(observations: ecbObservations([(0, "0.0")]), times: ["2022-06-01"]).utf8))
        XCTAssertEqual(zero.value, 0, accuracy: 1e-12)

        let negative = try MarketDataParsers.ecbDepositRate(
            Data(ecbJSON(observations: ecbObservations([(0, "-0.5")]), times: ["2021-06-01"]).utf8))
        XCTAssertEqual(negative.value, -0.005, accuracy: 1e-12)
    }

    func testMonthYearAndTimestampDates() throws {
        let month = try MarketDataParsers.ecbDepositRate(
            Data(ecbJSON(observations: ecbObservations([(0, "2.0")]), times: ["2024-06"]).utf8))
        XCTAssertEqual(month.label, "ECB-depositorente per jun 2024")
        XCTAssertEqual(month.asOf, Date(timeIntervalSince1970: 1_717_243_200)) // 1 jun 2024, 12:00 UTC

        let yearOnly = try MarketDataParsers.ecbDepositRate(
            Data(ecbJSON(observations: ecbObservations([(0, "2.0")]), times: ["2024"]).utf8))
        XCTAssertEqual(yearOnly.label, "ECB-depositorente per 2024")
        XCTAssertEqual(yearOnly.asOf, Date(timeIntervalSince1970: 1_704_110_400)) // 1 jan 2024, 12:00 UTC

        let stamped = try MarketDataParsers.ecbDepositRate(
            Data(ecbJSON(observations: ecbObservations([(0, "2.0")]), times: ["2024-06-12T00:00:00.000+00:00"]).utf8))
        XCTAssertEqual(stamped.label, "ECB-depositorente per 12 jun 2024")
    }

    func testMissingStructureStillGivesTheValue() throws {
        let json = #"{"dataSets":[{"series":{"0":{"observations":{"0":[2.5]}}}}]}"#
        let reading = try MarketDataParsers.ecbDepositRate(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.025, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "ECB-depositorente")
        XCTAssertNil(reading.asOf)
    }

    func testIndexBeyondTheTimeListGivesNoDate() throws {
        let json = ecbJSON(observations: ecbObservations([(5, "3.0")]), times: ["2024-06-12"])
        let reading = try MarketDataParsers.ecbDepositRate(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.03, accuracy: 1e-12)
        XCTAssertNil(reading.asOf)
    }

    func testSkipsSeriesWithoutObservations() throws {
        let json = #"{"dataSets":[{"series":{"0:0":{"attributes":[]},"1:0":{"observations":{"0":[1.5,0]}}}}]}"#
        let reading = try MarketDataParsers.ecbDepositRate(Data(json.utf8))
        XCTAssertEqual(reading.value, 0.015, accuracy: 1e-12)
    }

    func testBrokenAnswersAreParseErrors() {
        let answers = [
            #"{"header":{"id":"x"}}"#,
            #"{"dataSets":[]}"#,
            #"{"dataSets":[{"series":{}}]}"#,
            #"{"dataSets":[{"series":{"0":{"observations":{}}}}]}"#,
            #"{"dataSets":[{"series":{"0":{"observations":{"0":[null,0]}}}}]}"#,
            #"{"dataSets":[{"series":{"0":{"observations":{"0":[]}}}}]}"#,
            #"{"dataSets":[{"series":{"0":{"observations":{"-1":[3.0],"x":[4.0]}}}}]}"#,
            #"{"dataSets":[{"series":{"0":{"observations":{"0":"3.0"}}}}]}"#,
            "[1,2,3]",
            "not json at all",
            #"{"dataSets":["#
        ]
        for answer in answers {
            expectParseError { try MarketDataParsers.ecbDepositRate(Data(answer.utf8)) }
        }
        expectParseError { try MarketDataParsers.ecbDepositRate(Data()) }
    }
}

// MARK: - Historisch rendement

final class HistoricalReturnMathTests: XCTestCase {
    /// 100 in 2010, 150 na 5 jaar, 300 na 10 jaar.
    private var tenYears: [PricePoint] {
        [mdPoint(mdT0, 100), mdPoint(mdT0 + 5 * mdYear, 150), mdPoint(mdT0 + 10 * mdYear, 300)]
    }

    func testStartPointIsTheOneNearestToTheTargetPeriod() throws {
        let five = try XCTUnwrap(MarketDataParsers.cagr(points: tenYears, targetYears: 5))
        XCTAssertEqual(five.first.close, 150)
        XCTAssertEqual(five.last.close, 300)
        XCTAssertEqual(five.years, 5, accuracy: 1e-9)
        XCTAssertEqual(five.rate, 0.1486983549970351, accuracy: 1e-12) // (300 / 150)^(1/5) - 1

        let ten = try XCTUnwrap(MarketDataParsers.cagr(points: tenYears, targetYears: 10))
        XCTAssertEqual(ten.first.close, 100)
        XCTAssertEqual(ten.years, 10, accuracy: 1e-9)
        XCTAssertEqual(ten.rate, 0.11612317403390437, accuracy: 1e-12) // (300 / 100)^(1/10) - 1
    }

    func testWithoutTargetFirstAndLastPointAreUsed() throws {
        let result = try XCTUnwrap(MarketDataParsers.cagr(points: tenYears))
        XCTAssertEqual(result.first.close, 100)
        XCTAssertEqual(result.last.close, 300)
        XCTAssertEqual(result.rate, 0.11612317403390437, accuracy: 1e-12)
    }

    func testTargetLongerThanTheHistoryUsesTheOldestPoint() throws {
        let result = try XCTUnwrap(MarketDataParsers.cagr(points: tenYears, targetYears: 20))
        XCTAssertEqual(result.first.close, 100)
        XCTAssertEqual(result.years, 10, accuracy: 1e-9)
    }

    func testMonthlySeriesWithConstantGrowth() throws {
        // 1% per maand, 144 maanden. Vijf jaar terug is precies 60 punten eerder.
        var points: [PricePoint] = []
        for i in 0..<144 {
            points.append(mdPoint(mdT0 + Double(i) * mdMonth, 100 * pow(1.01, Double(i))))
        }
        let result = try XCTUnwrap(MarketDataParsers.cagr(points: points, targetYears: 5))
        XCTAssertEqual(result.first.date, Date(timeIntervalSince1970: mdT0 + 83 * mdMonth))
        XCTAssertEqual(result.last.date, Date(timeIntervalSince1970: mdT0 + 143 * mdMonth))
        XCTAssertEqual(result.years, 5, accuracy: 1e-9)
        XCTAssertEqual(result.rate, 0.12682503013196977, accuracy: 1e-9) // 1,01^12 - 1
    }

    func testUnsortedInputAndUnusablePricesAreHandled() throws {
        let points = [
            mdPoint(mdT0 + 10 * mdYear, 300),
            mdPoint(mdT0 + 5 * mdYear, 0),
            mdPoint(mdT0, 100),
            mdPoint(mdT0 + 2 * mdYear, Double.nan),
            mdPoint(mdT0 + 3 * mdYear, -4),
            mdPoint(mdT0 + 4 * mdYear, Double.infinity)
        ]
        let result = try XCTUnwrap(MarketDataParsers.cagr(points: points, targetYears: 10))
        XCTAssertEqual(result.first.close, 100)
        XCTAssertEqual(result.last.close, 300)
        XCTAssertEqual(result.rate, 0.11612317403390437, accuracy: 1e-12)
    }

    func testNegativeReturn() throws {
        let points = [mdPoint(mdT0, 200), mdPoint(mdT0 + 4 * mdYear, 100)]
        let result = try XCTUnwrap(MarketDataParsers.cagr(points: points, targetYears: 4))
        XCTAssertEqual(result.rate, -0.1591035847462855, accuracy: 1e-12) // (100 / 200)^(1/4) - 1
    }

    func testNeedsTwoUsablePointsAndHalfAYear() {
        XCTAssertNil(MarketDataParsers.cagr(points: []))
        XCTAssertNil(MarketDataParsers.cagr(points: [mdPoint(mdT0, 100)]))
        // Tweede punt is onbruikbaar: er blijft er maar één over.
        XCTAssertNil(MarketDataParsers.cagr(points: [mdPoint(mdT0, 100), mdPoint(mdT0 + mdYear, 0)]))
        // 60 dagen is te kort voor een jaarrendement.
        XCTAssertNil(MarketDataParsers.cagr(points: [mdPoint(mdT0, 100), mdPoint(mdT0 + 60 * 86_400, 110)]))
    }

    func testExactlyHalfAYearIsAccepted() throws {
        let points = [mdPoint(mdT0, 100), mdPoint(mdT0 + 0.5 * mdYear, 110)]
        let result = try XCTUnwrap(MarketDataParsers.cagr(points: points))
        XCTAssertEqual(result.years, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.rate, 0.21, accuracy: 1e-9) // 1,1^2 - 1
    }

    func testYearsAreClampedAndMappedToYahooRanges() {
        XCTAssertEqual(MarketDataParsers.clampYears(-3), 1)
        XCTAssertEqual(MarketDataParsers.clampYears(0), 1)
        XCTAssertEqual(MarketDataParsers.clampYears(7), 7)
        XCTAssertEqual(MarketDataParsers.clampYears(99), 20)

        let cases: [(Int, String)] = [(-4, "1y"), (0, "1y"), (1, "1y"), (2, "2y"), (3, "5y"), (5, "5y"),
                                      (6, "10y"), (10, "10y"), (11, "max"), (20, "max"), (99, "max")]
        for (years, expected) in cases {
            XCTAssertEqual(MarketDataParsers.yahooRange(forYears: years), expected, "jaren: \(years)")
        }
    }

    func testReadingMentionsSymbolPeriodAndThatDividendIsExcluded() throws {
        let reading = try MarketDataParsers.historicalReturn(points: tenYears, symbol: "VWCE.DE", years: 10)
        XCTAssertEqual(reading.value, 0.11612317403390437, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "Koersrendement VWCE.DE, 10 jaar (alleen koersgroei, zonder dividend)")
        XCTAssertEqual(reading.source, "Yahoo Finance")
        XCTAssertEqual(reading.asOf, Date(timeIntervalSince1970: mdT0 + 10 * mdYear))

        let five = try MarketDataParsers.historicalReturn(points: tenYears, symbol: "VWCE.DE", years: 5)
        XCTAssertEqual(five.value, 0.1486983549970351, accuracy: 1e-12)
        XCTAssertTrue(five.label.contains("5 jaar"))
    }

    func testShortHistoryIsLabelledWithTheRealPeriod() throws {
        // 23 maanden aan koersen terwijl 10 jaar gevraagd is.
        let points = [mdPoint(mdT0, 100), mdPoint(mdT0 + 23 * mdMonth, 121)]
        let reading = try MarketDataParsers.historicalReturn(points: points, symbol: "NEW.AS", years: 10)
        XCTAssertEqual(reading.value, 0.10456777065069889, accuracy: 1e-9) // 1,21^(12/23) - 1
        XCTAssertTrue(reading.label.contains("1 jaar en 11 maanden"), reading.label)
        XCTAssertFalse(reading.label.contains("10 jaar"), reading.label)
    }

    func testSlightlyShortHistoryKeepsTheRequestedLabel() throws {
        // 11 maanden voor "1 jaar": binnen de marge, dus het label blijft "1 jaar".
        let points = [mdPoint(mdT0, 100), mdPoint(mdT0 + 11 * mdMonth, 110)]
        let reading = try MarketDataParsers.historicalReturn(points: points, symbol: "ABC", years: 1)
        XCTAssertEqual(reading.value, 0.10957242854263938, accuracy: 1e-9) // 1,1^(12/11) - 1
        XCTAssertTrue(reading.label.contains("1 jaar"), reading.label)
    }

    func testTooLittleHistoryIsAReturnError() {
        let points = [mdPoint(mdT0, 100), mdPoint(mdT0 + 60 * 86_400, 110)]
        XCTAssertThrowsError(try MarketDataParsers.historicalReturn(points: points, symbol: "ABC", years: 5)) { error in
            XCTAssertEqual(error as? MarketReturnError, MarketReturnError.tooLittleHistory("ABC"))
        }
        XCTAssertFalse((MarketReturnError.tooLittleHistory("ABC").errorDescription ?? "").isEmpty)
        XCTAssertFalse((MarketReturnError.noTicker.errorDescription ?? "").isEmpty)
    }
}

// MARK: - De service met neppe netwerk en koersdienst

final class MarketServiceTests: XCTestCase {
    func testInflationComesFromTheWorldBank() async throws {
        var seen: [URL] = []
        let client = FakeClient { url in
            seen.append(url)
            return (Data(worldBankJSON([("2025", "null"), ("2024", "3.2")]).utf8), 200)
        }
        let service = LiveMarketDataService(client: client, quotes: MDFakeQuotes())
        let reading = try await service.fetchInflation()
        XCTAssertEqual(reading.value, 0.032, accuracy: 1e-12)
        XCTAssertEqual(reading.source, "Wereldbank")
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.host, "api.worldbank.org")
        XCTAssertTrue(seen.first?.absoluteString.contains("FP.CPI.TOTL.ZG") ?? false)
        XCTAssertTrue(seen.first?.absoluteString.contains("/NLD/") ?? false)
    }

    func testSavingsBenchmarkComesFromTheECB() async throws {
        var seen: [URL] = []
        let client = FakeClient { url in
            seen.append(url)
            return (Data(ecbJSON(observations: ecbObservations([(0, "2.0")]), times: ["2025-06-11"]).utf8), 200)
        }
        let service = LiveMarketDataService(client: client, quotes: MDFakeQuotes())
        let reading = try await service.fetchSavingsBenchmarkRate()
        XCTAssertEqual(reading.value, 0.02, accuracy: 1e-12)
        XCTAssertEqual(reading.label, "ECB-depositorente per 11 jun 2025")
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.host, "data-api.ecb.europa.eu")
        XCTAssertTrue(seen.first?.absoluteString.contains("DFR") ?? false)
        XCTAssertTrue(seen.first?.absoluteString.contains("lastNObservations=1") ?? false)
    }

    func testHttpErrorIsUnavailable() async {
        let client = FakeClient { _ in (Data(), 503) }
        let service = LiveMarketDataService(client: client, quotes: MDFakeQuotes())
        let inflation = await capturedError { try await service.fetchInflation() }
        XCTAssertTrue(isUnavailableError(inflation), "kreeg \(String(describing: inflation))")
        let savings = await capturedError { try await service.fetchSavingsBenchmarkRate() }
        XCTAssertTrue(isUnavailableError(savings), "kreeg \(String(describing: savings))")
        XCTAssertFalse((inflation?.localizedDescription ?? "").isEmpty)
    }

    func testNetworkFailureIsUnavailable() async {
        let client = MDThrowingClient(error: URLError(.notConnectedToInternet))
        let service = LiveMarketDataService(client: client, quotes: MDFakeQuotes())
        let error = await capturedError { try await service.fetchInflation() }
        XCTAssertTrue(isUnavailableError(error), "kreeg \(String(describing: error))")
    }

    func testCancellationIsNotReportedAsAFailureOfTheSource() async {
        let service = LiveMarketDataService(client: MDThrowingClient(error: CancellationError()), quotes: MDFakeQuotes())
        let first = await capturedError { try await service.fetchInflation() }
        XCTAssertTrue(first is CancellationError, "kreeg \(String(describing: first))")

        let cancelledSession = LiveMarketDataService(client: MDThrowingClient(error: URLError(.cancelled)), quotes: MDFakeQuotes())
        let second = await capturedError { try await cancelledSession.fetchSavingsBenchmarkRate() }
        XCTAssertTrue(second is CancellationError, "kreeg \(String(describing: second))")
    }

    func testUnreadableAnswerIsAParseError() async {
        let client = FakeClient { _ in (Data("<html>Service unavailable</html>".utf8), 200) }
        let service = LiveMarketDataService(client: client, quotes: MDFakeQuotes())
        let inflation = await capturedError { try await service.fetchInflation() }
        XCTAssertTrue(isParseError(inflation), "kreeg \(String(describing: inflation))")
        let savings = await capturedError { try await service.fetchSavingsBenchmarkRate() }
        XCTAssertTrue(isParseError(savings), "kreeg \(String(describing: savings))")
    }

    // MARK: Rendement

    private let tenYears = [mdPoint(mdT0, 100), mdPoint(mdT0 + 5 * mdYear, 150), mdPoint(mdT0 + 10 * mdYear, 300)]

    private func makeService(with quotes: MDFakeQuotes) -> LiveMarketDataService {
        LiveMarketDataService(client: FakeClient { _ in (Data(), 500) }, quotes: quotes)
    }

    func testReturnAsksForMonthlyBarsInTheRightRange() async throws {
        let quotes = MDFakeQuotes()
        quotes.points = tenYears
        let reading = try await makeService(with: quotes).historicalReturn(symbol: "  VWCE.DE ", years: 10)
        XCTAssertEqual(quotes.calls.count, 1)
        XCTAssertEqual(quotes.calls.first?.symbol, "VWCE.DE")
        XCTAssertEqual(quotes.calls.first?.range, "10y")
        XCTAssertEqual(quotes.calls.first?.interval, "1mo")
        XCTAssertEqual(reading.value, 0.11612317403390437, accuracy: 1e-12)
        XCTAssertEqual(reading.source, "Yahoo Finance")
        XCTAssertTrue(reading.label.contains("VWCE.DE"))
    }

    func testReturnClampsTheNumberOfYears() async throws {
        let quotes = MDFakeQuotes()
        quotes.points = tenYears
        let service = makeService(with: quotes)
        _ = try await service.historicalReturn(symbol: "ABC", years: 0)
        _ = try await service.historicalReturn(symbol: "ABC", years: 99)
        _ = try await service.historicalReturn(symbol: "ABC", years: 3)
        XCTAssertEqual(quotes.calls.map { $0.range }, ["1y", "max", "5y"])
    }

    func testReturnWithoutTickerDoesNotHitTheNetwork() async {
        let quotes = MDFakeQuotes()
        quotes.points = tenYears
        let service = makeService(with: quotes)
        let error = await capturedError { try await service.historicalReturn(symbol: "   ", years: 5) }
        XCTAssertEqual(error as? MarketReturnError, MarketReturnError.noTicker)
        XCTAssertTrue(quotes.calls.isEmpty)
    }

    func testReturnKeepsTheQuoteServiceError() async {
        let quotes = MDFakeQuotes()
        quotes.error = QuoteError.noData
        let service = makeService(with: quotes)
        let error = await capturedError { try await service.historicalReturn(symbol: "NOPE", years: 5) }
        if let quoteError = error as? QuoteError, case .noData = quoteError {
            // goed: de duidelijke melding van de koersdienst blijft behouden
        } else {
            XCTFail("verwachtte QuoteError.noData, kreeg \(String(describing: error))")
        }
    }

    func testReturnMapsOtherFailures() async {
        let quotes = MDFakeQuotes()
        let service = makeService(with: quotes)

        quotes.error = URLError(.timedOut)
        let network = await capturedError { try await service.historicalReturn(symbol: "ABC", years: 5) }
        XCTAssertTrue(isUnavailableError(network), "kreeg \(String(describing: network))")

        quotes.error = DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "kapot"))
        let decoding = await capturedError { try await service.historicalReturn(symbol: "ABC", years: 5) }
        XCTAssertTrue(isParseError(decoding), "kreeg \(String(describing: decoding))")

        quotes.error = CancellationError()
        let cancelled = await capturedError { try await service.historicalReturn(symbol: "ABC", years: 5) }
        XCTAssertTrue(cancelled is CancellationError, "kreeg \(String(describing: cancelled))")
    }

    func testReturnWithTooLittleHistory() async {
        let quotes = MDFakeQuotes()
        quotes.points = [mdPoint(mdT0, 100), mdPoint(mdT0 + 60 * 86_400, 110)]
        let service = makeService(with: quotes)
        let error = await capturedError { try await service.historicalReturn(symbol: "NEW.AS", years: 5) }
        XCTAssertEqual(error as? MarketReturnError, MarketReturnError.tooLittleHistory("NEW.AS"))

        quotes.points = []
        let empty = await capturedError { try await service.historicalReturn(symbol: "NEW.AS", years: 5) }
        XCTAssertEqual(empty as? MarketReturnError, MarketReturnError.tooLittleHistory("NEW.AS"))
    }
}

// MARK: - Echte bronnen (alleen met MYBUDDY_LIVE=1)

/// Raakt het echte internet. Wordt overgeslagen tenzij `MYBUDDY_LIVE=1` is gezet, bijvoorbeeld:
/// `MYBUDDY_LIVE=1 swift test --filter LiveMarketTests`
final class LiveMarketTests: XCTestCase {
    private func requireLive() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYBUDDY_LIVE"] == "1",
                          "Zet MYBUDDY_LIVE=1 om de echte bronnen te testen.")
    }

    func testLiveInflation() async throws {
        try requireLive()
        let reading = try await LiveMarketDataService().fetchInflation()
        print("LIVE inflatie:", reading)
        XCTAssertGreaterThan(reading.value, -0.05)
        XCTAssertLessThan(reading.value, 0.30)
    }

    func testLiveSavingsBenchmark() async throws {
        try requireLive()
        let reading = try await LiveMarketDataService().fetchSavingsBenchmarkRate()
        print("LIVE ECB-depositorente:", reading)
        XCTAssertGreaterThan(reading.value, -0.02)
        XCTAssertLessThan(reading.value, 0.15)
    }

    func testLiveHistoricalReturn() async throws {
        try requireLive()
        let reading = try await LiveMarketDataService().historicalReturn(symbol: "IWDA.AS", years: 5)
        print("LIVE rendement IWDA.AS 5 jaar:", reading)
        XCTAssertGreaterThan(reading.value, -0.5)
        XCTAssertLessThan(reading.value, 1.0)
    }
}
