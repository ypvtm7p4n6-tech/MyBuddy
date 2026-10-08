import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MyBuddyCore

// Hulpmiddelen voor de tests van inloggen en synchroniseren: een nagebootste HTTP-laag, een nagebootste
// Realtime Database (met ETag en 412), een klok die de test zelf verzet en voorbeeldgegevens.

/// Een klok die de test zelf verzet.
final class CloudTestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Vaste, hele seconden: het opslagbestand rondt tijden op de seconde af.
let cloudT0 = Date(timeIntervalSince1970: 1_790_000_000)

func cloudAt(_ seconds: TimeInterval) -> Date { cloudT0.addingTimeInterval(seconds) }

/// Vaste id's, zodat twee keer dezelfde gegevens maken ook echt dezelfde gegevens oplevert.
func cloudUUID(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

/// Gegevens met inhoud (salaris, huur) en een vaste wijzigingstijd.
func cloudFinance(salary: Double = 3000, modified: Date? = cloudT0) -> FinanceData {
    var d = makeBaseData()
    d.salary.fixedMonthly = salary
    d.modifiedAt = modified
    for key in d.months.keys.sorted() {
        guard var plan = d.months[key] else { continue }
        for index in plan.expenses.indices { plan.expenses[index].id = cloudUUID(100 + index) }
        for index in plan.extraIncome.indices { plan.extraIncome[index].id = cloudUUID(200 + index) }
        d.months[key] = plan
    }
    return d
}

/// Een nieuw apparaat: niets ingevuld, geen wijzigingstijd.
func cloudPristine() -> FinanceData {
    var d = FinanceData(startMonth: aug2026)
    d.materialize(upTo: oct2026)
    return d
}

func cloudTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyBuddyCloudTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - HTTP voor de inlogdienst

final class CloudMockHTTP: HTTPClient {
    private(set) var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> (Int, String)

    init(_ handler: @escaping (URLRequest) throws -> (Int, String)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    func bodyText(_ index: Int) -> String {
        String(data: requests[index].httpBody ?? Data(), encoding: .utf8) ?? ""
    }

    func bodyJSON(_ index: Int) -> [String: Any] {
        guard let data = requests[index].httpBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    func path(_ index: Int) -> String { requests[index].url?.path ?? "" }
}

// MARK: - Nagebootste Realtime Database

/// Gedraagt zich als de REST-API van de Realtime Database voor één gebruiker: ETag, if-match, 412,
/// verlopen tokens en regels (alleen je eigen pad).
final class FakeRealtimeDatabase: HTTPClient {
    struct Logged {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: String
    }

    private(set) var log: [Logged] = []
    /// De JSON van het document zoals het nu in de database staat.
    private(set) var document: String?
    private(set) var version = 0
    var sendsETagOnWrite = true
    var offline = false
    var rejectedTokens: Set<String> = []
    var forbidWrites = false
    /// De schrijfactie wordt wel toegepast, maar het antwoord komt nooit aan (time-out, onderbroken verbinding).
    var dropResponseAfterWrite = false
    /// Wordt vlak voor het beoordelen van een PUT aangeroepen, om een gelijktijdige schrijver na te bootsen.
    var beforeWrite: (() -> Void)?

    var etag: String { document == nil ? "null_etag" : "etag-\(version)" }

    func methods() -> [String] { log.map { $0.method } }
    func count(_ method: String) -> Int { log.filter { $0.method == method }.count }

    /// Zet een document neer alsof een ander apparaat het schreef.
    func seed(_ finance: FinanceData, device: String = "ander apparaat", modified: Date? = nil) throws {
        let snapshot = try RemoteSnapshot(finance: finance, modifiedAt: modified, device: device)
        let envelope = CloudEnvelope(data: snapshot.json,
                                     modifiedAt: CloudSync.milliseconds(snapshot.modifiedAt),
                                     device: device,
                                     schema: FirebaseDatabaseClient.schemaVersion)
        document = String(data: try JSONEncoder().encode(envelope), encoding: .utf8)
        version += 1
    }

    func seedRaw(_ json: String?) {
        document = json
        version += 1
    }

    /// Het document als `RemoteSnapshot`, zoals een ander apparaat het zou lezen.
    func currentSnapshot() -> RemoteSnapshot? {
        guard let document, let data = document.data(using: .utf8),
              let reading = try? JSONDecoder().decode(CloudEnvelopeReading.self, from: data) else { return nil }
        return RemoteSnapshot(reading: reading, etag: etag)
    }

    func currentFinance() -> FinanceData? {
        try? currentSnapshot()?.decodeFinance()
    }

    private func reply(_ request: URLRequest, _ status: Int, _ body: String, etag: String? = nil) -> (Data, HTTPURLResponse) {
        var headers: [String: String] = [:]
        if let etag { headers["ETag"] = etag }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Een echt netwerkverzoek geeft de uitvoering even vrij; zo komen overlappende acties in de tests voor.
        await Task.yield()
        if offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let method = request.httpMethod ?? "GET"
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        // Headernamen zijn niet hoofdlettergevoelig; log ze in kleine letters.
        var headers: [String: String] = [:]
        for (name, value) in request.allHTTPHeaderFields ?? [:] { headers[name.lowercased()] = value }
        log.append(Logged(method: method, path: components.path, query: query, headers: headers, body: body))

        let token = query["auth"] ?? ""
        if rejectedTokens.contains(token) { return reply(request, 401, #"{"error":"Auth token is expired"}"#) }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "users" else { return reply(request, 404, "{}") }
        let uid = parts[1].hasSuffix(".json") ? String(parts[1].dropLast(5)) : parts[1]
        guard token == "tok-\(uid)" || token.hasPrefix("tok-\(uid)-") else {
            return reply(request, 401, #"{"error":"Permission denied"}"#)
        }
        let isFinance = parts.count == 3 && parts[2] == "finance.json"

        switch method {
        case "GET":
            guard isFinance else { return reply(request, 404, "{}") }
            return reply(request, 200, document ?? "null", etag: etag)
        case "PUT":
            guard isFinance else { return reply(request, 404, "{}") }
            beforeWrite?()
            // Het antwoord laat even op zich wachten: andere berichten kunnen er intussen tussendoor komen.
            await Task.yield()
            if forbidWrites { return reply(request, 401, #"{"error":"Permission denied"}"#) }
            if let ifMatch = request.value(forHTTPHeaderField: "if-match"), ifMatch != etag {
                return reply(request, 412, document ?? "null", etag: etag)
            }
            document = body
            version += 1
            if dropResponseAfterWrite { throw URLError(.timedOut) }
            return reply(request, 204, "", etag: sendsETagOnWrite ? etag : nil)
        case "DELETE":
            document = nil
            version += 1
            return reply(request, 200, "null")
        default:
            return reply(request, 405, "{}")
        }
    }
}
