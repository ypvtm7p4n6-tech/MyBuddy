import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// De regels van het synchroniseren, zonder netwerk en zonder scherm, zodat ze volledig te testen zijn:
// - `CloudSync.reconcile`: wat doen we als lokale en cloudgegevens verschillen?
// - `SyncDebouncer`: wanneer schrijven we na een wijziging?
// - `ReconnectBackoff`: hoe lang wachten we voor we opnieuw verbinden?
// - `SSEParser` en `FirebaseStreamMessage`: berichten van de database lezen
// - `SyncState`, `ConflictBackupStore`, `LocalDataFinder`: kleine bestanden op het apparaat
//
// Uitgangspunt: een "versie" van de gegevens heeft een tijdstempel (`FinanceData.modifiedAt`, in de cloud
// `modifiedAt` in milliseconden). We bewaren welke versie we als laatste hebben gesynchroniseerd en
// vergelijken tijdstempels alleen op gelijkheid ("is dit nog dezelfde versie?"). Zo hebben verschillende
// klokken op iPhone, iPad en Mac geen invloed op de beslissing. De klokscheefheid-tolerantie van 60 seconden
// bepaalt alleen welke kant je als "nieuwste" mag aanwijzen bij een conflict.

// MARK: - Beslissing

enum SyncDecision: Equatable {
    /// Niets te doen: gelijk, of beide leeg.
    case noop
    /// Lokaal is veranderd, de cloud niet (of de cloud is leeg): upload.
    case pushLocal
    /// De cloud is veranderd, lokaal niet (of lokaal is leeg): download.
    case pullRemote
    /// Beide kanten zijn veranderd en verschillen echt: de gebruiker kiest.
    case conflict(localModified: Date?, remoteModified: Date?)
}

enum ConflictSide: Equatable {
    case local, remote
}

enum CloudSync {
    /// Hoeveel twee tijdstippen van verschillende apparaten mogen verschillen voordat we één als "nieuwer" aanwijzen.
    static let clockSkewTolerance: TimeInterval = 60
    /// Tijdstempels in het opslagbestand zijn op de seconde afgerond (naar beneden). Een lokale tijd mag daarom
    /// tot een seconde ouder zijn dan de versie waar hij bij hoort.
    static let stampPrecision: TimeInterval = 1
    /// Tijdstempels in de cloud zijn in milliseconden. Rond je een tijd af, dan verschilt hij hooguit een halve milliseconde.
    static let millisecondTolerance: TimeInterval = 0.001

    // MARK: Tijdstempels

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }

    /// Zijn twee tijden uit de cloud (of uit de bewaarde staat) dezelfde versie? Alleen afrondingen op de milliseconde tellen mee.
    static func sameStamp(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case (let x?, let y?):
            return abs(x.timeIntervalSince(y)) <= millisecondTolerance
        default:
            return false
        }
    }

    /// Hoort de wijzigingstijd van de lokale gegevens bij deze versie? De lokale tijd kan na opslaan en weer inlezen
    /// tot een seconde zijn afgerond (naar beneden), of een afrondingsverschil van een milliseconde hebben.
    /// Een lokale tijd die duidelijk later is, is een nieuwe wijziging, ook als dat maar een halve seconde scheelt.
    static func localMatches(_ local: Date?, _ version: Date?) -> Bool {
        switch (local, version) {
        case (nil, nil):
            return true
        case (let l?, let v?):
            let behind = v.timeIntervalSince(l)   // positief: lokaal is ouder dan de versie
            return behind >= -millisecondTolerance && behind < stampPrecision
        default:
            return false
        }
    }

    /// Welke kant is duidelijk nieuwer? `nil` als ze binnen de klokscheefheid liggen of een tijd onbekend is.
    static func newerSide(localModified: Date?, remoteModified: Date?) -> ConflictSide? {
        guard let l = localModified, let r = remoteModified else { return nil }
        let difference = l.timeIntervalSince(r)
        if abs(difference) <= clockSkewTolerance { return nil }
        return difference > 0 ? .local : .remote
    }

    // MARK: Inhoud

    /// Zitten er echt gegevens in? Een nieuw apparaat met alleen standaardinstellingen telt als leeg.
    /// Instellingen tellen niet mee: die worden soms vanzelf bijgewerkt (inflatie, rente).
    static func hasContent(_ data: FinanceData) -> Bool {
        if !data.pots.isEmpty || !data.potEntries.isEmpty || !data.holdings.isEmpty { return true }
        if !data.bankSnapshots.isEmpty || !data.bankEntries.isEmpty || !data.goals.isEmpty { return true }
        if !data.appliedAccelerators.isEmpty { return true }
        if data.salary != SalarySettings() { return true }
        for plan in data.months.values {
            if !plan.expenses.isEmpty || !plan.extraIncome.isEmpty { return true }
            if plan.salaryOverride != nil || plan.hoursOverride != nil || plan.transferDay != nil { return true }
            if !plan.allocations.isEmpty { return true }
        }
        return false
    }

    /// Een apparaat waar nog nooit iets is ingevuld: geen gegevens en geen wijzigingstijd.
    static func isPristine(_ data: FinanceData?) -> Bool {
        guard let data else { return true }
        return data.modifiedAt == nil && !hasContent(data)
    }

    /// Zijn de gegevens hetzelfde, los van de wijzigingstijd? Vergelijkt de JSON-tekst zoals die wordt opgeslagen,
    /// zodat tijdstippen die op de seconde zijn afgerond geen vals verschil geven.
    static func contentEqual(_ a: FinanceData, _ b: FinanceData) -> Bool {
        var left = a
        var right = b
        left.modifiedAt = nil
        right.modifiedAt = nil
        let encoder = FinanceStorage.makeEncoder()
        guard let x = try? encoder.encode(left), let y = try? encoder.encode(right) else { return false }
        return x == y
    }

    // MARK: Koersen

    /// De gegevens zonder wat de koersverversing vanzelf bijwerkt: de laatste koers van beleggingen met een ticker en
    /// (bij beleggingen die de live koers volgen) de meetpunten die daaruit volgen. Ook de wijzigingstijd is weg.
    /// Twee apparaten die op hetzelfde moment koersen verversen, verschillen alleen hierin (de meetpunten hebben een
    /// willekeurig id); dat is geen reden om de gebruiker te laten kiezen.
    static func withoutMarketData(_ data: FinanceData) -> FinanceData {
        var result = data
        result.modifiedAt = nil
        for index in result.holdings.indices where result.holdings[index].hasTicker {
            result.holdings[index].lastPrice = nil
            result.holdings[index].lastPriceDate = nil
            result.holdings[index].priceCurrency = nil
            if result.holdings[index].isTracked { result.holdings[index].snapshots = [] }
        }
        return result
    }

    /// Een korte vingerafdruk van de gegevens zonder koersen (zie `withoutMarketData`). Hiermee onthoudt de app
    /// hoe de gegevens er bij de laatste synchronisatie uitzagen, zonder een kopie te bewaren. `nil` als coderen mislukt.
    static func contentDigest(_ data: FinanceData) -> String? {
        guard let bytes = try? FinanceStorage.makeEncoder().encode(withoutMarketData(data)) else { return nil }
        // FNV-1a, 64 bit: dit is geen beveiliging, alleen "is er iets veranderd?".
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16) + "-" + String(bytes.count)
    }

    // MARK: Beslissen

    /// Bepaalt wat er moet gebeuren.
    ///
    /// - `local`: de gegevens op dit apparaat (`nil` = er is niets).
    /// - `localLastSyncedAt`: de tijdstempel (`modifiedAt`) van de versie die dit apparaat voor het laatst
    ///   succesvol heeft gesynchroniseerd, geüpload of gedownload. `nil` = nog nooit gesynchroniseerd.
    /// - `remote`: wat er nu in de cloud staat (`nil` = niets).
    /// - `localHasUnsyncedChanges`: de app weet dat er sinds de laatste synchronisatie iets is gewijzigd. Dat telt
    ///   mee naast de tijdstempels, want tijdstempels missen een wijziging die vlak na de synchronisatie volgt.
    /// - `syncedLocalDigest` en `syncedRemoteDigest`: de vingerafdruk (`contentDigest`) van de lokale gegevens en van
    ///   het cloudgegeven bij de laatste synchronisatie. Zijn beide bekend en zijn beide kanten veranderd, dan kijkt
    ///   `reconcile` of een kant alleen koersen veranderde. Dat is geen echte wijziging: de andere kant wint dan, en
    ///   verschillen allebei alleen in koersen, dan wint de nieuwste. Ontbreekt een vingerafdruk, dan blijft het een conflict.
    static func reconcile(local: FinanceData?, localLastSyncedAt: Date?, remote: RemoteSnapshot?,
                          localHasUnsyncedChanges: Bool = false,
                          syncedLocalDigest: String? = nil, syncedRemoteDigest: String? = nil) -> SyncDecision {
        let localHasContent = local.map(hasContent) ?? false

        // De cloud is leeg: bestaande lokale gegevens gaan erheen, anders valt er niets te doen.
        guard let remote else { return localHasContent ? .pushLocal : .noop }

        // Een apparaat waar nog nooit iets is ingevuld, neemt de cloud over.
        guard let local, !isPristine(local) else { return .pullRemote }

        let localModified = local.modifiedAt
        let remoteModified = remote.modifiedAt

        // Zelfde versie (bijvoorbeeld: ons eigen antwoord ging verloren).
        if !localHasUnsyncedChanges && localMatches(localModified, remoteModified) { return .noop }

        let remoteData = try? remote.decodeFinance()
        // Onleesbare cloudgegevens behandelen we voorzichtig als "gevuld".
        let remoteHasContent = remoteData.map(hasContent) ?? true
        let identical = remoteData.map { contentEqual(local, $0) } ?? false

        guard let synced = localLastSyncedAt else {
            // Nooit gesynchroniseerd op dit apparaat: we weten niet wie van wie afstamt.
            switch (localHasContent, remoteHasContent) {
            case (false, false): return .noop
            case (true, false): return .pushLocal
            case (false, true): return .pullRemote
            case (true, true):
                return identical ? .noop : .conflict(localModified: localModified, remoteModified: remoteModified)
            }
        }

        let localChanged = localHasUnsyncedChanges || !localMatches(localModified, synced)
        let remoteChanged = !sameStamp(remoteModified, synced)
        switch (localChanged, remoteChanged) {
        case (false, false):
            return .noop
        case (true, false):
            return .pushLocal
        case (false, true):
            return .pullRemote
        case (true, true):
            if identical { return .noop }
            if let syncedLocalDigest, let syncedRemoteDigest, let remoteData,
               let localNow = contentDigest(local), let remoteNow = contentDigest(remoteData) {
                let localContentChanged = localNow != syncedLocalDigest
                let remoteContentChanged = remoteNow != syncedRemoteDigest
                switch (localContentChanged, remoteContentChanged) {
                case (true, true):
                    break
                case (true, false):
                    return .pushLocal
                case (false, true):
                    return .pullRemote
                case (false, false):
                    // Allebei alleen andere koersen: de nieuwste versie wint, bij gelijke tijd de lokale.
                    return (localModified ?? .distantPast) >= remoteModified ? .pushLocal : .pullRemote
                }
            }
            return .conflict(localModified: localModified, remoteModified: remoteModified)
        }
    }
}

// MARK: - Wanneer schrijven?

/// Schrijft 1,5 seconde nadat de laatste wijziging binnenkwam, hoogstens elke 5 seconden, en
/// uiterlijk 15 seconden nadat de eerste onverstuurde wijziging binnenkwam (ook als je blijft typen).
struct SyncDebouncer: Equatable {
    var quietPeriod: TimeInterval
    var minimumInterval: TimeInterval
    var maximumWait: TimeInterval
    private(set) var pendingSince: Date?
    private(set) var lastChange: Date?
    private(set) var lastPush: Date?

    init(quietPeriod: TimeInterval = 1.5, minimumInterval: TimeInterval = 5, maximumWait: TimeInterval = 15) {
        self.quietPeriod = quietPeriod
        self.minimumInterval = minimumInterval
        self.maximumWait = maximumWait
    }

    var hasPending: Bool { pendingSince != nil }

    mutating func recordChange(at now: Date) {
        if pendingSince == nil { pendingSince = now }
        lastChange = now
    }

    /// Het moment waarop geschreven mag worden. `nil` als er niets wacht.
    func fireDate() -> Date? {
        guard let pendingSince, let lastChange else { return nil }
        var fire = min(lastChange.addingTimeInterval(quietPeriod), pendingSince.addingTimeInterval(maximumWait))
        if let lastPush {
            fire = max(fire, lastPush.addingTimeInterval(minimumInterval))
        }
        return fire
    }

    /// Seconden tot het schrijven, 0 als het nu mag, `nil` als er niets wacht.
    func delay(at now: Date) -> TimeInterval? {
        guard let fire = fireDate() else { return nil }
        return max(0, fire.timeIntervalSince(now))
    }

    func isDue(at now: Date) -> Bool {
        guard let delay = delay(at: now) else { return false }
        return delay <= 0
    }

    /// Roep aan op het moment dat de te schrijven gegevens worden gelezen. Wat daarna verandert, wacht opnieuw.
    mutating func beginPush(at now: Date) {
        lastPush = now
        pendingSince = nil
        lastChange = nil
    }

    /// Er bleek niets te schrijven: vergeet de wachtende wijziging.
    mutating func discardPending() {
        pendingSince = nil
        lastChange = nil
    }

    /// Het schrijven lukte niet: de gegevens zijn nog niet weg.
    mutating func restorePending(at now: Date) {
        if pendingSince == nil { pendingSince = now }
        if lastChange == nil { lastChange = now }
    }

    mutating func reset() {
        pendingSince = nil
        lastChange = nil
        lastPush = nil
    }
}

// MARK: - Opnieuw verbinden

/// Wachttijden bij opnieuw verbinden: 1, 2, 4, 8, 16, 32 en dan steeds 60 seconden.
struct ReconnectBackoff: Equatable {
    var base: TimeInterval = 1
    var maximum: TimeInterval = 60
    private(set) var attempts = 0

    init(base: TimeInterval = 1, maximum: TimeInterval = 60) {
        self.base = base
        self.maximum = maximum
    }

    mutating func nextDelay() -> TimeInterval {
        let steps = min(attempts, 20)
        attempts += 1
        return min(maximum, base * Double(1 << steps))
    }

    mutating func reset() {
        attempts = 0
    }
}

// MARK: - Server-Sent Events

struct SSEEvent: Equatable {
    var event: String
    var data: String
}

/// Leest een stroom Server-Sent Events. De stukjes data mogen overal breken: midden in een regel, midden in een
/// teken of tussen CR en LF. Een gebeurtenis is klaar bij een lege regel.
struct SSEParser {
    private var line: [UInt8] = []
    private var skipLineFeed = false
    private var eventName = ""
    private var dataLines: [String] = []

    init() {}

    mutating func feed(_ chunk: Data) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for byte in chunk {
            if skipLineFeed {
                skipLineFeed = false
                if byte == 0x0A { continue }
            }
            switch byte {
            case 0x0A:
                finishLine(into: &events)
            case 0x0D:
                finishLine(into: &events)
                skipLineFeed = true
            default:
                line.append(byte)
            }
        }
        return events
    }

    mutating func feed(_ text: String) -> [SSEEvent] {
        feed(Data(text.utf8))
    }

    mutating func reset() {
        line.removeAll()
        skipLineFeed = false
        eventName = ""
        dataLines = []
    }

    private mutating func finishLine(into events: inout [SSEEvent]) {
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)

        if text.isEmpty {
            if !dataLines.isEmpty {
                events.append(SSEEvent(event: eventName.isEmpty ? "message" : eventName,
                                       data: dataLines.joined(separator: "\n")))
            }
            eventName = ""
            dataLines = []
            return
        }
        if text.hasPrefix(":") { return }   // commentaar

        let field: String
        var value: String
        if let colon = text.firstIndex(of: ":") {
            field = String(text[text.startIndex..<colon])
            value = String(text[text.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = text
            value = ""
        }
        switch field {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break   // id en retry hebben we niet nodig
        }
    }
}

/// Wat een bericht van de database betekent voor ons.
enum FirebaseStreamMessage: Equatable {
    /// Het hele document (of `nil` als het is verwijderd).
    case snapshot(RemoteSnapshot?)
    /// Een deel van het document is veranderd: haal het geheel opnieuw op.
    case partialChange
    case keepAlive
    /// De database mag niet meer meekijken (regels).
    case cancel
    /// Het inlogtoken is verlopen: vernieuw het en verbind opnieuw.
    case authRevoked
    case unknown(String)

    private struct Payload: Decodable {
        enum Content {
            case null
            case envelope(CloudEnvelopeReading)
            case other
        }
        var path: String
        var content: Content

        enum CodingKeys: String, CodingKey { case path, data }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decodeIfPresent(String.self, forKey: .path) ?? "/"
            if !c.contains(.data) {
                content = .other
            } else if try c.decodeNil(forKey: .data) {
                content = .null
            } else if let reading = try? c.decode(CloudEnvelopeReading.self, forKey: .data), reading.isComplete {
                content = .envelope(reading)
            } else {
                content = .other
            }
        }
    }

    static func interpret(_ event: SSEEvent) -> FirebaseStreamMessage {
        switch event.event {
        case "keep-alive":
            return .keepAlive
        case "cancel":
            return .cancel
        case "auth_revoked":
            return .authRevoked
        case "put", "patch":
            guard let bytes = event.data.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(Payload.self, from: bytes) else {
                return .unknown(event.event)
            }
            // Wij schrijven altijd het hele document. Alles wat daar niet op lijkt: opnieuw ophalen.
            guard event.event == "put", payload.path == "/" else { return .partialChange }
            switch payload.content {
            case .null:
                return .snapshot(nil)
            case .envelope(let reading):
                if let snapshot = RemoteSnapshot(reading: reading, etag: nil) { return .snapshot(snapshot) }
                return .partialChange
            case .other:
                return .partialChange
            }
        default:
            return .unknown(event.event)
        }
    }
}

// MARK: - Staat van het synchroniseren (per account, op dit apparaat)

struct SyncState: Codable, Equatable {
    /// Tijdstempel van de versie die voor het laatst is gesynchroniseerd (zie `CloudSync.reconcile`).
    var lastSyncedStamp: Date?
    /// Wanneer dat gebeurde, voor "laatst gesynchroniseerd".
    var lastSyncedAt: Date?
    /// Is er sinds die synchronisatie iets gewijzigd dat de cloud nog niet kent? Dit blijft bewaard, ook na afsluiten.
    var dirty: Bool
    /// Wijzigingstijd van een schrijfactie die is verstuurd maar waarvan het antwoord nog niet binnen is. Is het
    /// antwoord verloren gegaan (time-out), dan herkent de motor de versie in de cloud als zijn eigen schrijfactie.
    var inFlightStamp: Date?
    /// Vingerafdruk (`CloudSync.contentDigest`) van de lokale gegevens bij de laatste synchronisatie.
    var syncedLocalDigest: String?
    /// Vingerafdruk van de versie in de cloud bij de laatste synchronisatie.
    var syncedRemoteDigest: String?

    init(lastSyncedStamp: Date? = nil, lastSyncedAt: Date? = nil, dirty: Bool = false,
         inFlightStamp: Date? = nil, syncedLocalDigest: String? = nil, syncedRemoteDigest: String? = nil) {
        self.lastSyncedStamp = lastSyncedStamp
        self.lastSyncedAt = lastSyncedAt
        self.dirty = dirty
        self.inFlightStamp = inFlightStamp
        self.syncedLocalDigest = syncedLocalDigest
        self.syncedRemoteDigest = syncedRemoteDigest
    }

    enum CodingKeys: String, CodingKey {
        case lastSyncedStamp, lastSyncedAt, dirty, inFlightStamp, syncedLocalDigest, syncedRemoteDigest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastSyncedStamp = try c.decodeIfPresent(Date.self, forKey: .lastSyncedStamp)
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        dirty = try c.decodeIfPresent(Bool.self, forKey: .dirty) ?? false
        inFlightStamp = try c.decodeIfPresent(Date.self, forKey: .inFlightStamp)
        syncedLocalDigest = try c.decodeIfPresent(String.self, forKey: .syncedLocalDigest)
        syncedRemoteDigest = try c.decodeIfPresent(String.self, forKey: .syncedRemoteDigest)
    }
}

protocol SyncStateStore {
    func load() -> SyncState
    func save(_ state: SyncState)
    func clear()
}

struct FileSyncStateStore: SyncStateStore {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// cloud-<uid>.json naast het gegevensbestand.
    static func standard(directory: URL, uid: String) -> FileSyncStateStore {
        FileSyncStateStore(url: directory.appendingPathComponent("cloud-\(uid).json"))
    }

    func load() -> SyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    func save(_ state: SyncState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

final class MemorySyncStateStore: SyncStateStore {
    private(set) var state: SyncState
    private(set) var saveCount = 0

    init(_ state: SyncState = SyncState()) {
        self.state = state
    }

    func load() -> SyncState { state }

    func save(_ state: SyncState) {
        self.state = state
        saveCount += 1
    }

    func clear() {
        state = SyncState()
    }
}

// MARK: - Back-up van de verliezende versie

/// Bij een conflict bewaren we eerst de versie die verliest als bestand op dit apparaat, zodat er niets kwijtraakt.
struct ConflictBackupStore {
    enum Side: String {
        case local = "lokaal"
        case cloud = "cloud"
    }

    let directory: URL
    let uid: String
    var keepPerSide = 5

    init(directory: URL, uid: String, keepPerSide: Int = 5) {
        self.directory = directory
        self.uid = uid
        self.keepPerSide = keepPerSide
    }

    private func prefix(for side: Side) -> String {
        "finance-\(uid).backup-\(side.rawValue)-"
    }

    /// 20261008-143005, in UTC zodat de bestandsnaam niet van de regio afhangt.
    static func stamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return String(format: "%04d", c.year ?? 0) + two(c.month) + two(c.day) + "-" + two(c.hour) + two(c.minute) + two(c.second)
    }

    /// Schrijft de gegevens weg als finance-<uid>.backup-<kant>-<tijd>.json. Geeft het bestand terug, of `nil` bij een fout.
    @discardableResult
    func save(_ data: FinanceData, side: Side, at date: Date) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = prefix(for: side) + Self.stamp(date)
        var url = directory.appendingPathComponent(base + ".json")
        var counter = 2
        while fm.fileExists(atPath: url.path) && counter < 100 {
            url = directory.appendingPathComponent("\(base)-\(counter).json")
            counter += 1
        }
        do {
            let encoded = try FinanceStorage.makeEncoder().encode(data)
            try encoded.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        prune(side: side)
        return url
    }

    /// De back-ups van één kant, nieuwste eerst.
    func backups(side: Side) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let wanted = prefix(for: side)
        // Sorteren zonder ".json", zodat "…-141320-2" (tweede in dezelfde seconde) boven "…-141320" komt.
        return names
            .filter { $0.hasPrefix(wanted) && $0.hasSuffix(".json") }
            .sorted { String($0.dropLast(5)) > String($1.dropLast(5)) }
            .map { directory.appendingPathComponent($0) }
    }

    func removeAll() {
        for side in [Side.local, Side.cloud] {
            for url in backups(side: side) { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func prune(side: Side) {
        let all = backups(side: side)
        guard all.count > keepPerSide else { return }
        for url in all.dropFirst(keepPerSide) { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - Lokale gegevens die mee kunnen naar een cloudaccount

struct LocalDataCandidate: Equatable {
    var url: URL
    var data: FinanceData
    /// Laatste wijziging: de nieuwste van `modifiedAt` en de bestandsdatum.
    var modified: Date
}

enum LocalDataFinder {
    /// finance.json (van vóór accounts) of finance-<UUID>.json (een lokaal account). Bestanden van cloudaccounts
    /// (met een Firebase-uid), back-ups en onleesbare bestanden tellen niet mee.
    static func isLocalDataFileName(_ name: String) -> Bool {
        if name == "finance.json" { return true }
        let prefix = "finance-"
        let suffix = ".json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { return false }
        let middle = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        return UUID(uuidString: middle) != nil
    }

    /// Alle lokale bestanden met echte gegevens, nieuwste eerst.
    static func find(in directory: URL) -> [LocalDataCandidate] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        var found: [LocalDataCandidate] = []
        for name in names where isLocalDataFileName(name) {
            let url = directory.appendingPathComponent(name)
            guard let raw = try? Data(contentsOf: url),
                  let data = try? FinanceStorage.makeDecoder().decode(FinanceData.self, from: raw),
                  CloudSync.hasContent(data) else { continue }
            let fileDate = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            let modified = [data.modifiedAt, fileDate].compactMap { $0 }.max() ?? Date(timeIntervalSince1970: 0)
            found.append(LocalDataCandidate(url: url, data: data, modified: modified))
        }
        return found.sorted { $0.modified > $1.modified }
    }
}

// MARK: - Account verwijderen

enum CloudAccountOperations {
    /// Verwijdert eerst de gegevens in de database (daarvoor moet je nog ingelogd zijn), dan het account zelf.
    /// Vraagt om het wachtwoord: de actie eist een verse login, en zo kan niemand per ongeluk je account wissen.
    /// Mislukt het wissen van de gegevens (bijvoorbeeld geen internet), dan blijft het account bestaan.
    static func deleteAccount(email: String, password: String,
                              auth: FirebaseAuthClient, database: FirebaseDatabaseClient) async throws {
        let session = try await auth.signIn(email: email, password: password)
        do {
            try await database.deleteUserData(uid: session.uid, idToken: session.idToken)
        } catch FirebaseDatabaseError.databaseNotFound {
            // Er is geen database om te wissen; het account zelf mag wel weg.
        }
        try await auth.deleteAccount(idToken: session.idToken)
    }
}
