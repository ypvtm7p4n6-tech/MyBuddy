import Foundation

// TIJDELIJKE STUB: wordt vervangen door de echte implementatie.
struct LiveMarketDataService: MarketDataService {
    func fetchInflation() async throws -> RateReading { throw MarketDataError.unavailable("de inflatie") }
    func fetchSavingsBenchmarkRate() async throws -> RateReading { throw MarketDataError.unavailable("de spaarrente") }
    func historicalReturn(symbol: String, years: Int) async throws -> RateReading { throw MarketDataError.unavailable("het rendement") }
}
