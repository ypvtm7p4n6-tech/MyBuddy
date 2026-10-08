import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Service

/// Haalt rekencijfers van internet, zonder API-sleutel:
/// - inflatie: Wereldbank (indicator FP.CPI.TOTL.ZG, jaarcijfers per land),
/// - spaarrente-richtpunt: depositorente van de ECB (SDMX-JSON),
/// - historisch rendement: maandkoersen via `QuoteService` (Yahoo Finance).
///
/// Elke bron heeft een eigen, los testbare parser in `MarketDataParsers`.
/// Netwerkfouten worden `MarketDataError.unavailable`, onleesbare antwoorden `MarketDataError.parse`.
struct LiveMarketDataService: MarketDataService {
    var client: any HTTPClient
    var quotes: any QuoteService

    init(client: any HTTPClient = URLSessionHTTPClient(), quotes: any QuoteService = QuoteServices.standard()) {
        self.client = client
        self.quotes = quotes
    }

    // MARK: Adressen

    /// Wereldbank: jaarlijkse consumentenprijsinflatie (%), nieuwste jaar eerst.
    static var inflationURL: URL? {
        URL(string: "https://api.worldbank.org/v2/country/NLD/indicator/FP.CPI.TOTL.ZG?format=json&per_page=10")
    }

    /// ECB: depositofaciliteit (DFR), alleen de laatste waarneming.
    /// Het `format`-argument overschrijft de Accept-header, die bij de ECB SDMX-mediatypes verwacht.
    /// Alternatief met dezelfde vorm: reeks `FM/D.U2.EUR.4F.KR.DFR.LEV` (kalenderdagen in plaats van werkdagen).
    static var depositRateURL: URL? {
        URL(string: "https://data-api.ecb.europa.eu/service/data/FM/B.U2.EUR.4F.KR.DFR.LEV?lastNObservations=1&format=jsondata")
    }

    // MARK: MarketDataService

    func fetchInflation() async throws -> RateReading {
        let what = "de inflatie"
        guard let url = Self.inflationURL else { throw MarketDataError.unavailable(what) }
        let data = try await fetch(url, what: what, accept: "application/json")
        return try MarketDataParsers.worldBankInflation(data)
    }

    func fetchSavingsBenchmarkRate() async throws -> RateReading {
        let what = "de spaarrente"
        guard let url = Self.depositRateURL else { throw MarketDataError.unavailable(what) }
        let data = try await fetch(url, what: what, accept: "*/*")
        return try MarketDataParsers.ecbDepositRate(data)
    }

    func historicalReturn(symbol: String, years: Int) async throws -> RateReading {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticker.isEmpty else { throw MarketReturnError.noTicker }
        let wanted = MarketDataParsers.clampYears(years)

        let points: [PricePoint]
        do {
            // Yahoo kent alleen vaste perioden (1y, 2y, 5y, 10y, max): we vragen de eerstvolgende
            // periode die lang genoeg is en kiezen daarna zelf het beginpunt.
            points = try await quotes.historyInEUR(symbol: ticker,
                                                   range: MarketDataParsers.yahooRange(forYears: wanted),
                                                   interval: "1mo")
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as QuoteError {
            throw error
        } catch is DecodingError {
            throw MarketDataError.parse("het rendement van \(ticker)")
        } catch {
            throw MarketDataError.unavailable("het rendement van \(ticker)")
        }
        return try MarketDataParsers.historicalReturn(points: points, symbol: ticker, years: wanted)
    }

    // MARK: Netwerk

    private func fetch(_ url: URL, what: String, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("MyBuddy/1.0", forHTTPHeaderField: "User-Agent")

        let result: (Data, HTTPURLResponse)
        do {
            result = try await client.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MarketDataError.unavailable(what)
        }
        guard (200..<300).contains(result.1.statusCode) else { throw MarketDataError.unavailable(what) }
        return result.0
    }
}

/// Fouten van het rendement ophalen die geen netwerkprobleem zijn.
enum MarketReturnError: Error, LocalizedError, Equatable {
    /// Er is geen ticker ingevuld.
    case noTicker
    /// De koershistorie is korter dan een half jaar (of er zijn minder dan twee koersen).
    case tooLittleHistory(String)

    var errorDescription: String? {
        switch self {
        case .noTicker:
            return "Vul eerst een ticker in om het rendement op te halen."
        case .tooLittleHistory(let symbol):
            return "Van \(symbol) is te weinig koershistorie (minder dan een half jaar) om een jaarrendement te berekenen."
        }
    }
}

// MARK: - Parsers

/// Resultaat van een CAGR-berekening: het rendement en welke twee koersen daarvoor zijn gebruikt.
struct CAGRResult: Equatable {
    /// Per jaar, als breuk (0,07 = 7%).
    var rate: Double
    /// Aantal jaren tussen de twee koersen, uit hun datums.
    var years: Double
    var first: PricePoint
    var last: PricePoint
}

/// Een (gedeeltelijke) datum uit een antwoord: jaar, jaar-maand of jaar-maand-dag.
fileprivate struct DateParts: Equatable {
    var year: Int
    var month: Int?
    var day: Int?
}

/// Leest de antwoorden van de bronnen. Alles is losgekoppeld van het netwerk, zodat het met vaste teksten te testen is.
/// De parsers zijn tolerant: onverwachte vormen geven `MarketDataError.parse`, nooit een crash.
enum MarketDataParsers {
    static let secondsPerYear: Double = 365.25 * 86_400
    /// Korter dan dit geeft een jaarrendement dat niets zegt.
    static let minimumYearsForReturn: Double = 0.5

    // MARK: Wereldbank (inflatie)

    /// Vorm: `[ {page, pages, ...}, [ {"date":"2024","value":3.2,...}, {"date":"2023","value":null,...}, ... ] ]`.
    /// Het jaarcijfer staat in procenten. We nemen het nieuwste jaar met een waarde (het lopende jaar is vaak nog `null`).
    static func worldBankInflation(_ data: Data) throws -> RateReading {
        let what = "de inflatie"
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
              root.count >= 2,
              let rows = root[1] as? [Any] else { throw MarketDataError.parse(what) }

        var newest: (year: Int, percent: Double)?
        for case let row as [String: Any] in rows {
            guard let year = intValue(row["date"]),
                  let percent = number(row["value"]),
                  percent.isFinite else { continue }
            if let current = newest, current.year >= year { continue }
            newest = (year, percent)
        }
        guard let found = newest else { throw MarketDataError.parse(what) }

        return RateReading(value: found.percent / 100,
                           label: "Inflatie Nederland, \(found.year)",
                           source: "Wereldbank",
                           asOf: makeDate(DateParts(year: found.year, month: 12, day: 31)))
    }

    // MARK: ECB (depositorente)

    /// SDMX-JSON. Relevante delen:
    /// ```
    /// dataSets[0].series["0:0:0:0:0:0:0"].observations = { "0": [3.75, 0, 0, null] }
    /// structure.dimensions.observation[0].values[0]     = { "id": "2024-06-12", ... }   // tijdsdimensie
    /// ```
    /// De sleutel van een waarneming is de index in de lijst met tijdwaarden. De waarde is in procenten.
    /// We nemen de waarneming met de hoogste index die een waarde heeft.
    static func ecbDepositRate(_ data: Data) throws -> RateReading {
        let what = "de spaarrente"
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let dataSets = root["dataSets"] as? [Any],
              let firstSet = dataSets.first as? [String: Any],
              let series = firstSet["series"] as? [String: Any] else { throw MarketDataError.parse(what) }

        let times = observationTimes(root)

        for seriesKey in series.keys.sorted() {
            guard let entry = series[seriesKey] as? [String: Any],
                  let observations = entry["observations"] as? [String: Any] else { continue }

            var newest: (index: Int, percent: Double)?
            for (rawKey, raw) in observations {
                guard let index = Int(rawKey), index >= 0,
                      let list = raw as? [Any],
                      let percent = number(list.first),
                      percent.isFinite else { continue }
                if let current = newest, current.index >= index { continue }
                newest = (index, percent)
            }
            guard let found = newest else { continue }

            var label = "ECB-depositorente"
            var asOf: Date?
            if found.index < times.count {
                let text = times[found.index]
                if let parts = isoParts(text) {
                    label += " per " + describe(parts)
                    asOf = makeDate(parts)
                }
            }
            return RateReading(value: found.percent / 100, label: label, source: "Europese Centrale Bank", asOf: asOf)
        }
        throw MarketDataError.parse(what)
    }

    /// De tijdwaarden van de waarnemingen, in volgorde van index (leeg als de structuur ontbreekt).
    private static func observationTimes(_ root: [String: Any]) -> [String] {
        guard let structure = root["structure"] as? [String: Any],
              let dimensions = structure["dimensions"] as? [String: Any],
              let observation = dimensions["observation"] as? [Any] else { return [] }
        let dims = observation.compactMap { $0 as? [String: Any] }
        let time = dims.first(where: { ($0["id"] as? String) == "TIME_PERIOD" }) ?? dims.first
        guard let values = time?["values"] as? [Any] else { return [] }
        return values.map { raw -> String in
            guard let value = raw as? [String: Any] else { return "" }
            return (value["id"] as? String) ?? (value["name"] as? String) ?? ""
        }
    }

    // MARK: Historisch rendement

    static func clampYears(_ years: Int) -> Int {
        max(1, min(20, years))
    }

    /// De kortste vaste Yahoo-periode die `years` jaar omvat. Yahoo accepteert alleen 1y, 2y, 5y, 10y en max.
    static func yahooRange(forYears years: Int) -> String {
        switch clampYears(years) {
        case 1: return "1y"
        case 2: return "2y"
        case 3...5: return "5y"
        case 6...10: return "10y"
        default: return "max"
        }
    }

    /// Jaarrendement (CAGR) uit maandkoersen, alleen koersgroei (geen dividend).
    /// Het eindpunt is de laatste koers. Het beginpunt is de koers die het dichtst bij `years` jaar eerder ligt;
    /// is de historie korter, dan wordt het oudste punt gebruikt en rekenen we met de werkelijke looptijd.
    static func historicalReturn(points: [PricePoint], symbol: String, years: Int) throws -> RateReading {
        let wanted = clampYears(years)
        guard let result = cagr(points: points, targetYears: Double(wanted)) else {
            throw MarketReturnError.tooLittleHistory(symbol)
        }
        let actualMonths = Int((result.years * 12).rounded())
        let wantedMonths = wanted * 12
        let shownMonths = abs(actualMonths - wantedMonths) <= 6 ? wantedMonths : actualMonths
        return RateReading(value: result.rate,
                           label: "Koersrendement \(symbol), \(Fmt.duration(months: shownMonths)) (alleen koersgroei, zonder dividend)",
                           source: "Yahoo Finance",
                           asOf: result.last.date)
    }

    /// CAGR = (laatste / eerste)^(1 / jaren) - 1, met de jaren uit de datums.
    /// Geeft `nil` bij minder dan twee bruikbare koersen (positief en eindig) of een looptijd korter dan een half jaar.
    /// Met `targetYears` wordt het beginpunt gekozen dat het dichtst bij zoveel jaar voor de laatste koers ligt.
    static func cagr(points: [PricePoint], targetYears: Double? = nil) -> CAGRResult? {
        let usable = points
            .filter { $0.close.isFinite && $0.close > 0 && $0.date.timeIntervalSince1970.isFinite }
            .sorted { $0.date < $1.date }
        guard usable.count >= 2, let last = usable.last else { return nil }

        var first = usable[0]
        if let target = targetYears, target > 0 {
            let wantedTime = last.date.timeIntervalSince1970 - target * secondsPerYear
            var bestDistance = abs(first.date.timeIntervalSince1970 - wantedTime)
            for point in usable.dropLast() {
                let distance = abs(point.date.timeIntervalSince1970 - wantedTime)
                if distance < bestDistance {
                    first = point
                    bestDistance = distance
                }
            }
        }

        let years = last.date.timeIntervalSince(first.date) / secondsPerYear
        guard years >= minimumYearsForReturn else { return nil }
        let rate = pow(last.close / first.close, 1 / years) - 1
        guard rate.isFinite else { return nil }
        return CAGRResult(rate: rate, years: years, first: first, last: last)
    }

    // MARK: Hulpjes

    /// Getal uit JSON: Double, Int, NSNumber of tekst. `null` en al het andere geven `nil`.
    private static func number(_ raw: Any?) -> Double? {
        guard let value = raw else { return nil }
        if value is NSNull { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let boxed = value as? NSNumber { return boxed.doubleValue }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        guard let value = raw else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite, abs(double) < 1e9, double == double.rounded() { return Int(double) }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    /// "2024", "2024-06" of "2024-06-12" (eventueel met een tijd erachter).
    fileprivate static func isoParts(_ text: String) -> DateParts? {
        let pieces = text.prefix(10).split(separator: "-")
        guard let head = pieces.first, head.count == 4, let year = Int(head) else { return nil }
        var parts = DateParts(year: year, month: nil, day: nil)
        if pieces.count > 1, let month = Int(pieces[1]), (1...12).contains(month) {
            parts.month = month
            if pieces.count > 2, let day = Int(pieces[2]), (1...31).contains(day) {
                parts.day = day
            }
        }
        return parts
    }

    /// Altijd 12:00 UTC, zodat de dag in elke tijdzone hetzelfde blijft.
    fileprivate static func makeDate(_ parts: DateParts) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) { calendar.timeZone = utc }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month ?? 1
        components.day = parts.day ?? 1
        components.hour = 12
        return calendar.date(from: components)
    }

    /// "12 jun 2024", "jun 2024" of "2024", met vaste Nederlandse maandnamen (dus onafhankelijk van tijdzone en taalinstelling).
    fileprivate static func describe(_ parts: DateParts) -> String {
        guard let month = parts.month, (1...12).contains(month) else { return String(parts.year) }
        let name = Fmt.shortMonthNames[month - 1]
        if let day = parts.day { return "\(day) \(name) \(parts.year)" }
        return "\(name) \(parts.year)"
    }
}
