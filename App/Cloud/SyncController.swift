import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

// De synchronisatie in de app: verbindt de regels uit Core (`CloudSyncEngine`) met de AppStore, de klok en het netwerk.
//
// - Na het starten: vergelijken met de cloud en doen wat nodig is (uploaden, downloaden of een conflict melden).
// - Daarna: elke lokale wijziging wordt na 1,5 seconde (hoogstens elke 5 seconden) weggeschreven.
// - Een open verbinding (Server-Sent Events) meldt wijzigingen van je andere apparaten meteen.
// - Valt de verbinding weg, dan wordt opnieuw verbonden na 1, 2, 4, ... hoogstens 60 seconden, en daarna ingehaald.
// - Zonder internet pauzeert alles; de app blijft gewoon op het lokale bestand werken.

/// Een back-up van de versie die bij een conflict niet werd gekozen.
struct ConflictBackupItem: Identifiable, Equatable {
    var url: URL
    var side: ConflictBackupStore.Side
    var date: Date
    var id: URL { url }

    var title: String {
        (side == .local ? "Versie van dit apparaat" : "Cloud-versie") + " van " + Fmt.dateTime(date)
    }
}

/// Alle wachttijden van de synchronisatie op één plek. De app gebruikt de standaardwaarden; tests maken ze kort,
/// zodat ze niet seconden op de klok hoeven te wachten.
struct SyncTiming {
    /// Wanneer na een wijziging geschreven wordt: rust, minimale tussentijd en uiterste wachttijd.
    var debouncer = SyncDebouncer()
    /// Wachttijden bij opnieuw verbinden.
    var backoff = ReconnectBackoff()
    /// Wachttijd voor de volgende poging nadat het wegschrijven mislukte.
    var retryAfterFailure: TimeInterval = 20
    /// Pauze nadat de database het meekijken weigerde.
    var pauseAfterStop: TimeInterval = 60
    /// Minimale pauze voor een nieuw schrijfmoment vlak na een schrijfactie, zodat herplannen niet in een lus eindigt.
    var rescheduleDelay: TimeInterval = 0.5
    /// Wachttijd voordat een verdwenen document wordt teruggezet (zie `CloudSyncEngine`).
    var restoreGrace: TimeInterval = 3
    /// Hoe vaak een wachtende lus kijkt of hij eerder wakker moet worden.
    var pollInterval: TimeInterval = 0.25

    init() {}
}

@MainActor
@Observable
final class SyncController {
    // MARK: Wat het scherm laat zien

    private(set) var status: SyncStatus = .connecting
    private(set) var lastSyncedAt: Date?
    private(set) var conflict: SyncConflict?
    private(set) var isOnline = true
    /// Het kiezen bij een conflict is bezig.
    private(set) var isResolving = false
    /// Waarschuwing als de gegevens groot worden.
    private(set) var sizeNote: String?
    /// Lokale gegevens op dit apparaat die mee kunnen naar het account (wacht op een antwoord van de gebruiker).
    private(set) var importOffer: LocalDataCandidate?
    /// De gebruiker koos "Later" bij het conflict: de melding blijft weg tot het conflict opnieuw optreedt.
    var conflictPromptDeferred = false

    /// Wat het scherm als status toont: een openstaand conflict gaat voor.
    var displayStatus: SyncStatus {
        conflict != nil ? .conflict : status
    }

    var isBusy: Bool {
        if case .busy = displayStatus { return true }
        return false
    }

    /// Zijn er wijzigingen die de cloud nog niet kent?
    var hasUnsyncedChanges: Bool {
        engine?.hasUnsyncedChanges ?? false
    }

    let user: CloudUser

    // MARK: Intern

    private enum ListenEnd {
        case dropped(offline: Bool)
        case authExpired
        case stopped(String)
    }

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let account: CloudAccount
    @ObservationIgnored private let engine: CloudSyncEngine?
    @ObservationIgnored private let streamer: any EventStreaming
    @ObservationIgnored private let monitor: NetworkMonitor
    @ObservationIgnored private let timing: SyncTiming
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<ListenEnd, Never>?
    @ObservationIgnored private var wakeRequested = false
    @ObservationIgnored private var restartRequested = false
    @ObservationIgnored private var wasInBackground = false
    @ObservationIgnored private var isRunning = false

    static func importFlagKey(uid: String) -> String {
        "mybuddy.cloud.importHandled.\(uid)"
    }

    /// - Parameters:
    ///   - directory: de map met de gegevensbestanden; hier komen ook de synchronisatiestaat en de back-ups.
    ///   - streamer: de verbinding voor live berichten (tests geven een nagebootste versie).
    ///   - timing: de wachttijden (tests geven korte).
    init(store: AppStore,
         account: CloudAccount,
         user: CloudUser,
         directory: URL,
         streamer: any EventStreaming = URLSessionEventStream(),
         monitor: NetworkMonitor? = nil,
         timing: SyncTiming = SyncTiming(),
         defaults: UserDefaults = .standard) {
        self.store = store
        self.account = account
        self.user = user
        self.directory = directory
        self.streamer = streamer
        self.timing = timing
        // Niet als standaardwaarde van de parameter: de klasse draait op de hoofdthread, een standaardwaarde niet.
        self.monitor = monitor ?? NetworkMonitor()
        self.defaults = defaults

        if let database = account.database {
            let name = CloudAccount.safeFileName(user.uid)
            let tokens = CloudTokenSource(uid: user.uid) { [weak account] forceRefresh in
                guard let account else { throw FirebaseAuthError.notSignedIn }
                return try await account.idToken(forceRefresh: forceRefresh)
            }
            let local = SyncLocalAccess(
                read: { [store] in store.data },
                apply: { [store] incoming in store.applyRemote(incoming) },
                stamp: { [store] date in store.mutate { $0.modifiedAt = date } })
            engine = CloudSyncEngine(tokens: tokens,
                                     database: database,
                                     local: local,
                                     stateStore: FileSyncStateStore.standard(directory: directory, uid: name),
                                     backups: ConflictBackupStore(directory: directory, uid: name),
                                     device: SyncController.deviceLabel(defaults: defaults),
                                     debouncer: timing.debouncer,
                                     restoreGrace: timing.restoreGrace)
        } else {
            engine = nil
        }
        engine?.onChange = { [weak self] in self?.refresh() }
        self.monitor.onReconnect = { [weak self] in self?.networkCameBack() }
        if engine == nil {
            status = .failed("Het databaseadres in FirebaseConfig.swift is ongeldig.")
        }
        refresh()
    }

    // MARK: Starten en stoppen

    /// Houdt de synchronisatie gaande tot de taak wordt geannuleerd (bijvoorbeeld als het scherm sluit).
    func run() async {
        guard let engine, !isRunning else { return }
        isRunning = true
        monitor.start()
        attachStore()
        defer {
            detachStore()
            monitor.stop()
            flushTask?.cancel()
            flushTask = nil
            streamTask = nil
            isRunning = false
        }

        await resolveImportOffer()

        var backoff = timing.backoff
        while !Task.isCancelled {
            engine.markConnecting()
            refresh()
            let outcome = await engine.syncNow()
            refresh()
            if Task.isCancelled { return }

            switch outcome {
            case .authExpired:
                account.sessionExpired()
                return
            case .offline:
                engine.connectionLost(offline: true)
                await pause(backoff.nextDelay())
                continue
            case .failed:
                await pause(backoff.nextDelay())
                continue
            case .done, .conflict:
                break
            }

            scheduleFlush()
            let started = Date()
            let end = await listen()
            if Task.isCancelled { return }
            refresh()

            if restartRequested {
                restartRequested = false
                backoff.reset()
                continue
            }
            switch end {
            case .authExpired:
                account.sessionExpired()
                return
            case .stopped:
                await pause(timing.pauseAfterStop)
            case .dropped(let offline):
                if Date().timeIntervalSince(started) > 30 { backoff.reset() }
                engine.connectionLost(offline: offline)
                await pause(backoff.nextDelay())
            }
        }
    }

    /// De app is weer actief. Was hij op de achtergrond, dan kan de verbinding ongemerkt zijn weggevallen:
    /// verbind opnieuw en haal in wat er gemist is.
    func appBecameActive() {
        guard isRunning, wasInBackground else { return }
        wasInBackground = false
        wakeRequested = true
        if let streamTask {
            restartRequested = true
            streamTask.cancel()
        }
    }

    /// De app gaat naar de achtergrond: schrijf wat nog wacht meteen weg.
    func appMovedToBackground() {
        guard isRunning else { return }
        wasInBackground = true
        flushTask?.cancel()
        flushTask = Task { [weak self] in await self?.flush() }
    }

    // MARK: Acties van de gebruiker

    /// "Nu synchroniseren".
    func syncNow() async {
        guard let engine else { return }
        wakeRequested = true
        let outcome = await engine.syncNow()
        refresh()
        if outcome == .authExpired {
            account.sessionExpired()
        } else {
            scheduleFlush()
        }
    }

    /// Kiest bij een conflict welke versie blijft. De andere versie wordt eerst als back-up bewaard.
    func resolve(_ choice: ConflictChoice) async {
        guard let engine else { return }
        isResolving = true
        defer { isResolving = false }
        let outcome = await engine.resolve(choice)
        refresh()
        if outcome == .authExpired {
            account.sessionExpired()
        } else if outcome != .done {
            // Mislukt (bijvoorbeeld geen internet): de melding niet meteen opnieuw tonen. In Instellingen kan het nog.
            conflictPromptDeferred = true
        }
    }

    /// Zoals `resolve`, maar zet meteen de markering "bezig", zodat de melding niet terugkomt terwijl het loopt.
    func startResolving(_ choice: ConflictChoice) {
        guard !isResolving else { return }
        isResolving = true
        Task { await resolve(choice) }
    }

    func deferConflictPrompt() {
        conflictPromptDeferred = true
    }

    /// Antwoord op "Je hebt lokale gegevens op dit apparaat. Uploaden naar je account?"
    func answerImportOffer(accept: Bool) {
        guard let offer = importOffer else { return }
        defaults.set(true, forKey: Self.importFlagKey(uid: user.uid))
        if accept {
            let month = store.now
            store.mutate { data in
                data = offer.data
                data.materialize(upTo: month)
            }
        }
        importOffer = nil
    }

    // MARK: Back-ups van conflicten

    /// De bewaarde versies die bij een conflict niet werden gekozen, nieuwste eerst.
    func conflictBackups() -> [ConflictBackupItem] {
        let backups = ConflictBackupStore(directory: directory, uid: CloudAccount.safeFileName(user.uid))
        var items: [ConflictBackupItem] = []
        for side in [ConflictBackupStore.Side.local, ConflictBackupStore.Side.cloud] {
            for url in backups.backups(side: side) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let date = (attributes?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
                items.append(ConflictBackupItem(url: url, side: side, date: date))
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    /// Zet een back-up terug als de huidige gegevens. De gegevens die je nu hebt, worden eerst zelf een back-up.
    /// Daarna gaat de teruggezette versie ook naar de cloud en je andere apparaten.
    @discardableResult
    func restoreBackup(_ item: ConflictBackupItem) -> Bool {
        guard let raw = try? Data(contentsOf: item.url),
              let restored = try? FinanceStorage.makeDecoder().decode(FinanceData.self, from: raw) else { return false }
        let backups = ConflictBackupStore(directory: directory, uid: CloudAccount.safeFileName(user.uid))
        if CloudSync.hasContent(store.data), backups.save(store.data, side: .local, at: Date()) == nil {
            return false
        }
        let month = store.now
        store.mutate { data in
            data = restored
            data.materialize(upTo: month)
        }
        return true
    }

    // MARK: Lokale gegevens meenemen

    /// Bij de eerste keer op dit apparaat: staan er lokale gegevens klaar, vraag dan of ze mee mogen.
    private func resolveImportOffer() async {
        let flag = Self.importFlagKey(uid: user.uid)
        if defaults.bool(forKey: flag) { return }
        // Al eens gesynchroniseerd of al gegevens in dit account? Dan valt er niets mee te nemen.
        if engine?.state.lastSyncedStamp != nil || CloudSync.hasContent(store.data) || store.data.modifiedAt != nil {
            defaults.set(true, forKey: flag)
            return
        }
        guard let best = LocalDataFinder.find(in: directory).first else {
            defaults.set(true, forKey: flag)
            return
        }
        importOffer = best
        while importOffer != nil && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(max(0.01, timing.pollInterval) * 1_000_000_000))
        }
    }

    // MARK: Lokale wijzigingen

    private func attachStore() {
        store.onDataChanged = { [weak self] _ in self?.storeDidChange() }
    }

    private func detachStore() {
        store.onDataChanged = nil
    }

    private func storeDidChange() {
        engine?.localDidChange()
        scheduleFlush()
    }

    /// Plant het wegschrijven na de rustperiode. `minimumDelay` voorkomt dat een herplanning in een razende lus eindigt.
    private func scheduleFlush(minimumDelay: TimeInterval = 0) {
        guard let engine, let wanted = engine.secondsUntilPush() else { return }
        let delay = max(wanted, minimumDelay)
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        guard let engine else { return }
        let outcome = await engine.pushIfNeeded()
        refresh()
        switch outcome {
        case .authExpired:
            account.sessionExpired()
        case .done, .conflict:
            // Is er tijdens het schrijven nog iets gewijzigd? Dan volgt die wijziging na een korte pauze.
            scheduleFlush(minimumDelay: timing.rescheduleDelay)
        case .offline, .failed:
            // Later opnieuw proberen. Komt de verbinding terug, dan haalt de hoofdlus het ook in.
            let retryDelay = timing.retryAfterFailure
            flushTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
    }

    // MARK: Live verbinding

    private func listen() async -> ListenEnd {
        let task = Task { await self.consumeStream() }
        streamTask = task
        let end = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        streamTask = nil
        return end
    }

    private func consumeStream() async -> ListenEnd {
        guard let engine else { return .dropped(offline: false) }
        let request: URLRequest
        do {
            request = try await engine.streamRequest()
        } catch {
            return classify(error)
        }

        var parser = SSEParser()
        do {
            for try await chunk in streamer.chunks(for: request) {
                for event in parser.feed(chunk) {
                    let action = await engine.receive(FirebaseStreamMessage.interpret(event))
                    refresh()
                    scheduleFlush()
                    switch action {
                    case .keepListening: continue
                    case .reconnect: return .dropped(offline: false)
                    case .authExpired: return .authExpired
                    case .stop(let text): return .stopped(text)
                    }
                }
            }
            return .dropped(offline: false)
        } catch {
            if let stream = error as? EventStreamError, case .badStatus(let code) = stream, code == 401 || code == 403 {
                // De database weigerde het token: vraag een nieuw en probeer opnieuw.
                _ = try? await account.idToken(forceRefresh: true)
            }
            return classify(error)
        }
    }

    private func classify(_ error: Error) -> ListenEnd {
        if let auth = error as? FirebaseAuthError {
            switch auth {
            case .sessionExpired, .userDisabled, .notSignedIn: return .authExpired
            case .network: return .dropped(offline: true)
            default: break
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                return .dropped(offline: true)
            default:
                break
            }
        }
        return .dropped(offline: false)
    }

    // MARK: Wachten

    /// Wacht hoogstens `seconds`, maar stopt eerder als er internet terugkomt of de gebruiker om synchroniseren vraagt.
    private func pause(_ seconds: TimeInterval) async {
        var remaining = seconds
        let step = max(0.01, timing.pollInterval)
        while remaining > 0 && !Task.isCancelled && !wakeRequested {
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            remaining -= step
        }
        wakeRequested = false
    }

    private func networkCameBack() {
        isOnline = true
        wakeRequested = true
    }

    // MARK: Status doorgeven

    private func refresh() {
        isOnline = monitor.isOnline
        guard let engine else { return }
        status = engine.status
        conflict = engine.conflict
        lastSyncedAt = engine.lastSyncedAt
        if conflict == nil { conflictPromptDeferred = false }
        if engine.sizeWarning {
            let megabytes = Fmt.input(Double(engine.lastPayloadBytes) / 1_000_000, maxDigits: 1)
            sizeNote = "Je gegevens zijn groot geworden (\(megabytes) MB). De cloud neemt tot 7,5 MB aan."
        } else {
            sizeNote = nil
        }
    }

    // MARK: Apparaatnaam

    /// "iPhone (a3f2)": de naam van het apparaat plus een kort nummer, zodat je eigen schrijfacties herkenbaar zijn.
    static func deviceLabel(defaults: UserDefaults) -> String {
        let key = "mybuddy.cloud.installID"
        var identifier = defaults.string(forKey: key) ?? ""
        if identifier.isEmpty {
            identifier = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased()
            defaults.set(identifier, forKey: key)
        }
        return "\(String(deviceName().prefix(40))) (\(identifier))"
    }

    private static func deviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Apparaat"
        #endif
    }
}

// MARK: - Hulp voor andere schermen

extension AppStore {
    /// Geeft de huidige gegevens een nieuwe wijzigingstijd en meldt ze aan de synchronisatie. Nodig na acties die
    /// alles in één keer vervangen (alles wissen, voorbeelddata, een back-up terugzetten), want die tellen
    /// anders niet als wijziging.
    func markChangedForSync() {
        mutate { $0.modifiedAt = Date() }
    }
}
