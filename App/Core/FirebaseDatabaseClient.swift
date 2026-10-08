import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Lezen en schrijven van de financiële gegevens in de Firebase Realtime Database via de REST-API
// (zonder Firebase-SDK). De gegevens staan als JSON-tekst onder /users/{uid}/finance:
//
//   { "data": "<JSON-tekst van FinanceData>", "modifiedAt": <milliseconden>, "device": "<naam>", "schema": 1 }
//
// De JSON-tekst is precies wat `FinanceStorage` in het bestand finance.json bewaart (zelfde encoder),
// zodat lokale bestanden en cloudgegevens uitwisselbaar zijn.

// MARK: - Fouten

enum FirebaseDatabaseError: Error, Equatable, LocalizedError {
    /// 401: het ID-token is verlopen of onleesbaar. Vernieuwen en opnieuw proberen helpt meestal.
    case unauthorized
    /// 401/403 met "Permission denied": de beveiligingsregels laten dit niet toe.
    case permissionDenied
    case databaseNotFound
    case tooLarge(bytes: Int)
    case network
    case server(Int)
    case badResponse
    case invalidUser
    case unreadable
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "De cloud weigerde je inlogsessie. Log opnieuw in als dit blijft gebeuren."
        case .permissionDenied:
            return "Geen toegang tot je gegevens in de cloud. Controleer of de regels uit firebase/database.rules.json in de Firebase-console zijn gepubliceerd."
        case .databaseNotFound:
            return "De database is niet gevonden. Controleer het databaseadres in FirebaseConfig.swift en of Realtime Database in de Firebase-console is aangemaakt."
        case .tooLarge(let bytes):
            let limit = Double(FirebaseDatabaseClient.maxBytes) / 1_000_000
            if bytes <= 0 {
                return String(format: "Je gegevens zijn te groot voor de cloud (maximaal %.1f MB).", limit)
            }
            let megabytes = Double(bytes) / 1_000_000
            return String(format: "Je gegevens zijn te groot voor de cloud (%.1f MB, maximaal %.1f MB).", megabytes, limit)
        case .network:
            return "Geen verbinding met de cloud."
        case .server(let code):
            return "De cloud gaf een fout (code \(code)). Probeer het later opnieuw."
        case .badResponse:
            return "Onverwacht antwoord van de cloud."
        case .invalidUser:
            return "Je account heeft een ongeldige gebruikers-ID. Log uit en weer in."
        case .unreadable:
            return "De gegevens in de cloud zijn niet te lezen. Werk de app bij of controleer de gegevens in de Firebase-console."
        case .unsupportedSchema:
            return "De gegevens in de cloud komen van een nieuwere versie van de app. Werk de app bij om te synchroniseren."
        }
    }
}

// MARK: - Het document in de cloud

/// Het document zoals het in de database staat.
struct CloudEnvelope: Codable, Equatable {
    var data: String
    var modifiedAt: Int64
    var device: String
    var schema: Int
}

/// Tolerant gelezen document: ontbrekende of anders getypte velden maken het hele antwoord niet onbruikbaar.
struct CloudEnvelopeReading: Decodable {
    var data: String?
    var modifiedAt: Double?
    var device: String?
    var schema: Int?

    enum CodingKeys: String, CodingKey { case data, modifiedAt, device, schema }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try? c.decode(String.self, forKey: .data)
        modifiedAt = try? c.decode(Double.self, forKey: .modifiedAt)
        device = try? c.decode(String.self, forKey: .device)
        schema = try? c.decode(Int.self, forKey: .schema)
    }

    /// Een volledig document heeft in elk geval tekst en een tijdstip.
    var isComplete: Bool { data != nil && modifiedAt != nil }
}

/// Wat er op dit moment in de cloud staat.
struct RemoteSnapshot: Equatable {
    /// De JSON-tekst van FinanceData.
    var json: String
    var modifiedAt: Date
    var device: String
    var schema: Int
    /// ETag van de database bij het ophalen; nodig om voorwaardelijk te schrijven. nil als onbekend.
    var etag: String?

    init(json: String, modifiedAt: Date, device: String = "", schema: Int = FirebaseDatabaseClient.schemaVersion, etag: String? = nil) {
        self.json = json
        self.modifiedAt = modifiedAt
        self.device = device
        self.schema = schema
        self.etag = etag
    }

    /// Maakt een document van gegevens, zoals de app het zou schrijven (tijdstip = wijzigingstijd van de gegevens).
    init(finance: FinanceData, modifiedAt: Date? = nil, device: String = "", etag: String? = nil) throws {
        let text = try FirebaseDatabaseClient.encodeFinance(finance)
        self.init(json: text,
                  modifiedAt: modifiedAt ?? finance.modifiedAt ?? Date(timeIntervalSince1970: 0),
                  device: device,
                  schema: FirebaseDatabaseClient.schemaVersion,
                  etag: etag)
    }

    init?(reading: CloudEnvelopeReading, etag: String?) {
        guard let text = reading.data, let millis = reading.modifiedAt else { return nil }
        self.init(json: text,
                  modifiedAt: CloudSync.date(milliseconds: millis),
                  device: reading.device ?? "",
                  schema: reading.schema ?? FirebaseDatabaseClient.schemaVersion,
                  etag: etag)
    }

    var isSupported: Bool { schema <= FirebaseDatabaseClient.schemaVersion }

    func decodeFinance() throws -> FinanceData {
        guard let bytes = json.data(using: .utf8) else { throw FirebaseDatabaseError.unreadable }
        do {
            return try FinanceStorage.makeDecoder().decode(FinanceData.self, from: bytes)
        } catch {
            throw FirebaseDatabaseError.unreadable
        }
    }
}

/// Uitkomst van een schrijfactie.
enum FirebaseWriteResult: Equatable {
    case written(WriteReceipt)
    /// 412: de ETag klopte niet, iemand anders schreef in de tussentijd.
    case preconditionFailed
}

struct WriteReceipt: Equatable {
    /// ETag na het schrijven, als de database hem meestuurde.
    var etag: String?
    /// Het document zoals het is weggeschreven.
    var snapshot: RemoteSnapshot
    var bytes: Int
    /// Boven ~5 MB: de gegevens worden groot. Boven ~7,5 MB schrijft de app niet meer.
    var sizeWarning: Bool
}

// MARK: - Client

struct FirebaseDatabaseClient {
    let baseURL: URL
    let http: any HTTPClient

    static let schemaVersion = 1
    /// ETag die zegt: "schrijf alleen als er nog niets staat".
    static let nullETag = "null_etag"
    static let warnBytes = 5_000_000
    /// De regels staan teksten tot 8 miljoen tekens toe; hier blijven we daar ruim onder.
    static let maxBytes = 7_500_000

    init(baseURL: URL, http: any HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.http = http
    }

    init?(databaseURL: String, http: any HTTPClient = URLSessionHTTPClient()) {
        guard let url = URL(string: databaseURL), url.scheme == "https", url.host != nil else { return nil }
        self.init(baseURL: url, http: http)
    }

    // MARK: Adressen

    /// Een Firebase-uid bestaat uit letters en cijfers. Alles anders wordt geweigerd, zodat er nooit een
    /// ander pad dan /users/{uid} kan ontstaan.
    static func isValidUID(_ uid: String) -> Bool {
        guard !uid.isEmpty, uid.count <= 128 else { return false }
        return uid.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
                || scalar == "-" || scalar == "_"
        }
    }

    /// /users/{uid}/finance.json?auth=TOKEN (en eventuele extra opties).
    func financeURL(uid: String, idToken: String?, silent: Bool = false) throws -> URL {
        try url(path: "/users/\(uid)/finance.json", uid: uid, idToken: idToken, silent: silent)
    }

    /// /users/{uid}.json?auth=TOKEN: alles van deze gebruiker.
    func userURL(uid: String, idToken: String?) throws -> URL {
        try url(path: "/users/\(uid).json", uid: uid, idToken: idToken, silent: false)
    }

    private func url(path: String, uid: String, idToken: String?, silent: Bool) throws -> URL {
        guard Self.isValidUID(uid) else { throw FirebaseDatabaseError.invalidUser }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw FirebaseDatabaseError.badResponse
        }
        components.path = path
        var items: [URLQueryItem] = []
        if let idToken { items.append(URLQueryItem(name: "auth", value: idToken)) }
        if silent { items.append(URLQueryItem(name: "print", value: "silent")) }
        components.queryItems = items.isEmpty ? nil : items
        guard let result = components.url else { throw FirebaseDatabaseError.badResponse }
        return result
    }

    // MARK: Coderen

    static func encodeFinance(_ finance: FinanceData) throws -> String {
        let data = try FinanceStorage.makeEncoder().encode(finance)
        guard let text = String(data: data, encoding: .utf8) else { throw FirebaseDatabaseError.badResponse }
        return text
    }

    // MARK: Lezen

    /// Haalt het document op. `nil` betekent: er staat nog niets in de cloud.
    func fetchFinance(uid: String, idToken: String) async throws -> RemoteSnapshot? {
        var request = URLRequest(url: try financeURL(uid: uid, idToken: idToken))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("true", forHTTPHeaderField: "X-Firebase-ETag")
        let (data, response) = try await perform(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, body: data) }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || text == "null" { return nil }
        guard let reading = try? JSONDecoder().decode(CloudEnvelopeReading.self, from: data),
              let snapshot = RemoteSnapshot(reading: reading, etag: response.value(forHTTPHeaderField: "ETag")) else {
            throw FirebaseDatabaseError.unreadable
        }
        return snapshot
    }

    // MARK: Schrijven

    /// Schrijft het document. Met `ifMatch` alleen als de database nog die versie heeft (gebruik `nullETag` als er
    /// nog niets mag staan). Een 412 komt terug als `.preconditionFailed`.
    func writeFinance(_ finance: FinanceData, uid: String, idToken: String, device: String,
                      ifMatch etag: String?) async throws -> FirebaseWriteResult {
        let text = try Self.encodeFinance(finance)
        let stamp = finance.modifiedAt ?? Date()
        let envelope = CloudEnvelope(data: text,
                                     modifiedAt: CloudSync.milliseconds(stamp),
                                     device: String(device.prefix(120)),
                                     schema: Self.schemaVersion)
        let body = try JSONEncoder().encode(envelope)
        if body.count > Self.maxBytes { throw FirebaseDatabaseError.tooLarge(bytes: body.count) }

        var request = URLRequest(url: try financeURL(uid: uid, idToken: idToken, silent: true))
        request.httpMethod = "PUT"
        request.httpBody = body
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "X-Firebase-ETag")
        if let etag, !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "if-match") }

        let (data, response) = try await perform(request)
        if response.statusCode == 412 { return .preconditionFailed }
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, body: data) }

        let snapshot = RemoteSnapshot(json: text,
                                      modifiedAt: CloudSync.date(milliseconds: Double(envelope.modifiedAt)),
                                      device: envelope.device,
                                      schema: envelope.schema,
                                      etag: response.value(forHTTPHeaderField: "ETag"))
        return .written(WriteReceipt(etag: snapshot.etag,
                                     snapshot: snapshot,
                                     bytes: body.count,
                                     sizeWarning: body.count > Self.warnBytes))
    }

    /// Verwijdert alles van deze gebruiker (/users/{uid}). Een gebruiker die niets heeft is ook goed.
    func deleteUserData(uid: String, idToken: String) async throws {
        var request = URLRequest(url: try userURL(uid: uid, idToken: idToken))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await perform(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(status: response.statusCode, body: data) }
    }

    // MARK: Live volgen

    /// Verzoek voor Server-Sent Events: de database stuurt zelf een bericht bij elke wijziging.
    func streamRequest(uid: String, idToken: String) throws -> URLRequest {
        var request = URLRequest(url: try financeURL(uid: uid, idToken: idToken))
        request.httpMethod = "GET"
        // Idle-time-out: de database stuurt ongeveer elke 30 seconden een keep-alive.
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    // MARK: Intern

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await http.data(for: request)
        } catch {
            if QuoteHTTP.isCancellation(error) { throw error }
            throw FirebaseDatabaseError.network
        }
    }

    /// Foutcodes van de database. Een 401 met "Permission denied" is een regelkwestie; andere 401's
    /// betekenen meestal een verlopen token.
    static func error(status: Int, body: Data) -> FirebaseDatabaseError {
        let text = (String(data: body, encoding: .utf8) ?? "").lowercased()
        switch status {
        case 401, 403:
            return text.contains("permission denied") ? .permissionDenied : .unauthorized
        case 404:
            return .databaseNotFound
        case 413:
            return .tooLarge(bytes: 0)
        default:
            return .server(status)
        }
    }
}
