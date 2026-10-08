import Foundation

/// Opent een verbinding die berichten blijft sturen (Server-Sent Events) en geeft de regels door zodra ze binnenkomen.
protocol EventStreaming {
    /// Levert de ruwe bytes van de verbinding, regel voor regel. De stroom eindigt als de verbinding sluit.
    func chunks(for request: URLRequest) -> AsyncThrowingStream<Data, Error>
}

enum EventStreamError: Error, LocalizedError {
    case notHTTP
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notHTTP: return "Onverwacht antwoord van de cloud."
        case .badStatus(let code): return "De cloud weigerde de verbinding (code \(code))."
        }
    }
}

/// De echte verbinding, via URLSession. `bytes(for:)` leest zodra er data is; de database stuurt
/// ongeveer elke 30 seconden een keep-alive, zodat een weggevallen verbinding binnen 90 seconden opvalt.
struct URLSessionEventStream: EventStreaming {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 24 * 3600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func chunks(for request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw EventStreamError.notHTTP }
                    guard http.statusCode == 200 else { throw EventStreamError.badStatus(http.statusCode) }
                    var line = Data()
                    for try await byte in bytes {
                        line.append(byte)
                        if byte == 0x0A {
                            continuation.yield(line)
                            line.removeAll(keepingCapacity: true)
                        }
                    }
                    if !line.isEmpty { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
