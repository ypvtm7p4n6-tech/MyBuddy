import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// De motor van het synchroniseren: haalt op, beslist (`CloudSync.reconcile`), schrijft of downloadt, en
// verwerkt berichten van de database. Alles in Foundation, zonder scherm en zonder eigen netwerklaag, zodat het
// met een nagebootste database te testen is. De app (App/Cloud/SyncController) voegt er de klok, het
// netwerk en de scherminformatie aan toe.

// MARK: - Status

enum SyncStatus: Equatable {
    /// Geen cloudaccount of sleutel: de app werkt alleen lokaal.
    case disabled
    case connecting
    case synced(at: Date)
    case busy
    case offline
    case failed(String)
    case conflict
}

enum ConflictChoice: Equatable {
    /// "Bewaar deze versie": de lokale gegevens gaan naar de cloud.
    case keepLocal
    /// "Neem cloud-versie over": de cloudgegevens vervangen de lokale.
    case takeRemote
}

/// Beide versies bij een conflict.
struct SyncConflict: Equatable {
    var local: FinanceData
    var remote: RemoteSnapshot
    var localModified: Date?
    var remoteModified: Date?

    var remoteDevice: String { remote.device }

    /// Alleen ingevuld als het verschil groter is dan de klokscheefheid.
    var newerSide: ConflictSide? {
        CloudSync.newerSide(localModified: localModified, remoteModified: remoteModified)
    }
}

enum SyncOutcome: Equatable {
    case done
    case conflict
    case offline
    /// De sessie is ongeldig (verlopen of uitgeschakeld): opnieuw inloggen.
    case authExpired
    case failed(String)
}

/// Wat de verbinding moet doen na een bericht.
enum StreamAction: Equatable {
    case keepListening
    /// Sluit en verbind opnieuw (met een nieuw token).
    case reconnect
    case authExpired
    case stop(String)
}

// MARK: - Aansluitingen

/// Levert het ID-token van de ingelogde gebruiker, ververst indien nodig.
struct CloudTokenSource {
    var uid: String
    var idToken: @MainActor (_ forceRefresh: Bool) async throws -> String

    init(uid: String, idToken: @escaping @MainActor (_ forceRefresh: Bool) async throws -> String) {
        self.uid = uid
        self.idToken = idToken
    }
}

/// Toegang tot de lokale gegevens (in de app: de AppStore).
struct SyncLocalAccess {
    var read: @MainActor () -> FinanceData
    /// Neemt gegevens van de cloud over zonder ze meteen terug te sturen (`AppStore.applyRemote`).
    var apply: @MainActor (FinanceData) -> Void
    /// Geeft de huidige gegevens een wijzigingstijd (voor oude bestanden zonder tijd), als gewone wijziging.
    var stamp: @MainActor (Date) -> Void

    init(read: @escaping @MainActor () -> FinanceData,
         apply: @escaping @MainActor (FinanceData) -> Void,
         stamp: @escaping @MainActor (Date) -> Void) {
        self.read = read
        self.apply = apply
        self.stamp = stamp
    }
}

// MARK: - Motor

@MainActor
final class CloudSyncEngine {
    private let tokens: CloudTokenSource
    private let database: FirebaseDatabaseClient
    private let local: SyncLocalAccess
    private let stateStore: any SyncStateStore
    private let backups: ConflictBackupStore?
    private let clock: () -> Date
    /// Wachttijd voordat een verdwenen document wordt teruggezet (zie `confirmAccountStillExists`).
    private let restoreGrace: TimeInterval
    /// Naam van dit apparaat in de cloud, uniek genoeg om je eigen schrijfacties te herkennen.
    let device: String

    private(set) var status: SyncStatus = .connecting {
        didSet { if status != oldValue { onChange?() } }
    }
    private(set) var conflict: SyncConflict? {
        didSet { onChange?() }
    }
    private(set) var state: SyncState
    /// Is er minstens één keer succesvol vergeleken met de cloud? Daarvoor wordt er niets geschreven.
    private(set) var isReady = false
    private(set) var debouncer: SyncDebouncer
    private(set) var lastPayloadBytes = 0
    private(set) var sizeWarning = false
    /// Wordt aangeroepen als status, conflict of staat verandert (voor het scherm).
    var onChange: (() -> Void)?

    private var knownETag: String?
    private var lastPushedStamp: Date?
    private var isBusy = false
    private var rerunRequested = false
    /// Telt de lokale wijzigingen, zodat wat tijdens het schrijven verandert niet als "verstuurd" wordt afgevinkt.
    private var changeCounter = 0

    init(tokens: CloudTokenSource,
         database: FirebaseDatabaseClient,
         local: SyncLocalAccess,
         stateStore: any SyncStateStore,
         backups: ConflictBackupStore? = nil,
         device: String,
         debouncer: SyncDebouncer = SyncDebouncer(),
         restoreGrace: TimeInterval = 3,
         clock: @escaping () -> Date = { Date() }) {
        self.restoreGrace = restoreGrace
        self.tokens = tokens
        self.database = database
        self.local = local
        self.stateStore = stateStore
        self.backups = backups
        self.device = device
        self.debouncer = debouncer
        self.clock = clock
        self.state = stateStore.load()
    }

    var lastSyncedAt: Date? { state.lastSyncedAt }

    // MARK: Wijzigingen van de gebruiker

    /// Een lokale wijziging is opgeslagen. Het schrijven zelf gebeurt via `pushIfNeeded()`.
    func localDidChange() {
        changeCounter += 1
        debouncer.recordChange(at: clock())
        if !state.dirty {
            state.dirty = true
            stateStore.save(state)
        }
    }

    /// Seconden tot er geschreven mag worden (0 = nu). `nil` als er niets te schrijven valt of het nog niet mag.
    func secondsUntilPush() -> TimeInterval? {
        guard isReady, conflict == nil else { return nil }
        return debouncer.delay(at: clock())
    }

    /// Is er een lokale wijziging die de cloud nog niet kent?
    var hasUnsyncedChanges: Bool {
        if state.dirty { return true }
        let current = local.read()
        return !CloudSync.localMatches(current.modifiedAt, state.lastSyncedStamp) && !CloudSync.isPristine(current)
    }

    // MARK: Synchroniseren

    /// Haalt de cloud op, beslist en doet wat nodig is. Gebruik dit bij het starten, bij "Nu synchroniseren"
    /// en na het terugkomen van het netwerk.
    @discardableResult
    func syncNow() async -> SyncOutcome {
        await serialized { await self.fullCycle() }
    }

    /// Schrijft wijzigingen weg. Met een bekende ETag gaat dat in één verzoek; anders eerst vergelijken.
    @discardableResult
    func pushIfNeeded() async -> SyncOutcome {
        await serialized { await self.fastPushOrCycle() }
    }

    /// Zet de gebruiker de keuze voor een conflict door.
    @discardableResult
    func resolve(_ choice: ConflictChoice) async -> SyncOutcome {
        guard let pending = conflict else { return .done }
        return await serialized { await self.performResolve(choice, pending) }
    }

    func connectionLost(offline: Bool) {
        status = offline ? .offline : .connecting
    }

    func markConnecting() {
        if conflict == nil { status = .connecting }
    }

    // MARK: Live bericht van de database

    func streamRequest() async throws -> URLRequest {
        let token = try await tokens.idToken(false)
        return try database.streamRequest(uid: tokens.uid, idToken: token)
    }

    func receive(_ message: FirebaseStreamMessage) async -> StreamAction {
        switch message {
        case .keepAlive, .unknown:
            return .keepListening
        case .authRevoked:
            return .reconnect
        case .cancel:
            let text = FirebaseDatabaseError.permissionDenied.localizedDescription
            status = .failed(text)
            return .stop(text)
        case .partialChange:
            knownETag = nil
            return action(for: await syncNow())
        case .snapshot(let snapshot):
            // Het echo van onze eigen schrijfactie.
            if let snapshot, isEcho(snapshot) { return .keepListening }
            knownETag = nil
            if isBusy {
                rerunRequested = true
                return .keepListening
            }
            guard isReady else { return .keepListening }
            if let snapshot, !snapshot.isSupported {
                status = .failed(FirebaseDatabaseError.unsupportedSchema(snapshot.schema).localizedDescription)
                return .keepListening
            }
            adoptOwnWrite(snapshot)
            let decision = decide(local.read(), snapshot)
            switch decision {
            case .noop:
                settleNoop(remote: snapshot)
                return .keepListening
            case .pullRemote:
                guard let snapshot else { return .keepListening }
                do {
                    try pull(snapshot)
                } catch {
                    status = .failed(describe(error))
                }
                return .keepListening
            case .pushLocal, .conflict:
                return action(for: await syncNow())
            }
        }
    }

    private func action(for outcome: SyncOutcome) -> StreamAction {
        switch outcome {
        case .done, .conflict: return .keepListening
        case .offline, .failed: return .reconnect
        case .authExpired: return .authExpired
        }
    }

    private func isEcho(_ snapshot: RemoteSnapshot) -> Bool {
        guard let lastPushedStamp else { return false }
        return snapshot.device == device && CloudSync.localMatches(lastPushedStamp, snapshot.modifiedAt)
    }

    // MARK: Intern: volgorde

    private func serialized(_ operation: () async -> SyncOutcome) async -> SyncOutcome {
        if isBusy {
            rerunRequested = true
            return .done
        }
        isBusy = true
        var outcome = await operation()
        while rerunRequested {
            rerunRequested = false
            guard outcome == .done else { break }
            outcome = await fullCycle()
        }
        rerunRequested = false
        isBusy = false
        return outcome
    }

    // MARK: Intern: een hele ronde

    private func fullCycle() async -> SyncOutcome {
        status = .busy
        for _ in 0..<4 {
            do {
                let uid = tokens.uid
                let remote = try await authorized { token in
                    try await self.database.fetchFinance(uid: uid, idToken: token)
                }
                if let remote {
                    guard remote.isSupported else { throw FirebaseDatabaseError.unsupportedSchema(remote.schema) }
                    _ = try remote.decodeFinance()
                }
                adoptOwnWrite(remote)
                let localData = local.read()
                let decision = decide(localData, remote)
                switch decision {
                case .noop:
                    settleNoop(remote: remote)
                    return .done
                case .pullRemote:
                    if let remote { try pull(remote) } else { settle(nil) }
                    return .done
                case .pushLocal:
                    if remote == nil, state.lastSyncedStamp != nil {
                        // De gegevens in de cloud zijn weg terwijl wij ze eerder zagen.
                        try await confirmAccountStillExists()
                    }
                    let etag = remote?.etag ?? (remote == nil ? FirebaseDatabaseClient.nullETag : nil)
                    if try await push(ifMatch: etag) { return .done }
                    // 412: de cloud veranderde net. Opnieuw ophalen en beslissen.
                    continue
                case .conflict(let localModified, let remoteModified):
                    guard let remote else { return .done }
                    knownETag = remote.etag
                    conflict = SyncConflict(local: localData, remote: remote,
                                            localModified: localModified, remoteModified: remoteModified)
                    isReady = true
                    status = .conflict
                    return .conflict
                }
            } catch {
                return handle(error)
            }
        }
        let text = "De cloud veranderde steeds tijdens het synchroniseren. Probeer het zo opnieuw."
        status = .failed(text)
        return .failed(text)
    }

    private func fastPushOrCycle() async -> SyncOutcome {
        guard isReady, conflict == nil else { return .done }
        guard hasUnsyncedChanges else {
            // Er bleek niets te schrijven. Vergeet de wachtende wijziging, anders blijft de planning terugkomen.
            debouncer.discardPending()
            return .done
        }
        // Is een eerdere schrijfactie onzeker (antwoord kwijt)? Lees dan eerst wat er in de cloud staat.
        guard let etag = knownETag, state.inFlightStamp == nil else { return await fullCycle() }
        status = .busy
        do {
            if try await push(ifMatch: etag) { return .done }
            knownETag = nil
            return await fullCycle()
        } catch {
            return handle(error)
        }
    }

    // MARK: Intern: de acties

    /// Schrijft de lokale gegevens. `false` betekent: 412, de cloud is intussen veranderd.
    private func push(ifMatch etag: String?) async throws -> Bool {
        var data = local.read()
        if data.modifiedAt == nil {
            // Gegevens van vóór de synchronisatie hebben geen wijzigingstijd. Geef ze er nu een.
            local.stamp(clock())
            data = local.read()
        }
        let stamp = data.modifiedAt ?? clock()
        let counterAtStart = changeCounter
        debouncer.beginPush(at: clock())
        lastPushedStamp = stamp
        // Onthoud vooraf wat we gaan schrijven: gaat het antwoord verloren, dan herkennen we de versie later als de onze.
        state.inFlightStamp = stamp
        stateStore.save(state)

        let uid = tokens.uid
        let result: FirebaseWriteResult
        do {
            result = try await authorized { token in
                try await self.database.writeFinance(data, uid: uid, idToken: token, device: self.device, ifMatch: etag)
            }
        } catch {
            debouncer.restorePending(at: clock())
            throw error
        }

        switch result {
        case .preconditionFailed:
            // Niet toegepast: er is geen onzekere schrijfactie meer.
            state.inFlightStamp = nil
            stateStore.save(state)
            debouncer.restorePending(at: clock())
            knownETag = nil
            return false
        case .written(let receipt):
            lastPayloadBytes = receipt.bytes
            sizeWarning = receipt.sizeWarning
            state.lastSyncedStamp = receipt.snapshot.modifiedAt
            state.inFlightStamp = nil
            state.syncedRemoteDigest = (try? receipt.snapshot.decodeFinance()).flatMap(CloudSync.contentDigest)
            state.syncedLocalDigest = CloudSync.contentDigest(data)
            // Is er tijdens het schrijven nog iets gewijzigd? Dan blijft dat openstaan.
            state.dirty = (changeCounter != counterAtStart)
            knownETag = receipt.etag
            finishSync()
            return true
        }
    }

    private func pull(_ remote: RemoteSnapshot) throws {
        let data = try remote.decodeFinance()
        local.apply(data)
        settle(remote)
    }

    /// Gelijk, of allebei leeg. Neem de tijdstempel van de cloud over als die afwijkt, zodat beide kanten
    /// dezelfde versie delen.
    private func settleNoop(remote: RemoteSnapshot?) {
        if let remote,
           !CloudSync.localMatches(local.read().modifiedAt, remote.modifiedAt),
           let data = try? remote.decodeFinance() {
            local.apply(data)
        }
        settle(remote)
    }

    private func settle(_ remote: RemoteSnapshot?) {
        // Overnemen en "gelijk" gebeuren zonder wachtmoment tussen lezen en doen: er is niets openstaand.
        state.dirty = false
        state.inFlightStamp = nil
        if let remote {
            state.lastSyncedStamp = remote.modifiedAt
            state.syncedRemoteDigest = (try? remote.decodeFinance()).flatMap(CloudSync.contentDigest)
            knownETag = remote.etag
        } else {
            state.syncedRemoteDigest = nil
            knownETag = FirebaseDatabaseClient.nullETag
        }
        state.syncedLocalDigest = CloudSync.contentDigest(local.read())
        finishSync()
    }

    /// Beslist wat er moet gebeuren, met de vingerafdrukken van de laatste synchronisatie erbij.
    private func decide(_ localData: FinanceData, _ remote: RemoteSnapshot?) -> SyncDecision {
        CloudSync.reconcile(local: localData, localLastSyncedAt: state.lastSyncedStamp, remote: remote,
                            localHasUnsyncedChanges: state.dirty,
                            syncedLocalDigest: state.syncedLocalDigest, syncedRemoteDigest: state.syncedRemoteDigest)
    }

    /// Staat in de cloud de versie die wij zelf schreven, maar waarvan we het antwoord nooit kregen (time-out, app naar
    /// de achtergrond)? Dan is dat geen wijziging van een ander apparaat: het is onze eigen versie, en wat we daarna
    /// nog wijzigden is gewoon nog niet verstuurd.
    private func adoptOwnWrite(_ remote: RemoteSnapshot?) {
        guard let remote, let inFlight = state.inFlightStamp,
              remote.device == device, CloudSync.sameStamp(remote.modifiedAt, inFlight) else { return }
        let current = local.read()
        state.lastSyncedStamp = remote.modifiedAt
        state.inFlightStamp = nil
        if let written = try? remote.decodeFinance() {
            state.syncedRemoteDigest = CloudSync.contentDigest(written)
            if CloudSync.contentEqual(current, written) {
                // Sindsdien is niets meer gewijzigd: er staat al precies wat we willen.
                state.dirty = false
                state.syncedLocalDigest = CloudSync.contentDigest(current)
            } else {
                state.syncedLocalDigest = nil
            }
        } else {
            state.syncedRemoteDigest = nil
            state.syncedLocalDigest = nil
        }
        knownETag = remote.etag
        stateStore.save(state)
    }

    /// Een document dat in de cloud verdwenen is, zetten we terug uit de lokale gegevens. Maar als een ander apparaat
    /// het account net heeft verwijderd, mag er niets terug: het ID-token blijft nog tot een uur geldig, dus de database
    /// zou de gegevens gewoon aannemen. Wacht daarom even (het verwijderen van het account volgt direct op het wissen
    /// van de gegevens) en vernieuw dan het token: voor een verwijderd account lukt dat niet meer.
    private func confirmAccountStillExists() async throws {
        if restoreGrace > 0 {
            try await Task.sleep(nanoseconds: UInt64(restoreGrace * 1_000_000_000))
        }
        _ = try await tokens.idToken(true)
    }

    private func finishSync() {
        let now = clock()
        state.lastSyncedAt = now
        stateStore.save(state)
        conflict = nil
        isReady = true
        status = .synced(at: now)
    }

    private func performResolve(_ choice: ConflictChoice, _ pending: SyncConflict) async -> SyncOutcome {
        switch choice {
        case .takeRemote:
            // Eerst de lokale versie veiligstellen, dan pas overschrijven.
            if let backups, backups.save(local.read(), side: .local, at: clock()) == nil {
                return failBackup()
            }
            do {
                try pull(pending.remote)
                return .done
            } catch {
                return handle(error)
            }
        case .keepLocal:
            if let backups {
                guard let remoteData = try? pending.remote.decodeFinance(),
                      backups.save(remoteData, side: .cloud, at: clock()) != nil else { return failBackup() }
            }
            var etag = pending.remote.etag
            let uid = tokens.uid
            for _ in 0..<3 {
                do {
                    if try await push(ifMatch: etag) { return .done }
                    // De cloud veranderde intussen nog een keer: bewaar ook die versie en probeer opnieuw.
                    let latest = try await authorized { token in
                        try await self.database.fetchFinance(uid: uid, idToken: token)
                    }
                    guard let latest else {
                        etag = FirebaseDatabaseClient.nullETag
                        continue
                    }
                    if let backups, !CloudSync.sameStamp(latest.modifiedAt, pending.remote.modifiedAt),
                       let data = try? latest.decodeFinance() {
                        backups.save(data, side: .cloud, at: clock())
                    }
                    etag = latest.etag
                } catch {
                    return handle(error)
                }
            }
            let text = "De cloud veranderde steeds tijdens het opslaan. Probeer het zo opnieuw."
            status = .failed(text)
            return .failed(text)
        }
    }

    private func failBackup() -> SyncOutcome {
        let text = "Een back-up van de andere versie maken is mislukt, dus er is niets overschreven. Controleer of er ruimte is op je apparaat."
        status = .failed(text)
        return .failed(text)
    }

    // MARK: Intern: token en fouten

    /// Voert een verzoek uit met het ID-token. Weigert de database het token, dan wordt het eenmalig vernieuwd.
    private func authorized<T>(_ call: (String) async throws -> T) async throws -> T {
        let token = try await tokens.idToken(false)
        do {
            return try await call(token)
        } catch let error as FirebaseDatabaseError where error == .unauthorized {
            let fresh = try await tokens.idToken(true)
            return try await call(fresh)
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func handle(_ error: Error) -> SyncOutcome {
        if QuoteHTTP.isCancellation(error) {
            // Onderbroken (bijvoorbeeld omdat het scherm sloot): geen fout, wel een nette status.
            status = isReady ? .synced(at: state.lastSyncedAt ?? clock()) : .connecting
            return .failed("")
        }
        if let auth = error as? FirebaseAuthError {
            switch auth {
            case .network:
                status = .offline
                return .offline
            case .sessionExpired, .userDisabled, .notSignedIn:
                status = .failed(describe(error))
                return .authExpired
            default:
                break
            }
        }
        if let database = error as? FirebaseDatabaseError, database == .network {
            status = .offline
            return .offline
        }
        let text = describe(error)
        status = .failed(text)
        return .failed(text)
    }
}
