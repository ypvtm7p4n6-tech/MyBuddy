import Foundation

/// Eén cijfer dat van internet is gehaald, met de bron erbij zodat de gebruiker kan zien waar het vandaan komt.
struct RateReading: Equatable {
    /// Als breuk: 0,023 betekent 2,3%.
    var value: Double
    /// Korte uitleg, bijv. "Inflatie Nederland, 2025".
    var label: String
    /// Naam van de bron, bijv. "Wereldbank" of "Europese Centrale Bank".
    var source: String
    /// Datum of periode waar het cijfer voor geldt, als bekend.
    var asOf: Date?
}

/// Haalt rekencijfers van internet. De app gebruikt dit voor inflatie, spaarrente en historisch rendement.
/// Alle methoden gooien een fout als de bron niet bereikbaar is of het antwoord niet te lezen is.
protocol MarketDataService {
    /// Jaarlijkse consumentenprijsinflatie in Nederland (laatst bekende jaar).
    func fetchInflation() async throws -> RateReading
    /// Rente die de ECB op deposito's geeft: een richtpunt voor spaarrente.
    func fetchSavingsBenchmarkRate() async throws -> RateReading
    /// Gemiddeld jaarrendement (CAGR, alleen koersgroei in euro) over de laatste `years` jaar.
    func historicalReturn(symbol: String, years: Int) async throws -> RateReading
}

enum MarketDataError: Error, LocalizedError {
    case unavailable(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let what): return "Kon \(what) niet ophalen. Controleer je internetverbinding."
        case .parse(let what): return "Het antwoord voor \(what) was niet te lezen."
        }
    }
}
